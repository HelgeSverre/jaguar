module main

import jagkit { imm, lbl }

// The songs are written in frames of a sixtieth of a second. A PAL machine
// shows fifty frames a second, so there every fifth frame counts twice:
// six frames of song in five of picture, and the tempo stays what it was.

fn (mut g Game) pal_timing() {
	mut m := g.m
	// extra_due returns "not equal" on the frames that count twice. Call
	// it once a frame. It changes d0.
	m.label('extra_due')
	m.tst(.w, lbl('pal'))
	m.b(.eq, 'extra_known')
	m.sub(.w, imm(1), lbl('pal_wait'))
	m.b(.ne, 'no_extra_frame')
	m.move(.w, imm(5), lbl('pal_wait'))
	m.moveq(1, d0)
	m.rts()
	m.label('no_extra_frame')
	m.moveq(0, d0)
	m.label('extra_known')
	m.rts()

	// sequence_timed is `sequence` for the menus, at the right tempo.
	m.label('sequence_timed')
	m.bsr('sequence')
	m.bsr('extra_due')
	m.b(.eq, 'sequence_timed_done')
	m.bsr('sequence')
	m.label('sequence_timed_done')
	m.rts()

	g.variable('pal', 0) // 1 on a PAL machine
	g.variable('pal_wait', 5)
}
