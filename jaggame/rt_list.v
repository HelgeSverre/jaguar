module jaggame

import jagkit { at, imm, ind, lbl }

// The display list. Every frame the runtime builds a fresh list from the
// visible sprites, because the object processor uses a list up as it draws
// it. Two lists take turns: one is built while the other is shown.
//
// A list is a header of 32 bytes (two branches that keep the object
// processor away outside the picture, and a stop), one 32-byte slot for
// each sprite that is drawn, a jump to the text, and then the objects of
// the text layers, which are copied from a template.
//
//   header | sprite | sprite | ... | jump | (unused slots) | text | text
//                     the sprites drawn this frame            fixed slots

// Where a sprite's fields are in its record.
struct SpriteOffsets {
	x       int
	y       int
	art     int
	frame   int
	layer   int
	visible int
	flip    int
	scale   int
	stride  int
}

fn (g &Game) sprite_offsets() SpriteOffsets {
	r := g.p.records[g.record.id]
	return SpriteOffsets{
		x:       r.offsets[r.field_index('x')]
		y:       r.offsets[r.field_index('y')]
		art:     r.offsets[r.field_index('art')]
		frame:   r.offsets[r.field_index('frame')]
		layer:   r.offsets[r.field_index('layer')]
		visible: r.offsets[r.field_index('visible')]
		flip:    r.offsets[r.field_index('flip')]
		scale:   r.offsets[r.field_index('scale')]
		stride:  r.size
	}
}

// Where the fields of an art's entry in the table `rt.arts` are. An entry is
// 32 bytes.
const art_data = 0 // long: the address of frame 0
const art_frame_bytes = 4 // long
const art_width = 8 // word: pixels
const art_height = 10 // word: lines
const art_line_bytes = 12 // word
const art_frames = 14 // byte
const art_p1_low = 16 // long: the low half of the bitmap's second phrase, without x
const art_p1_high = 20 // long: the high half

// emit_build_list writes the subroutine `rt.build_list`: it builds the
// display list in `rt.back` from the visible sprites, layer by layer and
// in the order of the pool within a layer, then adds the jump to the text
// and copies in the text objects.
//
// Per sprite it works out where the sprite is on the screen. A sprite wholly
// outside the screen is skipped. One that runs off the top or the bottom is
// cut by showing fewer lines (from the first line it can show). One that runs
// off the left or the right is left to the object processor, which clips at
// the edge of its line buffer; its overhang falls in the border of the
// display window, outside the logical screen.
fn (g &Game) emit_build_list(mut m jagkit.M68k) {
	off := g.sprite_offsets()
	last_layer := g.config.layers - 1
	m.label('rt.build_list')
	m.move(.l, lbl('rt.back'), a6)
	m.lea(at(32, a6), a1)
	m.moveq(0, d5)
	m.label('rt.layer')
	m.lea(lbl('sprites'), a0)
	m.move(.w, imm(g.config.sprites - 1), d6)
	m.label('rt.each_sprite')
	m.tst(.b, at(off.visible, a0))
	m.b(.eq, 'rt.next_sprite')
	m.moveq(0, d0)
	m.move(.b, at(off.layer, a0), d0)
	m.cmp(.b, imm(last_layer), d0)
	m.b(.ls, 'rt.layer_known')
	m.moveq(last_layer, d0) // a layer above the last is drawn with the last
	m.label('rt.layer_known')
	m.cmp(.b, d5, d0)
	m.b(.ne, 'rt.next_sprite')
	m.bsr('rt.sprite')
	m.label('rt.next_sprite')
	m.lea(at(off.stride, a0), a0)
	m.dbra(d6, 'rt.each_sprite')
	m.add(.w, imm(1), d5)
	m.cmp(.w, imm(g.config.layers), d5)
	m.b(.ne, 'rt.layer')

	// The jump to the text, and the text.
	m.move(.l, lbl('rt.back_template'), a2)
	m.move(.l, at(32, a2), ind(a1))
	m.move(.l, at(36, a2), at(4, a1))
	if g.texts.len > 0 {
		m.lea(at(40, a2), a2)
		m.lea(at(32 + 32 * (g.config.sprites + 1), a6), a3)
		m.move(.w, imm(g.texts.len * 8 - 1), d0)
		m.label('rt.copy_text')
		m.move(.l, jagkit.inc(a2), jagkit.inc(a3))
		m.dbra(d0, 'rt.copy_text')
	}
	m.rts()

	g.emit_sprite_object(mut m, off)
}

