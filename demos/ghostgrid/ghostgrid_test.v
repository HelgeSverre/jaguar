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
	g  &jaggame.Game
	it &jaggame.Interpreter
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
		// guard 0 walks east along the row of the west hall; stand in front of him
		put_figure(mut s, 12, 17)
		mut states := []int{}
		mut n := 0
		for b.value('phase') == 0 && n < 900 {
			s.frame(0)
			n++
			st := gstate(s, 0)
			if states.len == 0 || states.last() != st {
				states << st
			}
		}
		assert b.value('phase') == 2, 'the figure was caught (after ${n} frames; the guard went through ${states})'
		assert states[..3] == [patrol, suspicious, alert], 'patrol, then suspicious, then alert: ${states}'
		assert b.value('seen') >= 1
		assert b.value('level') == 2 || b.value('shown') == 3
		assert n < 400, 'caught in ${n} frames'
		// the end screen is up and the guards have stopped
		run_frames(mut s, 5, 0)
		gx0 := b.field('guards', 0, 'x')
		run_frames(mut s, 30, 0)
		assert b.field('guards', 0, 'x') == gx0, 'the guards stop when the mission is over'
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
		put_figure(mut s, 31, 17)
		run_frames(mut s, 3, pad(.up)) // face the crate
		s.frame(pad(.up, .c))
		spot_x := b.field('guards', 2, 'spot_x')
		assert gstate(s, 2) == suspicious || gstate(s, 2) == patrol
		run_frames(mut s, 2, 0)
		assert gstate(s, 2) == suspicious, 'the sentinel comes to look: ${state_names[gstate(s, 2)]}'
		for i in [0, 1, 3] {
			assert gstate(s, i) == patrol, 'guard ${i} is too far to hear it'
		}
		assert b.field('guards', 2, 'spot_x') == 31 * 16 + 8, 'he comes to where the knock was: ${spot_x}'
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

fn test_zz_debug() {
	mut b := boot(false)
	mut s := Sim(b)
	wait_loaded(mut s)
	put_figure(mut s, 12, 17)
	mut line := ''
	mut at := 0
	for n in 0 .. 600 {
		hold_pad(mut b.p, if n == 400 { pad(.a) } else { 0 })
		c := b.p.busy_cycles(1)
		b.pad_log << 0
		if c > 140000 || b.value('missed_frames') != at {
			at = b.value('missed_frames')
			line += ' ${n}:${c / 1000}(${gstate(s, 0)}/${b.value('phase')}/${b.value('missed_frames')})'
		}
	}
	println('hot frames:${line}')
}
