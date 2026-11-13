module jaggame

import math
import os
import rand
import jaggame.emulated

// Sight: the cone, the line, the arctangent and hearing, each against a plain
// V model, the interpreter against the machine on random rooms, and what
// the walk costs.

fn sight_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'jaggame_${os.getpid()}_${name}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn sight_tiles(dir string) string {
	mut pic := new_canvas(48, 16)
	pic.fill(0, 0, 16, 16, 30, 60, 90)
	pic.fill(16, 0, 16, 16, 200, 60, 60)
	pic.fill(32, 0, 16, 16, 240, 220, 40)
	path := os.join_path(dir, 'tiles.png')
	pic.save(path) or { panic(err) }
	return path
}

// random_room is a room of random walls and cover blocks around a wall.
fn random_room(mut rng rand.PRNG, w int, h int, percent int) string {
	mut rows := []string{}
	for y in 0 .. h {
		mut row := ''
		for x in 0 .. w {
			if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
				row += '#'
			} else {
				roll := rng.intn(100) or { 0 }
				row += if roll < percent {
					'#'
				} else if roll < percent + 6 {
					'c'
				} else {
					'.'
				}
			}
		}
		rows << row
	}
	return '\n' + rows.join('\n') + '\n'
}

// model_blocks is whether the tile at a pixel blocks sight, for a standing or
// crouching target: wall blocks, cover blocks only the crouching, outside is
// a wall.
fn model_blocks(rows []string, px int, py int, low bool) bool {
	col := int(math.floor(f64(px) / 16.0))
	row := int(math.floor(f64(py) / 16.0))
	if col < 0 || row < 0 || row >= rows.len || col >= rows[0].len {
		return true
	}
	ch := rows[row][col]
	return ch == `#` || (ch == `c` && low)
}

// model_clear is `rt_line_clear` written the plain way: the places of the
// line one by one, each worked out from the start with a multiplication.
fn model_clear(rows []string, x0 int, y0 int, x1 int, y1 int, low bool) bool {
	dx := x1 - x0
	dy := y1 - y0
	adx := int_abs(dx)
	ady := int_abs(dy)
	if adx > 255 || ady > 255 {
		return false
	}
	steps := (int_max(adx, ady) + 7) / 8
	if steps < 2 {
		return true
	}
	mut ix := (adx * 128) / steps
	mut iy := (ady * 128) / steps
	if dx < 0 {
		ix = -ix
	}
	if dy < 0 {
		iy = -iy
	}
	for k in 1 .. steps {
		px := int(math.floor(f64(x0 * 128 + ix * k) / 128.0))
		py := int(math.floor(f64(y0 * 128 + iy * k) / 128.0))
		if model_blocks(rows, px, py, low) {
			return false
		}
	}
	return true
}

fn int_abs(a int) int {
	return if a < 0 { -a } else { a }
}

fn test_the_arctangent_is_within_one_step_of_the_real_one() {
	mut worst := 0
	mut rng := rand.new_default(seed_: [u32(1), 2])
	for _ in 0 .. 20000 {
		dx := rng.intn(2001) or { 0 } - 1000
		dy := rng.intn(2001) or { 0 } - 1000
		if dx == 0 && dy == 0 {
			continue
		}
		got := direction_of(dx, dy)
		mut want := int(math.round(math.atan2(f64(dy), f64(dx)) * 256.0 / (2.0 * math.pi)))
		want = (want + 256) & 255
		mut off := int_abs(got - want)
		if off > 128 {
			off = 256 - off
		}
		worst = int_max(worst, off)
	}
	assert worst <= 1, 'the worst error is ${worst} 256ths of a turn'
	assert direction_of(10, 0) == 0 && direction_of(0, 10) == 64 && direction_of(-10, 0) == 128
		&& direction_of(0, -10) == 192
}

fn test_the_cone_agrees_with_the_angle_except_at_its_very_edge() {
	mut rng := rand.new_default(seed_: [u32(7), 9])
	for _ in 0 .. 20000 {
		dx := rng.intn(401) or { 0 } - 200
		dy := rng.intn(401) or { 0 } - 200
		facing := rng.intn(256) or { 0 }
		range := 20 + rng.intn(230) or { 0 }
		half := 4 + rng.intn(60) or { 0 }
		got := cone_inside(dx, dy, facing, range, half)
		dist := math.sqrt(f64(dx * dx + dy * dy))
		if dist > f64(range) + 0.01 {
			assert !got
			continue
		}
		if dist < f64(range) - 0.01 && (dx != 0 || dy != 0) {
			mut off := int_abs(direction_of(dx, dy) - facing)
			if off > 128 {
				off = 256 - off
			}
			if dist > 4 && off < half - 3 {
				assert got, 'inside: ${dx}, ${dy} facing ${facing} half ${half} range ${range}'
			}
			if dist > 4 && off > half + 3 {
				assert !got, 'outside: ${dx}, ${dy} facing ${facing} half ${half} range ${range}'
			}
		}
	}
}

