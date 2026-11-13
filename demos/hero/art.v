module main

import math
import jagkit

// Everything the game shows is computed here, when the image is built.

const screen_width = 320
const screen_height = 240

// The highway is seen in perspective. A note `t` frames ahead of the strike
// line is at depth z = 1 + t / look_ahead * (far_z - 1); a depth is drawn on
// the row vanish_row + (strike_row - vanish_row) / z, and everything at that
// depth is scaled by 1 / z.
const strike_row = 200
const far_row = 44
const far_z = 4.0
const vanish_row = (far_z * far_row - strike_row) / (far_z - 1)
const lane_width = 48 // at the strike line
const lanes = 5
const view_beats = 3 // how far ahead the highway reaches
const back_frames = 16 // how long a missed note stays in the table past the line
const hidden_line = 1900 // a half-line below the picture, for lines out of sight

// Colours of the lanes, left to right.
const lane_rgb = [[255, 40, 150], [255, 140, 20], [255, 236, 60],
	[40, 220, 255], [170, 90, 255]]

// CLUT entries. Text and its shadow use the first eight.
const clut_text = 1 // three colours: 1 white, 2 cycling, 3 accent
const clut_shadow = 5
const clut_meter = 8 // eight shades of the health meter
const clut_targets = 16 // four per lane: ring, gap, centre, glint
const clut_rails = 36 // rail, rail edge, separator, strike line, glow, frame
const clut_lanes = 64 // 24 per lane: twelve depth bands, centre and edge
const clut_background = 192 // 64 animated background colours
const lane_bands = 12
const rails_colours = 8
const background_colours = 64
const glow_levels = 16
const target_states = 4
const multiplier_tiers = 5
const background_phases = 32 // two beats

// Background index ranges, from clut_background.
const bg_rings = 0 // 16 rings around the sun
const bg_sun = 16 // 16 rows of sun
const bg_stars = 40 // four groups
const bg_lines = 44 // the ground's lines across, four depths
const bg_ground_far = 48 // eight phases of ground, far half
const bg_ground_near = 56 // and near half

fn depth_row(z f64) f64 {
	return vanish_row + (strike_row - vanish_row) / z
}

fn row_depth(row f64) f64 {
	return (strike_row - vanish_row) / (row - vanish_row)
}

fn lane_centre(lane int) int {
	return screen_width / 2 + (lane - 2) * lane_width
}

fn clampi(v int, lo int, hi int) int {
	return if v < lo {
		lo
	} else if v > hi {
		hi
	} else {
		v
	}
}

// hash is a small integer noise function.
fn hash(x int, y int) int {
	mut h := u32(x) * 0x9e3779b1 + u32(y) * 0x85ebca6b
	h ^= h >> 15
	h *= 0x2c1b3c6d
	h ^= h >> 12
	return int(h & 0xff)
}

// rgb scales a colour and turns it into CRY.
fn shade(rgb []int, level f64) u16 {
	return jagkit.cry(clampi(int(rgb[0] * level), 0, 255), clampi(int(rgb[1] * level), 0, 255), clampi(int(rgb[2] * level),
		0, 255))
}

fn blend_rgb(a []int, b []int, t f64) []int {
	return [int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t),
		int(a[2] + (b[2] - a[2]) * t)]
}

