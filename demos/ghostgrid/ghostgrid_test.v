module main

import os
import stbi
import tom
import jaggame
import jaggame.emulated
import jerry

// GHOSTGRID is tested by playing it: the image is booted in the emulator on
// both television standards and a robot plays it through the pad, reading
// where the figure and the guards are, their facings and their states, from
// the machine's memory by name. The same game logic then runs in the
// interpreter with the same pad and the two must agree.

const state_names = ['patrol', 'suspicious', 'alert', 'search', 'return']
const patrol = 0
const suspicious = 1
const alert = 2
const search = 3
const returning = 4

fn rows() []string {
	return depot.trim('\n').split('\n')
}

fn is_blocking(ch u8) bool {
	return ch == `#` || ch == `c`
}

// find is where a character is in the depot, in tiles.
fn find(ch u8) []jaggame.Point {
	mut found := []jaggame.Point{}
	for y, row in rows() {
		for x, c in row {
			if c == ch {
				found << jaggame.Point{x, y}
			}
		}
	}
	return found
}

// ---- what the tests can drive: the machine, or the interpreter ----

// Sim is a running game that a robot can play: one frame at a time with a
// pad, and the game's variables by name.
interface Sim {
	value(name string) int
	element(name string, index int) int
	field(array string, index int, field string) int
mut:
	frame(mask u32)
	poke(name string, raw int)
	poke_element(name string, index int, raw int)
	poke_field(array string, index int, field string, raw int)
}

fn fixed_of(raw int) f64 {
	return f64(raw) / 65536.0
}

fn px_of(s Sim) f64 {
	return fixed_of(s.value('px'))
}

// the buttons the robot can press, and the pad bits of the interpreter.
const robot_buttons = [jerry.Button.up, .down, .left, .right, .a, .b, .c, .pause]
const robot_masks = [jaggame.Button.up, .down, .left, .right, .a, .b, .c, .pause]

