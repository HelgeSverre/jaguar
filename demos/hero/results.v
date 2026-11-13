module main

import jagkit { at, imm, lbl }

// The menus' moving lanes, the head-up display while playing, and the
// results of a song.

// show_word prints a word variable as `digits` digits at a text cell.
fn (mut g Game) show_word(name string, column int, row int, digits int) {
	mut m := g.m
	m.moveq(0, d0)
	m.move(.w, lbl(name), d0)
	g.show_d0(column, row, digits)
}

fn (mut g Game) show_d0(column int, row int, digits int) {
	mut m := g.m
	m.moveq(digits, d4)
	m.bsr('number')
	m.moveq(column, d0)
	m.moveq(row, d1)
	m.moveq(2, d2)
	m.bsr('print')
}

fn (mut g Game) hud() {
	mut m := g.m
	// attract makes the lanes of the menus ripple.
	m.label('attract')
	m.lea(lbl('attract_wave'), a0)
	for lane in 0 .. lanes {
		m.move(.w, lbl('frame'), d0)
		m.add(.w, imm(lane * 6), d0)
		m.and(.l, imm(63), d0)
		m.moveq(0, d1)
		m.move(.b, jagkit.idx(0, a0, d0), d1)
		m.move(.w, d1, lbl('lane_glow_${lane}'))
		m.move(.w, imm(0), lbl('target_state_${lane}'))
	}
	m.move(.w, imm(0), lbl('tier'))
	m.rts()

	// hud keeps the score and the progress bar up to date.
	m.label('hud')
	m.move(.l, lbl('score'), d0)
	m.cmp(.l, lbl('shown_score'), d0)
	m.b(.eq, 'score_shown')
	m.move(.l, d0, lbl('shown_score'))
	g.show_d0(31, 2, 7)
	m.label('score_shown')
	m.moveq(0, d0)
	m.move(.w, lbl('clock'), d0)
	m.lsl(.l, imm(4), d0)
	m.move(.l, lbl('song_rec'), a5)
	m.move(.l, at(rec_end_frame, a5), d1)
	m.divu(d1, d0)
	m.cmp(.w, imm(progress_cells), d0)
	m.b(.ls, 'progress_known')
	m.moveq(progress_cells, d0)
	m.label('progress_known')
	m.cmp(.w, lbl('progress_shown'), d0)
	m.b(.eq, 'hud_done')
	m.move(.w, d0, lbl('progress_shown'))
	m.tst(.w, d0)
	m.b(.eq, 'hud_done')
	m.lea(lbl('text_block'), a0)
	m.moveq(2, d1)
	m.moveq(3, d2)
	m.bsr('print')
	m.label('hud_done')
	m.rts()
}

fn (mut g Game) results() {
	mut m := g.m
	m.label('enter_results')
	m.move(.w, imm(state_results), lbl('state'))
	m.move(.w, imm(seq_off), lbl('seq_mode'))
	g.mute(fade_rate)
	m.move(.w, imm(0), lbl('results_timer'))
	// Accuracy: a perfect counts in full, a great three quarters, a good
	// half.
	m.moveq(0, d0)
	m.move(.w, lbl('perfects'), d0)
	m.mulu(imm(100), d0)
	for name, worth in {
		'greats': 75
		'goods':  50
	} {
		m.moveq(0, d1)
		m.move(.w, lbl(name), d1)
		m.mulu(imm(worth), d1)
		m.add(.l, d1, d0)
	}
	m.divu(lbl('note_count'), d0)
	m.and(.l, imm(0xffff), d0)
	m.move(.w, d0, lbl('accuracy'))
	m.moveq(rank_letters.len - 1, d1)
	m.tst(.w, lbl('failed'))
	m.b(.ne, 'rank_known')
	m.moveq(rank_accuracy.len, d1)
	for i, need in rank_accuracy {
		next := m.unique('rank_below')
		m.cmp(.w, imm(need), d0)
		m.b(.cs, next)
		m.moveq(i, d1)
		m.bra('rank_known')
		m.label(next)
	}
	m.label('rank_known')
	m.move(.w, d1, lbl('rank'))
	// A best score for the session.
	m.move(.w, imm(0), lbl('new_best'))
	m.moveq(0, d0)
	m.move(.w, lbl('song'), d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('best'), a0)
	m.add(.l, d0, a0)
	m.move(.l, lbl('score'), d1)
	m.cmp(.l, jagkit.ind(a0), d1)
	m.b(.ls, 'no_best')
	m.move(.l, d1, jagkit.ind(a0))
	m.move(.w, imm(1), lbl('new_best'))
	m.label('no_best')

	m.bsr('clear_text')
	m.tst(.w, lbl('failed'))
	m.b(.eq, 'say_cleared')
	g.say(3, 3, 2, 'SONG FAILED')
	m.bra('said_how')
	m.label('say_cleared')
	g.say(3, 3, 2, 'SONG COMPLETE!')
	m.label('said_how')
	m.move(.l, lbl('song_rec'), a5)
	m.move(.l, at(rec_name, a5), a0)
	m.moveq(3, d0)
	m.moveq(5, d1)
	m.moveq(3, d2)
	m.bsr('print')
	rows := {
		'SCORE':     8
		'PERFECT':   10
		'GREAT':     11
		'GOOD':      12
		'MISS':      13
		'MAX COMBO': 15
		'ACCURACY':  16
		'BEST':      18
	}
	for text, row in rows {
		g.say(3, row, 1, text)
	}
	m.move(.l, lbl('score'), d0)
	g.show_d0(14, 8, 7)
	g.show_word('perfects', 17, 10, 4)
	g.show_word('greats', 17, 11, 4)
	g.show_word('goods', 17, 12, 4)
	g.show_word('misses', 17, 13, 4)
	g.show_word('max_combo', 17, 15, 4)
	g.show_word('accuracy', 18, 16, 3)
	g.say(21, 16, 1, '%')
	m.moveq(0, d0)
	m.move(.w, lbl('song'), d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('best'), a0)
	m.add(.l, d0, a0)
	m.move(.l, jagkit.ind(a0), d0)
	g.show_d0(14, 18, 7)
	m.tst(.w, lbl('new_best'))
	m.b(.eq, 'no_best_banner')
	g.say(3, 20, 2, 'NEW BEST SCORE!')
	m.label('no_best_banner')
	g.say(3, 28, 1, 'PRESS A FOR THE SONG LIST')
	m.rts()

	m.label('results')
	m.cmp(.w, imm(results_wait), lbl('results_timer'))
	m.b(.cc, 'results_ready')
	m.add(.w, imm(1), lbl('results_timer'))
	m.bra('frame_done')
	m.label('results_ready')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_confirm, d0)
	m.b(.eq, 'frame_done')
	m.bsr('enter_select')
	m.bra('frame_done')
}