// stage is the picture behind everything, 8 bits a pixel: the highway, the
// ground beside it, the sky and the sun. Every pixel is a CLUT index, and
// the program animates the CLUT.
fn stage() []u8 {
	mut pixels := []u8{len: screen_width * screen_height}
	sun_x := 160.0
	sun_y := f64(far_row) - 2
	sun_radius := 36.0
	for y in 0 .. screen_height {
		for x in 0 .. screen_width {
			mut index := 0
			fx := f64(x) + 0.5 - screen_width / 2
			if y >= far_row {
				z := row_depth(f64(y) + 0.5)
				wx := fx * z // world x, in pixels at the strike line
				t := (z - 1) / (far_z - 1) // 0 at the strike line, 1 far away
				if math.abs(wx) <= lanes * lane_width / 2 {
					lane := clampi(int((wx + 120) / lane_width), 0, 4)
					u := (wx + 120) / lane_width - lane
					if u < 0.035 || u > 0.965 {
						index = clut_rails + 2
					} else {
						band := clampi(int(t * lane_bands), 0, lane_bands - 1)
						edge := if math.abs(u - 0.5) > 0.32 { 1 } else { 0 }
						index = clut_lanes + lane * 24 + band * 2 + edge
					}
					dy := y - strike_row
					if dy >= -1 && dy <= 1 {
						index = clut_rails + 3
					} else if dy >= -4 && dy <= 4 {
						index = clut_rails + 4
					}
				} else if math.abs(wx) <= 130 {
					index = if math.abs(wx) <= 125 { clut_rails + 1 } else { clut_rails }
				} else {
					// Ground: lines along it, and across it a band for each
					// sixteenth of a beat, eight bands to a line.
					beats := t * view_beats
					along := math.fmod(math.abs(wx) - 130, 64)
					if along < 3.5 {
						index = clut_background + bg_lines + clampi(int(t * 4), 0, 3)
					} else {
						phase := int(math.floor(beats * 16)) & 7
						base := if t < 0.4 { bg_ground_near } else { bg_ground_far }
						index = clut_background + base + phase
					}
				}
			} else {
				dx := f64(x) + 0.5 - sun_x
				dy := f64(y) + 0.5 - sun_y
				distance := math.sqrt(dx * dx + dy * dy)
				// The sun, cut by thinning stripes towards the horizon.
				gap := (far_row - y) < 18 && (far_row - y) % 5 < (18 - (far_row - y)) / 5
				if distance < sun_radius && !gap {
					row := clampi(int((f64(y) - (sun_y - sun_radius)) / sun_radius * 16), 0, 15)
					index = clut_background + bg_sun + row
				} else if hash(x, y) > 250 && hash(y, x) & 3 == 0 {
					index = clut_background + bg_stars + (hash(x * 3, y) & 3)
				} else {
					index = clut_background + bg_rings + (int(distance / 9) & 15)
				}
			}
			pixels[y * screen_width + x] = u8(index)
		}
	}
	// Strike targets: a ring in each lane.
	for lane in 0 .. lanes {
		cx := f64(lane_centre(lane))
		for y in strike_row - 10 .. strike_row + 11 {
			for x in int(cx) - 22 .. int(cx) + 23 {
				ex := (f64(x) + 0.5 - cx) / 20.0
				ey := (f64(y) + 0.5 - strike_row) / 8.5
				d := math.sqrt(ex * ex + ey * ey)
				if d > 1 {
					continue
				}
				part := if d > 0.76 {
					0
				} else if d > 0.6 {
					1
				} else if ex < -0.2 && ex > -0.55 && ey < -0.2 && ey > -0.6 {
					3
				} else {
					2
				}
				pixels[y * screen_width + x] = u8(clut_targets + lane * 4 + part)
			}
		}
	}
	return pixels
}

const meter_x = 300
const meter_top = 64
const meter_width = 8
const meter_height = 128

const meter_frame_width = 16

// meter_frame is the box the health meter sits in, 8 bits a pixel, its
// outside transparent.
fn meter_frame() []u8 {
	mut pixels := []u8{len: meter_frame_width * (meter_height + 4)}
	for y in 0 .. meter_height + 4 {
		for x in 2 .. 14 {
			inside := y >= 2 && y < meter_height + 2 && x >= 4 && x < 12
			pixels[y * meter_frame_width + x] = u8(if inside {
				clut_rails + 6
			} else {
				clut_rails + 5
			})
		}
	}
	return pixels
}

