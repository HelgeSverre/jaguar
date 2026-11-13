module main

import jagkit { abs, at, idx, imm, inc, lbl, ptr }

// The 68000 side: start-up, and everything that happens once a frame in
// the vertical interrupt: showing the list built last frame, colours,
// music, the controller and the rules of the game.

const d0 = jagkit.d0
const d1 = jagkit.d1
const d2 = jagkit.d2
const d3 = jagkit.d3
const d4 = jagkit.d4
const d5 = jagkit.d5
const d6 = jagkit.d6
const d7 = jagkit.d7
const a0 = jagkit.a0
const a1 = jagkit.a1
const a2 = jagkit.a2
const a3 = jagkit.a3
const a4 = jagkit.a4
const a5 = jagkit.a5
const a6 = jagkit.a6
const sp = jagkit.sp

// Where things live in RAM. The image itself loads at `load_address`.
const load_address = u32(0x4000)
const list_a = u32(0x1c0000) // two display lists: one shown, one being built
const list_b = u32(0x1c1000)
const list_slots = 110 // objects in a list, 32 bytes each
const text_address = u32(0x1c4000) // 320x240 at two bits a pixel
const text_line_bytes = screen_width / 4
const text_bytes = text_line_bytes * screen_height
const note_state = u32(0x1d8000) // a byte per chart note: 0 coming, 1 hit, 2 missed
const max_notes = 4096

const text_columns = 40
const text_rows = 30

// Game states.
const state_title = 0
const state_select = 1
const state_play = 2
const state_results = 3

// Bits of `pad` and `pressed`, as `read_pad` leaves them.
const pad_up = 8
const pad_down = 9
const pad_confirm = 10
const pad_back = 11
const pad_pause = 12

// The controller matrix as `read_pad` gathers it: row r, column c is bit
// 4r + c; the fire button of row r is bit 16 + r; pause is bit 20.
fn matrix_bit(row int, column int) u32 {
	return u32(1) << (row * 4 + column)
}

const fire_a = u32(1) << 16
const fire_b = u32(1) << 17
const fire_c = u32(1) << 18
const fire_option = u32(1) << 19
const button_pause = u32(1) << 20

// lane_buttons: the keypad's 1 to 5, and on the pad left, up or down,
// right or C, B and A.
fn lane_buttons() []u32 {
	return [matrix_bit(1, 3) | matrix_bit(0, 2),
		matrix_bit(2, 3) | matrix_bit(0, 0) | matrix_bit(0, 1),
		matrix_bit(3, 3) | matrix_bit(0, 3) | fire_c, matrix_bit(1, 2) | fire_b,
		matrix_bit(2, 2) | fire_a]
}

// Sequencer modes.
const seq_off = 0
const seq_preview = 1 // loops a few bars, for the menus
const seq_play = 2

// Judgements, and the window of each, in frames either side of the note.
const judge_perfect = 0
const judge_great = 1
const judge_good = 2
const judge_miss = 3
const window_perfect = 1
const window_great = 3
const window_good = 5
const window_near = 12 // a press this close to a note is early, not wrong
// The list built in a frame is on screen the frame after, so a note is
// seen on the strike line a frame after its sound starts: presses are
// judged that much later.
const input_lag = 1

const health_full = meter_height
const health_start = 80
const health_miss = 7
const health_stray = 3
const finish_frames = 150

// The multiplier: combo needed for each tier, and what a tier multiplies.
const tier_combos = [10, 20, 30, 50]
const tier_factors = [1, 2, 3, 4, 8]
const judge_points = [100, 70, 40]
const judge_health = [2, 2, 1]

// Offsets in a song record: all longs.
const rec_steps = 0
const rec_chart = 4
const rec_view = 8
const rec_name = 12
const rec_setup = 16
const rec_phase = 20
const rec_style = 24
const rec_step_count = 28
const rec_note_count = 32
const rec_fps = 36
const rec_spb = 40
const rec_beat_frames = 44
const rec_look = 48
const rec_preview = 52
const rec_preview_steps = 56
const rec_bpm = 60
const rec_stars = 64
const rec_snare_step = 68
const rec_tom_step = 72
const rec_snare_level = 76
const rec_ghost_level = 80
const rec_hat_closed = 84
const rec_hat_open = 88
const rec_bass_rate = 92
const rec_chord_ring = 96
const rec_chord_mute = 100
const rec_hero_level = 104
const rec_harmony_level = 108
const rec_hero_sustain = 112
const rec_hero_release = 116
const rec_release = 120
const rec_end_frame = 124
const rec_theme = 128
const rec_bytes = 132

