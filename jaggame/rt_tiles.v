module jaggame

import jagkit { at, idx, imm, ind, lbl }

// The tile layer. A room is drawn once, when it is loaded, into a picture
// buffer in main memory, one byte a pixel (the game's palette), a line after
// a line, the whole room wide. Every frame the display list gets one object
// that shows a window of that picture: its data pointer picks the line and
// the 8-pixel phrase the camera is at, its position takes the 0..7 pixels
// that are left over. The layer is behind all sprites and the text.
//
// Loading a room takes more than a frame: a few dozen tiles are copied and
// drawn each frame (`tiles_per_frame`), the picture is blank meanwhile (no
// tile layer, no sprites, the text stays) and `loading` is true. It starts
// one frame late, so that the picture that is on its way to the screen is
// blank before the buffer changes.

// tile_buffer is where the room's picture is built.
const tile_buffer = u32(0x100000)

// tiles_per_frame is how many tiles of a room are copied and drawn in one
// frame while a room loads.
const tiles_per_frame = 48

// tile_queue_size is how many tile changes (`set_tile`) one frame can hold.
const tile_queue_size = 64

// TileVars is what the tile layer declares in the program: variables and
// functions, made by `use_map`.
@[heap]
struct TileVars {
mut:
	map          Expr // u8 array: the tile number of each cell of the loaded room
	room_w       Expr // i16: the room's width in tiles
	room_h       Expr
	map_on       Expr // bool: the picture is complete and shown
	wait         Expr // u8: 1 until the blank list has gone out
	next         Expr // u16: the next cell to copy and draw
	from         Expr // u16: the cells this frame draws, from and up to
	to           Expr
	cells        Expr // u16: the cells in the room
	first        Expr // u16: where the room's tiles start in the table of all rooms
	queue        Expr // u16 array: cells changed this frame
	queued       Expr // u8: how many
	lost         Expr // u16: changes that did not fit
	slide_x      Expr // fix: the position `move_and_slide` works on
	slide_y      Expr
	hit          Expr // u8: bit 0 stopped along x, bit 1 along y
	flags        Expr // u8 table: the flags of each tile
	tile_at      Func
	flags_at     Func
	load_room    Func
	load_step    Func
	set_tile     Func
	set_cell     Func
	follow       Func
	col_solid    Func
	row_solid    Func
	slide        Func
	marker       Func
	marker_count Func
}