fn pad(buttons ...jaggame.Button) u32 {
	mut mask := u32(0)
	for b in buttons {
		mask |= jaggame.button_mask(b)
	}
	return mask
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
struct Booted {
	img jaggame.Image
mut:
	p       emulated.Player
	pad_log []u32 // the pad of every frame played so far, for the interpreter
	pal     bool
	// where the logical screen's top left corner is in the emulator's picture
	ox int
	oy int
}

fn boot(pal bool) &Booted {
	img := build() or { panic(err) }
	return &Booted{
		img: img
		p:   emulated.boot(img.bytes, pal) or { panic(err) }
		pal: pal
	}
}

fn (mut b Booted) frame(mask u32) {
	hold_pad(mut b.p, mask)
	b.p.frames(1)
	b.pad_log << mask
}

fn (b &Booted) value(name string) int {
	return int(b.img.value(b.p.m.ram, name) or { panic(err) })
}

fn (b &Booted) element(name string, index int) int {
	return int(b.img.element(b.p.m.ram, name, index) or { panic(err) })
}

fn (b &Booted) field(array string, index int, field string) int {
	return int(b.img.field(b.p.m.ram, array, index, field) or { panic(err) })
}

fn (mut b Booted) poke(name string, raw int) {
	b.poke_element(name, 0, raw)
}

fn (mut b Booted) poke_element(name string, index int, raw int) {
	at, size := b.img.address_of_element(name, index) or { panic(err) }
	b.write(at, size, raw)
}

fn (mut b Booted) poke_field(array string, index int, field string, raw int) {
	at := b.img.field_address(array, index, field) or { panic(err) }
	b.write(at, b.img.field_size(array, field) or { panic(err) }, raw)
}

fn (mut b Booted) write(at u32, size int, raw int) {
	for k in 0 .. size {
		b.p.m.ram[at + u32(k)] = u8(raw >> u32(8 * (size - 1 - k)))
	}
}

// Rig is the game in the interpreter.
struct Rig {
mut:
	g       &jaggame.Game
	it      &jaggame.Interpreter
	pad_log []u32
}

fn new_rig(pal bool) &Rig {
	mut g := describe()
	it := g.interpreter(if pal { jaggame.Region.pal } else { jaggame.Region.ntsc }) or {
		panic(err)
	}
	return &Rig{
		g:  g
		it: it
	}
}

fn (mut r Rig) frame(mask u32) {
	r.pad_log << mask
	r.g.step(mut r.it, mask) or { panic(err) }
}

fn (r &Rig) value(name string) int {
	return int(r.it.value(name) or { panic(err) })
}

fn (r &Rig) element(name string, index int) int {
	return int(r.it.element(name, index) or { panic(err) })
}

fn (r &Rig) field(array string, index int, field string) int {
	return int(r.it.field(array, index, field) or { panic(err) })
}

fn (mut r Rig) poke(name string, raw int) {
	r.it.set_value(name, raw) or { panic(err) }
}

fn (mut r Rig) poke_element(name string, index int, raw int) {
	r.it.set_element(name, index, raw) or { panic(err) }
}

fn (mut r Rig) poke_field(array string, index int, field string, raw int) {
	r.it.set_field(array, index, field, raw) or { panic(err) }
}

// ---- reading the game ----

fn gx(s Sim, i int) f64 {
	return fixed_of(s.field('guards', i, 'x'))
}

fn gy(s Sim, i int) f64 {
	return fixed_of(s.field('guards', i, 'y'))
}

fn gstate(s Sim, i int) int {
	return s.element('guard_ai_state', i)
}

// gtile is the tile a guard is in (the tile of the middle of its box).
fn gtile(s Sim, i int) jaggame.Point {
	return jaggame.Point{int(gx(s, i) + 8) >> 4, int(gy(s, i) + 9) >> 4}
}

fn ptile(s Sim) jaggame.Point {
	return jaggame.Point{int(px_of(s) + 8) >> 4, int(fixed_of(s.value('py')) + 9) >> 4}
}

// put_figure puts the figure in the middle of a tile.
fn put_figure(mut s Sim, tx int, ty int) {
	s.poke('px', tx * 16 * 65536)
	s.poke('py', (ty * 16 - 1) * 65536)
}

fn lit_by(s Sim, tile jaggame.Point) int {
	return s.element('lit', tile.y * room_cols + tile.x)
}

// loaded plays frames until the room is loaded and the guards are on their routes.
fn wait_loaded(mut s Sim) {
	mut n := 0
	for s.value('loading') != 0 || n < 4 || s.value('setup_due') != 0 {
		s.frame(0)
		n++
		assert n < 200, 'a room never finished loading'
	}
	for _ in 0 .. 3 {
		s.frame(0)
	}
}

fn run_frames(mut s Sim, n int, mask u32) {
	for _ in 0 .. n {
		s.frame(mask)
	}
}

// ---- the plain tests ----

fn test_the_game_builds_and_the_art_is_imported() {
	img := build()!
	assert img.bytes.len > 10000 && img.bytes.len < 0x70000
	assert img.symbols['rt.start'] == jaggame.load_address
	assert room_cells == room_cols * room_rows
	r := rows()
	assert r.len == room_rows && r.all(it.len == room_cols)
}

fn test_the_depot_has_what_the_guide_says() {
	assert find(`@`).len == 1 && find(`X`).len == 1
	assert find(`1`).len == 1 && find(`2`).len == 1 && find(`5`).len == 1 && find(`9`).len == 1
	// every waypoint can be reached from the start, and so can the exit
	start := find(`@`)[0]
	mut reach := map[int]bool{}
	mut queue := [start]
	reach[start.y * room_cols + start.x] = true
	mut head := 0
	for head < queue.len {
		here := queue[head]
		head++
		for step in [jaggame.Point{1, 0}, jaggame.Point{-1, 0},
			jaggame.Point{0, 1}, jaggame.Point{0, -1}] {
			next := jaggame.Point{here.x + step.x, here.y + step.y}
			if next.x < 0 || next.y < 0 || next.x >= room_cols || next.y >= room_rows {
				continue
			}
			if is_blocking(rows()[next.y][next.x]) || reach[next.y * room_cols + next.x] {
				continue
			}
			reach[next.y * room_cols + next.x] = true
			queue << next
		}
	}
	for ch in `1` .. `:` {
		for p in find(u8(ch)) {
			assert reach[p.y * room_cols + p.x], 'waypoint ${rune(ch)} is not reachable'
		}
	}
	x := find(`X`)[0]
	assert reach[x.y * room_cols + x.x]
}

fn test_the_room_loads_and_everything_stands_on_its_start() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		assert b.value('missed_frames') == 0
		assert b.value('room_width') == room_cols * 16 && b.value('room_height') == room_rows * 16
		start := find(`@`)[0]
		assert fixed_of(b.value('px')) == start.x * 16 && fixed_of(b.value('py')) == start.y * 16
		// the guards are on their first waypoints, live, in patrol
		firsts := [find(`1`)[0], find(`3`)[0], find(`5`)[0], find(`6`)[0]]
		for i in 0 .. 4 {
			assert b.field('guards', i, 'live') == 1
			assert gstate(b, i) == patrol
			t := gtile(b, i)
			assert int_abs(t.x - firsts[i].x) + int_abs(t.y - firsts[i].y) < 6, 'guard ${i} is at ${t} near ${firsts[i]}'
		}
		cx := int(i16(b.value('camera_x')))
		cy := int(i16(b.value('camera_y')))
		assert cx == 0
			&& cy == int_min(room_rows * 16 - 240, int_max(0, int(fixed_of(b.value('py'))) + 9 - 120)), 'the camera is on the figure: ${cx}, ${cy}'
	}
}

fn int_abs(a int) int {
	return if a < 0 { -a } else { a }
}

// ---- the guards at work ----

// seen_states plays frames and returns the guard's states in order, each
// once (a run of the same state counts once).
fn watch_states(mut s Sim, guard int, frames int, mask u32) []int {
	mut seen := []int{}
	for _ in 0 .. frames {
		s.frame(mask)
		st := gstate(s, guard)
		if seen.len == 0 || seen.last() != st {
			seen << st
		}
	}
	return seen
}

fn test_a_figure_that_stands_in_a_guards_path_is_seen_chased_and_caught() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		// guard 1 walks south along a column of the west hall; stand in front of him
		put_figure(mut s, 8, 17)
		mut states := [gstate(s, 1)]
		mut n := 0
		for b.value('phase') == 0 && n < 900 {
			s.frame(0)
			n++
			st := gstate(s, 1)
			if states.len == 0 || states.last() != st {
				states << st
			}
		}
		assert b.value('phase') == 2, 'the figure was caught (after ${n} frames; the guard went through ${states})'
		assert states.len >= 3, 'the guard went through ${states}; others ${gstate(s, 0)} ${gstate(s,
			2)} ${gstate(s, 3)}'

		assert states[..3] == [patrol, suspicious, alert], 'patrol, then suspicious, then alert: ${states}'
		assert b.value('seen') >= 1
		assert b.value('level') == 2 || b.value('shown') == 3
		assert n < 400, 'caught in ${n} frames'
		// the end screen is up and the guards have stopped
		run_frames(mut s, 5, 0)
		gx1 := b.field('guards', 1, 'x')
		run_frames(mut s, 30, 0)
		assert b.field('guards', 1, 'x') == gx1, 'the guards stop when the mission is over'
		assert b.value('missed_frames') == 0
		// and it can be played again: A restarts, the room loads again and everything is back
		s.frame(pad(.a))
		wait_loaded(mut s)
		assert b.value('phase') == 0 && b.value('seen') == 0
		start := find(`@`)[0]
		assert fixed_of(b.value('px')) == start.x * 16
		for i in 0 .. 4 {
			assert gstate(b, i) == patrol
		}
		run_frames(mut s, 200, 0)
		assert b.value('phase') == 0, 'the new mission is not over at once'
		assert b.value('missed_frames') == 0
	}
}

