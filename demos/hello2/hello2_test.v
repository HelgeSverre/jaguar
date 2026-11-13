module main

import jaggame
import jaggame.emulated
import jagkit
import jerry

// The game is tested by running it: the image is built, booted in the
// emulator on both television standards and driven through the pad, its
// variables are read by name, and the picture is looked at. The same
// logic then runs in the interpreter, with the same buttons, and the two
// must agree.

struct Booted {
	img jaggame.Image
mut:
	p emulated.Player
}

fn boot(pal bool) Booted {
	img := build() or { panic(err) }
	return Booted{
		img: img
		p:   emulated.boot(img.bytes, pal) or { panic(err) }
	}
}

fn (b &Booted) value(name string) int {
	return int(b.img.value(b.p.m.ram, name) or { panic(err) })
}

// sprite_field is a field of a sprite of the pool: 0 the ball, 1 the coin,
// 2 the small ball, 3 the arrow.
fn (b &Booted) sprite_field(i int, name string) int {
	return int(b.img.field(b.p.m.ram, 'sprites', i, name) or { panic(err) })
}

fn is_orange(pixel u32) bool {
	return (pixel >> 16) & 0xff > (pixel & 0xff) + 20
}

fn is_white(pixel u32) bool {
	return pixel & 0xff > 180 && (pixel >> 8) & 0xff > 180 && (pixel >> 16) & 0xff > 180
}

// hide_coin takes the coin out of the picture: it is gold, which is orange
// to a test that looks for the ball.
fn (mut b Booted) hide_coin() {
	b.p.m.ram[b.img.field_address('sprites', 1, 'visible') or { panic(err) }] = 0
}

// ball_on_screen is the left edge and the bottom of the orange pixels: the
// small ball sits above and to the right of the big one, so these two belong
// to the big one.
fn (b &Booted) ball_on_screen() (int, int, int) {
	pic := b.p.picture()
	mut left := pic.width
	mut bottom := 0
	mut count := 0
	for y in 0 .. 190 { // above the yellow numbers
		for x in 0 .. pic.width {
			if is_orange(pic.at(x, y)) {
				left = if x < left { x } else { left }
				bottom = if y > bottom { y } else { bottom }
				count++
			}
		}
	}
	return left, bottom, count
}

fn test_the_game_runs_and_shows_the_ball_on_both_standards() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.p.frames(60)
		assert b.value('frame') == 60, 'one interrupt for each frame'
		b.hide_coin()
		b.p.frames(3)
		assert b.value('missed_frames') == 0
		assert b.value('fps') == if pal {
			50
		} else {
			60
		}
		left, bottom, count := b.ball_on_screen()
		assert count > 600 + 150, 'the ball, and the small one on it'
		x := b.sprite_field(0, 'x')
		y := b.sprite_field(0, 'y')
		// The emulator shows the middle of the display window, as a television
		// does, so the positions differ from the variables by a few pixels.
		assert left - x in [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5]
		bottom_row := bottom - (y + ball_size - 1)
		assert bottom_row > -25 && bottom_row < 25
	}
}

// The guide shows this one: a game booted on a PAL machine and driven through the pad.
fn test_the_guide_boots_it_and_presses_a_button() {
	// guide:boot
	img := build()!
	mut p := emulated.boot(img.bytes, true)! // true: a PAL machine
	p.frames(30)
	assert img.value(p.m.ram, 'fps')! == 50
	x := img.field(p.m.ram, 'sprites', 0, 'x')!

	p.hold(.right, 10) // hold the right key for ten frames
	p.frames(3)
	assert img.field(p.m.ram, 'sprites', 0, 'x')! == x + 10 * speed
	// guide:end
}

fn test_the_guide_runs_the_logic_in_the_interpreter() {
	// guide:interpreter
	mut game := describe()
	mut it := game.interpreter(.ntsc)!
	for _ in 0 .. 50 {
		game.step(mut it, jaggame.button_mask(.right))!
	}
	assert it.field('sprites', 0, 'x')! == 144 + 50 * speed
	assert it.value('frame')! == 50
	// guide:end
}

