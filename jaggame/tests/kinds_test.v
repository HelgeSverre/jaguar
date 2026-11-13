module main

import jaggame
import jaggame.emulated

// Every kind of storage and every loop the language has, in one program run
// both ways: arrays and tables of each width, locals of each type, while,
// repeat, continue, xor and max. Part of the check that every feature in the
// reference is exercised somewhere.

fn kinds_program() (&jaggame.Program, jaggame.Func) {
	mut p := jaggame.new_program()
	a8 := p.array_i8('a8', 4)
	a16 := p.array_i16('a16', 4)
	a32 := p.array_u32('a32', 4)
	b32 := p.array_i32('b32', 4)
	af := p.array_fix('af', 4)
	t16 := p.table_i16('t16', [-5, 300, -32768, 7])
	t32 := p.table_u32('t32', [i64(0xffffffff), 1, 2, 3])
	ti32 := p.table_i32('ti32', [i64(-2147483648), 5, 6, 7])
	tf := p.table_fix('tf', [0.5, -1.25, 2.0, 3.75])
	steps := p.u16('steps')
	odd_sum := p.u16('odd_sum')
	hash := p.u32('hash')
	widest := p.i32('widest')
	halves := p.fix('halves')
	flagged := p.bool('flagged')
	main := p.func('main', [], .void)
	mut c := p.define(main)
	i := c.local_u8('i')
	small := c.local_i8('small')
	mid := c.local_i16('mid')
	big := c.local_u32('big')
	sgn := c.local_i32('sgn')
	frac := c.local_fix('frac')
	flag := c.local_bool('flag')

	c.for_(i, 0, 4)
	c.set(a8.at(i), t16.at(i).as_(.i8))
	c.set(a16.at(i), t16.at(i))
	c.set(a32.at(i), t32.at(i))
	c.set(b32.at(i), ti32.at(i))
	c.set(af.at(i), tf.at(i))
	c.end()

	// while: halve 100 until it is 1
	c.set(big, 100)

	c.while_(big.gt(1))
	c.set(big, big.shr(1))
	c.inc(steps)
	c.end()

	// continue skips the even ones; repeat runs a counted loop
	c.for_(i, 0, 10)

	c.if_(i.and(1).eq(0))
	c.continue_()
	c.end()
	c.add_to(odd_sum, i)
	c.end()
	c.repeat(3)
	c.set(hash, hash.xor(0x5a5a5a5a).add(1))
	c.end()

	// max, locals of each width
	c.set(small, -100)
	c.set(mid, -30000)
	c.set(sgn, -2000000000)
	c.set(widest, sgn.max(small.as_(.i32)).max(mid.as_(.i32)))
	c.set(frac, 0.5)
	c.set(halves, frac.add(frac).add(frac))
	c.set(flag, widest.lt(0))
	c.set(flagged, flag)
	return p, main
}

fn test_every_kind_of_storage_and_loop_runs_the_same_both_ways() {
	p, main := kinds_program()
	mut it := p.interpreter()!
	it.run('main')!
	img := p.plain_image(main)!
	mut runner := emulated.new()
	runner.run(img.bytes, img.done, 600)!
	assert img.differences(it, runner.ram()).len == 0
	assert it.element('a8', 0)! == -5 && it.element('a8', 1)! == 44 && it.element('a8', 2)! == 0
	assert it.element('a16', 2)! == -32768
	assert it.element('a32', 0)! == 0xffffffff
	assert it.element('b32', 0)! == -2147483648
	assert it.element('af', 1)! == jaggame.fix_raw(-1.25)
	assert it.value('steps')! == 6, 'a hundred halved down to one takes six steps'
	assert it.value('odd_sum')! == 25
	assert it.value('hash')! != 0
	assert it.value('widest')! == -100
	assert jaggame.fix_value(it.value('halves')!) == 1.5
	assert it.value('flagged')! == 1
}

fn test_the_types_know_their_sizes_and_limits() {
	assert jaggame.Type.u8.size() == 1 && jaggame.Type.i16.size() == 2
		&& jaggame.Type.fix.size() == 4
	assert jaggame.Type.i8.smallest() == -128 && jaggame.Type.u16.largest() == 65535
	assert jaggame.Type.u8.is_integer() && !jaggame.Type.fix.is_integer()
		&& jaggame.Type.fix.is_number()
	assert jaggame.Type.i32.is_signed() && !jaggame.Type.u32.is_signed()
	assert jaggame.Type.u8.wrap(300) == 44 && jaggame.Type.i8.wrap(200) == -56
	assert jaggame.fix_raw(1.5) == 98304 && jaggame.fix_value(65536) == 1.0
	assert jaggame.all_types.len == 8 && jaggame.fix_one == 65536
}
