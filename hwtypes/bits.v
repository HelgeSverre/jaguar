module hwtypes

// sext8 sign-extends the low 8 bits of `v` to 32 bits.
@[inline]
pub fn sext8(v u32) u32 {
	return u32(i32(i8(u8(v))))
}

// sext16 sign-extends the low 16 bits of `v` to 32 bits.
@[inline]
pub fn sext16(v u32) u32 {
	return u32(i32(i16(u16(v))))
}

// sext sign-extends the low `bits` bits of `v` to 32 bits; `bits` is 1..32.
@[inline]
pub fn sext(v u32, bits u32) u32 {
	shift := 32 - bits
	return u32(i32(v << shift) >> shift)
}

// asr32 is an arithmetic right shift that is defined for every count.
@[inline]
pub fn asr32(v u32, count u32) u32 {
	if count >= 32 {
		return if v & 0x8000_0000 != 0 { u32(0xffff_ffff) } else { u32(0) }
	}
	return u32(i32(v) >> count)
}

// rol32 rotates left; `count` is taken modulo 32.
@[inline]
pub fn rol32(v u32, count u32) u32 {
	n := count & 31
	if n == 0 {
		return v
	}
	return (v << n) | (v >> (32 - n))
}

// ror32 rotates right; `count` is taken modulo 32.
@[inline]
pub fn ror32(v u32, count u32) u32 {
	n := count & 31
	if n == 0 {
		return v
	}
	return (v >> n) | (v << (32 - n))
}
