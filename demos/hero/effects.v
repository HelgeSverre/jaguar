module main

import jagkit { imm, lbl }

const progress_cells = 16
const results_wait = 60 // frames before the results take a button

// Accuracy thresholds of the ranks S, A, B, C; below them D, and F for a
// song that failed.
const rank_accuracy = [95, 88, 75, 60]

fn (mut g Game) effects() {
	mut m := g.m
	// Lanes glow while held and after a hit, and fade.
	m.label('effects')
	for lane in 0 .. lanes {
		floor := m.unique('glow_floor')
		kept := m.unique('glow_kept')
		state := m.unique('target_known')
		burst := m.unique('burst_kept')
		m.moveq(0, d1)
		m.move(.w, lbl('pad'), d0)
		m.btst(lane, d0)
		m.b(.eq, floor)
		m.moveq(5, d1)
		m.label(floor)
		m.move(.w, lbl('lane_glow_${lane}'), d0)
		m.cmp(.w, d1, d0)
		m.b(.ls, kept)
		m.sub(.w, imm(1), d0)
		m.move(.w, d0, d1)
		m.label(kept)
		m.move(.w, d1, lbl('lane_glow_${lane}'))
		// The target flashes after a hit or a miss, and is lit while held.
		quiet := m.unique('target_quiet')
		m.tst(.w, lbl('target_flash_${lane}'))
		m.b(.eq, quiet)
		m.sub(.w, imm(1), lbl('target_flash_${lane}'))
		m.move(.w, lbl('target_kind_${lane}'), lbl('target_state_${lane}'))
		m.bra(state)
		m.label(quiet)
		m.moveq(0, d0)
		m.move(.w, lbl('pad'), d1)
		not_held := m.unique('not_held')
		m.btst(lane, d1)
		m.b(.eq, not_held)
		m.moveq(1, d0)
		m.label(not_held)
		m.move(.w, d0, lbl('target_state_${lane}'))
		m.label(state)
		m.cmp(.w, imm(burst_frames_shown), lbl('burst_time_${lane}'))
		m.b(.cc, burst)
		m.add(.w, imm(1), lbl('burst_time_${lane}'))
		m.label(burst)
	}
	m.cmp(.w, imm(judge_frames_shown), lbl('judge_time'))
	m.b(.cc, 'judge_aged')
	m.add(.w, imm(1), lbl('judge_time'))
	m.label('judge_aged')
	m.tst(.w, lbl('flash'))
	m.b(.eq, 'flash_out')
	m.sub(.w, imm(1), lbl('flash'))
	m.label('flash_out')
	m.tst(.w, lbl('event_timer'))
	m.b(.eq, 'banner_kept')
	m.sub(.w, imm(1), lbl('event_timer'))
	m.b(.ne, 'banner_kept')
	g.say(event_column, event_row, 1, ' '.repeat(20))
	m.label('banner_kept')
	m.rts()
}
