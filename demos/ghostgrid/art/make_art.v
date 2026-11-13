// make_art draws GHOSTGRID's pictures and writes them as PNG files next to
// this file: tiles.png (six tiles of 16x16), player.png (the figure, four
// frames in each of four directions: standing, two steps, crouching),
// guard.png (the guard, three frames in each of four directions) and
// mark.png (the question mark and the exclamation mark that show above a
// guard). They are made here, in code, so that they can be tweaked and made
// again:
//
//     v run demos/ghostgrid/art
//
// The game imports the PNGs (demos/ghostgrid/main.v); this tool is not part
// of it. Everything is simple shapes: a dark floor with a glowing grid, the
// same floor tinted amber where a guard's cone lies, block walls with a lit
// top edge, a cover block, an exit pad, a red figure with a white helmet for
// the player and a broad teal figure with one red lens for a guard.
module main

import os
import jaggame

struct Colour {
	r int
	g int
	b int
}

// The colours. Few and flat: the whole game shares a palette of 256.
const floor_base = Colour{12, 16, 34}
const floor_line = Colour{22, 70, 96}
const floor_node = Colour{40, 140, 170}
const floor_glow = Colour{90, 230, 250}

const wall_body = Colour{52, 60, 94}
const wall_shade = Colour{32, 38, 66}
const wall_panel = Colour{68, 78, 122}
const wall_lit = Colour{150, 170, 232}
const wall_top = Colour{104, 120, 184}

const cover_body = Colour{96, 52, 116}
const cover_dark = Colour{62, 30, 82}
const cover_lit = Colour{178, 118, 208}

const pad_body = Colour{16, 110, 66}
const pad_edge = Colour{80, 250, 150}
const pad_arrow = Colour{210, 255, 225}

const lit_base = Colour{70, 56, 14}
const lit_line = Colour{140, 108, 22}
const lit_node = Colour{214, 170, 44}
const lit_glow = Colour{255, 226, 110}

const guard_suit = Colour{30, 110, 118}
const guard_plate = Colour{86, 178, 180}
const guard_dark = Colour{16, 62, 72}
const guard_cap = Colour{26, 32, 46}
const guard_lens = Colour{255, 64, 40}
const guard_belt = Colour{250, 204, 60}

const mark_ask = Colour{255, 196, 40}
const mark_shout = Colour{255, 70, 56}
const mark_edge = Colour{20, 12, 12}

const suit = Colour{228, 88, 68}
const suit_dark = Colour{150, 52, 44}
const helmet = Colour{240, 236, 228}
const helmet_shade = Colour{176, 172, 168}
const visor = Colour{70, 220, 255}
const boots = Colour{44, 40, 56}

fn main() {
	dir := os.dir(@FILE)
	tiles().save(os.join_path(dir, 'tiles.png')) or {
		eprintln(err)
		exit(1)
	}
	player().save(os.join_path(dir, 'player.png')) or {
		eprintln(err)
		exit(1)
	}
	guard().save(os.join_path(dir, 'guard.png')) or {
		eprintln(err)
		exit(1)
	}
	marks().save(os.join_path(dir, 'mark.png')) or {
		eprintln(err)
		exit(1)
	}
	println('${dir}: tiles.png, player.png, guard.png and mark.png written')
}

fn dot(mut img jaggame.Canvas, x int, y int, col Colour) {
	img.put(x, y, col.r, col.g, col.b, 255)
}

fn rect(mut img jaggame.Canvas, x int, y int, w int, h int, col Colour) {
	img.fill(x, y, w, h, col.r, col.g, col.b)
}

// floor draws the dark floor with its glowing grid in the tile at (ox, oy):
// a dim line along the left and top, and a node of light where they meet.
fn floor(mut img jaggame.Canvas, ox int, oy int) {
	floor_in(mut img, ox, oy, floor_base, floor_line, floor_node, floor_glow)
}

