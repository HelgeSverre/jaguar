module main

import jagkit { abs, at, idx, imm, ind, lbl }

// The play state: once a frame the sequencer plays, notes that slipped past
// the strike line are missed, presses are judged, and effects fade.

fn (mut g Game) play_state() {
	mut m := g.m
	m.label('play')
	m.tst(.w, lbl('paused'))
	m.b(.eq, 'not_paused')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_back, d0)
	m.b(.eq, 'still_paused')
	g.mute(cut_rate)
	m.bsr('enter_select')
	m.bra('frame_done')
	m.label('still_paused')
	m.btst(pad_pause, d0)
	m.b(.eq, 'frame_done')
	m.move(.w, imm(0), lbl('paused'))
	g.say(event_column, event_row + 2, 1, ' '.repeat(20))
	g.say(event_column, event_row + 3, 1, ' '.repeat(20))
	m.bra('frame_done')
	m.label('not_paused')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_pause, d0)
	m.b(.eq, 'play_on')
	m.move(.w, imm(1), lbl('paused'))
	g.mute(fade_rate)
	g.say(event_column, event_row + 2, 2, '       PAUSED       ')
	g.say(event_column, event_row + 3, 1, ' OPTION QUITS SONG  ')
	m.bra('frame_done')

	m.label('play_on')
	m.tst(.w, lbl('failed'))
	m.b(.ne, 'play_judged')
	m.bsr('sequence')
	m.tst(.w, lbl('finish_timer')) // a finished song takes no more presses
	m.b(.ne, 'play_judged')
	m.bsr('miss_sweep')
	m.bsr('judge_presses')
	m.label('play_judged')
	m.bsr('effects')
	m.bsr('hud')

	// The end: a banner, then the results.
	m.tst(.w, lbl('finish_timer'))
	m.b(.eq, 'not_finishing')
	m.sub(.w, imm(1), lbl('finish_timer'))
	m.b(.ne, 'play_advance')
	m.bsr('enter_results')
	m.bra('frame_done')
	m.label('not_finishing')
	m.tst(.w, lbl('song_over'))
	m.b(.eq, 'play_advance')
	m.move(.w, lbl('judge_first'), d0)
	m.cmp(.w, lbl('note_count'), d0)
	m.b(.cs, 'play_advance')
	m.move(.w, imm(finish_frames), lbl('finish_timer'))
	g.say(event_column, event_row, 2, '  SONG COMPLETE!   ')
	m.move(.w, imm(0), lbl('event_timer'))
	m.label('play_advance')
	m.add(.w, imm(1), lbl('clock'))
	m.bra('frame_done')
}

fn (mut g Game) judge() {
	mut m := g.m

	// miss_sweep misses every note that has gone past the window.
	m.label('miss_sweep')
	m.moveq(0, d0)
	m.move(.w, lbl('judge_first'), d0)
	m.label('sweep_next')
	m.cmp(.w, lbl('note_count'), d0)
	m.b(.cc, 'sweep_done')
	m.move(.l, lbl('chart_ptr'), a0)
	m.move(.l, d0, d1)
	m.lsl(.l, imm(2), d1)
	m.add(.l, d1, a0)
	m.move(.w, lbl('clock'), d1)
	m.sub(.w, ind(a0), d1)
	m.sub(.w, imm(input_lag), d1)
	m.cmp(.w, imm(window_good), d1)
	m.b(.le, 'sweep_done')
	m.lea(abs(note_state), a1)
	m.tst(.b, idx(0, a1, d0))
	m.b(.ne, 'sweep_judged')
	m.move(.b, imm(2), idx(0, a1, d0))
	m.push([d0])
	m.bsr('miss')
	m.pop([d0])
	m.label('sweep_judged')
	m.add(.w, imm(1), d0)
	m.move(.w, d0, lbl('judge_first'))
	m.bra('sweep_next')
	m.label('sweep_done')
	m.rts()

	// judge_presses looks for a note under every lane just pressed.
	m.label('judge_presses')
	for lane in 0 .. lanes {
		skip := m.unique('not_pressed')
		m.move(.w, lbl('pressed'), d7)
		m.btst(lane, d7)
		m.b(.eq, skip)
		m.moveq(lane, d6)
		m.bsr('try_hit')
		m.label(skip)
	}
	m.rts()

	// try_hit judges a press of lane d6 against the first note in that lane
	// not yet judged. Too early is ignored; nothing near is a stray press.
	m.label('try_hit')
	m.moveq(0, d0)
	m.move(.w, lbl('judge_first'), d0)
	m.move(.l, lbl('chart_ptr'), a0)
	m.move(.l, d0, d1)
	m.lsl(.l, imm(2), d1)
	m.add(.l, d1, a0)
	m.lea(abs(note_state), a1)
	m.add(.l, d0, a1)
	m.label('try_next')
	m.move(.w, ind(a0), d1)
	m.sub(.w, lbl('clock'), d1)
	m.add(.w, imm(input_lag), d1) // frames until the note: below zero is late
	m.cmp(.w, imm(window_near), d1)
	m.b(.gt, 'stray')
	m.tst(.b, ind(a1))
	m.b(.ne, 'try_skip')
	m.cmp(.b, at(2, a0), d6)
	m.b(.ne, 'try_skip')
	m.cmp(.w, imm(window_good), d1)
	m.b(.le, 'hit')
	m.rts() // early: the press is forgiven
	m.label('try_skip')
	m.add(.l, imm(4), a0)
	m.add(.l, imm(1), a1)
	m.bra('try_next')
	g.hit()
	g.miss()
}

// lane_word points a2 at the lane-d6 word of an effect array.
fn (mut g Game) lane_word(array string) {
	g.m.lea(lbl('${array}_0'), a2)
	g.m.add(.l, d4, a2)
}
