// The guards of GHOSTGRID: their routes, what they sense, the states they
// are in and the cone of light each throws on the floor.
//
// A guard is an actor (jaggame.Actors) with a position, a facing and the
// fields below, and one state machine, `guard_ai`, runs all four:
//
//   patrol      walk the route, waiting a little at each waypoint
//   suspicious  saw a flicker or heard a noise: stop, look at the spot, walk to it, look around
//   alert       saw the figure clearly: chase it; touching it ends the mission
//   search      lost it: go to where it was last seen, look around
//   return      walk back to the route
//
// Guards walk the route along the centres of tiles, following a field of
// directions that was worked out when the game was built, so they cannot
// be stuck on a corner. When they leave the route (to look at a noise, to
// chase) they walk freely with `move_and_slide`, and `return` goes back to
// a tile centre and rejoins the field.
module main

import jaggame

const guard_count = 4
const sight_range = 64 // pixels a cone reaches: four tiles
const sight_half = 24 // angle units either side of the facing: 34 degrees
const alert_after = 24 // frames in a cone before a suspicious guard is sure
const lose_after = 50 // frames without sight before a chasing guard searches
const cone_slots = 32 // cells a cone list holds

// the waypoint markers of the depot, in route order: a guard's route is the
// names `g<guard>w<k>` for k = 0, 1, ...
const route_names = [['g0w0', 'g0w1'], ['g1w0', 'g1w1'], ['g2w0'],
	['g3w0', 'g3w1', 'g3w2', 'g3w3']]
const post_facing = [jaggame.angle_right, jaggame.angle_down, jaggame.angle_up, jaggame.angle_right]

// guard_fields are what a guard's record holds besides what every actor has.
fn guard_fields() []jaggame.Field {
	// guide:gg_fields
	return [jaggame.Field{'wp', .u8}, jaggame.Field{'first', .u8},
		jaggame.Field{'count', .u8}, jaggame.Field{'dir', .u8},
		jaggame.Field{'mleft', .u8}, jaggame.Field{'pause', .u8},
		jaggame.Field{'look', .u8}, jaggame.Field{'exposure', .u8},
		jaggame.Field{'lost', .u8}, jaggame.Field{'stuck', .u8},
		jaggame.Field{'moving', .bool}, jaggame.Field{'stale', .bool},
		jaggame.Field{'spot_x', .i16}, jaggame.Field{'spot_y', .i16},
		jaggame.Field{'cone_x', .i16}, jaggame.Field{'cone_y', .i16},
		jaggame.Field{'cone_f', .u8}, jaggame.Field{'cone_n', .u8}]
	// guide:end
}

// passable is whether a guard can walk on a character of the map.
fn passable(ch u8) bool {
	return ch != `#` && ch != `c`
}

// flow_field is, for every tile of the room, the direction (0 right, 1
// down, 2 left, 3 up) of the first step of a shortest walk to the target
// tile; 255 at the target itself and where there is no way. Found by a
// breadth-first search from the target.
fn flow_field(rows []string, target jaggame.Point) []int {
	mut dist := []int{len: room_cols * room_rows, init: -1}
	mut field := []int{len: room_cols * room_rows, init: 255}
	mut queue := [target]
	dist[target.y * room_cols + target.x] = 0
	mut head := 0
	steps := [jaggame.Point{1, 0}, jaggame.Point{0, 1}, jaggame.Point{-1, 0},
		jaggame.Point{0, -1}]
	for head < queue.len {
		here := queue[head]
		head++
		for d, step in steps {
			next := jaggame.Point{here.x + step.x, here.y + step.y}
			if next.x < 0 || next.y < 0 || next.x >= room_cols || next.y >= room_rows {
				continue
			}
			cell := next.y * room_cols + next.x
			if !passable(rows[next.y][next.x]) || dist[cell] >= 0 {
				continue
			}
			dist[cell] = dist[here.y * room_cols + here.x] + 1
			field[cell] = (d + 2) % 4 // from `next`, the way back to `here`
			queue << next
		}
	}
	return field
}

// Routes is what the build works out about the guards' routes.
struct Routes {
mut:
	first  []int // the number of each guard's first waypoint
	count  []int
	tx     []int // the tile of every waypoint
	ty     []int
	fields []int // a field of directions for every waypoint, one after the other
}

