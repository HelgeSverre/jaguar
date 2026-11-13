module jaggame

import jagkit { abs, at, imm, inc, ind, lbl, ptr }

// The machine side of the runtime: start-up, the frame interrupt, the
// drawing of text rows, the colours and the sound.
//
// All game code runs inside the frame interrupt, one frame at a time, and
// nothing else touches the program's variables once the interrupt is
// enabled; the start-up code runs `rt_init` before that. So the language's
// fixed addresses for parameters and locals are never in use by two things
// at once: a function cannot be interrupted by another that shares them.
// A frame that takes longer than the time between interrupts is counted in
// `missed_frames`; it does not nest.
//
// The interrupt works one frame ahead of the picture. At the end of frame N
// it points the object processor at the list built at the end of frame N-1
// (shown during frame N+1), runs the game, and builds a new list. That way
// the work may last longer than the gap between two pictures without the
// object processor ever reading a list that is half built.

const all_registers = [d0, d1, d2, d3, d4, d5, d6, d7, a0, a1, a2, a3, a4, a5, a6]

// emit_start writes the entry of the program: video, colours, the lists,
// the sound, `rt_init`, the first list, then the interrupt.
fn (g &Game) emit_start(mut m jagkit.M68k, layout Layout, dsp_longs int, dsp_start u32, gpu_longs int, gpu_mailbox u32) {
	m.label('rt.start')
	m.move_to_sr(imm(0x2700))
	m.lea(abs(load_address), jagkit.sp)

	// Which standard? Bit 4 of the buttons register is set on NTSC.
	m.lea(lbl('rt.profile_ntsc'), a0)
	m.move(.w, abs(jagkit.joybuts), d0)
	m.btst(4, d0)
	m.b(.ne, 'rt.standard_known')
	m.lea(lbl('rt.profile_pal'), a0)
	m.move(.b, imm(1), lbl('rt_pal'))
	m.label('rt.standard_known')
	m.move(.w, inc(a0), d0)
	m.move(.w, d0, abs(jagkit.hdb1))
	m.move(.w, d0, abs(jagkit.hdb2))
	m.move(.w, inc(a0), abs(jagkit.hde))
	m.move(.w, inc(a0), abs(jagkit.vdb))
	m.move(.w, imm(0xffff), abs(jagkit.vde))
	m.move(.w, inc(a0), abs(jagkit.vi))
	m.move(.l, inc(a0), lbl('rt.left'))
	m.move(.l, inc(a0), lbl('rt.top'))
	m.move(.l, inc(a0), lbl('rt.template_0'))
	m.move(.l, inc(a0), lbl('rt.template_1'))
	m.move(.l, imm(0), abs(jagkit.bord1))
	m.move(.w, imm(g.config.background), abs(jagkit.bg))

	if g.palette.len > 0 {
		m.lea(lbl('rt.palette'), a0)
		m.lea(abs(jagkit.clut), a1)
		m.move(.w, imm(g.palette.len - 1), d0)
		m.label('rt.copy_palette')
		m.move(.w, inc(a0), inc(a1))
		m.dbra(d0, 'rt.copy_palette')
	}
	if g.texts.len > 0 {
		m.lea(abs(layout.text[0]), a0)
		m.move(.w, imm(int(layout.text_end - layout.text[0]) / 4 - 1), d0)
		m.label('rt.clear_text')
		m.move(.l, imm(0), inc(a0))
		m.dbra(d0, 'rt.clear_text')
	}

	// The two lists: each gets its header; the first is built into, the
	// second is shown next.
	m.move(.l, imm(layout.lists[0]), lbl('rt.back'))
	m.move(.l, lbl('rt.template_0'), lbl('rt.back_template'))
	m.move(.l, imm(layout.lists[1]), lbl('rt.front'))
	m.move(.l, lbl('rt.template_1'), lbl('rt.front_template'))
	for k in 0 .. 2 {
		copy := m.unique('rt.copy_header')
		m.move(.l, lbl('rt.template_${k}'), a0)
		m.lea(abs(layout.lists[k]), a1)
		m.moveq(7, d0)
		m.label(copy)
		m.move(.l, inc(a0), inc(a1))
		m.dbra(d0, copy)
	}

	if g.sounds {
		m.lea(lbl('rt.dsp_program'), a0)
		m.lea(abs(jagkit.dsp_ram), a1)
		m.move(.w, imm(dsp_longs - 1), d0)
		m.label('rt.copy_dsp')
		m.move(.l, inc(a0), inc(a1))
		m.dbra(d0, 'rt.copy_dsp')
		m.move(.l, imm(dsp_start), abs(jagkit.d_pc))
		m.move(.l, imm(jagkit.risc_go), abs(jagkit.d_ctrl))
	}

	if g.backdrop_used {
		g.emit_backdrop_start(mut m, gpu_longs, gpu_mailbox)
	}

	// The game's variables, then the first picture.
	m.jsr(lbl('rt_init'))
	m.bsr('rt.render_text')
	m.bsr('rt.sync_colours')
	m.bsr('rt.build_list')
	m.bsr('rt.swap_lists')
	m.move(.l, lbl('rt.front'), d0)
	m.swap(d0) // the pointer is written with its two words swapped
	m.move(.l, d0, abs(jagkit.olp))
	m.move(.w, imm(jagkit.vmode_cry16), abs(jagkit.vmode))
	m.move(.l, ptr('rt.frame_interrupt'), abs(jagkit.interrupt_vector))
	m.move(.w, imm(jagkit.int1_video), abs(jagkit.int1))
	m.move_to_sr(imm(0x2000))
	m.label('rt.sleep')
	m.stop(0x2000)
	m.bra('rt.sleep')
}

