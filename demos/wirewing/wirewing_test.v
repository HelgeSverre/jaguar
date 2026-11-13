module main

import hwtypes
import jerry
import loader
import machine
import math

// The game is tested by flying it: the image is built, booted in the
// emulator and flown by reading the game's own variables.

struct Pilot {
	symbols map[string]u32
mut:
	m &machine.Machine
}

fn boot() Pilot {
	return boot_as(.ntsc)
}

fn boot_as(region hwtypes.Region) Pilot {
	built := build() or { panic(err) }
	plan := loader.plan(built.image, loader.Options{}) or { panic(err) }
	mut m := machine.new(machine.Config{ region: region })
	m.load_direct(plan)
	return Pilot{
		symbols: built.symbols
		m:       m
	}
}

fn (p &Pilot) word(name string) int {
	return int(p.m.peek32(p.symbols[name]) >> 16)
}

// offset is how far a wrapping 16-bit coordinate is from another.
fn (p &Pilot) offset(target string, from string) int {
	return int(i16(u16(p.word(target) - p.word(from))))
}

fn (mut p Pilot) frames(count int) {
	for _ in 0 .. count {
		p.m.run_frame()
	}
}

fn (mut p Pilot) tap(button jerry.Button) {
	p.m.set_button(0, button, true)
	p.frames(3)
	p.m.set_button(0, button, false)
	p.frames(3)
}

// ground is the height under the plane, as the game works it out: the
// highest corner of its cell.
fn (p &Pilot) ground() int {
	column := p.word('eye_x') >> 8
	row := p.word('eye_z') >> 8
	mut highest := 0
	for corner in 0 .. 4 {
		x := (column + corner % 2) & (map_size - 1)
		z := (row + corner / 2) & (map_size - 1)
		h := int(p.m.peek8(p.symbols['heights'] + u32(z * map_size + x)))
		highest = math.max(highest, h)
	}
	return int(u32(highest) << height_shift)
}

// fly_to_beacon turns towards the beacon and holds a safe height, coming
// down to the beacon's when it is close.
fn (mut p Pilot) fly_to_beacon() {
	east := f64(p.offset('beacon_x', 'eye_x'))
	north := f64(p.offset('beacon_z', 'eye_z'))
	heading := f64(p.word('heading') >> 8) * 2 * math.pi / 256
	right := east * math.cos(heading) - north * math.sin(heading)
	ahead := east * math.sin(heading) + north * math.cos(heading)
	p.m.set_button(0, .right, right > 30 || (ahead < 0 && right >= 0))
	p.m.set_button(0, .left, right < -30 || (ahead < 0 && right < 0))
	close := math.sqrt(east * east + north * north) < 3 * cell
	wanted := if close { p.word('beacon_y') } else { math.max(p.word('beacon_y'), p.ground() + 250) }
	height := p.word('eye_y') + int(i16(p.word('climb'))) * 6
	p.m.set_button(0, .down, height < wanted - 20) // pull back to climb
	p.m.set_button(0, .up, height > wanted + 20)
}

fn test_title_flies_and_draws() {
	mut p := boot()
	p.frames(90)
	assert p.word('state') == state_title
	assert p.word('frame') > 80, 'the frame interrupt must run once a frame'
	pixels, info := p.m.frame()
	mut lit := 0
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			if pixels[y * info.pitch + x] & 0xffffff != 0 {
				lit++
			}
		}
	}
	assert lit > 2000, 'the landscape and the title must be on screen'
	assert lit < info.width * info.height / 2, 'lines, not a filled screen'

	// The GPU must keep up: a new picture at least every other frame.
	mut pictures := 0
	mut front := p.word('front')
	for _ in 0 .. 120 {
		p.frames(1)
		if p.word('front') != front {
			front = p.word('front')
			pictures++
		}
	}
	println('pictures in 120 frames: ' + pictures.str())
	assert pictures >= 55
}

fn test_a_flown_plane_collects_beacons() {
	mut p := boot()
	p.frames(30)
	p.tap(.b)
	assert p.word('state') == state_play
	started := p.word('frame')
	for _ in 0 .. 2400 {
		p.fly_to_beacon()
		p.frames(1)
	}
	assert p.word('frame') - started == 2400, 'the 68000 must never miss a frame'
	assert p.word('state') == state_play, 'a plane flown with care must stay up'
	assert p.word('score') >= 3
	assert p.word('fuel') > 0
}

fn test_diving_ends_in_the_ground_and_a_remark() {
	mut p := boot()
	p.frames(30)
	p.tap(.b)
	p.m.set_button(0, .up, true) // push forward: dive
	for _ in 0 .. 600 {
		p.frames(1)
		if p.word('state') == state_dead {
			break
		}
	}
	p.m.set_button(0, .up, false)
	p.frames(2) // let the interrupt that noticed finish printing
	assert p.word('state') == state_dead
	assert p.word('crashes') == 1
	assert p.word('eye_y') <= p.ground() + clearance
	// The remark is on screen: its first letter is drawn where it starts.
	column := (text_columns - favourite.len) / 2
	mut ink := 0
	for line in 0 .. 8 {
		ink += int(p.m.peek8(text_address + u32((9 * 8 + line) * text_columns + column)))
	}
	assert ink != 0, 'the first remark must be printed on row 9'

	p.frames(40)
	p.tap(.a)
	assert p.word('state') == state_play
	assert p.word('eye_y') == start_height
}

fn test_the_tank_runs_dry() {
	mut p := boot()
	p.frames(30)
	p.tap(.b)
	p.m.set_button(0, .down, true) // climb and stay up, away from every beacon
	p.frames(full_tank + 60)
	assert p.word('state') == state_dead
	assert p.word('crashes') == 0, 'running dry is not a crash'
}

fn test_it_flies_on_a_pal_machine() {
	mut p := boot_as(.pal)
	p.frames(60)
	assert p.m.peek32(p.symbols['profile']) == p.symbols['profile_pal']
	p.tap(.b)
	assert p.word('state') == state_play
	started := p.word('frame')
	for _ in 0 .. 600 {
		p.fly_to_beacon()
		p.frames(1)
	}
	assert p.word('frame') - started == 600, 'the 68000 must never miss a frame'
	assert p.word('state') == state_play
	pixels, info := p.m.frame()
	mut lit := 0
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			if pixels[y * info.pitch + x] & 0xffffff != 0 {
				lit++
			}
		}
	}
	assert lit > 1000, 'the landscape must be on screen'
}
