module main

import math
import jagkit

// Everything the game shows is computed here, when the image is built.

// The tunnel is rendered at half resolution and doubled by the object
// processor.
const tunnel_width = 160
const tunnel_height = 120

// The lookup table is bigger than the screen. The screen is a window on it
// that wanders, so the far end of the tunnel swerves.
const table_width = 224
const table_height = 168
const window_x = (table_width - tunnel_width) / 2 // the window's resting place
const window_y = (table_height - tunnel_height) / 2
const sway_x = 28 // how far the window wanders from it
const sway_y = 20

// The farthest the corner of the screen ever gets from the tunnel's centre.
const farthest_radius = math.sqrt(math.pow((table_width - 1) / 2.0 - (window_x - sway_x), 2) +
	math.pow((table_height - 1) / 2.0 - (window_y - sway_y), 2))

// depth_scale turns the distance from the centre of the tunnel into a
// depth: depth = depth_scale / radius, so the far end sits in the middle.
const depth_scale = 4080.0

// The wall texture is one byte a texel: 256 around the tunnel, 256 rings
// along it. A gate is a few rings painted over; the rings ahead of it
// carry the lane to its opening.
const gate_rings = 12
const gate_rows = [64, 192]
const lane_rings = 24

// Colours. A texel is an index into a palette of 256 colours at each of
// `fog_levels` brightnesses. The first `wall_colours` belong to the wall
// and rotate from one palette phase to the next; the rest stay put.
const fog_levels = 8
const palette_phases = 32
const wall_colours = 224
const spark_dark = 224 // sixteen steps from dark violet to white
const spark_white = 239
const lane_dark = 240 // six greens
const lane_bright = 245
const rail_colour = 247
const palette_bytes = fog_levels * 256 * 2

