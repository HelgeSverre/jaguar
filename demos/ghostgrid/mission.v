module main

import jaggame
import os

// Mission is the game's variables and functions, so that the figure, the
// guards and the update can share them. Everything here is a variable or a
// function of the jaggame program; the game itself runs from that.
struct Mission {
mut:
	game   &jaggame.Game
	room   jaggame.Room
	routes Routes
	// the figure
	px       jaggame.Expr // the figure's position in the world, pixels (top left of the picture)
	py       jaggame.Expr
	facing   jaggame.Expr // 0 down, 1 up, 2 left, 3 right
	playing  jaggame.Expr // the animation that runs: 1 + direction + 4 for running; 9 crouching; 0 none
	crouched jaggame.Expr
	clear_at jaggame.Expr // the next tile of `lit` to clear while a room loads
	pcell    jaggame.Expr // the tile the figure is on: row * columns + column
	flash    jaggame.Expr // frames the word KNOCK stays up
	// the mission
	phase     jaggame.Expr // 0 playing, 1 done, 2 caught
	clock     jaggame.Expr // frames of play
	secs      jaggame.Expr // whole seconds of play
	sub       jaggame.Expr // the frames since the last whole second
	secs_on   jaggame.Expr // the seconds the HUD shows
	seen_on   jaggame.Expr // the times seen the HUD shows
	seen      jaggame.Expr // times a guard noticed the figure
	level     jaggame.Expr // 0 calm, 1 someone is suspicious or searching, 2 someone is chasing
	shown     jaggame.Expr // the level on the status line, 3 when the mission is over
	setup_due jaggame.Expr // 0, or the steps of the start that are left: the figure, then each guard in a frame of its own
	// what the cones light
	lit   jaggame.Expr // a byte for each tile: bit g is set if guard g's cone is on it
	old_x jaggame.Expr // the tiles of each guard's cone: cone_slots for each
	old_y jaggame.Expr
	// tables
	wp_x     jaggame.Expr // the tile of each waypoint
	wp_y     jaggame.Expr
	flow     jaggame.Expr // fields of directions, a room of them for each waypoint
	view_at  jaggame.Expr // where the cone of a tile and a facing starts in the pool of cells
	view_len jaggame.Expr // how many cells it has
	pool_x   jaggame.Expr // the cells of all the cones: columns and rows
	pool_y   jaggame.Expr
	dir_x    jaggame.Expr
	dir_y    jaggame.Expr
	dim_of   jaggame.Expr // the tile that a lit tile goes back to
	glow_of  jaggame.Expr // the tile that shows a tile under a cone
	art_row  jaggame.Expr
	// the guards
	guards &jaggame.Actors
	ai     &jaggame.Machine
	hud    jaggame.TextLayer
	status jaggame.TextLayer
	msg    jaggame.TextLayer
	player jaggame.Sprite
	watch  jaggame.Func // the guard sees the figure, a bool
	chase  jaggame.Func // move towards a point; true when there
	follow jaggame.Func // one step along the route; true when at the waypoint
	around jaggame.Func // walk to the spot and look around; true when done
	moved  jaggame.Func // a guard has moved or turned: its cone may be out of date
	cone   jaggame.Func // work out a guard's cone and light it
	setup  jaggame.Func // put everything at the start
}

// describe describes everything: pictures, the room, text, and what
// happens at start-up and in each frame.
fn describe() &jaggame.Game {
	mut game := jaggame.new_game(jaggame.Config{
		sprites:    9
		layers:     3
		background: jaggame.cry(6, 8, 20)
	})

	// guide:gg_declare
	game.tileset(os.join_path(art_dir(), 'tiles.png'))
	game.png_pal('player', os.join_path(art_dir(), 'player.png'), 16, 16)
	game.png_pal('guard', os.join_path(art_dir(), 'guard.png'), 16, 16)
	game.png_pal('mark', os.join_path(art_dir(), 'mark.png'), 16, 16)

	game.legend_tile(`.`, tile_floor, 0)
	game.legend_tile(`#`, tile_wall, jaggame.flag_solid)
	game.legend_tile(`c`, tile_cover, jaggame.flag_solid | jaggame.flag_cover)
	game.legend_tile(`X`, tile_exit, jaggame.flag_exit)
	game.legend_tile(`,`, tile_floor_lit, 0)
	game.legend_tile(`;`, tile_exit_lit, jaggame.flag_exit)
	game.legend_marker(`@`, 'start', tile_floor, 0)
	mut waypoint := 0
	for names in route_names {
		for name in names {
			game.legend_marker(rune(`1` + waypoint), name, tile_floor, 0)
			waypoint++
		}
	}
	depot_room := game.room('depot', depot)
	// guide:end
	mut m := new_mission(mut game, depot_room)
	m.define_player_animations()
	m.define_guard_functions()
	m.define_states()
	m.define_init()
	m.define_update()
	return game
}

