module main

import jagkit { abs, at, dec, idx, imm, inc, ind, lbl, ptr }

// The 68000 side: start-up, and everything that happens once a frame in
// the vertical interrupt: showing the finished tunnel frame, music, the
// controller and the rules of the game.

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
const list_address = u32(0x80000) // the display list the object processor reads
const text_address = u32(0x81000) // 320x240 at one bit a pixel
const strip_address = u32(0x84000) // the scroller: 8 lines of 192 pixels
const buffer_a = u32(0x90000) // two tunnel frames, shown in turn
const buffer_b = u32(0xa0000)

const text_columns = 40
const text_rows = 30
const strip_bytes = 24 // per line; the last 8 are off screen
const strip_lines = 8
const list_objects = 5
const list_bytes = 32 + list_objects * 32
const scroller_object = 4 // its place in the title list

// Scenes: which display list is shown, as an offset into a video profile's
// table of lists.
const scene_title = 0
const scene_ship = 8 // level; the next two bank left and right
const scene_blast = 32 // four frames of explosion
const scene_wreck = 64 // the tunnel without a ship
const scene_count = 9

// Game states.
const state_title = 0
const state_play = 1
const state_dead = 2

// Pad bits, as `read_pad` leaves them.
const pad_fire = 0
const pad_left = 2
const pad_right = 3

// Tuning. Angles are 256 to the turn, depths 256 to the length of the
// tunnel; speeds are 8.8 fixed point per frame.
const ship_radius = 44 // tunnel pixels from the centre of the screen to the ship
const ship_depth = int(depth_scale / ship_radius) // the depth of the wall under it
// A gate nearer than this is past the corners of the screen, all of it.
const hidden_depth = int(depth_scale / farthest_radius) - gate_rings - 2
const ship_angle = 64 // the ship sits at the bottom of the screen
const ship_margin = 6 // half the ship's width, as an angle
const first_speed = 0x0180
const top_speed = 0x0400
const speed_gain = 0x000c
const turn_gain = 0x0040
const top_turn = 0x0380
const bank_turn = 0x0100 // turning faster than this tilts the ship
const widest_gap = 26 // half the opening, as an angle
const tightest_gap = 14
const grace_frames = 100
const blip_note = 96

// Offsets into a gate record.
const gate_ring = 0 // its first texture ring
const gate_gap = 2 // the angle of the middle of its opening
const gate_depth = 4 // its depth on the previous frame
const gate_stage = 6 // 0 as it was, 1 with its old lane gone, 2 with its new lane laid
const gate_wall = 8 // address of a copy of the wall its lane covers

// Offsets into a video profile.
const profile_scroller_y = 8
const profile_lists = 12

struct Game {
	mailbox u32 // the values shared with the GPU
	voices  u32 // the DSP's voice settings
mut:
	m &jagkit.M68k
}

fn (g &Game) shared_at(offset int) jagkit.Ea {
	return abs(g.mailbox + u32(offset))
}

fn (g &Game) voice(offset int) jagkit.Ea {
	return abs(g.voices + u32(offset))
}

// say prints a string constant at a text cell.
fn (mut g Game) say(column int, row int, text string) {
	name := g.m.unique('text')
	skip := g.m.unique('after')
	g.m.lea(lbl(name), a0)
	g.m.moveq(column, d0)
	g.m.moveq(row, d1)
	g.m.bsr('print')
	g.m.bra(skip)
	g.m.label(name)
	g.m.text(text)
	g.m.label(skip)
}

// variable reserves a word of game state.
fn (mut g Game) variable(name string, initial int) {
	g.m.label(name)
	g.m.word(initial)
}

// fade lets a voice's volume decay by 1/2^shift a frame, down to silence.
fn (mut g Game) fade(volume jagkit.Ea, shift int) {
	mut m := g.m
	keep := m.unique('keep')
	m.move(.l, volume, d0)
	m.move(.l, d0, d1)
	m.lsr(.l, imm(shift), d1)
	m.b(.ne, keep)
	m.moveq(0, d0)
	m.label(keep)
	m.sub(.l, d1, d0)
	m.move(.l, d0, volume)
}

