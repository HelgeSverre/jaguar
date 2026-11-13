module main

import os
import stbi
import tom
import jaggame
import jaggame.emulated
import jerry

// GHOSTGRID is tested by playing it: the image is booted in the emulator on
// both television standards and a robot plays it through the pad, reading
// where the figure is from the machine's memory by name. The same game
// logic then runs in the interpreter with the same pad and the two must
// agree.

const room_names = [hall, annex]

// rows is the text of a room, as lines.
fn rows(room int) []string {
	return room_names[room].trim('\n').split('\n')
}

fn is_blocking(ch u8) bool {
	return ch == `#` || ch == `c`
}

struct Cell {
	x int
	y int
}

// route is the shortest way from one tile to another through open floor, as
// the tiles to pass, found by a breadth-first search.
fn route(room int, from Cell, to Cell) []Cell {
	map_rows := rows(room)
	mut came := map[int]int{}
	key := fn (c Cell) int {
		return c.y * 100 + c.x
	}
	mut queue := [from]
	came[key(from)] = -1
	mut head := 0
	for head < queue.len {
		here := queue[head]
		head++
		if here == to {
			break
		}
		for step in [Cell{1, 0}, Cell{-1, 0}, Cell{0, 1}, Cell{0, -1}] {
			next := Cell{here.x + step.x, here.y + step.y}
			if next.y < 0 || next.y >= map_rows.len || next.x < 0 || next.x >= map_rows[0].len {
				continue
			}
			if is_blocking(map_rows[next.y][next.x]) || key(next) in came {
				continue
			}
			came[key(next)] = key(here)
			queue << next
		}
	}
	assert key(to) in came, 'there is a way from ${from} to ${to}'
	mut path := []Cell{}
	mut at := key(to)
	for at != -1 {
		path << Cell{at % 100, at / 100}
		at = came[at]
	}
	path.reverse_in_place()
	return path
}

// find is where a character is in a room, in tiles.
fn find(room int, ch u8) []Cell {
	mut found := []Cell{}
	for y, row in rows(room) {
		for x, c in row {
			if c == ch {
				found << Cell{x, y}
			}
		}
	}
	return found
}

struct Booted {
	img jaggame.Image
mut:
	p       emulated.Player
	pad_log []u32 // the pad of every frame played so far, for the interpreter
	// where the logical screen's top left corner is in the emulator's picture
	ox int
	oy int
}

// frame plays one frame with a pad and remembers it.
fn (mut b Booted) frame(mask u32) {
	hold_pad(mut b.p, mask)
	b.p.frames(1)
	b.pad_log << mask
}

fn boot(pal bool) Booted {
	img := build() or { panic(err) }
	return Booted{
		img: img
		p:   emulated.boot(img.bytes, pal) or { panic(err) }
	}
}

fn (b &Booted) value(name string) int {
	return int(b.img.value(b.p.m.ram, name) or { panic(err) })
}

// fixed is a `fix` variable of the game in pixels.
fn (b &Booted) fixed(name string) f64 {
	return f64(b.value(name)) / 65536.0
}

fn (b &Booted) camera() (int, int) {
	return int(i16(b.value('camera_x'))), int(i16(b.value('camera_y')))
}

// the buttons the robot can press, and the pad bits of the interpreter.
const robot_buttons = [jerry.Button.up, .down, .left, .right, .a]
const robot_masks = [jaggame.Button.up, .down, .left, .right, .a]

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

// steer is the pad that takes the figure towards a tile: the figure's
// position is its top left corner; standing in tile (tx, ty) it is at
// (16 tx, 16 ty - 1) (the centre of its box is the centre of the tile). It
// runs while it is far, and walks to be exact.
fn steer(px f64, py f64, target Cell) u32 {
	want_x := f64(target.x * 16)
	want_y := f64(target.y * 16 - 1)
	mut mask := u32(0)
	if want_x - px > 1.6 {
		mask |= jaggame.button_mask(.right)
	} else if px - want_x > 1.6 {
		mask |= jaggame.button_mask(.left)
	}
	if want_y - py > 1.6 {
		mask |= jaggame.button_mask(.down)
	} else if py - want_y > 1.6 {
		mask |= jaggame.button_mask(.up)
	}
	far := (if want_x > px { want_x - px } else { px - want_x }) + (if want_y > py {
		want_y - py
	} else {
		py - want_y
	})
	if far > 24 {
		mask |= jaggame.button_mask(.a)
	}
	return mask
}