// routes reads the waypoint markers of the depot and works out the fields.
fn routes(mut game jaggame.Game, room jaggame.Room) Routes {
	rows := depot.trim('\n').split('\n')
	mut r := Routes{}
	for names in route_names {
		r.first << r.tx.len
		r.count << names.len
		for name in names {
			found := game.markers_of(room, name)
			point := if found.len > 0 { found[0] } else { jaggame.Point{1, 1} }
			r.tx << point.x
			r.ty << point.y
			r.fields << flow_field(rows, point)
		}
	}
	return r
}

// define_guard_functions writes what the states use: seeing, walking along
// the route, walking freely, looking around, lighting the cone.
fn (mut m Mission) define_guard_functions() {
	mut game := m.game
	mut p := game.p

	// watch: does guard `i` see the figure? Only if the figure's tile is
	// lit by this guard's cone: what is lit is what sees. A crouching figure
	// is hidden when a cover block is on the line.
	// guide:gg_watch
	mut c := p.define(m.watch)
	mut i := m.watch.arg('i')
	sees := c.local_bool('sees')
	gtx := c.local_i32('gtx')
	gty := c.local_i32('gty')
	ptx := c.local_i32('ptx')
	pty := c.local_i32('pty')
	exposure := m.gf(i, 'exposure')
	bit := jaggame.lit(1).as_(.u8).shl(i)

	c.if_(m.lit.at(m.pcell).and(bit).ne(0))
	c.set(sees, true)

	c.if_(m.crouched)
	c.set(gtx, m.gcx(i).shr(4).shl(4).add(8)) // the centres of the two tiles
	c.set(gty, m.gcy(i).shr(4).shl(4).add(8))
	c.set(ptx, m.pcx().shr(4).shl(4).add(8))
	c.set(pty, m.pcy().shr(4).shl(4).add(8))
	c.set(sees,
		game.can_see_crouched(gtx, gty, m.guards.face(i), ptx, pty, sight_range, sight_half))
	c.end() // crouching
	c.end() // in a lit tile

	// How long it has been in view: it grows while seen, and fades.
	c.if_(sees)

	c.if_(exposure.lt(255))
	c.inc(exposure)
	c.end() // not at the top
	c.else_if(game.frame.and(1).eq(0).both(exposure.gt(0)))
	c.dec(exposure)
	c.end() // seen or not
	c.ret(sees)
	// guide:end

	// chase: one step towards a point (its middle, in the world) with
	// move_and_slide; true when it is there.
	c = p.define(m.chase)
	i = m.chase.arg('i')
	ddx := c.local_i32('ddx')
	ddy := c.local_i32('ddy')
	mx := c.local_fix('mx')
	my := c.local_fix('my')
	before_x := c.local_fix('before_x')
	before_y := c.local_fix('before_y')
	speed := m.chase.arg('speed')
	c.set(ddx, m.chase.arg('tx').sub(m.gcx(i)))
	c.set(ddy, m.chase.arg('ty').sub(m.gcy(i)))

	c.if_(ddx.abs().le(2).both(ddy.abs().le(2)))
	c.ret(true)
	c.end() // there

	c.if_(ddx.gt(0))
	c.set(mx, speed.min(ddx.as_(.fix)))
	c.else_if(ddx.lt(0))
	c.set(mx, speed.min(ddx.neg().as_(.fix)).neg())
	c.end() // along x

	c.if_(ddy.gt(0))
	c.set(my, speed.min(ddy.as_(.fix)))
	c.else_if(ddy.lt(0))
	c.set(my, speed.min(ddy.neg().as_(.fix)).neg())
	c.end() // along y
	c.set(before_x, m.guards.x(i))
	c.set(before_y, m.guards.y(i))
	game.move_and_slide(mut c, m.guards.x(i), m.guards.y(i), player_box, mx, my)

	c.if_(m.guards.x(i).eq(before_x).both(m.guards.y(i).eq(before_y)))

	c.if_(m.gf(i, 'stuck').lt(255))
	c.inc(m.gf(i, 'stuck'))
	c.end() // counting
	c.else_()
	c.set(m.gf(i, 'stuck'), 0)
	c.end() // moved or not
	c.set(m.guards.face(i), game.direction(ddx, ddy).add(32).and(0xc0)) // the nearest of the four ways
	c.set(m.gf(i, 'moving'), true)
	c.call(m.moved, i)
	c.ret(false)

	// follow: one step along the route, by the field of directions of the
	// waypoint the guard is heading for. At the middle of a tile it asks the
	// field which way to go; it walks 16 pixels that way. True when the field
	// says it is there.
	c = p.define(m.follow)
	i = m.follow.arg('i')
	gx := c.local_i32('gx')
	gy := c.local_i32('gy')
	way := c.local_u8('way')
	by := c.local_u8('by')
	mleft := m.gf(i, 'mleft')
	c.set(gx, m.gcx(i).shr(4))
	c.set(gy, m.gcy(i).shr(4))

	c.if_(mleft.eq(0))
	c.set(way,
		m.flow.at(m.gf(i, 'first').add(m.gf(i, 'wp')).as_(.u16).mul(room_cells).add(gy.mul(room_cols).add(gx).as_(.u16))))

	c.if_(way.eq(255))
	c.ret(true)
	c.end() // there
	c.set(m.gf(i, 'dir'), way)
	c.set(mleft, 16)
	c.set(m.guards.face(i), way.shl(6))
	c.end() // at the middle of a tile
	c.set(by, m.follow.arg('step').min(mleft))
	c.set(m.guards.x(i), m.guards.x(i).add(m.dir_x.at(m.gf(i, 'dir')).as_(.fix).mul(by.as_(.fix))))
	c.set(m.guards.y(i), m.guards.y(i).add(m.dir_y.at(m.gf(i, 'dir')).as_(.fix).mul(by.as_(.fix))))
	c.set(mleft, mleft.sub(by))
	c.set(m.gf(i, 'moving'), true)

	c.if_(mleft.and(7).eq(0))
	c.call(m.moved, i) // half way or all the way into the next tile
	c.end()
	c.ret(false)

	// around: walk to the guard's spot, then turn through the four ways, 20
	// frames each. True when it has looked all round.
	c = p.define(m.around)
	i = m.around.arg('i')
	look := m.gf(i, 'look')

	c.if_(look.eq(0))

	c.if_(m.chase.call(i, m.gf(i, 'spot_x').as_(.i32), m.gf(i, 'spot_y').as_(.i32),
		m.around.arg('speed')).either(m.gf(i, 'stuck').gt(30)))
	c.set(look, 1)
	c.set(m.gf(i, 'pause'), 0)
	c.set(m.gf(i, 'stuck'), 0)
	c.end() // there
	c.ret(false)
	c.end() // walking
	c.inc(m.gf(i, 'pause'))

	c.if_(m.gf(i, 'pause').ge(20))
	c.set(m.gf(i, 'pause'), 0)
	c.inc(look)
	c.set(m.guards.face(i), m.guards.face(i).add(64))
	c.set(m.gf(i, 'stale'), true)
	c.end() // time to turn
	c.ret(look.gt(4))

	m.define_cone()
}

