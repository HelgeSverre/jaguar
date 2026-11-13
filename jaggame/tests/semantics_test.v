module main

import jaggame
import jaggame.emulated

// The behaviour the language defines on purpose, each case worked out by
// hand: wrapping, division rounding toward zero and by zero, shifts,
// fixed-point rounding, conversions, short-circuit logic and the order of
// evaluation. Every case runs in the interpreter and on the 68000.
//
// docs/jaggame/guide.md shows this table; keep the two together.

struct Case {
	name string
	t    jaggame.Type
	e    jaggame.Expr
	want i64
}

fn test_the_defined_behaviour() {
	mut p := jaggame.new_program()
	i8_min := p.i8('i8_min', -128)
	i8_m7 := p.i8('i8_m7', -7)
	i8_m1 := p.i8('i8_m1', -1)
	i8_one := p.i8('i8_one', 1)
	u8_200 := p.u8('u8_200', 200)
	u8_0x81 := p.u8('u8_0x81', 0x81)
	u8_one := p.u8('u8_one', 1)
	u8_two := p.u8('u8_two', 2)
	u8_255 := p.u8('u8_255', 255)
	u16_zero := p.u16('u16_zero', 0)
	u16_max := p.u16('u16_max', 0xffff)
	u16_40000 := p.u16('u16_40000', 40000)
	i16_max := p.i16('i16_max', 32767)
	i16_min := p.i16('i16_min', -32768)
	i16_300 := p.i16('i16_300', 300)
	i16_m1 := p.i16('i16_m1', -1)
	u32_max := p.u32('u32_max', 0xffff_ffff)
	u32_top := p.u32('u32_top', 0x8000_0000)
	u32_five := p.u32('u32_five', 5)
	u32_33 := p.u32('u32_33', 33)
	i32_min := p.i32('i32_min', -2147483648)
	i32_m5 := p.i32('i32_m5', -5)
	i32_m1 := p.i32('i32_m1', -1)
	one := p.fix('one', 1.0)
	three := p.fix('three', 3.0)
	half := p.fix('half', 0.5)
	speed := p.fix('speed', 1.5)
	tiny := p.fix('tiny', 1.0 / 65536)
	f_m75 := p.fix('f_m75', -7.5)
	t := p.bool('t', true)
	counter := p.u8('counter')
	bump := p.func('bump', [], .bool)
	mut b := p.define(bump)
	b.inc(counter)
	b.ret(true)

	// guide:semantics
	cases := [
		Case{'u8 wraps', .u8, u8_200.add(100), 44},
		Case{'u16 wraps below 0', .u16, u16_zero.sub(1), 65535},
		Case{'i16 wraps', .i16, i16_max.add(1), -32768},
		Case{'division rounds toward zero', .i8, i8_m7.div(2), -3},
		Case{'remainder has the sign of the dividend', .i8, i8_m7.mod(2), -1},
		Case{'-128 / -1 wraps', .i8, i8_min.div(-1), -128},
		Case{'smallest i32 / -1 wraps', .i32, i32_min.div(i32_m1), -2147483648},
		Case{'division by zero is 0', .u32, u32_five.div(0), 0},
		Case{'remainder by zero is 0', .i32, i32_m5.mod(0), 0},
		Case{'fix division by zero is 0', .fix, one.div(0), 0},
		Case{'unsigned division', .u32, u32_max.div(2), 0x7fff_ffff},
		Case{'shr fills unsigned with 0', .u8, u8_0x81.shr(1), 0x40},
		Case{'shr keeps the sign', .i8, i8_min.shr(1), -64},
		Case{'shl into the sign bit', .i8, i8_one.shl(7), -128},
		Case{'shl out of the type', .u8, u8_one.shl(8), 0},
		Case{'a shift count is masked to 5 bits', .u32, u32_five.shl(u32_33), 10},
		Case{'shr of -1', .i32, i32_m1.shr(31), -1},
		Case{'fix product', .fix, speed.mul(2.25), jaggame.fix_raw(3.375)},
		Case{'fix product rounds down', .fix, tiny.mul(half), 0},
		Case{'a negative one too', .fix, tiny.neg().mul(half), -1},
		Case{'fix quotient rounds toward zero', .fix, one.div(three), 21845},
		Case{'a negative one too', .fix, one.neg().div(three), -21845},
		Case{'fix remainder', .fix, f_m75.mod(2), jaggame.fix_raw(-1.5)},
		Case{'fix with an integer', .fix, speed.add(u8_two), jaggame.fix_raw(3.5)},
		Case{'fix to integer rounds down', .i16, half.neg().as_(.i16), -1},
		Case{'fix to u8', .u8, speed.add(1.25).as_(.u8), 2},
		Case{'narrowing cuts', .u8, i16_300.as_(.u8), 44},
		Case{'i8 to u16', .u16, i8_m1.as_(.u16), 65535},
		Case{'u8 to i8', .i8, u8_255.as_(.i8), -1},
		Case{'integer to fix wraps', .fix, u16_40000.as_(.fix), -1673527296},
		Case{'bool to fix', .fix, t.as_(.fix), jaggame.fix_one},
		Case{'to bool compares with 0', .bool, half.as_(.bool), 1},
		Case{'abs of the smallest', .i16, i16_min.abs(), -32768},
		Case{'neg of the smallest', .i8, i8_min.neg(), -128},
		Case{'unsigned max', .u16, u16_max.max(1), 0xffff},
		Case{'signed min', .i16, i16_m1.min(1), -1},
		Case{'unsigned compare', .bool, u32_top.gt(1), 1},
		Case{'signed compare', .bool, i32_m1.lt(1), 1},
		Case{'either skips its right side', .bool, t.either(bump.call()), 1},
		Case{'both skips its right side', .bool, t.invert().both(bump.call()), 0},
		Case{'both runs its right side', .bool, t.both(bump.call()), 1},
	]
	// guide:end

	main := p.func('main', [], .void)
	mut c := p.define(main)
	for k, row in cases {
		c.set(p.global('case${k}', row.t), row.e)
	}
	// The destination's index is evaluated before the value.
	order := p.array_u8('order', 4)
	next := p.func('next', [], .u8)
	mut n := p.define(next)
	n.inc(counter)
	n.ret(counter)
	c.set(order.at(next.call()), next.call())

	mut it := p.interpreter()!
	it.run('main')!
	img := p.plain_image(main)!
	mut runner := emulated.new()
	runner.run(img.bytes, img.done, 60)!
	ram := runner.ram()
	assert img.differences(it, ram) == []
	mut wrong := []string{}
	for k, row in cases {
		got := it.value('case${k}')!
		if got != row.want {
			wrong << '${row.name}: ${p.show(row.e)} is ${got}, not ${row.want}'
		}
	}
	assert wrong == []
	// bump ran once (the last case); next ran for the index (2), then for the
	// value (3).
	assert it.value('counter')! == 3
	assert it.element('order', 2)! == 3
}