// new_mission declares the variables, tables and functions.
fn new_mission(mut game jaggame.Game, room jaggame.Room) &Mission {
	r := routes(mut game, room)
	mut p := game.p
	// The cones, worked out when the game is built: for every tile a guard
	// can stand on and every facing, the tiles it sees. A cone on the screen
	// is then a table look-up.
	rows := depot.trim('\n').split('\n')
	mut view_at := []int{}
	mut view_len := []int{}
	mut pool_x := []int{}
	mut pool_y := []int{}
	for y in 0 .. room_rows {
		for x in 0 .. room_cols {
			for f in 0 .. 4 {
				view_at << pool_x.len
				if passable(rows[y][x]) {
					for cell in game.view_cells(room, x, y, f * 64, sight_range, sight_half, false) {
						pool_x << cell.x
						pool_y << cell.y
					}
				}
				view_len << pool_x.len - view_at.last()
				assert view_len.last() <= cone_slots
			}
		}
	}
	assert pool_x.len < 65536
	mut fields := []int{}
	for f in r.fields {
		fields << f
	}
	guards := game.actors('guards', guard_fields(), guard_count, 1)
	mut m := &Mission{
		game:      game
		room:      room
		routes:    r
		px:        p.fix('px')
		py:        p.fix('py')
		facing:    p.u8('facing')
		playing:   p.u8('playing')
		crouched:  p.bool('crouched')
		pcell:     p.u16('pcell')
		clear_at:  p.u16('clear_at')
		flash:     p.u8('flash')
		phase:     p.u8('phase')
		clock:     p.u32('clock')
		secs:      p.u16('secs')
		sub:       p.u8('sub')
		secs_on:   p.u16('secs_on', 65535)
		seen_on:   p.u16('seen_on', 65535)
		seen:      p.u16('seen')
		level:     p.u8('level')
		shown:     p.u8('shown', 9)
		setup_due: p.u8('setup_due')
		lit:       p.array_u8('lit', room_cols * room_rows)
		old_x:     p.array_u8('cone_old_x', guard_count * cone_slots)
		old_y:     p.array_u8('cone_old_y', guard_count * cone_slots)
		wp_x:      p.table_u8('wp_x', r.tx)
		wp_y:      p.table_u8('wp_y', r.ty)
		flow:      p.table_u8('flow', fields)
		view_at:   p.table_u16('view_at', view_at)
		view_len:  p.table_u8('view_len', view_len)
		pool_x:    p.table_u8('pool_x', pool_x)
		pool_y:    p.table_u8('pool_y', pool_y)
		dir_x:     p.table_i8('dir_x', [1, 0, -1, 0])
		dir_y:     p.table_i8('dir_y', [0, 1, 0, -1])
		dim_of:    p.table_u8('dim_of', [tile_floor, tile_wall, tile_cover, tile_exit, tile_floor,
			tile_exit])
		glow_of:   p.table_u8('glow_of', [tile_floor_lit, tile_wall, tile_cover, tile_exit_lit,
			tile_floor_lit, tile_exit_lit])
		art_row:   p.table_u8('art_row', [3, 0, 2, 1]) // the sheet's row of a guard facing right, down, left, up
		guards:    guards
		ai:        p.machine('guard_ai', guards.records)
		hud:       game.text_layer('hud', jaggame.TextConfig{
			columns: 16
			rows:    2
			x:       8
			y:       8
			colour:  jaggame.cry(255, 225, 90)
		})
		status:    game.text_layer('status', jaggame.TextConfig{
			columns: 8
			rows:    1
			x:       248
			y:       8
			colour:  jaggame.cry(90, 240, 140)
		})
		msg:       game.text_layer('msg', jaggame.TextConfig{
			columns: 24
			rows:    7
			x:       64
			y:       70
		})
		player:    game.sprite(0)
	}
	m.watch = p.func('watch', [jaggame.Param{'i', .u16}], .bool)
	m.chase = p.func('chase', [jaggame.Param{'i', .u16}, jaggame.Param{'tx', .i32},
		jaggame.Param{'ty', .i32}, jaggame.Param{'speed', .fix}], .bool)
	m.follow = p.func('follow', [jaggame.Param{'i', .u16}, jaggame.Param{'step', .u8}], .bool)
	m.around = p.func('around', [jaggame.Param{'i', .u16}, jaggame.Param{'speed', .fix}], .bool)
	m.moved = p.func('moved', [jaggame.Param{'i', .u16}], .void)
	m.cone = p.func('light_cone', [jaggame.Param{'i', .u16}], .void)
	m.setup = p.func('setup', [jaggame.Param{'step', .u8}], .void)
	return m
}