// meter_bar is the health meter's picture, 8 bits a pixel: lighter shades
// further up.
fn meter_bar() []u8 {
	mut pixels := []u8{cap: meter_width * meter_height}
	for y in 0 .. meter_height {
		for x in 0 .. meter_width {
			edge := if x == 0 || x == meter_width - 1 { 1 } else { 0 }
			pixels << u8(clut_meter + clampi(7 - y * 8 / meter_height - edge, 0, 7))
		}
	}
	return pixels
}

// lane_colours is, for each lane and glow level, the 24 CLUT colours of its
// surface: dark glass that lights up towards the strike line.
fn lane_colours() []u16 {
	mut colours := []u16{}
	for lane in 0 .. lanes {
		rgb := lane_rgb[lane]
		for glow in 0 .. glow_levels {
			g := f64(glow) / (glow_levels - 1)
			for band in 0 .. lane_bands {
				fog := 1.0 - f64(band) / lane_bands * 0.8
				near := math.exp(-f64(band) / 1.8)
				for edge in 0 .. 2 {
					base := if edge == 0 { 0.13 } else { 0.24 }
					level := (base + g * near * 1.1 + g * 0.08) * fog
					tint := blend_rgb([30, 30, 70], rgb, math.min(1.0, 0.6 + g * 0.4))
					hot := blend_rgb(tint, [255, 255, 255], math.max(0.0, g * near - 0.55))
					colours << shade(hot, level)
				}
			}
		}
	}
	return colours
}

// target_colours is, for each lane and state (idle, held, struck, missed),
// the four colours of its target.
fn target_colours() []u16 {
	mut colours := []u16{}
	white := [255, 255, 255]
	for lane in 0 .. lanes {
		rgb := lane_rgb[lane]
		for state in 0 .. target_states {
			match state {
				0 {
					colours << shade(rgb, 0.75)
					colours << shade([10, 10, 25], 1)
					colours << shade(rgb, 0.22)
					colours << shade(white, 0.45)
				}
				1 {
					colours << shade(blend_rgb(rgb, white, 0.5), 1)
					colours << shade(rgb, 0.5)
					colours << shade(rgb, 0.85)
					colours << shade(white, 1)
				}
				2 {
					colours << shade(white, 1)
					colours << shade(rgb, 1)
					colours << shade(blend_rgb(rgb, white, 0.7), 1)
					colours << shade(white, 1)
				}
				else {
					colours << shade([255, 30, 20], 0.9)
					colours << shade([60, 0, 0], 1)
					colours << shade([120, 10, 10], 1)
					colours << shade(white, 0.4)
				}
			}
		}
	}
	return colours
}

// Colours of the rails for each multiplier tier.
const tier_rgb = [[90, 120, 200], [40, 230, 160], [255, 220, 40],
	[255, 120, 20], [255, 60, 255]]

// rail_colours is, for each tier and sixteenth of a beat, the colours of the
// rails, separators, strike line and meter frame. They flash on the beat.
fn rail_colours() []u16 {
	mut colours := []u16{}
	for tier in 0 .. multiplier_tiers {
		rgb := tier_rgb[tier]
		for phase in 0 .. 16 {
			pulse := math.pow(1.0 - f64(phase) / 16, 2)
			hot := if tier == 4 { blend_rgb(rgb, [255, 255, 255], pulse * 0.6) } else { rgb }
			colours << shade(hot, 0.55 + 0.45 * pulse)
			colours << shade(hot, 0.3 + 0.3 * pulse)
			colours << shade(hot, 0.18 + 0.1 * pulse)
			colours << shade(blend_rgb(hot, [255, 255, 255], 0.6), 0.8 + 0.2 * pulse)
			colours << shade(hot, 0.25 + 0.2 * pulse)
			colours << shade(hot, 0.7)
			colours << shade([0, 0, 0], 0)
			colours << shade([0, 0, 0], 0)
		}
	}
	return colours
}

