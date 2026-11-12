module machine

import loader

const signature_addr = u32(0x10_0000)
const pass_magic = u32(0x1234_5678)
const load_addr = u32(0x4000)

// words packs big-endian 16-bit words into bytes.
fn words(list []u16) []u8 {
	mut bytes := []u8{cap: list.len * 2}
	for w in list {
		bytes << u8(w >> 8)
		bytes << u8(w)
	}
	return bytes
}

// risc encodes one GPU/DSP instruction word.
fn risc(opcode u16, src u16, dst u16) u16 {
	return (opcode << 10) | ((src & 31) << 5) | (dst & 31)
}

// boot direct-loads a raw program at `load_addr`.
fn boot(program []u8) &Machine {
	plan := loader.plan(program, loader.Options{
		format:    .raw_binary
		load_addr: load_addr
	}) or { panic(err) }
	mut m := new(Config{})
	m.load_direct(plan)
	return m
}

// run_until_signature advances until the program publishes a result word.
fn run_until_signature(mut m Machine, max_frames int) u32 {
	for _ in 0 .. max_frames {
		m.run_frame()
		if m.peek32(signature_addr) != 0 {
			break
		}
	}
	return m.peek32(signature_addr)
}

fn test_direct_boot_runs_68000_program_to_pass() {
	mut m := boot(words([
		u16(0x23fc),
		0x1234,
		0x5678,
		0x0010,
		0x0000, // move.l #$12345678,$100000
		0x60fe, // bra.s *
	]))
	assert m.cpu.pc == load_addr
	assert m.peek32(signature_addr) == 0, 'signature must start cleared'
	assert run_until_signature(mut m, 2) == pass_magic
}

fn test_gpu_mailbox_program_executes_add() {
	gpu_program := [
		risc(38, 0, 1),
		0x0008,
		0x0010, // movei #$100008,r1
		risc(35, 5, 2), // moveq #5,r2
		risc(35, 7, 3), // moveq #7,r3
		risc(0, 2, 3), // add r2,r3
		risc(47, 1, 3), // store r3,(r1)
		risc(38, 0, 4),
		0x2114,
		0x00f0, // movei #G_CTRL,r4
		risc(35, 0, 5), // moveq #0,r5
		risc(47, 4, 5), // store r5,(r4): stop
		risc(57, 0, 0), // nop
		risc(57, 0, 0), // nop
	]
	mut code := [
		u16(0x41fa),
		0x0038, // lea gpu_program(pc),a0
		0x43f9,
		0x00f0,
		0x3000, // lea $f03000,a1
		0x7000 | u16(gpu_program.len - 1), // moveq #n-1,d0
		0x32d8, // move.w (a0)+,(a1)+
		0x51c8,
		0xfffc, // dbra d0,copy
		0x23fc,
		0x00f0,
		0x3000,
		0x00f0,
		0x2110, // move.l #$f03000,G_PC
		0x23fc,
		0x0000,
		0x0001,
		0x00f0,
		0x2114, // move.l #1,G_CTRL
		0x4ab9,
		0x0010,
		0x0008, // tst.l $100008
		0x67f8, // beq.s wait
		0x23fc,
		0x1234,
		0x5678,
		0x0010,
		0x0000, // move.l #$12345678,$100000
		0x60fe, // bra.s *
	]
	// The LEA displacement is relative to its extension word at offset 2.
	assert code.len * 2 == 2 + 0x38, 'the GPU program must start where the LEA points'
	code << gpu_program
	mut m := boot(words(code))
	assert run_until_signature(mut m, 4) == pass_magic
	assert m.peek32(signature_addr + 8) == 12, 'the GPU must have executed the ADD'
	assert !m.gpu.running
	assert m.gpu.instructions == 8, 'exactly the uploaded program ran'
}

fn test_stale_signature_is_cleared_by_power_on() {
	mut m := boot(words([u16(0x60fe)]))
	m.ram[signature_addr] = 0x12
	m.power_on()
	assert m.peek32(signature_addr) == 0
}

fn test_unmapped_memory_reads_as_ones_and_ignores_writes() {
	mut m := boot(words([u16(0x60fe)]))
	m.write16(0x50_0000, 0x1234)
	assert m.read16(0x50_0000) == 0xffff
	assert m.read8(0x90_0000) == 0xff, 'no cartridge installed'
	m.write8(0x20_0010, 0x5a)
	assert m.read8(0x10) == 0x5a, 'RAM mirrors once above 2 MiB'
}

fn test_word_writes_reach_long_registers() {
	mut m := boot(words([u16(0x60fe)]))
	m.write16(0xf0_2110, 0x00f0)
	m.write16(0xf0_2112, 0x3456)
	assert m.gpu.pc == 0x00f0_3456
	m.write32(0xf0_3010, 0xdead_beef)
	assert m.read16(0xf0_3012) == 0xbeef
	assert m.read8(0xf0_b010) == 0xde, 'GPU RAM repeats in the +0x8000 window'
}

fn test_controller_matrix_and_region_bit() {
	mut m := boot(words([u16(0x60fe)]))
	m.set_button(0, .up, true)
	m.set_button(0, .b, true)
	m.write16(0xf1_4000, 0x810e) // row 0 of port 0
	assert m.read16(0xf1_4000) & 0x0f00 == 0x0e00
	assert m.read16(0xf1_4002) & 0x0013 == 0x0013, 'B is not on row 0; NTSC bit set'
	m.write16(0xf1_4000, 0x810d) // row 1
	assert m.read16(0xf1_4000) & 0x0f00 == 0x0f00
	assert m.read16(0xf1_4002) & 0x0002 == 0, 'B reads on row 1'
}

fn test_vertical_interrupt_reaches_the_68000() {
	mut m := boot(words([u16(0x60fe)]))
	m.write16(0xf0_004e, 101) // VI
	m.write16(0xf0_00e0, 0x0001) // enable the video interrupt
	m.advance(m.tick + 200 * u64(m.tom.half_period()), false)
	assert m.tom.int_pending & 1 == 1
	assert m.cpu.irq_level == 2
	m.write16(0xf0_00e0, 0x0101) // acknowledge
	assert m.cpu.irq_level == 0
}
