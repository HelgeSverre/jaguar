module m68k

import hwtypes

// bcd_add computes the packed-decimal sum `dst + src + X` exactly as the
// 68000 adder and its decimal corrector do, including the officially
// undefined N and V flags and the results for non-decimal digits.
fn (mut c Cpu) bcd_add(src u32, dst u32) u32 {
	binary := src + dst + c.x_bit()
	binary_carry := ((src & dst) | (~binary & (src | dst))) & 0x88
	decimal_carry := (((binary + 0x66) ^ binary) & 0x110) >> 1
	carries := binary_carry | decimal_carry
	res := binary + (carries - (carries >> 2))
	carry := ((binary_carry | (binary & ~res)) >> 7) & 1
	overflow := ((~binary & res) >> 7) & 1
	c.set_xnzvc_sticky_z(nz_ccr(res, .byte) | u16((carry * 0x11) | (overflow << 1)))
	return res & 0xff
}

// bcd_sub computes the packed-decimal difference `dst - src - X` with the
// same fidelity as `bcd_add`.
fn (mut c Cpu) bcd_sub(src u32, dst u32) u32 {
	binary := dst - src - c.x_bit()
	borrows := ((~dst & src) | (binary & (~dst | src))) & 0x88
	res := binary - (borrows - (borrows >> 2))
	borrow := ((borrows | (~binary & res)) >> 7) & 1
	overflow := ((binary & ~res) >> 7) & 1
	c.set_xnzvc_sticky_z(nz_ccr(res, .byte) | u16((borrow * 0x11) | (overflow << 1)))
	return res & 0xff
}

// op_bcd executes ABCD and SBCD in their `Dy,Dx` and `-(Ay),-(Ax)` forms.
@[direct_array_access]
fn (mut c Cpu) op_bcd(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	ry := opcode & 7
	rx := (opcode >> 9) & 7
	if opcode & 0x0008 == 0 {
		src := c.d[ry] & 0xff
		dst := c.d[rx] & 0xff
		c.set_d(rx, .byte, if op == .add { c.bcd_add(src, dst) } else { c.bcd_sub(src, dst) })
		c.cycles += 6
		return
	}
	c.cycles += 2
	src := c.predec_load(mut bus, ry, .byte)
	dst := c.predec_load(mut bus, rx, .byte)
	res := if op == .add { c.bcd_add(src, dst) } else { c.bcd_sub(src, dst) }
	c.store(mut bus, c.a[rx], .byte, res)
	c.cycles += 4
}

// op_nbcd executes NBCD: the packed-decimal negation `0 - dst - X`.
@[direct_array_access]
fn (mut c Cpu) op_nbcd(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode == mode_dn {
		c.set_d(reg, .byte, c.bcd_sub(c.d[reg] & 0xff, 0))
		c.cycles += 6
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, .byte)
	res := c.bcd_sub(c.load(mut bus, addr, .byte), 0)
	c.store(mut bus, addr, .byte, res)
	c.cycles += 4
}
