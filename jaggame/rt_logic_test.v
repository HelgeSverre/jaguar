module jaggame

import jaggame.emulated
import jerry

// The parts of the runtime that are game logic, checked in the interpreter
// and on the machine, on both television standards: seconds, timers,
// animations, the pad, text and the beep.

// logic_game has two sprites, two animations, two timers and a few
// variables that record what the runtime gave the game.
fn logic_game() &Game {
	mut g := new_game(Config{ sprites: 2, layers: 1 })
	g.art_cry('box', 8, 8, 4, []u16{len: 8 * 8 * 4, init: cry(255, 255, 255)})
	g.sequence('blink', [Step{0, 0.1}, Step{1, 0.2}])
	g.sequence('once', [Step{2, 0.1}, Step{3, 0.1}])
	one_and_a_half := g.p.u16('one_and_a_half')
	a_tenth := g.p.u16('a_tenth')
	shots := g.p.u16('shots')
	is_playing := g.p.bool('is_playing')
	shot := g.timer('shot')
	clock := g.timer('clock')
	blinker := g.sprite(0)
	other := g.sprite(1)

	mut c := g.define_init()
	blinker.put(mut c, 'box', 10, 10, 0)
	blinker.play(mut c, 'blink', true)
	other.put(mut c, 'box', 30, 10, 0)

	c = g.define_update()
	c.set(one_and_a_half, g.seconds(1.5))
	c.set(a_tenth, g.seconds(0.1))
	c.set(is_playing, other.playing)

	c.if_(g.pressed(.a))
	shot.start(mut c, g.seconds(1.0))
	c.end()

	c.if_(g.pressed(.b))
	clock.stopwatch(mut c)
	c.end()

	c.if_(g.pressed(.up))
	other.play(mut c, 'once', false)
	c.end()

	c.if_(g.pressed(.down))
	blinker.stop(mut c)
	c.end()

	c.if_(shot.fired)
	c.inc(shots)
	c.end()
	return g
}

// Run is a game in the interpreter, fed a pad one frame at a time.
struct Run {
	game &Game
mut:
	it &Interpreter
}

fn start_run(pal bool) Run {
	mut g := logic_game()
	it := g.interpreter(if pal { Region.pal } else { Region.ntsc }) or { panic(err) }
	return Run{
		game: g
		it:   it
	}
}

fn (mut r Run) frames(count int, held u32) {
	for _ in 0 .. count {
		r.game.step(mut r.it, held) or { panic(err) }
	}
}

fn (r &Run) value(name string) int {
	return int(r.it.value(name) or { panic(err) })
}

fn (r &Run) sprite_frame(i int) int {
	return int(r.it.field('sprites', i, 'frame') or { panic(err) })
}

fn test_seconds_are_frames_of_the_standard_the_game_runs_on() {
	mut ntsc := start_run(false)
	ntsc.frames(1, 0)
	assert ntsc.value('fps') == 60
	assert ntsc.value('one_and_a_half') == 90
	assert ntsc.value('a_tenth') == 6, '0.1 seconds is 6 frames, not the 5 a floor would give'
	mut pal := start_run(true)
	pal.frames(1, 0)
	assert pal.value('fps') == 50
	assert pal.value('one_and_a_half') == 75
	assert pal.value('a_tenth') == 5
}

fn test_seconds_on_the_machine() {
	for pal in [false, true] {
		mut g := logic_game()
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, pal) or { panic(err) }
		p.frames(3)
		ram := p.m.ram
		assert img.value(ram, 'fps')! == if pal {
			50
		} else {
			60
		}
		assert img.value(ram, 'one_and_a_half')! == if pal {
			75
		} else {
			90
		}
		assert img.value(ram, 'a_tenth')! == if pal {
			5
		} else {
			6
		}
		assert img.value(ram, 'rt_pal')! == if pal {
			1
		} else {
			0
		}
	}
}