fn test_the_pad_moves_the_ball() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.p.frames(30)
		b.hide_coin()
		b.p.frames(3)
		x := b.sprite_field(0, 'x')
		y := b.sprite_field(0, 'y')
		left, bottom, _ := b.ball_on_screen()
		b.p.hold(.right, 10)
		b.p.hold(.down, 5)
		b.p.frames(3)
		assert b.sprite_field(0, 'x') == x + 10 * speed
		assert b.sprite_field(0, 'y') == y + 5 * speed
		moved_left, moved_bottom, _ := b.ball_on_screen()
		assert moved_left == left + 10 * speed, 'the picture follows the variable'
		assert moved_bottom == bottom + 5 * speed

		// It stops at the edges.
		b.p.hold(.left, 400)
		b.p.hold(.up, 400)
		assert b.sprite_field(0, 'x') == 0
		assert b.sprite_field(0, 'y') == 0
		b.p.hold(.right, 400)
		b.p.hold(.down, 400)
		assert b.sprite_field(0, 'x') == jaggame.logical_width - ball_size
		assert b.sprite_field(0, 'y') == jaggame.logical_height - ball_size
		assert b.value('missed_frames') == 0
	}
}

fn test_the_small_ball_rides_on_the_big_one_and_is_cut_at_the_edge() {
	mut b := boot(false)
	b.p.frames(10)
	assert b.sprite_field(2, 'x') == b.sprite_field(0, 'x') + 24
	b.p.hold(.up, 400)
	b.p.frames(3)
	assert b.sprite_field(2, 'y') == -6
	front := b.p.peek32(b.img.symbols['rt.front'])
	objects := b.p.list_objects(front)
	small := objects.filter(it.kind == 1)
	assert small.len == 1, 'one scaled object'
	assert small[0].hscale == 16, 'half size'
	assert small[0].height == 20, 'six of its sixteen lines are above the screen: twelve of the 32 lines of the picture, and 20 are left'
}

fn test_the_layers_are_drawn_in_order() {
	mut b := boot(false)
	b.p.frames(5)
	front := b.p.peek32(b.img.symbols['rt.front'])
	objects := b.p.list_objects(front)
	art := fn [b] (n int) u32 {
		return b.img.symbols['rt.art.${n}']
	}
	// The coin (layer 0), the ball (1), the small ball (2), the arrow (3), the two texts.
	assert objects.map(it.data)[..4] == [art(1), art(0), art(0),
		art(2)]
	assert objects.len == 6
	assert objects[4].depth == 0 && objects[5].depth == 0
}

fn test_fire_beeps() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.p.frames(30)
		assert b.p.loudest() < 200, 'silent until fire is pressed'
		b.p.hold(.a, 10)
		assert b.p.loudest() > 2000, 'the beep must be heard'
		b.p.frames(120)
		b.p.loudest()
		b.p.frames(10)
		assert b.p.loudest() < 200, 'and it must fade out'
	}
}

fn test_the_text_is_printed() {
	mut b := boot(false)
	b.p.frames(10)
	pic := b.p.picture()
	box := pic.bounds(0, 0, pic.width, 40, is_white)
	assert box.count == glyph_pixels('HELLO, JAGUAR!') + glyph_pixels('ARROWS MOVE. FIRE BEEPS.')
	// The HUD is yellow.
	hud := pic.bounds(0, 180, pic.width, pic.height, fn (px u32) bool {
		return (px >> 16) & 0xff > 150 && (px >> 8) & 0xff > 120 && px & 0xff < 120
	})
	assert hud.count > 100
}

fn test_the_numbers_count() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.p.frames(60)
		row := fn [b] (r int) []int {
			mut cells := []int{}
			for i in 0 .. 24 {
				cells << int(b.img.element(b.p.m.ram, 'hud_cells', r * 24 + i) or { panic(err) })
			}
			return cells
		}
		assert row(0)[7..12] == [0, 0, 0, 22, 16], 'FRAMES 60: the digits 6 and 0 are glyphs 22 and 16'
		assert row(1)[8..11] == [0, 0, 17], 'one second on both standards: whole seconds of the stopwatch'
		b.p.frames(if pal { 125 - 60 } else { 150 - 60 }) // two and a half seconds
		assert b.value('beats') == 5, 'a beat every half second: 5 in 2.5 seconds at either rate'
	}
}

