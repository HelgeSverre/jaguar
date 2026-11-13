// GHOSTGRID, the start of it: a figure walks through training rooms that
// are drawn from text, the camera follows, walls stop it and it slides
// along them, chips are picked up and counted, and the exit pad loads the
// next room. There is no assembly in this file: the game is described to
// jaggame, which checks it, compiles it and writes the image.
//
//     v run demos/ghostgrid          # writes demos/ghostgrid.jag
//
// docs/jaggame/guide.md, chapter 3, walks through this file. The pictures
// are made by demos/ghostgrid/art/make_art.v and imported from there.
module main

import os
import jaggame

const walk_speed = 1.5 // pixels a frame
const run_speed = 3.0 // with a fire button held
const player_box = jaggame.Hitbox{3, 4, 10, 10} // the part of the figure that collides

const tile_floor = 0
const tile_wall = 1
const tile_cover = 2
const tile_exit = 3
const tile_chip = 4

// hall is bigger than the screen both ways (34 by 24 tiles of 16 pixels).
// # wall, c cover block, . floor, @ where the player starts, o a chip,
// X the exit pad.
const hall = '
##################################
#@.....#..........#..............#
#......#..........#..............#
#..cc..#....o.....#....c.c.c.....#
#......#..........#..............#
#......#####..#####......#####...#
#................................#
#................................#
######..#########....########..###
#......#.........#..#........#...#
#......#.........#..#........#...#
#.o....#....c....#..#...o....#...#
#......#.........#..#........#...#
#......#.........#..#........#...#
#......####..#####..####..####...#
#................................#
#................................#
#.....cc.........................#
#.....cc.....##########..........#
#............#........#..........#
#..o.........#...c....#.......X..#
#............#........#..........#
#............#........#..........#
##################################
'

// annex is smaller than the screen (14 by 10 tiles), so the camera centres it.
// guide:gg_annex
const annex = '
##############
#@...........#
#..c.....c...#
#............#
#....####....#
#....#..#..o.#
#....#..#....#
#............#
#..c.......X.#
##############
'

// guide:end

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/ghostgrid.jag' }
	img := build() or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(output, img.bytes) or {
		eprintln(err)
		exit(1)
	}
	println('${output}: ${img.bytes.len} bytes')
}

// build compiles the game into an image. The test builds it too.
fn build() !jaggame.Image {
	mut g := describe()
	return g.build()!
}

// art_dir is where the pictures are, next to this file.
fn art_dir() string {
	return os.join_path(os.dir(@FILE), 'art')
}