// floor_lit is the floor in a guard's cone: the same grid, in amber.
fn floor_lit(mut img jaggame.Canvas, ox int, oy int) {
	floor_in(mut img, ox, oy, lit_base, lit_line, lit_node, lit_glow)
}

fn floor_in(mut img jaggame.Canvas, ox int, oy int, base Colour, line Colour, node Colour, glow Colour) {
	rect(mut img, ox, oy, 16, 16, base)
	rect(mut img, ox, oy, 1, 16, line)
	rect(mut img, ox, oy, 16, 1, line)
	dot(mut img, ox, oy, glow)
	dot(mut img, ox + 1, oy, node)
	dot(mut img, ox, oy + 1, node)
	dot(mut img, ox + 15, oy, node)
	dot(mut img, ox, oy + 15, node)
}

// wall draws a block: a lit top edge two lines deep, a panel with a frame
// and shaded bottom and right edges.
fn wall(mut img jaggame.Canvas, ox int, oy int) {
	rect(mut img, ox, oy, 16, 16, wall_body)
	rect(mut img, ox, oy + 14, 16, 2, wall_shade)
	rect(mut img, ox + 15, oy, 1, 16, wall_shade)
	rect(mut img, ox + 3, oy + 5, 10, 7, wall_panel)
	rect(mut img, ox + 4, oy + 6, 8, 5, wall_body)
	rect(mut img, ox, oy, 16, 1, wall_lit)
	rect(mut img, ox, oy + 1, 16, 1, wall_top)
	rect(mut img, ox, oy + 2, 1, 12, wall_top)
}

// cover draws a low block with stripes that stands on the floor, a pixel in
// from the edge of its tile.
fn cover(mut img jaggame.Canvas, ox int, oy int) {
	floor(mut img, ox, oy)
	rect(mut img, ox + 1, oy + 2, 14, 13, cover_body)
	for i in 0 .. 4 {
		rect(mut img, ox + 2 + i * 4, oy + 5, 2, 8, cover_dark)
	}
	rect(mut img, ox + 1, oy + 2, 14, 2, cover_lit)
	rect(mut img, ox + 1, oy + 14, 14, 1, cover_dark)
}

// pad draws the exit: a green pad on the floor with an arrow that points
// down and out of the room.
fn pad(mut img jaggame.Canvas, ox int, oy int, lit bool) {
	if lit {
		floor_lit(mut img, ox, oy)
	} else {
		floor(mut img, ox, oy)
	}
	rect(mut img, ox + 2, oy + 2, 12, 12, pad_edge)
	rect(mut img, ox + 3, oy + 3, 10, 10, pad_body)
	rect(mut img, ox + 7, oy + 4, 2, 5, pad_arrow)
	rect(mut img, ox + 5, oy + 8, 6, 1, pad_arrow)
	rect(mut img, ox + 6, oy + 9, 4, 1, pad_arrow)
	rect(mut img, ox + 7, oy + 10, 2, 1, pad_arrow)
}

// tiles is the tile set: floor, wall, cover, exit pad, floor in a cone, exit
// pad in a cone, in that order.
fn tiles() jaggame.Canvas {
	mut img := jaggame.new_canvas(96, 16)
	floor(mut img, 0, 0)
	wall(mut img, 16, 0)
	cover(mut img, 32, 0)
	pad(mut img, 48, 0, false)
	floor_lit(mut img, 64, 0)
	pad(mut img, 80, 0, true)
	return img
}

// Facing is a direction the figure looks.
enum Facing {
	down
	up
	left
	right
}

