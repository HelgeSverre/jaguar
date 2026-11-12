module main

import jagkit { abs, at, idx, imm, inc, ind, lbl, ptr }

// The 68000 side: start-up, and everything that happens once a frame in
// the vertical interrupt: showing the finished picture, flying, the beacon,
// the fuel and the remarks.

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
const text_address = u32(0x81000) // 320x200 at one bit a pixel
const points_address = u32(0x84000) // the GPU's projected points
const model_address = u32(0x85000) // the beacon's points, as the GPU reads them
const buffer_a = u32(0x90000) // two pictures, shown in turn
const buffer_b = u32(0xa0000)

const text_columns = 40
const text_rows = 25
const list_objects = 4
const list_bytes = 32 + list_objects * 32

// Game states.
const state_title = 0
const state_play = 1
const state_dead = 2

// Pad bits, as `read_pad` leaves them.
const pad_fire = 0
const pad_up = 4
const pad_down = 5
const pad_left = 6
const pad_right = 7

// Tuning. Angles are 256 to the turn and kept as 8.8 fixed point;
// distances are in units, 256 to a cell.
const turn_gain = 10
const top_turn = 0x0180 // a turn and a half of the angle unit a frame
const climb_gain = 2
const top_climb = 22
const cruise = 14 // units a frame
const ceiling = 1000
const clearance = 24 // the eye has to stay this far above the ground
const start_height = 720 // above every hill
const horizon_line = 64 // the eye looks a little down, to see the ground from up here
const beacon_radius = 70
const beacon_reach = 170 // how close counts as flying through it
const beacon_above = 230 // how high over the ground it hangs
const frames_a_second = 60
const full_tank = 40 * frames_a_second
const refuel = 12 * frames_a_second
const engine_volume = 2200
const blip_volume = 7000
const crash_volume = 12000

// Colour numbers.
const colour_text = 17
const colour_logo = 19
const colour_shadow = 21

// What the onboard computer has to say about a crash. Every other remark
// is the old favourite.
const favourite = 'WHERE DID YOU LEARN TO FLY?'
const remarks = [
	favourite,
	'THAT WAS A HILL. HILLS ARE SOLID.',
	favourite,
	'DOWN CLIMBS. UP DIVES. TRY AGAIN.',
	favourite,
	'I HAVE SEEN BRICKS GLIDE BETTER.',
	favourite,
	'THE GROUND WAS THERE ALL ALONG.',
]
const out_of_fuel = 'FUEL IS NOT A SUGGESTION.'

struct Flight {
	mailbox u32 // the values shared with the GPU
	voices  u32 // the DSP's voice settings
mut:
	m &jagkit.M68k
}

fn (f &Flight) shared_at(offset int) jagkit.Ea {
	return abs(f.mailbox + u32(offset))
}

fn (f &Flight) voice(offset int) jagkit.Ea {
	return abs(f.voices + u32(offset))
}

// say prints a string constant at a text cell.
fn (mut f Flight) say(column int, row int, text string) {
	name := f.m.unique('text')
	skip := f.m.unique('after')
	f.m.lea(lbl(name), a0)
	f.m.moveq(column, d0)
	f.m.moveq(row, d1)
	f.m.bsr('print')
	f.m.bra(skip)
	f.m.label(name)
	f.m.text(text)
	f.m.label(skip)
}

// centred prints a string constant in the middle of a row.
fn (mut f Flight) centred(row int, text string) {
	f.say((text_columns - text.len) / 2, row, text)
}

// variable reserves a word of game state.
fn (mut f Flight) variable(name string, initial int) {
	f.m.label(name)
	f.m.word(initial)
}

