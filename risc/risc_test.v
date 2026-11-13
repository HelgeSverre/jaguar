module risc

// TestBus is 64 KiB of external big-endian memory at address zero.
struct TestBus {
mut:
	mem []u8 = []u8{len: 0x10000}
}

fn (mut b TestBus) read8(addr u32) u8 {
	return b.mem[addr & 0xffff]
}

fn (mut b TestBus) read16(addr u32) u16 {
	return (u16(b.read8(addr)) << 8) | b.read8(addr + 1)
}

fn (mut b TestBus) read32(addr u32) u32 {
	return (u32(b.read16(addr)) << 16) | b.read16(addr + 2)
}

fn (mut b TestBus) write8(addr u32, val u8) {
	b.mem[addr & 0xffff] = val
}

fn (mut b TestBus) write16(addr u32, val u16) {
	b.write8(addr, u8(val >> 8))
	b.write8(addr + 1, u8(val))
}

fn (mut b TestBus) write32(addr u32, val u32) {
	b.write16(addr, u16(val >> 16))
	b.write16(addr + 2, u16(val))
}

// ins encodes one instruction word.
fn ins(op Opcode, src u32, dst u32) u16 {
	return u16((u32(op) << 10) | ((src & 31) << 5) | (dst & 31))
}

// movei encodes MOVEI with its immediate in low-word-first order.
fn movei(value u32, dst u32) []u16 {
	return [ins(.movei, 0, dst), u16(value), u16(value >> 16)]
}

// stop encodes the sequence that clears the GO bit: the usual program end.
fn stop(c &Risc) []u16 {
	mut words := movei(c.ctrl_base + reg_ctrl, 30)
	words << ins(.moveq, 0, 29)
	words << ins(.store, 30, 29)
	words << ins(.nop, 0, 0)
	words << ins(.nop, 0, 0)
	return words
}

// load_and_run places `words` at the start of local RAM and runs to the stop.
fn load_and_run(mut c Risc, mut bus TestBus, words []u16) {
	for i, w in words {
		c.write_ram8(u32(i * 2), u8(w >> 8))
		c.write_ram8(u32(i * 2 + 1), u8(w))
	}
	c.pc = c.ram_base
	c.running = true
	mut guard := 0
	for c.running && guard < 100 {
		c.run(mut bus, 1000)
		guard++
	}
	assert !c.running, 'program did not stop'
}

fn test_add_sets_carry_and_zero() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	mut program := movei(0xffff_ffff, 1)
	program << ins(.moveq, 1, 2)
	program << ins(.add, 1, 2)
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[2] == 0
	assert c.zf == 1
	assert c.cf == 1
	assert c.nf == 0
}

fn test_movei_immediate_is_low_word_first() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	mut program := [ins(.movei, 0, 5), u16(0x5678), u16(0x1234)]
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[5] == 0x1234_5678
}

fn test_taken_jump_executes_its_delay_slot() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	mut program := [
		ins(.moveq, 1, 1),
		ins(.jr, 3, 0), // always, to three words past the delay slot
		ins(.moveq, 2, 2), // delay slot: executes
		ins(.moveq, 3, 3), // skipped
		ins(.moveq, 4, 4), // skipped
		ins(.moveq, 5, 5), // jump target
	]
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[2] == 2
	assert c.regs[3] == 0
	assert c.regs[4] == 0
	assert c.regs[5] == 5
	assert c.regs[1] == 1
}

fn test_untaken_jump_falls_through() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	mut program := [
		ins(.moveq, 1, 1),
		ins(.cmpq, 1, 1), // equal: Z set
		ins(.jr, 2, 1), // NE: not taken
		ins(.moveq, 2, 2),
		ins(.moveq, 3, 3),
	]
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[2] == 2
	assert c.regs[3] == 3
}

