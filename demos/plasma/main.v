// PLASMA: a first program for the GPU. The 68000 keeps three numbers
// moving; the GPU turns them into a picture, once a frame. Run it to
// produce the image:
//
//     v run demos/plasma         # writes demos/plasma.jag
//
// docs/jagkit.md walks through this file after demos/hello.
module main

import math
import os
import jagkit { abs, imm, inc, lbl, ptr }

const d0 = jagkit.d0
const d1 = jagkit.d1
const a0 = jagkit.a0
const a1 = jagkit.a1
const sp = jagkit.sp

const load_address = u32(0x4000)
const list_address = u32(0x80000) // the display list the object processor reads
const list_bytes = 64 // two branches, a stop and one bitmap
const buffer = u32(0x90000) // the picture: a colour number a pixel

// The picture is drawn at half size and shown at double size.
const plasma_width = 160
const plasma_height = 100
const magnify = 2

// The values the two processors share, as offsets from the `shared` label
// of the GPU program. The 68000 writes the first six; the GPU counts its
// pictures in the last.
const shared_go = 4 // set by the 68000 when the GPU may draw
const shared_across = 8 // where on the wave the left edge is, 0..255
const shared_down = 12 // where the top edge is
const shared_slant = 16 // where the diagonal wave starts
const shared_wave = 20 // address of the wave table
const shared_buffer = 24 // address of the picture
const shared_drawn = 28 // pictures finished so far

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/plasma.jag' }
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

// painter is the GPU program. A pixel's colour number is the sum of three
// waves: one that depends on its column, one on its row and one on both.
// Each wave is a byte from a table, so a pixel costs two loads, two adds
// and a store.
fn painter() &jagkit.Risc {
	values := jagkit.Reg.r14 // `load_r14` and `store_r14` reach the shared values
	table := jagkit.Reg.r15
	picture := jagkit.Reg.r16
	wait := jagkit.Reg.r17 // jump targets too far away for `jr`
	next_row := jagkit.Reg.r18
	across_start := jagkit.Reg.r19
	down := jagkit.Reg.r20
	slant_start := jagkit.Reg.r21
	target := jagkit.Reg.r22
	rows := jagkit.Reg.r23
	left := jagkit.Reg.r24
	across := jagkit.Reg.r25
	slant := jagkit.Reg.r26
	row_wave := jagkit.Reg.r27
	colour := jagkit.Reg.r0
	other := jagkit.Reg.r1

	mut g := jagkit.new_risc(jagkit.gpu_ram)
	g.movei_label('shared', values)
	g.movei_label('wait', wait)
	g.movei_label('row', next_row)
	g.load_r14(shared_wave, table)
	g.load_r14(shared_buffer, picture)

	// Wait for the 68000 to say go, then take the word back.
	g.label('wait')
	g.load_r14(shared_go, colour)
	g.cmpq(0, colour)
	g.jr(.eq, 'wait')
	g.nop() // every jump runs the instruction after it; here there is nothing to do
	g.moveq(0, colour)
	g.store_r14(colour, shared_go)

	// Three places in the wave table. The table is two waves long, so a
	// place can run 255 bytes on without wrapping.
	g.load_r14(shared_across, across_start)
	g.add(table, across_start)
	g.load_r14(shared_down, down)
	g.add(table, down)
	g.load_r14(shared_slant, slant_start)
	g.add(table, slant_start)
	g.move(picture, target)
	g.movei(plasma_height, rows)

	g.label('row')
	g.loadb(down, row_wave) // this row's share
	g.addqt(1, down)
	g.move(across_start, across)
	g.move(slant_start, slant)
	g.movei(plasma_width, left)

	g.label('pixel')
	g.loadb(across, colour)
	g.addqt(1, across)
	g.loadb(slant, other)
	g.addqt(1, slant)
	g.add(other, colour)
	g.add(row_wave, colour)
	g.storeb(colour, target)
	g.subq(1, left) // sets the flags the jump tests ...
	g.jr(.ne, 'pixel')
	g.addqt(1, target) // ... and this runs either way, without touching them

	g.addqt(1, slant_start) // the diagonal wave starts one further on each row
	g.subq(1, rows)
	g.jump(.ne, next_row)
	g.nop()

	g.load_r14(shared_drawn, colour)
	g.addq(1, colour)
	g.store_r14(colour, shared_drawn)
	g.jump(.always, wait)
	g.nop()

	g.align_long()
	g.label('shared')
	for _ in 0 .. 8 {
		g.long(0)
	}
	return g
}

