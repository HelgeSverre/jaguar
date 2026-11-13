module jaggame

import jaggame.emulated
import jerry

// Scenes: the order of enter, leave and setup steps, that the machine and
// the interpreter agree, and the mistakes a description can make.

// scene_game has two scenes. `a` waits for the A button; `b` has a setup of
// three steps (the second one waits a frame) and goes back on B. Everything
// that happens is written into `trail`: 1 enter a, 2 leave a, 3 enter b, 10 +
// step for a setup step, 20 for each frame of b's update.
fn scene_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	trail := g.p.array_u8('trail', 32)
	used := g.p.u8('used')
	waited := g.p.bool('waited')
	mut scenes := g.scenes()
	log := g.p.func('log', [Param{'what', .u8}], .void)
	mut c := g.p.define(log)
	c.if_(used.lt(32))
	c.set(trail.at(used), log.arg('what'))
	c.inc(used)
	c.end()

	c = scenes.on_enter('a')
	c.call(log, 1)
	c = scenes.on_leave('a')
	c.call(log, 2)
	c = scenes.on_enter('b')
	c.call(log, 3)
	c.set(waited, false)
	c = scenes.setup('b', 3)

	c.if_(scenes.step.eq(1).both(waited.invert()))
	c.set(waited, true)
	scenes.wait(mut c)
	c.ret_void()
	c.end() // the second step waits once
	c.call(log, scenes.step.add(10).as_(.u8))

	c = scenes.scene('a')
	c.if_(g.pressed(.a))
	scenes.go(mut c, 'b')
	c.ret_void()
	c.end()

	c = scenes.scene('b')
	c.call(log, 20)

	c.if_(g.pressed(.b))
	scenes.go(mut c, 'a')
	c.ret_void()
	c.end()
	scenes.start('a')
	return g
}

fn trail_of(read fn (i int) int, count int) []int {
	mut found := []int{}
	for i in 0 .. count {
		found << read(i)
	}
	return found
}

fn test_scenes_enter_leave_and_set_up_in_order_on_both_sides() {
	mut g := scene_game()
	img := g.build()!
	mut h := scene_game()
	mut it := h.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!

	// A script of pads, one for each frame: idle, A, idle..., B, idle.
	mut script := []u32{}
	script << [u32(0), 0, button_mask(.a)]
	script << []u32{len: 8}
	script << [button_mask(.b), 0, 0]
	for held in script {
		h.step(mut it, held)!
		if held & button_mask(.a) != 0 {
			p.press(jerry.Button.a)
		} else {
			p.release(jerry.Button.a)
		}
		if held & button_mask(.b) != 0 {
			p.press(jerry.Button.b)
		} else {
			p.release(jerry.Button.b)
		}
		p.frames(1)
	}
	used := int(it.value('used')!)
	assert int(img.value(p.m.ram, 'used')!) == used
	machine := trail_of(fn [img, p] (i int) int {
		return int(img.element(p.m.ram, 'trail', i) or { panic(err) })
	}, used)
	interpreter := trail_of(fn [it] (i int) int {
		return int(it.element('trail', i) or { panic(err) })
	}, used)
	assert interpreter == machine
	// a: entered at the start; A: left, b entered; its three steps (the
	// second one a frame late), then its update until B; a is entered again.
	assert machine[..6] == [1, 2, 3, 10, 11, 12]
	assert machine[6..].filter(it == 20).len >= 3, 'the update of b ran: ${machine}'
	assert machine.last() == 1, 'B went back to a: ${machine}'
	assert img.differences(it, p.m.ram) == []
}

fn test_the_update_of_a_scene_waits_for_its_setup() {
	mut g := scene_game()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, 0)!
	g.step(mut it, button_mask(.a))!
	// the second step waits once, so it is seen twice
	for k in [0, 1, 1, 2] {
		assert it.value('scenes_step')! == k, 'step ${k}'
		assert it.value('scenes_steps')! == 3
		g.step(mut it, 0)!
	}
	assert it.value('scenes_step')! == 3
	g.step(mut it, 0)!
	assert it.element('trail', 5)! == 12
}

fn build_error(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}

fn test_scenes_report_their_mistakes_together() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	mut scenes := g.scenes()
	mut c := scenes.scene('title')
	scenes.go(mut c, 'menu')
	c = scenes.scene('title')
	scenes.on_leave('nowhere')
	message := build_error(mut g)
	assert message.contains('the scene `title` is defined twice'), message
	assert message.contains('a transition to the scene `menu`, which does not exist; the scenes are: title'), message
	assert message.contains('on_leave(`nowhere`) belongs to a scene that does not exist'), message
	assert message.contains('there is no start scene; call start(name)'), message
}

fn test_a_start_scene_that_does_not_exist_and_a_game_with_no_scenes_are_refused() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	mut scenes := g.scenes()
	scenes.scene('title')
	scenes.start('intro')
	message := build_error(mut g)
	assert message.contains('the start scene `intro` does not exist; the scenes are: title'), message

	mut h := new_game(Config{ sprites: 1, layers: 1 })
	h.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	h.scenes()
	other := build_error(mut h)
	assert other.contains('there are no scenes'), other
}

