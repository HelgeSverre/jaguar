module m68k

const flag_c = u16(0x01)
const flag_v = u16(0x02)
const flag_z = u16(0x04)
const flag_n = u16(0x08)
const flag_x = u16(0x10)

// Size is an operand width. The numeric values match the usual two-bit size
// field of the instruction encodings.
enum Size as u8 {
	byte
	word
	long
}

// mask returns the bit mask covering an operand of this size.
@[inline]
fn (s Size) mask() u32 {
	return match s {
		.byte { u32(0xff) }
		.word { u32(0xffff) }
		.long { u32(0xffff_ffff) }
	}
}

// msb returns the bit number of the sign bit.
@[inline]
fn (s Size) msb() u32 {
	return match s {
		.byte { u32(7) }
		.word { u32(15) }
		.long { u32(31) }
	}
}

// bits returns the operand width in bits.
@[inline]
fn (s Size) bits() u32 {
	return s.msb() + 1
}

// size_field decodes the standard two-bit size field. The decoder never
// routes the reserved value 3 to a handler that calls this.
@[inline]
fn size_field(bits u32) Size {
	return match bits & 3 {
		0 { Size.byte }
		1 { Size.word }
		else { Size.long }
	}
}

// nz_ccr returns N and Z for `res`; V and C are clear.
@[inline]
fn nz_ccr(res u32, size Size) u16 {
	if res & size.mask() == 0 {
		return flag_z
	}
	return u16(((res >> size.msb()) & 1) << 3)
}

// add_ccr returns X, N, Z, V and C for `res = dst + src`.
@[inline]
fn add_ccr(src u32, dst u32, res u32, size Size) u16 {
	msb := size.msb()
	carry := (((src & dst) | (~res & (src | dst))) >> msb) & 1
	overflow := (((src ^ res) & (dst ^ res)) >> msb) & 1
	return nz_ccr(res, size) | u16((carry * 0x11) | (overflow << 1))
}

// sub_ccr returns X, N, Z, V and C for `res = dst - src`.
@[inline]
fn sub_ccr(src u32, dst u32, res u32, size Size) u16 {
	msb := size.msb()
	borrow := (((src & ~dst) | (res & ~dst) | (src & res)) >> msb) & 1
	overflow := (((src ^ dst) & (res ^ dst)) >> msb) & 1
	return nz_ccr(res, size) | u16((borrow * 0x11) | (overflow << 1))
}

// set_xnzvc replaces all five condition codes.
@[inline]
fn (mut c Cpu) set_xnzvc(ccr u16) {
	c.sr = (c.sr & 0xffe0) | ccr
}

// set_nzvc replaces N, Z, V and C and keeps X.
@[inline]
fn (mut c Cpu) set_nzvc(ccr u16) {
	c.sr = (c.sr & 0xfff0) | (ccr & 0x000f)
}

// set_xnzvc_sticky_z replaces X, N, V and C; Z is only ever cleared, as the
// multi-precision instructions (ADDX, SUBX, NEGX, ABCD, SBCD, NBCD) require.
@[inline]
fn (mut c Cpu) set_xnzvc_sticky_z(ccr u16) {
	sticky := ccr & (c.sr | ~flag_z)
	c.sr = (c.sr & 0xffe0) | sticky
}

// set_logic_flags sets N and Z from `res`, clears V and C and keeps X.
@[inline]
fn (mut c Cpu) set_logic_flags(res u32, size Size) {
	c.set_nzvc(nz_ccr(res, size))
}

// x_bit returns the extend flag as 0 or 1.
@[inline]
fn (c &Cpu) x_bit() u32 {
	return u32(c.sr >> 4) & 1
}

// condition evaluates the four-bit condition code `cc` of Bcc, DBcc and Scc.
@[inline]
fn (c &Cpu) condition(cc u32) bool {
	sr := c.sr
	carry := sr & flag_c != 0
	overflow := sr & flag_v != 0
	zero := sr & flag_z != 0
	negative := sr & flag_n != 0
	return match cc & 15 {
		0 { true }
		1 { false }
		2 { !carry && !zero }
		3 { carry || zero }
		4 { !carry }
		5 { carry }
		6 { !zero }
		7 { zero }
		8 { !overflow }
		9 { overflow }
		10 { !negative }
		11 { negative }
		12 { negative == overflow }
		13 { negative != overflow }
		14 { !zero && negative == overflow }
		else { zero || negative != overflow }
	}
}