fn test_register_banks_and_cross_bank_moves() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	mut program := [ins(.moveq, 7, 1), ins(.moveta, 1, 2)]
	program << movei(c.ctrl_base, 10)
	program << movei(flag_regpage, 11)
	program << ins(.store, 10, 11) // switch to bank 1
	program << ins(.nop, 0, 0)
	program << ins(.moveq, 9, 1)
	program << ins(.movefa, 1, 3)
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.bank == 32
	assert c.regs[1] == 7
	assert c.regs[32 + 2] == 7
	assert c.regs[32 + 1] == 9
	assert c.regs[32 + 3] == 7
}

fn test_external_and_local_memory() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	bus.write32(0x4000, 0xcafe_f00d)
	mut program := movei(0x4000, 1)
	program << ins(.load, 1, 2)
	program << ins(.loadw, 1, 3)
	program << ins(.loadb, 1, 4)
	program << movei(0x4010, 5)
	program << ins(.store, 5, 2)
	program << movei(c.ram_base + 0x800, 6)
	program << ins(.store, 6, 2)
	program << ins(.loadb, 6, 7) // internal storage is long-wide
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[2] == 0xcafe_f00d
	assert c.regs[3] == 0xcafe
	assert c.regs[4] == 0xca
	assert bus.read32(0x4010) == 0xcafe_f00d
	assert c.ram32(c.ram_base + 0x800) == 0xcafe_f00d
	assert c.regs[7] == 0x0d
}

fn test_interrupt_entry_and_mask() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	// Service routine for source 3 at vector 0x30: count in r20 of bank 0,
	// then stop.
	mut handler := [ins(.addq, 1, 20)]
	handler << stop(c)
	for i, w in handler {
		c.write_ram8(u32(0x30 + i * 2), u8(w >> 8))
		c.write_ram8(u32(0x31 + i * 2), u8(w))
	}
	// Main program at 0x100: enable source 3, then spin.
	main_program := [ins(.nop, 0, 0), ins(.jr, 0x1e, 0), ins(.nop, 0, 0)]
	for i, w in main_program {
		c.write_ram8(u32(0x100 + i * 2), u8(w >> 8))
		c.write_ram8(u32(0x101 + i * 2), u8(w))
	}
	c.regs[31] = c.ram_base + 0x1000
	c.pc = c.ram_base + 0x100
	c.write_ctrl32(reg_flags, 1 << (4 + 3))
	c.running = true
	c.run(mut bus, 50)
	assert c.regs[20] == 0
	c.raise_irq(3)
	c.run(mut bus, 50)
	assert !c.running
	assert c.regs[20] == 1
	assert c.flags_ctl & flag_imask != 0
	assert c.regs[31] == c.ram_base + 0x1000 - 4
	assert c.read_ctrl32(reg_ctrl) & (1 << 9) != 0, 'latch stays until cleared'
	// Clearing the latch and writing IMASK=0 re-arms the source.
	c.write_ctrl32(reg_flags, (1 << (4 + 3)) | (1 << (9 + 3)))
	assert c.latches == 0
	assert c.flags_ctl & flag_imask == 0
}

fn test_disabled_interrupt_request_is_lost() {
	mut c := new_dsp()
	c.raise_irq(5)
	assert c.latches == 0, 'the enable gates the request into the latch'
	c.write_ctrl32(reg_flags, 1 << 16)
	assert c.latches == 0, 'enabling later does not recover it'
	c.raise_irq(5)
	assert c.read_ctrl32(reg_ctrl) & (1 << 16) != 0
	c.write_ctrl32(reg_flags, (1 << 16) | (1 << 17))
	assert c.latches == 0
}

fn test_latched_interrupt_waits_while_masked() {
	mut c := new_gpu()
	mut bus := &TestBus{}
	c.write_ctrl32(reg_flags, 1 << (4 + 2))
	c.flags_ctl |= flag_imask
	c.raise_irq(2)
	pc := c.pc
	c.service_interrupts(mut bus)
	assert c.latches == 1 << 2
	assert c.pc == pc, 'no entry while a service routine is active'
}

