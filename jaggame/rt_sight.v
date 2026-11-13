module jaggame

import math
import jagkit { idx, imm, lbl }

// Line of sight, vision cones, direction and hearing.
//
// Angles are `u8`, 256 to the full turn: 0 is right (+x), 64 down (+y on the
// screen), 128 left, 192 up. A number past 255 wraps, which is what an angle
// should do.
//
// `can_see(from, facing, to, range, half_angle)` is three tests, cheapest
// first:
//
//  1. inside range: the distance is at most `range` pixels (at most 255);
//  2. inside the cone: the angle between `facing` and the direction to the
//     target is at most `half_angle` (0..64, 64 being half a turn each way),
//     done with a dot product and a table of sines, no division;
//  3. nothing in the way: no wall on the line, found by `rt_line_clear`, a
//     routine in machine code that looks at the tile under every 8th pixel
//     of the line.
//
// Walls block sight. A cover block (the flag `flag_cover`) blocks it only
// for a target that is `crouched`: a standing figure is seen over it.
// The tile of the start and of the end are not looked at.

// sine_table is the sine of every angle, scaled to -127..127.
pub fn sine_table() []int {
	mut t := []int{}
	for a in 0 .. 256 {
		t << int(math.round(math.sin(f64(a) * 2.0 * math.pi / 256.0) * 127.0))
	}
	return t
}

// atan_table is the angle of the ratio r/64 for r = 0..64, in 1/256 turns:
// the arctangent, 0..32.
pub fn atan_table() []int {
	mut t := []int{}
	for r in 0 .. 65 {
		t << int(math.round(math.atan(f64(r) / 64.0) * 256.0 / (2.0 * math.pi)))
	}
	return t
}

// sight_step is the distance, in pixels, between the places on a line that
// are looked at.
const sight_step = 8

// sight_limit is the longest line, along either axis, that is looked at; a
// longer one is blocked.
const sight_limit = 255

// angle_right, angle_down, angle_left and angle_up are the four directions
// as angles.
pub const angle_right = 0
pub const angle_down = 64
pub const angle_left = 128
pub const angle_up = 192

// direction_of is the V version of `direction`: the angle of a vector.
pub fn direction_of(dx int, dy int) int {
	ax := if dx < 0 { -dx } else { dx }
	ay := if dy < 0 { -dy } else { dy }
	if ax == 0 && ay == 0 {
		return 0
	}
	atan := atan_table()
	mut a := 0
	if ax >= ay {
		a = atan[(ay * 64) / ax]
	} else {
		a = 64 - atan[(ax * 64) / ay]
	}
	if dx < 0 && dy >= 0 {
		a = 128 - a
	} else if dx < 0 && dy < 0 {
		a = 128 + a
	} else if dx >= 0 && dy < 0 {
		a = 256 - a
	}
	return a & 255
}

// cone_inside is the V version of the first two tests of `can_see`: whether
// a target at (dx, dy) from the eye is in range and in the cone.
pub fn cone_inside(dx int, dy int, facing int, range int, half_angle int) bool {
	return cone_inside_in(sine_table(), dx, dy, facing, range, half_angle)
}

// cone_inside_in is `cone_inside` with the table of sines given, for the
// callers that ask many times.
fn cone_inside_in(sine []int, dx int, dy int, facing int, range int, half_angle int) bool {
	if range > 255 {
		return false
	}
	ax := if dx < 0 { -dx } else { dx }
	ay := if dy < 0 { -dy } else { dy }
	if ax > range || ay > range {
		return false
	}
	dist2 := dx * dx + dy * dy
	if dist2 > range * range {
		return false
	}
	if dist2 == 0 {
		return true
	}
	dot := dx * sine[(facing + 64) & 255] + dy * sine[facing & 255]
	if dot < 0 {
		return false
	}
	c := sine[(64 + if half_angle > 64 { 64 } else { half_angle }) & 255]
	return dot * dot >= dist2 * c * c
}

