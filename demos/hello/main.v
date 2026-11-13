// HELLO: the smallest complete jagkit program. Two lines of text, a ball
// you move with the pad, and a beep when you press fire. Run it to produce the image:
//
//     v run demos/hello          # writes demos/hello.jag
//
// docs/jagkit.md walks through this file.
module main

import math
import os
import jagkit { abs, at, imm, inc, lbl, ptr }

const d0 = jagkit.d0
const d1 = jagkit.d1
const d7 = jagkit.d7
const a0 = jagkit.a0
const a1 = jagkit.a1
const sp = jagkit.sp

const video = jagkit.ntsc
const load_address = u32(0x4000) // where the image is loaded; the stack grows down from here
const list_address = u32(0x80000) // the display list the object processor reads
const list_bytes = 96 // two branches and a stop, then two bitmaps
const text = jagkit.TextScreen{
	address: 0x81000
	rows:    2
}
const text_colour = 1 // its place in the colour table

// The picture is a little larger than a television shows, so the program
// keeps to the middle of it.
const screen_width = 320
const screen_height = 232
const screen_left = (video.width - screen_width) / 2
const screen_top = (video.height - screen_height) / 2

const ball_size = 32
const speed = 2 // pixels a frame
const beep_note = 81 // the A above concert pitch
const beep_volume = 9000

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/hello.jag' }
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

// ball is the picture: a shaded sphere, 16 bits a pixel. Colour 0 is
// transparent, so the corners stay empty.
fn ball() []u16 {
	mut pixels := []u16{cap: ball_size * ball_size}
	radius := f64(ball_size) / 2
	for y in 0 .. ball_size {
		for x in 0 .. ball_size {
			dx := (x + 0.5 - radius) / radius
			dy := (y + 0.5 - radius) / radius
			if dx * dx + dy * dy > 1 {
				pixels << 0
				continue
			}
			// Lit from the top left.
			height := math.sqrt(1 - dx * dx - dy * dy)
			light := math.max(0.15, (height - 0.5 * dx - 0.5 * dy) / 1.5)
			pixels << jagkit.cry(int(255 * light), int(150 * light), int(40 * light))
		}
	}
	return pixels
}

// Built is the finished image and where its labels ended up; the test
// reads the program's variables through `symbols`.
struct Built {
	image   []u8
	symbols map[string]u32
}

// build assembles the DSP program, the 68000 program and the data into one
// image.
fn build() !Built {
	mut dsp := jagkit.synth()
	mut dsp_code := dsp.assemble()!
	for dsp_code.len % 4 != 0 {
		dsp_code << 0
	}

	mut m := jagkit.new_m68k(load_address)
	start_up(mut m, dsp_code.len / 4, dsp.address_of('start'))
	frame_interrupt(mut m, dsp.address_of('voices'))
	m.pad_reader() // the subroutine `read_pad`, and the variables `pad` and `pressed`
	m.text_routines(text) // `print`, `number` and `clear_text`, and the font

	// Variables: a word each.
	for name, initial in {
		'frame':  0
		'ball_x': (screen_width - ball_size) / 2
		'ball_y': (screen_height - ball_size) / 2
	} {
		m.label(name)
		m.word(initial)
	}

	// Data. Pictures start on a phrase (eight bytes), programs on a long.
	m.align(4)
	m.label('dsp_program')
	m.bytes(dsp_code)
	m.align(8)
	m.label('ball')
	m.bytes(jagkit.big_endian16(ball()))
	// The display list is kept as a master copy; a fresh copy goes to
	// `list_address` every frame.
	list := jagkit.object_list(list_address, video, [
		jagkit.Bitmap{
			width:       ball_size
			height:      ball_size
			data:        m.address_of('ball')
			depth:       .bpp16
			transparent: true
		},
		text.bitmap(screen_left, video.vdb + 2 * (screen_top + 8), text_colour),
	])!
	assert list.bytes.len == list_bytes
	m.label('list')
	m.bytes(list.bytes)

	payload := m.assemble()!
	// Nothing the program writes to may lie on top of the image or of
	// anything else.
	jagkit.check_regions([
		jagkit.Region{'image', load_address, payload.len},
		jagkit.Region{'display list', list_address, list_bytes},
		jagkit.Region{'text', text.address, text.bytes()},
	])!
	return Built{
		image:   jagkit.jag_image(load_address, m.address_of('entry'), payload)
		symbols: m.symbols()
	}
}

