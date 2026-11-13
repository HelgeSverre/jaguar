// WIREWING: a wireframe flying game for the Atari Jaguar, written as a V
// program that assembles itself. Run it to produce the image:
//
//     v run demos/wirewing       # writes demos/wirewing.jag
//
// The GPU projects a landscape and draws it in lines (wire.v), the 68000
// flies the plane (flight.v), the DSP hums.
module main

import math
import os
import jagkit

// The beacon is an octahedron: two tips and a square between them.
const beacon_points = 6
const beacon_lines = [u8(0), 2, 0, 3, 0, 4, 0, 5, 1, 2, 1, 3, 1, 4, 1, 5, 2, 3, 3, 4, 4, 5, 5,
	2]

const tallest = 80 // the highest a corner of the landscape gets; the plane starts above it

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/wirewing.jag' }
	built := build() or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(output, built.image) or {
		eprintln(err)
		exit(1)
	}
	println('${output}: ${built.image.len} bytes')
}

// heights is the landscape: rolling hills that repeat every `map_size`
// cells in both directions, a byte a corner.
fn heights() []u8 {
	mut corners := []u8{cap: map_size * map_size}
	turn := 2 * math.pi / map_size
	for z in 0 .. map_size {
		for x in 0 .. map_size {
			rolling := math.sin(x * turn) * math.cos(z * turn * 2) + 0.6 * math.sin((x +
				z) * turn * 2) + 0.4 * math.cos((x - 2 * z) * turn * 3)
			// Squaring pushes the valleys flat and the peaks up.
			level := math.pow((rolling + 2) / 4, 2) * tallest
			corners << u8(math.max(0.0, math.min(f64(tallest), level)))
		}
	}
	return corners
}

// sines is one turn of a sine, 256 steps, as 2.14 fixed-point words.
fn sines() []u16 {
	mut table := []u16{cap: 256}
	for i in 0 .. 256 {
		table << u16(i16(int(math.round(16384 * math.sin(2 * math.pi * f64(i) / 256)))))
	}
	return table
}

// ramp is eight colours from dim to bright, for lines far to near.
fn ramp(r int, g int, b int) []u16 {
	mut colours := []u16{cap: 8}
	for i in 1 .. 9 {
		colours << jagkit.cry(r * (i + 3) / 11, g * (i + 3) / 11, b * (i + 3) / 11)
	}
	return colours
}

// rainbow is one turn of the colour wheel.
fn rainbow(steps int) []u16 {
	mut colours := []u16{cap: steps}
	for i in 0 .. steps {
		phase := 2 * math.pi * f64(i) / steps
		colours << jagkit.cry(int(205 + 50 * math.sin(phase)),
			int(205 + 50 * math.sin(phase + 2.1)), int(205 + 50 * math.sin(phase + 4.2)))
	}
	return colours
}

// banner is a word in the 8x8 font, one bit a pixel, eight characters wide
// at most: one 64-bit phrase a line.
fn banner(word string) []u8 {
	font := jagkit.font_8x8()
	mut bits := []u8{len: 64}
	for i, c in word {
		for y in 0 .. 8 {
			bits[y * 8 + i] = font[(int(c) - jagkit.font_first) * 8 + y]
		}
	}
	return bits
}

// whole_longs pads a program to a multiple of four bytes, for copying.
fn whole_longs(code []u8) []u8 {
	mut padded := code.clone()
	for padded.len % 4 != 0 {
		padded << 0
	}
	return padded
}

// Built is the finished image and where its 68000 labels ended up.
struct Built {
	image   []u8
	symbols map[string]u32
}