fn (mut b Booted) wait_loaded() {
	b.frame(0)
	b.frame(0)
	mut n := 0
	for b.value('loading') != 0 {
		b.frame(0)
		n++
		assert n < 200, 'a room never finished loading'
	}
	for _ in 0 .. 3 {
		b.frame(0)
	}
}

// walk plays the robot along a route in the current room: it steers to
// each tile in turn and gives up after `limit` frames. It calls `each` after
// every frame.
fn (mut b Booted) walk(path []Cell, limit int, each fn (b &Booted)) {
	mut at := 0
	room := b.value('room_number')
	for _ in 0 .. limit {
		if at >= path.len || b.value('room_number') != room {
			break // there, or through the exit
		}
		px := b.fixed('px')
		py := b.fixed('py')
		target := path[at]
		dx := px - f64(target.x * 16)
		dy := py - f64(target.y * 16 - 1)
		if dx * dx + dy * dy < 2.6 * 2.6 || (at < path.len - 1 && dx * dx + dy * dy < 6 * 6) {
			at++
			continue
		}
		b.frame(steer(px, py, target))
		each(&b)
	}
	b.frame(0)
	assert at >= path.len - 1 || b.value('room_number') != room, 'the robot did not get to the end of its route (${at} of ${path.len})'
}

fn no_check(b &Booted) {
}

fn test_the_game_builds_and_the_art_is_imported() {
	img := build()!
	assert img.bytes.len > 1000
	assert img.symbols['rt.start'] == jaggame.load_address
}

fn test_the_first_room_loads_and_the_figure_stands_on_the_start() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		assert b.value('missed_frames') == 0
		assert b.value('room_number') == 0
		assert b.value('room_width') == 34 * 16 && b.value('room_height') == 24 * 16
		start := find(0, `@`)[0]
		assert b.fixed('px') == start.x * 16 && b.fixed('py') == start.y * 16
		assert b.value('total') == 4 && b.value('chips') == 0
		cx, cy := b.camera()
		assert cx == 0 && cy == 0, 'the camera is at the corner: ${cx}, ${cy}'
	}
}

// inside_wall tells whether the figure's box overlaps a wall or cover block
// of a room: the box is 10 by 10, 3 and 4 from the corner.
fn inside_wall(room int, px f64, py f64) bool {
	map_rows := rows(room)
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

fn test_the_figure_cannot_enter_a_wall_however_it_is_pushed() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		// Pushing into the corner: left and up, then flush against both walls.
		hold_pad(mut b.p, jaggame.button_mask(.left) | jaggame.button_mask(.up))
		b.p.frames(40)
		assert b.fixed('px') == 13 && b.fixed('py') == 12, 'flush in the corner: ${b.fixed('px')}, ${b.fixed('py')}'

		// Running into it changes nothing: no tunnelling at 3 pixels a frame.
		hold_pad(mut b.p,
			jaggame.button_mask(.left) | jaggame.button_mask(.up) | jaggame.button_mask(.a))
		b.p.frames(40)
		assert b.fixed('px') == 13 && b.fixed('py') == 12

		// Down and to the left slides down the west wall.
		hold_pad(mut b.p, jaggame.button_mask(.left) | jaggame.button_mask(.down))
		mut last := b.fixed('py')
		for _ in 0 .. 30 {
			b.p.frames(1)
			assert b.fixed('px') == 13, 'sliding along the wall: x ${b.fixed('px')}'
			assert b.fixed('py') >= last
			last = b.fixed('py')
		}
		assert last > 12 + 30, 'it slid ${last - 12} pixels'

		// All of it again, with a random pad: every frame the box is clear of the walls.
		mut seed := u32(12345)
		mut mask := u32(0)
		for n in 0 .. 3000 {
			if n % 12 == 0 {
				seed = seed * 1664525 + 1013904223
				mask = (seed >> 16) & 0xf // a direction: up, down, left, right
				if (seed >> 20) & 1 == 1 {
					mask |= jaggame.button_mask(.a)
				}
				mask = u32((mask & 0xf) | (mask & jaggame.button_mask(.a)))
			}
			hold_pad(mut b.p, mask)
			b.p.frames(1)
			assert !inside_wall(0, b.fixed('px'), b.fixed('py')), 'in a wall at ${b.fixed('px')}, ${b.fixed('py')} after ${n} frames'
			if b.value('room_number') != 0 {
				break // it found the exit
			}
		}
		assert b.value('missed_frames') == 0
	}
}