// pcx is the middle of the figure's box in the world.
fn (m &Mission) pcx() jaggame.Expr {
	return m.px.as_(.i32).add(8)
}

fn (m &Mission) pcy() jaggame.Expr {
	return m.py.as_(.i32).add(9)
}

// gf is a field of guard `i`.
fn (m &Mission) gf(i jaggame.Val, name string) jaggame.Expr {
	return m.guards.field(i, name)
}

// gcx is the middle of guard `i`'s box in the world.
fn (m &Mission) gcx(i jaggame.Val) jaggame.Expr {
	return m.guards.x(i).as_(.i32).add(8)
}

fn (m &Mission) gcy(i jaggame.Val) jaggame.Expr {
	return m.guards.y(i).as_(.i32).add(9)
}

// define_player_animations declares the figure's animations: frame 0 of each
// direction stands, 1 and 2 are the two steps, 3 crouches. Running is the
// same walk, faster.
fn (mut m Mission) define_player_animations() {
	// guide:gg_animations
	directions := ['down', 'up', 'left', 'right']
	for d, name in directions {
		first := d * 4
		m.game.sequence('walk_${name}', [jaggame.Step{first + 1, 0.14},
			jaggame.Step{first, 0.14}, jaggame.Step{first + 2, 0.14},
			jaggame.Step{first, 0.14}])
		m.game.sequence('run_${name}', [jaggame.Step{first + 1, 0.07},
			jaggame.Step{first, 0.07}, jaggame.Step{first + 2, 0.07},
			jaggame.Step{first, 0.07}])
	}
	// guide:end
}

