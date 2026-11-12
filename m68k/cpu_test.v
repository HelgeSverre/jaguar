// Hand-written MC68000 tests that need no external corpus.
module m68k

import m68k.testbus

const program_base = u32(0x1000)
const initial_ssp = u32(0x8000)
const initial_usp = u32(0x6000)

// handler_addr is where the test vector table sends exception `vector`.
fn handler_addr(vector u32) u32 {
	return 0x0001_0000 + vector * 0x10
}

fn poke32(mut bus testbus.TestBus, addr u32, value u32) {
	bus.poke16(addr, u16(value >> 16))
	bus.poke16(addr + 2, u16(value))
}

fn peek32(bus &testbus.TestBus, addr u32) u32 {
	return (u32(bus.peek16(addr)) << 16) | bus.peek16(addr + 2)
}

// install fills the vector table and places `program` at `program_base`.
fn install(mut bus testbus.TestBus, program []u16) {
	bus.clear()
	poke32(mut bus, 0, initial_ssp)
	poke32(mut bus, 4, program_base)
	for vector in u32(2) .. 256 {
		poke32(mut bus, vector * 4, handler_addr(vector))
	}
	for i, word in program {
		bus.poke16(program_base + u32(i) * 2, word)
	}
}

// boot returns a bus holding `program` and a CPU that has just been reset.
fn boot(program []u16) (&testbus.TestBus, Cpu) {
	mut bus := testbus.new()
	install(mut bus, program)
	mut cpu := Cpu{}
	cpu.reset(mut bus)
	return bus, cpu
}

// enter_user_mode drops a freshly reset CPU into user mode.
fn enter_user_mode(mut cpu Cpu) {
	cpu.usp = initial_usp
	cpu.set_sr(0)
}

fn test_reset_loads_vectors() {
	mut bus, mut cpu := boot([])
	assert cpu.a[7] == initial_ssp
	assert cpu.pc == program_base
	assert cpu.sr == 0x2700
	assert !cpu.stopped
	assert !cpu.halted

	cpu.halted = true
	cpu.stopped = true
	cpu.reset(mut bus)
	assert !cpu.halted
	assert !cpu.stopped
}

fn test_move_add_branch_program() {
	mut bus, mut cpu := boot([
		u16(0x7005), // moveq #5,d0
		0x7200, // moveq #0,d1
		0xd240, // loop: add.w d0,d1
		0x5340, // subq.w #1,d0
		0x66fa, // bne.s loop
		0x21c1, // move.l d1,$2000.w
		0x2000,
	])
	mut cycles := u32(0)
	for _ in 0 .. 18 {
		cycles += cpu.step(mut bus)
	}
	assert cpu.d[0] == 0
	assert cpu.d[1] == 15
	assert peek32(bus, 0x2000) == 15
	assert cpu.pc == program_base + 14
	// 2 moveq, 5 add + 5 subq, 4 taken and 1 untaken bne, move.l to abs.w.
	assert cycles == 2 * 4 + 10 * 4 + 4 * 10 + 8 + 16
	assert cpu.cycles == cycles
	assert !bus.long_access
}

fn test_interrupt_entry_with_supplied_vector() {
	mut bus, mut cpu := boot([u16(0x4e71)])
	cpu.set_sr(0xa000) // supervisor, trace, mask 0
	cpu.irq_level = 4
	cpu.irq_vector = 64
	cycles := cpu.step(mut bus)
	assert cycles == 44
	assert cpu.pc == handler_addr(64)
	assert cpu.sr == 0x2400 // supervisor, trace cleared, mask = level
	assert cpu.a[7] == initial_ssp - 6
	assert bus.peek16(initial_ssp - 6) == 0xa000
	assert peek32(bus, initial_ssp - 4) == program_base
}

fn test_interrupt_autovector_and_mask() {
	mut bus, mut cpu := boot([u16(0x4e71), 0x4e71])
	cpu.set_sr(0x2300)
	cpu.irq_level = 3 // not above the mask: ignored
	assert cpu.step(mut bus) == 4
	assert cpu.pc == program_base + 2
	cpu.irq_level = 5
	assert cpu.step(mut bus) == 44
	assert cpu.pc == handler_addr(24 + 5)
	assert cpu.sr == 0x2500
}

