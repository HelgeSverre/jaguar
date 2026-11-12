module risc

import hwtypes

// Opcode is the six-bit primary opcode. Where the GPU and the DSP assign
// different instructions to one encoding the name carries both.
enum Opcode {
	add
	addc
	addq
	addqt
	sub
	subc
	subq
	subqt
	neg
	and
	or
	xor
	not
	btst
	bset
	bclr
	mult
	imult
	imultn
	resmac
	imacn
	div
	abs
	sh
	shlq
	shrq
	sha
	sharq
	ror
	rorq
	cmp
	cmpq
	sat8_subqmod
	sat16_sat16s
	move
	moveq
	moveta
	movefa
	movei
	loadb
	loadw
	load
	loadp_sat32s
	load_r14_disp
	load_r15_disp
	storeb
	storew
	store
	storep_mirror
	store_r14_disp
	store_r15_disp
	move_pc
	jump
	jr
	mmult
	mtoi
	normi
	nop
	load_r14_reg
	load_r15_reg
	store_r14_reg
	store_r15_reg
	sat24
	pack_addqmod
}

// Provisional `functional_v1` instruction costs in master-clock ticks. They
// follow the shape of the pipeline (one tick for register operations, more
// for memory, multiply and divide) and are not measured timing.
const cost_register = u32(1)
const cost_memory = u32(2)
const cost_multiply = u32(2)
const cost_divide = u32(18)
const cost_jump = u32(2)
const cost_matrix = u32(8)

// run executes instructions until `budget` master ticks are consumed or the
// processor stops, and returns the ticks actually consumed. The last
// instruction may overshoot the budget; the caller carries the difference.
@[direct_array_access]
pub fn (mut c Risc) run(mut bus hwtypes.Bus, budget u32) u32 {
	mut used := u32(0)
	for used < budget && c.running {
		if c.irq_dirty {
			c.service_interrupts(mut bus)
		}
		in_delay_slot := c.branch_pending
		used += c.execute(mut bus)
		if in_delay_slot {
			c.pc = c.branch_target
			c.branch_pending = false
		}
		c.instructions++
	}
	return used
}