// define_setup writes `setup`: the figure on its start, every guard on its
// route. It runs once a room is loaded: the start
// and the first waypoint are read from the markers.
fn (mut m Mission) define_setup() {
	mut game := m.game
	mut c := game.p.define(m.setup)
	step := m.setup.arg('step')

	c.if_(step.eq(0))
	c.set(m.px, game.marker_x('start', 0).mul(jaggame.tile_size).as_(.fix))
	c.set(m.py, game.marker_y('start', 0).mul(jaggame.tile_size).as_(.fix))
	c.set(m.facing, 3)
	c.set(m.playing, 0)
	c.set(m.crouched, false)
	c.set(m.flash, 0)
	c.set(m.clock, 0)
	c.set(m.secs, 0)
	c.set(m.sub, 0)
	c.set(m.secs_on, 65535)
	c.set(m.seen_on, 65535)
	c.set(m.seen, 0)
	m.msg.clear(mut c)
	c.end() // the figure

	rows := depot.trim('\n').split('\n')
	for g in 0 .. guard_count {
		first := m.routes.first[g]
		count := m.routes.count[g]
		tile_x := m.routes.tx[first]
		tile_y := m.routes.ty[first]
		// The first leg: the direction the field of the next waypoint gives.
		mut face := post_facing[g]
		if count > 1 {
			field := flow_field(rows, jaggame.Point{m.routes.tx[first + 1], m.routes.ty[first + 1]})
			way := field[tile_y * room_cols + tile_x]
			if way < 4 {
				face = way * 64
			}
		}

		c.if_(step.eq(1 + g))
		m.guards.remove(mut c, g)
		c.call(m.guards.spawn_f, f64(tile_x * 16), f64(tile_y * 16 - 1))
		c.set(m.guards.face(g), face)
		c.set(m.gf(g, 'first'), first)
		c.set(m.gf(g, 'count'), count)
		c.set(m.gf(g, 'wp'), if count > 1 { 1 } else { 0 })
		c.set(m.gf(g, 'stale'), true)
		m.ai.start(mut c, g, 'patrol')
		m.guards.sprite(g).put(mut c, 'guard', tile_x * 16, tile_y * 16 - 1, 1)
		game.sprite(5 + g).put(mut c, 'mark', 0, 0, 2)
		game.sprite(5 + g).hide(mut c)

		if g == guard_count - 1 {
			// All set: the mission begins. Until now the end screen of the last one
			// was up and the guards that were alive were still.
			c.set(m.phase, 0)
			c.set(m.level, 0)
			c.set(m.shown, 9)
		}
		c.end() // this guard
	}
}

// define_init writes what runs once: the room is asked for and the text
// that never changes is written.
fn (mut m Mission) define_init() {
	mut game := m.game
	m.define_setup()
	// guide:gg_init
	mut c := game.define_init()
	game.load_room(mut c, m.room)
	c.set(m.setup_due, guard_count + 1)
	c.set(m.clear_at, 0)
	m.player.put(mut c, 'player', 0, 0, 1)
	m.hud.print(mut c, 0, 0, 'TIME')
	m.hud.print(mut c, 6, 0, ':')
	m.hud.print(mut c, 0, 1, 'SEEN')
	// guide:end
}

// define_update writes what runs every frame.
fn (mut m Mission) define_update() {
	mut game := m.game
	mut c := game.define_update()
	i := c.local_u16('i')
	k := c.local_u16('k')
	g := c.local_u16('g')

	// While a room is loading the picture is blank; only keep the camera on
	// the figure, so that it is right when the picture comes back.
	// guide:gg_update
	c.if_(game.loading)
	game.camera_follow(mut c, m.pcx(), m.pcy())

	// The lit tiles of the last mission are forgotten, a slice a frame.
	c.for_(k, m.clear_at, m.clear_at.add(128).min(room_cols * room_rows))
	c.set(m.lit.at(k), 0)
	c.end() // each tile of a slice
	c.set(m.clear_at, m.clear_at.add(128))
	c.ret_void()
	c.end() // loading

	c.if_(m.setup_due.ne(0))
	c.call(m.setup, jaggame.lit(guard_count + 1).as_(.u8).sub(m.setup_due)) // 0, then 1 for the first guard
	c.dec(m.setup_due)
	c.end() // the first frames of a room

	c.if_(m.phase.eq(0))
	m.define_figure(mut c)
	// guide:end

	// The guards think, each in its state; then one cone is worked out.
	// guide:gg_guards
	m.guards.each(mut c, i)
	m.ai.run(mut c, i)

	c.end() // each guard

	c.for_(k, 0, guard_count)
	c.set(g, game.frame.add(k).and(3).as_(.u16))

	c.if_(m.guards.live(g).both(m.gf(g, 'stale')))
	c.call(m.cone, g)
	c.break_()
	c.end() // a cone to work out
	c.end() // each guard, from a different one every frame
	// guide:end

	// The clock.
	c.inc(m.clock)
	c.inc(m.sub)

	c.if_(m.sub.ge(game.fps))
	c.set(m.sub, 0)
	c.inc(m.secs)
	c.end() // a second
	c.end() // playing

	m.define_sprites(mut c, i)
	m.define_hud(mut c)
	game.camera_follow(mut c, m.pcx(), m.pcy())
}