fn test_a_running_figure_is_heard_where_a_walking_one_is_not() {
	for pal in [false, true] {
		// the sentinel stands at his post, looking north; four tiles behind him,
		// out of his cone, a figure walks to and fro
		for running in [false, true] {
			mut b := boot(pal)
			mut s := Sim(b)
			wait_loaded(mut s)
			post := find(`5`)[0]
			put_figure(mut s, post.x, post.y + 4)
			mut woke := -1
			for n in 0 .. 360 {
				dir := if (n / 24) % 2 == 0 { pad(.right) } else { pad(.left) }
				s.frame(dir | if running { pad(.a) } else { u32(0) })
				if woke < 0 {
					assert lit_by(s, ptile(s)) & 4 == 0, 'the figure is outside the cone: it is heard, not seen'
				}
				if gstate(s, 2) != patrol && woke < 0 {
					woke = n
				}
			}
			if running {
				assert woke >= 0 && woke < 60, 'the running figure is heard (after ${woke} frames)'
				assert b.value('seen') == 0, 'heard, not seen'
			} else {
				assert woke < 0, 'a walking figure is not heard'
				assert gstate(s, 2) == patrol
			}
			assert b.value('missed_frames') == 0
		}
	}
}

fn test_a_knock_draws_the_nearest_guard_and_he_goes_back_to_his_route() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		// below the crates at (30,16) and (31,16); the sentinel is 7 tiles away, the others further
		put_figure(mut s, knock_place.x, knock_place.y)
		run_frames(mut s, 3, pad(.up)) // face the crate
		s.frame(pad(.up, .c))
		spot_x := b.field('guards', 2, 'spot_x')
		assert gstate(s, 2) == suspicious || gstate(s, 2) == patrol
		run_frames(mut s, 2, 0)
		assert gstate(s, 2) == suspicious, 'the sentinel comes to look: ${state_names[gstate(s, 2)]}'
		for i in [0, 1, 3] {
			assert gstate(s, i) == patrol, 'guard ${i} is too far to hear it'
		}
		assert b.field('guards', 2, 'spot_x') == knock_place.x * 16 + 8, 'he comes to where the knock was: ${spot_x}'
		// the figure leaves; the sentinel walks to the spot, looks round and goes back
		put_figure(mut s, 3, 23)
		mut closest := 1000.0
		mut states := []int{}
		for _ in 0 .. 900 {
			s.frame(0)
			d := (gx(s, 2) - 31 * 16) * (gx(s, 2) - 31 * 16) + (gy(s, 2) - 17 * 16) * (gy(s, 2) -
				17 * 16)
			closest = if d < closest { d } else { closest }
			st := gstate(s, 2)
			if states.len == 0 || states.last() != st {
				states << st
			}
		}
		assert closest < 40 * 40, 'he got to within a tile or two of the spot (${closest})'
		assert states == [suspicious, returning, patrol] || states == [suspicious, patrol], 'suspicious, return, patrol: ${states}'
		post := find(`5`)[0]
		t := gtile(s, 2)
		assert t.x == post.x && t.y == post.y, 'back at his post: ${t}'
		assert b.value('phase') == 0 && b.value('seen') == 0
		assert b.value('missed_frames') == 0
	}
}

fn test_a_crouched_figure_behind_cover_is_not_seen_where_a_standing_one_is() {
	for pal in [false, true] {
		for crouched in [false, true] {
			mut b := boot(pal)
			mut s := Sim(b)
			wait_loaded(mut s)
			// the doorway, with the crate between it and the sentinel who looks north
			put_figure(mut s, 34, 8)
			mut first_seen := -1
			for n in 0 .. 200 {
				s.frame(if crouched { pad(.b) } else { u32(0) })
				if b.value('seen') > 0 && first_seen < 0 {
					first_seen = n
				}
			}
			if crouched {
				assert first_seen < 0, 'a crouched figure behind a cover block is not seen'
				assert gstate(s, 2) == patrol
				// it is in a lit tile, though: the cone does reach it
				assert lit_by(s, ptile(s)) & 4 != 0, 'the tile is lit'
			} else {
				assert first_seen >= 0 && first_seen < 30, 'a standing figure there is seen (${first_seen})'
				assert gstate(s, 2) != patrol
			}
			assert b.value('missed_frames') == 0
		}
	}
}

// inside_wall tells whether a box overlaps a wall or cover block: the box is
// 10 by 10, 3 and 4 from the corner of the picture.
fn inside_wall(px f64, py f64) bool {
	map_rows := rows()
	left := int(px) + 3
	top := int(py) + 4
	for y in [top, top + 9] {
		for x in [left, left + 9] {
			if x < 0 || y < 0 || y / 16 >= map_rows.len || x / 16 >= map_rows[0].len {
				return true
			}
			if is_blocking(map_rows[y / 16][x / 16]) {
				return true
			}
		}
	}
	return false
}

