module jaggame

// Type is the type of a value in the language. `void` is only the result
// of a function that returns nothing.
pub enum Type {
	void
	bool
	u8
	i8
	u16
	i16
	u32
	i32
	fix
}

// all_types lists every type a variable can have.
pub const all_types = [Type.bool, .u8, .i8, .u16, .i16, .u32, .i32, .fix]

// fix_one is 1.0 in the 16.16 fixed-point format of `fix`.
pub const fix_one = 65536

// size is the number of bytes a value of the type takes in memory.
pub fn (t Type) size() int {
	return match t {
		.void { 0 }
		.bool, .u8, .i8 { 1 }
		.u16, .i16 { 2 }
		.u32, .i32, .fix { 4 }
	}
}

// is_integer is true for the eight- to 32-bit integer types.
pub fn (t Type) is_integer() bool {
	return t in [.u8, .i8, .u16, .i16, .u32, .i32]
}

// is_number is true for the integers and `fix`.
pub fn (t Type) is_number() bool {
	return t.is_integer() || t == .fix
}

// is_signed is true for the signed integers and `fix`.
pub fn (t Type) is_signed() bool {
	return t in [.i8, .i16, .i32, .fix]
}

// smallest is the smallest raw value of the type.
pub fn (t Type) smallest() i64 {
	return match t {
		.i8 { -128 }
		.i16 { -32768 }
		.i32, .fix { -2147483648 }
		else { 0 }
	}
}

// largest is the largest raw value of the type.
pub fn (t Type) largest() i64 {
	return match t {
		.void { 0 }
		.bool { 1 }
		.u8 { 255 }
		.i8 { 127 }
		.u16 { 65535 }
		.i16 { 32767 }
		.u32 { 4294967295 }
		.i32, .fix { 2147483647 }
	}
}

// wrap reduces a raw value to the type's width, the way the 68000 does:
// the bits above the width are dropped and a signed type is sign-extended.
pub fn (t Type) wrap(v i64) i64 {
	return match t {
		.void { i64(0) }
		.bool { v & 1 }
		.u8 { v & 0xff }
		.i8 { i64(i8(v)) }
		.u16 { v & 0xffff }
		.i16 { i64(i16(v)) }
		.u32 { v & 0xffff_ffff }
		.i32, .fix { i64(i32(v)) }
	}
}

// fits is true when an integer can be stored in the type without change.
fn (t Type) fits(v i64) bool {
	return v >= t.smallest() && v <= t.largest()
}

// range describes the values of an integer type, for messages.
fn (t Type) range() string {
	if t == .fix {
		return '-32768..32767'
	}
	return '${t.smallest()}..${t.largest()}'
}

// shift is log2 of the size, for indexing.
fn (t Type) shift() int {
	return match t.size() {
		2 { 1 }
		4 { 2 }
		else { 0 }
	}
}

// fix_raw is the raw 16.16 value nearest to a float: `fix_raw(1.5)` is
// 98304.
pub fn fix_raw(f f64) i64 {
	scaled := f * fix_one
	if scaled < 0 {
		return -i64(-scaled + 0.5)
	}
	return i64(scaled + 0.5)
}

// fix_fits is true when a float can be a `fix`.
fn fix_fits(f f64) bool {
	return f >= -32768.0 && f < 32768.0
}

// fix_value turns a raw `fix` into a float, for tests and messages.
pub fn fix_value(raw i64) f64 {
	return f64(raw) / fix_one
}