fn (mut g Game) start_up(gpu_longs int, dsp_longs int, dsp_start u32) {
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
	m.label('standard_known')
	m.move(.l, a6, lbl('profile'))
	m.move(.w, inc(a6), d0)
	m.move(.w, d0, abs(jagkit.hdb1))
	m.move(.w, d0, abs(jagkit.hdb2))
	m.move(.w, inc(a6), abs(jagkit.hde))
	m.move(.w, inc(a6), abs(jagkit.vdb))
	m.move(.w, imm(0xffff), abs(jagkit.vde))
	m.move(.w, inc(a6), abs(jagkit.vi))
	m.move(.l, imm(0), abs(jagkit.bord1))
	m.move(.w, imm(0), abs(jagkit.bg))
	m.move(.w, imm(0), abs(jagkit.clut))

	// Blank everything that is shown.
	m.bsr('clear_text')
	m.lea(abs(strip_address), a0)
	m.moveq(strip_bytes * strip_lines / 4 - 1, d0)
	m.bsr('clear')
	m.lea(abs(buffer_a), a0)
	m.move(.w, imm(tunnel_width * tunnel_height / 2 - 1), d0)
	m.bsr('clear')
	m.lea(abs(buffer_b), a0)
	m.move(.w, imm(tunnel_width * tunnel_height / 2 - 1), d0)
	m.bsr('clear')

	m.move(.w, imm(0), abs(jagkit.clut + 10)) // the shadow under the text
	for gate in ['gate_0', 'gate_1'] {
		m.lea(lbl(gate), a5)
		m.bsr('lay_lane')
		m.bsr('spark_gate')
	}
	m.bsr('enter_title')

	// The GPU: load it, tell it where its data is, start it.
	m.lea(lbl('gpu_program'), a0)
	m.lea(abs(jagkit.gpu_ram), a1)
	m.move(.w, imm(gpu_longs - 1), d0)
	m.bsr('copy')
	m.move(.l, ptr('tunnel_table'), g.shared_at(shared_table))
	m.move(.l, ptr('texture'), g.shared_at(shared_texture))
	m.move(.l, imm(buffer_b), g.shared_at(shared_first))
	m.move(.l, imm(buffer_a), g.shared_at(shared_second))
	m.move(.l, ptr('palettes'), g.shared_at(shared_palette))
	m.move(.l, imm((window_y << 16) | window_x), g.shared_at(shared_window))
	m.move(.l, imm(jagkit.gpu_ram), abs(jagkit.g_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.g_ctrl))

	// The DSP.
	m.lea(lbl('dsp_program'), a0)
	m.lea(abs(jagkit.dsp_ram), a1)
	m.move(.w, imm(dsp_longs - 1), d0)
	m.bsr('copy')
	m.move(.l, imm(dsp_start), abs(jagkit.d_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.d_ctrl))

	// The display list, then the interrupt that keeps it fresh.
	m.bsr('refresh_list')
	m.move(.l, imm((list_address << 16) | (list_address >> 16)), abs(jagkit.olp))
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

	// Show the frame the GPU has finished, and let it start the next.
	m.move(.l, g.shared_at(shared_finished), d0)
	m.b(.eq, 'no_new_frame')
	m.move(.w, imm(0), lbl('front'))
	m.cmp(.l, imm(buffer_b), d0)
	m.b(.ne, 'front_known')
	m.move(.w, imm(4), lbl('front'))
	m.label('front_known')
	m.move(.l, g.shared_at(shared_drawn), d1) // where its window was
	m.move(.w, d1, lbl('shown_x'))
	m.swap(d1)
	m.move(.w, d1, lbl('shown_y'))
	m.move(.l, imm(0), g.shared_at(shared_finished))
	m.label('no_new_frame')
	m.bsr('refresh_list')
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))

	m.add(.w, imm(1), lbl('frame'))
	m.bsr('cycle_colours')
	m.bsr('music')
	m.bsr('read_pad')

	m.move(.w, lbl('state'), d0)
	m.b(.eq, 'title')
	m.cmp(.w, imm(state_play), d0)
	m.b(.eq, 'play')
	m.bra('dead')

	// Hand the view to the GPU: where the ship is, ...
	m.label('frame_done')
	m.moveq(0, d0)
	m.move(.w, lbl('rotation'), d0)
	m.lsr(.w, imm(8), d0)
	m.move(.l, d0, g.shared_at(shared_rotation))
	m.moveq(0, d0)
	m.move(.w, lbl('travel'), d0)
	m.lsr(.w, imm(8), d0)
	m.move(.l, d0, g.shared_at(shared_travel))
	// ... the colours, a phase on every other frame, ...
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.lsr(.w, imm(1), d0)
	m.and(.w, imm(palette_phases - 1), d0)
	m.mulu(imm(palette_bytes), d0)
	m.add(.l, ptr('palettes'), d0)
	m.move(.l, d0, g.shared_at(shared_palette))
	// ... and the window on the table, which wanders on two sines of
	// different periods so that the tunnel swerves.
	m.lea(lbl('sway'), a0)
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.move(.w, d0, d2)
	m.and(.w, imm(0xff), d0)
	m.move(.b, idx(0, a0, d0), d1)
	m.ext(.w, d1)
	m.muls(imm(sway_x), d1)
	m.asr(.w, imm(7), d1)
	m.add(.w, imm(window_x), d1)
	m.move(.w, d2, d0)
	m.lsr(.w, imm(2), d2)
	m.sub(.w, d2, d0) // three quarters of the frame count
	m.and(.w, imm(0xff), d0)
	m.move(.b, idx(0, a0, d0), d2)
	m.ext(.w, d2)
	m.muls(imm(sway_y), d2)
	m.asr(.w, imm(7), d2)
	m.add(.w, imm(window_y), d2)
	m.swap(d2)
	m.move(.w, d1, d2)
	m.move(.l, d2, g.shared_at(shared_window))
	m.pop(everything)
	m.rte()
}

