module jaggame

import jaggame.emulated
import jagkit { imm, lbl }

// The runtime keeps its own values in a5, a6 and d7 and calls compiled
// functions from its frame interrupt, so compiled code and every helper
// routine must leave those three registers alone. `asm` statements set
// them before the work and save them after it.

fn test_compiled_code_leaves_a5_a6_and_d7_alone() {
	mut p := new_program()
	big := p.u32('big', 123456789)
	thousand := p.u32('thousand', 1000)
	negative := p.i32('negative', -77777)
	f := p.fix('f', 3.25)
	result := p.u32('result')
	kept_d7 := p.u32('kept_d7')
	kept_a5 := p.u32('kept_a5')
	kept_a6 := p.u32('kept_a6')

	// work uses all five helper routines and calls another function.
	square := p.func('square', [Param{'v', .fix}], .fix)
	mut c := p.define(square)
	c.ret(square.arg('v').mul(square.arg('v')))
	work := p.func('work', [Param{'x', .u32}], .u32)
	c = p.define(work)
	x := work.arg('x')
	c.ret(x.mul(big).div(thousand).add(negative.div(-3).mod(7).as_(.u32)).add(square.call(f).div(f.add(1)).as_(.u32)))

	main := p.func('main', [], .void)
	c = p.define(main)
	c.asm(fn (mut m jagkit.M68k) {
		m.move(.l, imm(0x7777_7777), jagkit.d7)
		m.lea(jagkit.abs(0x55_5554), jagkit.a5)
		m.lea(jagkit.abs(0x66_6666), jagkit.a6)
	})
	c.set(result, work.call(thousand))
	c.asm(fn (mut m jagkit.M68k) {
		m.move(.l, jagkit.d7, lbl('kept_d7'))
		m.move(.l, jagkit.a5, lbl('kept_a5'))
		m.move(.l, jagkit.a6, lbl('kept_a6'))
	})
	_ = kept_d7
	_ = kept_a5
	_ = kept_a6

	img := p.plain_image(main)!
	mut runner := emulated.new()
	runner.run(img.bytes, img.done, 60)!
	ram := runner.ram()
	assert img.value(ram, 'kept_d7')! == 0x7777_7777
	assert img.value(ram, 'kept_a5')! == 0x55_5554
	assert img.value(ram, 'kept_a6')! == 0x66_6666
	// 1000 * 123456789 wraps to 1234567890 * 100 mod 2^32; the rest by hand.
	product := (u64(1000) * 123456789) & 0xffff_ffff
	squared := (i64(fix_raw(3.25)) * fix_raw(3.25)) >> 16
	quotient := (squared * fix_one) / fix_raw(4.25)
	expected := (product / 1000 + u64(-77777 / -3 % 7) + u64(quotient >> 16)) & 0xffff_ffff
	assert img.value(ram, 'result')! == i64(expected)
}

fn test_the_interpreter_cannot_run_asm() {
	mut p := new_program()
	main := p.func('main', [], .void)
	mut c := p.define(main)
	c.asm(fn (mut m jagkit.M68k) {
		m.nop()
	})
	mut it := p.interpreter()!
	it.run('main') or {
		assert err.msg() == 'the interpreter cannot run an asm statement'
		return
	}
	assert false
}