// cone_cells lists the tiles, as offsets in tiles from the guard's own tile,
// that a cone reaches when everything is open: the tiles whose centre is
// inside the range and the cone seen from the centre of the guard's tile.
// The guard's own tile, (0, 0), comes first. It is the part of `can_see`
// that does not depend on the walls, worked out when the game is built, so
// that a game can light a cone by looking at the walls only.
pub fn cone_cells(facing int, range int, half_angle int) []Point {
	mut cells := [Point{0, 0}]
	reach := range / tile_size + 1
	for oy in -reach .. reach + 1 {
		for ox in -reach .. reach + 1 {
			if (ox != 0 || oy != 0)
				&& cone_inside(ox * tile_size, oy * tile_size, facing, range, half_angle) {
				cells << Point{ox, oy}
			}
		}
	}
	return cells
}

// SightVars is what the sight and hearing declare in the program.
@[heap]
struct SightVars {
mut:
	sine       Expr // i8 table
	atan       Expr // u8 table
	noise_left Expr // u8: frames the noise is still heard
	noise_x    Expr // i16
	noise_y    Expr // i16
	noise_r    Expr // u16
	line_clear Func
	can_see    Func
	direction  Func
	hears      Func
}

// use_sight declares the sight's tables and functions, once.
fn (mut g Game) use_sight() {
	if g.sight_ready {
		return
	}
	g.use_map()
	g.sight_ready = true
	g.sight = &SightVars{
		sine:       invalid('')
		atan:       invalid('')
		noise_left: g.p.u8('rt_noise_left')
		noise_x:    g.p.i16('rt_noise_x')
		noise_y:    g.p.i16('rt_noise_y')
		noise_r:    g.p.u16('rt_noise_r')
	}
	pos := Param{'x0', .i32}
	g.sight.line_clear = g.p.func('rt_line_clear', [pos, Param{'y0', .i32},
		Param{'x1', .i32}, Param{'y1', .i32}, Param{'low', .bool}], .bool)
	g.sight.can_see = g.p.func('rt_can_see', [Param{'fx', .i32},
		Param{'fy', .i32}, Param{'facing', .u8}, Param{'tx', .i32},
		Param{'ty', .i32}, Param{'range', .u8}, Param{'half', .u8},
		Param{'low', .bool}], .bool)
	g.sight.direction = g.p.func('rt_direction', [Param{'dx', .i32},
		Param{'dy', .i32}], .u8)
	g.sight.hears = g.p.func('rt_hears', [Param{'x', .i32}, Param{'y', .i32}], .bool)
}

// can_see is true when an eye at (from_x, from_y) that faces `facing` (an
// angle) sees the point (to_x, to_y): it is at most `range` pixels away (at
// most 255), inside the cone of `half_angle` (0..64) either side of the
// facing, and no wall is on the line between. A cover block does not block
// it: this is the view of a standing target. The positions are world
// pixels as `i32` or narrower (a `fix` needs `as_(.i32)`).
pub fn (mut g Game) can_see(from_x Val, from_y Val, facing Val, to_x Val, to_y Val, range Val, half_angle Val) Expr {
	g.use_sight()
	return g.sight.can_see.call(from_x, from_y, facing, to_x, to_y, range, half_angle, false)
}

// can_see_crouched is `can_see` for a target that is crouching: a cover
// block on the line hides it as a wall does.
pub fn (mut g Game) can_see_crouched(from_x Val, from_y Val, facing Val, to_x Val, to_y Val, range Val, half_angle Val) Expr {
	g.use_sight()
	return g.sight.can_see.call(from_x, from_y, facing, to_x, to_y, range, half_angle, true)
}

// line_clear is true when no wall is on the line from one world position
// to another (the last argument says whether a cover block counts as a wall:
// true for a crouching target). It is the third test of `can_see` on its own:
// the line is looked at every 8 pixels, the places at the two ends are not
// looked at, and a line longer than 255 pixels along an axis is blocked.
pub fn (mut g Game) line_clear(from_x Val, from_y Val, to_x Val, to_y Val, crouched Val) Expr {
	g.use_sight()
	return g.sight.line_clear.call(from_x, from_y, to_x, to_y, crouched)
}