// refresh_list copies the list for the current scene and front buffer into
// place: the object processor consumed the last copy while drawing. Then it
// moves what has to move.
fn (mut g Game) refresh_list() {
	mut m := g.m
	scroller := list_address + u32(32 + scroller_object * 32)
	m.label('refresh_list')
	m.move(.l, lbl('profile'), a0)
	m.moveq(0, d0)
	m.move(.w, lbl('scene'), d0)
	m.add(.w, lbl('front'), d0)
	m.move(.l, idx(profile_lists, a0, d0), a1)
	m.lea(abs(list_address), a2)
	m.moveq(list_bytes / 4 - 1, d1)
	m.label('copy_list')
	m.move(.l, inc(a1), inc(a2))
	m.dbra(d1, 'copy_list')
	m.move(.w, lbl('scene'), d0)
	m.b(.ne, 'not_title_list')
	// On the title the scroller bobs: rewrite its YPOS field.
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.and(.w, imm(63), d0)
	m.lea(lbl('bounce'), a1)
	m.moveq(0, d1)
	m.move(.b, idx(0, a1, d0), d1)
	m.add(.w, d1, d1)
	m.add(.w, at(profile_scroller_y, a0), d1)
	m.lsl(.w, imm(3), d1)
	m.move(.w, abs(scroller + 6), d0)
	m.and(.w, imm(0xc007), d0)
	m.orr(.w, d1, d0)
	m.move(.w, d0, abs(scroller + 6))
	m.rts()

	// In the tunnel the ship, or what is left of it, follows the tunnel as
	// it swerves: the second object, and in an explosion the third too.
	m.label('not_title_list')
	m.cmp(.w, imm(scene_wreck), d0)
	m.b(.cc, 'list_done')
	m.move(.w, imm(window_x), d2)
	m.sub(.w, lbl('shown_x'), d2)
	m.add(.w, d2, d2) // screen pixels to the right
	m.move(.w, imm(window_y), d3)
	m.sub(.w, lbl('shown_y'), d3)
	m.lsl(.w, imm(5), d3) // half-lines down, in place for the YPOS field
	m.lea(abs(list_address + 64), a1)
	m.bsr('follow')
	m.cmp(.w, imm(scene_blast), lbl('scene'))
	m.b(.cs, 'list_done')
	m.lea(abs(list_address + 96), a1)
	// follow moves the object at a1 by d2 pixels and d3 / 8 half-lines.
	m.label('follow')
	m.move(.w, at(14, a1), d0) // XPOS: the low twelve bits
	m.move(.w, d0, d1)
	m.and(.w, imm(0xf000), d1)
	m.add(.w, d2, d0)
	m.and(.w, imm(0x0fff), d0)
	m.orr(.w, d1, d0)
	m.move(.w, d0, at(14, a1))
	m.move(.w, at(6, a1), d0) // YPOS: bits 3 to 13
	m.move(.w, d0, d1)
	m.and(.w, imm(0xc007), d1)
	m.add(.w, d3, d0)
	m.and(.w, imm(0x3ff8), d0)
	m.orr(.w, d1, d0)
	m.move(.w, d0, at(6, a1))
	m.label('list_done')
	m.rts()
}

fn (mut g Game) cycle_colours() {
	mut m := g.m
	m.label('cycle_colours')
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.lsr(.w, imm(1), d0)
	m.and(.w, imm(63), d0)
	m.add(.w, d0, d0)
	m.lea(lbl('rainbow'), a0)
	m.move(.w, idx(0, a0, d0), abs(jagkit.clut + 2)) // the text
	m.eor(.w, imm(64), d0)
	m.move(.w, idx(0, a0, d0), abs(jagkit.clut + 6)) // the scroller
	// The lightning over a wreck flickers between white and blue.
	m.move(.w, imm(jagkit.cry(255, 255, 255)), d1)
	m.move(.w, lbl('frame'), d0)
	m.btst(1, d0)
	m.b(.eq, 'zap_colour_known')
	m.move(.w, imm(jagkit.cry(60, 120, 255)), d1)
	m.label('zap_colour_known')
	m.move(.w, d1, abs(jagkit.clut + 14))
	m.rts()
}

