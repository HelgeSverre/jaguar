module main

import jagkit { abs, at, idx, imm, inc, lbl }

// Drawing: once a frame the CLUT is animated and a fresh display list is
// built from templates, one object for every note, line, burst and digit.

const template_bytes = 24 // the three phrases of an object, link and position left blank
const prefix_bytes = 32 // the branches at the start of a list, and their stop
const max_drawn_notes = 48
const lane_table_bytes = glow_levels * lane_bands * 2 * 2
const unit_scale = 0x2020 // 1.0 both ways

fn (mut g Game) colours() {
	mut m := g.m
	m.label('colours')
	m.move(.w, lbl('frame'), d0)
	m.lsr(.w, imm(1), d0)
	m.and(.l, imm(63), d0)
	m.add(.w, d0, d0)
	m.lea(lbl('rainbow'), a0)
	m.move(.w, idx(0, a0, d0), abs(jagkit.clut + (clut_text + 1) * 2))

	// Each lane's surface, for its glow.
	m.lea(abs(jagkit.clut + clut_lanes * 2), a1)
	for lane in 0 .. lanes {
		m.lea(lbl('lane_table'), a0)
		m.add(.l, imm(lane * lane_table_bytes), a0)
		m.moveq(0, d0)
		m.move(.w, lbl('lane_glow_${lane}'), d0)
		m.mulu(imm(lane_bands * 4), d0)
		m.add(.l, d0, a0)
		m.moveq(lane_bands * 2 / 2 - 1, d0)
		m.bsr('copy')
	}
	// The targets, for their state.
	m.lea(abs(jagkit.clut + clut_targets * 2), a1)
	for lane in 0 .. lanes {
		m.lea(lbl('target_table'), a0)
		m.add(.l, imm(lane * target_states * 8), a0)
		m.moveq(0, d0)
		m.move(.w, lbl('target_state_${lane}'), d0)
		m.lsl(.w, imm(3), d0)
		m.add(.l, d0, a0)
		m.move(.l, inc(a0), inc(a1))
		m.move(.l, inc(a0), inc(a1))
	}
	// The beat: where in it we are, a sixteenth at a time. A crash
	// brightens it all.
	m.move(.l, lbl('song_rec'), a5)
	m.move(.l, at(rec_phase, a5), a0)
	m.moveq(0, d0)
	m.move(.w, lbl('beat_timer'), d0)
	m.moveq(0, d7)
	m.move(.b, idx(0, a0, d0), d7)
	m.move(.w, d7, lbl('beat_phase'))
	m.cmp(.w, imm(6), lbl('flash'))
	m.b(.ls, 'no_flash')
	m.moveq(0, d7)
	m.label('no_flash')
	// The rails, by multiplier tier.
	m.moveq(0, d0)
	m.move(.w, lbl('tier'), d0)
	m.lsl(.w, imm(4), d0)
	m.add(.w, d7, d0)
	m.lsl(.w, imm(4), d0)
	m.lea(lbl('rail_table'), a0)
	m.add(.l, d0, a0)
	m.lea(abs(jagkit.clut + clut_rails * 2), a1)
	m.moveq(rails_colours / 2 - 1, d0)
	m.bsr('copy')
	// The background, two beats long; on fire in overdrive.
	m.moveq(0, d0)
	m.move(.w, lbl('beat_parity'), d0)
	m.lsl(.w, imm(4), d0)
	m.add(.w, d7, d0)
	m.cmp(.w, imm(multiplier_tiers - 1), lbl('tier'))
	m.b(.ne, 'calm')
	m.add(.w, imm(background_phases), d0)
	m.label('calm')
	m.lsl(.l, imm(7), d0) // 64 colours of two bytes
	m.add(.l, at(rec_theme, a5), d0)
	m.lea(lbl('background_table'), a0)
	m.add(.l, d0, a0)
	m.lea(abs(jagkit.clut + clut_background * 2), a1)
	m.moveq(background_colours / 2 - 1, d0)
	m.bsr('copy')
	// The health meter, by mood; failing, it flashes.
	m.move(.w, lbl('health'), d1)
	m.moveq(0, d0)
	for mood, above in [90, 48, 24] {
		m.cmp(.w, imm(above), d1)
		m.b(.cc, 'mood_known')
		m.moveq(mood + 1, d0)
	}
	m.move(.w, lbl('frame'), d2)
	m.btst(3, d2)
	m.b(.eq, 'mood_known')
	m.moveq(2, d0)
	m.label('mood_known')
	m.lsl(.w, imm(4), d0)
	m.lea(lbl('meter_table'), a0)
	m.add(.l, d0, a0)
	m.lea(abs(jagkit.clut + clut_meter * 2), a1)
	m.moveq(3, d0)
	m.bsr('copy')
	m.rts()
}