// wave is two turns of a sine, 256 bytes each, from 0 to 84: three of them
// add up to a colour number below 256.
fn wave() []u8 {
	mut table := []u8{cap: 512}
	for i in 0 .. 512 {
		table << u8(math.round(42 + 42 * math.sin(2 * math.pi * f64(i) / 256)))
	}
	return table
}

// colours is the colour table: twice around the colour wheel.
fn colours() []u16 {
	mut table := []u16{cap: 256}
	for i in 0 .. 256 {
		turn := 4 * math.pi * f64(i) / 256
		table << jagkit.cry(int(128 + 127 * math.sin(turn)), int(128 + 127 * math.sin(turn + 2.1)), int(
			128 + 127 * math.sin(turn + 4.2)))
	}
	return table
}

// Built is the finished image, where the 68000 labels ended up, and the
// address of the values shared with the GPU.
struct Built {
	image   []u8
	symbols map[string]u32
	mailbox u32
}

fn build() !Built {
	mut gpu := painter()
	mut gpu_code := gpu.assemble()!
	for gpu_code.len % 4 != 0 {
		gpu_code << 0
	}
	mailbox := gpu.address_of('shared')

	mut m := jagkit.new_m68k(load_address)
	start_up(mut m, gpu_code.len / 4, mailbox)
	frame_interrupt(mut m, mailbox)

	for name in ['frame', 'across', 'down', 'slant'] {
		m.label(name)
		m.word(0)
	}
	m.label('list') // the address of the master display list, from the profile
	m.long(0)

	m.label('wave')
	m.bytes(wave())
	m.label('colours')
	m.bytes(jagkit.big_endian16(colours()))
	m.align(4)
	m.label('gpu_program')
	m.bytes(gpu_code)

	// A profile for each television standard, as in demos/hello.
	for video in [jagkit.ntsc, jagkit.pal] {
		list := jagkit.object_list(list_address, video, [
			jagkit.Bitmap{
				x:      (video.width - plasma_width * magnify) / 2
				y:      video.vdb + (video.height - plasma_height * magnify) / 2 * 2
				width:  plasma_width
				height: plasma_height
				data:   buffer
				depth:  .bpp8
				hscale: magnify
				vscale: magnify
			},
		])!
		// A scaled bitmap takes three phrases; the list is copied whole.
		assert list.bytes.len == list_bytes
		name := video.name.to_lower()
		m.label('list_${name}')
		m.bytes(list.bytes)
		m.label('profile_${name}')
		m.word(video.hdb)
		m.word(video.hde)
		m.word(video.vdb)
		m.word(video.vde | 1)
		m.long_label('list_${name}')
	}

	payload := m.assemble()!
	jagkit.check_regions([
		jagkit.Region{'image', load_address, payload.len},
		jagkit.Region{'display list', list_address, list_bytes},
		jagkit.Region{'picture', buffer, plasma_width * plasma_height},
	])!
	return Built{
		image:   jagkit.jag_image(load_address, m.address_of('entry'), payload)
		symbols: m.symbols()
		mailbox: mailbox
	}
}

