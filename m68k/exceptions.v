module m68k

import hwtypes

const vector_address_error = u32(3)
const vector_illegal = u32(4)
const vector_zero_divide = u32(5)
const vector_chk = u32(6)
const vector_trapv = u32(7)
const vector_privilege = u32(8)
const vector_trace = u32(9)
const vector_line_a = u32(10)
const vector_line_f = u32(11)
const vector_autovector = u32(24)
const vector_trap = u32(32)

// Access classifies the bus cycle that raised an address error.
enum Access as u8 {
	read  // data-space read
	write // data-space write
	fetch // program-space read: instruction stream or PC-relative operand
}

// read_vector reads a 32-bit exception vector as two word accesses.
fn read_vector(mut bus hwtypes.Bus, addr u32) u32 {
	hi := u32(bus.read16(addr))
	lo := u32(bus.read16(addr + 2))
	return (hi << 16) | lo
}

// enter_supervisor switches to the supervisor stack and clears trace, as
// every exception does before stacking. It returns the previous SR.
fn (mut c Cpu) enter_supervisor() u16 {
	saved := c.sr
	c.set_sr((saved | sr_supervisor) & ~sr_trace)
	c.stopped = false
	return saved
}

// exception enters a group 1 or group 2 exception: it stacks `return_pc` and
// the status register and continues at the handler named by `vector`.
// `cycles` is the complete cost of the exception sequence.
@[direct_array_access]
fn (mut c Cpu) exception(mut bus hwtypes.Bus, vector u32, return_pc u32, cycles u32) {
	saved_sr := c.enter_supervisor()
	if c.a[7] & 1 != 0 {
		// The stacking itself would raise an address error whose own
		// stacking faults again: a double fault.
		c.halted = true
		c.cycles += cycles
		return
	}
	sp := c.a[7] - 6
	c.a[7] = sp
	bus.write16(sp + 4, u16(return_pc))
	bus.write16(sp, saved_sr)
	bus.write16(sp + 2, u16(return_pc >> 16))
	c.pc = read_vector(mut bus, vector << 2)
	c.cycles += cycles
}

// address_error enters the group 0 address error exception for an access to
// odd address `addr`. The 14-byte frame holds `return_pc`, SR, the opcode,
// the fault address and the access information word. The current
// instruction is abandoned.
@[direct_array_access]
fn (mut c Cpu) address_error(mut bus hwtypes.Bus, addr u32, access Access, return_pc u32) {
	c.aborted = true
	mut info := c.ir & 0xffe0
	info |= match access {
		.read { u16(0x11) }
		.write { u16(0x01) }
		.fetch { u16(0x12) }
	}

	if c.supervisor() {
		info |= 0x04
	}
	saved_sr := c.enter_supervisor()
	// 4 cycles for the aborted bus cycle, 54 for the exception sequence.
	c.cycles += 58
	if c.a[7] & 1 != 0 {
		c.halted = true
		return
	}
	sp := c.a[7] - 14
	c.a[7] = sp
	bus.write16(sp + 12, u16(return_pc))
	bus.write16(sp + 8, saved_sr)
	bus.write16(sp + 10, u16(return_pc >> 16))
	bus.write16(sp + 6, c.ir)
	bus.write16(sp + 4, u16(addr))
	bus.write16(sp, info)
	bus.write16(sp + 2, u16(addr >> 16))
	c.pc = read_vector(mut bus, vector_address_error << 2)
}

// illegal raises the illegal instruction, line-A or line-F exception. The
// stacked PC is the address of the offending opcode.
fn (mut c Cpu) illegal(mut bus hwtypes.Bus, vector u32) {
	c.aborted = true
	c.exception(mut bus, vector, c.pc - 2, 34)
}

// require_supervisor raises a privilege violation and returns false when the
// processor is in user mode.
fn (mut c Cpu) require_supervisor(mut bus hwtypes.Bus) bool {
	if c.supervisor() {
		return true
	}
	c.illegal(mut bus, vector_privilege)
	return false
}

// service_interrupt samples the IPL input and enters the interrupt exception
// when the level exceeds the SR mask, or on a transition to level 7 (NMI).
// It returns true when an interrupt was taken.
fn (mut c Cpu) service_interrupt(mut bus hwtypes.Bus) bool {
	level := c.irq_level & 7
	nmi_edge := level == 7 && c.ipl_seen != 7
	c.ipl_seen = level
	if level == 0 {
		return false
	}
	mask := u8((c.sr & sr_int_mask) >> 8)
	if level <= mask && !nmi_edge {
		return false
	}
	vector := if c.irq_vector != 0 { u32(c.irq_vector) } else { vector_autovector + level }
	c.exception(mut bus, vector, c.pc, 44)
	c.sr = (c.sr & ~sr_int_mask) | (u16(level) << 8)
	return true
}