// Theme is a song's background palette.
struct Theme {
	sky    []int
	ring   []int
	sun_a  []int // top of the sun
	sun_b  []int // bottom
	grid   []int
	ground []int
}

// One theme a song: synth-wave pink, toxic green, molten orange, ice blue
// and blood red.
const themes = [
	Theme{
		sky:    [20, 0, 40]
		ring:   [255, 40, 200]
		sun_a:  [255, 230, 80]
		sun_b:  [255, 30, 160]
		grid:   [255, 50, 220]
		ground: [20, 0, 40]
	},
	Theme{
		sky:    [10, 15, 10]
		ring:   [90, 255, 60]
		sun_a:  [210, 255, 120]
		sun_b:  [40, 120, 20]
		grid:   [120, 255, 40]
		ground: [5, 20, 5]
	},
	Theme{
		sky:    [30, 5, 0]
		ring:   [255, 90, 20]
		sun_a:  [255, 240, 120]
		sun_b:  [255, 60, 0]
		grid:   [255, 120, 30]
		ground: [30, 8, 0]
	},
	Theme{
		sky:    [0, 10, 40]
		ring:   [60, 160, 255]
		sun_a:  [255, 255, 255]
		sun_b:  [120, 160, 255]
		grid:   [80, 200, 255]
		ground: [0, 10, 40]
	},
	Theme{
		sky:    [40, 0, 0]
		ring:   [255, 20, 40]
		sun_a:  [255, 255, 200]
		sun_b:  [255, 0, 40]
		grid:   [255, 40, 40]
		ground: [30, 0, 0]
	},
]

// background_colours is, for each song, calm and on fire, and for each of
// 32 steps through two beats, the 64 background colours: rings that pulse
// outwards on the beat, twinkling stars, the ground grid rolling towards
// the player.
fn background_colours() []u16 {
	mut colours := []u16{}
	for theme in themes {
		for hot in 0 .. 2 {
			heat := if hot == 1 { 1.6 } else { 1.0 }
			for step in 0 .. background_phases {
				phase := step % 16
				pulse := math.pow(1.0 - f64(phase) / 16, 2)
				mut row := []u16{len: background_colours}
				for ring in 0 .. 16 {
					distance := (ring - phase + 16) % 16
					lit := math.max(0.0, 1.0 - f64(distance) / 3.0)
					level := (0.05 + 0.3 * lit * (1 - f64(ring) / 20)) * heat
					row[bg_rings + ring] = shade(blend_rgb(theme.sky, theme.ring, 0.4 + 0.6 * lit), math.min(1.0,
						level * 2.2))
				}
				for i in 0 .. 16 {
					rgb := blend_rgb(theme.sun_a, theme.sun_b, f64(i) / 15)
					row[bg_sun + i] = shade(rgb, math.min(1.0, (0.75 + 0.25 * pulse) * (0.8 +
						0.2 * heat)))
				}
				for star in 0 .. 4 {
					twinkle := 0.5 + 0.5 * math.sin(f64(step + star * 9) * math.pi / 8)
					row[bg_stars + star] = shade([255, 255, 255], 0.35 + 0.6 * twinkle)
				}
				for depth in 0 .. 4 {
					row[bg_lines + depth] = shade(theme.grid, (0.5 - 0.1 * f64(depth)) * (0.7 +
						0.3 * pulse) * heat)
				}
				// The lit band of the ground moves one sixteenth of a beat
				// nearer every sixteenth of a beat.
				lit_band := (8 - phase % 8) % 8
				for band in 0 .. 8 {
					on := band == lit_band
					row[bg_ground_far + band] = if on {
						shade(theme.grid, 0.4 * heat)
					} else {
						shade(theme.ground, 1)
					}
					row[bg_ground_near + band] = if on {
						shade(theme.grid, math.min(1.0, 0.8 * heat))
					} else {
						shade(theme.ground, 1.2)
					}
				}
				colours << row
			}
		}
	}
	return colours
}