// music plays one step of the tune every six frames: a kick on the beat,
// bass on the three steps behind it, a hi-hat half way, and the lead when
// it has a note. Every frame all three voices fade.
fn (mut g Game) music() {
	mut m := g.m
	m.label('music')
	m.move(.w, lbl('beat_tick'), d6) // frames into the step
	m.add(.w, imm(1), d6)
	m.cmp(.w, imm(step_frames), d6)
	m.b(.cs, 'same_step')
	m.moveq(0, d6)
	m.add(.w, imm(1), lbl('step'))
	m.label('same_step')
	m.move(.w, d6, lbl('beat_tick'))
	m.moveq(0, d2)
	m.move(.w, lbl('step'), d2)
	m.move(.w, d2, d3)
	m.and(.w, imm(3), d3) // steps into the beat
	m.and(.w, imm(song_steps - 1), d2)
	m.lsl(.w, imm(2), d2) // offset into the tables
	m.tst(.w, d3)
	m.b(.ne, 'not_kick')
	// The kick is the bass voice falling in pitch over its first frames.
	m.cmp(.w, imm(kick_sweep().len), d6)
	m.b(.cc, 'lead')
	m.moveq(0, d0)
	m.move(.w, d6, d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('kick_sweep'), a0)
	m.move(.l, idx(0, a0, d0), g.voice(voice_bass_step))
	m.tst(.w, d6)
	m.b(.ne, 'lead')
	m.move(.l, imm(kick_volume), g.voice(voice_bass_volume))
	m.bra('lead')
	m.label('not_kick')
	m.tst(.w, d6)
	m.b(.ne, 'lead')
	m.lea(lbl('bass_line'), a0)
	m.move(.l, idx(0, a0, d2), g.voice(voice_bass_step))
	m.move(.l, imm(bass_volume), g.voice(voice_bass_volume))
	m.cmp(.w, imm(2), d3)
	m.b(.ne, 'lead')
	m.move(.l, imm(hat_volume), g.voice(voice_noise_volume))
	m.label('lead')
	m.tst(.w, d6)
	m.b(.ne, 'fade')
	m.lea(lbl('lead_line'), a0)
	m.move(.l, idx(0, a0, d2), d1)
	m.b(.eq, 'fade')
	m.move(.l, d1, g.voice(voice_lead_step))
	m.move(.l, imm(lead_volume), g.voice(voice_lead_volume))
	m.label('fade')
	g.fade(g.voice(voice_bass_volume), 3)
	g.fade(g.voice(voice_lead_volume), 2)
	g.fade(g.voice(voice_noise_volume), 1)
	m.rts()
}

// read_pad leaves the held buttons in `pad` and the newly pressed ones in
// `pressed`: bit 0 any fire button, bit 2 left, bit 3 right.
fn (mut g Game) read_pad() {
	mut m := g.m
	row := jagkit.joystick_enable | 0xf0
	m.label('read_pad')
	m.move(.w, imm(row | 0xe), abs(jagkit.joystick)) // row 0: directions and A
	m.move(.w, abs(jagkit.joystick), d0)
	m.move(.w, abs(jagkit.joybuts), d1)
	m.move(.w, imm(row | 0xd), abs(jagkit.joystick)) // row 1: B
	m.and(.w, abs(jagkit.joybuts), d1)
	m.move(.w, imm(row | 0xb), abs(jagkit.joystick)) // row 2: C
	m.and(.w, abs(jagkit.joybuts), d1)
	m.not(.w, d0) // the lines are low while pressed
	m.lsr(.w, imm(8), d0)
	m.and(.w, imm((1 << pad_left) | (1 << pad_right)), d0)
	m.btst(1, d1)
	m.b(.ne, 'no_fire')
	m.orr(.w, imm(1 << pad_fire), d0)
	m.label('no_fire')
	m.move(.w, lbl('pad'), d1)
	m.move(.w, d0, lbl('pad'))
	m.not(.w, d1)
	m.and(.w, d0, d1)
	m.move(.w, d1, lbl('pressed'))
	m.rts()
}