// use_map declares the tile layer's variables and functions, once. They
// are only there in a game that uses a tile set.
fn (mut g Game) use_map() {
	if g.map_ready {
		return
	}
	g.map_ready = true
	g.tv = &TileVars{
		map:     invalid('')
		room_w:  invalid('')
		room_h:  invalid('')
		map_on:  invalid('')
		wait:    invalid('')
		next:    invalid('')
		from:    invalid('')
		to:      invalid('')
		cells:   invalid('')
		first:   invalid('')
		queue:   invalid('')
		queued:  invalid('')
		lost:    invalid('')
		slide_x: invalid('')
		slide_y: invalid('')
		hit:     invalid('')
		flags:   invalid('')
	}
	g.tv.map = g.p.array_u8('rt_map', max_room_tiles)
	g.tv.room_w = g.p.i16('rt_room_w')
	g.tv.room_h = g.p.i16('rt_room_h')
	g.tv.map_on = g.p.bool('rt_map_on')
	g.tv.wait = g.p.u8('rt_load_wait')
	g.tv.next = g.p.u16('rt_load_next')
	g.tv.from = g.p.u16('rt_load_from')
	g.tv.to = g.p.u16('rt_load_to')
	g.tv.cells = g.p.u16('rt_load_cells')
	g.tv.first = g.p.u16('rt_load_first')
	g.tv.queue = g.p.array_u16('rt_tile_queue', tile_queue_size)
	g.tv.queued = g.p.u8('rt_tile_count')
	g.tv.lost = g.p.u16('rt_tile_lost')
	g.tv.slide_x = g.p.fix('rt_slide_x')
	g.tv.slide_y = g.p.fix('rt_slide_y')
	g.tv.hit = g.p.u8('rt_slide_hit')
	xy := Param{'x', .i32}
	yy := Param{'y', .i32}
	g.tv.tile_at = g.p.func('rt_tile_at', [xy, yy], .u8)
	g.tv.flags_at = g.p.func('rt_flags_at', [xy, yy], .u8)
	g.tv.load_room = g.p.func('rt_load_room', [Param{'room', .u16}], .void)
	g.tv.load_step = g.p.func('rt_load_step', [], .void)
	g.tv.set_tile = g.p.func('rt_set_tile', [xy, yy, Param{'tile', .u8}], .void)
	g.tv.set_cell = g.p.func('rt_set_cell', [Param{'cell', .u16},
		Param{'tile', .u8}], .void)
	g.tv.follow = g.p.func('rt_follow', [xy, yy], .void)
	g.tv.col_solid = g.p.func('rt_col_solid', [Param{'col', .i32},
		Param{'r0', .i32}, Param{'r1', .i32}], .bool)
	g.tv.row_solid = g.p.func('rt_row_solid', [Param{'row', .i32},
		Param{'c0', .i32}, Param{'c1', .i32}], .bool)
	g.tv.slide = g.p.func('rt_slide', [Param{'ox', .i32}, Param{'oy', .i32},
		Param{'w', .i32}, Param{'h', .i32}, Param{'dx', .fix},
		Param{'dy', .fix}], .void)
	g.tv.marker = g.p.func('rt_marker', [Param{'name', .u8}, Param{'k', .u8},
		Param{'axis', .u8}], .i16)
	g.tv.marker_count = g.p.func('rt_marker_count', [Param{'name', .u8}], .u8)
}

// load_room starts loading a room (see `room`). The tile layer and the
// sprites are not drawn until it is done, `loading` is true meanwhile, and
// the game's update goes on running: leave the room alone while `loading`.
// The room's size (`room_width`, `room_height`) and its markers are right
// at once; `tile_at` and the tiles are not until the room is loaded.
pub fn (mut g Game) load_room(mut c Code, room Room) {
	if room.index < 0 || room.index >= g.rooms.len {
		g.problem('load_room: there is no room ${room.index}')
		return
	}
	g.use_map()
	c.call(g.tv.load_room, room.index)
}

// load_room_number is `load_room` for a room number that is not known when
// the game is built: an expression, from 0. A number past the last room
// loads the last one.
pub fn (mut g Game) load_room_number(mut c Code, number Val) {
	g.use_map()
	c.call(g.tv.load_room, number)
}

// set_tile puts a tile at a column and a row of the room (in tiles) and
// redraws it. Up to 64 changes can be drawn in one frame; more are counted
// in `rt_tile_lost` and not drawn. A place outside the room is ignored.
pub fn (mut g Game) set_tile(mut c Code, column Val, row Val, tile Val) {
	g.use_map()
	c.call(g.tv.set_tile, column, row, tile)
}

// set_cell is `set_tile` for a cell number: the tile at `cell` (row *
// room width + column) of the loaded room becomes `tile`, drawn this frame
// like `set_tile`. A cell outside the room is ignored.
pub fn (mut g Game) set_cell(mut c Code, cell Val, tile Val) {
	g.use_map()
	c.call(g.tv.set_cell, cell, tile)
}

// tile_at is the tile number at a world position in pixels, as a `u8`
// expression: `tile_none` (255) outside the room. The position is an `i32`
// or narrower; turn a `fix` into pixels with `as_(.i32)`.
pub fn (mut g Game) tile_at(x Val, y Val) Expr {
	g.use_map()
	return g.tv.tile_at.call(x, y)
}

// flags_at is the flags of the tile at a world position (the `flag_`
// constants, added together), as a `u8` expression; outside the room it is
// `flag_solid`.
pub fn (mut g Game) flags_at(x Val, y Val) Expr {
	g.use_map()
	return g.tv.flags_at.call(x, y)
}