// emit_sprite_object writes `rt.sprite`: it builds the object of the sprite
// at a0 in the slot at a1 and moves a1 on, or leaves it where it is when
// the sprite is off the screen.
fn (g &Game) emit_sprite_object(mut m jagkit.M68k, off SpriteOffsets) {
	m.label('rt.sprite')
	m.push([d5, d6])
	// The art, and the address of the frame.
	m.moveq(0, d0)
	m.move(.b, at(off.art, a0), d0)
	m.lsl(.w, imm(5), d0)
	m.lea(lbl('rt.arts'), a2)
	m.add(.l, d0, a2)
	m.moveq(0, d3)
	m.move(.b, at(off.frame, a0), d3)
	m.cmp(.b, at(art_frames, a2), d3)
	m.b(.cs, 'rt.frame_known')
	m.moveq(0, d3) // a frame the art does not have shows frame 0
	m.label('rt.frame_known')
	m.mulu(at(art_frame_bytes + 2, a2), d3)
	m.add(.l, at(art_data, a2), d3)

	// The scale in 3.5 fixed point, 1..255, in d4.
	m.move(.l, at(off.scale, a0), d4)
	m.lsr(.l, imm(8), d4)
	m.lsr(.l, imm(3), d4)
	m.cmp(.l, imm(255), d4)
	m.b(.ls, 'rt.scale_below')
	m.move(.l, imm(255), d4)
	m.label('rt.scale_below')
	m.tst(.l, d4)
	m.b(.ne, 'rt.scale_known')
	m.moveq(1, d4)
	m.label('rt.scale_known')

	// The size on the screen: width in d1, height in d2.
	m.move(.w, at(art_width, a2), d1)
	m.mulu(d4, d1)
	m.lsr(.l, imm(5), d1)
	m.move(.w, at(art_height, a2), d2)
	m.mulu(d4, d2)
	m.lsr(.l, imm(5), d2)
	m.tst(.l, d1)
	m.b(.eq, 'rt.skip')
	m.tst(.l, d2)
	m.b(.eq, 'rt.skip')

	// Across: off the screen on either side hides the sprite. The position
	// in the display window goes to a3 and the width to a4.
	m.move(.w, at(off.x, a0), d0)
	m.ext(.l, d0)
	m.cmp(.l, imm(logical_width), d0)
	m.b(.ge, 'rt.skip')
	m.move(.l, d0, d6)
	m.add(.l, d1, d6)
	m.b(.le, 'rt.skip')
	m.add(.l, lbl('rt.left'), d0)
	m.move(.l, d0, a3)
	m.move(.l, d1, a4)

	// Down: the source lines to show are in d5, the line to start on in d7.
	m.move(.w, at(off.y, a0), d7)
	m.ext(.l, d7)
	m.cmp(.l, imm(logical_height), d7)
	m.b(.ge, 'rt.skip')
	m.moveq(0, d5)
	m.move(.w, at(art_height, a2), d5)
	m.tst(.l, d7)
	m.b(.pl, 'rt.top_in')
	// Cut the top: leave out the source lines that lie above the screen.
	m.neg(.l, d7)
	m.cmp(.l, d2, d7)
	m.b(.ge, 'rt.skip')
	m.move(.l, d7, d0)
	m.lsl(.l, imm(5), d0)
	m.divu(d4, d0)
	m.and(.l, imm(0xffff), d0)
	m.cmp(.l, d5, d0)
	m.b(.ge, 'rt.skip')
	m.sub(.l, d0, d5)
	m.mulu(at(art_line_bytes, a2), d0)
	m.add(.l, d0, d3)
	m.moveq(0, d7)
	m.label('rt.top_in')
	// Cut the bottom: show only the source lines that end on the screen.
	m.move(.l, imm(logical_height), d0)
	m.sub(.l, d7, d0)
	m.move(.l, d5, d1)
	m.mulu(d4, d1)
	m.lsr(.l, imm(5), d1)
	m.cmp(.l, d0, d1)
	m.b(.ls, 'rt.bottom_in')
	m.lsl(.l, imm(5), d0)
	m.add(.l, d4, d0)
	m.sub(.l, imm(1), d0)
	m.divu(d4, d0)
	m.and(.l, imm(0xffff), d0)
	m.cmp(.l, d5, d0)
	m.b(.ge, 'rt.bottom_in')
	m.move(.l, d0, d5)
	m.label('rt.bottom_in')

	// The first phrase: type, line, height, link, data.
	m.move(.l, d7, d1)
	m.add(.l, d1, d1) // half-lines
	m.add(.l, lbl('rt.top'), d1)
	m.lsl(.l, imm(3), d1)
	m.move(.l, d5, d2)
	m.lsl(.l, imm(8), d2)
	m.lsl(.l, imm(6), d2)
	m.orr(.l, d2, d1)
	m.move(.l, a1, d0)
	m.add(.l, imm(32), d0) // the link: the next slot
	m.move(.l, d0, d2)
	m.lsl(.l, imm(8), d2)
	m.lsl(.l, imm(8), d2)
	m.lsl(.l, imm(5), d2)
	m.orr(.l, d2, d1)
	m.cmp(.l, imm(32), d4)
	m.b(.eq, 'rt.unscaled')
	m.orr(.l, imm(1), d1) // a scaled object
	m.label('rt.unscaled')
	m.move(.l, d1, at(4, a1))
	m.lsr(.l, imm(8), d0)
	m.lsr(.l, imm(3), d0)
	m.move(.l, d3, d1)
	m.lsl(.l, imm(8), d1)
	m.orr(.l, d0, d1)
	m.move(.l, d1, ind(a1))

	// The second phrase: where, how deep, how wide, whether mirrored. A
	// mirrored object is drawn from its right edge to the left.
	m.move(.l, a3, d0)
	m.tst(.b, at(off.flip, a0))
	m.b(.eq, 'rt.not_flipped')
	m.add(.l, a4, d0)
	m.sub(.l, imm(1), d0)
	m.label('rt.not_flipped')
	m.and(.l, imm(0xfff), d0)
	m.orr(.l, at(art_p1_low, a2), d0)
	m.move(.l, d0, at(12, a1))
	m.move(.l, at(art_p1_high, a2), d0)
	m.tst(.b, at(off.flip, a0))
	m.b(.eq, 'rt.not_reflected')
	m.orr(.l, imm(0x2000), d0) // bit 45: reflect
	m.label('rt.not_reflected')
	m.move(.l, d0, at(8, a1))

	// A scaled object has a third phrase: the two scales and the remainder.
	m.cmp(.l, imm(32), d4)
	m.b(.eq, 'rt.slot_done')
	m.clr(.l, at(16, a1))
	m.move(.l, d4, d0)
	m.lsl(.l, imm(8), d0)
	m.orr(.l, d4, d0)
	m.orr(.l, imm(0x200000), d0)
	m.move(.l, d0, at(20, a1))
	m.label('rt.slot_done')
	m.lea(at(32, a1), a1)
	m.label('rt.skip')
	m.pop([d5, d6])
	m.rts()
}

// emit_art_table writes the table the builder reads, the pictures' pixels
// and the profiles of the two television standards, which hold the
// templates of the display lists.
fn (g &Game) emit_art_data(mut m jagkit.M68k) {
	m.align(8)
	for i, a in g.arts {
		m.label('rt.art.${i}')
		m.bytes(a.pixels)
		m.align(8)
	}
	m.align(4)
	m.label('rt.arts')
	for i, a in g.arts {
		per_phrase := 64 / a.bits
		phrases := a.width / per_phrase
		depth := if a.bits == 16 { 4 } else { 3 }
		m.long_label('rt.art.${i}')
		m.long(u32(a.frame_bytes()))
		m.word(a.width)
		m.word(a.height)
		m.word(a.line_bytes())
		m.byte(a.frames)
		m.byte(0)
		m.long((u32(depth) << 12) | (u32(1) << 15) | (u32(phrases) << 18) | (u32(phrases & 0xf) << 28))
		m.long(u32((phrases >> 4) | (1 << 15))) // colour 0 is transparent
		m.long(0)
		m.long(0)
	}
}
