module main

import jaggame
import os

// Mission is the game's variables and functions, so that the figure, the
// guards, the cameras and the update can share them. Everything here is a
// variable or a function of the jaggame program; the game itself runs from
// that.
struct Mission {
mut:
	game  &jaggame.Game
	world World
	// the figure
	px       jaggame.Expr // the figure's position in the world, pixels (top left of the picture)
	py       jaggame.Expr
	facing   jaggame.Expr // 0 down, 1 up, 2 left, 3 right
	playing  jaggame.Expr // the animation that runs: 1 + direction + 4 for running; 9 crouching; 0 none
	crouched jaggame.Expr
	clear_at jaggame.Expr // the next tile of `lit` to clear while a room loads
	pcell    jaggame.Expr // the tile the figure is on: row * columns + column
	flash    jaggame.Expr // frames the word KNOCK stays on the HUD
	// the mission
	mission     jaggame.Expr  // the mission being played, from 0
	room_at     jaggame.Expr  // the room of the mission the figure is in, from 0
	entering    jaggame.Expr  // how the figure came into the room: 0 at the start, 1 by a door onward, 2 by a door back
	phase       jaggame.Expr  // 0 playing, 1 done, 2 caught, 3 out of time
	clock       jaggame.Timer // a stopwatch: the frames of play
	secs        jaggame.Expr  // whole seconds of play
	secs_on     jaggame.Expr  // the seconds the HUD shows
	seen_on     jaggame.Expr  // the times seen the HUD shows
	seen        jaggame.Expr  // times a guard or a camera noticed the figure
	alerts      jaggame.Expr  // times a guard went to chase the figure
	level       jaggame.Expr  // 0 calm, 1 someone is suspicious or searching, 2 someone is chasing
	shown       jaggame.Expr  // the level on the status line, 3 when the mission is over
	paused      jaggame.Expr  // the pause menu is up: the mission stands still
	stride      jaggame.Expr  // frames since the last footstep
	worked      jaggame.Expr  // a cone was worked out this frame
	chips_left  jaggame.Expr  // the data chips still to take in this room
	chips_total jaggame.Expr  // the chips the mission's room had
	chips_on    jaggame.Expr  // the chips the HUD shows
	left_on     jaggame.Expr  // the seconds left that the HUD shows
	secs_at     jaggame.Expr  // the frame of the stopwatch at which the next second is complete
	left_secs   jaggame.Expr  // the seconds left, counted up to the next whole one
	left_edge   jaggame.Expr  // the frames left at which that becomes one less
	limit       jaggame.Timer // the countdown of a timed mission
	// the result and the record
	score    jaggame.Expr // seconds, and 5 for each time seen, and 15 for each alert
	rank     jaggame.Expr // 4 S, 3 A, 2 B, 1 C
	best_up  jaggame.Expr // the mission select shows the saved record
	new_best jaggame.Expr // this mission was the best time so far
	unlocked jaggame.Expr // how many missions are open
	bests    jaggame.Expr // for each mission: the best rank in the top four bits and the best time in seconds below
	page     jaggame.Expr // the page of the mission select
	has_next jaggame.Expr // there is a mission after this one and it is open
	// what the cones light
	lit      jaggame.Expr // a word for each tile: bit s is set if source s's cone is on it (guards 0..3, cameras 4..6)
	old_cell jaggame.Expr // the cells of each source's cone: cone_slots for each
	// tables
	ms_first  jaggame.Expr // each mission: its first room
	ms_rooms  jaggame.Expr // and how many it has
	ms_limit  jaggame.Expr // and its limit in seconds
	ms_rank_s jaggame.Expr // and the scores that earn S, A and B
	ms_rank_a jaggame.Expr
	ms_rank_b jaggame.Expr
	rm_guards jaggame.Expr // each room: its number of guards
	g_first   jaggame.Expr // each room and guard: its first waypoint, how many it has and the way it starts
	g_count   jaggame.Expr
	g_face    jaggame.Expr
	rm_cams   jaggame.Expr // each room: its number of cameras
	c_tx      jaggame.Expr // each room and camera: its tile, its first angle and its number of positions
	c_ty      jaggame.Expr
	c_a0      jaggame.Expr
	c_n       jaggame.Expr
	wp_x      jaggame.Expr // the tile of each waypoint
	wp_y      jaggame.Expr
	flow      jaggame.Expr // fields of directions, a room of them for each waypoint
	view_at   jaggame.Expr // where the cone of a tile and a facing starts in its room's part of the pool of cells
	view_len  jaggame.Expr // how many cells it has
	pool_base jaggame.Expr // where each room's part of the pool starts
	pool_cell jaggame.Expr // the cells of all the cones, as row * columns + column
	dir_x     jaggame.Expr
	dir_y     jaggame.Expr
	dim_of    jaggame.Expr // the tile that a lit tile goes back to
	glow_of   jaggame.Expr // the tile that shows a tile under a cone
	art_row   jaggame.Expr
	// the guards and the cameras
	guards      &jaggame.Actors
	cams        &jaggame.Actors
	ai          &jaggame.Machine
	hud         jaggame.TextLayer
	status      jaggame.TextLayer
	msg         jaggame.TextLayer
	player      jaggame.Sprite
	panel       jaggame.Sprite
	medal       jaggame.Sprite
	scenes      &jaggame.Scenes
	save        jaggame.Save
	picker      jaggame.Menu // the mission select
	pause       jaggame.Menu // the pause menu
	win         jaggame.Menu // the menu on the result screen of a mission done
	lose        jaggame.Menu // and of a mission failed
	watch       jaggame.Func // the guard sees the figure, a bool
	chase       jaggame.Func // move towards a point; true when there
	follow      jaggame.Func // one step along the route; true when at the waypoint
	around      jaggame.Func // walk to the spot and look around; true when done
	moved       jaggame.Func // a guard has moved or turned: its cone may be out of date
	cone        jaggame.Func // work out a guard's cone and light its new cells
	light       jaggame.Func // light a cone's new cells and put out its old ones
	setup       jaggame.Func // put everything at the start
	think       jaggame.Func // a camera's frame
	call_guards jaggame.Func // the guards near a camera come to the figure
}