// execute runs one instruction and returns its cost in master ticks.
@[direct_array_access]
fn (mut c Risc) execute(mut bus hwtypes.Bus) u32 {
	instruction_pc := c.pc
	word := c.fetch16(mut bus)
	src := (word >> 5) & 31
	rn := c.bank + (word & 31)
	rm := c.bank + src
	op := unsafe { Opcode(word >> 10) }
	match op {
		.add {
			c.regs[rn] = c.add_flags(c.regs[rn], c.regs[rm], 0)
		}
		.addc {
			c.regs[rn] = c.add_flags(c.regs[rn], c.regs[rm], c.cf)
		}
		.addq {
			c.regs[rn] = c.add_flags(c.regs[rn], quick(src), 0)
		}
		.addqt {
			c.regs[rn] += quick(src)
		}
		.sub {
			c.regs[rn] = c.sub_flags(c.regs[rn], c.regs[rm], 0)
		}
		.subc {
			c.regs[rn] = c.sub_flags(c.regs[rn], c.regs[rm], c.cf)
		}
		.subq {
			c.regs[rn] = c.sub_flags(c.regs[rn], quick(src), 0)
		}
		.subqt {
			c.regs[rn] -= quick(src)
		}
		.neg {
			c.regs[rn] = c.sub_flags(0, c.regs[rn], 0)
		}
		.and {
			c.regs[rn] = c.zn(c.regs[rn] & c.regs[rm])
		}
		.or {
			c.regs[rn] = c.zn(c.regs[rn] | c.regs[rm])
		}
		.xor {
			c.regs[rn] = c.zn(c.regs[rn] ^ c.regs[rm])
		}
		.not {
			c.regs[rn] = c.zn(~c.regs[rn])
		}
		.btst {
			c.zf = ((c.regs[rn] >> src) & 1) ^ 1
		}
		.bset {
			c.regs[rn] = c.zn(c.regs[rn] | (u32(1) << src))
		}
		.bclr {
			c.regs[rn] = c.zn(c.regs[rn] & ~(u32(1) << src))
		}
		.mult {
			c.regs[rn] = c.zn((c.regs[rn] & 0xffff) * (c.regs[rm] & 0xffff))
			return cost_multiply
		}
		.imult {
			c.regs[rn] = c.zn(u32(signed_product(c.regs[rn], c.regs[rm])))
			return cost_multiply
		}
		.imultn {
			product := signed_product(c.regs[rn], c.regs[rm])
			c.acc = product
			c.zn(u32(product))
			return cost_multiply
		}
		.resmac {
			c.regs[rn] = u32(c.acc)
		}
		.imacn {
			c.acc = sext40(c.acc + signed_product(c.regs[rn], c.regs[rm]))
			return cost_multiply
		}
		.div {
			c.divide(rn, c.regs[rm])
			return cost_divide
		}
		.abs {
			value := c.regs[rn]
			c.cf = value >> 31
			if value == 0x8000_0000 {
				c.nf = 1
				c.zf = 0
			} else {
				c.regs[rn] = c.zn(if c.cf != 0 { u32(0) - value } else { value })
			}
		}
		.sh {
			c.regs[rn] = c.zn(c.shift_logical(c.regs[rn], c.regs[rm]))
		}
		.shlq {
			value := c.regs[rn]
			count := 32 - src
			c.cf = value >> 31
			c.regs[rn] = c.zn(if count >= 32 { u32(0) } else { value << count })
		}
		.shrq {
			value := c.regs[rn]
			count := quick(src)
			c.cf = value & 1
			c.regs[rn] = c.zn(if count >= 32 { u32(0) } else { value >> count })
		}
		.sha {
			c.regs[rn] = c.zn(c.shift_arithmetic(c.regs[rn], c.regs[rm]))
		}
		.sharq {
			value := c.regs[rn]
			c.cf = value & 1
			c.regs[rn] = c.zn(hwtypes.asr32(value, quick(src)))
		}
		.ror {
			value := c.regs[rn]
			c.cf = value >> 31
			c.regs[rn] = c.zn(hwtypes.ror32(value, c.regs[rm]))
		}
		.rorq {
			value := c.regs[rn]
			c.cf = value >> 31
			c.regs[rn] = c.zn(hwtypes.ror32(value, quick(src)))
		}
		.cmp {
			c.sub_flags(c.regs[rn], c.regs[rm], 0)
		}
		.cmpq {
			c.sub_flags(c.regs[rn], hwtypes.sext(src, 5), 0)
		}
		.sat8_subqmod {
			if c.variant == .gpu {
				c.regs[rn] = c.zn(saturate_unsigned(c.regs[rn], 0xff))
			} else {
				value := c.regs[rn]
				result := c.sub_flags(value, quick(src), 0)
				c.regs[rn] = (result & ~c.modulo) | (value & c.modulo)
			}
		}
		.sat16_sat16s {
			if c.variant == .gpu {
				c.regs[rn] = c.zn(saturate_unsigned(c.regs[rn], 0xffff))
			} else {
				c.regs[rn] = c.zn(saturate_signed16(c.regs[rn]))
			}
		}
		.move {
			c.regs[rn] = c.regs[rm]
		}
		.moveq {
			c.regs[rn] = src
		}
		.moveta {
			c.regs[rn ^ 32] = c.regs[rm]
		}
		.movefa {
			c.regs[rn] = c.regs[rm ^ 32]
		}
		.movei {
			// The immediate follows low word first.
			low := c.fetch16(mut bus)
			high := c.fetch16(mut bus)
			c.regs[rn] = (high << 16) | low
			return cost_memory
		}
		.loadb {
			addr := c.regs[rm]
			c.regs[rn] = if c.is_internal(addr) {
				c.load32(mut bus, addr) & 0xff
			} else {
				u32(bus.read8(addr))
			}
			return cost_memory
		}
		.loadw {
			addr := c.regs[rm]
			c.regs[rn] = if c.is_internal(addr) {
				c.load32(mut bus, addr) & 0xffff
			} else {
				u32(bus.read16(addr & 0xffff_fffe))
			}
			return cost_memory
		}
		.load {
			c.regs[rn] = c.load32(mut bus, c.regs[rm])
			return cost_memory
		}
		.loadp_sat32s {
			if c.variant == .gpu {
				addr := c.regs[rm] & 0xffff_fff8
				c.hidata = c.load32(mut bus, addr)
				c.regs[rn] = c.load32(mut bus, addr + 4)
				return cost_memory
			}
			c.regs[rn] = c.zn(c.saturate_accumulator(c.regs[rn]))
		}
		.load_r14_disp {
			c.regs[rn] = c.load32(mut bus, c.regs[c.bank + 14] + (quick(src) << 2))
			return cost_memory
		}
		.load_r15_disp {
			c.regs[rn] = c.load32(mut bus, c.regs[c.bank + 15] + (quick(src) << 2))
			return cost_memory
		}
		.storeb {
			addr := c.regs[rm]
			if c.is_internal(addr) {
				c.store32(mut bus, addr, c.regs[rn] & 0xff)
			} else {
				bus.write8(addr, u8(c.regs[rn]))
			}
			return cost_memory
		}
		.storew {
			addr := c.regs[rm]
			if c.is_internal(addr) {
				c.store32(mut bus, addr, c.regs[rn] & 0xffff)
			} else {
				bus.write16(addr & 0xffff_fffe, u16(c.regs[rn]))
			}
			return cost_memory
		}
		.store {
			c.store32(mut bus, c.regs[rm], c.regs[rn])
			return cost_memory
		}
		.storep_mirror {
			if c.variant == .gpu {
				addr := c.regs[rm] & 0xffff_fff8
				c.store32(mut bus, addr, c.hidata)
				c.store32(mut bus, addr + 4, c.regs[rn])
				return cost_memory
			}
			c.regs[rn] = c.zn(reverse_bits(c.regs[rn]))
		}
		.store_r14_disp {
			c.store32(mut bus, c.regs[c.bank + 14] + (quick(src) << 2), c.regs[rn])
			return cost_memory
		}
		.store_r15_disp {
			c.store32(mut bus, c.regs[c.bank + 15] + (quick(src) << 2), c.regs[rn])
			return cost_memory
		}
		.move_pc {
			c.regs[rn] = instruction_pc
		}
		.jump {
			if c.condition(word & 31) {
				c.branch_target = c.regs[rm] & 0xffff_fffe
				c.branch_pending = true
			}
			return cost_jump
		}
		.jr {
			if c.condition(word & 31) {
				c.branch_target = c.pc + (hwtypes.sext(src, 5) << 1)
				c.branch_pending = true
			}
			return cost_jump
		}
		.mmult {
			c.regs[rn] = c.zn(c.matrix_multiply(mut bus, src))
			return cost_matrix
		}
		.mtoi {
			value := c.regs[rm]
			c.regs[rn] = c.zn((hwtypes.asr32(value, 8) & 0xff80_0000) | (value & 0x007f_ffff))
		}
		.normi {
			c.regs[rn] = c.zn(normalisation_integer(c.regs[rm]))
		}
		.nop {}
		.load_r14_reg {
			c.regs[rn] = c.load32(mut bus, c.regs[c.bank + 14] + c.regs[rm])
			return cost_memory
		}
		.load_r15_reg {
			c.regs[rn] = c.load32(mut bus, c.regs[c.bank + 15] + c.regs[rm])
			return cost_memory
		}
		.store_r14_reg {
			c.store32(mut bus, c.regs[c.bank + 14] + c.regs[rm], c.regs[rn])
			return cost_memory
		}
		.store_r15_reg {
			c.store32(mut bus, c.regs[c.bank + 15] + c.regs[rm], c.regs[rn])
			return cost_memory
		}
		.sat24 {
			// Not implemented by the DSP, which executes it as a no-op.
			if c.variant == .gpu {
				c.regs[rn] = c.zn(saturate_unsigned(c.regs[rn], 0xff_ffff))
			}
		}
		.pack_addqmod {
			value := c.regs[rn]
			if c.variant == .dsp {
				result := c.add_flags(value, quick(src), 0)
				c.regs[rn] = (result & ~c.modulo) | (value & c.modulo)
			} else if src == 0 {
				c.regs[rn] = ((value >> 10) & 0xf000) | ((value >> 5) & 0x0f00) | (value & 0xff)
			} else {
				c.regs[rn] = ((value & 0xf000) << 10) | ((value & 0x0f00) << 5) | (value & 0xff)
			}
		}
	}

	return cost_register
}

