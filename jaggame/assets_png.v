module jaggame

import os
import stbi
import jagkit

// PNG import. Pictures are read when the game is described, cut into frames
// by a grid and turned into the art the sprites and the tile layer use.
// Every mistake (a missing file, a size the grid does not divide, a width
// that does not fill whole phrases, colours that do not fit the palette) is
// recorded against the file's name and reported with all the others when
// the game is built.
//
// A pixel with an alpha below 128 is transparent: it becomes the pixel value
// 0. Every other pixel is opaque and keeps its colour, which is never 0 (an
// opaque black becomes the darkest colour above it).

// Rgba is a decoded picture: four bytes a pixel, red, green, blue and alpha,
// a line after a line.
struct Rgba {
	width  int
	height int
	pixels []u8
}

// read_png decodes a PNG file, or says what is wrong with it.
fn read_png(path string) !Rgba {
	if !os.exists(path) {
		return error('${path}: the file does not exist')
	}
	img := stbi.load(path) or { return error('${path}: this is not a PNG that can be read') }
	defer {
		img.free()
	}
	count := img.width * img.height * 4
	mut pixels := []u8{len: count}
	unsafe { vmemcpy(pixels.data, img.data, count) }
	return Rgba{
		width:  img.width
		height: img.height
		pixels: pixels
	}
}

// opaque tells whether a pixel is drawn.
fn (img Rgba) opaque(x int, y int) bool {
	return img.pixels[(y * img.width + x) * 4 + 3] >= 128
}

// colour_at is the CRY colour of an opaque pixel, never 0.
fn (img Rgba) colour_at(x int, y int, mut known map[int]u16) u16 {
	i := (y * img.width + x) * 4
	key := int(img.pixels[i]) * 65536 + int(img.pixels[i + 1]) * 256 + int(img.pixels[i + 2])
	if key in known {
		return known[key]
	}
	mut c := jagkit.cry(int(img.pixels[i]), int(img.pixels[i + 1]), int(img.pixels[i + 2]))
	if c == 0 {
		c = 1
	}
	known[key] = c
	return c
}

// rgb_text is a colour as it is written in a message.
fn (img Rgba) rgb_text(x int, y int) string {
	i := (y * img.width + x) * 4
	return '#${img.pixels[i]:02x}${img.pixels[i + 1]:02x}${img.pixels[i + 2]:02x}'
}

// grid_problem checks that a grid divides a picture and that the cells fill
// whole phrases at a depth. It returns what is wrong, or an empty string.
fn grid_problem(path string, img Rgba, cell_w int, cell_h int, bits int) string {
	if cell_w < 1 || cell_h < 1 {
		return '${path}: the cell ${cell_w}x${cell_h} is not a size'
	}
	if img.width % cell_w != 0 || img.height % cell_h != 0 {
		return '${path}: the picture is ${img.width}x${img.height} pixels, which a grid of ${cell_w}x${cell_h} does not divide (${img.width % cell_w} columns and ${img.height % cell_h} lines are left over)'
	}
	per_phrase := 64 / bits
	if cell_w % per_phrase != 0 {
		return '${path}: a cell ${cell_w} pixels wide at ${bits} bits does not fill whole 64-bit phrases; the width must be a multiple of ${per_phrase}'
	}
	if cell_w * cell_h * bits / 8 > 65535 {
		return '${path}: a frame of ${cell_w}x${cell_h} pixels is more than 65535 bytes'
	}
	frames := img.width / cell_w * (img.height / cell_h)
	if frames > 255 {
		return '${path}: ${frames} frames; at most 255'
	}
	return ''
}

// png_cry reads a PNG as art of 16-bit CRY pixels, cut into frames by a grid
// of `cell_w` by `cell_h` pixels. The frames are numbered across and then
// down. The cell width must be a multiple of 4.
pub fn (mut g Game) png_cry(name string, path string, cell_w int, cell_h int) Art {
	img := read_png(path) or {
		g.problem('art `${name}`: ${err.msg()}')
		return g.failed_art(name)
	}
	bad := grid_problem(path, img, cell_w, cell_h, 16)
	if bad != '' {
		g.problem('art `${name}`: ${bad}')
		return g.failed_art(name)
	}
	mut known := map[int]u16{}
	mut pixels := []u16{cap: img.width * img.height}
	for cy in 0 .. img.height / cell_h {
		for cx in 0 .. img.width / cell_w {
			for y in 0 .. cell_h {
				for x in 0 .. cell_w {
					px := cx * cell_w + x
					py := cy * cell_h + y
					pixels << if img.opaque(px, py) {
						img.colour_at(px, py, mut known)
					} else {
						u16(0)
					}
				}
			}
		}
	}
	return g.art_cry(name, cell_w, cell_h, img.width / cell_w * (img.height / cell_h), pixels)
}

// png_pal reads a PNG as art of 8-bit pixels that index the game's palette,
// cut into frames by a grid like `png_cry`. The cell width must be a
// multiple of 8. If the game declared its palette (`palette`), every colour
// in the picture must be in it; if not, the colours of the picture are added
// to a palette that grows with each picture, in the order they are found
// (entry 0 is the transparent colour).
pub fn (mut g Game) png_pal(name string, path string, cell_w int, cell_h int) Art {
	img := read_png(path) or {
		g.problem('art `${name}`: ${err.msg()}')
		return g.failed_art(name)
	}
	bad := grid_problem(path, img, cell_w, cell_h, 8)
	if bad != '' {
		g.problem('art `${name}`: ${bad}')
		return g.failed_art(name)
	}
	if !g.palette_fixed && g.palette.len == 0 {
		g.palette << 0
		g.palette_index[u16(0)] = 0
	}
	before := g.palette.len
	mut known := map[int]u16{}
	mut missing := map[u16]string{}
	mut pixels := []u8{cap: img.width * img.height}
	cells_across := img.width / cell_w
	cells_down := img.height / cell_h
	for cy in 0 .. cells_down {
		for cx in 0 .. cells_across {
			for y in 0 .. cell_h {
				for x in 0 .. cell_w {
					px := cx * cell_w + x
					py := cy * cell_h + y
					if !img.opaque(px, py) {
						pixels << 0
						continue
					}
					colour := img.colour_at(px, py, mut known)
					index := g.palette_index[colour] or {
						if g.palette_fixed {
							if colour !in missing {
								missing[colour] = '${img.rgb_text(px, py)} at (${px}, ${py})'
							}
							pixels << 0
							continue
						}
						if g.palette.len >= 256 {
							pixels << 0
							continue
						}
						g.palette << colour
						g.palette_index[colour] = g.palette.len - 1
						g.palette.len - 1
					}
					pixels << u8(index)
				}
			}
		}
	}
	if missing.len > 0 {
		mut shown := []string{}
		for _, text in missing {
			if shown.len < 4 {
				shown << text
			}
		}
		g.problem('art `${name}`: ${path} uses ${missing.len} colours that are not in the palette, for example ${shown.join(', ')}')
	}
	if g.palette.len > before {
		g.palette_sources << '${path} (${g.palette.len - before})'
	}
	return g.art_pal(name, cell_w, cell_h, cells_across * cells_down, pixels)
}

// failed_art stands in for a picture that could not be read, so that one
// mistake does not hide the next: no art is added, the game is already
// marked as wrong.
fn (mut g Game) failed_art(name string) Art {
	return Art{
		id:   -1
		name: name
	}
}
