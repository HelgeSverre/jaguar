module m68k

import hwtypes
import math.bits

// op_mul executes MULU and MULS: 16 x 16 -> 32 bits. The execution time
// depends on the bit pattern of the source operand.
@[direct_array_access]
fn (mut c Cpu) op_mul(mut bus hwtypes.Bus, signed bool) {
	opcode := u32(c.ir)
	src := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	dn := (opcode >> 9) & 7
	mut res := u32(0)
	mut steps := 0
	if signed {
		res = u32(i32(i16(src)) * i32(i16(c.d[dn])))
		// One step per 01 or 10 transition in the source with a zero
		// appended below bit 0.
		steps = bits.ones_count_32((src ^ (src << 1)) & 0xffff)
	} else {
		res = src * (c.d[dn] & 0xffff)
		steps = bits.ones_count_32(src)
	}
	c.d[dn] = res
	c.set_logic_flags(res, .long)
	c.cycles += u64(38 + 2 * steps)
}

// op_divu executes DIVU: 32 / 16 -> 16-bit quotient and remainder.
@[direct_array_access]
fn (mut c Cpu) op_divu(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	divisor := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	dn := (opcode >> 9) & 7
	dividend := c.d[dn]
	if divisor == 0 {
		c.zero_divide(mut bus)
		return
	}
	c.cycles += divu_cycles(dividend, divisor)
	quotient := dividend / divisor
	if quotient > 0xffff {
		c.set_nzvc(flag_v | flag_n)
		return
	}
	c.d[dn] = ((dividend % divisor) << 16) | quotient
	c.set_logic_flags(quotient, .word)
}

// op_divs executes DIVS: signed 32 / 16 -> 16-bit quotient and remainder.
@[direct_array_access]
fn (mut c Cpu) op_divs(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	src := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	dn := (opcode >> 9) & 7
	if src == 0 {
		c.zero_divide(mut bus)
		return
	}
	dividend := i64(i32(c.d[dn]))
	divisor := i64(i16(src))
	c.cycles += divs_cycles(dividend, divisor)
	quotient := dividend / divisor
	if quotient > 0x7fff || quotient < -0x8000 {
		c.set_nzvc(flag_v | flag_n)
		return
	}
	remainder := dividend % divisor
	c.d[dn] = (u32(remainder & 0xffff) << 16) | u32(quotient & 0xffff)
	c.set_logic_flags(u32(quotient & 0xffff), .word)
}

// zero_divide raises the divide-by-zero exception.
fn (mut c Cpu) zero_divide(mut bus hwtypes.Bus) {
	c.set_nzvc(0)
	c.exception(mut bus, vector_zero_divide, c.pc, 38)
}

// divu_cycles returns the execution time of DIVU, excluding the operand
// fetch, by replaying the restoring division the microcode performs.
fn divu_cycles(dividend u32, divisor u32) u64 {
	if (dividend >> 16) >= divisor {
		return 10
	}
	mut cycles := u64(76)
	mut rest := dividend
	shifted_divisor := divisor << 16
	for _ in 0 .. 15 {
		carried := rest & 0x8000_0000 != 0
		rest <<= 1
		if carried {
			rest -= shifted_divisor
		} else if rest >= shifted_divisor {
			rest -= shifted_divisor
			cycles += 2
		} else {
			cycles += 4
		}
	}
	return cycles
}

// divs_cycles returns the execution time of DIVS, excluding the operand
// fetch. The microcode divides magnitudes and fixes the signs afterwards.
fn divs_cycles(dividend i64, divisor i64) u64 {
	mut cycles := u64(12)
	if dividend < 0 {
		cycles += 2
	}
	abs_dividend := u64(if dividend < 0 { -dividend } else { dividend })
	abs_divisor := u64(if divisor < 0 { -divisor } else { divisor })
	if (abs_dividend >> 16) >= abs_divisor {
		return cycles + 4
	}
	cycles += 110
	if divisor >= 0 {
		if dividend >= 0 {
			cycles -= 2
		} else {
			cycles += 2
		}
	}
	mut quotient := abs_dividend / abs_divisor
	for _ in 0 .. 15 {
		if quotient & 0x8000 == 0 {
			cycles += 2
		}
		quotient <<= 1
	}
	return cycles
}
