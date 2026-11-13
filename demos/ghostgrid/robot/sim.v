// The robot of GHOSTGRID's tests: it plays the game through the pad, on the
// emulated machine and in the interpreter, reading the game's variables by
// name, and finds a way through a mission that no guard or camera sees.
//
// This is a module of its own, not part of the game, so that the game's build
// does not link the emulator, and so that every test file of the demo can
// use it (each `_test.v` compiles alone).
module robot

import jaggame
import jaggame.emulated
import jerry

// Spec is what the robot has to be told about the game: how to build and
// describe it, and the size and the maps of its rooms.
pub struct Spec {
pub:
	build    fn () !jaggame.Image @[required]
	describe fn () &jaggame.Game  @[required]
	cols     int
	rows     int
	maps     []string // the map of every room
	first    []int    // the first room of every mission
	rooms    []int    // how many rooms every mission has
	range    int      // the reach of a guard's cone, pixels
	half     int      // and its half angle
	image    jaggame.Image
}

// the scenes, in the order the game declares them
pub const scene_title = 0
pub const scene_picker = 1
pub const scene_brief = 2
pub const scene_play = 3
pub const scene_result = 4

// the guards' states
pub const state_names = ['patrol', 'suspicious', 'alert', 'search', 'return']
pub const patrol = 0
pub const suspicious = 1
pub const alert = 2
pub const search = 3
pub const returning = 4

// Sim is a running game that a robot can play: one frame at a time with a
// pad, and the game's variables by name.
pub interface Sim {
	value(name string) int
	element(name string, index int) int
	field(array string, index int, field string) int
mut:
	frame(mask u32)
	poke(name string, raw int)
	poke_element(name string, index int, raw int)
	poke_field(array string, index int, field string, raw int)
}

// fixed_of is a 16.16 number as a float.
pub fn fixed_of(raw int) f64 {
	return f64(raw) / 65536.0
}

// the buttons the robot can press, and the pad bits of the interpreter.
const robot_buttons = [jerry.Button.up, .down, .left, .right, .a, .b, .c, .pause, .option]
const robot_masks = [jaggame.Button.up, .down, .left, .right, .a, .b, .c, .pause, .option]

// pad is the pad value with the given buttons held.
pub fn pad(buttons ...jaggame.Button) u32 {
	mut mask := u32(0)
	for b in buttons {
		mask |= jaggame.button_mask(b)
	}
	return mask
}

// button_bits is a pad value as the machine holds it, a bit per
// `jerry.Button`, the form `cli.presses_of` reads.
pub fn button_bits(mask u32) u32 {
	mut bits := u32(0)
	for i, button in robot_masks {
		if mask & jaggame.button_mask(button) != 0 {
			bits |= u32(1) << u32(robot_buttons[i])
		}
	}
	return bits
}

// hold_pad presses exactly the buttons of a pad value on the first pad.
fn hold_pad(mut p emulated.Player, mask u32) {
	for i, button in robot_masks {
		if mask & jaggame.button_mask(button) != 0 {
			p.press(robot_buttons[i])
		} else {
			p.release(robot_buttons[i])
		}
	}
}

// Booted is the game on the emulated machine.
pub struct Booted {
pub:
	img jaggame.Image
pub mut:
	p       emulated.Player
	pad_log []u32 // the pad of every frame played so far
	pal     bool
	// where the logical screen's top left corner is in the emulator's picture
	ox int
	oy int
}

// boot starts the game on the machine, NTSC or PAL.
pub fn (s &Spec) boot(pal bool) &Booted {
	return &Booted{
		img: s.image
		p:   emulated.boot(s.image.bytes, pal) or { panic(err) }
		pal: pal
	}
}

pub fn (mut b Booted) frame(mask u32) {
	hold_pad(mut b.p, mask)
	b.p.frames(1)
	b.pad_log << mask
}

pub fn (b &Booted) value(name string) int {
	return int(b.img.value(b.p.m.ram, name) or { panic(err) })
}

pub fn (b &Booted) element(name string, index int) int {
	return int(b.img.element(b.p.m.ram, name, index) or { panic(err) })
}

pub fn (b &Booted) field(array string, index int, field string) int {
	return int(b.img.field(b.p.m.ram, array, index, field) or { panic(err) })
}

pub fn (mut b Booted) poke(name string, raw int) {
	b.poke_element(name, 0, raw)
}

pub fn (mut b Booted) poke_element(name string, index int, raw int) {
	at, size := b.img.address_of_element(name, index) or { panic(err) }
	b.write(at, size, raw)
}

