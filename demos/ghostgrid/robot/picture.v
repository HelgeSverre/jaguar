module robot

import stbi
import tom
import jaggame

// What the screen shows, checked against the map: the picture is the room's
// tiles with the sprites and the text over them.

// tile_colours are the colours of a tile set as the machine shows them: 16 by
// 16 pixels for each tile, 0x00RRGGBB.
pub fn tile_colours(path string) [][]u32 {
	img := stbi.load(path) or { panic(err) }
	mut tiles := [][]u32{}
	for t in 0 .. img.width / 16 {
		mut pixels := []u32{}
		for y in 0 .. 16 {
			for x in 0 .. 16 {
				i := (y * img.width + t * 16 + x) * 4
				r, g, bl := int(unsafe { img.data[i] }), int(unsafe { img.data[i + 1] }), int(unsafe {
					img.data[i + 2]
				})
				pixels << tom.cry_to_rgb(u32(jaggame.cry(r, g, bl)))
			}
		}
		tiles << pixels
	}
	return tiles
}

// covered tells whether a pixel of the logical screen belongs to something
// that is not the room: a sprite or the text.
fn (b &Booted) covered(cx int, cy int, sx int, sy int) bool {
	if (sx < 150 && sy < 36) || (sx >= 244 && sy < 36) {
		return true // the text of the status lines
	}
	for i in 0 .. 14 {
		if b.field('sprites', i, 'visible') == 0 {
			continue
		}
		fixed := b.field('sprites', i, 'fixed') != 0
		x := int(i16(b.field('sprites', i, 'x'))) - if fixed { 0 } else { cx }
		y := int(i16(b.field('sprites', i, 'y'))) - if fixed { 0 } else { cy }
		size := if i == 12 {
			220
		} else if i == 13 {
			50
		} else {
			17
		}
		h := if i == 12 { 130 } else { size }
		if sx >= x - 1 && sx < x + size && sy >= y - 1 && sy < y + h {
			return true
		}
	}
	return false
}

// matches counts how many pixels of the room part of the logical screen are
// what they should be, and how many there are, with the screen at (ox, oy)
// in the emulator's picture. The room is what is in the map now: the lit
// tiles are tiles of their own.
pub fn (b &Booted) matches(tiles [][]u32, background_cry u16, step int) (int, int) {
	cx := int(i16(b.value('camera_x')))
	cy := int(i16(b.value('camera_y')))
	pic := b.p.picture()
	w := b.value('rt_room_w')
	h := b.value('rt_room_h')
	background := tom.cry_to_rgb(u32(background_cry))
	mut good := 0
	mut all := 0
	for sy := 0; sy < 240; sy += step {
		for sx := 0; sx < 320; sx += step {
			if sx + b.ox < 0 || sy + b.oy < 0 || sx + b.ox >= pic.width || sy + b.oy >= pic.height {
				continue
			}
			if b.covered(cx, cy, sx, sy) {
				continue
			}
			all++
			wx := sx + cx
			wy := sy + cy
			want := if wx < 0 || wy < 0 || wx >= w * 16 || wy >= h * 16 {
				background
			} else {
				tile := b.element('rt_map', (wy / 16) * w + wx / 16)
				tiles[tile][(wy % 16) * 16 + wx % 16]
			}
			if pic.at(sx + b.ox, sy + b.oy) == want {
				good++
			}
		}
	}
	return good, all
}

// find_origin looks for where the logical screen's top left corner is in the
// emulator's picture, the offset that matches most.
pub fn (mut b Booted) find_origin(tiles [][]u32, background_cry u16) {
	mut best_ox := 0
	mut best_oy := 0
	mut top := 0
	for oy in -8 .. 9 {
		for ox in -8 .. 9 {
			b.ox = ox
			b.oy = oy
			good, _ := b.matches(tiles, background_cry, 5)
			if good > top {
				top = good
				best_ox = ox
				best_oy = oy
			}
		}
	}
	b.ox = best_ox
	b.oy = best_oy
}
