module jaggame

import os
import rand
import jaggame.emulated

// Collision: tile flags by position, `move_and_slide` against the solid
// tiles (checked on its own, as a property of random moves, and against the
// machine), boxes against boxes.

fn workdir(name string) string {
	dir := os.join_path(os.temp_dir(), 'jaggame_${os.getpid()}_${name}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn tiles_png(dir string) string {
	mut pic := new_canvas(80, 16)
	pic.fill(0, 0, 16, 16, 30, 60, 90)
	pic.fill(16, 0, 16, 16, 200, 60, 60)
	pic.fill(32, 0, 16, 16, 240, 220, 40)
	pic.fill(48, 0, 16, 16, 40, 200, 90)
	pic.fill(64, 0, 16, 16, 160, 60, 200)
	path := os.join_path(dir, 'tiles.png')
	pic.save(path) or { panic(err) }
	return path
}

// the room of the tests: a 12 by 8 room with a thin wall, a pillar, a chip,
// an exit, a cover tile and a gap in the east wall.
const arena = '
############
#..........#
#.#####....#
#..........#
#.....#.o..#
#..c...#..xI
#..........#
############
'

// Wall tiles are 1, the chip 2, the exit 3 and the cover 1 with flag cover
// (so it is solid too): `c` is a solid cover block.
fn arena_game(dir string) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(tiles_png(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`c`, 1, flag_solid)
	g.legend_tile(`o`, 2, flag_item)
	g.legend_tile(`x`, 3, flag_exit)
	g.legend_tile(`I`, 4, flag_user1)
	g.room('arena', arena)
	return g
}

// run_game is the arena with a mover: `px`, `py` is its position in pixels,
// `dx`, `dy` what it moves this frame (set from outside), box 10x10 offset
// by 3.
fn move_game(dir string) &Game {
	mut g := arena_game(dir)
	px := g.p.fix('px', 40.0)
	py := g.p.fix('py', 52.0)
	dx := g.p.fix('dx')
	dy := g.p.fix('dy')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.if_(g.loading.invert())
	g.move_and_slide(mut c, px, py, Hitbox{3, 3, 10, 10}, dx, dy)
	c.end()
	return g
}

// loaded runs an interpreter until the room is loaded.
fn loaded(mut g Game) !&Interpreter {
	mut it := g.interpreter(.ntsc)!
	for _ in 0 .. 40 {
		g.step(mut it, 0)!
	}
	assert it.value('loading')! == 0
	return it
}

fn test_flags_are_asked_by_position() {
	dir := workdir('flags')
	mut g := arena_game(dir)
	q := g.p.u8('q')
	tile := g.p.u8('tile')
	solid := g.p.bool('solid')
	seen := g.p.u8('seen')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.set(tile, g.tile_at(q.as_(.i32).mul(8), 24))
	c.set(seen, g.flags_at(q.as_(.i32).mul(8), 24))
	c.set(solid, g.solid_at(q.as_(.i32).mul(8), 24))
	mut it := loaded(mut g)!
	probe := fn [mut it, g] (x int, y int) (int, int, bool) {
		// the update asks about (q * 8, 24); use q as x/8 and move y by hand
		_ = y
		it.set_value('q', i64(x / 8)) or { panic(err) }
		g.step(mut it, 0) or { panic(err) }
		return int(it.value('tile') or { panic(err) }), int(it.value('q') or { panic(err) }), it.value('solid') or {
			panic(err)
		} != 0
	}
	// Row 1 (y 16..31) of the arena is `#..........#`.
	tile0, _, solid0 := probe(0, 24)
	assert tile0 == 1 && solid0, 'the west wall'
	tile1, _, solid1 := probe(16, 24)
	assert tile1 == 0 && !solid1, 'floor'
	_, _, solid_outside := probe(8 * 12 * 2, 24)
	assert solid_outside, 'beyond the east edge is solid'
}

fn test_the_queries_match_the_text_everywhere() {
	dir := workdir('queries')
	mut g := arena_game(dir)
	x := g.p.i16('x')
	y := g.p.i16('y')
	tile := g.p.u8('tile')
	flags := g.p.u8('flags')
	solid := g.p.bool('solid')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.set(tile, g.tile_at(x, y))
	c.set(flags, g.flags_at(x, y))
	c.set(solid, g.solid_at(x, y))
	mut it := loaded(mut g)!
	rows := room_rows(arena)
	for ty in -2 .. 11 {
		for tx in -2 .. 15 {
			for off in [0, 15] {
				it.set_value('x', i64(tx * 16 + off))!
				it.set_value('y', i64(ty * 16 + 15 - off))!
				g.step(mut it, 0)!
				inside := tx >= 0 && ty >= 0 && tx < 12 && ty < 8
				ch := if inside { rows[ty].runes()[tx] } else { `#` }
				want_tile := if !inside {
					tile_none
				} else {
					match ch {
						`#`, `c` { 1 }
						`o` { 2 }
						`x` { 3 }
						`I` { 4 }
						else { 0 }
					}
				}
				want_flags := if !inside {
					flag_solid
				} else {
					match ch {
						`#`, `c` { flag_solid }
						`o` { flag_item }
						`x` { flag_exit }
						`I` { flag_user1 }
						else { 0 }
					}
				}
				assert it.value('tile')! == want_tile, 'tile at ${tx},${ty}'
				assert it.value('flags')! == want_flags, 'flags at ${tx},${ty}'
				assert (it.value('solid')! != 0) == (want_flags == flag_solid), 'solid at ${tx},${ty}'
			}
		}
	}
}

// moved runs one move_and_slide in the interpreter from a position.
fn moved(mut g Game, mut it Interpreter, x f64, y f64, dx f64, dy f64) (f64, f64) {
	it.set_value('px', i64(x * 65536)) or { panic(err) }
	it.set_value('py', i64(y * 65536)) or { panic(err) }
	it.set_value('dx', i64(dx * 65536)) or { panic(err) }
	it.set_value('dy', i64(dy * 65536)) or { panic(err) }
	g.step(mut it, 0) or { panic(err) }
	return f64(it.value('px') or { panic(err) }) / 65536, f64(it.value('py') or { panic(err) }) / 65536
}

fn test_a_box_stops_flush_against_a_wall_and_slides_along_it() {
	dir := workdir('slide')
	mut g := move_game(dir)
	mut it := loaded(mut g)!
	// The box is 10x10 at an offset of 3: with the position at (x, y) it covers
	// x+3 .. x+12. The east wall of the room is the column of tile 11: x = 176.
	// A box stopped by it has its right edge at 175: x + 12 = 175, x = 163.
	x, y := moved(mut g, mut it, 158, 48, 8, 0)
	assert x == 163 && y == 48, 'stopped flush against the east wall: ${x}, ${y}'
	assert it.value('rt_slide_hit')! == 1
	// Pushing diagonally down and right slides down the wall.
	x2, y2 := moved(mut g, mut it, 160, 48, 8, 5)
	assert x2 == 163 && y2 == 53, 'slides: ${x2}, ${y2}'
	// Free movement keeps the fraction.
	x3, y3 := moved(mut g, mut it, 40.25, 50.5, 1.5, -0.25)
	assert x3 == 41.75 && y3 == 50.25, 'free: ${x3}, ${y3}'
	assert it.value('rt_slide_hit')! == 0
	// Along y: the top wall is row 0, so a box stopped by it has its top at 16: y + 3 = 16.
	x4, y4 := moved(mut g, mut it, 40, 20, 0, -9)
	assert x4 == 40 && y4 == 13, 'stopped by the top: ${x4}, ${y4}'
	assert it.value('rt_slide_hit')! == 2
	// The thin wall of row 2 (columns 2..6): from below, the top of the
	// box stops at the bottom of tile row 2, y + 3 = 48.
	x5, y5 := moved(mut g, mut it, 60, 52, 0, -10)
	assert x5 == 60 && y5 == 45, 'stopped by the thin wall: ${x5}, ${y5}'
	// A fraction is dropped when a wall stops the box.
	x6, y6 := moved(mut g, mut it, 158.5, 48.75, 8.5, 0)
	assert x6 == 163 && y6 == 48.75, 'only the blocked axis changes: ${x6}, ${y6}'
}

fn test_the_largest_step_cannot_tunnel_through_a_wall_one_tile_thick() {
	dir := workdir('tunnel')
	mut g := move_game(dir)
	mut it := loaded(mut g)!
	// The thin wall is tile row 2, columns 2..6: y 32..47. A box above it
	// (top at y+3) moving down by 16 or more from every position that is free.
	for startx in [45.0, 52.5, 60.0, 90.0] {
		for starty in [17.0, 18.0, 20.0, 29.0, 30.5] {
			// bottom edge = y + 12; it must be above row 2 (< 32) to start: y < 20
			if starty + 12 >= 32 {
				continue
			}
			for dy in [1.0, 8.0, 15.5, 16.0, 17.0, 40.0, 200.0] {
				_, y := moved(mut g, mut it, startx, starty, 0, dy)
				assert y + 12 < 32, 'tunnelled from y ${starty} by ${dy}: ended at ${y}'
			}
		}
	}
	// A step larger than a tile is cut to one tile.
	_, y := moved(mut g, mut it, 100.0, 17.0, 0, 200.0)
	assert y <= 17 + 16, 'cut to one tile: ${y}'
}

// overlaps_solid tells whether the 10x10 box of a position covers a solid
// tile of the arena.
fn overlaps_solid(x f64, y f64) bool {
	rows := room_rows(arena)
	left := int(x) + 3
	top := int(y) + 3
	for yy in [top, top + 9] {
		for xx in [left, left + 9] {
			tx := if xx < 0 { -1 } else { xx / 16 }
			ty := if yy < 0 { -1 } else { yy / 16 }
			if tx < 0 || ty < 0 || tx >= 12 || ty >= 8 {
				return true
			}
			if rows[ty].runes()[tx] in [`#`, `c`] {
				return true
			}
		}
	}
	return false
}

fn test_random_moves_never_enter_a_wall_and_never_stick_when_free() {
	dir := workdir('random')
	mut g := move_game(dir)
	mut it := loaded(mut g)!
	rand.seed([u32(7), 11])
	mut x := 40.0
	mut y := 52.0
	mut walls := 0
	for _ in 0 .. 4000 {
		dx := f64(rand.int_in_range(-16 * 4, 16 * 4 + 1) or { 0 }) / 4
		dy := f64(rand.int_in_range(-16 * 4, 16 * 4 + 1) or { 0 }) / 4
		nx, ny := moved(mut g, mut it, x, y, dx, dy)
		assert !overlaps_solid(nx, ny), 'inside a wall at ${nx}, ${ny} after moving ${dx}, ${dy} from ${x}, ${y}'
		hit := it.value('rt_slide_hit')!
		if hit == 0 {
			assert nx == x + dx && ny == y + dy, 'free but not moved: ${x}+${dx}, ${y}+${dy} gave ${nx}, ${ny}'
		} else {
			walls++
		}
		x = nx
		y = ny
		// Keep the mover moving about: when it is in a corner, put it back.
		if (x - 40) * (x - 40) + (y - 52) * (y - 52) > 90 * 90 {
			x = 40
			y = 52
		}
	}
	assert walls > 200, 'the moves reached walls often enough to mean something: ${walls}'
}

fn test_the_machine_moves_a_box_as_the_interpreter_does() {
	dir := workdir('machine')
	mut g := move_game(dir)
	img := g.build() or { panic(err) }
	mut h := move_game(dir)
	mut it := loaded(mut h)!
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(20)
	rand.seed([u32(3), 5])
	for n in 0 .. 150 {
		dx := rand.int_in_range(-20 * 65536, 20 * 65536) or { 0 }
		dy := rand.int_in_range(-20 * 65536, 20 * 65536) or { 0 }
		it.set_value('dx', dx)!
		it.set_value('dy', dy)!
		write_long(mut p, img.symbols['dx'], dx)
		write_long(mut p, img.symbols['dy'], dy)
		p.frames(1)
		h.step(mut it, 0)!
		got_x := int(img.value(p.m.ram, 'px')!)
		got_y := int(img.value(p.m.ram, 'py')!)
		assert got_x == int(it.value('px')!) && got_y == int(it.value('py')!), 'step ${n}: machine ${got_x}, ${got_y}; interpreter ${it.value('px')!}, ${it.value('py')!}'
	}
	assert img.value(p.m.ram, 'missed_frames')! == 0
}

fn write_long(mut p emulated.Player, at u32, value i64) {
	for i in 0 .. 4 {
		p.m.ram[at + u32(i)] = u8(value >> u32(24 - 8 * i))
	}
}

fn test_boxes_overlap_when_they_share_a_pixel() {
	mut p := new_program()
	ax := p.i16('ax')
	ay := p.i16('ay')
	hit := p.bool('hit')
	mut c := p.define(p.func('main', [], .void))
	c.set(hit, overlap(Rect{ax, ay, 10, 10}, Rect{lit(20).as_(.i16), lit(20).as_(.i16), 8, 8}))
	mut it := p.interpreter()!
	for a in [[0, 0, 0], [10, 10, 0], [11, 11, 1], [10, 20, 0],
		[19, 19, 1], [20, 20, 1], [27, 27, 1], [28, 28, 0], [12, 27, 1],
		[12, 28, 0], [-10, 20, 0], [11, 20, 1]] {
		it.set_value('ax', a[0])!
		it.set_value('ay', a[1])!
		it.run('main')!
		assert it.value('hit')! == a[2], 'box at ${a[0]}, ${a[1]}'
	}
}

// slides_game does `count` moves in each frame, from the same place, 1.5
// right and 0.5 down in the open.
fn slides_game(dir string, count int) &Game {
	mut g := arena_game(dir)
	px := g.p.fix('px')
	py := g.p.fix('py')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.set(px, 40.0)
	c.set(py, 52.0)
	c.repeat(count)
	g.move_and_slide(mut c, px, py, Hitbox{3, 3, 10, 10}, 1.5, 0.5)
	c.end()
	return g
}

fn test_what_a_move_costs() {
	dir := workdir('cost')
	mut cycles := []int{}
	for count in [0, 20] {
		mut g := slides_game(dir, count)
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, false) or { panic(err) }
		p.frames(40)
		cycles << p.busy_cycles(20)
	}
	each := (cycles[1] - cycles[0]) / 20
	println('move_and_slide: ${each} cycles a call in the open')
	assert each < 12000, 'a move costs ${each} cycles'
}