// build assembles the three programs and their data into one image.
fn build() !Built {
	mut gpu := wireframe()
	gpu_code := whole_longs(gpu.assemble()!)
	mut dsp := jagkit.synth()
	dsp_code := whole_longs(dsp.assemble()!)
	if gpu_code.len > jagkit.gpu_ram_size || dsp_code.len > jagkit.dsp_ram_size {
		return error('a RISC program does not fit its RAM')
	}

	mut m := jagkit.new_m68k(load_address)
	mut f := Flight{
		m:       m
		mailbox: gpu.address_of('shared')
		voices:  dsp.address_of('voices')
	}
	f.start_up(gpu_code.len / 4, dsp_code.len / 4, dsp.address_of('start'))
	f.frame_interrupt()
	f.colours()
	f.read_pad()
	f.sound()
	f.states()
	f.fly()
	f.beacon()
	f.text_routines()
	f.variables()

	m.label('heights')
	m.bytes(heights())
	m.label('beacon_lines')
	m.bytes(beacon_lines)
	m.align(2)
	m.label('sines')
	m.bytes(jagkit.big_endian16(sines()))
	m.label('greens')
	m.bytes(jagkit.big_endian16(ramp(40, 255, 110)))
	m.label('reds')
	m.bytes(jagkit.big_endian16(ramp(255, 60, 20)))
	m.label('rainbow')
	m.bytes(jagkit.big_endian16(rainbow(64)))
	m.align(4)
	m.label('gpu_program')
	m.bytes(gpu_code)
	m.label('dsp_program')
	m.bytes(dsp_code)
	m.align(8)
	m.label('banner')
	m.bytes(banner('WIREWING'))

	// One set of display lists for each television standard: the title
	// and the flight, for each of the two picture buffers.
	for video in [jagkit.ntsc, jagkit.pal] {
		left := (video.width - screen_width) / 2
		top := video.vdb + (video.height - screen_height) / 2 * 2
		text := jagkit.Bitmap{
			x:           left
			y:           top
			width:       text_columns * 8
			height:      text_rows * 8
			data:        text_address
			depth:       .bpp1
			palette:     colour_text - 1
			transparent: true
		}
		// The same text one pixel down and right, in black.
		shadow := jagkit.Bitmap{
			...text
			x:       left + 1
			y:       top + 2
			palette: colour_shadow - 1
		}
		mut names := []string{}
		for with_banner in [true, false] {
			for b, buffer in [buffer_a, buffer_b] {
				mut bitmaps := [
					jagkit.Bitmap{
						x:      left
						y:      top
						width:  screen_width
						height: screen_height
						data:   buffer
						depth:  .bpp8
					},
				]
				if with_banner {
					bitmaps << jagkit.Bitmap{
						x:           left + (screen_width - 64 * 4) / 2
						y:           top + 2 * 30
						width:       64
						height:      8
						data:        m.address_of('banner')
						depth:       .bpp1
						palette:     colour_logo - 1
						transparent: true
						hscale:      4
						vscale:      4
					}
				}
				bitmaps << shadow
				bitmaps << text
				mut bytes := jagkit.object_list(list_address, video, bitmaps)!.bytes.clone()
				for bytes.len < list_bytes {
					bytes << 0
				}
				name := 'list_${video.name}_${with_banner}_${b}'
				m.label(name)
				m.bytes(bytes)
				names << name
			}
		}
		m.label('profile_${video.name.to_lower()}')
		m.word(video.hdb)
		m.word(video.hde)
		m.word(video.vdb)
		m.word(video.vde | 1)
		for name in names {
			m.long_label(name)
		}
	}

	payload := m.assemble()!
	// Nothing the program writes to may lie on top of the image or of
	// anything else.
	jagkit.check_regions([
		jagkit.Region{'image', load_address, payload.len},
		jagkit.Region{'display list', list_address, list_bytes},
		jagkit.Region{'text', text_address, text_columns * text_rows * 8},
		jagkit.Region{'points', points_address, 0x1000},
		jagkit.Region{'model', model_address, beacon_points * 12},
		jagkit.Region{'buffer a', buffer_a, screen_width * screen_height},
		jagkit.Region{'buffer b', buffer_b, screen_width * screen_height},
	])!
	return Built{
		image:   jagkit.jag_image(load_address, m.address_of('entry'), payload)
		symbols: m.symbols()
	}
}