fn test_the_cone_cells_of_a_facing_are_a_wedge() {
	cells := cone_cells(angle_right, 80, 24)
	assert cells[0] == Point{0, 0}
	assert Point{3, 0} in cells && Point{5, 0} in cells
	assert Point{-1, 0} !in cells && Point{0, 3} !in cells
	assert Point{4, 1} in cells && Point{4, -1} in cells
	assert cells.len > 8 && cells.len < 30, '${cells.len} cells'
	up := cone_cells(angle_up, 80, 24)
	assert up.len == cells.len && Point{0, -4} in up
}

fn test_the_model_agrees_with_a_one_pixel_walk_except_for_grazes() {
	// A wall that the line crosses for more than 9 pixels in a row is never missed.
	mut rng := rand.new_default(seed_: [u32(3), 4])
	for _ in 0 .. 300 {
		rows := random_room(mut rng, 24, 16, 22).trim('\n').split('\n')
		for _ in 0 .. 30 {
			x0 := 16 + rng.intn(300) or { 0 }
			y0 := 16 + rng.intn(200) or { 0 }
			x1 := int_max(0, int_min(383, x0 + rng.intn(200) or { 0 } - 100))
			y1 := int_max(0, int_min(255, y0 + rng.intn(200) or { 0 } - 100))
			dx := x1 - x0
			dy := y1 - y0
			major := int_max(int_abs(dx), int_abs(dy))
			if major == 0 || major > 255 {
				continue
			}
			mut run := 0
			mut crossed := false
			for k in 12 .. major - 12 {
				px := x0 + int(math.floor(f64(dx * k) / f64(major)))
				py := y0 + int(math.floor(f64(dy * k) / f64(major)))
				if model_blocks(rows, px, py, true) {
					run++
					if run >= 10 {
						crossed = true
					}
				} else {
					run = 0
				}
			}
			if crossed {
				assert !model_clear(rows, x0, y0, x1, y1, true), 'a wall in the way is missed: ${x0},${y0} to ${x1},${y1}'
			}
		}
	}
}

// sight_game is a room of the text with the sight queried through variables
// that the test sets: the two points, the facing, the range and half angle
// and a noise.
fn sight_game(dir string, room string) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(sight_tiles(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`c`, 2, flag_solid | flag_cover)
	g.room('arena', room)
	fx := g.p.i16('fx')
	fy := g.p.i16('fy')
	tx := g.p.i16('tx')
	ty := g.p.i16('ty')
	facing := g.p.u8('facing')
	range := g.p.u8('range')
	half := g.p.u8('half')
	nx := g.p.i16('nx')
	ny := g.p.i16('ny')
	nr := g.p.u16('nr')
	see := g.p.bool('see')
	see_low := g.p.bool('see_low')
	clear := g.p.bool('clear')
	clear_low := g.p.bool('clear_low')
	angle := g.p.u8('angle')
	heard := g.p.bool('heard')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.if_(g.loading.invert())
	c.set(see, g.can_see(fx, fy, facing, tx, ty, range, half))
	c.set(see_low, g.can_see_crouched(fx, fy, facing, tx, ty, range, half))
	c.set(clear, g.sight.line_clear.call(fx, fy, tx, ty, false))
	c.set(clear_low, g.sight.line_clear.call(fx, fy, tx, ty, true))
	c.set(angle, g.direction(tx.sub(fx), ty.sub(fy)))
	c.if_(g.frame.eq(0xfff0))
	g.noise(mut c, nx, ny, nr)
	c.end()
	c.set(heard, g.hears(tx, ty))
	c.end()
	return g
}

struct Query {
	fx     int
	fy     int
	tx     int
	ty     int
	facing int
	range  int
	half   int
}