// emit_handler writes the frame interrupt and the small routines it uses.
fn (g &Game) emit_handler(mut m jagkit.M68k) {
	m.label('rt.frame_interrupt')
	m.push(all_registers)
	// Acknowledge the interrupt and let the next one through.
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))
	// Show the list that was finished last time.
	m.move(.l, lbl('rt.front'), d0)
	m.swap(d0)
	m.move(.l, d0, abs(jagkit.olp))

	m.bsr('rt.read_pad')
	m.jsr(lbl('rt_frame'))
	if g.backdrop_used {
		m.bsr('rt.send_backdrop')
	}
	if g.has_tileset {
		m.bsr('rt.render_tiles')
	}
	m.bsr('rt.render_text')
	m.bsr('rt.sync_colours')
	m.bsr('rt.fade_clut')
	if g.sounds {
		m.bsr('rt.send_voices')
	}
	m.bsr('rt.build_list')
	m.bsr('rt.swap_lists')

	// An interrupt that came while we were busy is still waiting.
	m.move(.w, abs(jagkit.int1), d0)
	m.btst(0, d0)
	m.b(.eq, 'rt.on_time')
	m.add(.w, imm(1), lbl('missed_frames'))
	m.label('rt.on_time')
	m.pop(all_registers)
	m.rte()

	m.label('rt.swap_lists')
	m.move(.l, lbl('rt.front'), d0)
	m.move(.l, lbl('rt.back'), lbl('rt.front'))
	m.move(.l, d0, lbl('rt.back'))
	m.move(.l, lbl('rt.front_template'), d0)
	m.move(.l, lbl('rt.back_template'), lbl('rt.front_template'))
	m.move(.l, d0, lbl('rt.back_template'))
	m.rts()
}

// emit_text_routines writes `rt.render_text`, which draws every row of
// every text layer whose `dirty` mark is set into the layer's picture, and
// `rt.sync_colours`, which copies the layers' colour variables into the
// colour table. A cell is a glyph of the font: eight bytes, one a line.
fn (g &Game) emit_text_routines(mut m jagkit.M68k, layout Layout) {
	m.label('rt.render_text')
	for i, t in g.texts {
		rows := m.unique('rt.row')
		cell := m.unique('rt.cell')
		clean := m.unique('rt.clean')
		skip := m.unique('rt.skip_cell')
		cols := t.columns
		m.lea(lbl('${t.name}_dirty'), a0)
		m.lea(lbl('${t.name}_stale'), a1)
		m.lea(lbl('${t.name}_cells'), a2)
		m.move(.l, a2, a4)
		m.lea(abs(layout.text[i]), a3)
		m.move(.l, a3, a5)
		m.move(.w, imm(t.rows - 1), d6)
		m.label(rows)
		m.move(.b, inc(a0), d0)
		m.b(.eq, clean)
		m.clr(.b, at(-1, a0))
		m.move(.w, imm(cols / 4 - 1), d5)
		m.label(cell)
		// Four cells at a time: most groups have nothing to draw.
		m.move(.l, ind(a1), d0)
		m.b(.eq, skip)
		for k in 0 .. 4 {
			next_cell := m.unique('rt.next_cell')
			m.tst(.b, at(k, a1))
			m.b(.eq, next_cell)
			m.clr(.b, at(k, a1))
			m.moveq(0, d0)
			m.move(.b, at(k, a2), d0)
			m.lsl(.w, imm(3), d0)
			m.lea(lbl('rt.font'), a6)
			m.add(.l, d0, a6)
			for line in 0 .. 8 {
				m.move(.b, inc(a6), at(line * cols + k, a3))
			}
			m.label(next_cell)
		}
		m.label(skip)
		m.lea(at(4, a1), a1)
		m.lea(at(4, a2), a2)
		m.lea(at(4, a3), a3)
		m.dbra(d5, cell)
		m.bra('rt.next_${rows}')
		m.label(clean)
		m.lea(at(cols, a1), a1)
		m.label('rt.next_${rows}')
		m.lea(at(cols, a4), a4)
		m.move(.l, a4, a2)
		m.lea(at(8 * cols, a5), a5)
		m.move(.l, a5, a3)
		m.dbra(d6, rows)
	}
	m.rts()

	m.label('rt.sync_colours')
	m.moveq(0, d0)
	m.move(.b, lbl('rt_fade'), d0)
	for i, t in g.texts {
		// A one-bit object with palette 254 - 2i draws its set pixels in colour 255 - 2i.
		m.move(.w, lbl('${t.name}_colour'), d2)
		m.bsr('rt.dim')
		m.move(.w, d2, abs(jagkit.clut + u32(2 * (255 - 2 * i))))
	}
	m.rts()

	// rt.dim scales the intensity (the low byte) of the CRY colour in d2 by
	// d0/16; the colour part (the high byte) stays.
	m.label('rt.dim')
	m.cmp(.b, imm(16), d0)
	m.b(.eq, 'rt.dim_done')
	m.move(.w, d2, d3)
	m.and(.w, imm(0xff), d3)
	m.mulu(d0, d3)
	m.lsr(.w, imm(4), d3)
	m.and(.w, imm(0xff00), d2)
	m.orr(.w, d3, d2)
	m.label('rt.dim_done')
	m.rts()

	// rt.fade_clut puts the palette in the colour table at the brightness
	// `rt_fade` says, when that is not what it holds (the text layers' colours
	// are done by `rt.sync_colours` every frame).
	m.label('rt.fade_clut')
	if g.palette.len > 0 {
		m.moveq(0, d0)
		m.move(.b, lbl('rt_fade'), d0)
		m.cmp(.b, lbl('rt_fade_applied'), d0)
		m.b(.eq, 'rt.fade_done')
		m.move(.b, d0, lbl('rt_fade_applied'))
		m.lea(lbl('rt.palette'), a0)
		m.lea(abs(jagkit.clut), a1)
		m.move(.w, imm(g.palette.len - 1), d1)
		m.label('rt.fade_entry')
		m.move(.w, inc(a0), d2)
		m.bsr('rt.dim')
		m.move(.w, d2, inc(a1))
		m.dbra(d1, 'rt.fade_entry')
		m.label('rt.fade_done')
	}
	m.rts()
}