// direction is the angle of the vector (dx, dy), a `u8` expression: the
// arctangent, from a table of 64 steps, within one 256th of a turn.
pub fn (mut g Game) direction(dx Val, dy Val) Expr {
	g.use_sight()
	return g.sight.direction.call(dx, dy)
}

// sine is the sine of an angle, -127..127 for -1..1, an `i8` expression.
pub fn (mut g Game) sine(angle Val) Expr {
	g.use_sight()
	return g.sight.sine.at(angle)
}

// cosine is the cosine of an angle, an `i8` expression.
pub fn (mut g Game) cosine(angle Val) Expr {
	g.use_sight()
	return g.sight.sine.at(lit(angle).as_(.u8).add(64))
}

// noise makes a noise at a world position (an `i32` or narrower, in
// pixels) that can be heard up to `radius` pixels away. It is heard by
// `hears` during this frame and the next, so that whoever runs before the
// maker of the noise hears it too; a later noise replaces it.
pub fn (mut g Game) noise(mut c Code, x Val, y Val, radius Val) {
	g.use_sight()
	c.set(g.sight.noise_x, lit(x).as_(.i16))
	c.set(g.sight.noise_y, lit(y).as_(.i16))
	c.set(g.sight.noise_r, lit(radius).as_(.u16))
	c.set(g.sight.noise_left, 2)
}

// hears is true when a noise is being heard at a world position: one was
// made this frame or last, within its radius (a circle, walls do not stop
// it), as a `bool` expression.
pub fn (mut g Game) hears(x Val, y Val) Expr {
	g.use_sight()
	return g.sight.hears.call(x, y)
}

// noise_x is where the noise being heard was made (`i16`).
pub fn (mut g Game) noise_x() Expr {
	g.use_sight()
	return g.sight.noise_x
}

// noise_y is where the noise being heard was made (`i16`).
pub fn (mut g Game) noise_y() Expr {
	g.use_sight()
	return g.sight.noise_y
}

// tile_cell is the tile number at a cell of the loaded room (row * width +
// column), an element of the map, as a `u8` expression and a destination for
// nothing: use `set_tile` to change a tile.
pub fn (mut g Game) tile_cell(cell Val) Expr {
	g.use_map()
	return g.tv.map.at(cell)
}