fn test_guards_never_walk_through_a_wall_and_never_stay_stuck() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		// the figure waits in the corner where nobody looks
		mut last_wp := [0, 0, 0, 0]
		mut changes := [0, 0, 0, 0]
		mut last_moved := [0, 0, 0, 0]
		mut last_pos := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
		frames := if pal { 2500 } else { 4000 }
		for n in 0 .. frames {
			s.frame(0)
			for i in 0 .. 4 {
				assert !inside_wall(gx(s, i), gy(s, i)), 'guard ${i} is in a wall at ${gx(s, i)}, ${gy(s,
					i)} after ${n} frames'

				wp := b.field('guards', i, 'wp')
				if wp != last_wp[i] {
					changes[i]++
					last_wp[i] = wp
				}
				if gx(s, i) != last_pos[i][0] || gy(s, i) != last_pos[i][1] {
					last_moved[i] = n
					last_pos[i] = [gx(s, i), gy(s, i)]
				}
				if i != 2 {
					assert n - last_moved[i] < 120, 'guard ${i} has not moved for ${n - last_moved[i]} frames at ${gx(s,
						i)}, ${gy(s, i)}'
				}
			}
			assert b.value('phase') == 0, 'nobody sees the figure in the corner (frame ${n})'
		}
		// the first guard goes to and fro (a leg is about 200 frames), the loop guard goes round
		assert changes[0] > frames / 400 && changes[1] > frames / 400 && changes[3] > frames / 600, 'every guard that has a route makes progress along it: ${changes}'
		assert b.value('missed_frames') == 0
	}
}

fn test_a_figure_pushed_about_at_random_never_enters_a_wall() {
	mut b := boot(false)
	mut s := Sim(b)
	wait_loaded(mut s)
	mut seed := u32(12345)
	mut mask := u32(0)
	for n in 0 .. 3000 {
		if n % 12 == 0 {
			seed = seed * 1664525 + 1013904223
			mask = (seed >> 16) & 0xf // a direction: up, down, left, right
			if (seed >> 20) & 1 == 1 {
				mask |= pad(.a)
			}
		}
		s.frame(mask)
		assert !inside_wall(fixed_of(b.value('px')), fixed_of(b.value('py'))), 'in a wall after ${n} frames'
		if b.value('phase') != 0 {
			s.poke('phase', 0) // caught or through: it does not matter here
		}
	}
	assert b.value('missed_frames') == 0
}

// ---- the robot ----
//
// The robot plays the mission unseen. It does not look ahead by guessing: the
// guards walk the same way whatever the figure does as long as they do not
// notice it, so the game is first run in the interpreter with the figure
// parked in a wall, and the cones of every frame are written down (the game's
// own `lit` bytes and where each guard is). Then a search over (tile, time)
// finds the walk that is never in a lit tile, waiting where it has to, and
// crouching where a cover block hides it. The knock changes what the guards
// do, so the search is made twice: to the knocking place, and after the knock,
// from there to the exit, with the game run again from the knock on.

const room_zero = jaggame.Room{
	index: 0
	name:  'depot'
}
const tick = 4 // frames in a step of the plan
const horizon = 1000 // ticks the plan may take

// Recording is what the guards did, frame by frame from `t0`.
struct Recording {
mut:
	t0     int
	frames int
	lit    []u8  // room_cells bytes after each frame
	guards []int // after each frame, for each guard: tile x, tile y, facing (0..3)
}

// record plays `frames` frames with nobody touching the pad and writes down
// the cones and the guards after each.
fn record(mut rig Rig, frames int) Recording {
	mut rec := Recording{
		t0:     rig.value('frame')
		frames: frames + 1
	}
	rec.snapshot(mut rig)
	for _ in 0 .. frames {
		rig.frame(0)
		rec.snapshot(mut rig)
	}
	return rec
}

fn (mut rec Recording) snapshot(mut rig Rig) {
	for v in rig.it.array('lit') or { panic(err) } {
		rec.lit << u8(v)
	}
	s := Sim(rig)
	for i in 0 .. 4 {
		t := gtile(s, i)
		rec.guards << t.x
		rec.guards << t.y
		rec.guards << s.field('guards', i, 'face') >> 6
	}
}

// Danger says, for every tick of a plan and every tile, whether standing there
// would be seen and whether crouching there would be.
struct Danger {
mut:
	standing  []bool
	crouching []bool
}

fn view_grid(mut game jaggame.Game, mut cache map[int][]bool, x int, y int, f int) []bool {
	key := (y * room_cols + x) * 4 + f
	if key in cache {
		return cache[key]
	}
	mut grid := []bool{len: room_cells}
	for p in game.view_cells(room_zero, x, y, f * 64, sight_range, sight_half, true) {
		grid[p.y * room_cols + p.x] = true
	}
	cache[key] = grid
	return grid
}

// danger works out what each tick of the plan has to avoid. A tick covers
// the frames around it, a little before and after, so that a plan that is a
// frame or two out is still safe.
fn danger(rec &Recording, mut game jaggame.Game) Danger {
	ticks := (rec.frames - 10) / tick
	mut d := Danger{
		standing:  []bool{len: ticks * room_cells}
		crouching: []bool{len: ticks * room_cells}
	}
	mut cache := map[int][]bool{}
	for f in 0 .. rec.frames {
		// which tiles are lit now, and which of them a crouching figure is seen on
		mut stand := []bool{len: room_cells}
		mut crouch := []bool{len: room_cells}
		for cell in 0 .. room_cells {
			bits := rec.lit[f * room_cells + cell]
			if bits & 0x0f == 0 {
				continue
			}
			stand[cell] = true
			for g in 0 .. 4 {
				if bits & (1 << u8(g)) != 0 {
					base := f * 12 + g * 3
					grid := view_grid(mut game, mut cache, rec.guards[base], rec.guards[base + 1], rec.guards[
						base + 2])
					if grid[cell] {
						crouch[cell] = true
					}
				}
			}
		}
		// frame f belongs to the ticks whose window it is in
		first := (f - 6 + tick - 1) / tick
		last := (f + 2) / tick
		for k in int_max(0, first) .. int_min(ticks, last + 1) {
			for cell in 0 .. room_cells {
				if stand[cell] {
					d.standing[k * room_cells + cell] = true
				}
				if crouch[cell] {
					d.crouching[k * room_cells + cell] = true
				}
			}
		}
	}
	return d
}