// start_up runs once: video, the DSP, the display list, the interrupt.
fn start_up(mut m jagkit.M68k, dsp_longs int, dsp_start u32) {
	m.label('entry')
	m.move_to_sr(imm(0x2700)) // no interrupts yet
	m.lea(abs(load_address), sp)

	// The display window, as the boot ROM would have set it.
	m.move(.w, imm(video.hdb), abs(jagkit.hdb1))
	m.move(.w, imm(video.hdb), abs(jagkit.hdb2))
	m.move(.w, imm(video.hde), abs(jagkit.hde))
	m.move(.w, imm(video.vdb), abs(jagkit.vdb))
	m.move(.w, imm(0xffff), abs(jagkit.vde))
	m.move(.w, imm(video.vde | 1), abs(jagkit.vi)) // interrupt after the last line
	m.move(.l, imm(0), abs(jagkit.bord1))
	m.move(.w, imm(jagkit.cry(0, 0, 60)), abs(jagkit.bg)) // dark blue behind everything

	// The text: it is printed once and stays.
	m.move(.w, imm(jagkit.cry(255, 255, 255)), abs(jagkit.clut + 2 * text_colour))
	m.bsr('clear_text')
	m.print_at(13, 0, 'HELLO, JAGUAR!')
	m.print_at(8, 1, 'ARROWS MOVE. FIRE BEEPS.')

	// The DSP: copy the synthesizer into its RAM and start it.
	m.lea(lbl('dsp_program'), a0)
	m.lea(abs(jagkit.dsp_ram), a1)
	m.move(.w, imm(dsp_longs - 1), d0)
	m.label('copy_dsp')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'copy_dsp')
	m.move(.l, imm(dsp_start), abs(jagkit.d_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.d_ctrl))

	// The display list, then the interrupt that keeps it fresh. The list
	// pointer is written with its two words swapped.
	m.bsr('show')
	m.move(.l, imm((list_address << 16) | (list_address >> 16)), abs(jagkit.olp))
	m.move(.w, imm(jagkit.vmode_cry16), abs(jagkit.vmode))
	m.move(.l, ptr('frame_interrupt'), abs(jagkit.interrupt_vector))
	m.move(.w, imm(jagkit.int1_video), abs(jagkit.int1))
	m.move_to_sr(imm(0x2000))
	// Everything else happens in the interrupt.
	m.label('sleep')
	m.stop(0x2000)
	m.bra('sleep')
}

// frame_interrupt runs once a frame, after the last visible line.
fn frame_interrupt(mut m jagkit.M68k, voices u32) {
	registers := [d0, d1, d7, a0, a1]
	lead_step := abs(voices + u32(jagkit.voice_lead_step))
	lead_volume := abs(voices + u32(jagkit.voice_lead_volume))

	m.label('frame_interrupt')
	m.push(registers)
	// Acknowledge the interrupt and let the next one through.
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))
	m.add(.w, imm(1), lbl('frame'))

	m.bsr('read_pad')
	m.move(.w, lbl('pad'), d7)
	slide(mut m, jagkit.pad_left, 'ball_x', -speed, screen_width - ball_size)
	slide(mut m, jagkit.pad_right, 'ball_x', speed, screen_width - ball_size)
	slide(mut m, jagkit.pad_up, 'ball_y', -speed, screen_height - ball_size)
	slide(mut m, jagkit.pad_down, 'ball_y', speed, screen_height - ball_size)

	// Fire starts a beep; every frame the beep loses an eighth of its
	// volume.
	m.move(.w, lbl('pressed'), d0)
	m.btst(jagkit.pad_fire, d0)
	m.b(.eq, 'no_beep')
	m.move(.l, imm(jagkit.note_step(beep_note)), lead_step)
	m.move(.l, imm(beep_volume), lead_volume)
	m.label('no_beep')
	m.move(.l, lead_volume, d0)
	m.move(.l, d0, d1)
	m.lsr(.l, imm(3), d1)
	m.sub(.l, d1, d0)
	m.move(.l, d0, lead_volume)

	m.bsr('show')
	m.pop(registers)
	m.rte()

	// show copies the master display list into place, because the object
	// processor used up the last copy, and moves the ball in the copy. The
	// ball is the first bitmap, 32 bytes in; its line is in bits 3..13 of its first
	// phrase and its column in bits 0..11 of its second.
	m.label('show')
	m.lea(lbl('list'), a0)
	m.lea(abs(list_address), a1)
	m.moveq(list_bytes / 4 - 1, d0)
	m.label('copy_list')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'copy_list')
	m.lea(abs(list_address + 32), a1)
	m.move(.w, lbl('ball_y'), d0)
	m.add(.w, d0, d0) // the object processor counts half-lines
	m.add(.w, imm(video.vdb + 2 * screen_top), d0)
	m.lsl(.w, imm(3), d0)
	m.and(.w, imm(0xc007), at(6, a1))
	m.orr(.w, d0, at(6, a1))
	m.move(.w, lbl('ball_x'), d0)
	m.add(.w, imm(screen_left), d0)
	m.and(.w, imm(0xf000), at(14, a1))
	m.orr(.w, d0, at(14, a1))
	m.rts()
}

// slide moves a variable by `step` while a pad button is held, as long as
// it stays within 0..limit. This is V writing 68000 code: the function is
// called four times and leaves four copies behind, like a macro.
fn slide(mut m jagkit.M68k, button int, variable string, step int, limit int) {
	skip := m.unique('skip')
	m.btst(button, d7)
	m.b(.eq, skip)
	m.move(.w, lbl(variable), d0)
	if step > 0 {
		m.add(.w, imm(step), d0)
	} else {
		m.sub(.w, imm(-step), d0)
	}
	// Unsigned, so a value below zero is out of range as well.
	m.cmp(.w, imm(limit), d0)
	m.b(.hi, skip)
	m.move(.w, d0, lbl(variable))
	m.label(skip)
}
