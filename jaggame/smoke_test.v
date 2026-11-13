module jaggame

import jaggame.emulated

fn test_a_small_program_runs_both_ways() {
	mut p := new_program()
	total := p.u32('total')
	half := p.fix('half', 0.5)
	scaled := p.fix('scaled')
	main := p.func('main', [], .void)
	mut c := p.define(main)
	i := c.local_u16('i')
	c.for_(i, 1, 11)
	c.add_to(total, i)
	c.end()
	c.set(scaled, half.mul(total))
	mut it := p.interpreter()!
	it.run('main')!
	assert it.value('total')! == 55
	assert it.value('scaled')! == 55 * fix_one / 2

	img := p.plain_image(main)!
	mut r := emulated.new()
	r.run(img.bytes, img.done, 10)!
	assert img.value(r.ram(), 'total')! == 55
	assert img.value(r.ram(), 'scaled')! == 55 * fix_one / 2
}