fn (mut g Game) states() {
	mut m := g.m
	hint := 'FOLLOW THE GREEN LANE'

	// Title: drift down the tunnel until a fire button is pressed.
	m.label('title')
	m.add(.w, imm(0x0050), lbl('rotation'))
	m.add(.w, imm(0x0140), lbl('travel'))
	m.bsr('gates')
	m.bsr('scroller')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_fire, d0)
	m.b(.eq, 'frame_done')
	m.bsr('start_game')
	m.bra('frame_done')

	// Play: left and right spin the tunnel, with a little inertia.
	m.label('play')
	m.move(.w, lbl('turn'), d0)
	m.move(.w, lbl('pad'), d1)
	m.btst(pad_left, d1)
	m.b(.eq, 'not_left')
	m.add(.w, imm(turn_gain), d0)
	m.label('not_left')
	m.btst(pad_right, d1)
	m.b(.eq, 'not_right')
	m.sub(.w, imm(turn_gain), d0)
	m.label('not_right')
	m.and(.w, imm((1 << pad_left) | (1 << pad_right)), d1)
	m.b(.ne, 'limit_turn')
	m.move(.w, d0, d2) // nothing held: slow down
	m.asr(.w, imm(3), d2)
	m.b(.ne, 'still_turning')
	m.moveq(0, d0)
	m.label('still_turning')
	m.sub(.w, d2, d0)
	m.label('limit_turn')
	m.cmp(.w, imm(top_turn), d0)
	m.b(.le, 'not_too_fast')
	m.move(.w, imm(top_turn), d0)
	m.label('not_too_fast')
	m.cmp(.w, imm(-top_turn), d0)
	m.b(.ge, 'turn_known')
	m.move(.w, imm(-top_turn), d0)
	m.label('turn_known')
	m.move(.w, d0, lbl('turn'))
	m.add(.w, d0, lbl('rotation'))
	// The ship leans into a fast turn.
	m.move(.w, imm(scene_ship), d1)
	m.cmp(.w, imm(bank_turn), d0)
	m.b(.lt, 'not_leaning_left')
	m.move(.w, imm(scene_ship + 8), d1)
	m.label('not_leaning_left')
	m.cmp(.w, imm(-bank_turn), d0)
	m.b(.gt, 'not_leaning_right')
	m.move(.w, imm(scene_ship + 16), d1)
	m.label('not_leaning_right')
	m.move(.w, d1, lbl('scene'))
	m.move(.w, lbl('speed'), d0)
	m.add(.w, d0, lbl('travel'))
	m.tst(.w, lbl('grace'))
	m.b(.eq, 'no_grace')
	m.sub(.w, imm(1), lbl('grace'))
	m.b(.ne, 'no_grace')
	g.say(9, 22, ' '.repeat(hint.len)) // the hint has been read
	m.label('no_grace')
	m.bsr('gates')
	m.bra('frame_done')

	// Dead: the ship is stuck in the gate, which keeps crackling. For the
	// first moments the gate's hum drowns the music.
	m.label('dead')
	m.bsr('gates')
	m.cmp(.w, imm(24), lbl('timer'))
	m.b(.cc, 'hum_over')
	m.move(.l, imm(hertz_step(55)), g.voice(voice_bass_step))
	m.move(.l, imm(kick_volume), g.voice(voice_bass_volume))
	m.move(.l, imm(zap_volume), g.voice(voice_noise_volume))
	m.label('hum_over')
	m.add(.w, imm(1), lbl('timer'))
	m.move(.w, lbl('timer'), d0)
	m.cmp(.w, imm(32), d0)
	m.b(.cs, 'still_exploding')
	m.move(.w, imm(scene_wreck), lbl('scene'))
	m.bra('exploded')
	m.label('still_exploding')
	m.and(.w, imm(0x18), d0) // a new picture every eight frames
	m.add(.w, imm(scene_blast), d0)
	m.move(.w, d0, lbl('scene'))
	m.label('exploded')
	m.cmp(.w, imm(30), lbl('timer'))
	m.b(.cs, 'frame_done')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_fire, d0)
	m.b(.eq, 'frame_done')
	m.bsr('start_game')
	m.bra('frame_done')

	m.label('start_game')
	m.move(.w, imm(0), lbl('score'))
	m.move(.w, imm(0), lbl('turn'))
	m.move(.w, imm(first_speed), lbl('speed'))
	m.move(.w, imm(widest_gap), lbl('gap_half'))
	m.move(.w, imm(grace_frames), lbl('grace'))
	m.move(.w, imm(state_play), lbl('state'))
	m.move(.w, imm(scene_ship), lbl('scene'))
	m.bsr('clear_text')
	g.say(9, 22, hint)
	m.bra('show_status')

	m.label('enter_title')
	m.move(.w, imm(state_title), lbl('state'))
	m.move(.w, imm(scene_title), lbl('scene'))
	m.move(.w, imm(widest_gap), lbl('gap_half'))
	m.bsr('clear_text')
	g.say(12, 15, 'PRESS A, B OR C')
	g.say(3, 18, 'THE GATES ARE LIVE. DO NOT TOUCH.')
	g.say(5, 20, 'LEFT AND RIGHT TURN THE TUNNEL')
	m.rts()

	m.label('show_status')
	g.say(2, 1, 'SCORE')
	g.say(27, 1, 'BEST')
	m.move(.w, lbl('best'), d0)
	m.bsr('number')
	m.moveq(32, d0)
	m.moveq(1, d1)
	m.bsr('print')
	m.label('show_score')
	m.move(.w, lbl('score'), d0)
	m.bsr('number')
	m.moveq(8, d0)
	m.moveq(1, d1)
	m.bra('print')
}