// figure draws the player in the cell at (ox, oy): a helmet with a visor, a
// body with arms, two legs. `step` is 0 standing, 1 left foot forward, 2
// right foot forward; the arms swing the other way.
fn figure(mut img jaggame.Canvas, ox int, oy int, facing Facing, step int) {
	left_foot := if step == 1 {
		-1
	} else if step == 2 {
		1
	} else {
		0
	}
	right_foot := -left_foot
	match facing {
		.down, .up {
			// Legs, body, arms, helmet.
			rect(mut img, ox + 5, oy + 12 + left_foot, 3, 3, boots)
			rect(mut img, ox + 8, oy + 12 + right_foot, 3, 3, boots)
			rect(mut img, ox + 4, oy + 7, 8, 6, suit)
			rect(mut img, ox + 4, oy + 12, 8, 1, suit_dark)
			rect(mut img, ox + 2, oy + 7 + right_foot, 2, 5, suit_dark)
			rect(mut img, ox + 12, oy + 7 + left_foot, 2, 5, suit_dark)
			rect(mut img, ox + 5, oy + 1, 6, 6, helmet)
			rect(mut img, ox + 5, oy + 6, 6, 1, helmet_shade)
			if facing == .down {
				rect(mut img, ox + 6, oy + 3, 4, 2, visor)
			} else {
				rect(mut img, ox + 6, oy + 2, 4, 1, helmet_shade)
				rect(mut img, ox + 5, oy + 7, 6, 1, suit_dark)
			}
		}
		.left, .right {
			dir := if facing == .left { -1 } else { 1 }
			front := if facing == .left { 0 } else { 2 } // the visor side of the helmet
			rect(mut img, ox + 5, oy + 12, 3, 3, boots)
			rect(mut img, ox + 8 + left_foot * dir, oy + 12, 3, 3, boots)
			rect(mut img, ox + 5, oy + 7, 6, 6, suit)
			rect(mut img, ox + 5, oy + 12, 6, 1, suit_dark)
			rect(mut img, ox + 6 + right_foot * dir, oy + 7, 3, 5, suit_dark)
			rect(mut img, ox + 5, oy + 1, 6, 6, helmet)
			rect(mut img, ox + 5, oy + 6, 6, 1, helmet_shade)
			rect(mut img, ox + 5 + front, oy + 3, 4, 2, visor)
		}
	}
}

// crouch draws the player crouching in the cell at (ox, oy): low and wide,
// the helmet down on the shoulders.
fn crouch(mut img jaggame.Canvas, ox int, oy int, facing Facing) {
	rect(mut img, ox + 3, oy + 10, 10, 5, suit)
	rect(mut img, ox + 3, oy + 14, 10, 1, suit_dark)
	rect(mut img, ox + 2, oy + 11, 2, 3, suit_dark)
	rect(mut img, ox + 12, oy + 11, 2, 3, suit_dark)
	rect(mut img, ox + 5, oy + 6, 6, 5, helmet)
	rect(mut img, ox + 5, oy + 10, 6, 1, helmet_shade)
	match facing {
		.down {
			rect(mut img, ox + 6, oy + 8, 4, 2, visor)
		}
		.up {
			rect(mut img, ox + 6, oy + 7, 4, 1, helmet_shade)
		}
		.left {
			rect(mut img, ox + 5, oy + 8, 4, 2, visor)
		}
		.right {
			rect(mut img, ox + 7, oy + 8, 4, 2, visor)
		}
	}
}

// player is the sheet of the figure: four frames across (standing, left
// foot, right foot, crouching) and a row for each direction: down, up, left,
// right.
fn player() jaggame.Canvas {
	mut img := jaggame.new_canvas(64, 64)
	for row, facing in [Facing.down, .up, .left, .right] {
		for step in 0 .. 3 {
			figure(mut img, step * 16, row * 16, facing, step)
		}
		crouch(mut img, 48, row * 16, facing)
	}
	return img
}