// define_cone writes `light_cone` and `show_tile`: the tiles a guard's cone
// reaches are lit on the floor. A guard's cone is a list of cells that the
// build worked out for the tile it stands on and the way it faces
// (`view_cells`, walls taken into account), and a byte for each tile (`lit`)
// says which guards' cones are on it; a tile is drawn lit while any
// guard's bit is set. Moving a cone changes only the tiles that are in one
// list and not in the other.
fn (mut m Mission) define_cone() {
	mut game := m.game
	mut p := game.p

	// moved: has the guard left the tile its cone was worked out for, or
	// turned? Then the cone is stale and the update will do it again.
	mut c := p.define(m.moved)
	mi := m.moved.arg('i')

	c.if_(m.gcx(mi).shr(4).ne(m.gf(mi, 'cone_x').as_(.i32)).either(m.gcy(mi).shr(4).ne(m.gf(mi,
		'cone_y').as_(.i32))).either(m.guards.face(mi).shr(6).ne(m.gf(mi, 'cone_f'))))
	c.set(m.gf(mi, 'stale'), true)
	c.end() // moved or turned

	// guide:gg_cone
	c = p.define(m.cone)
	i := m.cone.arg('i')
	f := c.local_u8('f')
	k := c.local_u16('k')
	n := c.local_u8('n')
	gx := c.local_i32('gx')
	gy := c.local_i32('gy')
	key := c.local_u16('key')
	start := c.local_u16('start')
	cell := c.local_u16('cell')
	slot := c.local_u16('slot')
	bit := c.local_u8('bit')
	marked := c.local_u8('marked')
	c.set(f, m.guards.face(i).shr(6))
	c.set(gx, m.gcx(i).shr(4))
	c.set(gy, m.gcy(i).shr(4))
	c.set(bit, jaggame.lit(1).as_(.u8).shl(i))
	c.set(marked, bit.shl(4))
	c.set(key, gy.mul(room_cols).add(gx).as_(.u16).shl(2).add(f.as_(.u16)))
	c.set(start, m.view_at.at(key))
	c.set(n, m.view_len.at(key))

	// Mark the cells of the new cone, so that the cells that stay are not
	// drawn twice.
	c.for_(k, 0, n)
	c.set(cell,
		m.pool_y.at(start.add(k)).as_(.u16).mul(room_cols).add(m.pool_x.at(start.add(k)).as_(.u16)))
	c.set(m.lit.at(cell), m.lit.at(cell).or_(marked))
	c.end() // each new cell

	// The cells that were lit and are not any more.
	c.for_(k, 0, m.gf(i, 'cone_n'))
	c.set(slot, i.mul(cone_slots).add(k))
	c.set(cell, m.old_y.at(slot).as_(.u16).mul(room_cols).add(m.old_x.at(slot).as_(.u16)))

	c.if_(m.lit.at(cell).and(marked).eq(0))
	c.set(m.lit.at(cell), m.lit.at(cell).and(bit.not()))

	c.if_(m.lit.at(cell).and(0x0f).eq(0))
	game.set_cell(mut c, cell, m.dim_of.at(game.tile_cell(cell))) // no cone is on it any more
	c.end() // dark
	c.end() // gone
	c.end() // each old cell

	// The cells that are lit now and were not; the list is kept for next time.
	c.for_(k, 0, n)
	c.set(slot, start.add(k))
	c.set(cell, m.pool_y.at(slot).as_(.u16).mul(room_cols).add(m.pool_x.at(slot).as_(.u16)))

	c.if_(m.lit.at(cell).and(bit).eq(0))

	c.if_(m.lit.at(cell).and(0x0f).eq(0))
	game.set_cell(mut c, cell, m.glow_of.at(game.tile_cell(cell))) // the first cone on it
	c.end() // lit
	c.set(m.lit.at(cell), m.lit.at(cell).or_(bit))
	c.end() // new
	c.set(m.lit.at(cell), m.lit.at(cell).and(marked.not()))
	c.set(slot, i.mul(cone_slots).add(k))
	c.set(m.old_x.at(slot), m.pool_x.at(start.add(k)))
	c.set(m.old_y.at(slot), m.pool_y.at(start.add(k)))
	c.end() // each new cell
	c.set(m.gf(i, 'cone_n'), n)
	c.set(m.gf(i, 'cone_x'), gx.as_(.i16))
	c.set(m.gf(i, 'cone_y'), gy.as_(.i16))
	c.set(m.gf(i, 'cone_f'), f)
	c.set(m.gf(i, 'stale'), false)
	// guide:end
}