fn test_the_coin_spins_at_the_same_speed_on_both_standards() {
	for pal in [false, true] {
		step := if pal { 5 } else { 6 } // 0.1 seconds
		mut b := boot(pal)
		mut seen := []int{}
		for _ in 0 .. 5 * step * 2 {
			b.p.frames(1)
			seen << b.sprite_field(1, 'frame')
		}
		assert seen.len > 0
		// Each frame of the coin is shown for 0.1 seconds, in order, round and round.
		mut runs := []int{}
		mut length := 1
		for i in 1 .. seen.len {
			if seen[i] == seen[i - 1] {
				length++
			} else {
				runs << length
				length = 1
			}
		}
		assert runs.len >= 6
		for run in runs[1..] {
			assert run == step
		}
		assert runs[0] == step - 1, 'the first step has already lost the frame in which it started'
		assert 0 in seen && 3 in seen
	}
}

// pad_script is what the player does, one entry for each frame: the buttons held.
fn pad_script() []u32 {
	mut script := []u32{}
	script << []u32{len: 20}
	script << []u32{len: 30, init: jaggame.button_mask(.right)}
	script << []u32{len: 20, init: jaggame.button_mask(.down) | jaggame.button_mask(.right)}
	script << []u32{len: 1, init: jaggame.button_mask(.a)}
	script << []u32{len: 10}
	script << []u32{len: 80, init: jaggame.button_mask(.left)}
	script << []u32{len: 60, init: jaggame.button_mask(.up) | jaggame.button_mask(.left)}
	script << []u32{len: 20}
	script << []u32{len: 160, init: jaggame.button_mask(.right)}
	return script
}

// hold_pad presses exactly the buttons of a pad value on the first pad.
fn hold_pad(mut p emulated.Player, mask u32) {
	for i, button in [jaggame.Button.up, .down, .left, .right, .a] {
		real := [jerry.Button.up, .down, .left, .right, .a][i]
		if mask & jaggame.button_mask(button) != 0 {
			p.press(real)
		} else {
			p.release(real)
		}
	}
}

// What the machine did and what the interpreter does, frame for frame with
// the same pad, must be the same: the game logic is tested twice.
fn test_the_interpreter_does_what_the_machine_did() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut g := describe()
		mut it := g.interpreter(if pal { jaggame.Region.pal } else { jaggame.Region.ntsc })!
		script := pad_script()
		// guide:compare
		for n, mask in script {
			hold_pad(mut b.p, mask)
			b.p.frames(1)
			g.step(mut it, mask)!
			assert b.value('frame') == n + 1
		}
		mut differences := b.img.differences(it, b.p.m.ram)
		// The machine marks a text row done when it has drawn it.
		differences = differences.filter(!it.contains('_dirty'))
		assert differences.len == 0, differences.join('\n')
		// guide:end
		assert b.value('frame') == script.len
		// And the game did what the pad said: it went somewhere and the numbers counted.
		period := if pal { 25 } else { 30 } // frames in half a second
		assert b.value('beats') == script.len / period
		assert it.value('beats')! == b.value('beats')
		assert b.sprite_field(0, 'x') > 0
	}
}

// glyph_pixels is the number of set pixels in the font for a string.
fn glyph_pixels(text string) int {
	font := jagkit.font_8x8()
	mut count := 0
	for ch in text {
		for row in 0 .. 8 {
			mut bits := font[(int(ch) - 32) * 8 + row]
			for bits != 0 {
				count += int(bits & 1)
				bits >>= 1
			}
		}
	}
	return count
}

fn test_a_frame_of_work_is_a_small_part_of_a_frame() {
	mut b := boot(false)
	b.p.frames(10)
	cycles := b.p.busy_cycles(30)
	assert cycles < 100000, 'cycles a frame: ${cycles}'
}