// the sprites of the pool
const sprite_player = 0
const sprite_guard = 1 // 1..4
const sprite_mark = 5 // 5..8
const sprite_cam = 9 // 9..11
const sprite_panel = 12
const sprite_medal = 13

// describe describes everything: pictures, the rooms, text, and what
// happens at start-up and in each frame.
fn describe() &jaggame.Game {
	mut game := jaggame.new_game(jaggame.Config{
		sprites:    14
		layers:     4
		background: jaggame.cry(6, 8, 20)
	})

	// guide:gg_declare
	game.tileset(os.join_path(art_dir(), 'tiles.png'))
	game.png_pal('player', os.join_path(art_dir(), 'player.png'), 16, 16)
	game.png_pal('guard', os.join_path(art_dir(), 'guard.png'), 16, 16)
	game.png_pal('mark', os.join_path(art_dir(), 'mark.png'), 16, 16)
	game.png_pal('cam', os.join_path(art_dir(), 'cam.png'), 16, 16)
	game.png_cry('medal', os.join_path(art_dir(), 'medal.png'), 24, 24)
	game.art_cry('panel', 28, 16, 1, []u16{len: 28 * 16, init: jaggame.cry(8, 12, 34)})

	game.legend_tile(`.`, tile_floor, 0)
	game.legend_tile(`#`, tile_wall, jaggame.flag_solid)
	game.legend_tile(`c`, tile_cover, jaggame.flag_solid | jaggame.flag_cover)
	game.legend_tile(`X`, tile_exit, jaggame.flag_exit)
	game.legend_tile(`,`, tile_floor_lit, 0)
	game.legend_tile(`;`, tile_exit_lit, jaggame.flag_exit)
	game.legend_tile(`%`, tile_chip_lit, jaggame.flag_item)
	game.legend_tile(`D`, tile_door_next, flag_door)
	game.legend_tile(`d`, tile_door_next_lit, flag_door)
	game.legend_tile(`U`, tile_door_prev, flag_door)
	game.legend_tile(`u`, tile_door_prev_lit, flag_door)
	game.legend_marker(`@`, marker_start, tile_floor, 0)
	game.legend_marker(`[`, marker_from_prev, tile_floor, 0)
	game.legend_marker(`]`, marker_from_next, tile_floor, 0)
	game.legend_marker(`$`, 'chip', tile_chip, jaggame.flag_item)
	for k in 0 .. max_cams {
		game.legend_marker(rune(`A` + k), 'cam${k}', tile_wall, jaggame.flag_solid)
	}
	for k in 1 .. 10 {
		game.legend_marker(rune(`0` + k), waypoint_marker(u8(`0` + k)), tile_floor, 0)
	}
	mut world := new_world(mut game)
	// guide:end
	game.backdrop(jaggame.Backdrop{
		colours: [jaggame.Rgb{30, 110, 255}, jaggame.Rgb{150, 50, 255},
			jaggame.Rgb{20, 210, 190}]
	})
	mut m := new_mission(mut game, mut world)
	m.define_player_animations()
	m.define_sounds()
	m.define_guard_functions()
	m.define_states()
	m.define_cameras()
	m.define_setup()
	m.define_scenes()
	return game
}