// solid_at is true when the tile at a world position blocks movement.
pub fn (mut g Game) solid_at(x Val, y Val) Expr {
	return g.flags_at(x, y).and(flag_solid).ne(0)
}

// marker_index is the number of a marker name, or a recorded mistake.
fn (mut g Game) marker_index(name string) int {
	names := g.marker_names()
	for i, n in names {
		if n == name {
			return i
		}
	}
	if names.len == 0 {
		g.problem('there is no marker `${name}`; no marker has been declared (legend_marker)')
	} else {
		g.problem('there is no marker `${name}`; the markers are: ${names.join(', ')}')
	}
	return 0
}

// marker_count is how many places of the marker `name` the loaded room has,
// a `u8` expression.
pub fn (mut g Game) marker_count(name string) Expr {
	g.use_map()
	return g.tv.marker_count.call(g.marker_index(name))
}

// marker_x is the column, in tiles, of place number `k` (from 0) of the
// marker `name` in the loaded room, an `i16` expression; -1 if there is no
// such place. Multiply by 16 for pixels.
pub fn (mut g Game) marker_x(name string, k Val) Expr {
	g.use_map()
	return g.tv.marker.call(g.marker_index(name), k, 0)
}

// marker_y is the row of a marker's place, like `marker_x`.
pub fn (mut g Game) marker_y(name string, k Val) Expr {
	g.use_map()
	return g.tv.marker.call(g.marker_index(name), k, 1)
}

// camera_follow moves the camera so that the world position (x, y) is in
// the middle of the screen, as far as the room allows: the camera stops at
// the edges of the room, and a room smaller than the screen is centred.
// The position is in pixels, an `i32` or narrower.
pub fn (mut g Game) camera_follow(mut c Code, x Val, y Val) {
	g.use_map()
	c.call(g.tv.follow, x, y)
}

// define_map writes the functions of the tile layer: the rooms' data, loading,
// the queries and the camera.
fn (mut g Game) define_map() {
	g.parse_rooms()
	tv := g.tv
	grid := tv.map
	room_w := tv.room_w
	room_h := tv.room_h

	// The rooms: their tiles one after the other, and where each starts.
	mut all := []int{}
	mut first := []int{}
	mut cols := []int{}
	mut rows := []int{}
	for r in g.rooms {
		first << all.len
		cols << r.width
		rows << r.height
		for t in r.tiles {
			all << int(t)
		}
	}
	if all.len == 0 {
		all << 0
		first << 0
		cols << 1
		rows << 1
	}
	room_tiles := g.p.table_u8('rt_room_tiles', all)
	room_first := g.p.table_u16('rt_room_first', first)
	cols_table := g.p.table_u8('rt_room_cols', cols)
	rows_table := g.p.table_u8('rt_room_rows', rows)
	flags := g.p.table_u8('rt_tile_flags', g.flag_table())
	g.tv.flags = flags
	g.define_markers()

	// tile_at and flags_at are machine code.
	mut c := g.p.define(tv.tile_at)
	tile_at := tv.tile_at
	c.native_ret(fn [tile_at] (mut m jagkit.M68k) {
		emit_cell_at(mut m, tile_at, false)
	}, fn [tile_at] (mut it Interpreter) ! {
		run_cell_at(mut it, tile_at, false)!
	})
	c = g.p.define(tv.flags_at)
	flags_at := tv.flags_at
	c.native_ret(fn [flags_at] (mut m jagkit.M68k) {
		emit_cell_at(mut m, flags_at, true)
	}, fn [flags_at] (mut it Interpreter) ! {
		run_cell_at(mut it, flags_at, true)!
	})

	// load_room: the numbers are right at once, the tiles come a few a frame.
	c = g.p.define(tv.load_room)
	n := tv.load_room.arg('room')
	last := c.local_u16('last')
	c.set(last, n.min(g.rooms.len - 1))
	c.set(g.room_number, last.as_(.u8))
	c.set(room_w, cols_table.at(last).as_(.i16))
	c.set(room_h, rows_table.at(last).as_(.i16))
	c.set(g.room_width, room_w.shl(4))
	c.set(g.room_height, room_h.shl(4))
	c.set(tv.cells, room_w.as_(.u16).mul(room_h.as_(.u16)))
	c.set(tv.first, room_first.at(last))
	c.set(tv.next, 0)
	c.set(tv.from, 0)
	c.set(tv.to, 0)
	c.set(tv.map_on, false)
	c.set(tv.wait, 1)
	c.set(g.loading, true)

	// load_step runs at the end of every frame.
	c = g.p.define(tv.load_step)
	i := c.local_u16('i')
	c.set(tv.from, 0)
	c.set(tv.to, 0)

	c.if_(g.loading)
	c.if_(tv.wait.ne(0))
	c.set(tv.wait, 0) // the blank list is built before anything is drawn
	c.else_()
	c.set(tv.from, tv.next)
	c.set(tv.to, tv.next.add(tiles_per_frame).min(tv.cells))

	c.for_(i, tv.from, tv.to)
	c.set(grid.at(i), room_tiles.at(tv.first.add(i)))
	c.end() // for each tile
	c.set(tv.next, tv.to)

	c.if_(tv.next.ge(tv.cells))
	c.set(g.loading, false)
	c.set(tv.map_on, true)
	c.end() // done
	c.end() // not waiting
	c.end() // loading

	// set_tile and set_cell are machine code too: a game that lights a cone
	// changes a dozen tiles at once.
	c = g.p.define(tv.set_tile)
	set_tile := tv.set_tile
	c.native(fn [set_tile] (mut m jagkit.M68k) {
		emit_set_tile(mut m, set_tile, true)
	}, fn [set_tile] (mut it Interpreter) ! {
		run_set_tile(mut it, set_tile, true)!
	})
	c = g.p.define(tv.set_cell)
	set_cell := tv.set_cell
	c.native(fn [set_cell] (mut m jagkit.M68k) {
		emit_set_tile(mut m, set_cell, false)
	}, fn [set_cell] (mut it Interpreter) ! {
		run_set_tile(mut it, set_cell, false)!
	})

	g.define_follow(tv.follow)
	g.define_slide()
}

