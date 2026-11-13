// GHOSTGRID, the first mission: a figure sneaks through a depot to the exit
// pad. Four guards patrol it, each with a cone of sight that is lit on the
// floor, that walls cut and that is exactly what sees you. You can walk,
// run (guards hear it), crouch behind a cover block (guards cannot see
// you there) and knock on a wall (a guard comes to look). There is no
// assembly in this file: the game is described to jaggame, which checks it,
// compiles it and writes the image.
//
//     v run demos/ghostgrid          # writes demos/ghostgrid.jag
//
// docs/jaggame/guide.md walks through it: chapter 3 the figure and the
// room, chapter 4 the guards. The pictures are made by
// demos/ghostgrid/art/make_art.v and imported from there. The guards'
// states are in guards.v.
//
//   D-pad   walk
//   A       run: faster, and a guard within five tiles hears it
//   B       crouch: slow and quiet; hidden from a guard behind a cover block
//   C       knock on the wall you face: a guard within seven tiles comes
//   Pause   (or A) after the mission: play again
module main

import os
import jaggame

const walk_speed = 1.5 // pixels a frame
const run_speed = 3.0 // with A held
const crouch_speed = 0.75 // with B held
const player_box = jaggame.Hitbox{3, 4, 10, 10} // the part of the figure that collides

const tile_floor = 0
const tile_wall = 1
const tile_cover = 2
const tile_exit = 3
const tile_floor_lit = 4 // the floor in a guard's cone
const tile_exit_lit = 5

const room_cols = 40
const room_rows = 26
const room_cells = 1040 // room_cols * room_rows; a plain number because V 0.5.2 cannot pass a computed constant as a Val

const run_hearing = 80 // a running figure is heard this many pixels away
const knock_hearing = 112 // a knock is heard this far: seven tiles

// depot is bigger than the screen both ways (40 by 26 tiles of 16 pixels).
// # wall, c cover block, . floor, @ where the figure starts, X the exit pad;
// the digits are the guards' waypoints: 1 and 2 are the first guard's
// route, 3 and 4 the second's, 5 the sentinel's post, 6 to 9 the fourth
// guard's loop. , and ; are the lit floor and the lit exit pad: they are
// never in the text, they are the tiles a cone changes the floor into.
// guide:gg_depot
const depot = '
########################################
#...................##....#............#
#.6...............7.##....#............#
#....########.......##....#.........X..#
#....########.......##....#............#
#....########.......##....#............#
#....########.......##....#............#
#...................##....#............#
#.9...............8.##....########..####
#.............###...##............c....#
#...................##.................#
#.......cc..........##............5....#
#...................##..#####..........#
#..#####............##..#####..........#
#...................##.................#
#...................##.................#
#..........cc.......##.3......cc.......#
#..1.............2.....................#
#..........................###.........#
#...................##.....###.........#
#...ccc.............##...........cc....#
#...................##.................#
#...................##.4...............#
#.@.................##.................#
#...................##.................#
########################################
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
