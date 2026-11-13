module main

import hwtypes
import loader
import machine

struct Viewer {
	symbols map[string]u32
	mailbox u32
mut:
	m &machine.Machine
}

fn boot_as(region hwtypes.Region) Viewer {
	built := build() or { panic(err) }
	plan := loader.plan(built.image, loader.Options{}) or { panic(err) }
	mut m := machine.new(machine.Config{ region: region })
	m.load_direct(plan)
	return Viewer{
		symbols: built.symbols
		mailbox: built.mailbox
		m:       m
	}
}

fn (p &Viewer) word(name string) int {
	return int(p.m.peek32(p.symbols[name]) >> 16)
}

fn (mut p Viewer) frames(count int) {
	for _ in 0 .. count {
		p.m.run_frame()
	}
}

// picture is the buffer the GPU draws into.
fn (p &Viewer) picture() []u8 {
	mut bytes := []u8{cap: plasma_width * plasma_height}
	for i in 0 .. plasma_width * plasma_height {
		bytes << p.m.peek8(buffer + u32(i))
	}
	return bytes
}

fn test_the_gpu_draws_a_picture_every_frame() {
	mut p := boot_as(.ntsc)
	p.frames(10)
	drawn := p.m.peek32(p.mailbox + shared_drawn)
	frame := p.word('frame')
	p.frames(60)
	assert p.word('frame') - frame == 60
	assert p.m.peek32(p.mailbox + shared_drawn) - drawn == 60, 'the GPU must finish a picture in a frame'
}

fn test_the_picture_is_what_the_program_says() {
	mut p := boot_as(.ntsc)
	p.frames(30)
	// Work out in V what the GPU should draw from the values it was given.
	// A frame of the emulator ends while the GPU is at work, so the top of
	// the picture is drawn from this frame's values and the rest from the
	// last frame's.
	table := wave()
	across := int(p.m.peek32(p.mailbox + shared_across))
	down := int(p.m.peek32(p.mailbox + shared_down))
	slant := int(p.m.peek32(p.mailbox + shared_slant))
	picture := p.picture()
	mut fresh := 0
	for y in 0 .. plasma_height {
		for x in 0 .. plasma_width {
			now := u8(int(table[across + x]) + int(table[down + y]) + int(table[slant + x + y]))
			before := u8(int(table[((across - 2) & 255) + x]) + int(table[((down + 1) & 255) + y]) +
				int(table[((slant - 3) & 255) + x + y]))
			pixel := picture[y * plasma_width + x]
			assert pixel == now || pixel == before, 'pixel ${x},${y}'
			if pixel == now && pixel != before {
				fresh++
			}
		}
	}
	assert fresh > 0, 'the GPU must have started on the new picture'

	// And it reaches the screen: many colours, nearly no black.
	pixels, info := p.m.frame()
	mut seen := map[u32]bool{}
	mut dark := 0
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			pixel := pixels[y * info.pitch + x] & 0xffffff
			seen[pixel] = true
			if pixel == 0 {
				dark++
			}
		}
	}
	assert seen.len > 100
	assert dark < info.width * info.height / 4, 'the picture is 320 by 200 of 240 lines'
}

fn test_the_picture_moves() {
	mut p := boot_as(.ntsc)
	p.frames(30)
	before := p.picture()
	p.frames(1)
	assert p.picture() != before
}

fn test_it_runs_on_a_pal_machine() {
	mut p := boot_as(.pal)
	p.frames(10)
	assert p.m.peek32(p.symbols['list']) == p.symbols['list_pal']
	drawn := p.m.peek32(p.mailbox + shared_drawn)
	p.frames(50)
	assert p.m.peek32(p.mailbox + shared_drawn) - drawn == 50
}
