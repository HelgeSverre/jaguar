module main

import jagkit { abs, at, imm, inc, lbl }

// The display list is built anew every frame into the list that is not
// being shown. a1 is the next free object slot and a2 the link that slot
// must carry to the one after it; everything that draws keeps them.

fn (mut g Game) emitter() {
	mut m := g.m
	// emit copies the template at a0 into the next slot, at x d0 and
	// half-line d1 from the top left of the picture, with scale d2.
	m.label('emit')
	m.cmp(.l, lbl('list_limit'), a1)
	m.b(.cc, 'emit_full')
	m.add(.w, lbl('screen_left'), d0)
	m.add(.w, lbl('screen_top'), d1)
	m.move(.l, inc(a0), d3)
	m.orr(.l, inc(a2), d3)
	m.move(.l, d3, inc(a1))
	m.move(.l, inc(a0), d3)
	m.orr(.l, inc(a2), d3)
	m.lsl(.w, imm(3), d1)
	m.orr(.w, d1, d3)
	m.move(.l, d3, inc(a1))
	m.move(.l, inc(a0), inc(a1))
	m.move(.l, inc(a0), d3)
	m.and(.w, imm(0xfff), d0)
	m.orr(.w, d0, d3)
	m.move(.l, d3, inc(a1))
	m.move(.l, inc(a0), inc(a1))
	m.move(.l, inc(a0), d3)
	m.orr(.w, d2, d3)
	m.move(.l, d3, inc(a1))
	m.add(.l, imm(8), a1)
	m.label('emit_full')
	m.rts()

	// emit_meter is emit for the health meter: only its bottom d4 lines
	// are shown, so the data starts further in and the height is d4.
	m.label('emit_meter')
	m.add(.w, lbl('screen_left'), d0)
	m.add(.w, lbl('screen_top'), d1)
	m.move(.l, inc(a0), d3)
	m.orr(.l, inc(a2), d3)
	m.move(.l, imm(meter_height), d5)
	m.sub(.l, d4, d5)
	m.lsl(.l, imm(8), d5) // lines skipped, a phrase each, into the data field
	m.lsl(.l, imm(3), d5)
	m.add(.l, d5, d3)
	m.move(.l, d3, inc(a1))
	m.move(.l, inc(a0), d3)
	m.orr(.l, inc(a2), d3)
	m.lsl(.w, imm(3), d1)
	m.orr(.w, d1, d3)
	m.move(.l, d4, d5)
	m.lsl(.l, imm(8), d5)
	m.lsl(.l, imm(6), d5)
	m.orr(.l, d5, d3)
	m.move(.l, d3, inc(a1))
	m.move(.l, inc(a0), inc(a1))
	m.move(.l, inc(a0), d3)
	m.and(.w, imm(0xfff), d0)
	m.orr(.w, d0, d3)
	m.move(.l, d3, inc(a1))
	m.add(.l, imm(16), a1)
	m.rts()
}

fn (mut g Game) list_builder() {
	mut m := g.m
	m.label('build_list')
	m.lea(abs(list_a), a1)
	m.lea(lbl('links_a'), a2)
	m.move(.l, lbl('list_next'), d0)
	m.cmp(.l, imm(list_a), d0)
	m.b(.ne, 'building_known')
	m.lea(abs(list_b), a1)
	m.lea(lbl('links_b'), a2)
	m.label('building_known')
	m.move(.l, a1, lbl('list_building'))
	m.add(.l, imm(prefix_bytes), a1)
	m.move(.l, a1, d0)
	m.add(.l, imm((list_slots - 1) * 32), d0)
	m.move(.l, d0, lbl('list_limit'))

	m.lea(lbl('tpl_stage'), a0)
	m.moveq(0, d0)
	m.moveq(0, d1)
	m.moveq(0, d2)
	m.bsr('emit')
	m.bsr('draw_beams')
	m.move(.w, lbl('state'), d0)
	m.b(.ne, 'not_title')
	m.bsr('draw_title')
	m.bra('drawn')
	m.label('not_title')
	m.cmp(.w, imm(state_select), d0)
	m.b(.ne, 'not_select')
	m.bsr('draw_select')
	m.bra('drawn')
	m.label('not_select')
	m.cmp(.w, imm(state_play), d0)
	m.b(.ne, 'not_play')
	m.bsr('draw_play')
	m.bra('drawn')
	m.label('not_play')
	m.bsr('draw_results')
	m.label('drawn')
	m.lea(lbl('tpl_shadow'), a0)
	m.moveq(1, d0)
	m.moveq(2, d1)
	m.moveq(0, d2)
	m.bsr('emit')
	m.lea(lbl('tpl_text'), a0)
	m.moveq(0, d0)
	m.moveq(0, d1)
	m.moveq(0, d2)
	m.bsr('emit')
	// A stop object ends the list.
	m.move(.l, imm(0), inc(a1))
	m.move(.l, imm(4), jagkit.ind(a1))
	m.move(.l, lbl('list_building'), lbl('list_next'))
	m.rts()
}

fn (mut g Game) beams() {
	mut m := g.m
	// draw_beams flashes a beam of light on every beat, left and right in
	// turn, fading over a quarter of the beat.
	m.label('draw_beams')
	m.moveq(0, d4)
	m.move(.w, lbl('beat_phase'), d4)
	m.lsr(.w, imm(2), d4)
	m.cmp(.w, imm(beam_levels), d4)
	m.b(.cc, 'no_beam')
	m.moveq(0, d0)
	m.move(.w, lbl('beat_parity'), d0)
	m.mulu(imm(beam_levels), d0)
	m.add(.w, d4, d0)
	m.mulu(imm(template_bytes), d0)
	m.lea(lbl('tpl_beams'), a0)
	m.add(.l, d0, a0)
	m.moveq(0, d0)
	m.tst(.w, lbl('beat_parity'))
	m.b(.eq, 'beam_left')
	m.move(.w, imm(screen_width - int(beam_width * beam_scale)), d0)
	m.label('beam_left')
	m.moveq(0, d1)
	scale := fixed_3_5(beam_scale)
	m.move(.w, imm(scale | (scale << 8)), d2)
	m.bsr('emit')
	m.label('no_beam')
	m.rts()
}

// placed emits template a0 at the x, y and scale words of the table entry
// at a3.
fn (mut g Game) placed() {
	mut m := g.m
	m.move(.w, jagkit.ind(a3), d0)
	m.move(.w, at(2, a3), d1)
	m.move(.w, at(4, a3), d2)
	m.bsr('emit')
}