pub fn (mut b Booted) poke_field(array string, index int, field string, raw int) {
	at := b.img.field_address(array, index, field) or { panic(err) }
	b.write(at, b.img.field_size(array, field) or { panic(err) }, raw)
}

fn (mut b Booted) write(at u32, size int, raw int) {
	for k in 0 .. size {
		b.p.m.ram[at + u32(k)] = u8(raw >> u32(8 * (size - 1 - k)))
	}
}

// Rig is the game in the interpreter.
pub struct Rig {
pub mut:
	g       &jaggame.Game
	it      &jaggame.Interpreter
	pad_log []u32
}

// rig starts the game in the interpreter, as on NTSC or PAL.
pub fn (s &Spec) rig(pal bool) &Rig {
	mut g := s.describe()
	it := g.interpreter(if pal { jaggame.Region.pal } else { jaggame.Region.ntsc }) or {
		panic(err)
	}
	return &Rig{
		g:  g
		it: it
	}
}

pub fn (mut r Rig) frame(mask u32) {
	r.pad_log << mask
	r.g.step(mut r.it, mask) or { panic(err) }
}

pub fn (r &Rig) value(name string) int {
	return int(r.it.value(name) or { panic(err) })
}

pub fn (r &Rig) element(name string, index int) int {
	return int(r.it.element(name, index) or { panic(err) })
}

pub fn (r &Rig) field(array string, index int, field string) int {
	return int(r.it.field(array, index, field) or { panic(err) })
}

pub fn (mut r Rig) poke(name string, raw int) {
	r.it.set_value(name, raw) or { panic(err) }
}

pub fn (mut r Rig) poke_element(name string, index int, raw int) {
	r.it.set_element(name, index, raw) or { panic(err) }
}

pub fn (mut r Rig) poke_field(array string, index int, field string, raw int) {
	r.it.set_field(array, index, field, raw) or { panic(err) }
}

// ---- reading the game ----

pub fn px_of(s Sim) f64 {
	return fixed_of(s.value('px'))
}

pub fn py_of(s Sim) f64 {
	return fixed_of(s.value('py'))
}

pub fn gx(s Sim, i int) f64 {
	return fixed_of(s.field('guards', i, 'x'))
}

pub fn gy(s Sim, i int) f64 {
	return fixed_of(s.field('guards', i, 'y'))
}

pub fn gstate(s Sim, i int) int {
	return s.element('guard_ai_state', i)
}

// gtile is the tile a guard is in (the tile of the middle of its box).
pub fn gtile(s Sim, i int) jaggame.Point {
	return jaggame.Point{int(gx(s, i) + 8) >> 4, int(gy(s, i) + 9) >> 4}
}

pub fn ptile(s Sim) jaggame.Point {
	return jaggame.Point{int(px_of(s) + 8) >> 4, int(py_of(s) + 9) >> 4}
}

// put_figure puts the figure in the middle of a tile.
pub fn put_figure(mut s Sim, tx int, ty int) {
	s.poke('px', tx * 16 * 65536)
	s.poke('py', (ty * 16 - 1) * 65536)
}

pub fn scene_of(s Sim) int {
	return s.element('scene_state', 0)
}

pub fn run_frames(mut s Sim, n int, mask u32) {
	for _ in 0 .. n {
		s.frame(mask)
	}
}

// force_play puts the game back in the mission with nobody caught, as the
// tests that push the figure about need: the scene's variables are poked, no
// scene code runs.
pub fn force_play(mut s Sim) {
	s.poke_element('scene_state', 0, scene_play)
	s.poke('scenes_steps', 6)
	s.poke('scenes_step', 6)
	s.poke('scenes_fading', 0)
	s.poke('rt_fade', 16)
	s.poke('phase', 0)
	s.poke('paused', 0)
}

// ---- finding things on the maps ----

pub fn (s &Spec) rows_of(room int) []string {
	return s.maps[room].trim('\n').split('\n')
}

// find is where a character is on a room's map, in tiles.
pub fn (s &Spec) find(room int, ch u8) []jaggame.Point {
	mut found := []jaggame.Point{}
	for y, row in s.rows_of(room) {
		for x, c in row {
			if c == ch {
				found << jaggame.Point{x, y}
			}
		}
	}
	return found
}

// is_blocking is whether a map character stops the figure.
pub fn is_blocking(ch u8) bool {
	return ch == `#` || ch == `c` || ch == `A` || ch == `B` || ch == `C`
}

// room_of_mission is the number of a room of a mission.
pub fn (s &Spec) room_of_mission(mission int, k int) int {
	return s.first[mission] + k
}

// ---- driving the menus ----

