module m68k

import hwtypes

// ShiftKind is the two-bit operation field shared by the register and
// memory shift encodings.
enum ShiftKind as u8 {
	arithmetic
	logical
	rotate_x
	rotate
}

// shift_kind decodes the two-bit shift operation field.
@[inline]
fn shift_kind(bits u32) ShiftKind {
	return match bits & 3 {
		0 { ShiftKind.arithmetic }
		1 { ShiftKind.logical }
		2 { ShiftKind.rotate_x }
		else { ShiftKind.rotate }
	}
}

// bit_op applies BTST (0), BCHG (1), BCLR (2) or BSET (3) to bit `bit` of
// `value`, sets Z from the bit's previous state and returns the new value.
@[inline]
fn (mut c Cpu) bit_op(kind u32, value u32, bit u32) u32 {
	mask := u32(1) << bit
	c.sr = if value & mask == 0 { c.sr | flag_z } else { c.sr & ~flag_z }
	return match kind {
		0 { value }
		1 { value ^ mask }
		2 { value & ~mask }
		else { value | mask }
	}
}

// op_bit_dynamic executes BTST, BCHG, BCLR and BSET with the bit number in
// a data register.
@[direct_array_access]
fn (mut c Cpu) op_bit_dynamic(mut bus hwtypes.Bus) {
	c.bit_instruction(mut bus, c.d[(c.ir >> 9) & 7])
}

// op_bit_static executes BTST, BCHG, BCLR and BSET with an immediate bit
// number.
fn (mut c Cpu) op_bit_static(mut bus hwtypes.Bus) {
	number := c.fetch16(mut bus)
	c.bit_instruction(mut bus, number)
}

// bit_instruction runs a bit instruction on the operand named by the
// opcode. A data register is treated as 32 bits wide, memory as a byte.
@[direct_array_access]
fn (mut c Cpu) bit_instruction(mut bus hwtypes.Bus, number u32) {
	opcode := u32(c.ir)
	kind := (opcode >> 6) & 3
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode == mode_dn {
		bit := number & 31
		c.d[reg] = c.bit_op(kind, c.d[reg], bit)
		high := bit > 15
		c.cycles += match kind {
			0 {
				u64(6)
			}
			2 {
				if high {
					u64(10)
				} else {
					u64(8)
				}
			}
			else {
				if high {
					u64(8)
				} else {
					u64(6)
				}
			}
		}

		return
	}
	bit := number & 7
	if kind == 0 {
		c.bit_op(kind, c.read_ea(mut bus, mode, reg, .byte), bit)
	} else {
		addr := c.ea_read_addr(mut bus, mode, reg, .byte)
		res := c.bit_op(kind, c.load(mut bus, addr, .byte), bit)
		c.store(mut bus, addr, .byte, res)
	}
	c.cycles += 4
}

// shift performs one shift or rotate of `value` by `count` (0..63) and sets
// the condition codes. All arithmetic is done on 64-bit intermediates so no
// host shift ever reaches its operand width.
fn (mut c Cpu) shift(kind ShiftKind, left bool, value u32, count u32, size Size) u32 {
	bits := size.bits()
	mask := u64(size.mask())
	val := u64(value) & mask
	mut res := val
	mut carry := u64(0)
	mut overflow := false
	mut sets_x := count != 0
	match kind {
		.arithmetic {
			if left {
				res, carry, overflow = asl(val, count, bits)
			} else {
				res, carry = asr(val, count, bits)
			}
		}
		.logical {
			if count > bits {
				res = 0
			} else if count != 0 {
				if left {
					carry = (val >> (bits - count)) & 1
					res = (val << count) & mask
				} else {
					carry = (val >> (count - 1)) & 1
					res = val >> count
				}
			}
		}
		.rotate_x {
			// A rotate through X works on bits+1 bits with X on top.
			wide := bits + 1
			n := count % wide
			ext := (u64(c.x_bit()) << bits) | val
			rotated := if n == 0 {
				ext
			} else if left {
				(ext << n) | (ext >> (wide - n))
			} else {
				(ext >> n) | (ext << (wide - n))
			}
			res = rotated & mask
			carry = (rotated >> bits) & 1
		}
		.rotate {
			sets_x = false
			n := count % bits
			if n != 0 {
				rotated := if left {
					(val << n) | (val >> (bits - n))
				} else {
					(val >> n) | (val << (bits - n))
				}
				res = rotated & mask
			}
			if count != 0 {
				carry = if left { res & 1 } else { (res >> (bits - 1)) & 1 }
			}
		}
	}

	mut ccr := nz_ccr(u32(res), size) | u16(carry)
	if overflow {
		ccr |= flag_v
	}
	if sets_x {
		c.set_xnzvc(ccr | u16(carry << 4))
	} else {
		c.set_nzvc(ccr)
	}
	return u32(res)
}

// asl returns the result, last bit shifted out and overflow of an
// arithmetic left shift. Overflow is set when the sign bit changes at any
// point during the shift.
fn asl(val u64, count u32, bits u32) (u64, u64, bool) {
	if count == 0 {
		return val, 0, false
	}
	mask := (u64(1) << bits) - 1
	if count >= bits {
		carry := if count == bits { val & 1 } else { u64(0) }
		return 0, carry, val != 0
	}
	// The sign bit and the `count` bits below it must all be equal.
	top := val >> (bits - 1 - count)
	top_mask := (u64(1) << (count + 1)) - 1
	overflow := top != 0 && top != top_mask
	return (val << count) & mask, (val >> (bits - count)) & 1, overflow
}

// asr returns the result and last bit shifted out of an arithmetic right
// shift.
fn asr(val u64, count u32, bits u32) (u64, u64) {
	if count == 0 {
		return val, 0
	}
	mask := (u64(1) << bits) - 1
	sign := (val >> (bits - 1)) & 1
	fill := if sign != 0 { mask } else { u64(0) }
	if count >= bits {
		return fill, sign
	}
	return ((val >> count) | (fill << (bits - count))) & mask, (val >> (count - 1)) & 1
}

// op_shift_reg executes the register shifts and rotates. The count comes
// from the opcode (1..8) or from a data register modulo 64.
@[direct_array_access]
fn (mut c Cpu) op_shift_reg() {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	reg := opcode & 7
	mut count := (opcode >> 9) & 7
	if opcode & 0x0020 != 0 {
		count = c.d[count] & 63
	} else if count == 0 {
		count = 8
	}
	res := c.shift(shift_kind(opcode >> 3), opcode & 0x0100 != 0, c.d[reg], count, size)
	c.set_d(reg, size, res)
	base := if size == .long { u64(8) } else { u64(6) }
	c.cycles += base + 2 * u64(count)
}

// op_shift_mem executes the memory shifts and rotates: one bit on a word.
fn (mut c Cpu) op_shift_mem(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	addr := c.ea_read_addr(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	value := c.load(mut bus, addr, .word)
	res := c.shift(shift_kind(opcode >> 9), opcode & 0x0100 != 0, value, 1, .word)
	c.store(mut bus, addr, .word, res)
	c.cycles += 4
}