// fade_game has a palette, a text layer and two scenes: A on the first goes
// to the second through black, B goes back by a plain `go`. The second has a
// two step setup. `trail` records the scene's name (1, 2) each frame its
// update ran.
fn fade_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.palette([u16(0), cry(200, 100, 50), cry(0, 255, 0)])
	g.art_pal('box', 8, 8, 1, []u8{len: 64, init: 1})
	hud := g.text_layer('hud', TextConfig{
		columns: 8
		rows:    1
		colour:  cry(255, 255, 255)
	})
	trail := g.p.array_u8('trail', 64)
	used := g.p.u8('used')
	mut scenes := g.scenes()
	mut c := scenes.on_enter('second')
	hud.print(mut c, 0, 0, 'TWO')
	c = scenes.setup('second', 2)
	c = scenes.scene('first')
	c.if_(used.lt(64))
	c.set(trail.at(used), 1)
	c.inc(used)
	c.end()

	c.if_(g.pressed(.a))
	scenes.go_fade(mut c, 'second')
	c.end()
	c = scenes.scene('second')
	c.if_(used.lt(64))
	c.set(trail.at(used), 2)
	c.inc(used)
	c.end()

	c.if_(g.pressed(.b))
	scenes.go(mut c, 'first')
	c.end()
	scenes.start('first')
	return g
}

// intensity is the low byte of colour table entry `i` as the machine has it.
fn intensity(p &emulated.Player, i int) int {
	return int(p.m.tom.clut[i]) & 0xff
}

fn test_a_fade_goes_through_black_and_the_colour_table_follows_on_both_sides() {
	mut g := fade_game()
	img := g.build()!
	mut h := fade_game()
	mut it := h.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(2)
	h.step(mut it, 0)!
	h.step(mut it, 0)!
	full := intensity(&p, 1)
	assert full > 40
	text_full := intensity(&p, 255)
	assert text_full > 100
	mut levels := []int{}
	mut shown := []int{}
	mut scenes_seen := []int{}
	for n in 0 .. 60 {
		held := if n == 4 { button_mask(.a) } else { u32(0) }
		h.step(mut it, held)!
		if held != 0 {
			p.press(jerry.Button.a)
		} else {
			p.release(jerry.Button.a)
		}
		p.frames(1)
		p.settle()
		levels << int(it.value('rt_fade')!)
		shown << intensity(&p, 1)
		scenes_seen << int(it.element('scene_state', 0)!)
		assert int(img.value(p.m.ram, 'rt_fade')!) == levels.last(), 'frame ${n}: the brightness is the same on both sides'
	}
	// it dims in steps of 2 down to 0, the scene changes while it is black,
	// and it comes back up, after the two setup steps
	assert levels[..4] == [16, 16, 16, 16]
	assert levels[5..9] == [14, 12, 10, 8]
	assert levels.contains(0)
	first_dark := levels.index(0)
	assert scenes_seen[first_dark - 1] == 0 && scenes_seen[first_dark + 1] == 1, 'the scene changes while it is black: ${scenes_seen[first_dark - 1..
		first_dark + 2]}'

	assert levels.last() == 16
	for k in 0 .. levels.len {
		// the colour table has the brightness the variable says (the machine is a frame
		// behind the settled variable by at most a frame)
		if k > 0 && levels[k] == levels[k - 1] {
			assert shown[k] == full * levels[k] / 16, 'frame ${k}: ${shown[k]} for level ${levels[k]} and full ${full}'
		}
	}
	assert shown[first_dark + 1] == 0, 'black while it is dark'
	assert shown.last() == full, 'and back to the colours as drawn'
	assert intensity(&p, 255) == text_full, 'the text colour is back too'
	mut dark_text := false
	for k, l in levels {
		if l == 0 && k > 0 {
			dark_text = true
		}
	}
	assert dark_text
	// the second scene's update ran only after the fade in finished
	used := int(it.value('used')!)
	assert used > 10
	left := img.differences(it, p.m.ram).filter(!it.contains('_dirty') && !it.contains('_stale'))
	assert left.len == 0, left.join('\n')
}

// The number of the current scene and the test for a scene, as expressions.
fn test_the_current_scene_is_a_number_and_a_scene_can_be_asked_for_by_name() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	now := g.p.u8('now')
	in_b := g.p.bool('in_b')
	mut scenes := g.scenes()
	mut c := scenes.scene('a')
	c.set(now, scenes.current())

	c.if_(g.pressed(.a))
	scenes.go(mut c, 'b')
	c.end()
	c = scenes.scene('b')
	c.set(now, scenes.current())
	c.set(in_b, scenes.in_scene('b'))
	scenes.start('a')
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, 0)!
	g.step(mut it, 0)!
	assert it.value('now')! == 0 && it.value('in_b')! == 0
	g.step(mut it, button_mask(.a))!
	g.step(mut it, 0)!
	assert it.value('now')! == 1 && it.value('in_b')! == 1
}
