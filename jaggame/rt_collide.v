module jaggame

import jagkit

// Collision. Tiles have flags (the legend gives them; see `flags_at`), and
// `move_and_slide` moves a box against the solid ones. Boxes against boxes
// are a plain expression.

// Hitbox is the part of a sprite that collides: a rectangle of `w` by `h`
// pixels whose top left corner is `ox`, `oy` pixels from the sprite's
// position. A hitbox smaller than the picture lets the corners pass walls.
pub struct Hitbox {
pub:
	ox int
	oy int
	w  int
	h  int
}

// Rect is a rectangle in the world, for `overlap`.
pub struct Rect {
pub:
	x Val
	y Val
	w Val
	h Val
}

// rect is the world rectangle of a sprite's hitbox. The sprite's position
// is an `i16`, so the other rectangle's numbers must be one too.
pub fn (s Sprite) rect(b Hitbox) Rect {
	return Rect{
		x: s.x.add(b.ox)
		y: s.y.add(b.oy)
		w: b.w
		h: b.h
	}
}

// overlap is true when two rectangles share at least one pixel. All their
// numbers must be of one type (integers; a `fix` position needs `as_`).
pub fn overlap(a Rect, b Rect) Expr {
	ax := lit(a.x)
	ay := lit(a.y)
	bx := lit(b.x)
	by := lit(b.y)
	return ax.lt(bx.add(b.w)).both(bx.lt(ax.add(a.w))).both(ay.lt(by.add(b.h))).both(by.lt(ay.add(a.h)))
}

// max_step is the most a box moves along one axis in one `move_and_slide`:
// one tile. A larger step is cut to it; a faster mover calls again.
pub const max_step = 16

// move_and_slide moves the box of a mover, whose position is `x` and `y`
// (`fix` variables, in world pixels), by `dx` and `dy` (`fix` values)
// against the solid tiles: first along x, then along y, each stopping flush
// against a wall. Moving diagonally into a wall therefore slides along it.
// Afterwards `blocked_x` and `blocked_y` say which way a wall stopped it.
//
// A step along one axis is at most `max_step` (16) pixels, one tile, so
// that only one new column or row of tiles can be entered and nothing is
// tunnelled through; a larger step is cut to that. The box must not start
// inside a wall. Outside the room counts as solid. The edge of the box is
// the whole pixel the position is in: the position's fraction is kept while
// the box is free and dropped when a wall stops it.
pub fn (mut g Game) move_and_slide(mut c Code, x Expr, y Expr, box Hitbox, dx Val, dy Val) {
	g.use_map()
	c.set(g.tv.slide_x, x)
	c.set(g.tv.slide_y, y)
	c.call(g.tv.slide, box.ox, box.oy, box.w, box.h, dx, dy)
	c.set(x, g.tv.slide_x)
	c.set(y, g.tv.slide_y)
}

// blocked_x is true when the last `move_and_slide` was stopped by a wall
// along x.
pub fn (mut g Game) blocked_x() Expr {
	g.use_map()
	return g.tv.hit.and(1).ne(0)
}

// blocked_y is true when the last `move_and_slide` was stopped by a wall
// along y.
pub fn (mut g Game) blocked_y() Expr {
	g.use_map()
	return g.tv.hit.and(2).ne(0)
}