// Action is one step of a plan: what the figure does for `ticks` ticks.
struct Action {
	kind  int // 0 wait, 1 wait crouching, 2 walk, 3 crouch-walk, 4 knock
	cell  int // the tile it ends in
	ticks int
}

const wait = 0
const hide = 1
const walk = 2
const creep = 3
const knock = 4

fn (a Action) name() string {
	return ['wait', 'hide', 'walk', 'creep', 'knock'][a.kind]
}

// Options say what the plan may use.
struct Options {
	hide  bool = true // wait crouching, behind cover
	creep bool = true // walk crouching
}

// make_plan finds the fastest way, by breadth first search over (tick, tile), from
// a tile at a tick to a goal tile, never in a tile a guard would see. With
// `knock_at` the goal is to be able to knock (three ticks standing still).
fn make_plan(d &Danger, ticks int, from int, from_tick int, goal int, knock_at bool, opts Options) ?[]Action {
	map_rows := rows()
	mut passable_cell := []bool{len: room_cells}
	for y in 0 .. room_rows {
		for x in 0 .. room_cols {
			passable_cell[y * room_cols + x] = !is_blocking(map_rows[y][x])
		}
	}
	size := (ticks + 8) * room_cells
	mut parent := []int{len: size, init: -1}
	mut how := []u8{len: size}
	mut seen := []bool{len: size}
	mut buckets := [][]int{len: ticks + 8}
	start := from_tick * room_cells + from
	seen[start] = true
	buckets[from_tick] << start
	safe := fn [d, ticks] (k int, cell int, crouching bool) bool {
		if k >= ticks {
			return false
		}
		return !(if crouching {
			d.crouching[k * room_cells + cell]
		} else {
			d.standing[k * room_cells + cell]
		})
	}
	for k in from_tick .. ticks {
		for state in buckets[k] {
			cell := state % room_cells
			if cell == goal && (!knock_at || (safe(k + 1, cell, false) && safe(k + 2, cell, false)
				&& safe(k + 3, cell, false))) {
				// walk back to find the way
				mut path := []Action{}
				if knock_at {
					path << Action{knock, cell, 3}
				}
				mut at := state
				for parent[at] >= 0 {
					path << Action{int(how[at]), at % room_cells, at / room_cells - parent[at] / room_cells}
					at = parent[at]
				}
				path.reverse_in_place()
				return path
			}
			mut moves := [[0, cell, 1, wait]]
			if opts.hide {
				moves << [1, cell, 1, hide]
			}
			for step in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
				x := cell % room_cols + step[0]
				y := cell / room_cols + step[1]
				if x < 0 || y < 0 || x >= room_cols || y >= room_rows
					|| !passable_cell[y * room_cols + x] {
					continue
				}
				n := y * room_cols + x
				if safe(k + 1, n, false) && safe(k + 2, n, false) && safe(k + 3, n, false)
					&& safe(k + 1, cell, false) && safe(k + 2, cell, false)
					&& safe(k + 3, cell, false) {
					moves << [2, n, 3, walk]
				}
				if opts.creep {
					mut ok := true
					for j in 1 .. 7 {
						ok = ok && safe(k + j, n, true) && safe(k + j, cell, true)
					}
					if ok {
						moves << [2, n, 6, creep]
					}
				}
			}
			for mv in moves {
				n := mv[1]
				nk := k + (if mv[0] == 0 || mv[0] == 1 { 1 } else { mv[2] })
				if mv[0] == 0 && !safe(nk, n, false) {
					continue
				}
				if mv[0] == 1 && !safe(nk, n, true) {
					continue
				}
				target := nk * room_cells + n
				if seen[target] {
					continue
				}
				seen[target] = true
				parent[target] = state
				how[target] = u8(mv[3])
				buckets[nk] << target
			}
		}
	}
	return none
}

// steer is the pad that takes the figure towards the middle of a tile: the
// figure's position is its top left corner, (16 tx, 16 ty - 1) when its box
// is in the middle of the tile.
fn steer(s Sim, cell int, tolerance f64) u32 {
	want_x := f64((cell % room_cols) * 16)
	want_y := f64((cell / room_cols) * 16 - 1)
	px := fixed_of(s.value('px'))
	py := fixed_of(s.value('py'))
	mut mask := u32(0)
	if want_x - px > tolerance {
		mask |= pad(.right)
	} else if px - want_x > tolerance {
		mask |= pad(.left)
	}
	if want_y - py > tolerance {
		mask |= pad(.down)
	} else if py - want_y > tolerance {
		mask |= pad(.up)
	}
	return mask
}

// execute plays a plan frame by frame.
fn execute(mut s Sim, actions []Action, each fn (mut s Sim)) {
	for a in actions {
		for f in 0 .. a.ticks * tick {
			mut mask := u32(0)
			match a.kind {
				hide {
					mask = pad(.b)
				}
				walk {
					mask = steer(s, a.cell, 1.6)
				}
				creep {
					mask = steer(s, a.cell, 0.8) | pad(.b)
				}
				knock {
					if f < 3 {
						mask = pad(.up)
					} else if f == 3 {
						mask = pad(.up, .c)
					}
				}
				else {}
			}

			s.frame(mask)
			each(mut s)
		}
	}
}