// guard_figure draws a guard in the cell at (ox, oy): broad shoulders, a
// flat dark cap and a single red lens on the side he looks to. `step` is as
// for `figure`.
fn guard_figure(mut img jaggame.Canvas, ox int, oy int, facing Facing, step int) {
	left_foot := if step == 1 {
		-1
	} else if step == 2 {
		1
	} else {
		0
	}
	right_foot := -left_foot
	match facing {
		.down, .up {
			rect(mut img, ox + 4, oy + 12 + left_foot, 3, 3, guard_cap)
			rect(mut img, ox + 9, oy + 12 + right_foot, 3, 3, guard_cap)
			rect(mut img, ox + 3, oy + 6, 10, 7, guard_suit)
			rect(mut img, ox + 3, oy + 11, 10, 1, guard_belt)
			rect(mut img, ox + 3, oy + 12, 10, 1, guard_dark)
			rect(mut img, ox + 1, oy + 6, 14, 3, guard_plate)
			rect(mut img, ox + 1, oy + 8, 14, 1, guard_dark)
			rect(mut img, ox + 1, oy + 9 + right_foot, 2, 4, guard_dark)
			rect(mut img, ox + 13, oy + 9 + left_foot, 2, 4, guard_dark)
			rect(mut img, ox + 4, oy + 1, 8, 5, guard_cap)
			rect(mut img, ox + 3, oy + 5, 10, 1, guard_dark)
			if facing == .down {
				rect(mut img, ox + 6, oy + 3, 4, 2, guard_lens)
				dot(mut img, ox + 6, oy + 3, guard_belt)
			} else {
				rect(mut img, ox + 7, oy + 2, 2, 3, guard_dark)
			}
		}
		.left, .right {
			dir := if facing == .left { -1 } else { 1 }
			front := if facing == .left { 0 } else { 5 }
			rect(mut img, ox + 4, oy + 12, 3, 3, guard_cap)
			rect(mut img, ox + 8 + left_foot * dir, oy + 12, 3, 3, guard_cap)
			rect(mut img, ox + 4, oy + 6, 8, 7, guard_suit)
			rect(mut img, ox + 4, oy + 11, 8, 1, guard_belt)
			rect(mut img, ox + 4, oy + 12, 8, 1, guard_dark)
			rect(mut img, ox + 3, oy + 6, 10, 3, guard_plate)
			rect(mut img, ox + 3, oy + 8, 10, 1, guard_dark)
			rect(mut img, ox + 6 + right_foot * dir, oy + 9, 3, 4, guard_dark)
			rect(mut img, ox + 4, oy + 1, 8, 5, guard_cap)
			rect(mut img, ox + 3, oy + 5, 10, 1, guard_dark)
			rect(mut img, ox + 3 + front, oy + 3, 3, 2, guard_lens)
		}
	}
}

// guard is the sheet of the guard: three frames across and a row for each
// direction: down, up, left, right.
fn guard() jaggame.Canvas {
	mut img := jaggame.new_canvas(48, 64)
	for row, facing in [Facing.down, .up, .left, .right] {
		for step in 0 .. 3 {
			guard_figure(mut img, step * 16, row * 16, facing, step)
		}
	}
	return img
}

// outlined draws a rectangle with a dark edge a pixel wide.
fn outlined(mut img jaggame.Canvas, x int, y int, w int, h int, col Colour) {
	rect(mut img, x - 1, y - 1, w + 2, h + 2, mark_edge)
	rect(mut img, x, y, w, h, col)
}

// marks is the two signs over a guard's head: a question mark (frame 0, he
// noticed something) and an exclamation mark (frame 1, he has seen you).
fn marks() jaggame.Canvas {
	mut img := jaggame.new_canvas(32, 16)
	// ?
	for part in [[5, 2, 6, 2], [10, 4, 2, 3], [7, 7, 4, 2], [7, 9, 2, 2],
		[7, 12, 2, 2]] {
		outlined(mut img, part[0], part[1], part[2], part[3], mark_ask)
	}
	for part in [[5, 2, 6, 2], [10, 4, 2, 3], [7, 7, 4, 2], [7, 9, 2, 2],
		[7, 12, 2, 2]] {
		rect(mut img, part[0], part[1], part[2], part[3], mark_ask)
	}
	// !
	for part in [[23, 2, 2, 8], [23, 12, 2, 2]] {
		outlined(mut img, part[0], part[1], part[2], part[3], mark_shout)
	}
	for part in [[23, 2, 2, 8], [23, 12, 2, 2]] {
		rect(mut img, part[0], part[1], part[2], part[3], mark_shout)
	}
	return img
}