fn test_divide_integer_and_fixed_point() {
	mut c := new_gpu()
	c.regs[1] = 100
	c.divide(1, 7)
	assert c.regs[1] == 14
	c.regs[1] = 3
	c.div_ctrl = 1
	c.divide(1, 2)
	assert c.regs[1] == 0x0001_8000
}

fn test_saturation_and_absolute_value() {
	assert saturate_unsigned(0xffff_fff0, 0xff) == 0
	assert saturate_unsigned(300, 0xff) == 0xff
	assert saturate_unsigned(17, 0xff) == 17
	assert saturate_signed16(0x0001_0000) == 0x7fff
	assert saturate_signed16(0xfffe_0000) == 0xffff_8000
	assert reverse_bits(0x0000_0001) == 0x8000_0000
	assert reverse_bits(0x1234_5678) == 0x1e6a_2c48
}

fn test_dsp_accumulator_is_forty_bits() {
	mut c := new_dsp()
	mut bus := &TestBus{}
	mut program := movei(0x7fff, 1)
	program << ins(.imultn, 1, 1)
	// 0x3fff0001 added 400 more times overflows 32 bits but not 40.
	program << movei(400, 2)
	program << ins(.imacn, 1, 1)
	program << ins(.subq, 1, 2)
	program << ins(.jr, 0x1d, 1) // NE: back to the IMACN
	program << ins(.nop, 0, 0)
	program << ins(.resmac, 0, 3)
	program << ins(.loadp_sat32s, 0, 3)
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.acc == i64(0x3fff_0001) * 401
	assert c.read_ctrl32(reg_machi) == u32((i64(0x3fff_0001) * 401) >> 32)
	assert c.regs[3] == 0x7fff_ffff
}

fn test_dsp_program_runs_from_its_unaligned_ram_base() {
	// The DSP's RAM base is not a multiple of its size, so indexing must be
	// relative to the base.
	mut c := new_dsp()
	mut bus := &TestBus{}
	mut program := movei(c.ram_base + 0x100, 1)
	program << ins(.store, 1, 1)
	program << ins(.load, 1, 2)
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[2] == c.ram_base + 0x100
	assert c.read_ram8(0x101) == 0xf1
}

fn test_dsp_modulo_addressing() {
	mut c := new_dsp()
	mut bus := &TestBus{}
	c.modulo = 0xffff_fff0 // 16-byte ring
	mut program := movei(0x0000_100c, 1)
	program << ins(.pack_addqmod, 8, 1)
	program << stop(c)
	load_and_run(mut c, mut bus, program)
	assert c.regs[1] == 0x0000_1004
}

fn test_normi_normalises_to_bit_23() {
	assert normalisation_integer(0) == 0
	assert normalisation_integer(0x0080_0000) == 0
	assert normalisation_integer(320) == u32(-15)
	assert normalisation_integer(1) == u32(-23)
	assert normalisation_integer(0x8000_0000) == 8
}

// The GPU moves a long outside its own memory at once and ignores the two
// low address bits; the DSP's bus is 16 bits wide, so its long is two word
// transfers and needs only an even address. Programs exist that depend on
// each.
fn test_external_longs_align_to_the_width_of_each_bus() {
	for gpu in [true, false] {
		mut c := if gpu { new_gpu() } else { new_dsp() }
		mut bus := &TestBus{}
		bus.write32(0x4000, 0x1122_3344)
		bus.write32(0x4004, 0x5566_7788)
		mut program := movei(0x4002, 1)
		program << ins(.load, 1, 2)
		program << movei(0x4013, 5)
		program << ins(.store, 5, 2)
		program << stop(c)
		load_and_run(mut c, mut bus, program)
		if gpu {
			assert c.regs[2] == 0x1122_3344
			assert bus.read32(0x4010) == 0x1122_3344
		} else {
			assert c.regs[2] == 0x3344_5566
			assert bus.read32(0x4012) == 0x3344_5566
		}
	}
}