fn nothing(mut s Sim) {
}

fn cell_of(p jaggame.Point) int {
	return p.y * room_cols + p.x
}

// Plans is what the robot works out: how to get to the place where it knocks, and from there to the exit.
struct Plans {
	to_knock []Action
	to_exit  []Action
	pad_log  []u32 // every frame's pad from the boot to the exit
	direct   bool  // there is a way to the exit that does not need the knock
}

const knock_place = jaggame.Point{32, 17}

// parked_rig is a game whose room has loaded and whose figure has been put
// out of the way, in a wall, so that nobody can see it.
fn parked_rig() &Rig {
	mut rig := new_rig(false)
	mut s := Sim(rig)
	wait_loaded(mut s)
	return rig
}

fn make_plans(opts Options) ?Plans {
	// 1. the guards with the figure out of the way
	mut rig := parked_rig()
	mut s := Sim(rig)
	s.poke('px', 0)
	s.poke('py', 0)
	rec0 := record(mut rig, 3600)
	d0 := danger(&rec0, mut rig.g)
	ticks := (rec0.frames - 10) / tick
	start := cell_of(find(`@`)[0])
	exit_cell := cell_of(find(`X`)[0])
	direct := make_plan(&d0, ticks, start, 0, exit_cell, false, opts) != none

	// 2. to the knocking place
	to_knock := make_plan(&d0, ticks, start, 0, cell_of(knock_place), true, opts)?

	// 3. play it, and go on with the figure out of the way to see what the knock did
	mut run := parked_rig()
	mut rs := Sim(run)
	execute(mut rs, to_knock, nothing)
	run.frame(0)
	rs.poke('px', 0)
	rs.poke('py', 0)
	rec1 := record(mut run, 3000)
	d1 := danger(&rec1, mut run.g)
	to_exit :=
		make_plan(&d1, (rec1.frames - 10) / tick, cell_of(knock_place), 0, exit_cell, false, opts)?

	// 4. play both, with the figure in the game all the way, to have the pad
	mut final := parked_rig()
	mut fs := Sim(final)
	execute(mut fs, to_knock, nothing)
	final.frame(0)
	execute(mut fs, to_exit, nothing)
	return Plans{
		to_knock: to_knock
		to_exit:  to_exit
		pad_log:  final.pad_log
		direct:   direct
	}
}

fn describe_plan(actions []Action) string {
	mut parts := []string{}
	for a in actions {
		parts << '${a.name()} ${a.cell % room_cols},${a.cell / room_cols} x${a.ticks}'
	}
	return parts.join(', ')
}

// kinds counts the actions of each kind in a plan.
fn kinds(actions []Action) map[string]int {
	mut count := map[string]int{}
	for a in actions {
		count[a.name()] += a.ticks
	}
	return count
}

fn test_the_mission_needs_waiting_cover_and_one_knock() {
	plans := make_plans(Options{}) or {
		assert false, 'the robot finds no way to the exit that is never seen'
		return
	}
	assert !plans.direct, 'the exit cannot be reached unseen without the knock'
	to_knock := kinds(plans.to_knock)
	to_exit := kinds(plans.to_exit)
	assert to_knock['wait'] > 0, 'the way to the knock includes waiting for a guard to go by'
	assert to_knock['hide'] > 0, 'and hiding behind a cover block while he does'
	assert to_knock['knock'] == 3 && to_exit['knock'] == 0, 'one knock'
	println('robot: ${plans.to_knock.len} steps to the knock (${to_knock}), ${plans.to_exit.len} from it to the exit (${to_exit}), ${plans.pad_log.len} frames in all')
	// Without crouching behind cover there is no way at all.
	if _ := make_plans(Options{ hide: false, creep: false }) {
		assert false, 'the mission can be done without the cover'
	}
}

// the robot's run is checked frame by frame on the machine

fn test_a_robot_completes_the_mission_without_being_seen() {
	plans := make_plans(Options{}) or {
		assert false, 'no plan'
		return
	}
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		mut it := new_rig(pal)
		mut knocked := false
		mut woke := false
		for n, mask in plans.pad_log {
			s.frame(mask)
			it.frame(mask)
			assert b.value('seen') == 0, 'a guard saw the figure (frame ${n})'
			for i in 0 .. 4 {
				st := gstate(s, i)
				if i == 2 {
					assert st in [patrol, suspicious, returning], 'the sentinel is ${state_names[st]} (frame ${n})'
					if st == suspicious {
						woke = true
					}
				} else {
					assert st == patrol, 'guard ${i} is ${state_names[st]} (frame ${n})'
				}
			}
			if b.value('flash') > 0 {
				knocked = true
			}
			// the interpreter does the same
			for name in ['px', 'py', 'phase', 'seen', 'camera_x', 'camera_y', 'crouched'] {
				assert b.value(name) == it.value(name), 'frame ${n}: ${name}: machine ${b.value(name)}, interpreter ${it.value(name)}'
			}
			for i in 0 .. 4 {
				for field in ['x', 'y', 'face', 'wp', 'mleft'] {
					assert b.field('guards', i, field) == it.field('guards', i, field), 'frame ${n}: guard ${i} ${field}: machine ${b.field('guards',
						i, field)}, interpreter ${it.field('guards', i, field)}'
				}
			}
			if b.value('phase') != 0 {
				break
			}
		}
		assert b.value('phase') == 1, 'the mission is done'
		assert knocked && woke, 'the knock drew the sentinel'
		assert b.value('seen') == 0 && b.value('missed_frames') == 0
		assert b.field('guards', 2, 'live') == 1
		for _ in 0 .. 3 {
			s.frame(0)
			it.frame(0)
		}
		// the end screen shows the time and the times seen
		assert b.value('shown') == 3
		secs := b.value('secs')
		assert secs > 5 && secs < 120, 'it took ${secs} seconds'
		println('robot on ${if pal { 'PAL' } else { 'NTSC' }}: through in ${secs} seconds, seen ${b.value('seen')} times')
		// and every variable of the program is the same on both
		mut differences := b.img.differences(it.it, b.p.m.ram)
		differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale'))
		assert differences.len == 0, differences.join('\n')
	}
}