// profile_for is the display list templates and the numbers of one
// television standard.
struct Profile {
	video  jagkit.Video
	left   int
	top    int
	blobs  [2][]u8
	labels [2]string
}

// templates builds, for a standard, what is copied into each of the two
// lists: the header, the jump to the text and the text objects.
fn (g &Game) profile(video jagkit.Video, layout Layout) !Profile {
	left := (video.width - logical_width) / 2
	top := video.vdb + (video.height - logical_height) / 2 * 2
	mut blobs := [2][]u8{}
	for k in 0 .. 2 {
		base := layout.lists[k]
		mut maps := []jagkit.Bitmap{len: g.slots(), init: jagkit.Bitmap{
			width:  4
			height: 1
		}}
		if g.backdrop_used {
			maps[0] = backdrop_bitmap(left, top)
		}
		for i, t in g.texts {
			maps << jagkit.Bitmap{
				x:           left + t.x
				y:           top + 2 * t.y
				width:       t.columns * 8
				height:      t.rows * 8
				data:        layout.text[i]
				depth:       .bpp1
				palette:     254 - 2 * i
				transparent: true
			}
		}
		list := jagkit.object_list(base, video, maps)!
		text_at := 32 + 32 * g.slots()
		mut blob := list.bytes[..32].clone()
		// The jump: always taken (a line of 0x7ff), to the text or to the stop.
		target := if g.texts.len > 0 { base + u32(text_at) } else { base + 16 }
		jump := u64(3) | (u64(0x7ff) << 3) | (u64(target >> 3) << 24)
		for shift := 56; shift >= 0; shift -= 8 {
			blob << u8(jump >> u32(shift))
		}
		blob << list.bytes[text_at..]
		if g.backdrop_used {
			blob << list.bytes[32..64] // the backdrop's slot, ready to copy
		}
		blobs[k] = blob
	}
	return Profile{
		video:  video
		left:   left
		top:    top
		blobs:  blobs
		labels: ['', '']!
	}
}

// emit_profiles writes the data the start-up code picks from: for each
// standard a record of the display window, where the logical screen starts
// and the two templates.
fn (g &Game) emit_profiles(mut m jagkit.M68k, layout Layout) ! {
	for video in [jagkit.ntsc, jagkit.pal] {
		prof := g.profile(video, layout)!
		name := video.name.to_lower()
		for k in 0 .. 2 {
			m.align(4)
			m.label('rt.template_${name}_${k}')
			m.bytes(prof.blobs[k])
		}
		m.align(2)
		m.label('rt.profile_${name}')
		m.word(video.hdb)
		m.word(video.hde)
		m.word(video.vdb)
		m.word(video.vde | 1) // the interrupt comes after the last line shown
		m.long(u32(prof.left))
		m.long(u32(prof.top))
		m.long_label('rt.template_${name}_0')
		m.long_label('rt.template_${name}_1')
	}
}