fn random_query(mut rng rand.PRNG, w int, h int) Query {
	fx := 16 + rng.intn(w * 16 - 32) or { 0 }
	fy := 16 + rng.intn(h * 16 - 32) or { 0 }
	reach := 30 + rng.intn(226) or { 0 }
	tx := int_max(0, int_min(w * 16 - 1, fx + rng.intn(reach * 2) or { 0 } - reach))
	ty := int_max(0, int_min(h * 16 - 1, fy + rng.intn(reach * 2) or { 0 } - reach))
	// half the time the eye looks more or less at the target
	aimed := (direction_of(tx - fx, ty - fy) + rng.intn(41) or { 0 } - 20 + 256) & 255
	return Query{
		fx:     fx
		fy:     fy
		tx:     tx
		ty:     ty
		facing: if (rng.intn(2) or { 0 }) == 0 { aimed } else { rng.intn(256) or { 0 } }
		range:  40 + rng.intn(216) or { 0 }
		half:   2 + rng.intn(63) or { 0 }
	}
}

fn model_see(rows []string, q Query, low bool) bool {
	return cone_inside(q.tx - q.fx, q.ty - q.fy, q.facing, q.range, q.half)
		&& model_clear(rows, q.fx, q.fy, q.tx, q.ty, low)
}

fn set_query(mut it Interpreter, q Query) ! {
	it.set_value('fx', q.fx)!
	it.set_value('fy', q.fy)!
	it.set_value('tx', q.tx)!
	it.set_value('ty', q.ty)!
	it.set_value('facing', q.facing)!
	it.set_value('range', q.range)!
	it.set_value('half', q.half)!
}

fn write_sight_word(mut p emulated.Player, at u32, value int) {
	p.m.ram[at] = u8(value >> 8)
	p.m.ram[at + 1] = u8(value)
}

fn test_the_interpreter_the_machine_and_the_plain_model_agree_on_random_rooms() {
	mut rng := rand.new_default(seed_: [u32(11), 12])
	mut asked := 0
	mut seen_yes := 0
	mut blocked_by_wall := 0
	for room_number in 0 .. 14 {
		w := 20 + rng.intn(12) or { 0 }
		h := 12 + rng.intn(8) or { 0 }
		text := random_room(mut rng, w, h, 8 + room_number * 2)
		rows := text.trim('\n').split('\n')
		dir := sight_dir('sight${room_number}')
		mut g := sight_game(dir, text)
		img := g.build() or { panic(err) }
		mut h2 := sight_game(dir, text)
		mut it := h2.interpreter(.ntsc) or { panic(err) }
		for _ in 0 .. 40 {
			h2.step(mut it, 0) or { panic(err) }
		}
		mut p := emulated.boot(img.bytes, false) or { panic(err) }
		p.frames(40)
		for _ in 0 .. 260 {
			q := random_query(mut rng, w, h)
			set_query(mut it, q) or { panic(err) }
			h2.step(mut it, 0) or { panic(err) }
			for name, v in {
				'fx':     q.fx
				'fy':     q.fy
				'tx':     q.tx
				'ty':     q.ty
				'facing': q.facing
				'range':  q.range
				'half':   q.half
			} {
				at := img.symbols[name]
				if name in ['facing', 'range', 'half'] {
					p.m.ram[at] = u8(v)
				} else {
					write_sight_word(mut p, at, v)
				}
			}
			p.frames(1)
			p.settle()
			want_see := model_see(rows, q, false)
			want_low := model_see(rows, q, true)
			want_clear := model_clear(rows, q.fx, q.fy, q.tx, q.ty, false)
			want_clear_low := model_clear(rows, q.fx, q.fy, q.tx, q.ty, true)
			want_angle := direction_of(q.tx - q.fx, q.ty - q.fy)
			where := 'room ${room_number}, ${q}'
			assert it.value('see')! == i64(if want_see {
				1
			} else {
				0
			}), 'see (interpreter): ${where}'
			assert it.value('see_low')! == i64(if want_low {
				1
			} else {
				0
			}), 'see_low (interpreter): ${where}'
			assert it.value('clear')! == i64(if want_clear {
				1
			} else {
				0
			}), 'clear (interpreter): ${where}'
			assert it.value('clear_low')! == i64(if want_clear_low {
				1
			} else {
				0
			}), 'clear_low (interpreter): ${where}'
			assert it.value('angle')! == want_angle, 'angle (interpreter): ${where}'
			for name in ['see', 'see_low', 'clear', 'clear_low', 'angle'] {
				assert img.value(p.m.ram, name)! == it.value(name)!, '${name}: machine ${img.value(p.m.ram,
					name)!}, interpreter ${it.value(name)!}: ${where}'
			}
			asked++
			if want_see {
				seen_yes++
			}
			if want_clear && !want_clear_low {
				blocked_by_wall++
			}
		}
	}
	println('sight: ${asked} queries agree in 14 random rooms; ${seen_yes} seen, ${blocked_by_wall} where cover hides a crouching target')
	assert seen_yes > 300 && blocked_by_wall > 20, 'the queries cover what they should'
}