// meter_colours is the health meter's eight shades for four moods: full of
// it, fine, worried, and failing (which flashes).
fn meter_colours() []u16 {
	moods := [[80, 255, 120], [60, 200, 255], [255, 200, 40],
		[255, 30, 30]]
	mut colours := []u16{}
	for rgb in moods {
		for i in 0 .. 8 {
			colours << shade(rgb, 0.45 + 0.08 * f64(i))
		}
	}
	return colours
}

// rainbow is one turn of a hot colour wheel, for cycling text.
fn rainbow(steps int) []u16 {
	mut colours := []u16{cap: steps}
	for i in 0 .. steps {
		phase := 2 * math.pi * f64(i) / steps
		colours << jagkit.cry(int(215 + 40 * math.sin(phase)),
			int(170 + 85 * math.sin(phase + 2.1)), int(150 + 105 * math.sin(phase + 4.2)))
	}
	return colours
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

fn (p &Picture) get(x int, y int) u16 {
	if x >= 0 && y >= 0 && x < p.width && y < p.height {
		return p.pixels[y * p.width + x]
	}
	return 0
}

const gem_width = 40
const gem_height = 16

// gem draws a note: a glossy capsule in the lane's colour, dimmer for the
// far distance. `lane` -1 is the grey of a missed note.
fn gem(lane int, fog int) Picture {
	mut p := new_picture(gem_width, gem_height)
	rgb := if lane < 0 { [120, 120, 130] } else { lane_rgb[lane] }
	dim := [1.0, 0.7, 0.42][fog]
	for y in 0 .. gem_height {
		for x in 0 .. gem_width {
			ex := (f64(x) + 0.5 - gem_width / 2.0) / (gem_width / 2.0)
			ey := (f64(y) + 0.5 - gem_height / 2.0) / (gem_height / 2.0)
			d := math.pow(math.pow(math.abs(ex), 4) + math.pow(math.abs(ey), 2.2), 0.25)
			if d > 1 {
				continue
			}
			mut colour := []int{}
			mut level := 1.0
			if d > 0.88 {
				colour = [10, 10, 20]
			} else if ey < -0.45 {
				colour = blend_rgb(rgb, [255, 255, 255], 0.55)
			} else if ey > 0.45 {
				colour = rgb.clone()
				level = 0.55
			} else {
				colour = rgb.clone()
				level = 0.95 - 0.2 * math.abs(ex)
			}
			if math.abs(ey + 0.15) < 0.17 && math.abs(ex) < 0.5 {
				colour = blend_rgb(colour, [255, 255, 255], 0.75)
				level = 1
			}
			p.set(x, y, shade(colour, level * dim))
		}
	}
	return p
}

const beam_width = 32
const beam_height = 60
const beam_scale = 4.0
const beam_levels = 3

// beam is a shaft of light from a top corner of the screen, drawn by adding
// brightness to what is under it and magnified four times. Side 0 comes
// from the left; level 0 is the brightest.
fn beam(side int, level int) Picture {
	mut p := new_picture(beam_width, beam_height)
	strength := [1.0, 0.62, 0.32][level]
	dx := 0.42
	dy := 0.91
	for y in 0 .. beam_height {
		for x in 0 .. beam_width {
			fx := if side == 0 { f64(x) + 0.5 } else { beam_width - f64(x) - 0.5 }
			vx := fx + 3
			vy := f64(y) + 0.5 + 2
			along := vx * dx + vy * dy
			across := math.abs(vx * dy - vy * dx)
			width := 1.0 + along * 0.11
			edge := math.max(0.0, 1 - across / width)
			fade := math.max(0.0, 1 - along / 90)
			boost := int(strength * 127 * math.pow(edge, 0.7) * fade)
			if boost > 0 {
				p.set(x, y, u16(boost))
			}
		}
	}
	return p
}

const line_width = 240

// beat_line is the line across the highway on every beat, drawn by adding
// brightness to what is under it. A bar line is brighter.
fn beat_line(bar bool) Picture {
	height := if bar { 3 } else { 2 }
	mut p := new_picture(line_width, height)
	for y in 0 .. height {
		for x in 0 .. line_width {
			edge := math.min(x, line_width - 1 - x)
			boost := if bar { 100 } else { 46 }
			p.set(x, y, u16(clampi(boost * clampi(edge, 0, 8) / 8, 1, 127)))
		}
	}
	return p
}

const burst_size = 48
const burst_frames = 6

// burst is one frame of a hit: a white flash that opens into a ring of
// sparks in the lane's colour.
fn burst(lane int, frame int) Picture {
	mut p := new_picture(burst_size, burst_size)
	rgb := lane_rgb[lane]
	outer := 7.0 + f64(frame) * 3.4
	inner := if frame == 0 { -1.0 } else { outer - 5 - f64(frame) * 0.4 }
	for y in 0 .. burst_size {
		for x in 0 .. burst_size {
			dx := f64(x) + 0.5 - burst_size / 2
			dy := (f64(y) + 0.5 - burst_size / 2) * 1.6
			distance := math.sqrt(dx * dx + dy * dy)
			angle := math.atan2(dy, dx)
			ray := math.abs(math.sin(angle * 4)) > 0.96 && distance < outer + 6 - f64(frame)
			if !ray && (distance > outer || distance < inner) {
				continue
			}
			if hash(x + frame * 64, y + lane * 7) < frame * 34 {
				continue
			}
			heat := 1.0 - (distance - inner) / (outer - inner + 1) * 0.4 - f64(frame) * 0.1
			white := math.max(0.0, 1.0 - f64(frame) * 0.3)
			colour := blend_rgb(rgb, [255, 255, 255], if ray { 0.8 } else { white })
			p.set(x, y, shade(colour, math.max(0.3, heat)))
		}
	}
	return p
}

// The font: 5x7 glyphs for ASCII 32..127, five bits a row, left pixel first.
// Some codes are symbols: @ a star, ^ an empty star, | a block, } half a
// block, ~ an arrow.
// vfmt off
const glyphs = {
	` `: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
	`!`: [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04]
	`"`: [0x0a, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00]
	`#`: [0x0a, 0x1f, 0x0a, 0x0a, 0x0a, 0x1f, 0x0a]
	`%`: [0x19, 0x19, 0x02, 0x04, 0x08, 0x13, 0x13]
	`&`: [0x0c, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0d]
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
	`2`: [0x0e, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1f]
	`3`: [0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e]
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
	`D`: [0x1c, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1c]
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
	`[`: [0x0e, 0x08, 0x08, 0x08, 0x08, 0x08, 0x0e]
	`]`: [0x0e, 0x02, 0x02, 0x02, 0x02, 0x02, 0x0e]
	`_`: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1f]
	`@`: [0x04, 0x0e, 0x1f, 0x1f, 0x1f, 0x0e, 0x04]
	`^`: [0x04, 0x0a, 0x11, 0x11, 0x11, 0x0a, 0x04]
	`|`: [0x1f, 0x1f, 0x1f, 0x1f, 0x1f, 0x1f, 0x1f]
	`}`: [0x00, 0x00, 0x00, 0x1f, 0x1f, 0x1f, 0x1f]
	`~`: [0x08, 0x0c, 0x0e, 0x0f, 0x0e, 0x0c, 0x08]
}
// vfmt on