// define_sight writes the sight's and the hearing's functions.
fn (mut g Game) define_sight() {
	s := g.sight
	sine := g.p.table_i8('rt_sine', sine_table())
	atan := g.p.table_u8('rt_atan', atan_table())
	g.sight.sine = sine
	g.sight.atan = atan

	// Which tiles block sight, for a standing and for a crouching target.
	flags := g.flag_table()
	g.p.table_u8('rt_sight_stand', flags.map(if it & flag_solid != 0 && it & flag_cover == 0 {
		1
	} else {
		0
	}))
	g.p.table_u8('rt_sight_low', flags.map(if it & flag_solid != 0 { 1 } else { 0 }))

	line_clear := s.line_clear
	mut c := g.p.define(line_clear)
	c.native_ret(fn [line_clear] (mut m jagkit.M68k) {
		emit_line_clear(mut m, line_clear)
	}, fn [line_clear] (mut it Interpreter) ! {
		run_line_clear(mut it, line_clear)!
	})

	can_see := s.can_see
	c = g.p.define(can_see)
	dx := c.local_i32('dx')
	dy := c.local_i32('dy')
	dist2 := c.local_i32('dist2')
	dot := c.local_i32('dot')
	reach := c.local_i32('reach')
	cone := c.local_i32('cone')
	c.set(reach, can_see.arg('range').as_(.i32))
	c.set(dx, can_see.arg('tx').sub(can_see.arg('fx')))
	c.set(dy, can_see.arg('ty').sub(can_see.arg('fy')))

	c.if_(dx.abs().gt(reach).either(dy.abs().gt(reach)))
	c.ret(false)
	c.end() // too far along an axis

	c.set(dist2, dx.mul(dx).add(dy.mul(dy)))

	c.if_(dist2.gt(reach.mul(reach)))
	c.ret(false)
	c.end() // too far

	c.if_(dist2.ne(0))
	c.set(dot,
		dx.mul(sine.at(can_see.arg('facing').add(64)).as_(.i32)).add(dy.mul(sine.at(can_see.arg('facing')).as_(.i32))))

	c.if_(dot.lt(0))
	c.ret(false)
	c.end() // behind the eye

	c.set(cone, sine.at(can_see.arg('half').min(64).add(64)).as_(.i32))

	c.if_(dot.mul(dot).lt(dist2.mul(cone.mul(cone))))
	c.ret(false)
	c.end() // outside the cone
	c.end() // not the same place
	c.ret(line_clear.call(can_see.arg('fx'), can_see.arg('fy'), can_see.arg('tx'),
		can_see.arg('ty'), can_see.arg('low')))

	direction := s.direction
	c = g.p.define(direction)
	ddx := direction.arg('dx')
	ddy := direction.arg('dy')
	ax := c.local_i32('ax')
	ay := c.local_i32('ay')
	a := c.local_i32('a')
	c.set(ax, ddx.abs())
	c.set(ay, ddy.abs())

	c.if_(ax.eq(0).both(ay.eq(0)))
	c.ret(0)
	c.end() // no direction

	c.if_(ax.ge(ay))
	c.set(a, atan.at(ay.shl(6).div(ax)).as_(.i32))
	c.else_()
	c.set(a, atan.at(ax.shl(6).div(ay)).as_(.i32).neg().add(64))
	c.end() // which axis is longer

	c.if_(ddx.lt(0).both(ddy.ge(0)))
	c.set(a, a.neg().add(128))
	c.else_if(ddx.lt(0).both(ddy.lt(0)))
	c.set(a, a.add(128))
	c.else_if(ddx.ge(0).both(ddy.lt(0)))
	c.set(a, a.neg())
	c.end() // which quarter
	c.ret(a.and(255).as_(.u8))

	hears := s.hears
	c = g.p.define(hears)
	hx := c.local_i32('hx')
	hy := c.local_i32('hy')
	r := c.local_i32('r')

	c.if_(s.noise_left.eq(0))
	c.ret(false)
	c.end() // silence

	c.set(hx, hears.arg('x').sub(s.noise_x.as_(.i32)))
	c.set(hy, hears.arg('y').sub(s.noise_y.as_(.i32)))
	c.set(r, s.noise_r.as_(.i32))
	c.ret(hx.mul(hx).add(hy.mul(hy)).le(r.mul(r)))
}