// define_follow writes `rt_follow`: put the camera on a position, within the room.
fn (mut g Game) define_follow(follow Func) {
	mut c := g.p.define(follow)
	x := follow.arg('x')
	y := follow.arg('y')

	c.if_(g.room_width.le(logical_width))
	c.set(g.camera_x, g.room_width.sub(logical_width).div(2))
	c.else_()
	c.set(g.camera_x,
		x.sub(logical_width / 2).max(0).min(g.room_width.as_(.i32).sub(logical_width)).as_(.i16))
	c.end()

	c.if_(g.room_height.le(logical_height))
	c.set(g.camera_y, g.room_height.sub(logical_height).div(2))
	c.else_()
	c.set(g.camera_y,
		y.sub(logical_height / 2).max(0).min(g.room_height.as_(.i32).sub(logical_height)).as_(.i16))
	c.end()
}

// emit_tile_routines writes the machine side of the tile layer: drawing the
// tiles a frame has to draw, and the display list object.
fn (g &Game) emit_tile_routines(mut m jagkit.M68k) {
	if !g.has_tileset {
		return
	}
	g.emit_render_tiles(mut m)
	g.emit_tile_object(mut m)
}

// emit_render_tiles writes `rt.render_tiles`: it draws the cells from
// `rt_load_from` up to `rt_load_to` (the slice of a room that is loading)
// and then the cells the game changed this frame (`rt_tile_queue`), each
// from the tile number in `rt_map`.
fn (g &Game) emit_render_tiles(mut m jagkit.M68k) {
	m.label('rt.render_tiles')
	m.push([d6, d7])
	m.moveq(0, d7)
	m.move(.w, lbl('rt_load_from'), d7)
	m.moveq(0, d6)
	m.move(.w, lbl('rt_load_to'), d6)
	m.label('rt.slice')
	m.cmp(.l, d6, d7)
	m.b(.cc, 'rt.slice_done') // from >= to
	m.move(.l, d7, d0)
	m.bsr('rt.draw_tile')
	m.add(.l, imm(1), d7)
	m.bra('rt.slice')
	m.label('rt.slice_done')
	m.moveq(0, d6)
	m.move(.b, lbl('rt_tile_count'), d6)
	m.moveq(0, d7)
	m.label('rt.queue')
	m.cmp(.l, d6, d7)
	m.b(.cc, 'rt.queue_done')
	m.lea(lbl('rt_tile_queue'), a0)
	m.move(.l, d7, d0)
	m.add(.l, d0, d0)
	m.moveq(0, d1)
	m.move(.w, idx(0, a0, d0), d1)
	m.move(.l, d1, d0)
	m.bsr('rt.draw_tile')
	m.add(.l, imm(1), d7)
	m.bra('rt.queue')
	m.label('rt.queue_done')
	m.pop([d6, d7])
	m.rts()

	// draw_tile: d0 is the cell. The 16 lines of the tile are 16 bytes each
	// in the tile set, and a line apart in the room's picture.
	m.label('rt.draw_tile')
	m.moveq(0, d1)
	m.move(.w, lbl('rt_room_w'), d1)
	m.move(.l, d0, d2)
	m.divu(d1, d2) // the row in the low word, the column in the high
	m.move(.l, d2, d3)
	m.swap(d3)
	m.and(.l, imm(0xffff), d3) // the column
	m.and(.l, imm(0xffff), d2) // the row
	m.move(.l, d1, d4)
	m.lsl(.l, imm(8), d4) // a row of tiles is 16 lines of room_w*16 bytes
	m.mulu(d4, d2)
	m.lsl(.l, imm(4), d3)
	m.add(.l, d3, d2)
	m.add(.l, imm(i64(tile_buffer)), d2)
	m.move(.l, d2, a2)
	m.lsl(.l, imm(4), d1) // the width of the picture in bytes
	m.lea(lbl('rt_map'), a0)
	m.moveq(0, d5)
	m.move(.b, idx(0, a0, d0), d5)
	m.lsl(.l, imm(8), d5)
	m.lea(lbl('rt.art.${g.tileset_art}'), a1)
	m.add(.l, d5, a1)
	m.move(.l, d1, d5) // the movem below uses d0-d3
	m.moveq(15, d4)
	m.label('rt.tile_line')
	m.word(0x4cd9) // movem.l (a1)+,d0-d3
	m.word(0x000f)
	m.word(0x48d2) // movem.l d0-d3,(a2)
	m.word(0x000f)
	m.add(.l, d5, a2)
	m.dbra(d4, 'rt.tile_line')
	m.rts()
}