const font_first = 32
const font_count = 96

// glyph_rows is a glyph as 8 rows of 8 pixels: bold, one pixel wider than
// it was drawn, with an empty row and column to separate characters.
fn glyph_rows(code rune) []u8 {
	rows := glyphs[code] or { glyphs[` `] }
	mut out := []u8{len: 8}
	for y, row in rows {
		wide := (row << 1) | row
		out[y] = u8(wide << 1)
	}
	return out
}

// font_2bpp is the font at two bits a pixel, once for each of the three
// text colours: a glyph row is a word.
fn font_2bpp() []u16 {
	mut font := []u16{len: 3 * font_count * 8}
	for colour in 1 .. 4 {
		for code in font_first .. font_first + font_count {
			rows := glyph_rows(rune(code))
			for y, row in rows {
				mut word := u16(0)
				for x in 0 .. 8 {
					if row & (0x80 >> x) != 0 {
						word |= u16(colour) << (14 - 2 * x)
					}
				}
				font[((colour - 1) * font_count + code - font_first) * 8 + y] = word
			}
		}
	}
	return font
}

// block_text draws words in big blocks with a dark outline and a drop
// shadow; `paint` colours a block by its place, 0..1 from top to bottom.
fn block_text(word string, block int, paint fn (f64, f64) u16) Picture {
	pad := 3
	raw_width := word.len * 6 * block - block + 2 * pad
	width := (raw_width + 3) / 4 * 4
	height := 7 * block + 2 * pad + 1
	mut p := new_picture(width, height)
	mut solid := []bool{len: width * height}
	for i, c in word {
		rows := glyphs[rune(c)] or { glyphs[` `] }
		for gy, row in rows {
			for gx in 0 .. 5 {
				if row & (0x10 >> gx) == 0 {
					continue
				}
				for y in 0 .. block {
					for x in 0 .. block {
						px := (i * 6 + gx) * block + x + pad + (width - raw_width) / 2
						py := gy * block + y + pad
						solid[py * width + px] = true
					}
				}
			}
		}
	}
	// Shadow and outline first, then the face.
	for y in 0 .. height {
		for x in 0 .. width {
			mut near := false
			for oy in -1 .. 2 {
				for ox in -1 .. 2 {
					qx := x + ox
					qy := y + oy
					if qx >= 0 && qy >= 0 && qx < width && qy < height && solid[qy * width + qx] {
						near = true
					}
				}
			}
			shadow := x >= 2 && y >= 2 && solid[(y - 2) * width + x - 2]
			if near || shadow {
				p.set(x, y, jagkit.cry(16, 0, 24))
			}
		}
	}
	for y in 0 .. height {
		for x in 0 .. width {
			if solid[y * width + x] {
				p.set(x, y, paint(f64(y - pad) / f64(7 * block), f64(x) / f64(width)))
			}
		}
	}
	return p
}

