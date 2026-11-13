// make_art draws GHOSTGRID's pictures and writes them as PNG files next to
// this file: tiles.png (five tiles of 16x16) and player.png (the figure,
// three frames in each of four directions). They are made here, in code, so
// that they can be tweaked and made again:
//
//     v run demos/ghostgrid/art
//
// The game imports the PNGs (demos/ghostgrid/main.v); this tool is not part
// of it. Everything is simple shapes: a dark floor with a glowing grid,
// block walls with a lit top edge, a cover block, an exit pad, a data chip
// and a figure made of boxes.
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

const chip_body = Colour{232, 202, 44}
const chip_dark = Colour{150, 120, 18}
const chip_pin = Colour{200, 204, 210}
const chip_core = Colour{70, 56, 8}
const chip_glint = Colour{255, 250, 190}

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
	println('${dir}: tiles.png and player.png written')
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
	rect(mut img, ox, oy, 16, 16, floor_base)
	rect(mut img, ox, oy, 1, 16, floor_line)
	rect(mut img, ox, oy, 16, 1, floor_line)
	dot(mut img, ox, oy, floor_glow)
	dot(mut img, ox + 1, oy, floor_node)
	dot(mut img, ox, oy + 1, floor_node)
	dot(mut img, ox + 15, oy, floor_node)
	dot(mut img, ox, oy + 15, floor_node)
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
fn pad(mut img jaggame.Canvas, ox int, oy int) {
	floor(mut img, ox, oy)
	rect(mut img, ox + 2, oy + 2, 12, 12, pad_edge)
	rect(mut img, ox + 3, oy + 3, 10, 10, pad_body)
	rect(mut img, ox + 7, oy + 4, 2, 5, pad_arrow)
	rect(mut img, ox + 5, oy + 8, 6, 1, pad_arrow)
	rect(mut img, ox + 6, oy + 9, 4, 1, pad_arrow)
	rect(mut img, ox + 7, oy + 10, 2, 1, pad_arrow)
}

// chip draws a data chip: a small yellow package with pins on both sides
// and a dark core, on the floor.
fn chip(mut img jaggame.Canvas, ox int, oy int) {
	floor(mut img, ox, oy)
	rect(mut img, ox + 4, oy + 4, 8, 8, chip_dark)
	rect(mut img, ox + 5, oy + 5, 6, 6, chip_body)
	rect(mut img, ox + 7, oy + 7, 2, 2, chip_core)
	dot(mut img, ox + 5, oy + 5, chip_glint)
	for i in 0 .. 3 {
		rect(mut img, ox + 2, oy + 5 + i * 2, 2, 1, chip_pin)
		rect(mut img, ox + 12, oy + 5 + i * 2, 2, 1, chip_pin)
	}
}

// tiles is the tile set: floor, wall, cover, exit pad, chip, in that order.
fn tiles() jaggame.Canvas {
	mut img := jaggame.new_canvas(80, 16)
	floor(mut img, 0, 0)
	wall(mut img, 16, 0)
	cover(mut img, 32, 0)
	pad(mut img, 48, 0)
	chip(mut img, 64, 0)
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

// player is the sheet of the figure: three frames across (standing, left
// foot, right foot) and a row for each direction: down, up, left, right.
fn player() jaggame.Canvas {
	mut img := jaggame.new_canvas(48, 64)
	for row, facing in [Facing.down, .up, .left, .right] {
		for step in 0 .. 3 {
			figure(mut img, step * 16, row * 16, facing, step)
		}
	}
	return img
}