// define_figure writes the figure's part of the update: walking, running,
// crouching, knocking, the exit.
fn (mut m Mission) define_figure(mut c jaggame.Code) {
	mut game := m.game
	speed := c.local_fix('speed')
	dx := c.local_fix('dx')
	dy := c.local_fix('dy')
	probe_x := c.local_i32('probe_x')
	probe_y := c.local_i32('probe_y')
	c.set(m.crouched, game.held(.b))
	c.set(speed, walk_speed)

	c.if_(game.held(.a))
	c.set(speed, run_speed)
	c.end() // running

	c.if_(m.crouched)
	c.set(speed, crouch_speed)
	c.end() // crouching

	c.if_(game.held(.up))
	c.set(dy, speed.neg())
	c.set(m.facing, 1)
	c.end()

	c.if_(game.held(.down))
	c.set(dy, speed)
	c.set(m.facing, 0)
	c.end()

	c.if_(game.held(.left))
	c.set(dx, speed.neg())
	c.set(m.facing, 2)
	c.end()

	c.if_(game.held(.right))
	c.set(dx, speed)
	c.set(m.facing, 3)
	c.end()

	game.move_and_slide(mut c, m.px, m.py, player_box, dx, dy)
	c.set(m.pcell, m.pcy().shr(4).mul(room_cols).add(m.pcx().shr(4)).as_(.u16))
	moving := dx.ne(0).either(dy.ne(0))

	// Running is heard: a noise at the figure every eighth frame.
	c.if_(moving.both(speed.eq(run_speed)).both(game.frame.and(7).eq(0)))
	game.noise(mut c, m.pcx(), m.pcy(), run_hearing)
	c.end() // running

	// A knock on the wall the figure faces is heard further.
	c.if_(game.pressed(.c))
	c.set(probe_x, m.pcx())
	c.set(probe_y, m.pcy())

	c.if_(m.facing.eq(0))
	c.add_to(probe_y, 12)
	c.else_if(m.facing.eq(1))
	c.sub_from(probe_y, 12)
	c.else_if(m.facing.eq(2))
	c.sub_from(probe_x, 12)
	c.else_()
	c.add_to(probe_x, 12)
	c.end() // which way

	c.if_(game.solid_at(probe_x, probe_y))
	game.noise(mut c, m.pcx(), m.pcy(), knock_hearing)
	c.set(m.flash, 40)
	c.end() // a wall to knock on
	c.end() // C pressed

	// guide:gg_animate
	// The figure walks while it moves, and stands when it does not; a
	// crouching figure holds a pose. What should be playing is worked out
	// each frame, and the animation is started only when that changes.
	directions := ['down', 'up', 'left', 'right']
	want := c.local_u8('want')
	c.set(want, 0)

	c.if_(m.crouched)
	c.set(want, 9)
	c.set(m.player.frame, m.facing.mul(4).add(3))
	c.else_if(moving)
	c.set(want, m.facing.add(1))

	c.if_(speed.eq(run_speed))
	c.set(want, want.add(4))
	c.end() // running
	c.end() // crouching, moving or standing

	c.if_(want.ne(m.playing))
	c.set(m.playing, want)
	m.player.stop(mut c)

	c.if_(want.eq(0))
	c.set(m.player.frame, m.facing.mul(4))
	c.end() // standing
	for d, name in directions {
		for run in [false, true] {
			which := 1 + d + if run { 4 } else { 0 }

			c.if_(want.eq(which))
			m.player.play(mut c, '${if run { 'run' } else { 'walk' }}_${name}', true)
			c.end()
		}
	}
	c.end() // something else to play
	// guide:end

	// guide:gg_world
	c.set(m.player.x, m.px.as_(.i16))
	c.set(m.player.y, m.py.as_(.i16))

	// What is under the middle of the figure: the exit.
	c.if_(game.flags_at(m.pcx(), m.pcy()).and(jaggame.flag_exit).ne(0))
	c.set(m.phase, 1)
	c.end() // on the exit pad
	// guide:end
}