// define_slide writes `rt_slide` and the two functions it asks the tiles
// with.
fn (mut g Game) define_slide() {
	tv := g.tv
	mut c := g.p.define(tv.col_solid)
	col_solid := tv.col_solid
	c.native_ret(fn [col_solid] (mut m jagkit.M68k) {
		emit_line_solid(mut m, col_solid, true)
	}, fn [col_solid] (mut it Interpreter) ! {
		run_line_solid(mut it, col_solid, true)!
	})
	c = g.p.define(tv.row_solid)
	row_solid := tv.row_solid
	c.native_ret(fn [row_solid] (mut m jagkit.M68k) {
		emit_line_solid(mut m, row_solid, false)
	}, fn [row_solid] (mut it Interpreter) ! {
		run_line_solid(mut it, row_solid, false)!
	})

	slide := tv.slide
	c = g.p.define(slide)
	ox := slide.arg('ox')
	oy := slide.arg('oy')
	w := slide.arg('w')
	h := slide.arg('h')
	mx := c.local_fix('mx')
	my := c.local_fix('my')
	nx := c.local_fix('nx')
	ny := c.local_fix('ny')
	left := c.local_i32('left')
	top := c.local_i32('top')
	edge := c.local_i32('edge')
	sx := tv.slide_x
	sy := tv.slide_y
	hit := tv.hit
	c.set(hit, 0)
	c.set(mx, slide.arg('dx').max(-f64(max_step)).min(f64(max_step)))
	c.set(my, slide.arg('dy').max(-f64(max_step)).min(f64(max_step)))

	// Along x, with the box at its old y.
	c.if_(mx.ne(0))
	c.set(nx, sx.add(mx))
	c.set(top, sy.as_(.i32).add(oy))
	c.set(left, nx.as_(.i32).add(ox))

	c.if_(mx.gt(0))
	c.set(edge, left.add(w).sub(1).shr(4)) // the column of the right edge
	c.if_(tv.col_solid.call(edge, top.shr(4), top.add(h).sub(1).shr(4)))
	c.set(nx, edge.shl(4).sub(w).sub(ox).as_(.fix))
	c.set(hit, hit.or_(1))
	c.end() // a wall on the right
	c.else_()
	c.set(edge, left.shr(4)) // the column of the left edge
	c.if_(tv.col_solid.call(edge, top.shr(4), top.add(h).sub(1).shr(4)))
	c.set(nx, edge.add(1).shl(4).sub(ox).as_(.fix))
	c.set(hit, hit.or_(1))
	c.end() // a wall on the left
	c.end() // which way
	c.set(sx, nx)
	c.end() // moves along x

	// Along y, with the box at its new x.
	c.if_(my.ne(0))
	c.set(ny, sy.add(my))
	c.set(left, sx.as_(.i32).add(ox))
	c.set(top, ny.as_(.i32).add(oy))

	c.if_(my.gt(0))
	c.set(edge, top.add(h).sub(1).shr(4)) // the row of the bottom edge
	c.if_(tv.row_solid.call(edge, left.shr(4), left.add(w).sub(1).shr(4)))
	c.set(ny, edge.shl(4).sub(h).sub(oy).as_(.fix))
	c.set(hit, hit.or_(2))
	c.end() // a wall below
	c.else_()
	c.set(edge, top.shr(4)) // the row of the top edge
	c.if_(tv.row_solid.call(edge, left.shr(4), left.add(w).sub(1).shr(4)))
	c.set(ny, edge.add(1).shl(4).sub(oy).as_(.fix))
	c.set(hit, hit.or_(2))
	c.end() // a wall above
	c.end() // which way
	c.set(sy, ny)
	c.end() // moves along y
}

// define_markers writes the functions that tell where the markers are in
// the loaded room, from tables of every room's markers.
fn (mut g Game) define_markers() {
	tv := g.tv
	names := g.marker_names()
	if names.len == 0 {
		return
	}
	mut most := 1
	for r in g.rooms {
		for n in names {
			if r.markers[n].len > most {
				most = r.markers[n].len
			}
		}
	}
	mut counts := []int{}
	mut places := []int{}
	for r in g.rooms {
		for n in names {
			found := r.markers[n].clone()
			counts << found.len
			for k in 0 .. most {
				places << if k < found.len { found[k].x } else { 0 }
				places << if k < found.len { found[k].y } else { 0 }
			}
		}
	}
	if counts.len == 0 {
		counts << 0
		places << [0, 0]
	}
	count_table := g.p.table_u8('rt_marker_counts', counts)
	place_table := g.p.table_u8('rt_marker_places', places)
	mut c := g.p.define(tv.marker_count)
	slot := count_table.at(g.room_number.as_(.u16).mul(names.len).add(tv.marker_count.arg('name')))
	c.ret(slot)

	marker := tv.marker
	c = g.p.define(marker)
	index := c.local_u16('index')
	c.set(index, g.room_number.as_(.u16).mul(names.len).add(marker.arg('name')))

	c.if_(marker.arg('k').ge(count_table.at(index)))
	c.ret(-1)
	c.end() // no such place

	c.ret(place_table.at(index.mul(most).add(marker.arg('k')).mul(2).add(marker.arg('axis'))).as_(.i16))
}