fn test_the_robot_walks_to_the_exit_picking_up_chips_and_the_camera_follows() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		chips := find(0, `o`)
		exit_pad := find(0, `X`)[0]
		mut at := find(0, `@`)[0]
		mut stops := []Cell{}
		stops << chips[0]
		stops << chips[2]
		stops << exit_pad
		mut moved_camera := false
		mut counted := 0
		mut peak_x := 0
		mut peak_y := 0
		for i, stop in stops {
			path := route(0, at, stop)
			b.walk(path, 1500, fn (b &Booted) {
				// The camera is on the figure, as far as the room allows.
				cx, cy := b.camera()
				want_x := int_max(0, int_min(int(b.fixed('px')) + 8 - 160, 34 * 16 - 320))
				want_y := int_max(0, int_min(int(b.fixed('py')) + 9 - 120, 24 * 16 - 240))
				if b.value('loading') == 0 && b.value('room_number') == 0 {
					assert cx == want_x && cy == want_y, 'room ${b.value('room_number')} loading ${b.value('loading')} camera ${cx}, ${cy} for the figure at ${b.fixed('px')}, ${b.fixed('py')}'
				}
			})
			at = stop
			if i == 0 {
				counted = b.value('chips')
				assert counted == 1, 'the first chip is counted: ${counted}'
			}
			if i == 1 {
				assert b.value('chips') == 2
			}
			cx, cy := b.camera()
			peak_x = int_max(peak_x, cx)
			peak_y = int_max(peak_y, cy)
			moved_camera = moved_camera || cx > 0 || cy > 0
			if i == 2 {
				break
			}
		}
		assert moved_camera
		assert peak_x == 34 * 16 - 320 && peak_y > 0, 'the camera reached the east edge: ${peak_x}, ${peak_y}'
		// The robot is on the exit: the other room is loading or loaded.
		b.wait_loaded()
		assert b.value('room_number') == 1
		assert b.value('missed_frames') == 0
	}
}

fn test_the_second_room_is_smaller_than_the_screen_and_centred() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		b.walk(route(0, find(0, `@`)[0], find(0, `X`)[0]), 3000, no_check)
		b.wait_loaded()
		assert b.value('room_number') == 1
		assert b.value('room_width') == 14 * 16 && b.value('room_height') == 10 * 16
		cx, cy := b.camera()
		assert cx == -(320 - 224) / 2 && cy == -(240 - 160) / 2, 'centred: ${cx}, ${cy}'
		start := find(1, `@`)[0]
		assert b.fixed('px') == start.x * 16 && b.fixed('py') == start.y * 16, 'the figure is on the start of the room'
		assert b.value('chips') == 0 && b.value('total') == 1
	}
}