fn start_up(mut m jagkit.M68k, gpu_longs int, mailbox u32) {
	m.label('entry')
	m.move_to_sr(imm(0x2700))
	m.lea(abs(load_address), sp)

	m.lea(lbl('profile_ntsc'), a0)
	m.move(.w, abs(jagkit.joybuts), d0)
	m.btst(4, d0)
	m.b(.ne, 'standard_known')
	m.lea(lbl('profile_pal'), a0)
	m.label('standard_known')
	m.move(.w, inc(a0), d0)
	m.move(.w, d0, abs(jagkit.hdb1))
	m.move(.w, d0, abs(jagkit.hdb2))
	m.move(.w, inc(a0), abs(jagkit.hde))
	m.move(.w, inc(a0), abs(jagkit.vdb))
	m.move(.w, imm(0xffff), abs(jagkit.vde))
	m.move(.w, inc(a0), abs(jagkit.vi))
	m.move(.l, inc(a0), lbl('list'))
	m.move(.l, imm(0), abs(jagkit.bord1))
	m.move(.w, imm(0), abs(jagkit.bg))

	// The colour table: 256 words.
	m.lea(lbl('colours'), a0)
	m.lea(abs(jagkit.clut), a1)
	m.move(.w, imm(255), d0)
	m.label('copy_colours')
	m.move(.w, inc(a0), inc(a1))
	m.dbra(d0, 'copy_colours')

	// The GPU: copy the program into its RAM, tell it where its data is,
	// and start it. It will wait for the first `go`.
	m.lea(lbl('gpu_program'), a0)
	m.lea(abs(jagkit.gpu_ram), a1)
	m.move(.w, imm(gpu_longs - 1), d0)
	m.label('copy_gpu')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'copy_gpu')
	m.move(.l, ptr('wave'), abs(mailbox + shared_wave))
	m.move(.l, imm(buffer), abs(mailbox + shared_buffer))
	m.move(.l, imm(jagkit.gpu_ram), abs(jagkit.g_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.g_ctrl))

	m.bsr('show')
	m.move(.l, imm((list_address << 16) | (list_address >> 16)), abs(jagkit.olp))
	m.move(.w, imm(jagkit.vmode_cry16), abs(jagkit.vmode))
	m.move(.l, ptr('frame_interrupt'), abs(jagkit.interrupt_vector))
	m.move(.w, imm(jagkit.int1_video), abs(jagkit.int1))
	m.move_to_sr(imm(0x2000))
	m.label('sleep')
	m.stop(0x2000)
	m.bra('sleep')
}

// frame_interrupt runs after the last visible line: it moves the three
// waves, hands them to the GPU and says go. The GPU draws from the top,
// faster than the television does, so the picture on screen is never half
// old and half new.
fn frame_interrupt(mut m jagkit.M68k, mailbox u32) {
	registers := [d0, d1, a0, a1]
	m.label('frame_interrupt')
	m.push(registers)
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))
	m.add(.w, imm(1), lbl('frame'))

	// Each wave moves at its own speed; the GPU wants a long from 0 to 255.
	for name, step in {
		'across': 2
		'down':   255 // one back
		'slant':  3
	} {
		m.add(.w, imm(step), lbl(name))
		m.and(.w, imm(255), lbl(name))
	}
	m.moveq(0, d0)
	m.move(.w, lbl('across'), d0)
	m.move(.l, d0, abs(mailbox + shared_across))
	m.move(.w, lbl('down'), d0)
	m.move(.l, d0, abs(mailbox + shared_down))
	m.move(.w, lbl('slant'), d0)
	m.move(.l, d0, abs(mailbox + shared_slant))
	m.move(.l, imm(1), abs(mailbox + shared_go))

	m.bsr('show')
	m.pop(registers)
	m.rte()

	// show copies the master display list into place: the object processor
	// used up the last copy.
	m.label('show')
	m.move(.l, lbl('list'), a0)
	m.lea(abs(list_address), a1)
	m.moveq(list_bytes / 4 - 1, d0)
	m.label('copy_list')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'copy_list')
	m.rts()
}