// quick maps a five-bit field to 1..32; an encoded zero means 32.
@[inline]
fn quick(field u32) u32 {
	return if field == 0 { u32(32) } else { field }
}

// zn sets Z and N from `value` and returns it.
@[inline]
fn (mut c Risc) zn(value u32) u32 {
	c.zf = if value == 0 { u32(1) } else { u32(0) }
	c.nf = value >> 31
	return value
}

// add_flags returns a + b + carry_in and sets Z, N and the carry out.
@[inline]
fn (mut c Risc) add_flags(a u32, b u32, carry_in u32) u32 {
	wide := u64(a) + u64(b) + u64(carry_in)
	c.cf = u32(wide >> 32) & 1
	return c.zn(u32(wide))
}

// sub_flags returns a - b - borrow_in and sets Z, N and the borrow out.
@[inline]
fn (mut c Risc) sub_flags(a u32, b u32, borrow_in u32) u32 {
	wide := u64(a) - u64(b) - u64(borrow_in)
	c.cf = u32(wide >> 32) & 1
	return c.zn(u32(wide))
}

// condition evaluates a five-bit jump condition: bit 0 requires Z clear,
// bit 1 Z set, bit 2 the tested flag clear and bit 3 the tested flag set,
// where bit 4 selects N instead of C as the tested flag.
@[inline]
fn (c &Risc) condition(code u32) bool {
	if code & 1 != 0 && c.zf != 0 {
		return false
	}
	if code & 2 != 0 && c.zf == 0 {
		return false
	}
	tested := if code & 16 != 0 { c.nf } else { c.cf }
	if code & 4 != 0 && tested != 0 {
		return false
	}
	if code & 8 != 0 && tested == 0 {
		return false
	}
	return true
}