// emit_line_clear writes the machine code of `rt_line_clear`: whether no
// wall is on the line from (x0, y0) to (x1, y1). The line is cut into
// steps of `sight_step` pixels along its longer axis, and the tile under
// each place between the two ends (not at them) is looked up in the table of
// what blocks sight. A line longer than `sight_limit` along an axis is
// blocked; one with fewer than two steps is clear. The result, 1 or 0, is
// left in d0.
//
// The positions are kept as 16.16 numbers, the step as a number of 128ths
// of a pixel (from a division of at most 16 bits), so that the pixel is the
// high word, and the tile is that word shifted by 4. A position outside
// the room is a word that is not below the room's width or height.
fn emit_line_clear(mut m jagkit.M68k, f Func) {
	clear := m.unique('rt.sight_clear')
	blocked := m.unique('rt.sight_blocked')
	done := m.unique('rt.sight_done')
	again := m.unique('rt.sight_again')
	pos_x := m.unique('rt.sight_posx')
	pos_y := m.unique('rt.sight_posy')
	longer := m.unique('rt.sight_longer')
	up_x := m.unique('rt.sight_upx')
	up_y := m.unique('rt.sight_upy')
	low := m.unique('rt.sight_low')
	table := m.unique('rt.sight_table')
	n := f.name
	m.move(.l, lbl('${n}.x0'), d0)
	m.move(.l, lbl('${n}.y0'), d1)
	m.move(.l, lbl('${n}.x1'), d2)
	m.sub(.l, d0, d2) // dx
	m.move(.l, lbl('${n}.y1'), d3)
	m.sub(.l, d1, d3) // dy
	m.move(.l, d2, d4)
	m.b(.pl, pos_x)
	m.neg(.l, d4)
	m.label(pos_x)
	m.move(.l, d3, d5)
	m.b(.pl, pos_y)
	m.neg(.l, d5)
	m.label(pos_y)
	m.cmp(.l, imm(sight_limit), d4)
	m.b(.gt, blocked)
	m.cmp(.l, imm(sight_limit), d5)
	m.b(.gt, blocked)

	// The number of steps, in d6.
	m.move(.l, d4, d6)
	m.cmp(.l, d6, d5)
	m.b(.le, longer)
	m.move(.l, d5, d6)
	m.label(longer)
	m.add(.l, imm(sight_step - 1), d6)
	m.lsr(.l, imm(3), d6)
	m.cmp(.l, imm(2), d6)
	m.b(.lt, clear)

	// The steps, in 128ths of a pixel and then as 16.16 numbers.
	m.lsl(.l, imm(7), d4)
	m.divu(d6, d4)
	m.and(.l, imm(0xffff), d4)
	m.tst(.l, d2)
	m.b(.pl, up_x)
	m.neg(.l, d4)
	m.label(up_x)
	m.lsl(.l, imm(8), d4)
	m.lsl(.l, imm(1), d4)
	m.lsl(.l, imm(7), d5)
	m.divu(d6, d5)
	m.and(.l, imm(0xffff), d5)
	m.tst(.l, d3)
	m.b(.pl, up_y)
	m.neg(.l, d5)
	m.label(up_y)
	m.lsl(.l, imm(8), d5)
	m.lsl(.l, imm(1), d5)

	// Where it starts, and which table to look in.
	m.swap(d0)
	m.clr(.w, d0)
	m.swap(d1)
	m.clr(.w, d1)
	m.lea(lbl('rt_map'), jagkit.a0)
	m.lea(lbl('rt_sight_stand'), jagkit.a1)
	m.tst(.b, lbl('${n}.low'))
	m.b(.eq, low)
	m.lea(lbl('rt_sight_low'), jagkit.a1)
	m.label(low)
	m.sub(.l, imm(2), d6)
	m.label(again)
	m.add(.l, d4, d0)
	m.add(.l, d5, d1)
	m.move(.l, d0, d2)
	m.swap(d2)
	m.lsr(.w, imm(4), d2)
	m.move(.l, d1, d3)
	m.swap(d3)
	m.lsr(.w, imm(4), d3)
	m.cmp(.w, lbl('rt_room_w'), d2)
	m.b(.cc, blocked)
	m.cmp(.w, lbl('rt_room_h'), d3)
	m.b(.cc, blocked)
	m.mulu(lbl('rt_room_w'), d3)
	m.add(.w, d2, d3)
	m.moveq(0, d2)
	m.move(.b, idx(0, jagkit.a0, d3), d2)
	m.move(.b, idx(0, jagkit.a1, d2), d2)
	m.b(.ne, blocked)
	m.dbra(d6, again)
	m.label(clear)
	m.label(table)
	m.moveq(1, d0)
	m.bra(done)
	m.label(blocked)
	m.moveq(0, d0)
	m.label(done)
}

// run_line_clear is what the interpreter does for `rt_line_clear`.
fn run_line_clear(mut it Interpreter, f Func) ! {
	x0 := it.get_label('${f.name}.x0', 0)!
	y0 := it.get_label('${f.name}.y0', 0)!
	dx := it.get_label('${f.name}.x1', 0)! - x0
	dy := it.get_label('${f.name}.y1', 0)! - y0
	low := it.get_label('${f.name}.low', 0)! != 0
	w := it.get_label('rt_room_w', 0)!
	h := it.get_label('rt_room_h', 0)!
	adx := if dx < 0 { -dx } else { dx }
	ady := if dy < 0 { -dy } else { dy }
	it.result = 0
	if adx > sight_limit || ady > sight_limit {
		return
	}
	longest := if adx > ady { adx } else { ady }
	steps := (longest + sight_step - 1) >> 3
	if steps < 2 {
		it.result = 1
		return
	}
	mut ix := (adx * 128) / steps
	mut iy := (ady * 128) / steps
	if dx < 0 {
		ix = -ix
	}
	if dy < 0 {
		iy = -iy
	}
	mut x := x0 * 65536
	mut y := y0 * 65536
	table := if low { 'rt_sight_low' } else { 'rt_sight_stand' }
	for _ in 1 .. steps {
		x += ix * 512
		y += iy * 512
		col := ((x >> 16) & 0xffff) >> 4
		row := ((y >> 16) & 0xffff) >> 4
		if col >= w || row >= h {
			return
		}
		tile := it.get_label('rt_map', int(row * w + col))!
		if it.get_label(table, int(tile))! != 0 {
			return
		}
	}
	it.result = 1
}