fn test_a_cover_block_hides_only_a_crouching_target() {
	room := '
##########
#........#
#..c.....#
#........#
##########
'
	dir := sight_dir('cover')
	mut g := sight_game(dir, room)
	mut it := g.interpreter(.ntsc)!
	for _ in 0 .. 40 {
		g.step(mut it, 0)!
	}
	// From the middle of tile (1,2) to the middle of tile (6,2): the block at (3,2) is on the way.
	q := Query{24, 40, 104, 40, 0, 120, 30}
	set_query(mut it, q)!
	g.step(mut it, 0)!
	assert it.value('see')! == 1, 'a standing figure is seen over the cover'
	assert it.value('see_low')! == 0, 'a crouching one is not'
	assert it.value('clear')! == 1 && it.value('clear_low')! == 0
	// Along the row above the block both are seen.
	set_query(mut it, Query{24, 24, 104, 24, 0, 120, 30})!
	g.step(mut it, 0)!
	assert it.value('see')! == 1 && it.value('see_low')! == 1
	// Behind the eye, out of range and outside the cone.
	set_query(mut it, Query{104, 24, 24, 24, 0, 120, 30})!
	g.step(mut it, 0)!
	assert it.value('see')! == 0, 'behind the eye'
	set_query(mut it, Query{24, 24, 152, 24, 0, 120, 30})!
	g.step(mut it, 0)!
	assert it.value('see')! == 0, 'out of range'
	set_query(mut it, Query{24, 24, 100, 56, 0, 120, 10})!
	g.step(mut it, 0)!
	assert it.value('see')! == 0, 'outside a narrow cone'
}

fn test_hearing_is_a_circle_for_two_frames() {
	room := '
##########
#........#
#........#
##########
'
	dir := sight_dir('hearing')
	mut g := sight_game(dir, room)
	mut it := g.interpreter(.ntsc)!
	for _ in 0 .. 40 {
		g.step(mut it, 0)!
	}
	set_query(mut it, Query{24, 24, 60, 24, 0, 100, 30})!
	g.step(mut it, 0)!
	assert it.value('heard')! == 0, 'no noise, nothing heard'
	// Make a noise at (20, 24) with a radius of 50 by running the update on a frame whose number the game looks for.
	it.set_value('frame', 0xfff0 - 1)!
	it.set_value('nx', 20)!
	it.set_value('ny', 24)!
	it.set_value('nr', 50)!
	g.step(mut it, 0)!
	assert it.value('heard')! == 1, 'a listener 40 pixels from a noise of radius 50 hears it'
	set_query(mut it, Query{24, 24, 80, 24, 0, 100, 30})!
	g.step(mut it, 0)!
	assert it.value('heard')! == 0, 'one 60 pixels away does not (and it was the next frame, still heard by those in range)'
	set_query(mut it, Query{24, 24, 60, 24, 0, 100, 30})!
	g.step(mut it, 0)!
	assert it.value('heard')! == 0, 'the noise has died away after two frames'
}

fn test_what_a_look_costs() {
	dir := sight_dir('sightcost')
	mut cycles := []int{}
	for count in [0, 40] {
		mut g := new_game(Config{ sprites: 1, layers: 1 })
		g.tileset(sight_tiles(dir))
		g.legend_tile(`.`, 0, 0)
		g.legend_tile(`#`, 1, flag_solid)
		g.room('arena', '
################################
#..............................#
#..............................#
#..............................#
################################
')
		hits := g.p.u16('hits')
		mut c := g.define_init()
		g.load_room(mut c, Room{0, 'arena'})
		c = g.define_update()
		c.repeat(count)
		c.add_to(hits, g.can_see(24, 24, 0, 144, 24, 128, 30).as_(.u16))
		c.end()
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, false) or { panic(err) }
		p.frames(40)
		cycles << p.busy_cycles(20)
		assert count == 0 || img.value(p.m.ram, 'hits')! > 0
	}
	each := (cycles[1] - cycles[0]) / 40
	println('can_see: ${each} cycles a call over 120 pixels (15 places looked at)')
	assert each < 6000
}