fn gradient(top []int, bottom []int) fn (f64, f64) u16 {
	return fn [top, bottom] (t f64, _ f64) u16 {
		k := math.max(0.0, math.min(1.0, t))
		return shade(blend_rgb(top, bottom, k), 1)
	}
}

// fire is the logo's paint: white-hot at the top through gold to red, with
// a bright streak.
fn fire(t f64, u f64) u16 {
	k := math.max(0.0, math.min(1.0, t))
	mut rgb := if k < 0.5 {
		blend_rgb([255, 255, 220], [255, 200, 40], k * 2)
	} else {
		blend_rgb([255, 200, 40], [230, 30, 60], (k - 0.5) * 2)
	}
	if math.abs(k - 0.42 - (u - 0.5) * 0.3) < 0.05 {
		rgb = blend_rgb(rgb, [255, 255, 255], 0.7)
	}
	return shade(rgb, 1)
}

fn chrome(t f64, _ f64) u16 {
	k := math.max(0.0, math.min(1.0, t))
	level := if k < 0.5 { 1.0 - k * 0.9 } else { 0.35 + (k - 0.5) * 1.2 }
	return shade(blend_rgb([120, 200, 255], [255, 255, 255], 1 - k), level)
}

const judge_words = ['PERFECT', 'GREAT', 'GOOD', 'MISS']

fn judge_word(i int) Picture {
	paints := [gradient([255, 255, 220], [255, 170, 0]), gradient([200, 255, 255], [0, 150, 255]),
		gradient([200, 255, 160], [30, 180, 40]), gradient([255, 120, 120], [160, 0, 0])]
	return block_text(judge_words[i], 2, paints[i])
}