fn test_a_countdown_fires_once_after_its_time_on_both_standards() {
	for pal in [false, true] {
		second := if pal { 50 } else { 60 }
		mut r := start_run(pal)
		r.frames(1, button_mask(.a)) // frame 1 starts the countdown
		r.frames(second - 1, 0) // frame 50 or 60
		assert r.value('shot_fired') == 0
		assert r.value('shot_left') == 1
		assert r.value('shot_running') == 1
		r.frames(1, 0)
		assert r.value('shot_fired') == 1, 'it fires on the frame its time is up'
		assert r.value('shots') == 1
		assert r.value('shot_running') == 0
		assert r.value('shot_elapsed') == second
		r.frames(1, 0)
		assert r.value('shot_fired') == 0, 'and only on that frame'
		r.frames(second * 3, 0)
		assert r.value('shots') == 1
	}
}

fn test_a_stopwatch_counts_up_until_it_is_stopped() {
	mut r := start_run(false)
	r.frames(10, 0)
	assert r.value('clock_elapsed') == 0, 'a timer that was never started does not run'
	r.frames(1, button_mask(.b))
	r.frames(99, 0)
	assert r.value('clock_elapsed') == 99
	assert r.value('clock_running') == 1
	assert r.value('clock_fired') == 0, 'a stopwatch has no end'
}

fn test_the_timers_agree_on_the_machine() {
	for pal in [false, true] {
		mut g := logic_game()
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, pal) or { panic(err) }
		mut r := start_run(pal)
		p.press(.a)
		p.frames(1)
		p.release(.a)
		r.frames(1, button_mask(.a))
		for _ in 0 .. 120 {
			p.frames(1)
			r.frames(1, 0)
			assert img.value(p.m.ram, 'frame')! == r.value('frame')
			for name in ['shot_left', 'shot_elapsed', 'shot_running', 'shot_fired', 'shots'] {
				assert img.value(p.m.ram, name)! == r.value(name), '${name} at frame ${r.value('frame')}'
			}
		}
		assert r.value('shots') == 1
	}
}

// frames_shown is the frame of sprite 0 after each of `count` frames.
fn (mut r Run) frames_shown(count int) []int {
	mut shown := []int{}
	for _ in 0 .. count {
		r.frames(1, 0)
		shown << r.sprite_frame(0)
	}
	return shown
}

// first_at is the 1-based number of the first frame that shows `frame`.
fn first_at(shown []int, frame int, from int) int {
	for i in from .. shown.len {
		if shown[i] == frame {
			return i + 1
		}
	}
	return -1
}

fn test_an_animation_runs_in_seconds_on_both_standards() {
	for pal in [false, true] {
		first, second := if pal { 5, 10 } else { 6, 12 } // 0.1 and 0.2 seconds in frames
		mut r := start_run(pal)
		shown := r.frames_shown(80)
		assert shown[..first - 1].all(it == 0)
		assert first_at(shown, 1, 0) == first, 'frame 1 after 0.1 seconds'
		assert first_at(shown, 0, first) == first + second, 'and frame 0 again 0.2 seconds later'
		assert first_at(shown, 1, first + second) == 2 * first + second, 'it repeats'
		// One round is 0.3 seconds in either standard.
		assert (first + second) * 10 == if pal {
			150
		} else {
			180
		}
	}
}

fn test_an_animation_that_does_not_repeat_stays_on_its_last_frame() {
	for pal in [false, true] {
		step := if pal { 5 } else { 6 }
		mut r := start_run(pal)
		r.frames(1, button_mask(.up)) // plays `once` on sprite 1
		assert r.sprite_frame(1) == 2
		assert r.value('is_playing') == 0, 'the game sees it a frame late: it asked before it started'
		for _ in 0 .. step - 1 {
			r.frames(1, 0)
		}
		assert r.sprite_frame(1) == 3, 'the second step after ${step} frames'
		assert r.value('is_playing') == 1
		for _ in 0 .. step - 1 {
			r.frames(1, 0)
		}
		assert r.sprite_frame(1) == 3
		r.frames(1, 0)
		r.frames(1, 0)
		assert r.value('is_playing') == 0, 'it has ended'
		assert r.sprite_frame(1) == 3, 'on the last frame'
		r.frames(30, 0)
		assert r.sprite_frame(1) == 3
	}
}