// describe describes everything: pictures, rooms, text, and what happens at
// start-up and in each frame.
fn describe() &jaggame.Game {
	mut game := jaggame.new_game(jaggame.Config{
		sprites:    2
		layers:     2
		background: jaggame.cry(6, 8, 20)
	})

	// guide:gg_declare
	game.tileset(os.join_path(art_dir(), 'tiles.png'))
	game.png_pal('player', os.join_path(art_dir(), 'player.png'), 16, 16)

	game.legend_tile(`.`, tile_floor, 0)
	game.legend_tile(`#`, tile_wall, jaggame.flag_solid)
	game.legend_tile(`c`, tile_cover, jaggame.flag_solid | jaggame.flag_cover)
	game.legend_tile(`X`, tile_exit, jaggame.flag_exit)
	game.legend_marker(`@`, 'start', tile_floor, 0)
	game.legend_marker(`o`, 'chip', tile_chip, jaggame.flag_item)
	training_hall := game.room('hall', hall)
	training_annex := game.room('annex', annex)
	// guide:end

	// The figure's animations: frame 0 of each direction stands, 1 and 2 are
	// the two steps. Running is the same walk, faster.
	// guide:gg_animations
	directions := ['down', 'up', 'left', 'right']
	for d, name in directions {
		first := d * 3
		game.sequence('walk_${name}', [jaggame.Step{first + 1, 0.14},
			jaggame.Step{first, 0.14}, jaggame.Step{first + 2, 0.14},
			jaggame.Step{first, 0.14}])
		game.sequence('run_${name}', [jaggame.Step{first + 1, 0.07},
			jaggame.Step{first, 0.07}, jaggame.Step{first + 2, 0.07},
			jaggame.Step{first, 0.07}])
	}
	// guide:end

	// guide:gg_variables
	hud := game.text_layer('hud', jaggame.TextConfig{
		columns: 16
		rows:    3
		x:       8
		y:       8
		colour:  jaggame.cry(255, 225, 90)
	})
	px := game.p.fix('px') // the figure's position in the world, pixels
	py := game.p.fix('py')
	facing := game.p.u8('facing') // 0 down, 1 up, 2 left, 3 right
	playing :=
		game.p.u8('playing') // the animation that runs: 1 + direction + 4 for running; 0 none
	chips := game.p.u8('chips') // picked up in this room
	total := game.p.u8('total') // in this room
	player := game.sprite(0)
	// guide:end

	// guide:gg_init
	mut c := game.define_init()
	game.load_room(mut c, training_hall)
	enter_room(mut c, mut game, px, py, chips, total)
	player.put(mut c, 'player', px.as_(.i16), py.as_(.i16), 1)
	hud.print(mut c, 0, 0, 'CHIPS')
	hud.print(mut c, 8, 0, '/')
	hud.print(mut c, 0, 2, 'ROOM')
	// guide:end

	// guide:gg_update
	c = game.define_update()

	// While a room is loading the picture is blank; only keep the camera on
	// the figure, so that it is right when the picture comes back.
	c.if_(game.loading)
	game.camera_follow(mut c, px.add(8).as_(.i32), py.add(9).as_(.i32))
	c.ret_void()
	c.end()

	speed := c.local_fix('speed')
	dx := c.local_fix('dx')
	dy := c.local_fix('dy')
	c.set(speed, walk_speed)

	c.if_(game.held(.fire))
	c.set(speed, run_speed)
	c.end()

	c.if_(game.held(.up))
	c.set(dy, speed.neg())
	c.set(facing, 1)
	c.end()

	c.if_(game.held(.down))
	c.set(dy, speed)
	c.set(facing, 0)
	c.end()

	c.if_(game.held(.left))
	c.set(dx, speed.neg())
	c.set(facing, 2)
	c.end()

	c.if_(game.held(.right))
	c.set(dx, speed)
	c.set(facing, 3)
	c.end()

	game.move_and_slide(mut c, px, py, player_box, dx, dy)
	// guide:end

	// guide:gg_animate
	// The figure walks while it moves, and stands when it does not. The
	// animation is started once, when the direction or the speed changes.
	moving := dx.ne(0).either(dy.ne(0))
	for d, name in directions {
		for run in [false, true] {
			which := 1 + d + if run { 4 } else { 0 }
			speed_is := if run { speed.eq(run_speed) } else { speed.eq(walk_speed) }

			c.if_(moving.both(facing.eq(d)).both(speed_is).both(playing.ne(which)))
			c.set(playing, which)
			player.play(mut c, '${if run { 'run' } else { 'walk' }}_${name}', true)
			c.end()
		}
	}

	c.if_(moving.invert().both(playing.ne(0)))
	c.set(playing, 0)
	player.stop(mut c)
	c.set(player.frame, facing.mul(3))
	c.end()
	// guide:end

	// guide:gg_world
	c.set(player.x, px.as_(.i16))
	c.set(player.y, py.as_(.i16))
	game.camera_follow(mut c, px.add(8).as_(.i32), py.add(9).as_(.i32))

	// What is under the middle of the figure: a chip to pick up, or the exit.
	here_x := c.local_i32('here_x')
	here_y := c.local_i32('here_y')
	here := c.local_u8('here')
	c.set(here_x, px.add(8).as_(.i32))
	c.set(here_y, py.add(9).as_(.i32))
	c.set(here, game.flags_at(here_x, here_y))

	c.if_(here.and(jaggame.flag_item).ne(0))
	game.set_tile(mut c, here_x.shr(4), here_y.shr(4), tile_floor)
	c.inc(chips)
	c.end()

	c.if_(here.and(jaggame.flag_exit).ne(0))
	c.if_(game.room_number.eq(0))
	game.load_room(mut c, training_annex)
	c.else_()
	game.load_room(mut c, training_hall)
	c.end() // which room
	enter_room(mut c, mut game, px, py, chips, total)
	c.end() // on the exit pad

	hud.number(mut c, 6, 0, chips, 2)
	hud.number(mut c, 9, 0, total, 2)
	hud.number(mut c, 6, 2, game.room_number.add(1), 2)
	// guide:end
	return game
}

// enter_room puts the figure on the start of the room that was just asked
// for and counts its chips. The room's size and markers are right as soon as
// `load_room` has been called; its tiles come a few frames later.
fn enter_room(mut c jaggame.Code, mut game jaggame.Game, px jaggame.Expr, py jaggame.Expr, chips jaggame.Expr, total jaggame.Expr) {
	c.set(px, game.marker_x('start', 0).mul(jaggame.tile_size).as_(.fix))
	c.set(py, game.marker_y('start', 0).mul(jaggame.tile_size).as_(.fix))
	c.set(chips, 0)
	c.set(total, game.marker_count('chip'))
}