// fade lets a voice's volume decay by 1/2^shift a frame, down to silence.
fn (mut f Flight) fade(volume jagkit.Ea, shift int) {
	mut m := f.m
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

// limit keeps a signed word register within -bound..bound.
fn (mut f Flight) limit(register jagkit.Ea, bound int) {
	mut m := f.m
	low := m.unique('low')
	high := m.unique('high')
	m.cmp(.w, imm(bound), register)
	m.b(.le, high)
	m.move(.w, imm(bound), register)
	m.label(high)
	m.cmp(.w, imm(-bound), register)
	m.b(.ge, low)
	m.move(.w, imm(-bound), register)
	m.label(low)
}

// steer changes a signed word register: up by `gain` while one pad button
// is held, down while the other is, and back towards zero by an eighth a
// frame while neither is. d7 holds the pad.
fn (mut f Flight) steer(register jagkit.Ea, more int, less int, gain int) {
	mut m := f.m
	not_more := m.unique('not_more')
	not_less := m.unique('not_less')
	held := m.unique('held')
	moving := m.unique('moving')
	m.btst(more, d7)
	m.b(.eq, not_more)
	m.add(.w, imm(gain), register)
	m.label(not_more)
	m.btst(less, d7)
	m.b(.eq, not_less)
	m.sub(.w, imm(gain), register)
	m.label(not_less)
	m.move(.w, d7, d1)
	m.and(.w, imm((1 << more) | (1 << less)), d1)
	m.b(.ne, held)
	m.move(.w, register, d1)
	m.asr(.w, imm(3), d1)
	m.b(.ne, moving)
	m.moveq(0, register)
	m.label(moving)
	m.sub(.w, d1, register)
	m.label(held)
}

fn (mut f Flight) start_up(gpu_longs int, dsp_longs int, dsp_start u32) {
	mut m := f.m
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
	m.move(.w, imm(0), abs(jagkit.clut + 2 * colour_shadow))
	m.move(.w, imm(jagkit.cry(255, 230, 140)), abs(jagkit.clut + 2 * colour_text))

	// Blank everything that is shown.
	m.bsr('clear_text')
	m.lea(abs(buffer_a), a0)
	m.move(.w, imm(screen_width * screen_height / 4 - 1), d0)
	m.bsr('clear')
	m.lea(abs(buffer_b), a0)
	m.move(.w, imm(screen_width * screen_height / 4 - 1), d0)
	m.bsr('clear')
	m.bsr('enter_title')
	m.bsr('place_beacon')

	// The GPU: load it, tell it where its data is, start it.
	m.lea(lbl('gpu_program'), a0)
	m.lea(abs(jagkit.gpu_ram), a1)
	m.move(.w, imm(gpu_longs - 1), d0)
	m.bsr('copy')
	m.bsr('publish')
	m.move(.l, imm(buffer_b), f.shared_at(shared_first))
	m.move(.l, imm(buffer_a), f.shared_at(shared_second))
	m.move(.l, ptr('heights'), f.shared_at(shared_heights))
	m.move(.l, imm(points_address), f.shared_at(shared_points))
	m.move(.l, imm(model_address), f.shared_at(shared_model))
	m.move(.l, imm(beacon_points), f.shared_at(shared_model_points))
	m.move(.l, ptr('beacon_lines'), f.shared_at(shared_model_lines))
	m.move(.l, imm(beacon_lines.len / 2), f.shared_at(shared_model_line_count))
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

fn (mut f Flight) frame_interrupt() {
	mut m := f.m
	everything := [d0, d1, d2, d3, d4, d5, d6, d7, a0, a1, a2, a3, a4, a5, a6]
	m.label('frame_interrupt')
	m.push(everything)

	// Show the picture the GPU has finished, and let it start the next.
	m.move(.l, f.shared_at(shared_finished), d0)
	m.b(.eq, 'no_new_frame')
	m.move(.w, imm(0), lbl('front'))
	m.cmp(.l, imm(buffer_b), d0)
	m.b(.ne, 'front_known')
	m.move(.w, imm(4), lbl('front'))
	m.label('front_known')
	m.bsr('publish')
	m.move(.l, imm(0), f.shared_at(shared_finished))
	m.label('no_new_frame')
	m.bsr('refresh_list')
	m.move(.w, imm(jagkit.int1_video | jagkit.int1_video_ack), abs(jagkit.int1))
	m.move(.w, imm(0), abs(jagkit.int2))

	m.add(.w, imm(1), lbl('frame'))
	m.bsr('colours')
	m.bsr('read_pad')
	m.bsr('sound')

	m.move(.w, lbl('state'), d0)
	m.b(.eq, 'title')
	m.cmp(.w, imm(state_play), d0)
	m.b(.eq, 'play')
	m.bra('dead')
	m.label('frame_done')
	m.pop(everything)
	m.rte()

	// refresh_list copies the list for the current state and front buffer
	// into place: the object processor consumed the last copy.
	m.label('refresh_list')
	m.move(.l, lbl('profile'), a0)
	m.moveq(0, d0)
	m.move(.w, lbl('front'), d0)
	m.tst(.w, lbl('state'))
	m.b(.eq, 'list_chosen')
	m.add(.w, imm(8), d0)
	m.label('list_chosen')
	m.move(.l, idx(8, a0, d0), a1)
	m.lea(abs(list_address), a2)
	m.moveq(list_bytes / 4 - 1, d1)
	m.label('copy_list')
	m.move(.l, inc(a1), inc(a2))
	m.dbra(d1, 'copy_list')
	m.rts()
}

// colours sets the palette: the landscape's eight greens, or reds while a
// crash is fresh, and the colours that cycle.
fn (mut f Flight) colours() {
	mut m := f.m
	m.label('colours')
	m.lea(lbl('greens'), a0)
	m.cmp(.w, imm(state_dead), lbl('state'))
	m.b(.ne, 'ramp_chosen')
	m.cmp(.w, imm(40), lbl('timer'))
	m.b(.cc, 'ramp_chosen')
	m.lea(lbl('reds'), a0)
	m.label('ramp_chosen')
	m.lea(abs(jagkit.clut + 2), a1)
	m.moveq(7, d0)
	m.label('copy_ramp')
	m.move(.w, inc(a0), inc(a1))
	m.dbra(d0, 'copy_ramp')
	m.moveq(0, d0)
	m.move(.w, lbl('frame'), d0)
	m.and(.w, imm(63), d0)
	m.add(.w, d0, d0)
	m.lea(lbl('rainbow'), a0)
	m.move(.w, idx(0, a0, d0), abs(jagkit.clut + 2 * model_colour))
	m.eor(.w, imm(64), d0)
	m.move(.w, idx(0, a0, d0), abs(jagkit.clut + 2 * colour_logo))
	m.rts()
}

// read_pad leaves the held buttons in `pad` and the newly pressed ones in
// `pressed`: bit 0 any fire button, bits 4 to 7 up, down, left, right.
fn (mut f Flight) read_pad() {
	mut m := f.m
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
	m.lsr(.w, imm(4), d0)
	m.and(.w, imm(0xf0), d0)
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

// sound keeps the engine droning, beeps when the fuel is low and fades the
// rest.
fn (mut f Flight) sound() {
	mut m := f.m
	m.label('sound')
	m.move(.l, imm(jagkit.hertz_step(62)), f.voice(jagkit.voice_bass_step))
	m.move(.l, imm(0), f.voice(jagkit.voice_bass_volume))
	m.cmp(.w, imm(state_play), lbl('state'))
	m.b(.ne, 'engine_set')
	m.move(.l, imm(engine_volume), f.voice(jagkit.voice_bass_volume))
	m.cmp(.w, imm(10 * frames_a_second), lbl('fuel'))
	m.b(.cc, 'engine_set')
	m.move(.w, lbl('frame'), d0)
	m.and(.w, imm(31), d0)
	m.b(.ne, 'engine_set')
	m.move(.l, imm(jagkit.note_step(88)), f.voice(jagkit.voice_lead_step))
	m.move(.l, imm(blip_volume / 2), f.voice(jagkit.voice_lead_volume))
	m.label('engine_set')
	f.fade(f.voice(jagkit.voice_lead_volume), 2)
	f.fade(f.voice(jagkit.voice_noise_volume), 4)
	m.rts()
}

fn (mut f Flight) states() {
	mut m := f.m

	// Title: the plane flies itself in a wide circle.
	m.label('title')
	m.move(.w, imm(0x0060), lbl('turn'))
	m.move(.w, imm(0), lbl('climb'))
	m.bsr('fly')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_fire, d0)
	m.b(.eq, 'frame_done')
	m.bsr('start_game')
	m.bra('frame_done')

	// Play.
	m.label('play')
	m.move(.w, lbl('pad'), d7)
	m.move(.w, lbl('turn'), d0)
	f.steer(d0, pad_right, pad_left, turn_gain)
	f.limit(d0, top_turn)
	m.move(.w, d0, lbl('turn'))
	m.move(.w, lbl('climb'), d0)
	f.steer(d0, pad_down, pad_up, climb_gain) // pull back to climb
	f.limit(d0, top_climb)
	m.move(.w, d0, lbl('climb'))
	m.bsr('fly')

	// Into the ground?
	m.move(.w, lbl('eye_x'), d0)
	m.move(.w, lbl('eye_z'), d1)
	m.bsr('ground')
	m.add(.w, imm(clearance), d0)
	m.cmp(.w, lbl('eye_y'), d0)
	m.b(.le, 'still_flying')
	m.lea(lbl('remark_list'), a1)
	m.move(.w, lbl('crashes'), d0)
	m.add(.w, imm(1), lbl('crashes'))
	m.and(.w, imm(remarks.len - 1), d0)
	m.mulu(imm(6), d0)
	m.add(.l, d0, a1)
	m.bra('game_over')
	m.label('still_flying')

	// Out of fuel?
	m.sub(.w, imm(1), lbl('fuel'))
	m.b(.ne, 'have_fuel')
	m.lea(lbl('fuel_remark'), a1)
	m.bra('game_over')
	m.label('have_fuel')

	// Through the beacon?
	m.bsr('beacon_offset')
	for register in [d0, d1, d2] {
		positive := m.unique('positive')
		m.tst(.w, register)
		m.b(.pl, positive)
		m.neg(.w, register)
		m.label(positive)
	}
	m.cmp(.w, imm(beacon_reach), d0)
	m.b(.hi, 'beacon_missed')
	m.cmp(.w, imm(beacon_reach), d2)
	m.b(.hi, 'beacon_missed')
	m.cmp(.w, imm(beacon_reach + 60), d1)
	m.b(.hi, 'beacon_missed')
	m.add(.w, imm(1), lbl('score'))
	m.add(.w, imm(refuel), lbl('fuel'))
	m.cmp(.w, imm(full_tank), lbl('fuel'))
	m.b(.ls, 'tank_holds')
	m.move(.w, imm(full_tank), lbl('fuel'))
	m.label('tank_holds')
	m.move(.l, imm(jagkit.note_step(84)), f.voice(jagkit.voice_lead_step))
	m.move(.l, imm(blip_volume), f.voice(jagkit.voice_lead_volume))
	m.bsr('place_beacon')
	m.label('beacon_missed')
	m.bsr('show_status')
	m.bsr('show_bearing')
	m.bra('frame_done')

	// game_over ends the flight with the remark at a1: a column, then the
	// address of the text.
	m.label('game_over')
	m.move(.w, imm(state_dead), lbl('state'))
	m.move(.w, imm(0), lbl('timer'))
	m.move(.l, imm(crash_volume), f.voice(jagkit.voice_noise_volume))
	m.move(.w, lbl('score'), d0)
	m.cmp(.w, lbl('best'), d0)
	m.b(.ls, 'no_record')
	m.move(.w, d0, lbl('best'))
	m.label('no_record')
	m.move(.l, a1, dec_sp())
	m.bsr('clear_text')
	m.bsr('show_status')
	m.move(.l, inc(sp), a1)
	m.moveq(0, d0)
	m.move(.w, inc(a1), d0)
	m.move(.l, ind(a1), a0)
	m.moveq(9, d1)
	m.bsr('print')
	f.centred(12, 'PRESS FIRE')
	m.bra('frame_done')

	// Dead: wait for a fire button.
	m.label('dead')
	m.add(.w, imm(1), lbl('timer'))
	m.cmp(.w, imm(30), lbl('timer'))
	m.b(.cs, 'frame_done')
	m.move(.w, lbl('pressed'), d0)
	m.btst(pad_fire, d0)
	m.b(.eq, 'frame_done')
	m.bsr('start_game')
	m.bra('frame_done')

	m.label('start_game')
	m.move(.w, imm(state_play), lbl('state'))
	m.move(.w, imm(0), lbl('score'))
	m.move(.w, imm(0), lbl('turn'))
	m.move(.w, imm(0), lbl('climb'))
	m.move(.w, imm(start_height), lbl('eye_y'))
	m.move(.w, imm(full_tank), lbl('fuel'))
	m.bsr('place_beacon')
	m.bsr('clear_text')
	m.bra('show_status')

	m.label('enter_title')
	m.move(.w, imm(state_title), lbl('state'))
	m.move(.w, imm(start_height), lbl('eye_y'))
	m.bsr('clear_text')
	f.centred(11, 'PRESS A, B OR C')
	f.centred(14, 'LEFT AND RIGHT BANK')
	f.centred(16, 'DOWN CLIMBS, UP DIVES')
	f.centred(19, 'FLY THROUGH THE BEACONS')
	f.centred(21, 'BEFORE THE FUEL RUNS OUT')
	m.rts()

	m.label('show_status')
	f.say(1, 0, 'SCORE')
	f.say(15, 0, 'FUEL')
	f.say(29, 0, 'BEST')
	m.move(.w, lbl('best'), d0)
	m.bsr('number')
	m.moveq(34, d0)
	m.moveq(0, d1)
	m.bsr('print')
	m.moveq(0, d0)
	m.move(.w, lbl('fuel'), d0)
	m.divu(imm(frames_a_second), d0)
	m.bsr('number')
	m.moveq(20, d0)
	m.moveq(0, d1)
	m.bsr('print')
	m.move(.w, lbl('score'), d0)
	m.bsr('number')
	m.moveq(7, d0)
	m.moveq(0, d1)
	m.bra('print')
}

// dec_sp is `-(sp)`.
fn dec_sp() jagkit.Ea {
	return jagkit.dec(sp)
}

// fly moves the plane a frame's worth along its heading and tells the GPU
// where it is.
fn (mut f Flight) fly() {
	mut m := f.m
	m.label('fly')
	m.move(.w, lbl('turn'), d0)
	m.add(.w, d0, lbl('heading'))
	m.move(.w, lbl('climb'), d0)
	m.add(.w, d0, lbl('eye_y'))
	m.cmp(.w, imm(ceiling), lbl('eye_y'))
	m.b(.le, 'under_ceiling')
	m.move(.w, imm(ceiling), lbl('eye_y'))
	m.label('under_ceiling')
	m.move(.w, lbl('heading'), d0)
	m.lsr(.w, imm(8), d0)
	m.move(.w, d0, d2)
	m.bsr('sine')
	m.muls(imm(cruise), d0)
	m.asl(.l, imm(2), d0)
	m.swap(d0) // sine * speed, down from 2.14
	m.add(.w, d0, lbl('eye_x'))
	m.move(.w, d2, d0)
	m.add(.w, imm(64), d0)
	m.bsr('sine')
	m.muls(imm(cruise), d0)
	m.asl(.l, imm(2), d0)
	m.swap(d0)
	m.add(.w, d0, lbl('eye_z'))
	m.rts()

	// sine returns the sine of angle d0 (256 to the turn) as 2.14 fixed
	// point in d0. For a cosine add 64 first.
	m.label('sine')
	m.and(.l, imm(0xff), d0)
	m.add(.w, d0, d0)
	m.lea(lbl('sines'), a0)
	m.move(.w, idx(0, a0, d0), d0)
	m.rts()

	// publish gives the GPU the view: where the eye is and how it is
	// turned and banked.
	m.label('publish')
	m.moveq(0, d0)
	m.move(.w, lbl('eye_x'), d0)
	m.move(.l, d0, f.shared_at(shared_eye_x))
	m.move(.w, lbl('eye_z'), d0)
	m.move(.l, d0, f.shared_at(shared_eye_z))
	m.move(.w, lbl('eye_y'), d0)
	m.move(.l, d0, f.shared_at(shared_eye_y))
	m.move(.w, lbl('heading'), d2)
	m.lsr(.w, imm(8), d2)
	m.move(.w, d2, d0)
	m.bsr('sine')
	m.ext(.l, d0)
	m.move(.l, d0, f.shared_at(shared_yaw_sin))
	m.move(.w, d2, d0)
	m.add(.w, imm(64), d0)
	m.bsr('sine')
	m.ext(.l, d0)
	m.move(.l, d0, f.shared_at(shared_yaw_cos))
	// The bank follows the turn; the horizon drops in a climb.
	m.move(.w, lbl('turn'), d2)
	m.asr(.w, imm(4), d2)
	m.move(.w, d2, d0)
	m.bsr('sine')
	m.ext(.l, d0)
	m.move(.l, d0, f.shared_at(shared_roll_sin))
	m.move(.w, d2, d0)
	m.add(.w, imm(64), d0)
	m.bsr('sine')
	m.ext(.l, d0)
	m.move(.l, d0, f.shared_at(shared_roll_cos))
	m.move(.w, lbl('climb'), d0)
	m.add(.w, d0, d0)
	m.add(.w, imm(horizon_line), d0)
	m.ext(.l, d0)
	m.move(.l, d0, f.shared_at(shared_horizon))

	// The beacon: two tips and a square that spins between them, as
	// offsets from the eye.
	m.bsr('beacon_offset')
	m.move(.w, d0, d3) // right
	m.move(.w, d1, d4) // up
	m.move(.w, d2, d5) // ahead
	m.move(.w, lbl('frame'), d0)
	m.add(.w, d0, d0)
	m.move(.w, d0, d2)
	m.bsr('sine')
	m.muls(imm(beacon_radius), d0)
	m.asl(.l, imm(2), d0)
	m.swap(d0)
	m.move(.w, d0, d6) // radius * sine
	m.move(.w, d2, d0)
	m.add(.w, imm(64), d0)
	m.bsr('sine')
	m.muls(imm(beacon_radius), d0)
	m.asl(.l, imm(2), d0)
	m.swap(d0)
	m.move(.w, d0, d7) // radius * cosine
	m.lea(abs(model_address), a1)
	// Each corner of the square is the one before, turned a quarter.
	for tip in [beacon_radius * 3 / 2, -beacon_radius * 3 / 2] {
		m.move(.w, d3, d0)
		m.move(.w, d4, d1)
		m.add(.w, imm(tip), d1)
		m.move(.w, d5, d2)
		m.bsr('put_point')
	}
	for _ in 0 .. 4 {
		m.move(.w, d3, d0)
		m.add(.w, d7, d0)
		m.move(.w, d4, d1)
		m.move(.w, d5, d2)
		m.add(.w, d6, d2)
		m.bsr('put_point')
		m.move(.w, d7, d0) // (cosine, sine) becomes (-sine, cosine)
		m.move(.w, d6, d7)
		m.neg(.w, d7)
		m.move(.w, d0, d6)
	}
	m.rts()

	// put_point stores the words d0, d1, d2 as longs at a1.
	m.label('put_point')
	m.ext(.l, d0)
	m.move(.l, d0, inc(a1))
	m.ext(.l, d1)
	m.move(.l, d1, inc(a1))
	m.ext(.l, d2)
	m.move(.l, d2, inc(a1))
	m.rts()
}

// beacon holds what concerns the beacon and the ground.
fn (mut f Flight) beacon() {
	mut m := f.m
	// beacon_offset leaves how far the beacon is to the east, above and
	// to the north of the eye in d0, d1, d2. The world wraps, and so do
	// the words.
	m.label('beacon_offset')
	m.move(.w, lbl('beacon_x'), d0)
	m.sub(.w, lbl('eye_x'), d0)
	m.move(.w, lbl('beacon_y'), d1)
	m.sub(.w, lbl('eye_y'), d1)
	m.move(.w, lbl('beacon_z'), d2)
	m.sub(.w, lbl('eye_z'), d2)
	m.rts()

	// place_beacon puts the beacon three to eleven cells away in each
	// direction, over the ground there.
	m.label('place_beacon')
	for coordinate in ['x', 'z'] {
		ahead := m.unique('ahead')
		m.bsr('random')
		m.move(.w, d0, d1)
		m.and(.w, imm(0x07ff), d0)
		m.add(.w, imm(3 * cell), d0)
		m.btst(15, d1)
		m.b(.eq, ahead)
		m.neg(.w, d0)
		m.label(ahead)
		m.add(.w, lbl('eye_${coordinate}'), d0)
		m.move(.w, d0, lbl('beacon_${coordinate}'))
	}
	m.move(.w, lbl('beacon_x'), d0)
	m.move(.w, lbl('beacon_z'), d1)
	m.bsr('ground')
	m.add(.w, imm(beacon_above), d0)
	m.move(.w, d0, lbl('beacon_y'))
	m.rts()

	// ground returns in d0 the height of the highest corner of the cell
	// that holds the point d0 east, d1 north.
	m.label('ground')
	m.lsr(.w, imm(8), d0)
	m.lsr(.w, imm(8), d1)
	m.lea(lbl('heights'), a0)
	m.moveq(0, d6)
	for corner in 0 .. 4 {
		lower := m.unique('lower')
		m.move(.w, d1, d4)
		if corner >= 2 {
			m.add(.w, imm(1), d4)
		}
		m.and(.l, imm(map_size - 1), d4)
		m.lsl(.w, imm(5), d4)
		m.move(.w, d0, d5)
		if corner % 2 == 1 {
			m.add(.w, imm(1), d5)
		}
		m.and(.w, imm(map_size - 1), d5)
		m.add(.w, d5, d4)
		m.moveq(0, d5)
		m.move(.b, idx(0, a0, d4), d5)
		m.cmp(.w, d6, d5)
		m.b(.ls, lower)
		m.move(.w, d5, d6)
		m.label(lower)
	}
	m.move(.w, d6, d0)
	m.lsl(.w, imm(height_shift), d0)
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

	// show_bearing points at the beacon: arrows to the side it is on, or
	// up when it is ahead.
	m.label('show_bearing')
	m.bsr('beacon_offset')
	m.move(.w, d0, d3)
	m.move(.w, d2, d5)
	m.move(.w, lbl('heading'), d0)
	m.lsr(.w, imm(8), d0)
	m.move(.w, d0, d2)
	m.bsr('sine')
	m.move(.w, d0, d6)
	m.move(.w, d2, d0)
	m.add(.w, imm(64), d0)
	m.bsr('sine')
	m.move(.w, d0, d7)
	m.move(.w, d3, d0)
	m.muls(d7, d0)
	m.move(.w, d5, d1)
	m.muls(d6, d1)
	m.sub(.l, d1, d0) // how far to the right of the nose
	m.muls(d6, d3)
	m.muls(d7, d5)
	m.add(.l, d3, d5) // how far ahead
	m.lea(lbl('bearing_ahead'), a0)
	m.move(.l, d0, d1)
	m.b(.pl, 'right_side')
	m.neg(.l, d1)
	m.label('right_side')
	m.asl(.l, imm(1), d1)
	m.cmp(.l, d5, d1)
	m.b(.lt, 'bearing_known') // less than half as far aside as ahead
	m.lea(lbl('bearing_right'), a0)
	m.tst(.l, d0)
	m.b(.pl, 'bearing_known')
	m.lea(lbl('bearing_left'), a0)
	m.label('bearing_known')
	m.moveq(13, d0)
	m.moveq(23, d1)
	m.bra('print')
	m.label('bearing_ahead')
	m.text('    BEACON    ')
	m.label('bearing_left')
	m.text('<<  BEACON    ')
	m.label('bearing_right')
	m.text('    BEACON  >>')
}

fn (mut f Flight) text_routines() {
	mut m := f.m
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
	m.sub(.w, imm(jagkit.font_first), d2)
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

	// number writes d0 as three digits and leaves a0 pointing at them.
	m.label('number')
	m.lea(lbl('digits_end'), a0)
	m.moveq(2, d2)
	m.label('next_digit')
	m.and(.l, imm(0xffff), d0)
	m.divu(imm(10), d0)
	m.swap(d0) // the remainder
	m.add(.b, imm(int(`0`)), d0)
	m.move(.b, d0, jagkit.dec(a0))
	m.move(.w, imm(0), d0)
	m.swap(d0) // the quotient
	m.dbra(d2, 'next_digit')
	m.rts()
	m.label('digits')
	m.bytes([]u8{len: 3})
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

fn (mut f Flight) variables() {
	mut m := f.m
	f.variable('state', state_title)
	f.variable('frame', 0)
	f.variable('front', 0) // 0 while buffer A is shown, 4 for buffer B
	f.variable('heading', 0)
	f.variable('turn', 0)
	f.variable('climb', 0)
	f.variable('eye_x', 16 * cell)
	f.variable('eye_z', 16 * cell)
	f.variable('eye_y', start_height)
	f.variable('beacon_x', 0)
	f.variable('beacon_y', 0)
	f.variable('beacon_z', 0)
	f.variable('fuel', full_tank)
	f.variable('score', 0)
	f.variable('best', 0)
	f.variable('crashes', 0)
	f.variable('timer', 0)
	f.variable('pad', 0)
	f.variable('pressed', 0)
	f.variable('noise', 0xace1)
	m.label('profile')
	m.long(0)

	// The remarks: for each the column that centres it and its address.
	m.label('remark_list')
	for i, remark in remarks {
		m.word((text_columns - remark.len) / 2)
		m.long_label('remark_${i}')
	}
	m.label('fuel_remark')
	m.word((text_columns - out_of_fuel.len) / 2)
	m.long_label('remark_fuel')
	for i, remark in remarks {
		m.label('remark_${i}')
		m.text(remark)
	}
	m.label('remark_fuel')
	m.text(out_of_fuel)
}