const song_count = 5
const list_top = 4 // the text row of the first song on the list
const preview_bars = 8

struct Game {
	voices  u32 // the DSP's voice records
	globals u32 // and its echo settings
mut:
	m &jagkit.M68k
}

fn (g &Game) voice(v int, field int) jagkit.Ea {
	return abs(g.voices + u32(v * voice_bytes + field))
}

// say prints a string constant at a text cell in colour 1..3.
fn (mut g Game) say(column int, row int, colour int, text string) {
	name := g.m.unique('text')
	skip := g.m.unique('after')
	g.m.lea(lbl(name), a0)
	g.m.moveq(column, d0)
	g.m.moveq(row, d1)
	g.m.moveq(colour, d2)
	g.m.bsr('print')
	g.m.bra(skip)
	g.m.label(name)
	g.m.text(text)
	g.m.label(skip)
}

// centre prints a string constant in the middle of a row.
fn (mut g Game) centre(row int, colour int, text string) {
	g.say((text_columns - text.len) / 2, row, colour, text)
}

// variable reserves a word of game state.
fn (mut g Game) variable(name string, initial int) {
	g.m.label(name)
	g.m.word(initial)
}

fn (mut g Game) long_variable(name string, initial u32) {
	g.m.align(2)
	g.m.label(name)
	g.m.long(initial)
}

fn (mut g Game) start_up(dsp_longs int, dsp_start u32) {
	mut m := g.m
	m.label('entry')
	m.move_to_sr(imm(0x2700))
	m.lea(abs(load_address), sp)

	// The video standard decides the display window and the lists.
	m.lea(lbl('profile_ntsc'), a6)
	m.move(.w, abs(jagkit.joybuts), d0)
	m.btst(4, d0)
	m.b(.ne, 'standard_known')
	m.lea(lbl('profile_pal'), a6)
	m.move(.w, imm(1), lbl('pal'))
	m.label('standard_known')
	m.move(.w, inc(a6), d0)
	m.move(.w, d0, abs(jagkit.hdb1))
	m.move(.w, d0, abs(jagkit.hdb2))
	m.move(.w, inc(a6), abs(jagkit.hde))
	m.move(.w, inc(a6), abs(jagkit.vdb))
	m.move(.w, imm(0xffff), abs(jagkit.vde))
	m.move(.w, inc(a6), abs(jagkit.vi))
	m.move(.w, inc(a6), lbl('screen_left'))
	m.move(.w, inc(a6), lbl('screen_top'))
	// The start of both lists: the branches past the lines outside the
	// picture, and the stop they lead to.
	for list in [list_a, list_b] {
		again := m.unique('prefix')
		m.lea(abs(list), a1)
		m.moveq(prefix_bytes / 4 - 1, d0)
		m.label(again)
		m.move(.l, inc(a6), inc(a1))
		m.dbra(d0, again)
	}
	m.move(.l, imm(0), abs(jagkit.bord1))
	m.move(.w, imm(0), abs(jagkit.bg))

	// Fixed colours: the text and its shadow.
	m.move(.w, imm(jagkit.cry(255, 255, 255)), abs(jagkit.clut + clut_text * 2))
	m.move(.w, imm(jagkit.cry(255, 80, 200)), abs(jagkit.clut + (clut_text + 2) * 2))
	for i in 0 .. 3 {
		m.move(.w, imm(jagkit.cry(8, 0, 16)), abs(jagkit.clut + u32(clut_shadow + i) * 2))
	}

	m.bsr('clear_text')
	m.lea(abs(echo_address), a0)
	m.move(.w, imm(echo_mask / 4), d0)
	m.bsr('clear')

	// The DSP.
	m.lea(lbl('dsp_program'), a0)
	m.lea(abs(jagkit.dsp_ram), a1)
	m.move(.w, imm(dsp_longs - 1), d0)
	m.bsr('copy')
	m.move(.l, imm(dsp_start), abs(jagkit.d_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.d_ctrl))

	m.bsr('enter_title')
	m.bsr('build_list')

	// Show the first list, then let the interrupt keep them coming.
	m.move(.l, lbl('list_next'), d0)
	m.swap(d0)
	m.move(.l, d0, abs(jagkit.olp))
	m.move(.w, imm(jagkit.vmode_cry16), abs(jagkit.vmode))
	m.move(.l, ptr('frame_interrupt'), abs(jagkit.interrupt_vector))
	m.move(.w, imm(jagkit.int1_video), abs(jagkit.int1))
	m.move_to_sr(imm(0x2000))
	m.label('sleep')
	m.stop(0x2000)
	m.bra('sleep')
}

