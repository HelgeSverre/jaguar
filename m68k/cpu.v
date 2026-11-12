// Motorola MC68000 interpreter.
//
// The core executes one instruction (including any exception that instruction
// raises) per `step` call and talks to the rest of the machine only through
// `hwtypes.Bus`, using byte and word accesses in the order of the real chip.
// Timing is accumulated per bus access plus the idle cycles of each
// instruction, so `cycles` advances exactly as the MC68000 clock would.
module m68k

import hwtypes

const sr_trace = u16(0x8000)
const sr_supervisor = u16(0x2000)
const sr_int_mask = u16(0x0700)
// sr_implemented masks the status register bits that exist on the MC68000.
const sr_implemented = u16(0xa71f)

// idle_quantum is the time reported by `step` while the processor is stopped
// or halted and therefore executes nothing.
const idle_quantum = u32(4)

// Cpu is the complete programmer-visible and internal state of one MC68000.
@[heap]
pub struct Cpu {
mut:
	ir            u16  // opcode of the instruction being executed
	aborted       bool // the current instruction was cut short by a group 0/1 exception
	trace_pending bool // a trace exception is due before the next instruction
	ipl_seen      u8   // interrupt level sampled by the previous step, for the level 7 edge
pub mut:
	d       [8]u32
	a       [8]u32 // a[7] is the active stack pointer
	pc      u32    // address of the next instruction to execute
	sr      u16
	usp     u32  // user stack pointer while in supervisor mode
	ssp     u32  // supervisor stack pointer while in user mode
	stopped bool // STOP executed, waiting for an interrupt
	halted  bool // double fault; only `reset` recovers
	// irq_level is the level-sensitive IPL input (0..7), driven by the machine.
	irq_level u8
	// irq_vector is the vector number supplied at interrupt acknowledge;
	// 0 requests the autovector (24 + level).
	irq_vector u8
	cycles     u64 // total MC68000 clock cycles executed
	// reset_line_pulsed is set when a RESET instruction asserts the external
	// reset line. The machine observes and clears it.
	reset_line_pulsed bool
}

// reset performs a power-on or external reset: the supervisor stack pointer
// is loaded from vector 0, the program counter from vector 1 and the status
// register becomes 0x2700. Data and address registers keep their contents.
pub fn (mut c Cpu) reset(mut bus hwtypes.Bus) {
	c.sr = sr_supervisor | sr_int_mask
	c.a[7] = read_vector(mut bus, 0)
	c.pc = read_vector(mut bus, 4)
	c.stopped = false
	c.halted = false
	c.aborted = false
	c.trace_pending = false
	c.ipl_seen = 0
	c.reset_line_pulsed = false
}

// step runs one instruction, or one trace or interrupt exception entry, and
// returns the number of MC68000 clock cycles it consumed. The result is never
// zero: a stopped or halted processor reports a small idle quantum.
//
// Callers should hold the bus as a `hwtypes.Bus` value and pass that: V boxes
// a concrete bus type on every implicit conversion to the interface, which
// would put a heap allocation into each call.
pub fn (mut c Cpu) step(mut bus hwtypes.Bus) u32 {
	if c.halted {
		c.cycles += idle_quantum
		return idle_quantum
	}
	start := c.cycles
	if c.trace_pending {
		c.trace_pending = false
		c.exception(mut bus, vector_trace, c.pc, 34)
	} else if !c.service_interrupt(mut bus) {
		if c.stopped {
			c.cycles += idle_quantum
		} else {
			c.execute(mut bus)
		}
	}
	return u32(c.cycles - start)
}

// str_state formats PC, SR and all data and address registers on one line.
pub fn (c &Cpu) str_state() string {
	mut s := 'PC=${c.pc:08x} SR=${c.sr:04x}'
	for i, v in c.d {
		s += ' D${i}=${v:08x}'
	}
	for i, v in c.a {
		s += ' A${i}=${v:08x}'
	}
	return s
}

// execute fetches and runs the instruction at `pc`.
@[direct_array_access]
fn (mut c Cpu) execute(mut bus hwtypes.Bus) {
	if c.pc & 1 != 0 {
		c.address_error(mut bus, c.pc, .fetch, c.pc)
		return
	}
	traced := c.sr & sr_trace != 0
	c.aborted = false
	opcode := bus.read16(c.pc)
	c.ir = opcode
	c.pc += 2
	c.dispatch(mut bus, op_table[opcode])
	if traced && !c.aborted {
		c.trace_pending = true
	}
}

// supervisor reports whether the processor is in supervisor mode.
@[inline]
fn (c &Cpu) supervisor() bool {
	return c.sr & sr_supervisor != 0
}

// set_sr loads the whole status register, exchanging the active stack
// pointer when the supervisor bit changes.
@[direct_array_access]
fn (mut c Cpu) set_sr(value u16) {
	next := value & sr_implemented
	if (c.sr ^ next) & sr_supervisor != 0 {
		if c.supervisor() {
			c.ssp = c.a[7]
			c.a[7] = c.usp
		} else {
			c.usp = c.a[7]
			c.a[7] = c.ssp
		}
	}
	c.sr = next
}

// set_ccr loads the condition code byte of the status register.
@[inline]
fn (mut c Cpu) set_ccr(value u32) {
	c.sr = (c.sr & 0xff00) | u16(value & 0x1f)
}

// set_d stores the low `size` bits of `value` into data register `reg`.
@[direct_array_access; inline]
fn (mut c Cpu) set_d(reg u32, size Size, value u32) {
	mask := size.mask()
	c.d[reg] = (c.d[reg] & ~mask) | (value & mask)
}

// reg_value returns register `index` of the combined D0-D7/A0-A7 file.
@[direct_array_access; inline]
fn (c &Cpu) reg_value(index u32) u32 {
	return if index < 8 { c.d[index] } else { c.a[index & 7] }
}

// set_reg stores into register `index` of the combined D0-D7/A0-A7 file.
@[direct_array_access; inline]
fn (mut c Cpu) set_reg(index u32, value u32) {
	if index < 8 {
		c.d[index] = value
	} else {
		c.a[index & 7] = value
	}
}