// ---- the interpreter, with the guards chasing ----

fn test_the_interpreter_does_what_the_machine_did_while_guards_chase_and_search() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		mut it := new_rig(pal)
		mut seed := u32(99)
		mut mask := u32(0)
		mut visited := map[int]bool{}
		for n in 0 .. 1800 {
			if n % 20 == 0 {
				seed = seed * 1664525 + 1013904223
				mask = (seed >> 16) & 0xf
				if (seed >> 20) & 3 == 0 {
					mask |= pad(.a)
				}
				if (seed >> 22) & 7 == 0 {
					mask |= pad(.b)
				}
				if (seed >> 25) & 7 == 0 {
					mask |= pad(.c)
				}
			}
			if n % 250 == 5 {
				// put the figure in front of a guard (the same on both)
				seed = seed * 1664525 + 1013904223
				g := int((seed >> 16) % 4)
				t := gtile(s, g)
				for ps in [Sim(b), Sim(it)] {
					mut one := ps
					put_figure(mut one, int_max(1, int_min(38, t.x + 2)), t.y)
				}
			}
			if n % 250 == 90 {
				// and away again, so that whoever chased has lost it
				for ps in [Sim(b), Sim(it)] {
					mut one := ps
					put_figure(mut one, 2, 23)
				}
			}
			if b.value('phase') != 0 {
				mask = pad(.a) // play again
			}
			s.frame(mask)
			it.frame(mask)
			for name in ['px', 'py', 'phase', 'seen', 'level', 'secs', 'camera_x', 'camera_y'] {
				assert b.value(name) == it.value(name), 'frame ${n}: ${name}: machine ${b.value(name)}, interpreter ${it.value(name)}'
			}
			for i in 0 .. 4 {
				assert gstate(b, i) == gstate(it, i), 'frame ${n}: guard ${i}: machine ${state_names[gstate(b,
					i)]}, interpreter ${state_names[gstate(it, i)]}'
				visited[gstate(b, i)] = true
				for field in ['x', 'y', 'face', 'wp', 'mleft', 'look', 'stuck', 'cone_n'] {
					assert b.field('guards', i, field) == it.field('guards', i, field), 'frame ${n}: guard ${i} ${field}: machine ${b.field('guards',
						i, field)}, interpreter ${it.field('guards', i, field)}'
				}
			}
		}
		assert visited.len == 5, 'every state was visited: ${visited.keys()}'
		mut differences := b.img.differences(it.it, b.p.m.ram)
		differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale'))
		assert differences.len <= 12, differences.join('\n')
		assert b.value('missed_frames') == 0
	}
}

// ---- the picture ----

// tile_colours are the colours of the tile set as the machine shows them:
// 16 by 16 pixels for each tile, 0x00RRGGBB.
fn tile_colours() [][]u32 {
	path := os.join_path(art_dir(), 'tiles.png')
	img := stbi.load(path) or { panic(err) }
	mut tiles := [][]u32{}
	for t in 0 .. img.width / 16 {
		mut pixels := []u32{}
		for y in 0 .. 16 {
			for x in 0 .. 16 {
				i := (y * img.width + t * 16 + x) * 4
				r, g, bl := int(unsafe { img.data[i] }), int(unsafe { img.data[i + 1] }), int(unsafe {
					img.data[i + 2]
				})
				pixels << tom.cry_to_rgb(u32(jaggame.cry(r, g, bl)))
			}
		}
		tiles << pixels
	}
	return tiles
}

// covered tells whether a pixel of the logical screen belongs to something
// that is not the room: a sprite or the text.
fn (b &Booted) covered(cx int, cy int, sx int, sy int) bool {
	if (sx < 150 && sy < 36) || (sx >= 236 && sy < 20)
		|| (sx >= 60 && sx < 260 && sy >= 66 && sy < 130 && b.value('phase') != 0) {
		return true // the text
	}
	for i in 0 .. 9 {
		if b.field('sprites', i, 'visible') == 0 {
			continue
		}
		x := int(i16(b.field('sprites', i, 'x'))) - cx
		y := int(i16(b.field('sprites', i, 'y'))) - cy
		if sx >= x - 1 && sx < x + 17 && sy >= y - 1 && sy < y + 17 {
			return true
		}
	}
	return false
}

// matches counts how many pixels of the room part of the logical screen are
// what they should be, and how many there are, with the screen at (ox, oy)
// in the emulator's picture. The room is what is in the map now: the lit tiles
// are tiles of their own.
fn (b &Booted) matches(tiles [][]u32, ox int, oy int, step int) (int, int) {
	cx := int(i16(b.value('camera_x')))
	cy := int(i16(b.value('camera_y')))
	pic := b.p.picture()
	w := b.value('rt_room_w')
	h := b.value('rt_room_h')
	background := tom.cry_to_rgb(u32(jaggame.cry(6, 8, 20)))
	mut good := 0
	mut all := 0
	for sy := 0; sy < 240; sy += step {
		for sx := 0; sx < 320; sx += step {
			if sx + ox < 0 || sy + oy < 0 || sx + ox >= pic.width || sy + oy >= pic.height {
				continue
			}
			if b.covered(cx, cy, sx, sy) {
				continue
			}
			all++
			wx := sx + cx
			wy := sy + cy
			want := if wx < 0 || wy < 0 || wx >= w * 16 || wy >= h * 16 {
				background
			} else {
				tile := b.element('rt_map', (wy / 16) * w + wx / 16)
				tiles[tile][(wy % 16) * 16 + wx % 16]
			}
			if pic.at(sx + ox, sy + oy) == want {
				good++
			}
		}
	}
	return good, all
}