fn (mut g Game) frame_interrupt() {
	mut m := g.m
	everything := [d0, d1, d2, d3, d4, d5, d6, d7, a0, a1, a2, a3, a4, a5, a6]
	m.label('frame_interrupt')
	m.push(everything)
	// Show what was built last frame; the object processor reads the list
	// pointer at the start of every line.
	m.move(.l, lbl('list_next'), d0)
	m.swap(d0)
	m.move(.l, d0, abs(jagkit.olp))
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))

	m.add(.w, imm(1), lbl('frame'))
	m.bsr('colours')
	m.bsr('read_pad')

	m.move(.w, lbl('state'), d0)
	m.b(.eq, 'title')
	m.cmp(.w, imm(state_select), d0)
	m.b(.eq, 'select')
	m.cmp(.w, imm(state_play), d0)
	m.b(.eq, 'play')
	m.bra('results')

	m.label('frame_done')
	m.bsr('build_list')
	m.pop(everything)
	m.rte()
}

// read_pad leaves the held buttons in `pad` and the newly pressed ones in
// `pressed`: bits 0..4 the lanes, then up, down, confirm, back and pause.
fn (mut g Game) read_pad() {
	mut m := g.m
	m.label('read_pad')
	m.moveq(0, d2)
	for row in 0 .. 4 {
		row_select := jagkit.joystick_enable | 0xf0 | (0xf & ~(1 << row))
		m.move(.w, imm(row_select), abs(jagkit.joystick))
		m.move(.w, abs(jagkit.joystick), d0)
		m.move(.w, abs(jagkit.joybuts), d1)
		m.not(.w, d0) // the lines are low while pressed
		m.lsr(.w, imm(8), d0)
		m.and(.l, imm(0xf), d0)
		mut shift := row * 4
		for shift > 0 {
			step := if shift > 8 { 8 } else { shift }
			m.lsl(.l, imm(step), d0)
			shift -= step
		}
		m.orr(.l, d0, d2)
		fire := m.unique('no_fire')
		m.btst(1, d1)
		m.b(.ne, fire)
		m.bset(16 + row, d2)
		m.label(fire)
		if row == 0 {
			no_pause := m.unique('no_pause')
			m.btst(0, d1)
			m.b(.ne, no_pause)
			m.bset(20, d2)
			m.label(no_pause)
		}
	}
	m.move(.l, d2, lbl('raw_pad'))
	m.moveq(0, d0)
	mut masks := lane_buttons()
	masks << matrix_bit(0, 0)
	masks << matrix_bit(0, 1)
	masks << fire_a | fire_b | fire_c | button_pause
	masks << fire_option
	masks << button_pause
	bits := [0, 1, 2, 3, 4, pad_up, pad_down, pad_confirm, pad_back, pad_pause]
	for i, mask in masks {
		skip := m.unique('not_held')
		m.move(.l, d2, d1)
		m.and(.l, imm(mask), d1)
		m.b(.eq, skip)
		m.bset(bits[i], d0)
		m.label(skip)
	}
	m.move(.w, lbl('pad'), d1)
	m.move(.w, d0, lbl('pad'))
	m.not(.w, d1)
	m.and(.w, d0, d1)
	m.move(.w, d1, lbl('pressed'))
	m.rts()
}