// signed_product multiplies the low 16 bits of both operands as signed values.
@[inline]
fn signed_product(a u32, b u32) i64 {
	return i64(i16(u16(a))) * i64(i16(u16(b)))
}

// sext40 wraps a value to the 40-bit accumulator and sign-extends it.
@[inline]
fn sext40(value i64) i64 {
	return i64(u64(value) << 24) >> 24
}

// shift_logical implements SH: a negative count shifts left.
@[inline]
fn (mut c Risc) shift_logical(value u32, count u32) u32 {
	if count & 0x8000_0000 != 0 {
		left := u32(0) - count
		c.cf = value >> 31
		return if left >= 32 { u32(0) } else { value << left }
	}
	c.cf = value & 1
	return if count >= 32 { u32(0) } else { value >> count }
}

// shift_arithmetic implements SHA: a negative count shifts left.
@[inline]
fn (mut c Risc) shift_arithmetic(value u32, count u32) u32 {
	if count & 0x8000_0000 != 0 {
		left := u32(0) - count
		c.cf = value >> 31
		return if left >= 32 { u32(0) } else { value << left }
	}
	c.cf = value & 1
	return hwtypes.asr32(value, count)
}

// saturate_unsigned clamps a signed value to 0..max.
@[inline]
fn saturate_unsigned(value u32, max u32) u32 {
	if value & 0x8000_0000 != 0 {
		return 0
	}
	return if value > max { max } else { value }
}