// gates moves both gates. A gate that has passed out of sight gets a new
// opening for its next pass; one that reaches the ship is a point or a
// wreck.
fn (mut g Game) gates() {
	mut m := g.m
	m.label('gates')
	m.lea(lbl('gate_0'), a5)
	m.bsr('gate')
	m.lea(lbl('gate_1'), a5)
	m.label('gate')
	m.move(.w, at(gate_ring, a5), d0)
	m.move(.w, lbl('travel'), d1)
	m.lsr(.w, imm(8), d1)
	m.sub(.w, d1, d0)
	m.and(.w, imm(0xff), d0) // depth of the gate's near edge
	m.cmp(.w, imm(128), d0)
	m.b(.ls, 'gate_near')
	m.move(.w, imm(0), at(gate_stage, a5))
	m.bra('gate_moved')
	m.label('gate_near')
	// Out of sight it gets the lane for its next pass, in two frames.
	m.cmp(.w, imm(hidden_depth), d0)
	m.b(.hi, 'gate_reaches_ship')
	m.cmp(.w, imm(1), d0)
	m.b(.cs, 'gate_reaches_ship')
	m.move(.w, at(gate_stage, a5), d1)
	m.cmp(.w, imm(2), d1)
	m.b(.cc, 'gate_reaches_ship')
	m.add(.w, imm(1), at(gate_stage, a5))
	m.move(.w, d0, d7)
	m.tst(.w, d1)
	m.b(.ne, 'second_part')
	m.bsr('erase_lane') // first the old lane goes, and a new opening is chosen
	m.bsr('random')
	m.and(.w, imm(127), d0)
	m.sub(.w, imm(64), d0)
	m.add(.w, lbl('last_gap'), d0)
	m.and(.w, imm(0xff), d0)
	m.move(.w, d0, at(gate_gap, a5))
	m.move(.w, d0, lbl('last_gap'))
	m.bra('part_done')
	m.label('second_part')
	m.bsr('lay_lane')
	m.label('part_done')
	m.move(.w, d7, d0)

	m.label('gate_reaches_ship')
	m.cmp(.w, imm(state_play), lbl('state'))
	m.b(.ne, 'gate_moved')
	m.tst(.w, lbl('grace'))
	m.b(.ne, 'gate_moved')
	m.cmp(.w, imm(ship_depth), d0)
	m.b(.hi, 'gate_moved')
	m.move(.w, at(gate_depth, a5), d1)
	m.cmp(.w, imm(ship_depth), d1)
	m.b(.ls, 'gate_moved')
	// It crossed the ship this frame. How far is the opening?
	m.move(.w, d0, at(gate_depth, a5))
	m.move(.w, lbl('rotation'), d1)
	m.lsr(.w, imm(8), d1)
	m.add(.w, imm(ship_angle), d1)
	m.sub(.w, at(gate_gap, a5), d1)
	m.ext(.w, d1)
	m.b(.pl, 'distance_known')
	m.neg(.w, d1)
	m.label('distance_known')
	m.add(.w, imm(ship_margin), d1)
	m.cmp(.w, lbl('gap_half'), d1)
	m.b(.hi, 'wreck')

	// Through: a point, a little faster, and every fourth gate tighter.
	m.add(.w, imm(1), lbl('score'))
	m.cmp(.w, imm(top_speed), lbl('speed'))
	m.b(.cc, 'fast_enough')
	m.add(.w, imm(speed_gain), lbl('speed'))
	m.label('fast_enough')
	m.move(.w, lbl('score'), d0)
	m.and(.w, imm(3), d0)
	m.b(.ne, 'wide_enough')
	m.cmp(.w, imm(tightest_gap), lbl('gap_half'))
	m.b(.ls, 'wide_enough')
	m.sub(.w, imm(1), lbl('gap_half'))
	m.label('wide_enough')
	m.move(.l, imm(phase_step(blip_note)), g.voice(voice_lead_step))
	m.move(.l, imm(lead_volume * 2), g.voice(voice_lead_volume))
	m.bra('show_score')

	m.label('wreck')
	m.move(.w, imm(state_dead), lbl('state'))
	m.move(.w, imm(0), lbl('timer'))
	m.move(.w, imm(0), lbl('speed')) // stopped dead, in the gate
	m.move(.w, imm(0), lbl('turn'))
	m.move(.w, lbl('score'), d0)
	m.cmp(.w, lbl('best'), d0)
	m.b(.ls, 'no_record')
	m.move(.w, d0, lbl('best'))
	m.label('no_record')
	g.say(11, 13, 'ZAPPED BY THE GATE')
	g.say(15, 16, 'PRESS FIRE')
	m.bra('show_status')

	m.label('gate_moved')
	m.move(.w, d0, at(gate_depth, a5))
	// The lightning changes on every other frame, the two gates in turn;
	// not while the gate is between its old lane and its new one.
	m.cmp(.w, imm(1), at(gate_stage, a5))
	m.b(.eq, 'no_spark')
	m.move(.w, lbl('frame'), d0)
	m.move(.w, at(gate_ring, a5), d1)
	m.lsr(.w, imm(7), d1)
	m.eor(.w, d1, d0)
	m.btst(0, d0)
	m.b(.eq, 'spark_gate')
	m.label('no_spark')
	m.rts()

	// random steps a 16-bit shift register and returns it in d0.
	m.label('random')
	m.move(.w, lbl('noise'), d0)
	m.lsr(.w, imm(1), d0)
	m.b(.cc, 'random_done')
	m.eor(.w, imm(0xb400), d0)
	m.label('random_done')
	m.move(.w, d0, lbl('noise'))
	m.rts()
}