// sight_blocks is whether a tile blocks sight for a standing or a crouching
// target, by its flags.
fn sight_blocks(flags int, crouched bool) bool {
	return flags & flag_solid != 0 && (crouched || flags & flag_cover == 0)
}

// walk_clear is `rt_line_clear` in V over a map that is known when the game
// is built: whether no tile that `blocks` says blocks is on the line from
// (x0, y0) to (x1, y1), the world pixels, looked at every 8th pixel. It does
// the same arithmetic as the machine code and the interpreter's version.
fn walk_clear(x0 int, y0 int, x1 int, y1 int, width int, height int, blocks fn (col int, row int) bool) bool {
	dx := x1 - x0
	dy := y1 - y0
	adx := if dx < 0 { -dx } else { dx }
	ady := if dy < 0 { -dy } else { dy }
	if adx > sight_limit || ady > sight_limit {
		return false
	}
	longest := if adx > ady { adx } else { ady }
	steps := (longest + sight_step - 1) / 8
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
	mut x := x0 * 65536
	mut y := y0 * 65536
	for _ in 1 .. steps {
		x += ix * 512
		y += iy * 512
		col := ((x >> 16) & 0xffff) >> 4
		row := ((y >> 16) & 0xffff) >> 4
		if col >= width || row >= height || blocks(col, row) {
			return false
		}
	}
	return true
}

// view_cells is what a guard standing in the middle of tile (tile_x, tile_y)
// of a room, facing `facing` (an angle) sees, as the tiles it is on top of or
// that `can_see` from the middle of the tile to the middle of that tile says
// are in view: inside `range` pixels and the cone of `half_angle`, and
// no wall on the line. Tiles that are themselves walls are not in the list
// (a cover block counts as a wall; `crouched` makes cover hide what is
// behind it, as `can_see_crouched` does). The guard's own tile is first.
//
// It is worked out when the game is built, so that showing a cone costs a
// table look-up and not a walk for every tile: the game keeps the tables
// (one list for each tile and facing it can have) and changes the floor's
// colour on the tiles of the list. `can_see` in the program gives the same
// answer for every tile of the list and for none outside it (a test checks
// both).
pub fn (mut g Game) view_cells(room Room, tile_x int, tile_y int, facing int, range int, half_angle int, crouched bool) []Point {
	g.parse_rooms()
	if room.index < 0 || room.index >= g.rooms.len {
		return []Point{}
	}
	r := g.rooms[room.index]
	flags := g.flag_table()
	tiles := r.tiles.clone()
	width := r.width
	height := r.height
	blocks := fn [tiles, flags, width, crouched] (col int, row int) bool {
		return sight_blocks(flags[tiles[row * width + col]], crouched)
	}
	from_x := tile_x * tile_size + tile_size / 2
	from_y := tile_y * tile_size + tile_size / 2
	mut seen := []Point{}
	for c in cone_cells(facing, range, half_angle) {
		x := tile_x + c.x
		y := tile_y + c.y
		if x < 0 || y < 0 || x >= width || y >= height {
			continue
		}
		if blocks(x, y) || sight_blocks(flags[tiles[y * width + x]], true) {
			continue
		}
		if (c.x != 0 || c.y != 0)
			&& !walk_clear(from_x, from_y, x * tile_size + tile_size / 2, y * tile_size + tile_size / 2, width, height, blocks) {
			continue
		}
		seen << Point{x, y}
	}
	return seen
}
