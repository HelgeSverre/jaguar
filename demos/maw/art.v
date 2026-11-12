module main

import math
import jagkit

// Everything the game shows is computed here, when the image is built.

// The tunnel is rendered at half resolution and doubled by the object
// processor.
const tunnel_width = 160
const tunnel_height = 120
const tunnel_pixels = tunnel_width * tunnel_height

// depth_scale turns the distance from the centre of the screen into a
// depth: depth = depth_scale / radius, so the far end sits in the middle.
const depth_scale = 4080.0

// The wall texture wraps around the tunnel (256 texels) and along it
// (256 rings). A gate is twelve rings of the texture painted over.
const gate_rings = 12
const gate_rows = [64, 192]

// tunnel_table holds, for every screen pixel, where on the wall the eye
// looks: brightness in bits 16..23, depth in 8..15, angle in 0..7.
fn tunnel_table() []u32 {
	mut table := []u32{cap: tunnel_pixels}
	for y in 0 .. tunnel_height {
		for x in 0 .. tunnel_width {
			dx := f64(x) - (tunnel_width - 1) / 2.0
			dy := f64(y) - (tunnel_height - 1) / 2.0
			radius := math.sqrt(dx * dx + dy * dy)
			angle := u32(int(math.atan2(dy, dx) / (2 * math.pi) * 256 + 256)) & 0xff
			depth := u32(math.min(255.0, depth_scale / math.max(radius, 1.0)))
			// Fog: black in the distance, full brightness at the rim.
			mut light := math.pow(math.min(1.0, radius / 62.0), 1.25)
			light *= math.max(0.0, math.min(1.0, (radius - 8) / 12))
			table << (u32(light * 255) << 16) | (depth << 8) | angle
		}
	}
	return table
}

// hash is a small integer noise function.
fn hash(x int, y int) int {
	mut h := u32(x) * 0x9e3779b1 + u32(y) * 0x85ebca6b
	h ^= h >> 15
	h *= 0x2c1b3c6d
	h ^= h >> 12
	return int(h & 0xff)
}

// wall_texture is 256 rings of 256 CRY texels: riveted panels with glowing
// seams, a few of them lit.
fn wall_texture() []u16 {
	mut texture := []u16{cap: 65536}
	for ring in 0 .. 256 {
		for angle in 0 .. 256 {
			cell_a := angle & 15
			cell_r := ring & 15
			panel := hash(angle >> 4, ring >> 4)
			texture << if cell_a < 2 || cell_r < 2 {
				// Seam: brightest where two seams cross.
				if cell_a < 2 && cell_r < 2 {
					jagkit.cry(255, 255, 255)
				} else {
					jagkit.cry(40, 220, 255)
				}
			} else if panel < 40 {
				// A lit panel, hot in the middle.
				glow := 255 - 9 * (math.abs(cell_a - 8) + math.abs(cell_r - 8))
				jagkit.cry(glow, glow * 5 / 9, glow / 8)
			} else {
				grain := hash(angle, ring) / 8
				bevel := if cell_a == 2 || cell_r == 2 {
					40
				} else if cell_a == 15 || cell_r == 15 {
					-30
				} else {
					0
				}
				rivet := if cell_a in [4, 13] && cell_r in [4, 13] { 70 } else { 0 }
				level := 70 + panel % 50 + grain + bevel + rivet
				if ((angle >> 4) + (ring >> 4)) & 1 == 0 {
					jagkit.cry(level / 4, level / 3, level)
				} else {
					jagkit.cry(level * 2 / 3, level / 5, level)
				}
			}
		}
	}
	return texture
}

// gate_texture is the rings of a gate: hazard stripes between two
// white-hot edges.
fn gate_texture() []u16 {
	mut rings := []u16{cap: gate_rings * 256}
	for ring in 0 .. gate_rings {
		for angle in 0 .. 256 {
			rings << if ring == 0 || ring == gate_rings - 1 {
				jagkit.cry(255, 240, 200)
			} else if ((angle + ring) >> 3) & 1 == 0 {
				jagkit.cry(255, 30, 20)
			} else {
				jagkit.cry(120, 0, 30)
			}
		}
	}
	return rings
}

// gate_post is the colour of the markers on both sides of a gap.
fn gate_post() u16 {
	return jagkit.cry(120, 255, 60)
}