// paint_gate holds the routines that draw the gate at a5 into the wall
// texture: the gate itself, a ring of lightning that changes all the time,
// and ahead of it the lane, a green strip between two rails that leads to
// the opening and through it.
fn (mut g Game) paint_gate() {
	mut m := g.m
	lane_bytes := lane_rings * 256

	// gate_base points a0 at the lane's first ring in the texture and a2
	// at the copy of the wall it covers.
	m.label('gate_base')
	m.moveq(0, d0)
	m.move(.w, at(gate_ring, a5), d0)
	m.sub(.w, imm(lane_rings), d0)
	m.lsl(.l, imm(8), d0)
	m.lea(lbl('texture'), a0)
	m.add(.l, d0, a0)
	m.move(.l, at(gate_wall, a5), a2)
	m.rts()

	// copy_arc copies d3 + 1 texels starting at angle d2 from each of
	// d6 + 1 rings at a4 to the rings at a3. The angle is a byte, so an arc
	// across angle 0 wraps by itself.
	m.label('copy_arc')
	m.moveq(0, d4)
	m.move(.b, d2, d4)
	m.move(.w, d3, d5)
	m.label('copy_texel')
	m.move(.b, idx(0, a4, d4), idx(0, a3, d4))
	m.add(.b, imm(1), d4)
	m.dbra(d5, 'copy_texel')
	m.lea(at(256, a3), a3)
	m.lea(at(256, a4), a4)
	m.dbra(d6, 'copy_arc')
	m.rts()

	// erase_lane restores the wall under the lane of the current opening.
	m.label('erase_lane')
	m.bsr('gate_base')
	m.move(.l, a0, a3)
	m.move(.l, a2, a4)
	m.move(.w, at(gate_gap, a5), d2)
	m.sub(.w, imm(widest_gap + 2), d2)
	m.moveq(2 * (widest_gap + 2) - 1, d3)
	m.moveq(lane_rings - 1, d6)
	m.bra('copy_arc')

	// lay_lane draws the lane to the current opening, and its rails.
	m.label('lay_lane')
	m.bsr('gate_base')
	m.move(.l, a0, a3)
	m.lea(lbl('lane'), a4)
	m.bsr('opening')
	m.moveq(lane_rings - 1, d6)
	m.bsr('copy_arc')
	m.move(.w, at(gate_gap, a5), d2) // two columns right of the opening
	m.add(.w, lbl('gap_half'), d2)
	m.bsr('rail')
	m.add(.w, imm(1), d2)
	m.bsr('rail')
	m.move(.w, at(gate_gap, a5), d2) // and two left of it
	m.sub(.w, lbl('gap_half'), d2)
	m.sub(.w, imm(1), d2)
	m.bsr('rail')
	m.sub(.w, imm(1), d2)
	m.label('rail')
	m.moveq(0, d4)
	m.move(.b, d2, d4)
	m.lea(idx(0, a0, d4), a3)
	m.moveq(lane_rings - 1, d5)
	m.label('rail_texel')
	m.move(.b, imm(rail_colour), ind(a3))
	m.lea(at(256, a3), a3)
	m.dbra(d5, 'rail_texel')
	m.rts()

	// opening leaves the first angle of the opening in d2 and its width,
	// less one, in d3.
	m.label('opening')
	m.move(.w, at(gate_gap, a5), d2)
	m.sub(.w, lbl('gap_half'), d2)
	m.move(.w, lbl('gap_half'), d3)
	m.add(.w, d3, d3)
	m.sub(.w, imm(1), d3)
	m.rts()

	// spark_gate redraws the gate with the next frame of lightning, then
	// lets the lane through it again.
	m.label('spark_gate')
	m.bsr('gate_base')
	m.lea(at(lane_bytes, a0), a3)
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.lsr(.w, imm(1), d0)
	m.and(.w, imm(spark_frames - 1), d0)
	m.mulu(imm(gate_rings * 256), d0)
	m.lea(lbl('sparks'), a1)
	m.add(.l, d0, a1)
	m.move(.w, imm(gate_rings * 256 / 4 - 1), d1)
	m.label('spark_long')
	m.move(.l, inc(a1), inc(a3))
	m.dbra(d1, 'spark_long')
	m.lea(at(lane_bytes, a0), a3)
	m.lea(lbl('lane'), a4)
	m.add(.l, imm(lane_bytes), a4)
	m.bsr('opening')
	m.moveq(gate_rings - 1, d6)
	m.bra('copy_arc')
}