// spot_figure makes the place where the figure is the guard's spot.
fn (m &Mission) spot_figure(mut c jaggame.Code, i jaggame.Expr) {
	c.set(m.gf(i, 'spot_x'), m.pcx().as_(.i16))
	c.set(m.gf(i, 'spot_y'), m.pcy().as_(.i16))
}

// spot_noise makes the place of the noise being heard the guard's spot.
fn (mut m Mission) spot_noise(mut c jaggame.Code, i jaggame.Expr) {
	c.set(m.gf(i, 'spot_x'), m.game.noise_x())
	c.set(m.gf(i, 'spot_y'), m.game.noise_y())
}

// define_states writes the guard's state machine.
fn (mut m Mission) define_states() {
	mut game := m.game
	// guide:gg_states
	mut c := m.ai.state('patrol')
	mut i := c.me()
	c.set(m.gf(i, 'moving'), false)

	c.if_(m.watch.call(i))
	m.spot_figure(mut c, i)
	c.inc(m.seen)
	c.to('suspicious')
	c.ret_void()
	c.end() // saw something

	c.if_(game.hears(m.gcx(i), m.gcy(i)))
	m.spot_noise(mut c, i)
	c.to('suspicious')
	c.ret_void()
	c.end() // heard something

	c.if_(m.gf(i, 'pause').gt(0))
	c.dec(m.gf(i, 'pause'))
	c.ret_void()
	c.end() // waiting at a waypoint

	c.if_(m.follow.call(i, 1))
	c.set(m.gf(i, 'wp'), m.gf(i, 'wp').add(1))

	c.if_(m.gf(i, 'wp').ge(m.gf(i, 'count')))
	c.set(m.gf(i, 'wp'), 0)
	c.end() // round the route
	c.set(m.gf(i, 'pause'), 45)
	// Turn to look along the next leg.
	way := c.local_u8('way')
	c.set(way,
		m.flow.at(m.gf(i, 'first').add(m.gf(i, 'wp')).as_(.u16).mul(room_cells).add(m.gcy(i).shr(4).mul(room_cols).add(m.gcx(i).shr(4)).as_(.u16))))

	c.if_(way.ne(255))
	c.set(m.guards.face(i), way.shl(6))
	c.set(m.gf(i, 'stale'), true)
	c.end() // there is a next leg
	c.end() // at the waypoint

	c = m.ai.state('suspicious')
	i = c.me()
	c.set(m.gf(i, 'moving'), false)

	c.if_(m.watch.call(i))
	m.spot_figure(mut c, i)

	c.if_(m.gf(i, 'exposure').ge(alert_after))
	c.to('alert')
	c.ret_void()
	c.end() // sure now
	c.end() // in view

	c.if_(c.time_in_state().lt(20))

	c.if_(c.time_in_state().eq(0))
	c.set(m.guards.face(i), game.direction(m.gf(i, 'spot_x').as_(.i32).sub(m.gcx(i)), m.gf(i,
		'spot_y').as_(.i32).sub(m.gcy(i))).add(32).and(0xc0))
	c.end() // turn to the spot
	c.ret_void()
	c.end() // standing still

	c.if_(m.around.call(i, 1.0))
	c.to('return')
	c.end() // done looking

	c = m.ai.state('alert')
	i = c.me()
	c.set(m.gf(i, 'moving'), false)

	c.if_(m.watch.call(i))
	c.set(m.gf(i, 'lost'), 0)
	m.spot_figure(mut c, i)
	c.else_()
	c.set(m.gf(i, 'lost'), m.gf(i, 'lost').add(1).min(255))
	c.end() // in view
	c.call(m.chase, i, m.gf(i, 'spot_x').as_(.i32), m.gf(i, 'spot_y').as_(.i32), 2.0)

	c.if_(jaggame.overlap(jaggame.Rect{
		x: m.guards.x(i).as_(.i16).add(2)
		y: m.guards.y(i).as_(.i16).add(3)
		w: 12
		h: 12
	}, jaggame.Rect{
		x: m.px.as_(.i16).add(2)
		y: m.py.as_(.i16).add(3)
		w: 12
		h: 12
	}))
	c.set(m.phase, 2) // caught
	c.end() // touched the figure

	c.if_(m.gf(i, 'lost').gt(lose_after))
	c.to('search')
	c.end() // lost it

	c = m.ai.state('search')
	i = c.me()
	c.set(m.gf(i, 'moving'), false)

	c.if_(m.watch.call(i))
	m.spot_figure(mut c, i)
	c.to('alert')
	c.ret_void()
	c.end() // there it is

	c.if_(m.around.call(i, 1.5))
	c.to('return')
	c.end() // looked everywhere

	c = m.ai.state('return')
	i = c.me()
	c.set(m.gf(i, 'moving'), false)

	c.if_(m.watch.call(i))
	m.spot_figure(mut c, i)
	c.inc(m.seen)
	c.to('suspicious')
	c.ret_void()
	c.end() // saw something

	c.if_(game.hears(m.gcx(i), m.gcy(i)))
	m.spot_noise(mut c, i)
	c.to('suspicious')
	c.ret_void()
	c.end() // heard something

	c.if_(m.gf(i, 'look').eq(0))
	// First to the middle of the tile it is on, then it can use the field again.
	c.if_(m.chase.call(i, m.gcx(i).shr(4).shl(4).add(8), m.gcy(i).shr(4).shl(4).add(8), 1.0).either(m.gf(i,
		'stuck').gt(30)))
	c.set(m.guards.x(i), m.gcx(i).shr(4).shl(4).as_(.fix))
	c.set(m.guards.y(i), m.gcy(i).shr(4).shl(4).sub(1).as_(.fix))
	c.set(m.gf(i, 'look'), 1)
	c.set(m.gf(i, 'mleft'), 0)
	c.end() // on the middle
	c.ret_void()
	c.end() // not on it yet

	c.if_(m.follow.call(i, 2))
	c.set(m.gf(i, 'pause'), 20)
	c.to('patrol')
	c.end() // back on the route

	// Every state starts with a clean sheet when it is entered.
	for name in ['suspicious', 'alert', 'search', 'return'] {
		mut e := m.ai.on_enter(name)
		j := e.me()
		e.set(m.gf(j, 'look'), 0)
		e.set(m.gf(j, 'pause'), 0)
		e.set(m.gf(j, 'stuck'), 0)
		e.set(m.gf(j, 'lost'), 0)
		if name == 'return' {
			e.set(m.gf(j, 'mleft'), 0)
		}
	}
	// guide:end
}
