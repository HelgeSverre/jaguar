// GHOSTGRID, a stealth trainer: ten short missions in which a figure sneaks
// through simulated rooms. Guards patrol them with cones of sight that are
// lit on the floor, that walls cut and that are exactly what sees you;
// cameras sweep cones of their own. You can walk, run (guards hear it),
// crouch behind a cover block (guards cannot see you there) and knock on a
// wall (a guard comes to look). There is no assembly in this file: the game
// is described to jaggame, which checks it, compiles it and writes the
// image.
//
//     v run demos/ghostgrid          # writes demos/ghostgrid.jag and demos/ghostgrid.j64
//
// docs/jaggame/guide.md walks through it: chapter 3 the figure and the
// room, chapter 4 the guards, chapter 5 the scenes, the sound and the save,
// chapter 6 how the missions are data. The pictures are made by
// demos/ghostgrid/art/make_art.v and imported from there. The missions are in
// missions.v and the maps in maps.v; the guards' states are in guards.v, the
// cameras' in cameras.v, the scenes in scenes.v, the sound in sound.v.
//
// The game starts on a title; A goes to the mission select, where the pad
// (up, down, A) picks a mission, B goes back and the item NEXT PAGE turns
// to the other five. A briefing follows. In a mission:
//
//   D-pad   walk
//   A       run: faster, and a guard within five tiles hears it
//   B       crouch: slow and quiet; hidden from a guard behind a cover block
//   C       knock on the wall you face: a guard within seven tiles comes
//   Pause   (or Option) pause: resume, restart or quit
//
// The result screen shows the time, the times seen and a rank; the best
// time and rank of each mission, and how many missions are open, are kept on
// the cartridge's EEPROM (the emulator keeps it between runs).
module main

import os
import jaggame

const walk_speed = 1.5 // pixels a frame
const run_speed = 3.0 // with A held
const crouch_speed = 0.75 // with B held
const player_box = jaggame.Hitbox{3, 4, 10, 10} // the part of the figure that collides
const catch_box = jaggame.Hitbox{2, 3, 12, 12} // the part of a guard and of the figure that touches the other

const tile_floor = 0
const tile_wall = 1
const tile_cover = 2
const tile_exit = 3
const tile_floor_lit = 4 // the floor in a cone
const tile_exit_lit = 5
const tile_chip = 6
const tile_chip_lit = 7
const tile_door_next = 8
const tile_door_next_lit = 9
const tile_door_prev = 10
const tile_door_prev_lit = 11

const flag_door = 16 // a tile that leads to another room: jaggame.flag_user1 (a plain number, see room_cells)

const room_cols = 28
const room_rows = 20
const room_cells = 560 // room_cols * room_rows; a plain number because V 0.5.2 cannot pass a computed constant as a Val

const run_hearing = 80 // a running figure is heard this many pixels away
const knock_hearing = 112 // a knock is heard this far: seven tiles

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
	// The same game as a cartridge image, for a board with the EEPROM that
	// keeps the best times (see jaggame/rt_save.v).
	rom := img.cartridge() or {
		eprintln(err)
		exit(1)
	}
	rom_path := output.trim_string_right('.jag') + '.j64'
	os.write_file_array(rom_path, rom) or {
		eprintln(err)
		exit(1)
	}
	println('${rom_path}: ${rom.len} bytes')
}

// build compiles the game into an image. The tests build it too.
fn build() !jaggame.Image {
	mut g := describe()
	return g.build()!
}

// art_dir is where the pictures are, next to this file.
fn art_dir() string {
	return os.join_path(os.dir(@FILE), 'art')
}