fn test_the_cells_a_cone_lights_are_the_cells_can_see_says_yes_to() {
	mut rng := rand.new_default(seed_: [u32(21), 22])
	mut lit := 0
	mut asked := 0
	for room_number in 0 .. 6 {
		w := 16 + rng.intn(10) or { 0 }
		h := 12 + rng.intn(6) or { 0 }
		text := random_room(mut rng, w, h, 10 + room_number * 3)
		rows := text.trim('\n').split('\n')
		dir := sight_dir('cells${room_number}')
		mut g := sight_game(dir, text)
		mut it := g.interpreter(.ntsc)!
		for _ in 0 .. 40 {
			g.step(mut it, 0)!
		}
		for _ in 0 .. 12 {
			tx := 1 + rng.intn(w - 2) or { 1 }
			ty := 1 + rng.intn(h - 2) or { 1 }
			if rows[ty][tx] != `.` {
				continue
			}
			facing := (rng.intn(4) or { 0 }) * 64
			for crouched in [false, true] {
				cells := g.view_cells(Room{0, 'arena'}, tx, ty, facing, 80, 24, crouched)
				for y in 0 .. h {
					for x in 0 .. w {
						if rows[y][x] != `.` {
							continue
						}
						set_query(mut it, Query{tx * 16 + 8, ty * 16 + 8, x * 16 + 8, y * 16 + 8, facing, 80, 24})!
						g.step(mut it, 0)!
						says := it.value(if crouched { 'see_low' } else { 'see' })! == 1
						in_list := Point{x, y} in cells
						assert says == in_list, 'tile ${x},${y} seen from ${tx},${ty} facing ${facing} crouched ${crouched}: can_see says ${says}, the list says ${in_list}'
						asked++
						if in_list {
							lit++
						}
					}
				}
			}
		}
	}
	println('cells: ${asked} tiles asked, ${lit} lit, can_see and the lists agree')
	assert lit > 100
}

// set_game changes a tile by cell number or by place when the test says so.
fn set_game(dir string) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(sight_tiles(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`c`, 2, flag_solid | flag_cover)
	g.room('arena', '
##########
#........#
#........#
##########
')
	cell := g.p.u16('cell')
	col := g.p.i16('col')
	row := g.p.i16('row')
	tile := g.p.u8('tile')
	mode := g.p.u8('mode')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.if_(g.loading.invert())
	c.if_(mode.eq(1))
	g.set_cell(mut c, cell, tile)
	c.else_if(mode.eq(2))
	g.set_tile(mut c, col, row, tile)
	c.end()
	c.set(mode, 0)
	c.end()
	return g
}

fn test_set_cell_and_set_tile_change_the_map_queue_and_count_what_does_not_fit() {
	dir := sight_dir('setcell')
	mut g := set_game(dir)
	img := g.build()!
	mut h := set_game(dir)
	mut it := h.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!
	for _ in 0 .. 40 {
		h.step(mut it, 0)!
	}
	p.frames(40)
	mut steps := 0
	// 70 changes in 70 frames are fine; then 70 in one frame, where only 64 fit.
	for k in 0 .. 70 {
		mode := 1 + k % 2
		it.set_value('cell', 11 + k % 6)!
		it.set_value('col', 1 + k % 6)!
		it.set_value('row', 2)!
		it.set_value('tile', 2 + k % 3)!
		it.set_value('mode', mode)!
		write_sight_word(mut p, img.symbols['cell'], 11 + k % 6)
		write_sight_word(mut p, img.symbols['col'], 1 + k % 6)
		write_sight_word(mut p, img.symbols['row'], 2)
		p.m.ram[img.symbols['tile']] = u8(2 + k % 3)
		p.m.ram[img.symbols['mode']] = u8(mode)
		h.step(mut it, 0)!
		p.frames(1)
		p.settle()
		steps++
	}
	for k in 0 .. 40 {
		assert img.element(p.m.ram, 'rt_map', k)! == it.element('rt_map', k)!, 'cell ${k}'
	}
	for k in [11, 13, 15, 22, 24, 26] {
		assert it.element('rt_map', k)! >= 2, 'cell ${k} was set'
	}
	assert img.value(p.m.ram, 'rt_tile_lost')! == 0 && it.value('rt_tile_lost')! == 0
	// Outside the room nothing happens: cell 40 of a 10 by 4 room, and column 12.
	it.set_value('cell', 40)!
	it.set_value('tile', 3)!
	it.set_value('mode', 1)!
	h.step(mut it, 0)!
	it.set_value('col', 12)!
	it.set_value('mode', 2)!
	h.step(mut it, 0)!
	for k in 0 .. 40 {
		assert it.element('rt_map', k)! < 5
	}
	assert steps == 70
}