// The big digits, then X, then a plus sign; gold, and red-hot for
// overdrive.
const digit_glyphs = '0123456789X'

fn big_digit(c u8, hot bool) Picture {
	paint := if hot {
		gradient([255, 255, 255], [255, 30, 120])
	} else {
		gradient([255, 255, 200], [255, 150, 0])
	}
	return block_text(c.ascii_str(), 3, paint)
}

const rank_letters = 'SABCDF'

fn rank_letter(i int) Picture {
	paints := [gradient([255, 255, 255], [255, 200, 0]), gradient([255, 240, 160], [255, 90, 0]),
		gradient([160, 255, 255], [0, 120, 255]), gradient([200, 255, 160], [20, 160, 40]),
		gradient([230, 200, 255], [120, 40, 200]), gradient([255, 120, 120], [140, 0, 0])]
	return block_text(rank_letters[i].ascii_str(), 8, paints[i])
}

// View is where one moment ahead of the strike line is drawn.
struct View {
	gem_top  int // half-lines from the top of the picture, or -1 when off screen
	line_top int
	scale    int // hscale | vscale << 8, in 3.5 fixed point
	line_x   int
	gem_x    []int
	fog      int // which of the three gem brightnesses
}

fn fixed_3_5(scale f64) int {
	return clampi(int(scale * 32 + 0.5), 1, 255)
}

// view_table is, for every frame from back_frames behind the strike line
// to `look_ahead` frames ahead of it, where its notes and beat line go.
fn view_table(look_ahead int) []View {
	mut views := []View{}
	for t in -back_frames .. look_ahead + 1 {
		z := 1 + f64(t) / look_ahead * (far_z - 1)
		if z <= 0.3 {
			views << View{
				gem_top:  -1
				line_top: hidden_line
				gem_x:    []int{len: lanes}
			}
			continue
		}
		s := 1 / z
		vs := s * (0.75 + 0.25 * math.min(1.0, s))
		row := depth_row(z)
		hs := fixed_3_5(s)
		vv := fixed_3_5(vs)
		sh := f64(hs) / 32
		sv := f64(vv) / 32
		top := row - gem_height / 2 * sv
		mut xs := []int{}
		for lane in 0 .. lanes {
			centre := screen_width / 2 + (f64(lane) - 2) * lane_width * s
			xs << int(centre - gem_width / 2 * sh + 0.5)
		}
		visible := top + gem_height * sv < screen_height && top > 0
		fog := if t > look_ahead * 2 / 3 {
			2
		} else if t > look_ahead / 3 {
			1
		} else {
			0
		}
		views << View{
			gem_top:  if visible { int(top * 2) } else { -1 }
			line_top: int((row - 1) * 2)
			scale:    hs | (vv << 8)
			line_x:   int(screen_width / 2 - line_width / 2 * sh + 0.5)
			gem_x:    xs
			fog:      fog
		}
	}
	return views
}

// view_bytes lays the table out for the 68000: 16 words a frame.
fn view_bytes(views []View) []u8 {
	mut words := []u16{}
	for v in views {
		words << u16(v.gem_top)
		words << u16(v.line_top)
		words << u16(v.scale)
		words << u16(v.line_x)
		for x in v.gem_x {
			words << u16(x)
		}
		words << u16(v.fog * template_bytes)
		words << u16((v.scale & 0xff) | (32 << 8)) // the line: only as wide
		for words.len % 16 != 0 {
			words << 0
		}
	}
	return jagkit.big_endian16(words)
}

// pop is, for each frame since a judgement, how large its word is drawn: it
// lands big and settles.
fn pop_scale(t int) f64 {
	return if t < 6 { 1.15 + 0.8 * math.pow(1 - f64(t) / 6, 2) } else { 1.15 }
}
