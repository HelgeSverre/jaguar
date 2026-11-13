module jaggame

import jaggame.emulated

// The cost of showing a number that changes every frame, and that the
// machine's digits are the interpreter's.

// counting_game shows `n` on every frame, in a layer of 24 cells. `mode`
// says how n changes: 0 it does not change, 1 it counts up by one, 2 every
// digit changes but the number stays below 65536, 3 the same with a number
// that fills 32 bits (two divisions for each digit).
fn counting_game(print bool, mode int) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	n := g.p.u32('n', 12345)
	hud := g.text_layer('hud', TextConfig{ columns: 24, rows: 3, x: 8, y: 16 })
	mut c := g.define_update()
	if mode == 1 {
		c.inc(n)
	} else if mode == 2 {
		c.set(n, n.mul(7).add(13).and(0xffff))
	} else if mode == 3 {
		c.set(n, n.mul(7).add(13))
	}
	if print {
		hud.number(mut c, 7, 1, n, 5)
	}
	return g
}

fn cycles_of(print bool, mode int) int {
	mut g := counting_game(print, mode)
	img := g.build() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(10)
	return p.busy_cycles(30)
}

fn test_a_number_that_changes_every_frame_costs_a_fifth_of_what_it_did() {
	// Slice 2 measured about 17,000 cycles a frame for a number that
	// changed every frame (compiled division for each digit, and the whole
	// row drawn again).
	counting := cycles_of(true, 1) - cycles_of(false, 1)
	churning := cycles_of(true, 2) - cycles_of(false, 2)
	wide := cycles_of(true, 3) - cycles_of(false, 3)
	still := cycles_of(true, 0) - cycles_of(false, 0)
	println('number: counting ${counting}, every digit ${churning}, a 32-bit value ${wide}, unchanged ${still} cycles')
	assert counting < 3400, 'counting: ${counting}'
	assert churning < 3400, 'every digit changes: ${churning}'
	assert wide < 4500, 'a 32-bit value: ${wide}'
	assert still < 1800, 'unchanged: ${still}'
}

fn test_the_machine_shows_the_digits_the_interpreter_computes() {
	mut g := counting_game(true, 3)
	img := g.build() or { panic(err) }
	mut it := g.interpreter(.ntsc) or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	// n grows past 65535 within a few frames, so both division paths run.
	for _ in 0 .. 40 {
		p.frames(1)
		g.step(mut it, 0)!
	}
	mut differences := img.differences(it, p.m.ram)
	differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale'))
	assert differences.len == 0, differences.join('\n')
}
