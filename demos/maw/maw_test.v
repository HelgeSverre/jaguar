module main

import jerry
import loader
import machine

// The game is tested by playing it: the image is built, booted in the
// emulator and steered by reading the game's own variables.

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

fn (p &Player) gate(i int, field int) int {
	return int(p.m.peek32(p.symbols['gate_${i}'] + u32(field)) >> 16)
}

fn (mut p Player) frames(count int) {
	for _ in 0 .. count {
		p.m.run_frame()
	}
}

fn (mut p Player) tap(button jerry.Button) {
	p.m.set_button(0, button, true)
	p.frames(3)
	p.m.set_button(0, button, false)
	p.frames(3)
}

// steer turns towards the opening of the gate that reaches the ship next.
fn (mut p Player) steer() {
	mut next := 0
	mut nearest := 1000
	for i in 0 .. 2 {
		depth := p.gate(i, gate_depth)
		if depth > ship_depth && depth < nearest {
			next = i
			nearest = depth
		}
	}
	under_ship := (p.word('rotation') >> 8) + ship_angle
	off := int(i8(u8(p.gate(next, gate_gap) - under_ship)))
	// Letting go sheds an eighth of the turn rate a frame, so the ship
	// coasts about eight frames' worth further.
	coast := int(i16(p.word('turn'))) * 8 / 256
	p.m.set_button(0, .left, off - coast > 2)
	p.m.set_button(0, .right, off - coast < -2)
}

fn test_title_waits_and_draws() {
	mut p := boot()
	p.frames(60)
	assert p.word('state') == state_title
	assert p.word('frame') > 50, 'the frame interrupt must run once a frame'
	pixels, info := p.m.frame()
	assert info.width >= 320 && info.height >= 240
	mut lit := 0
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			if pixels[y * info.pitch + x] & 0xffffff != 0 {
				lit++
			}
		}
	}
	assert lit > info.width * info.height / 2, 'the tunnel must fill the screen'
}

fn test_a_steered_ship_scores_and_an_unsteered_one_wrecks() {
	mut p := boot()
	p.frames(30)
	p.tap(.b)
	assert p.word('state') == state_play
	started := p.word('frame')
	for _ in 0 .. 1500 {
		p.steer()
		p.frames(1)
	}
	// Repainting a gate must never make the 68000 miss a frame.
	assert p.word('frame') - started == 1500
	score := p.word('score')
	assert p.word('state') == state_play, 'a ship steered into every opening must survive'
	assert score >= 15
	assert p.word('speed') > first_speed
	assert p.word('gap_half') < widest_gap

	// Let go, facing away from the next opening: the next gate ends it.
	p.m.set_button(0, .left, false)
	p.m.set_button(0, .right, false)
	for _ in 0 .. 1200 {
		p.frames(1)
		if p.word('state') == state_dead {
			break
		}
	}
	assert p.word('state') == state_dead
	assert p.word('best') == p.word('score')

	// The ship blows up, then a fire button starts the next attempt.
	p.frames(10)
	assert p.word('scene') in [scene_blast, scene_blast + 8]
	p.frames(50)
	assert p.word('scene') == scene_wreck
	p.tap(.a)
	assert p.word('state') == state_play
	assert p.word('score') == 0
}

fn test_sound_plays() {
	mut p := boot()
	p.frames(120)
	mut samples := []i16{len: 8192}
	count := p.m.drain_audio(mut samples)
	assert count > 0
	mut loudest := 0
	for s in samples[..count] {
		if s > loudest {
			loudest = s
		}
	}
	assert loudest > 2000, 'the DSP must be making sound'
}
