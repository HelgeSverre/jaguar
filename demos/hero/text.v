module main

import jagkit { abs, at, idx, imm, inc, ind, lbl }

// Text on the two-bit layer, numbers, and the variables of the game.

fn (mut g Game) text_routines() {
	mut m := g.m
	// print draws the zero-terminated string at a0 at column d0, row d1, in
	// colour d2 (1..3).
	m.label('print')
	m.and(.l, imm(0xffff), d1)
	m.mulu(imm(text_line_bytes * 8), d1)
	m.and(.l, imm(0xffff), d0)
	m.add(.l, d0, d1)
	m.add(.l, d0, d1)
	m.lea(abs(text_address), a1)
	m.add(.l, d1, a1)
	m.sub(.w, imm(1), d2)
	m.and(.l, imm(3), d2)
	m.mulu(imm(font_count * 16), d2)
	m.lea(lbl('font'), a2)
	m.add(.l, d2, a2)
	m.label('print_next')
	m.moveq(0, d3)
	m.move(.b, inc(a0), d3)
	m.b(.eq, 'print_done')
	m.sub(.w, imm(font_first), d3)
	m.lsl(.w, imm(4), d3)
	m.lea(idx(0, a2, d3), a3)
	for row in 0 .. 8 {
		m.move(.w, inc(a3), at(row * text_line_bytes, a1))
	}
	m.add(.l, imm(2), a1)
	m.bra('print_next')
	m.label('print_done')
	m.rts()

	// number writes d0 as d4 digits, leading zeros blank, and leaves a0
	// pointing at them. It changes only d0..d3, a0 and a1.
	m.label('number')
	m.lea(lbl('digits_end'), a0)
	m.move(.w, d4, d1)
	m.sub(.w, imm(1), d1)
	m.label('number_digit')
	// d0 / 10 in two halves, as divu only gives a word of quotient.
	m.move(.l, d0, d2)
	m.clr(.w, d2)
	m.swap(d2)
	m.divu(imm(10), d2)
	m.move(.w, d2, d3)
	m.move(.w, d0, d2)
	m.divu(imm(10), d2)
	m.moveq(0, d0)
	m.move(.w, d3, d0)
	m.swap(d0)
	m.move(.w, d2, d0)
	m.swap(d2)
	m.add(.b, imm(int(`0`)), d2)
	m.move(.b, d2, jagkit.dec(a0))
	m.dbra(d1, 'number_digit')
	m.move(.l, a0, a1)
	m.move(.w, d4, d1)
	m.sub(.w, imm(2), d1)
	m.b(.mi, 'number_done')
	m.label('number_blank')
	m.cmp(.b, imm(int(`0`)), ind(a1))
	m.b(.ne, 'number_done')
	m.move(.b, imm(int(` `)), inc(a1))
	m.dbra(d1, 'number_blank')
	m.label('number_done')
	m.rts()
	m.label('digits')
	m.bytes([]u8{len: 8})
	m.label('digits_end')
	m.byte(0)
	m.align(2)

	m.label('clear_text')
	m.lea(abs(text_address), a0)
	m.move(.w, imm(text_bytes / 32 - 1), d0)
	m.moveq(0, d1)
	m.label('clear_text_row')
	for _ in 0 .. 8 {
		m.move(.l, d1, inc(a0))
	}
	m.dbra(d0, 'clear_text_row')
	m.rts()

	// clear zeroes d0 + 1 longs from a0.
	m.label('clear')
	m.move(.l, imm(0), inc(a0))
	m.dbra(d0, 'clear')
	m.rts()

	// copy moves d0 + 1 longs from a0 to a1.
	m.label('copy')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'copy')
	m.rts()
}

fn (mut g Game) variables() {
	mut m := g.m
	m.align(2)
	for name in ['state', 'frame', 'chosen', 'pad', 'pressed', 'screen_left', 'screen_top', 'song',
		'seq_mode', 'seq_left', 'step_timer', 'step_in_beat', 'beat_timer', 'beat_parity',
		'beat_phase', 'fps', 'spb', 'beat_frames', 'look', 'note_count', 'hero_live', 'results_timer',
		'accuracy', 'rank', 'new_best', 'health', 'judge_kind', 'judge_time', 'progress_shown'] {
		g.variable(name, 0)
	}
	for name in song_counters {
		g.variable(name, 0)
	}
	for name in lane_effects {
		for lane in 0 .. lanes {
			g.variable('${name}_${lane}', 0)
		}
	}
	m.label('combo_digits')
	for _ in 0 .. 8 {
		m.word(0)
	}
	m.label('combo_digits_end')
	g.long_variable('raw_pad', 0)
	g.long_variable('list_next', list_a)
	for name in ['list_building', 'list_limit', 'song_rec', 'seq_ptr', 'seq_loop', 'chart_ptr',
		'view_ptr', 'score', 'shown_score'] {
		g.long_variable(name, 0)
	}
	m.label('best')
	for _ in 0 .. song_count {
		m.long(0)
	}
}