fn (mut b Booted) find_origin(tiles [][]u32) {
	mut best := 0
	for oy in -8 .. 9 {
		for ox in -8 .. 9 {
			good, _ := b.matches(tiles, ox, oy, 5)
			if good > best {
				best = good
				b.ox = ox
				b.oy = oy
			}
		}
	}
}

fn test_the_picture_shows_the_room_and_the_cones_as_lit_floor() {
	tiles := tile_colours()
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		run_frames(mut s, 100, 0)
		b.find_origin(tiles)
		for n in 0 .. 4 {
			run_frames(mut s, 37, 0)
			// a few frames for the picture to catch up with the tiles; the cones keep moving, so
			// stop the guards' work: the picture is a frame behind, no more
			run_frames(mut s, 3, 0)
			good, all := b.matches(tiles, b.ox, b.oy, 1)
			assert all > 60000, 'most of the screen is room: ${all}'
			// a tile is drawn in place while it may be on its way to the screen, so a
			// few pixels of a tile that changed this frame can be old
			assert good * 100 >= all * 99, 'the picture shows the map (round ${n}): ${all - good} of ${all} pixels are wrong'
		}
		// and there is light on the floor: pixels of the lit tile, and the cone is where the bytes say
		pic := b.p.picture()
		cx := int(i16(b.value('camera_x')))
		cy := int(i16(b.value('camera_y')))
		mut lit_pixels := 0
		for sy in 0 .. 240 {
			for sx in 0 .. 320 {
				if pic.at(sx + b.ox, sy + b.oy) == tiles[4][5 * 16 + 5] {
					lit_pixels++
				}
			}
		}
		_ = cx
		_ = cy
		assert lit_pixels > 100, 'the lit floor is in the picture: ${lit_pixels}'
	}
}

// ---- cost ----

fn frame_cycles(pal bool) int {
	return if pal { 265_000 } else { 221_000 }
}

struct Costs {
	mean int
	p90  int
	max  int
}

fn measure(mut b Booted, frames int, each fn (mut b Booted, n int)) Costs {
	mut all := []int{}
	for n in 0 .. frames {
		each(mut b, n)
		all << b.p.busy_cycles(1)
	}
	all.sort()
	mut total := 0
	for a in all {
		total += a
	}
	return Costs{total / all.len, all[all.len * 9 / 10], all[all.len - 1]}
}

fn no_help(mut b Booted, n int) {
}

fn test_what_a_frame_costs() {
	for pal in [false, true] {
		mut b := boot(pal)
		mut s := Sim(b)
		wait_loaded(mut s)
		run_frames(mut s, 60, 0)
		budget := frame_cycles(pal)
		// the figure waits in its corner, the guards patrol
		calm := measure(mut b, 600, no_help)
		println('${if pal { 'PAL ' } else { 'NTSC' }} calm (4 guards on patrol, cones lit): mean ${calm.mean}, 90% under ${calm.p90}, most ${calm.max} cycles; a frame is ${budget}')
		assert calm.max < budget, 'a calm frame fits'

		// each guard's share: everyone waiting at a waypoint (sensing and the sprites), then
		// no guard at all
		waiting := measure(mut b, 60, fn (mut b Booted, n int) {
			for i in 0 .. 4 {
				b.poke_field('guards', i, 'pause', 200)
			}
		})
		for i in 0 .. 4 {
			b.poke_field('guards', i, 'live', 0)
		}
		b.p.frames(3)
		empty := measure(mut b, 60, no_help)
		println('  the figure alone ${empty.mean}; four guards waiting ${waiting.mean} (sensing, sprites and signs: ${(waiting.mean - empty.mean) / 4} a guard); patrolling ${calm.mean} (walking: ${(calm.mean - waiting.mean) / 4} a guard; cones: ${calm.p90 - calm.mean} more in the frames that move one)')

		// the worst case: all four guards chasing, the figure running, in the open yard
		mut w := boot(pal)
		mut ws := Sim(w)
		wait_loaded(mut ws)
		run_frames(mut ws, 20, 0)
		put_figure(mut ws, 33, 15)
		spots := [[28, 15], [38, 15], [33, 21], [33, 10]]
		for i in 0 .. 4 {
			w.poke_field('guards', i, 'x', spots[i][0] * 16 * 65536)
			w.poke_field('guards', i, 'y', (spots[i][1] * 16 - 1) * 65536)
		}
		worst := measure(mut w, 800, fn (mut w Booted, n int) {
			for i in 0 .. 4 {
				w.poke_element('guard_ai_state', i, alert)
				w.poke_field('guards', i, 'lost', 0)
			}
			w.poke('phase', 0)
			w.pad_log << 0
			dirs := [pad(.right), pad(.down), pad(.left), pad(.up)]
			hold_pad(mut w.p, dirs[(n / 45) % 4] | pad(.a))
		})
		println('  worst case (four guards chasing, the figure running, cones moving): mean ${worst.mean} (${worst.mean * 100 / budget}% of a frame), 90% under ${worst.p90}, most ${worst.max}; missed frames ${w.value('missed_frames')}')
		assert worst.mean * 100 < budget * 60, 'the worst case uses under 60% of a frame: ${worst.mean} of ${budget}'
		assert w.value('missed_frames') == 0 && b.value('missed_frames') == 0
	}
}