// define_sprites keeps the guards' sprites and the signs over their heads
// with the guards.
fn (mut m Mission) define_sprites(mut c jaggame.Code, i jaggame.Expr) {
	mut game := m.game
	c.set(m.level, 0)
	m.guards.each(mut c, i)
	s := m.guards.sprite(i)
	mark := game.sprite_at(i.add(5))
	state := m.ai.state_of(i)
	c.set(s.x, m.guards.x(i).as_(.i16))
	c.set(s.y, m.guards.y(i).as_(.i16))
	c.set(s.frame,
		m.art_row.at(m.guards.face(i).shr(6)).mul(3).add(m.gf(i, 'moving').as_(.u8).mul(game.frame.shr(3).and(1).as_(.u8).add(1))))

	c.if_(state.eq(0).either(state.eq(4)))
	c.set(mark.visible, false)
	c.else_()
	c.set(mark.visible, true)
	c.set(mark.x, m.guards.x(i).as_(.i16))
	c.set(mark.y, m.guards.y(i).as_(.i16).sub(13))
	c.set(mark.frame, state.eq(2).as_(.u8))

	c.if_(state.eq(2))
	c.set(m.level, 2)
	c.else_if(m.level.eq(0))
	c.set(m.level, 1)
	c.end() // the most alarmed guard
	c.end() // calm or not
	c.end() // each guard
}

// define_hud writes the clock, the alert indicator and the end screen.
fn (mut m Mission) define_hud(mut c jaggame.Code) {
	mut game := m.game

	// The numbers are written when they change.
	c.if_(m.secs.ne(m.secs_on))
	c.set(m.secs_on, m.secs)
	m.hud.number(mut c, 5, 0, m.secs.div(60), 1)
	m.hud.number(mut c, 7, 0, m.secs.mod(60).div(10), 1)
	m.hud.number(mut c, 8, 0, m.secs.mod(10), 1)
	c.end() // the clock

	c.if_(m.seen.ne(m.seen_on))
	c.set(m.seen_on, m.seen)
	m.hud.number(mut c, 5, 1, m.seen, 3)
	c.end() // times seen

	// The alert indicator, in a colour that says it too.
	c.if_(m.phase.eq(0).both(m.level.ne(m.shown)))
	c.set(m.shown, m.level)

	c.if_(m.level.eq(0))
	c.set(m.status.colour, jaggame.cry(90, 240, 140))
	m.status.print(mut c, 0, 0, 'CALM    ')
	c.else_if(m.level.eq(1))
	c.set(m.status.colour, jaggame.cry(255, 196, 40))
	m.status.print(mut c, 0, 0, 'CAUTION ')
	c.else_()
	c.set(m.status.colour, jaggame.cry(255, 70, 56))
	m.status.print(mut c, 0, 0, 'ALERT!  ')
	c.end() // which level
	c.end() // the level changed

	// The end of the mission.
	c.if_(m.phase.ne(0).both(m.shown.ne(3)))
	c.set(m.shown, 3)

	c.if_(m.phase.eq(1))
	m.msg.print(mut c, 4, 1, 'MISSION COMPLETE')
	m.msg.print(mut c, 4, 3, 'TIME')
	m.msg.number(mut c, 10, 3, m.secs.div(60), 1)
	m.msg.print(mut c, 11, 3, ':')
	m.msg.number(mut c, 12, 3, m.secs.mod(60).div(10), 1)
	m.msg.number(mut c, 13, 3, m.secs.mod(10), 1)
	m.msg.print(mut c, 4, 4, 'SEEN')
	m.msg.number(mut c, 10, 4, m.seen, 3)
	c.else_()
	m.msg.print(mut c, 4, 1, 'YOU WERE CAUGHT')
	c.end() // done or caught
	m.msg.print(mut c, 2, 6, 'PRESS A TO PLAY AGAIN')
	m.status.print(mut c, 0, 0, '        ')
	c.end() // the mission just ended

	c.if_(m.phase.ne(0).both(game.pressed(.a).either(game.pressed(.pause))))
	game.load_room(mut c, m.room)
	c.set(m.setup_due, guard_count + 1)
	c.set(m.clear_at, 0)
	c.end() // again
}
