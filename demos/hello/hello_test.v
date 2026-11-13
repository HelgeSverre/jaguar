module main

import jerry
import loader
import machine

// The program is tested by running it: the image is built, booted in the
// emulator and driven through the pad, and its variables are read through
// the assembler's symbol table.

struct Player {
	symbols map[string]u32
mut:
	m &machine.Machine
}

fn boot() Player {
	built := build() or { panic(err) }
	plan := loader.plan(built.image, loader.Options{}) or { panic(err) }
	mut m := machine.new(machine.Config{})
	m.load_direct(plan)
	return Player{
		symbols: built.symbols
		m:       m
	}
}

fn (p &Player) word(name string) int {
	return int(p.m.peek32(p.symbols[name]) >> 16)
}

fn (mut p Player) frames(count int) {
	for _ in 0 .. count {
		p.m.run_frame()
	}
}

fn (mut p Player) hold(button jerry.Button, count int) {
	p.m.set_button(0, button, true)
	p.frames(count)
	p.m.set_button(0, button, false)
	p.frames(1)
}

// ball_on_screen is the left edge and the top of the orange pixels, and
// how many there are.
fn (p &Player) ball_on_screen() (int, int, int) {
	pixels, info := p.m.frame()
	mut left := info.width
	mut top := info.height
	mut count := 0
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			pixel := pixels[y * info.pitch + x]
			if (pixel >> 16) & 0xff > (pixel & 0xff) + 20 {
				count++
				if x < left {
					left = x
				}
				if y < top {
					top = y
				}
			}
		}
	}
	return left, top, count
}

// loudest drains the sound made so far and returns its peak.
fn (mut p Player) loudest() int {
	mut samples := []i16{len: 8192}
	mut peak := 0
	for {
		count := p.m.drain_audio(mut samples)
		for s in samples[..count * 2] {
			if s > peak {
				peak = s
			}
		}
		if count < samples.len / 2 {
			break
		}
	}
	return peak
}

fn test_the_ball_is_shown() {
	mut p := boot()
	p.frames(30)
	assert p.word('frame') > 20, 'the interrupt must run once a frame'
	left, top, count := p.ball_on_screen()
	assert count > 600, 'a 32-pixel ball covers about 800 pixels'
	assert count < ball_size * ball_size
	// The emulator shows the middle of the picture, as a television does,
	// so the ball is a few pixels from where the program counts it.
	assert left - p.word('ball_x') in [-2, -1, 0, 1, 2]
	assert top - p.word('ball_y') in [-2, -1, 0, 1, 2]
}

fn test_the_pad_moves_it() {
	mut p := boot()
	p.frames(30)
	x := p.word('ball_x')
	y := p.word('ball_y')
	left, top, _ := p.ball_on_screen()
	p.hold(.right, 10)
	p.hold(.down, 5)
	assert p.word('ball_x') == x + 10 * speed
	assert p.word('ball_y') == y + 5 * speed
	moved_left, moved_top, _ := p.ball_on_screen()
	assert moved_left == left + 10 * speed, 'the picture must follow the variable'
	assert moved_top == top + 5 * speed

	// It stops at the edges.
	p.hold(.left, 400)
	p.hold(.up, 400)
	assert p.word('ball_x') == 0
	assert p.word('ball_y') == 0
	p.hold(.right, 400)
	p.hold(.down, 400)
	assert p.word('ball_x') == screen_width - ball_size
	assert p.word('ball_y') == screen_height - ball_size
}

fn test_fire_beeps() {
	mut p := boot()
	p.frames(30)
	assert p.loudest() < 200, 'silent until fire is pressed'
	p.hold(.a, 10)
	assert p.loudest() > 2000, 'the beep must be heard'
	p.frames(120)
	p.loudest()
	p.frames(10)
	assert p.loudest() < 200, 'and it must fade out'
}