// emit_tile_object writes `rt.tile_object`: it puts the object that shows
// the room's picture, as the camera sees it, in the slot at a1 and moves a1
// on; with no room it leaves everything alone. The picture is one byte a
// pixel. The camera's x is cut into phrases (8 pixels) that go into the
// data pointer and a rest of 0..7 pixels that moves the object left of
// where it would be. A room narrower than the screen is placed by the
// negative camera instead.
fn (g &Game) emit_tile_object(mut m jagkit.M68k) {
	m.label('rt.tile_object')
	m.tst(.b, lbl('rt_map_on'))
	m.b(.eq, 'rt.tile_none')
	m.moveq(0, d1)
	m.move(.w, lbl('rt_room_w'), d1)
	m.lsl(.l, imm(4), d1) // the picture's width
	m.moveq(0, d2)
	m.move(.w, lbl('rt_room_h'), d2)
	m.lsl(.l, imm(4), d2) // and height

	// Across: d3 is where in the picture the window starts, d4 how far in
	// from the left of the screen the picture starts.
	m.move(.w, lbl('camera_x'), d3)
	m.ext(.l, d3)
	m.moveq(0, d4)
	m.tst(.l, d3)
	m.b(.pl, 'rt.camera_x_in')
	m.move(.l, d3, d4)
	m.neg(.l, d4)
	m.moveq(0, d3)
	m.label('rt.camera_x_in')
	m.move(.l, d3, d5)
	m.lsr(.l, imm(3), d5) // phrases to leave out
	m.move(.l, d3, d6)
	m.and(.l, imm(7), d6) // pixels to leave out
	m.move(.l, d1, d0)
	m.lsr(.l, imm(3), d0)
	m.sub(.l, d5, d0) // phrases left in the picture
	m.b(.le, 'rt.tile_none')
	m.cmp(.l, imm(41), d0)
	m.b(.le, 'rt.tile_wide')
	m.moveq(41, d0) // 328 pixels: the screen and a phrase for the fine scroll
	m.label('rt.tile_wide')
	m.move(.l, d0, a2) // phrases shown
	m.move(.l, lbl('rt.left'), d0)
	m.add(.l, d4, d0)
	m.sub(.l, d6, d0)
	m.move(.l, d0, a3) // the object's x
	m.move(.l, d5, d0)
	m.lsl(.l, imm(3), d0)
	m.add(.l, imm(i64(tile_buffer)), d0)
	m.move(.l, d0, a4) // the data, so far

	// Down: d3 the first line of the picture shown, d4 the line of the
	// screen it is on.
	m.move(.w, lbl('camera_y'), d3)
	m.ext(.l, d3)
	m.moveq(0, d4)
	m.tst(.l, d3)
	m.b(.pl, 'rt.camera_y_in')
	m.move(.l, d3, d4)
	m.neg(.l, d4)
	m.moveq(0, d3)
	m.label('rt.camera_y_in')
	m.move(.l, imm(logical_height), d5)
	m.sub(.l, d4, d5) // lines left on the screen
	m.move(.l, d2, d6)
	m.sub(.l, d3, d6) // lines left in the picture
	m.cmp(.l, d6, d5)
	m.b(.le, 'rt.tile_high')
	m.move(.l, d6, d5)
	m.label('rt.tile_high')
	m.tst(.l, d5)
	m.b(.le, 'rt.tile_none')
	m.mulu(d1, d3) // the first line, in bytes
	m.add(.l, d3, a4)

	// The first phrase: the line, the height, the link, the data.
	m.move(.l, d4, d0)
	m.add(.l, d0, d0)
	m.add(.l, lbl('rt.top'), d0)
	m.lsl(.l, imm(3), d0)
	m.move(.l, d5, d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(6), d6)
	m.orr(.l, d6, d0)
	m.move(.l, a1, d6)
	m.add(.l, imm(32), d6) // the link: the next slot
	m.move(.l, d6, d4)
	m.lsl(.l, imm(8), d4)
	m.lsl(.l, imm(8), d4)
	m.lsl(.l, imm(5), d4)
	m.orr(.l, d4, d0)
	m.move(.l, d0, at(4, a1))
	m.lsr(.l, imm(8), d6)
	m.lsr(.l, imm(3), d6)
	m.move(.l, a4, d0)
	m.lsl(.l, imm(8), d0)
	m.orr(.l, d6, d0)
	m.move(.l, d0, ind(a1))

	// The second phrase: where, 8 bits a pixel, how wide the picture is, how
	// many phrases are shown. The pixel 0 is drawn: the layer is opaque.
	m.move(.l, a3, d0)
	m.and(.l, imm(0xfff), d0)
	m.orr(.l, imm((3 << 12) | (1 << 15)), d0)
	m.lsr(.l, imm(3), d1) // phrases a line of the picture takes
	m.move(.l, d1, d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(2), d6)
	m.orr(.l, d6, d0)
	m.move(.l, a2, d6)
	m.and(.l, imm(0xf), d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(8), d6)
	m.lsl(.l, imm(4), d6)
	m.orr(.l, d6, d0)
	m.move(.l, d0, at(12, a1))
	m.move(.l, a2, d0)
	m.lsr(.l, imm(4), d0)
	m.move(.l, d0, at(8, a1))
	m.lea(at(32, a1), a1)
	m.label('rt.tile_none')
	m.rts()
}