fn test_stop_keeps_the_frame() {
	mut r := start_run(false)
	r.frames(8, 0)
	assert r.sprite_frame(0) == 1
	r.frames(1, button_mask(.down))
	frozen := r.sprite_frame(0)
	r.frames(60, 0)
	assert r.sprite_frame(0) == frozen
}

fn test_animations_agree_on_the_machine() {
	for pal in [false, true] {
		mut g := logic_game()
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, pal) or { panic(err) }
		mut r := start_run(pal)
		for n in 0 .. 70 {
			// Sprite 1 starts its animation on frame 5.
			if n == 4 {
				p.press(.up)
			}
			p.frames(1)
			if n == 4 {
				p.release(.up)
			}
			r.frames(1, if n == 4 { button_mask(.up) } else { 0 })
			for i in 0 .. 2 {
				assert int(img.field(p.m.ram, 'sprites', i, 'frame')!) == r.sprite_frame(i), 'sprite ${i} at frame ${
					n + 1}'
			}
			assert img.value(p.m.ram, 'is_playing')! == r.value('is_playing')
		}
	}
}

fn test_the_pad_is_a_variable_the_interpreter_can_be_fed() {
	mut r := start_run(false)
	mut g := r.game
	assert button_mask(.up) == 1 && button_mask(.right) == 8 && button_mask(.a) == 1 << 16
	assert button_mask(.pause) == 1 << 20
	assert button_mask(.fire) == (1 << 16) | (1 << 17) | (1 << 18)
	r.frames(1, button_mask(.left) | button_mask(.b))
	assert r.value('pad') == int(button_mask(.left) | button_mask(.b))
	assert r.value('pad_pressed') == int(button_mask(.left) | button_mask(.b))
	r.frames(1, button_mask(.left) | button_mask(.c))
	assert r.value('pad_pressed') == int(button_mask(.c)), 'only what went down this frame'
	r.frames(1, 0)
	assert r.value('pad') == 0
	_ = g
}

fn test_the_machine_reads_the_buttons_into_the_pad() {
	mut g := logic_game()
	img := g.build() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(2)
	assert img.value(p.m.ram, 'pad')! == 0
	buttons := {
		'up':     jerry.Button.up
		'down':   .down
		'left':   .left
		'right':  .right
		'a':      .a
		'b':      .b
		'c':      .c
		'option': .option
		'pause':  .pause
		'one':    .one
		'five':   .five
		'zero':   .zero
		'star':   .star
		'hash':   .hash
		'nine':   .nine
		'three':  .three
	}
	masks := {
		'up':     Button.up
		'down':   .down
		'left':   .left
		'right':  .right
		'a':      .a
		'b':      .b
		'c':      .c
		'option': .option
		'pause':  .pause
		'one':    .one
		'five':   .five
		'zero':   .zero
		'star':   .star
		'hash':   .hash
		'nine':   .nine
		'three':  .three
	}
	for name, button in buttons {
		p.press(button)
		p.frames(2)
		assert img.value(p.m.ram, 'pad')! == i64(button_mask(masks[name])), 'while ${name} is held'
		p.release(button)
		p.frames(2)
		assert img.value(p.m.ram, 'pad')! == 0
	}
	// Two at once, and the one-frame `pad_pressed`.
	p.press(.left)
	p.press(.b)
	p.frames(1)
	assert img.value(p.m.ram, 'pad')! == i64(button_mask(.left) | button_mask(.b))
	assert img.value(p.m.ram, 'pad_pressed')! == i64(button_mask(.left) | button_mask(.b))
	p.frames(1)
	assert img.value(p.m.ram, 'pad_pressed')! == 0
}