// saturate_signed16 clamps a signed value to the 16-bit signed range.
@[inline]
fn saturate_signed16(value u32) u32 {
	signed := i32(value)
	if signed < -32768 {
		return 0xffff_8000
	}
	if signed > 32767 {
		return 0x7fff
	}
	return value
}

// saturate_accumulator implements SAT32S: the 40-bit accumulator decides
// whether `value` overflowed the signed 32-bit range.
@[inline]
fn (c &Risc) saturate_accumulator(value u32) u32 {
	high := i32(u32(u64(c.acc) >> 32))
	if high < -1 {
		return 0x8000_0000
	}
	if high > 0 {
		return 0x7fff_ffff
	}
	return value
}

// reverse_bits mirrors all 32 bits (DSP MIRROR, used for FFT addressing).
fn reverse_bits(value u32) u32 {
	mut v := value
	v = ((v >> 1) & 0x5555_5555) | ((v & 0x5555_5555) << 1)
	v = ((v >> 2) & 0x3333_3333) | ((v & 0x3333_3333) << 2)
	v = ((v >> 4) & 0x0f0f_0f0f) | ((v & 0x0f0f_0f0f) << 4)
	v = ((v >> 8) & 0x00ff_00ff) | ((v & 0x00ff_00ff) << 8)
	return (v >> 16) | (v << 16)
}

// normalisation_integer implements NORMI: the signed number of right shifts
// that brings the operand's most significant set bit to bit 23, the position
// of the leading one in the 24-bit mantissa format. Small operands give a
// negative count (left shifts).
fn normalisation_integer(value u32) u32 {
	if value == 0 {
		return 0
	}
	mut v := value
	mut result := u32(0)
	for v & 0xff80_0000 == 0 {
		v <<= 1
		result--
	}
	for v & 0xff00_0000 != 0 {
		v >>= 1
		result++
	}
	return result
}

// divide implements DIV with the divider's non-restoring algorithm, which
// also defines the results for a zero divisor and the quirky remainder.
// Bit 0 of DIVCTRL selects 16.16 fixed-point operands.
fn (mut c Risc) divide(rn u32, divisor u32) {
	mut quotient := c.regs[rn]
	mut remainder := u32(0)
	if c.div_ctrl & 1 != 0 {
		remainder = quotient >> 16
		quotient <<= 16
	}
	for _ in 0 .. 32 {
		negative := remainder & 0x8000_0000 != 0
		remainder = (remainder << 1) | (quotient >> 31)
		if negative {
			remainder += divisor
		} else {
			remainder -= divisor
		}
		quotient = (quotient << 1) | ((~remainder) >> 31)
	}
	c.regs[rn] = quotient
	c.remain = remainder
}

// matrix_multiply implements MMULT: the dot product of a row of 16-bit values
// held in the alternate register bank with a row or column of the matrix in
// local RAM.
fn (mut c Risc) matrix_multiply(mut bus hwtypes.Bus, first_reg u32) u32 {
	count := c.mtxc & 0x0f
	stride := if c.mtxc & 0x10 != 0 { count << 2 } else { u32(4) }
	alternate := c.bank ^ 32
	mut addr := c.mtxa
	mut sum := i64(0)
	for i in 0 .. count {
		reg := c.regs[alternate + ((first_reg + (i >> 1)) & 31)]
		half := if i & 1 != 0 { reg >> 16 } else { reg }
		sum += signed_product(half, c.load32(mut bus, addr))
		addr += stride
	}
	return u32(sum)
}