// tunnel_table holds, for every point of the table, where on the wall the
// eye looks: the offset of its fog level's palette in the high word, then
// the depth, then the angle.
fn tunnel_table() []u32 {
	mut table := []u32{cap: table_width * table_height}
	for y in 0 .. table_height {
		for x in 0 .. table_width {
			dx := f64(x) - (table_width - 1) / 2.0
			dy := f64(y) - (table_height - 1) / 2.0
			radius := math.sqrt(dx * dx + dy * dy)
			angle := u32(int(math.atan2(dy, dx) / (2 * math.pi) * 256 + 256)) & 0xff
			depth := u32(math.min(255.0, depth_scale / math.max(radius, 1.0)))
			// Fog: black in the distance, full brightness near the eye.
			mut light := math.pow(math.min(1.0, radius / 70.0), 1.2)
			light *= math.max(0.0, math.min(1.0, (radius - 8) / 12))
			level := u32(math.min(f64(fog_levels - 1), light * fog_levels))
			table << ((level * 512) << 16) | (depth << 8) | angle
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

// fold mirrors a texture coordinate every 32 texels and maps it to -1..1,
// so a pattern drawn with it tiles without a seam.
fn fold(coordinate int) f64 {
	t := coordinate & 63
	mirrored := if t < 32 { t } else { 63 - t }
	return (f64(mirrored) - 15.5) / 15.5
}

// wall_texture is a Julia set, mirrored into a kaleidoscope: each texel is
// how long its point takes to escape, as a wall colour.
fn wall_texture() []u8 {
	mut texture := []u8{cap: 65536}
	for ring in 0 .. 256 {
		for angle in 0 .. 256 {
			mut x := fold(angle) * 1.45
			mut y := fold(ring) * 1.45
			mut steps := 0
			for steps < 48 && x * x + y * y < 16 {
				x, y = x * x - y * y - 0.7269, 2 * x * y + 0.1889
				steps++
			}
			// The fraction makes the bands flow instead of stepping.
			smooth := f64(steps) + 1 - math.log2(math.max(1.0, math.log2(x * x + y * y + 1.0001)))
			texture << u8(int(math.max(0.0, smooth) * 20) % wall_colours)
		}
	}
	return texture
}

// lane_texture is the strip of wall that leads through a gate: green, with
// a brighter band every eight rings and a darker stripe down the middle of
// every sixteen texels.
fn lane_texture() []u8 {
	mut lane := []u8{cap: (lane_rings + gate_rings) * 256}
	for ring in 0 .. lane_rings + gate_rings {
		for angle in 0 .. 256 {
			mut colour := if ring % 8 < 3 { lane_bright } else { lane_dark + 2 }
			if angle % 16 == 0 {
				colour -= 2
			}
			lane << u8(colour)
		}
	}
	return lane
}

const spark_frames = 4

// spark_texture is one frame of a gate: a wall of lightning. Five arcs
// wander around the ring between two glowing edges.
fn spark_texture(frame int) []u8 {
	mut rings := [][]u8{len: gate_rings, init: []u8{len: 256, init: u8(spark_dark)}}
	for ring in 0 .. gate_rings {
		for angle in 0 .. 256 {
			rings[ring][angle] = u8(spark_dark + 1 + hash(angle + frame * 256, ring) % 5)
		}
	}
	for arc in 0 .. 5 {
		mut at := 2 + hash(arc, frame) % (gate_rings - 4)
		for angle in 0 .. 256 {
			at += hash(angle + arc * 256, frame + 7) % 3 - 1
			at = math.max(1, math.min(gate_rings - 2, at))
			for reach in -2 .. 3 {
				ring := at + reach
				if ring < 1 || ring > gate_rings - 2 {
					continue
				}
				glow := u8(spark_white - math.abs(reach) * 5)
				if glow > rings[ring][angle] {
					rings[ring][angle] = glow
				}
			}
		}
	}
	for angle in 0 .. 256 {
		edge := u8(spark_white - ((angle + frame) & 1) * 4)
		rings[0][angle] = edge
		rings[gate_rings - 1][angle] = edge
	}
	mut texture := []u8{cap: gate_rings * 256}
	for ring in rings {
		texture << ring
	}
	return texture
}

// colour_of is the full-brightness colour of a palette entry, as red,
// green and blue, when the wall's colours have been rotated by `turn`.
fn colour_of(index int, turn int) (f64, f64, f64) {
	if index < wall_colours {
		// Acid bands: once round the colour wheel, a dark valley every
		// sixteen entries.
		i := (index + turn) % wall_colours
		hue := 2 * math.pi * f64(i) / wall_colours
		value := 0.12 + 0.88 * math.pow(math.abs(math.sin(math.pi * f64(i) / 16)), 0.7)
		return value * (0.5 + 0.5 * math.sin(hue)), value * (0.5 + 0.5 * math.sin(hue + 2.1)), value * (
			0.5 + 0.5 * math.sin(hue + 4.2))
	}
	if index <= spark_white {
		t := f64(index - spark_dark) / (spark_white - spark_dark)
		return math.pow(t, 2.5), 0.05 + 0.95 * math.pow(t, 1.3), 0.4 + 0.6 * math.sqrt(t)
	}
	if index <= lane_bright {
		t := f64(index - lane_dark) / (lane_bright - lane_dark)
		return 0.1 * t, 0.3 + 0.7 * t, 0.15 * t
	}
	if index == rail_colour {
		return 0.6, 1.0, 0.5
	}
	return 1.0, 1.0, 1.0
}

// palettes is every phase of the palette, one after another. Within a
// phase the fog levels follow each other, darkest first.
fn palettes() []u16 {
	mut colours := []u16{cap: palette_phases * fog_levels * 256}
	for phase in 0 .. palette_phases {
		turn := phase * wall_colours / palette_phases
		for level in 0 .. fog_levels {
			// The gates and lanes glow: fog dims them less than the wall.
			for index in 0 .. 256 {
				r, g, b := colour_of(index, turn)
				fog := f64(level) / (fog_levels - 1)
				light := if index < wall_colours { fog } else { math.sqrt(fog) }
				colours << jagkit.cry(int(r * light * 255), int(g * light * 255),
					int(b * light * 255))
			}
		}
	}
	return colours
}

// sway is one turn of a sine as signed bytes, for the swerving window.
fn sway() []u8 {
	mut values := []u8{cap: 256}
	for i in 0 .. 256 {
		values << u8(i8(int(127 * math.sin(2 * math.pi * f64(i) / 256))))
	}
	return values
}

const zap_size = 128

// zap is the picture shown over a wreck: lightning forking out from the
// ship, one bit a pixel.
fn zap() []u8 {
	mut bits := []u8{len: zap_size * zap_size / 8}
	for bolt in 0 .. 9 {
		mut heading := 2 * math.pi * f64(bolt) / 9 + f64(hash(bolt, 1)) / 255
		mut x := f64(zap_size / 2)
		mut y := f64(zap_size / 2)
		for step in 0 .. 60 {
			if step % 4 == 0 {
				heading += (f64(hash(bolt, step)) / 255 - 0.5) * 1.6
			}
			x += math.cos(heading)
			y += math.sin(heading)
			// Thick near the ship, a hair at the tips.
			tall := if step < 30 { 2 } else { 1 }
			wide := if step < 15 { 2 } else { 1 }
			for dy in 0 .. tall {
				for dx in 0 .. wide {
					px := int(x) + dx
					py := int(y) + dy
					if px >= 0 && py >= 0 && px < zap_size && py < zap_size {
						bits[py * (zap_size / 8) + px / 8] |= u8(0x80) >> u32(px % 8)
					}
				}
			}
		}
	}
	return bits
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
			rows := jagkit.glyph(c)
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

// ship draws the player: a delta wing seen from behind, engines lit. `lean`
// is -1, 0 or 1 and tips the nose into a turn.
fn ship(lean int) Picture {
	mut picture := new_picture(32, 24)
	for y in 0 .. 24 {
		half := 1 + y * 14 / 23
		middle := 16 + lean * (23 - y) / 5
		for x in middle - half .. middle + half {
			edge := x == middle - half || x == middle + half - 1 || y == 23
			spine := math.abs(x - middle) < 2 && y > 4 && y < 16
			// The wing on the inside of the turn is in shadow.
			shade := if lean * (x - middle) < 0 { 45 } else { 0 }
			level := 135 + y * 5 - math.abs(x - middle) * 4 - shade
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

const blast_frames = 4

// blast draws one frame of the ship's end: a white flash that opens into a
// ring of cooling sparks.
fn blast(frame int) Picture {
	size := 48
	mut picture := new_picture(size, size)
	outer := 9 + frame * 5
	inner := if frame == 0 { -1 } else { outer - 9 + frame }
	for y in 0 .. size {
		for x in 0 .. size {
			dx := x - size / 2
			dy := y - size / 2
			distance := int(math.sqrt(f64(dx * dx + dy * dy)))
			if distance > outer || distance < inner {
				continue
			}
			// Later frames are ragged: more and more sparks have gone out.
			if hash(x + frame * 64, y) < frame * 60 {
				continue
			}
			heat := 255 - (distance - inner) * 12 - frame * 30
			picture.set(x, y, match frame {
				0 { jagkit.cry(255, 255, 200 + distance * 5) }
				1 { jagkit.cry(255, heat, heat / 3) }
				2 { jagkit.cry(heat + 40, heat / 2, 20) }
				else { jagkit.cry(heat + 30, heat / 4, 30) }
			})
		}
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