// settle plays frames with nothing held until no fade is going on and no
// room is loading and the scene's setup is done.
pub fn settle(mut s Sim) {
	mut n := 0
	for s.value('scenes_fading') != 0 || s.value('loading') != 0
		|| s.value('scenes_step') < s.value('scenes_steps') || n < 2 {
		s.frame(0)
		n++
		if n >= 400 {
			panic('the game never settled (scene ${scene_of(s)})')
		}
	}
}

// tap presses a button for a frame and lets go for three.
pub fn tap(mut s Sim, buttons ...jaggame.Button) {
	s.frame(pad(...buttons))
	run_frames(mut s, 3, 0)
}

// to_picker plays the title (A) to the mission select, if the game is on
// the title.
pub fn to_picker(mut s Sim) {
	run_frames(mut s, 3, 0)
	if scene_of(s) == scene_title {
		tap(mut s, .a)
		settle(mut s)
	}
	if scene_of(s) != scene_picker {
		panic('the mission select is up, not scene ${scene_of(s)}')
	}
}

// select_mission moves the cursor of the mission select to a mission, turning
// the page if need be, and chooses it: the briefing comes up.
pub fn select_mission(mut s Sim, mission int) {
	page := mission / 5
	slot := mission % 5
	if s.value('page') != page {
		for s.value('picker_cursor') != 5 {
			tap(mut s, .down)
		}
		tap(mut s, .a)
		run_frames(mut s, 3, 0)
		if s.value('page') != page {
			panic('the page did not turn')
		}
	}
	for s.value('picker_cursor') != slot {
		tap(mut s, .down)
	}
	// every mission is open, whatever the record (a record that was written
	// by an earlier mission of the test says fewer)
	if mission > 0 {
		s.poke('unlocked', 10)
	}
	tap(mut s, .a)
	settle(mut s)
	if scene_of(s) != scene_brief || s.value('mission') != mission {
		panic('the briefing of mission ${mission} is not up: scene ${scene_of(s)}, mission ${s.value('mission')}')
	}
}

// enter_mission plays the game from the title to the first frame of a
// mission, with the room loaded and everything on its start; three frames
// more, so that the guards are on their way.
pub fn enter_mission(mut s Sim, mission int) {
	// every mission is open (the first always is): the record's count of open
	// missions is set before the mission select reads it (a record that is not
	// there leaves it alone)
	if mission > 0 {
		s.poke('save_open', 10)
	}
	to_picker(mut s)
	select_mission(mut s, mission)
	tap(mut s, .a)
	ready(mut s)
}

// ready waits until a room of the mission is loaded, everything is on its
// start and the picture is back, then three more frames.
pub fn ready(mut s Sim) {
	settle(mut s)
	if scene_of(s) != scene_play {
		panic('the mission is up, not scene ${scene_of(s)}')
	}
	run_frames(mut s, 3, 0)
}

// save_picture writes what the emulator shows as a PNG.
pub fn (b &Booted) save_picture(path string) ! {
	pic := b.p.picture()
	mut canvas := jaggame.new_canvas(pic.width, pic.height)
	for y in 0 .. pic.height {
		for x in 0 .. pic.width {
			px := pic.at(x, y)
			canvas.put(x, y, int((px >> 16) & 0xff), int((px >> 8) & 0xff), int(px & 0xff), 255)
		}
	}
	canvas.save(path)!
}

// cost_frame plays a frame with a pad and returns the cycles the 68000 spent
// in its interrupt, counting what runs on past the emulator's frame boundary.
pub fn (mut b Booted) cost_frame(mask u32) int {
	hold_pad(mut b.p, mask)
	cycles := b.p.busy_cycles(1) + b.p.settle_cycles()
	b.pad_log << mask
	return cycles
}

// frame_cycles is the 68000 cycles in a television frame.
pub fn frame_cycles(pal bool) int {
	return if pal { 265_000 } else { 221_000 }
}

// layer_text reads `count` cells of a row of a text layer (`msg` is 24 cells
// wide, `status` 8, `hud` 16).
pub fn layer_text(s Sim, layer string, columns int, row int, from int, count int) string {
	mut out := []u8{}
	for k in 0 .. count {
		out << u8(s.element('${layer}_cells', row * columns + from + k) + 32)
	}
	return out.bytestr()
}

// screen_text reads cells of the `msg` layer: the menus, the briefing, the result.
pub fn screen_text(s Sim, row int, from int, count int) string {
	return layer_text(s, 'msg', 24, row, from, count)
}

// clock_text is seconds as the game writes them.
pub fn clock_text(secs int) string {
	return '${secs / 60}:${(secs % 60) / 10}${secs % 10}'
}