// scroller moves the strip one pixel to the left and, every eighth frame,
// puts the next character of the message in its hidden right end.
fn (mut g Game) scroller() {
	mut m := g.m
	m.label('scroller')
	m.lea(abs(strip_address + strip_bytes * strip_lines), a0)
	m.moveq(strip_lines - 1, d1)
	m.label('shift_line')
	m.move(.l, dec(a0), d0)
	m.asl(.l, imm(1), d0) // the bit shifted out goes into X ...
	m.move(.l, d0, ind(a0))
	m.moveq(strip_bytes / 4 - 2, d2)
	m.label('shift_long')
	m.move(.l, dec(a0), d0)
	m.roxl(.l, imm(1), d0) // ... and from X into the long to the left
	m.move(.l, d0, ind(a0))
	m.dbra(d2, 'shift_long')
	m.dbra(d1, 'shift_line')

	m.add(.w, imm(1), lbl('scrolled'))
	m.move(.w, lbl('scrolled'), d0)
	m.and(.w, imm(7), d0)
	m.b(.ne, 'scroller_done')
	m.move(.l, lbl('message_at'), a0)
	m.moveq(0, d0)
	m.move(.b, inc(a0), d0)
	m.b(.ne, 'have_character')
	m.lea(lbl('message'), a0)
	m.move(.b, inc(a0), d0)
	m.label('have_character')
	m.move(.l, a0, lbl('message_at'))
	m.sub(.w, imm(font_first), d0)
	m.lsl(.w, imm(3), d0)
	m.lea(lbl('font'), a1)
	m.add(.w, d0, a1)
	m.lea(abs(strip_address + strip_bytes - 8), a2)
	m.moveq(7, d1)
	m.label('scroller_row')
	m.move(.b, inc(a1), ind(a2))
	m.lea(at(strip_bytes, a2), a2)
	m.dbra(d1, 'scroller_row')
	m.label('scroller_done')
	m.rts()
}

fn (mut g Game) text_routines() {
	mut m := g.m
	// print draws the zero-terminated string at a0 at column d0, row d1.
	m.label('print')
	m.mulu(imm(text_columns * 8), d1)
	m.add(.w, d0, d1)
	m.lea(abs(text_address), a1)
	m.add(.l, d1, a1)
	m.label('print_next')
	m.moveq(0, d2)
	m.move(.b, inc(a0), d2)
	m.b(.eq, 'print_done')
	m.sub(.w, imm(font_first), d2)
	m.lsl(.w, imm(3), d2)
	m.lea(lbl('font'), a2)
	m.add(.w, d2, a2)
	m.move(.l, a1, a3)
	m.moveq(7, d3)
	m.label('print_row')
	m.move(.b, inc(a2), ind(a3))
	m.lea(at(text_columns, a3), a3)
	m.dbra(d3, 'print_row')
	m.add(.l, imm(1), a1)
	m.bra('print_next')
	m.label('print_done')
	m.rts()

	// number writes d0 as five digits and leaves a0 pointing at them.
	m.label('number')
	m.lea(lbl('digits_end'), a0)
	m.moveq(4, d2)
	m.label('next_digit')
	m.and(.l, imm(0xffff), d0)
	m.divu(imm(10), d0)
	m.swap(d0) // the remainder
	m.add(.b, imm(int(`0`)), d0)
	m.move(.b, d0, dec(a0))
	m.move(.w, imm(0), d0)
	m.swap(d0) // the quotient
	m.dbra(d2, 'next_digit')
	m.rts()
	m.label('digits')
	m.bytes([]u8{len: 5})
	m.label('digits_end')
	m.byte(0)
	m.align(2)

	m.label('clear_text')
	m.lea(abs(text_address), a0)
	m.move(.w, imm(text_columns * text_rows * 8 / 4 - 1), d0)
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
	g.variable('state', state_title)
	g.variable('scene', scene_title)
	g.variable('frame', 0)
	g.variable('front', 0) // 0 while buffer A is shown, 4 for buffer B
	g.variable('rotation', 0)
	g.variable('travel', 0)
	g.variable('turn', 0)
	g.variable('speed', first_speed)
	g.variable('gap_half', widest_gap)
	g.variable('grace', 0)
	g.variable('timer', 0)
	g.variable('score', 0)
	g.variable('best', 0)
	g.variable('pad', 0)
	g.variable('pressed', 0)
	g.variable('noise', 0xace1)
	g.variable('last_gap', ship_angle)
	g.variable('scrolled', 0)
	g.variable('beat_tick', step_frames - 1)
	g.variable('step', 0xffff)
	g.variable('shown_x', window_x) // the window of the frame on screen
	g.variable('shown_y', window_y)
	m.label('profile')
	m.long(0)
	m.label('message_at')
	m.long_label('message')
	for i, ring in gate_rows {
		m.label('gate_${i}')
		m.word(ring)
		m.word(ship_angle + i * 40)
		m.word(0)
		m.word(0)
		m.long_label('wall_${i}')
	}
}
