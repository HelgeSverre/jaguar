module emulated

import hwtypes
import jerry
import loader
import machine

// Player is an emulated machine that a test drives: it boots an image on
// either television standard, runs frames, holds buttons and looks at the
// memory, the picture and the sound.
pub struct Player {
pub mut:
	m &machine.Machine
}

// boot loads an image into a fresh machine of a television standard.
pub fn boot(image []u8, pal bool) !Player {
	plan := loader.plan(image, loader.Options{})!
	mut m := machine.new(machine.Config{
		region: if pal { hwtypes.Region.pal } else { hwtypes.Region.ntsc }
	})
	m.load_direct(plan)
	return Player{
		m: m
	}
}

// frames runs a number of frames. A frame of the emulator ends in the
// middle of the frame interrupt of a game that does real work, so after
// each one the machine runs on until the processor is idle again
// (`settle`): a test then sees the state the interrupt left behind.
pub fn (mut p Player) frames(count int) {
	for _ in 0 .. count {
		p.m.run_frame()
		p.settle()
	}
}

// settle runs the machine on, for at most a frame, until the 68000 has
// stopped to wait for the next interrupt.
pub fn (mut p Player) settle() {
	limit := p.m.tick + p.m.config.region.master_clock_hz() / 60
	for !p.m.cpu.stopped && p.m.tick < limit {
		p.m.advance(p.m.tick + 400, false)
	}
}

// press holds a button of the first pad until `release`.
pub fn (mut p Player) press(button jerry.Button) {
	p.m.set_button(0, button, true)
}

// release lets go of a button of the first pad.
pub fn (mut p Player) release(button jerry.Button) {
	p.m.set_button(0, button, false)
}

// hold holds a button for a number of frames, lets go and runs one more.
pub fn (mut p Player) hold(button jerry.Button, count int) {
	p.press(button)
	p.frames(count)
	p.release(button)
	p.frames(1)
}

// busy_cycles runs a number of frames and returns how many cycles of the
// 68000 a frame used on average: the time it was not stopped, counted in
// steps of 100 cycles.
pub fn (mut p Player) busy_cycles(count int) int {
	mut busy := u64(0)
	for _ in 0 .. count {
		for {
			if !p.m.cpu.stopped {
				busy += 200
			}
			if p.m.advance(p.m.tick + 200, true) == .frame_complete {
				break
			}
		}
	}
	return int(busy / 2 / u64(count))
}

// peek8 reads a byte of main memory.
pub fn (p &Player) peek8(address u32) int {
	return int(p.m.ram[address])
}

// peek16 reads a big-endian word.
pub fn (p &Player) peek16(address u32) int {
	return int((u32(p.peek8(address)) << 8) | u32(p.peek8(address + 1)))
}

// peek32 reads a big-endian long.
pub fn (p &Player) peek32(address u32) u32 {
	return (u32(p.peek16(address)) << 16) | u32(p.peek16(address + 2))
}

// Picture is a frame of the emulator: 0x00RRGGBB pixels.
pub struct Picture {
pub:
	pixels []u32
	width  int
	height int
	pitch  int
}

// picture is the last completed frame.
pub fn (p &Player) picture() Picture {
	pixels, info := p.m.frame()
	return Picture{
		pixels: pixels
		width:  info.width
		height: info.height
		pitch:  info.pitch
	}
}

// at is the pixel at a column and a row, or 0 outside the picture.
pub fn (pic &Picture) at(x int, y int) u32 {
	if x < 0 || y < 0 || x >= pic.width || y >= pic.height {
		return 0
	}
	return pic.pixels[y * pic.pitch + x]
}

// Box is the smallest rectangle around some pixels, and how many there are.
pub struct Box {
pub:
	left   int
	top    int
	right  int // the last column
	bottom int // the last row
	count  int
}

// bounds finds the pixels of a picture that `wanted` accepts, inside a
// rectangle (right and bottom are not included).
pub fn (pic &Picture) bounds(x0 int, y0 int, x1 int, y1 int, wanted fn (pixel u32) bool) Box {
	mut left := pic.width
	mut top := pic.height
	mut right := -1
	mut bottom := -1
	mut count := 0
	for y in y0 .. y1 {
		for x in x0 .. x1 {
			if wanted(pic.at(x, y)) {
				count++
				left = if x < left { x } else { left }
				top = if y < top { y } else { top }
				right = if x > right { x } else { right }
				bottom = if y > bottom { y } else { bottom }
			}
		}
	}
	return Box{left, top, right, bottom, count}
}

// loudest drains the sound made so far and returns the peak sample.
pub fn (mut p Player) loudest() int {
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

// Object is one object of a display list as the object processor reads it.
pub struct Object {
pub:
	address u32
	kind    int // 0 bitmap, 1 scaled bitmap
	ypos    int // half-lines
	height  int // lines
	data    u32
	xpos    int // signed
	depth   int // log2 of the bits a pixel
	iwidth  int // phrases
	dwidth  int
	reflect bool
	trans   bool
	hscale  int // 3.5 fixed point; 0 for an unscaled object
	vscale  int
}

fn (p &Player) phrase(address u32) u64 {
	return (u64(p.peek32(address)) << 32) | u64(p.peek32(address + 4))
}

// list_objects follows a display list from its first slot, after the
// 32-byte header at `base`, through its links and branches, and returns the
// bitmap objects it finds, as they stand in memory now.
pub fn (p &Player) list_objects(base u32) []Object {
	mut found := []Object{}
	mut at := base + 32
	for _ in 0 .. 512 {
		p0 := p.phrase(at)
		kind := int(p0 & 7)
		link := u32(p0 >> 21) & 0x3f_fff8
		match kind {
			0, 1 {
				p1 := p.phrase(at + 8)
				mut xpos := int(p1 & 0xfff)
				if xpos >= 0x800 {
					xpos -= 0x1000
				}
				mut hscale := 0
				mut vscale := 0
				if kind == 1 {
					p2 := p.phrase(at + 16)
					hscale = int(p2 & 0xff)
					vscale = int((p2 >> 8) & 0xff)
				}
				found << Object{
					address: at
					kind:    kind
					ypos:    int((p0 >> 3) & 0x7ff)
					height:  int((p0 >> 14) & 0x3ff)
					data:    u32(p0 >> 43) << 3
					xpos:    xpos
					depth:   int((p1 >> 12) & 7)
					iwidth:  int((p1 >> 28) & 0x3ff)
					dwidth:  int((p1 >> 18) & 0x3ff)
					reflect: p1 & (u64(1) << 45) != 0
					trans:   p1 & (u64(1) << 47) != 0
					hscale:  hscale
					vscale:  vscale
				}
				at = link
			}
			3 {
				at = link
			}
			else {
				break
			}
		}
	}
	return found
}