fn test_level_seven_is_edge_triggered() {
	mut bus, mut cpu := boot([u16(0x4e71), 0x4e71])
	assert cpu.sr & 0x0700 == 0x0700
	cpu.irq_level = 7
	assert cpu.step(mut bus) == 44
	assert cpu.pc == handler_addr(24 + 7)
	// Still asserted: no second interrupt without a new edge.
	bus.poke16(handler_addr(24 + 7), 0x4e71)
	assert cpu.step(mut bus) == 4
	cpu.irq_level = 0
	bus.poke16(handler_addr(24 + 7) + 2, 0x4e71)
	assert cpu.step(mut bus) == 4
	cpu.irq_level = 7
	assert cpu.step(mut bus) == 44
}

fn test_stop_waits_for_interrupt() {
	mut bus, mut cpu := boot([u16(0x4e72), 0x2000, 0x4e71])
	assert cpu.step(mut bus) == 4
	assert cpu.stopped
	assert cpu.sr == 0x2000
	assert cpu.step(mut bus) > 0
	assert cpu.stopped
	assert cpu.pc == program_base + 4
	cpu.irq_level = 2
	assert cpu.step(mut bus) == 44
	assert !cpu.stopped
	assert cpu.pc == handler_addr(24 + 2)
	// The stacked PC is the instruction after STOP.
	assert peek32(bus, initial_ssp - 4) == program_base + 4
}

fn test_privilege_violation() {
	mut bus, mut cpu := boot([u16(0x46c0)]) // move d0,sr
	enter_user_mode(mut cpu)
	cpu.d[0] = 0x2700
	assert cpu.step(mut bus) == 34
	assert cpu.pc == handler_addr(8)
	assert cpu.sr == 0x2000
	assert cpu.usp == initial_usp
	assert cpu.a[7] == initial_ssp - 6
	assert bus.peek16(initial_ssp - 6) == 0x0000
	// The stacked PC points at the offending instruction.
	assert peek32(bus, initial_ssp - 4) == program_base
}

fn writes(bus &testbus.TestBus) []testbus.BusEvent {
	return bus.events[..bus.event_count].filter(it.write)
}

fn test_long_write_order() {
	// move.l d0,-(a0) puts the low word on the bus first.
	mut bus, mut cpu := boot([u16(0x2100), 0x2080])
	cpu.d[0] = 0x1234_5678
	cpu.a[0] = 0x3004
	assert cpu.step(mut bus) == 12
	assert cpu.a[0] == 0x3000
	assert writes(bus) == [
		testbus.BusEvent{true, 2, 0x3002, 0x5678},
		testbus.BusEvent{true, 2, 0x3000, 0x1234},
	]

	// move.l d0,(a0) writes the high word first.
	bus.event_count = 0
	cpu.a[0] = 0x3008
	assert cpu.step(mut bus) == 12
	assert writes(bus) == [
		testbus.BusEvent{true, 2, 0x3008, 0x1234},
		testbus.BusEvent{true, 2, 0x300a, 0x5678},
	]
	assert !bus.long_access
}

fn test_trace_exception_follows_instruction() {
	mut bus, mut cpu := boot([u16(0x4e71), 0x4e71])
	cpu.set_sr(0xa700)
	assert cpu.step(mut bus) == 4
	assert cpu.pc == program_base + 2
	assert cpu.step(mut bus) == 34
	assert cpu.pc == handler_addr(9)
	assert cpu.sr == 0x2700
	assert bus.peek16(initial_ssp - 6) == 0xa700
	assert peek32(bus, initial_ssp - 4) == program_base + 2
}

fn test_illegal_and_emulator_lines() {
	for opcode, vector in {
		u16(0x4afc): u32(4)
		0xa123:      10
		0xf123:      11
	} {
		mut bus, mut cpu := boot([opcode])
		assert cpu.step(mut bus) == 34
		assert cpu.pc == handler_addr(vector)
		assert peek32(bus, initial_ssp - 4) == program_base
	}
}