// The font: 5x7 glyphs for ASCII 32..95, five bits a row, left pixel first.
// vfmt off
const glyphs = {
	` `: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
	`!`: [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04]
	`'`: [0x04, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00]
	`(`: [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02]
	`)`: [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08]
	`*`: [0x00, 0x04, 0x15, 0x0e, 0x15, 0x04, 0x00]
	`+`: [0x00, 0x04, 0x04, 0x1f, 0x04, 0x04, 0x00]
	`,`: [0x00, 0x00, 0x00, 0x00, 0x0c, 0x04, 0x08]
	`-`: [0x00, 0x00, 0x00, 0x1f, 0x00, 0x00, 0x00]
	`.`: [0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x0c]
	`/`: [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x00]
	`0`: [0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e]
	`1`: [0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e]
	`2`: [0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f]
	`3`: [0x1f, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0e]
	`4`: [0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02]
	`5`: [0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e]
	`6`: [0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e]
	`7`: [0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08]
	`8`: [0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e]
	`9`: [0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c]
	`:`: [0x00, 0x0c, 0x0c, 0x00, 0x0c, 0x0c, 0x00]
	`<`: [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02]
	`=`: [0x00, 0x00, 0x1f, 0x00, 0x1f, 0x00, 0x00]
	`>`: [0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08]
	`?`: [0x0e, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04]
	`A`: [0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11]
	`B`: [0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e]
	`C`: [0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e]
	`D`: [0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e]
	`E`: [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f]
	`F`: [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10]
	`G`: [0x0e, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0f]
	`H`: [0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11]
	`I`: [0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e]
	`J`: [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0c]
	`K`: [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11]
	`L`: [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f]
	`M`: [0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11]
	`N`: [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11]
	`O`: [0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e]
	`P`: [0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10]
	`Q`: [0x0e, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0d]
	`R`: [0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11]
	`S`: [0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e]
	`T`: [0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04]
	`U`: [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e]
	`V`: [0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04]
	`W`: [0x11, 0x11, 0x11, 0x15, 0x15, 0x1b, 0x11]
	`X`: [0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11]
	`Y`: [0x11, 0x11, 0x0a, 0x04, 0x04, 0x04, 0x04]
	`Z`: [0x1f, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1f]
}
// vfmt on

const font_first = 32
const font_count = 64

// font_bitmap is the font as 8x8 cells, one byte a row, for ASCII 32..95.
fn font_bitmap() []u8 {
	mut font := []u8{len: font_count * 8}
	for code, rows in glyphs {
		for y, row in rows {
			font[(int(code) - font_first) * 8 + y] = u8(row) << 2
		}
	}
	return font
}

// Picture is a 16-bit CRY bitmap; pixel 0 is transparent.
struct Picture {
	width  int
	height int
mut:
	pixels []u16
}

fn new_picture(width int, height int) Picture {
	return Picture{
		width:  width
		height: height
		pixels: []u16{len: width * height}
	}
}

fn (mut p Picture) set(x int, y int, colour u16) {
	if x >= 0 && y >= 0 && x < p.width && y < p.height {
		p.pixels[y * p.width + x] = colour
	}
}

// logo draws a word in big blocks, lit from yellow at the top to red at the
// bottom, with a drop shadow.
fn logo(word string, block int) Picture {
	height := 7 * block + 8
	mut picture := new_picture(word.len * 6 * block, height)
	for pass in 0 .. 2 {
		for i, c in word {
			rows := glyphs[rune(c)]
			for gy, row in rows {
				for gx in 0 .. 5 {
					if row & (0x10 >> gx) == 0 {
						continue
					}
					for y in 0 .. block - 1 {
						for x in 0 .. block - 1 {
							px := (i * 6 + gx) * block + x + block / 2
							py := gy * block + y
							if pass == 0 {
								picture.set(px + 4, py + 4, jagkit.cry(40, 0, 60))
							} else {
								t := py * 255 / (7 * block)
								picture.set(px, py, jagkit.cry(255, 255 - t * 3 / 4, 60 - t / 5))
							}
						}
					}
				}
			}
		}
	}
	return picture
}

// ship draws the player: a delta wing seen from behind, engines lit.
fn ship() Picture {
	mut picture := new_picture(32, 24)
	for y in 0 .. 24 {
		half := 1 + y * 14 / 23
		for x in 16 - half .. 16 + half {
			edge := x == 16 - half || x == 16 + half - 1 || y == 23
			spine := math.abs(x - 16) < 2 && y > 4 && y < 16
			level := 120 + y * 5 - math.abs(x - 16) * 4
			picture.set(x, y, if edge {
				jagkit.cry(30, 40, 70)
			} else if spine {
				jagkit.cry(60, 230, 255)
			} else {
				jagkit.cry(level, level, level + 20)
			})
		}
	}
	for x in [9, 10, 11, 20, 21, 22] {
		picture.set(x, 21, jagkit.cry(255, 200, 60))
		picture.set(x, 22, jagkit.cry(255, 120, 20))
	}
	return picture
}

// rainbow is one turn of the colour wheel at full brightness.
fn rainbow(steps int) []u16 {
	mut colours := []u16{cap: steps}
	for i in 0 .. steps {
		phase := 2 * math.pi * f64(i) / steps
		colours << jagkit.cry(int(205 + 50 * math.sin(phase)),
			int(205 + 50 * math.sin(phase + 2.1)), int(205 + 50 * math.sin(phase + 4.2)))
	}
	return colours
}

// bounce is one period of a sine, 0..amplitude, for things that bob.
fn bounce(steps int, amplitude int) []u8 {
	mut values := []u8{cap: steps}
	for i in 0 .. steps {
		values << u8((1 + math.sin(2 * math.pi * f64(i) / steps)) / 2 * amplitude)
	}
	return values
}