fn test_the_whole_trip_there_and_back() {
	mut b := boot(false)
	b.wait_loaded()
	b.walk(route(0, find(0, `@`)[0], find(0, `X`)[0]), 3000, no_check)
	b.wait_loaded()
	assert b.value('room_number') == 1
	chip := find(1, `o`)[0]
	b.walk(route(1, find(1, `@`)[0], chip), 1500, fn (b &Booted) {
		assert !inside_wall(1, b.fixed('px'), b.fixed('py'))
	})
	assert b.value('chips') == 1
	b.walk(route(1, chip, find(1, `X`)[0]), 1500, no_check)
	b.wait_loaded()
	assert b.value('room_number') == 0, 'back in the hall'
	assert b.value('chips') == 0 && b.value('total') == 4
	assert b.value('missed_frames') == 0
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

// background is the colour behind the room.
fn background() u32 {
	return tom.cry_to_rgb(u32(jaggame.cry(6, 8, 20)))
}

// room_pixel is what the logical screen should show at (sx, sy) for a camera:
// the tile of the room as it is in the machine's memory now, or the background.
fn (b &Booted) room_pixel(tiles [][]u32, cx int, cy int, sx int, sy int) u32 {
	wx := sx + cx
	wy := sy + cy
	w := b.value('rt_room_w')
	h := b.value('rt_room_h')
	if wx < 0 || wy < 0 || wx >= w * 16 || wy >= h * 16 {
		return background()
	}
	tile := int(b.img.element(b.p.m.ram, 'rt_map', (wy / 16) * w + wx / 16) or { panic(err) })
	return tiles[tile][(wy % 16) * 16 + wx % 16]
}

// covered tells whether a pixel of the logical screen belongs to something
// that is not the room: the figure, or the text.
fn (b &Booted) covered(cx int, cy int, sx int, sy int) bool {
	if sx < 140 && sy < 28 {
		return true // the HUD
	}
	fx := int(b.fixed('px')) - cx
	fy := int(b.fixed('py')) - cy
	return sx >= fx && sx < fx + 16 && sy >= fy && sy < fy + 16
}

// matches counts how many pixels of the room part of the logical screen are
// what they should be, and how many there are, with the screen at (ox, oy)
// in the emulator's picture.
fn (b &Booted) matches(tiles [][]u32, ox int, oy int, step int) (int, int) {
	cx, cy := b.camera()
	pic := b.p.picture()
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
			if pic.at(sx + ox, sy + oy) == b.room_pixel(tiles, cx, cy, sx, sy) {
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

fn (b &Booted) assert_picture(tiles [][]u32, what string) {
	good, all := b.matches(tiles, b.ox, b.oy, 1)
	cx, cy := b.camera()
	assert all > 70000, 'most of the screen is in the picture: ${all}'
	assert good == all, '${what}: ${all - good} of ${all} pixels are wrong, camera ${cx}, ${cy}'
}

fn test_the_picture_shows_the_room_and_a_picked_up_chip_is_gone() {
	tiles := tile_colours()
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		b.find_origin(tiles)
		b.assert_picture(tiles, 'the first screen')

		// The first chip: its tile is the chip tile (4) in the map and in the picture.
		chip := find(0, `o`)[0]
		cell := chip.y * 34 + chip.x
		assert b.img.element(b.p.m.ram, 'rt_map', cell)! == 4
		b.walk(route(0, find(0, `@`)[0], chip), 1500, no_check)
		b.frame(0)
		b.frame(0)
		assert b.value('chips') == 1
		assert b.img.element(b.p.m.ram, 'rt_map', cell)! == 0, 'the tile is floor now'
		b.assert_picture(tiles, 'after the chip')
		// And it is the floor that shows where the chip was: look at the pixel
		// a chip has its glint on.
		// Step off the tile, so that the figure does not stand on it.
		for _ in 0 .. 24 {
			b.frame(jaggame.button_mask(.right))
		}
		b.frame(0)
		b.frame(0)
		b.frame(0)
		cx, cy := b.camera()
		pic := b.p.picture()
		glint := pic.at(b.ox + chip.x * 16 + 5 - cx, b.oy + chip.y * 16 + 5 - cy)
		assert glint == tiles[0][5 * 16 + 5], 'the chip is gone from the picture'
		assert glint != tiles[4][5 * 16 + 5]
	}
}

fn test_the_camera_stops_at_the_edges_of_the_room_in_the_picture() {
	tiles := tile_colours()
	mut b := boot(false)
	b.wait_loaded()
	b.find_origin(tiles)
	// Run to the south east corner of the hall and look at it.
	hold := jaggame.button_mask(.right) | jaggame.button_mask(.down) | jaggame.button_mask(.a)
	mut checks := 0
	for n in 0 .. 900 {
		b.frame(hold)
		if n % 60 == 59 {
			// Stop for the picture to catch up with the camera: it is a frame behind.
			for _ in 0 .. 3 {
				b.frame(0)
			}
			b.assert_picture(tiles, 'on the way')
			checks++
		}
	}
	cx, cy := b.camera()
	assert cx == 34 * 16 - 320 || cy == 24 * 16 - 240 || b.fixed('px') > 100, 'it ran somewhere: ${cx}, ${cy}'
	// Every part of the way shows a room whose edge never leaves the screen:
	// the camera never shows beyond the room.
	assert cx >= 0 && cx <= 34 * 16 - 320 && cy >= 0 && cy <= 24 * 16 - 240
	assert checks == 15
}

fn test_the_small_room_is_centred_in_the_picture() {
	tiles := tile_colours()
	mut b := boot(false)
	b.wait_loaded()
	b.find_origin(tiles)
	b.walk(route(0, find(0, `@`)[0], find(0, `X`)[0]), 3000, no_check)
	b.wait_loaded()
	assert b.value('room_number') == 1
	b.assert_picture(tiles, 'the annex')
	pic := b.p.picture()
	// The room is 224 by 160: the background on every side, and its wall
	// where the camera says.
	assert pic.at(b.ox + 10, b.oy + 10) == background()
	assert pic.at(b.ox + 310, b.oy + 230) == background()
	assert pic.at(b.ox + 48 + 2, b.oy + 40 + 8) == tiles[1][8 * 16 + 2], 'the top left wall block'
}

// ---- the interpreter ----

fn test_the_interpreter_does_what_the_machine_did() {
	for pal in [false, true] {
		mut b := boot(pal)
		b.wait_loaded()
		// A trip: to a chip, to the exit, across the annex and back; and some pushing at walls.
		b.walk(route(0, find(0, `@`)[0], find(0, `o`)[0]), 1500, no_check)
		for _ in 0 .. 40 {
			b.frame(jaggame.button_mask(.left) | jaggame.button_mask(.up))
		}
		b.walk(route(0, find(0, `o`)[0], find(0, `X`)[0]), 3000, no_check)
		b.wait_loaded()
		assert b.value('room_number') == 1
		for _ in 0 .. 30 {
			b.frame(jaggame.button_mask(.right) | jaggame.button_mask(.a))
		}

		mut g := describe()
		mut it := g.interpreter(if pal { jaggame.Region.pal } else { jaggame.Region.ntsc })!
		mut again := boot(pal)
		for n, mask in b.pad_log {
			again.frame(mask)
			g.step(mut it, mask)!
			for name in ['px', 'py', 'chips', 'room_number', 'loading', 'camera_x', 'camera_y',
				'facing', 'playing', 'total'] {
				assert again.value(name) == int(it.value(name)!), 'frame ${n}: ${name}: machine ${again.value(name)}, interpreter ${it.value(name)!}'
			}
		}
		mut differences := again.img.differences(it, again.p.m.ram)
		differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale'))
		assert differences.len == 0, differences.join('\n')
		assert again.value('room_number') == 1 && b.pad_log.len > 600
	}
}

// ---- cost ----

fn test_what_a_frame_costs() {
	mut b := boot(false)
	b.wait_loaded()
	standing := b.p.busy_cycles(30)
	hold_pad(mut b.p,
		jaggame.button_mask(.right) | jaggame.button_mask(.down) | jaggame.button_mask(.a))
	b.p.frames(10)
	walking := b.p.busy_cycles(60)
	hold_pad(mut b.p, 0)
	println('ghostgrid: standing ${standing}, running ${walking} cycles a frame')
	assert standing < 60000 && walking < 80000

	// A room loading: the cost of each of its frames.
	mut c := boot(false)
	c.frame(0)
	mut worst := 0
	mut total := 0
	mut n := 0
	for c.value('loading') != 0 || n < 3 {
		cycles := c.p.busy_cycles(1)
		worst = int_max(worst, cycles)
		total += cycles
		n++
		assert n < 100
	}
	println('ghostgrid: the hall loads in ${n} frames, at most ${worst} cycles a frame')
	assert worst < 200000, 'a loading frame has to fit a frame (221,000 cycles): ${worst}'
	assert c.value('missed_frames') == 0
}