fn test_trap_stacks_next_instruction() {
	mut bus, mut cpu := boot([u16(0x4e45)]) // trap #5
	assert cpu.step(mut bus) == 34
	assert cpu.pc == handler_addr(32 + 5)
	assert peek32(bus, initial_ssp - 4) == program_base + 2
}

fn test_reset_instruction_pulses_line_only() {
	mut bus, mut cpu := boot([u16(0x4e70)])
	cpu.d[3] = 0xdead_beef
	assert cpu.step(mut bus) == 132
	assert cpu.reset_line_pulsed
	assert cpu.pc == program_base + 2
	assert cpu.sr == 0x2700
	assert cpu.a[7] == initial_ssp
	assert cpu.d[3] == 0xdead_beef
}

fn test_address_error_frame() {
	mut bus, mut cpu := boot([u16(0x3010)]) // move.w (a0),d0
	cpu.a[0] = 0x0000_3001
	assert cpu.step(mut bus) == 58
	assert cpu.pc == handler_addr(3)
	sp := initial_ssp - 14
	assert cpu.a[7] == sp
	assert bus.peek16(sp) == 0x3015 // opcode bits, read, supervisor data
	assert peek32(bus, sp + 2) == 0x0000_3001
	assert bus.peek16(sp + 6) == 0x3010
	assert bus.peek16(sp + 8) == 0x2700
	assert peek32(bus, sp + 10) == program_base + 2
}

fn test_double_fault_halts() {
	mut bus, mut cpu := boot([u16(0x4e40)]) // trap #0
	cpu.a[7] = initial_ssp + 1
	assert cpu.step(mut bus) > 0
	assert cpu.halted
	pc := cpu.pc
	assert cpu.step(mut bus) > 0
	assert cpu.pc == pc
	cpu.reset(mut bus)
	assert !cpu.halted
}

fn test_decode_rejects_later_family_members() {
	for opcode in [
		u16(0x42c0), // move ccr,d0 (68010)
		0x4e74, // rtd (68010)
		0x4e7a, // movec (68010)
		0x0e10, // moves (68010)
		0x06c0, // callm/rtm (68020)
		0x4c00, // mull (68020)
		0x49c0, // extb.l (68020)
		0xe8c0, // bftst (68020)
		0x4808, // link.l (68020)
		0x51fc, // trapf (68020)
		0x0c3a, // cmpi #,(d16,pc) (68010)
		0x4afc, // illegal
	] {
		assert op_table[opcode] == .illegal, 'opcode ${opcode:04x}'
	}
	assert op_table[0xa000] == .line_a
	assert op_table[0xffff] == .line_f
	assert op_table[0x4e71] == .nop
}

fn test_every_opcode_executes_without_panic() {
	mut bus := testbus.new()
	for user_mode in [false, true] {
		for opcode in 0 .. 0x10000 {
			// The extension words keep displacements and absolute
			// addresses even and inside RAM.
			install(mut bus, [u16(opcode), 0x0010, 0x0020, 0x0030, 0x0040])
			mut cpu := Cpu{}
			cpu.reset(mut bus)
			for i in 0 .. 8 {
				cpu.d[i] = 0x0101_0101 * u32(i + 1)
			}
			for i in 0 .. 7 {
				cpu.a[i] = 0x0002_0000 + 0x100 * u32(i)
			}
			if user_mode {
				enter_user_mode(mut cpu)
			}
			cycles := cpu.step(mut bus)
			assert cycles > 0, 'opcode ${opcode:04x}'
			assert cycles == cpu.cycles, 'opcode ${opcode:04x}'
			assert !cpu.halted, 'opcode ${opcode:04x}'
			assert !bus.long_access, 'opcode ${opcode:04x}'
		}
	}
}

fn test_str_state() {
	_, mut cpu := boot([])
	cpu.d[2] = 0xcafe_f00d
	line := cpu.str_state()
	assert line.starts_with('PC=00001000 SR=2700 D0=00000000')
	assert line.contains('D2=cafef00d')
	assert line.ends_with('A7=00008000')
}