fn (mut g Game) menus() {
	mut m := g.m

	// Title: the logo over the stage, the music of the first song.
	m.label('enter_title')
	m.move(.w, imm(state_title), lbl('state'))
	m.moveq(0, d0)
	m.bsr('preview_song')
	m.bsr('clear_text')
	g.centre(17, 3, 'FIVE SONGS. FIVE LANES. NO MERCY.')
	g.centre(20, 1, 'PRESS START')
	g.centre(27, 2, 'LANES: KEYS 1 2 3 4 5 OR')
	g.centre(28, 1, 'PAD LEFT, UP, RIGHT, B, A')
	m.rts()

	m.label('title')
	m.bsr('sequence_timed')
	m.bsr('attract')
	m.move(.w, lbl('pressed'), d0)
	m.and(.w, imm((1 << pad_confirm) | 0x1f), d0)
	m.b(.eq, 'frame_done')
	m.bsr('enter_select')
	m.bra('frame_done')

	// Song select: up and down choose, the chosen song plays.
	m.label('enter_select')
	m.move(.w, imm(state_select), lbl('state'))
	m.bsr('clear_text')
	g.centre(2, 2, 'CHOOSE YOUR SONG')
	g.centre(27, 1, 'UP/DOWN CHOOSE   A OR START PLAYS')
	g.centre(28, 3, 'OPTION GOES BACK')
	m.moveq(0, d6)
	m.label('list_songs')
	m.move(.w, d6, d0)
	m.bsr('song_entry')
	m.add(.w, imm(1), d6)
	m.cmp(.w, imm(song_count), d6)
	m.b(.ne, 'list_songs')
	m.bra('select_changed')

	m.label('select')
	m.bsr('sequence_timed')
	m.bsr('attract')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_back, d0)
	m.b(.eq, 'select_not_back')
	m.bsr('enter_title')
	m.bra('frame_done')
	m.label('select_not_back')
	m.and(.w, imm(1 << pad_confirm), d0)
	m.b(.eq, 'select_not_go')
	m.bsr('start_song')
	m.bra('frame_done')
	m.label('select_not_go')
	m.move(.w, lbl('chosen'), d1)
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_up, d0)
	m.b(.eq, 'select_not_up')
	m.sub(.w, imm(1), d1)
	m.b(.pl, 'select_move')
	m.moveq(song_count - 1, d1)
	m.bra('select_move')
	m.label('select_not_up')
	m.btst(pad_down, d0)
	m.b(.eq, 'frame_done')
	m.add(.w, imm(1), d1)
	m.cmp(.w, imm(song_count), d1)
	m.b(.ne, 'select_move')
	m.moveq(0, d1)
	m.label('select_move')
	m.move(.w, d1, lbl('chosen'))
	m.bsr('select_changed')
	m.bra('frame_done')

	// select_changed marks the chosen song and plays a little of it.
	m.label('select_changed')
	m.moveq(0, d6)
	m.label('mark_songs')
	m.move(.w, d6, d1)
	m.mulu(imm(4), d1)
	m.add(.w, imm(list_top), d1)
	m.moveq(1, d0)
	m.lea(lbl('text_blank'), a0)
	m.cmp(.w, lbl('chosen'), d6)
	m.b(.ne, 'not_chosen')
	m.lea(lbl('text_arrow'), a0)
	m.label('not_chosen')
	m.moveq(2, d2)
	m.bsr('print')
	m.add(.w, imm(1), d6)
	m.cmp(.w, imm(song_count), d6)
	m.b(.ne, 'mark_songs')
	m.move(.w, lbl('chosen'), d0)
	m.bra('preview_song')

	// song_entry writes song d0's three lines of the list: name, style
	// and tempo, best score; and its difficulty in stars.
	m.label('song_entry')
	m.move(.w, d0, d7)
	m.bsr('song_record')
	m.move(.w, d7, d5)
	m.mulu(imm(4), d5)
	m.add(.w, imm(list_top), d5) // the first row
	m.move(.l, at(rec_name, a5), a0)
	m.moveq(4, d0)
	m.move(.w, d5, d1)
	m.moveq(3, d2)
	m.bsr('print')
	m.move(.l, at(rec_style, a5), a0)
	m.moveq(4, d0)
	m.move(.w, d5, d1)
	m.add(.w, imm(1), d1)
	m.moveq(1, d2)
	m.bsr('print')
	m.lea(lbl('stars_text'), a0)
	m.move(.l, at(rec_stars, a5), d0)
	m.sub(.w, imm(1), d0)
	m.mulu(imm(6), d0)
	m.add(.l, d0, a0)
	m.moveq(30, d0)
	m.move(.w, d5, d1)
	m.moveq(2, d2)
	m.bsr('print')
	m.lea(lbl('text_bpm'), a0)
	m.moveq(30, d0)
	m.move(.w, d5, d1)
	m.add(.w, imm(1), d1)
	m.moveq(1, d2)
	m.bsr('print')
	m.move(.l, at(rec_bpm, a5), d0)
	m.moveq(3, d4)
	m.bsr('number')
	m.moveq(34, d0)
	m.move(.w, d5, d1)
	m.add(.w, imm(1), d1)
	m.moveq(1, d2)
	m.bsr('print')
	m.lea(lbl('text_best'), a0)
	m.moveq(4, d0)
	m.move(.w, d5, d1)
	m.add(.w, imm(2), d1)
	m.moveq(1, d2)
	m.bsr('print')
	m.move(.w, d7, d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('best'), a0)
	m.move(.l, idx(0, a0, d0), d0)
	m.moveq(7, d4)
	m.bsr('number')
	m.moveq(9, d0)
	m.move(.w, d5, d1)
	m.add(.w, imm(2), d1)
	m.moveq(2, d2)
	m.bra('print')
}