fn test_what_a_query_costs() {
	dir := workdir('querycost')
	mut cycles := []int{}
	for count in [0, 50] {
		mut g := arena_game(dir)
		hits := g.p.u16('hits')
		k := g.p.i16('k')
		mut c := g.define_init()
		g.load_room(mut c, Room{0, 'arena'})
		c = g.define_update()
		c.set(k, 0)
		c.repeat(count)
		c.set(hits, hits.add(g.flags_at(k, 40)))
		c.set(k, k.add(3))
		c.end()
		img := g.build() or { panic(err) }
		mut p := emulated.boot(img.bytes, false) or { panic(err) }
		p.frames(40)
		cycles << p.busy_cycles(20)
	}
	each := (cycles[1] - cycles[0]) / 50
	println('flags_at: ${each} cycles a call')
	assert each < 3000
}

fn test_the_machine_answers_the_queries_as_the_interpreter_does() {
	dir := workdir('machinequeries')
	mut g := arena_game(dir)
	x := g.p.i16('x')
	y := g.p.i16('y')
	tile := g.p.u8('tile')
	flags := g.p.u8('flags')
	solid := g.p.bool('solid')
	line := g.p.bool('line')
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'arena'})
	c = g.define_update()
	c.set(tile, g.tile_at(x, y))
	c.set(flags, g.flags_at(x, y))
	c.set(solid, g.solid_at(x, y))
	c.set(line, g.tv.col_solid.call(x.shr(4).as_(.i32), y.shr(4).as_(.i32),
		y.shr(4).as_(.i32).add(2)))
	img := g.build() or { panic(err) }
	mut h := arena_game(dir)
	x2 := h.p.i16('x')
	y2 := h.p.i16('y')
	tile2 := h.p.u8('tile')
	flags2 := h.p.u8('flags')
	solid2 := h.p.bool('solid')
	line2 := h.p.bool('line')
	c = h.define_init()
	h.load_room(mut c, Room{0, 'arena'})
	c = h.define_update()
	c.set(tile2, h.tile_at(x2, y2))
	c.set(flags2, h.flags_at(x2, y2))
	c.set(solid2, h.solid_at(x2, y2))
	c.set(line2, h.tv.col_solid.call(x2.shr(4).as_(.i32), y2.shr(4).as_(.i32),
		y2.shr(4).as_(.i32).add(2)))
	mut it := loaded(mut h)!
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(20)
	for ty in -2 .. 11 {
		for tx in -2 .. 15 {
			for off in [0, 15] {
				px := tx * 16 + off
				py := ty * 16 + 15 - off
				it.set_value('x', px)!
				it.set_value('y', py)!
				h.step(mut it, 0)!
				write_word(mut p, img.symbols['x'], px)
				write_word(mut p, img.symbols['y'], py)
				p.frames(1)
				for name in ['tile', 'flags', 'solid', 'line'] {
					assert img.value(p.m.ram, name)! == it.value(name)!, '${name} at ${px}, ${py}: machine ${img.value(p.m.ram,
						name)!}, interpreter ${it.value(name)!}'
				}
			}
		}
	}
}

fn write_word(mut p emulated.Player, at u32, value i64) {
	p.m.ram[at] = u8(value >> 8)
	p.m.ram[at + 1] = u8(value)
}