// new_mission declares the variables, tables and functions.
fn new_mission(mut game jaggame.Game, mut world World) &Mission {
	world.routes(mut game)
	world.cameras(mut game)
	// The cones, worked out when the game is built: for every tile a guard
	// can stand on and every facing, the tiles it sees, and for every
	// position of a camera's sweep. A cone on the screen is then a table look-up.
	// guide:gg_views
	world.views(mut game)
	// guide:end
	mut p := game.p
	// guide:gg_actors
	guards := game.actors('guards', guard_fields(), max_guards, sprite_guard)
	cams := game.actors('cams', cam_fields(), max_cams, sprite_cam)
	// guide:end
	// guide:gg_screens
	// The text that is not the status line shares one layer: the title, the
	// mission select, the briefing, the pause menu and the result.
	msg := game.text_layer('msg', jaggame.TextConfig{
		columns: 24
		rows:    12
		x:       64
		y:       48
	})
	mut scenes := game.scenes()
	// guide:end
	mut pool_base := []i64{}
	for b in world.rm_pool {
		pool_base << b
	}
	mut ranks := [][]int{len: 3}
	mut limits := []int{}
	mut counts := []int{}
	for def in world.defs {
		limits << def.limit
		counts << def.rooms.len
		for k in 0 .. 3 {
			ranks[k] << def.ranks[k]
		}
	}
	mut m := &Mission{
		game:        game
		world:       world
		px:          p.fix('px')
		py:          p.fix('py')
		facing:      p.u8('facing')
		playing:     p.u8('playing')
		crouched:    p.bool('crouched')
		pcell:       p.u16('pcell')
		clear_at:    p.u16('clear_at')
		flash:       p.u8('flash')
		mission:     p.u8('mission')
		room_at:     p.u8('room_at')
		entering:    p.u8('entering')
		phase:       p.u8('phase')
		clock:       game.timer('clock')
		secs:        p.u16('secs')
		secs_on:     p.u16('secs_on', 65535)
		seen_on:     p.u16('seen_on', 65535)
		seen:        p.u16('seen')
		alerts:      p.u16('alerts')
		level:       p.u8('level')
		shown:       p.u8('shown', 9)
		paused:      p.bool('paused')
		stride:      p.u8('stride')
		worked:      p.bool('worked')
		chips_left:  p.u8('chips_left')
		chips_total: p.u8('chips_total')
		chips_on:    p.u8('chips_on', 255)
		left_on:     p.u16('left_on', 65535)
		secs_at:     p.u16('secs_at')
		left_secs:   p.u16('left_secs')
		left_edge:   p.u16('left_edge')
		limit:       game.timer('limit')
		score:       p.u16('score')
		rank:        p.u8('rank')
		best_up:     p.bool('best_up')
		new_best:    p.bool('new_best')
		unlocked:    p.u16('unlocked', 1)
		bests:       p.array_u16('bests', mission_count)
		page:        p.u8('page')
		has_next:    p.bool('has_next')
		lit:         p.array_u16('lit', room_cells)
		old_cell:    p.array_u16('cone_old_cell', (max_guards + max_cams) * cone_slots)
		ms_first:    p.table_u8('ms_first', world.first)
		ms_rooms:    p.table_u8('ms_rooms', counts)
		ms_limit:    p.table_u16('ms_limit', limits)
		ms_rank_s:   p.table_u16('ms_rank_s', ranks[0])
		ms_rank_a:   p.table_u16('ms_rank_a', ranks[1])
		ms_rank_b:   p.table_u16('ms_rank_b', ranks[2])
		rm_guards:   p.table_u8('rm_guards', world.rm_guards)
		g_first:     p.table_u8('g_first', world.g_first)
		g_count:     p.table_u8('g_count', world.g_count)
		g_face:      p.table_u8('g_face', world.g_face)
		rm_cams:     p.table_u8('rm_cams', world.rm_cams)
		c_tx:        p.table_u8('c_tx', world.c_tx)
		c_ty:        p.table_u8('c_ty', world.c_ty)
		c_a0:        p.table_u8('c_a0', world.c_a0)
		c_n:         p.table_u8('c_n', world.c_n)
		wp_x:        p.table_u8('wp_x', world.wp_x)
		wp_y:        p.table_u8('wp_y', world.wp_y)
		flow:        p.table_u8('flow', world.fields)
		view_at:     p.table_u16('view_at', world.view_at)
		view_len:    p.table_u8('view_len', world.view_len)
		pool_base:   p.table_u32('pool_base', pool_base)
		pool_cell:   p.table_u16('pool_cell', world.pool_cell)
		dir_x:       p.table_i8('dir_x', [1, 0, -1, 0])
		dir_y:       p.table_i8('dir_y', [0, 1, 0, -1])
		dim_of:      p.table_u8('dim_of', [tile_floor, tile_wall, tile_cover, tile_exit, tile_floor,
			tile_exit, tile_chip, tile_chip, tile_door_next, tile_door_next, tile_door_prev,
			tile_door_prev])
		glow_of:     p.table_u8('glow_of', [tile_floor_lit, tile_wall, tile_cover, tile_exit_lit,
			tile_floor_lit, tile_exit_lit, tile_chip_lit, tile_chip_lit, tile_door_next_lit,
			tile_door_next_lit, tile_door_prev_lit, tile_door_prev_lit])
		art_row:     p.table_u8('art_row', [3, 0, 2, 1]) // the sheet's row of a guard facing right, down, left, up
		guards:      guards
		cams:        cams
		ai:          p.machine('guard_ai', guards.records)
		hud:         game.text_layer('hud', jaggame.TextConfig{
			columns: 16
			rows:    2
			x:       8
			y:       8
			colour:  jaggame.cry(255, 225, 90)
		})
		status:      game.text_layer('status', jaggame.TextConfig{
			columns: 8
			rows:    3
			x:       248
			y:       8
			colour:  jaggame.cry(90, 240, 140)
		})
		msg:         msg
		player:      game.sprite(sprite_player)
		panel:       game.sprite(sprite_panel)
		medal:       game.sprite(sprite_medal)
		scenes:      scenes
		// guide:gg_menus
		save:   game.save(2, ['m0', 'm1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7', 'm8', 'm9', 'open'])
		picker: game.menu('picker', msg, 1, 3, ['                    ', '                    ',
			'                    ', '                    ', '                    ', 'NEXT PAGE',
			'BACK'])
		pause:  game.menu('pause', msg, 5, 4, ['RESUME', 'RESTART', 'QUIT'])
		win:    game.menu('win', msg, 3, 9, ['PLAY AGAIN', 'NEXT MISSION', 'MISSION SELECT'])
		lose:   game.menu('lose', msg, 3, 9, ['PLAY AGAIN', 'MISSION SELECT'])
		// guide:end
	}
	m.watch = p.func('watch', [jaggame.Param{'i', .u16}], .bool)
	m.chase = p.func('chase', [jaggame.Param{'i', .u16}, jaggame.Param{'tx', .i32},
		jaggame.Param{'ty', .i32}, jaggame.Param{'speed', .fix}], .bool)
	m.follow = p.func('follow', [jaggame.Param{'i', .u16}, jaggame.Param{'step', .u8}], .bool)
	m.around = p.func('around', [jaggame.Param{'i', .u16}, jaggame.Param{'speed', .fix}], .bool)
	m.moved = p.func('moved', [jaggame.Param{'i', .u16}], .void)
	m.cone = p.func('light_cone', [jaggame.Param{'i', .u16}], .void)
	m.light = p.func('light', [jaggame.Param{'src', .u16}, jaggame.Param{'key', .u16},
		jaggame.Param{'old_n', .u8}], .u8)
	m.setup = p.func('setup', [jaggame.Param{'step', .u8}], .void)
	m.think = p.func('think_camera', [jaggame.Param{'i', .u16}], .void)
	m.call_guards = p.func('call_guards', [jaggame.Param{'i', .u16},
		jaggame.Param{'mode', .u8}], .void)
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

// room_of is the number of the room the figure is in: the mission's first
// room and the room of the mission.
fn (m &Mission) room_of() jaggame.Expr {
	return m.ms_first.at(m.mission).as_(.u16).add(m.room_at.as_(.u16))
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
// route, every camera on its pillar. It runs once a room is loaded, a step a
// frame: the markers and the tables say where everything goes.
fn (mut m Mission) define_setup() {
	mut game := m.game
	mut c := game.p.define(m.setup)
	step := m.setup.arg('step')
	rn := m.room_of()

	c.if_(step.eq(0))
	// where the figure is: the start, or beside the door it came through
	c.if_(m.entering.eq(0))
	c.set(m.px, game.marker_x(marker_start, 0).mul(jaggame.tile_size).as_(.fix))
	c.set(m.py, game.marker_y(marker_start, 0).mul(jaggame.tile_size).as_(.fix))
	c.else_if(m.entering.eq(1))
	c.set(m.px, game.marker_x(marker_from_prev, 0).mul(jaggame.tile_size).as_(.fix))
	c.set(m.py, game.marker_y(marker_from_prev, 0).mul(jaggame.tile_size).as_(.fix))
	c.else_()
	c.set(m.px, game.marker_x(marker_from_next, 0).mul(jaggame.tile_size).as_(.fix))
	c.set(m.py, game.marker_y(marker_from_next, 0).mul(jaggame.tile_size).as_(.fix))
	c.end() // which way in
	c.set(m.facing, 3)
	c.set(m.playing, 0)
	c.set(m.crouched, false)
	c.set(m.flash, 0)
	c.set(m.secs_on, 65535)
	c.set(m.seen_on, 65535)
	c.set(m.chips_on, 255)
	c.set(m.left_on, 65535)
	c.set(m.paused, false)
	c.set(m.stride, 0)
	c.set(m.worked, false)

	// the mission's own counts begin with its first room only
	c.if_(m.entering.eq(0))
	c.set(m.secs, 0)
	c.set(m.seen, 0)
	c.set(m.alerts, 0)
	c.end() // the first room
	c.set(m.chips_total, game.marker_count('chip'))
	c.set(m.chips_left, game.marker_count('chip'))
	m.msg.clear(mut c)
	m.hud.clear(mut c)
	m.status.clear(mut c)
	m.hud.print(mut c, 0, 0, 'TIME')
	m.hud.print(mut c, 6, 0, ':')
	m.hud.print(mut c, 0, 1, 'SEEN')

	c.if_(m.chips_total.gt(0))
	m.status.print(mut c, 0, 1, 'CHIP')
	m.status.print(mut c, 6, 1, '/')
	c.end() // there are chips
	c.if_(m.ms_rooms.at(m.mission).gt(1))
	m.status.print(mut c, 0, 1, 'ROOM')
	m.status.print(mut c, 6, 1, '/')
	m.status.number(mut c, 7, 1, m.ms_rooms.at(m.mission), 1)
	c.end() // several rooms
	c.if_(m.ms_limit.at(m.mission).gt(0))
	m.status.print(mut c, 0, 2, 'LEFT')
	c.end() // a countdown
	m.player.put(mut c, 'player', 0, 0, 1)
	m.panel.hide(mut c)
	m.medal.hide(mut c)
	c.end() // the figure

	for g in 0 .. max_guards {
		slot := rn.mul(max_guards).add(g)
		first := m.g_first.at(slot)

		c.if_(step.eq(1 + g))
		m.guards.remove(mut c, g)
		game.sprite(sprite_mark + g).hide(mut c)

		c.if_(m.rm_guards.at(rn).gt(g))
		tx := m.wp_x.at(first).as_(.i16)
		ty := m.wp_y.at(first).as_(.i16)
		c.call(m.guards.spawn_f, tx.mul(16).as_(.fix), ty.mul(16).sub(1).as_(.fix))
		c.set(m.guards.face(g), m.g_face.at(slot))
		c.set(m.gf(g, 'first'), first)
		c.set(m.gf(g, 'count'), m.g_count.at(slot))
		c.set(m.gf(g, 'wp'), m.g_count.at(slot).gt(1).as_(.u8))
		c.set(m.gf(g, 'stale'), true)
		m.ai.start(mut c, g, 'patrol')
		m.guards.sprite(g).put(mut c, 'guard', tx.mul(16), ty.mul(16).sub(1), 1)
		game.sprite(sprite_mark + g).put(mut c, 'mark', 0, 0, 2)
		game.sprite(sprite_mark + g).hide(mut c)
		c.end() // a guard that is in this room
		c.end() // this guard
	}

	c.if_(step.eq(1 + max_guards))
	for k in 0 .. max_cams {
		m.cams.remove(mut c, k)
	}
	for k in 0 .. max_cams {
		slot := rn.mul(max_cams).add(k)

		c.if_(m.rm_cams.at(rn).gt(k))
		tx := m.c_tx.at(slot).as_(.i16)
		ty := m.c_ty.at(slot).as_(.i16)
		c.call(m.cams.spawn_f, tx.mul(16).as_(.fix), ty.mul(16).as_(.fix))
		c.set(m.cf(k, 'tx'), m.c_tx.at(slot))
		c.set(m.cf(k, 'ty'), m.c_ty.at(slot))
		c.set(m.cf(k, 'a0'), m.c_a0.at(slot))
		c.set(m.cf(k, 'n'), m.c_n.at(slot))
		c.set(m.cf(k, 'stale'), true)
		m.cams.sprite(k).put(mut c, 'cam', tx.mul(16), ty.mul(16), 0)
		c.end() // a camera that is in this room
	}
	// All set: the mission begins. Until now the end screen of the last one
	// was up and everything was still.
	c.set(m.phase, 0)
	c.set(m.level, 0)
	c.set(m.shown, 9)
	c.end() // the cameras
}

// define_play_setup writes the setup of the play scene, a step a frame: while
// the room loads the picture is blank and only the camera is kept on the
// figure, so that it is right when the picture comes back; the lit tiles of
// the last room are forgotten, a slice a frame; then `setup` runs for
// each step, the figure first, then a guard to a frame, then the cameras.
fn (mut m Mission) define_play_setup(mut c jaggame.Code) {
	mut game := m.game
	k := c.local_u16('k')
	// guide:gg_setup
	c.if_(game.loading)
	game.camera_follow(mut c, m.pcx(), m.pcy())
	c.for_(k, m.clear_at, m.clear_at.add(128).min(room_cells))
	c.set(m.lit.at(k), 0)
	c.end() // each tile of a slice
	c.set(m.clear_at, m.clear_at.add(128))
	m.scenes.wait(mut c) // the same step again next frame
	c.ret_void()
	c.end() // loading
	c.call(m.setup, m.scenes.step)
	// guide:end
}

// define_play_update writes what runs every frame of the mission.
fn (mut m Mission) define_play_update(mut c jaggame.Code) {
	mut game := m.game
	i := c.local_u16('i')
	k := c.local_u16('k')
	g := c.local_u16('g')

	// The pause menu takes the frame; nothing else moves.
	// guide:gg_pause
	c.if_(m.paused)
	m.pause.update(mut c)

	c.if_(m.pause.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	c.if_(m.pause.chosen.eq(0).either(m.pause.backed))
	game.play(mut c, 'menu_select')
	m.resume(mut c)
	c.else_if(m.pause.chosen.eq(1))
	game.play(mut c, 'menu_select')
	m.start_mission(mut c, 'play')
	c.else_if(m.pause.chosen.eq(2))
	game.play(mut c, 'menu_select')
	m.scenes.go_fade(mut c, 'picker')
	c.end() // what was chosen
	c.ret_void()
	c.end() // paused

	c.if_(game.pressed(.option).either(game.pressed(.pause)).both(m.phase.eq(0)))
	c.set(m.paused, true)
	c.set(m.limit.running, false)
	c.set(m.clock.running, false)
	m.show_panel(mut c)
	c.set(game.fade, 8)
	m.msg.print(mut c, 9, 2, 'PAUSED')
	m.pause.open(mut c)
	c.ret_void()
	c.end() // pause pressed
	// guide:end

	// The countdown begins with the first frame of the first room, and goes
	// on in the next rooms.
	// guide:gg_limit
	c.if_(m.scenes.time().eq(0))

	c.if_(m.entering.eq(0))
	m.clock.stopwatch(mut c)
	c.set(m.secs_at, game.fps.as_(.u16))
	c.else_()
	c.set(m.clock.running, true)
	c.end() // the start, or another room

	c.if_(m.ms_limit.at(m.mission).gt(0))

	c.if_(m.entering.eq(0))
	m.limit.start(mut c, game.seconds(m.ms_limit.at(m.mission)))
	c.set(m.left_secs, m.ms_limit.at(m.mission))
	c.set(m.left_edge, game.seconds(m.ms_limit.at(m.mission)).sub(game.fps.as_(.u16)))
	c.else_()
	c.set(m.limit.running, true)
	c.end() // the start, or another room
	c.end() // a countdown
	c.end() // the first frame
	// guide:end

	// guide:gg_update
	c.if_(m.phase.eq(0))
	m.define_figure(mut c)
	// guide:end

	// The guards think, each in its state; then a cone is worked out.
	// guide:gg_guards
	m.guards.each(mut c, i)
	m.ai.run(mut c, i)

	c.end() // each guard

	c.set(m.worked, false)
	c.for_(k, 0, max_guards)
	c.set(g, game.frame.add(k).and(3).as_(.u16))

	c.if_(m.guards.live(g).both(m.gf(g, 'stale')))
	c.call(m.cone, g)
	c.set(m.worked, true)
	c.break_()
	c.end() // a cone to work out
	c.end() // each guard, from a different one every frame
	// guide:end

	// The cameras look and sweep; a cone moves only in a frame in which no guard's did.
	m.cams.each(mut c, i)
	c.call(m.think, i)
	c.end() // each camera

	// The clock.
	c.if_(m.clock.elapsed.ge(m.secs_at))
	c.inc(m.secs)
	c.set(m.secs_at, m.secs_at.add(game.fps.as_(.u16)))
	c.end() // a second

	c.if_(m.left_secs.gt(0).both(m.limit.left.le(m.left_edge)))
	c.dec(m.left_secs)
	c.set(m.left_edge, m.left_edge.sub(game.fps.as_(.u16)))
	c.end() // a second off the countdown

	c.if_(m.limit.fired)
	c.set(m.phase, 3)
	c.end() // out of time
	c.end() // playing

	c.if_(m.phase.ne(0))
	c.set(m.clock.running, false)
	// the time of the result, worked out from the frames once
	c.set(m.secs, game.whole_seconds(m.clock.elapsed).as_(.u16))
	c.end() // the mission is over

	m.define_sprites(mut c, i)
	m.define_hud(mut c)
	game.camera_follow(mut c, m.pcx(), m.pcy())

	// The music follows the alarm: the alert track while a guard is chasing, the calm
	// one when none is suspicious; while one is only suspicious, whichever plays.
	// guide:gg_music
	c.if_(m.level.eq(2))
	game.music_play(mut c, 'alert')
	c.else_if(m.level.eq(0))
	game.music_play(mut c, 'calm')
	c.end() // the level
	// guide:end

	// The mission is over: the result.
	c.if_(m.phase.ne(0))
	m.scenes.go(mut c, 'result')
	c.end() // the end
}

// show_panel puts the dark panel behind the text of a menu: a small solid
// picture, scaled up, above every sprite of the room.
fn (m &Mission) show_panel(mut c jaggame.Code) {
	m.panel.put(mut c, 'panel', 54, 40, 3)
	c.set(m.panel.scale, 7.5)
	c.set(m.panel.fixed, true)
}

// resume puts the mission going again after the pause menu.
fn (m &Mission) resume(mut c jaggame.Code) {
	c.set(m.paused, false)
	c.set(m.panel.visible, false)
	c.set(m.game.fade, 16)
	c.set(m.clock.running, true)
	c.set(m.limit.running, m.ms_limit.at(m.mission).gt(0).both(m.limit.left.gt(0)))
	m.msg.clear(mut c)
}

// start_mission starts the selected mission over from its first room: with
// a fade, or at once.
fn (mut m Mission) start_mission(mut c jaggame.Code, scene string) {
	c.set(m.room_at, 0)
	c.set(m.entering, 0)
	m.scenes.go_fade(mut c, scene)
}

// define_figure writes the figure's part of the update: walking, running,
// crouching, knocking, the chips, the doors, the exit.
fn (mut m Mission) define_figure(mut c jaggame.Code) {
	mut game := m.game
	speed := c.local_fix('speed')
	dx := c.local_fix('dx')
	dy := c.local_fix('dy')
	probe_x := c.local_i32('probe_x')
	probe_y := c.local_i32('probe_y')
	under := c.local_u8('under')
	// guide:gg_figure
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
	// a figure that pushes against a wall does not walk on the spot
	moving := c.local_bool('moving')
	c.set(moving,
		dx.ne(0).both(game.blocked_x().invert()).either(dy.ne(0).both(game.blocked_y().invert())))

	// guide:end

	// Footsteps: a thud every so often while the figure walks or runs, none
	// while it creeps. A running step comes on the frame half way between
	// two of the noises a run makes (below), so that the two are not in one
	// frame.
	// guide:gg_steps
	c.if_(moving.both(m.crouched.invert()))
	c.inc(m.stride)

	c.if_(m.stride.ge(14).either(m.stride.ge(8).both(speed.eq(run_speed)).both(game.frame.and(7).eq(4))))
	c.set(m.stride, 0)

	c.if_(speed.eq(run_speed))
	game.play(mut c, 'run')
	c.else_()
	game.play(mut c, 'step')
	c.end() // run or walk
	c.end() // time for a step
	c.else_()
	c.set(m.stride, 0)
	c.end() // moving
	// guide:end

	// Running is heard: a noise at the figure every eighth frame.
	// guide:gg_noise
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
	game.play(mut c, 'knock')
	c.set(m.flash, 40)
	c.end() // a wall to knock on
	c.end() // C pressed
	// guide:end

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

	// What is under the middle of the figure: a chip, the exit, a door.
	c.set(under, game.flags_at(m.pcx(), m.pcy()))
	// guide:end

	// A chip is taken: the tile is the floor again, lit if a cone is on it.
	// guide:gg_chip
	c.if_(under.and(jaggame.flag_item).ne(0))
	c.dec(m.chips_left)
	game.play(mut c, 'chip')

	c.if_(m.lit.at(m.pcell).and(0x7f).ne(0))
	game.set_tile(mut c, m.pcx().shr(4), m.pcy().shr(4), tile_floor_lit)
	c.else_()
	game.set_tile(mut c, m.pcx().shr(4), m.pcy().shr(4), tile_floor)
	c.end() // lit or not
	c.end() // a chip
	// guide:end

	// The exit pad works when every chip is taken.
	c.if_(under.and(jaggame.flag_exit).ne(0).both(m.chips_left.eq(0)))
	c.set(m.phase, 1)
	c.end() // on the exit pad

	// A door leads to the next room (or back): through black, into the new room.
	// guide:gg_door
	c.if_(under.and(flag_door).ne(0).both(m.phase.eq(0)))
	tile := game.tile_at(m.pcx(), m.pcy())

	c.if_(tile.eq(tile_door_next).either(tile.eq(tile_door_next_lit)))
	c.inc(m.room_at)
	c.set(m.entering, 1)
	c.else_()
	c.dec(m.room_at)
	c.set(m.entering, 2)
	c.end() // onward or back
	game.play(mut c, 'door')
	c.set(m.limit.running, false)
	c.set(m.clock.running, false)
	m.scenes.go_fade(mut c, 'play')
	c.end() // on a door
	// guide:end
}

// define_sprites keeps the guards' sprites and the signs over their heads
// with the guards.
fn (mut m Mission) define_sprites(mut c jaggame.Code, i jaggame.Expr) {
	mut game := m.game
	c.set(m.level, 0)
	m.guards.each(mut c, i)
	s := m.guards.sprite(i)
	mark := game.sprite_at(i.add(sprite_mark))
	state := m.ai.state_of(i)
	m.guards.show(mut c, i, 0, 0)
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

// define_hud writes the clock, the times seen, the chips, the room, the
// countdown, the knock and the alert indicator on the status lines.
fn (mut m Mission) define_hud(mut c jaggame.Code) {
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

	c.if_(m.chips_total.gt(0).both(m.chips_left.ne(m.chips_on)))
	c.set(m.chips_on, m.chips_left)
	m.status.number(mut c, 5, 1, m.chips_total.sub(m.chips_left), 1)
	m.status.number(mut c, 7, 1, m.chips_total, 1)
	c.end() // chips taken

	c.if_(m.ms_rooms.at(m.mission).gt(1))
	m.status.number(mut c, 5, 1, m.room_at.add(1), 1)
	c.end() // the room

	// The countdown shows the seconds left, counted up to the next whole one.
	c.if_(m.ms_limit.at(m.mission).gt(0))

	c.if_(m.left_secs.ne(m.left_on))
	c.set(m.left_on, m.left_secs)
	m.status.number(mut c, 5, 2, m.left_secs, 2)
	c.end() // a new second
	c.end() // a countdown

	// The word KNOCK shows for a moment after a knock.
	c.if_(m.flash.ne(0))

	c.if_(m.flash.eq(40))
	m.hud.print(mut c, 10, 1, 'KNOCK')
	c.end() // just knocked
	c.dec(m.flash)

	c.if_(m.flash.eq(0))
	m.hud.print(mut c, 10, 1, '     ')
	c.end() // gone again
	c.end() // a knock was heard

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
}
