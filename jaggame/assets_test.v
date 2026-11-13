module jaggame

import os

// Assets: PNG import, palettes, tile sets and maps, and the mistakes an
// author can make with them.

// workdir is a fresh directory for the files of one test.
fn workdir(name string) string {
	dir := os.join_path(os.temp_dir(), 'jaggame_${os.getpid()}_${name}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// tiles_png writes a tile set of floor, wall and chip tiles, 16x16 each, and
// returns its path. The floor has a lit line along its left and top; the
// wall a lit top edge; the chip a white centre on the floor colour.
fn tiles_png(dir string) string {
	mut pic := new_canvas(48, 16)
	pic.fill(0, 0, 16, 16, 30, 60, 90)
	pic.fill(0, 0, 1, 16, 60, 120, 180)
	pic.fill(0, 0, 16, 1, 60, 120, 180)
	pic.fill(16, 0, 16, 16, 200, 60, 60)
	pic.fill(16, 0, 16, 2, 255, 160, 160)
	pic.fill(32, 0, 16, 16, 30, 60, 90)
	pic.fill(36, 4, 8, 8, 255, 255, 255)
	path := os.join_path(dir, 'tiles.png')
	pic.save(path) or { panic(err) }
	return path
}

fn problems_of(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}

fn test_a_sheet_is_cut_into_frames_by_a_grid() {
	dir := workdir('sheet')
	mut pic := new_canvas(32, 16)
	pic.fill(0, 0, 16, 16, 255, 0, 0)
	pic.fill(16, 0, 16, 16, 0, 255, 0)
	pic.put(16, 0, 0, 0, 0, 0) // a transparent corner of frame 1
	path := os.join_path(dir, 'sheet.png')
	pic.save(path) or { panic(err) }

	mut g := new_game(Config{ sprites: 1, layers: 1 })
	art := g.png_cry('sheet', path, 16, 16)
	assert art.id == 0
	info := g.arts[0]
	assert info.frames == 2 && info.width == 16 && info.height == 16 && info.bits == 16
	// Two frames of 16x16 at two bytes a pixel; frame 1's first pixel is transparent,
	// its second is green (never 0), and frame 0 is red everywhere.
	assert info.pixels.len == 2 * 16 * 16 * 2
	assert info.pixels[512..514] == [u8(0), 0]
	assert info.pixels[514..516] != [u8(0), 0]
	assert info.pixels[0..2] != [u8(0), 0]
	assert info.pixels[0..2] != info.pixels[514..516], 'red and green are different colours'
	assert g.p.problems.len == 0
}

fn test_eight_bit_art_builds_the_palette_from_the_pictures() {
	dir := workdir('palette')
	mut pic := new_canvas(16, 8)
	pic.fill(0, 0, 8, 8, 255, 0, 0)
	pic.fill(8, 0, 8, 8, 0, 0, 255)
	pic.put(0, 0, 0, 0, 0, 0)
	pic.put(1, 0, 0, 0, 0, 255) // opaque black is not transparent
	path := os.join_path(dir, 'a.png')
	pic.save(path) or { panic(err) }
	mut second := new_canvas(8, 8)
	second.fill(0, 0, 8, 8, 0, 0, 255) // blue again, and nothing new
	path2 := os.join_path(dir, 'b.png')
	second.save(path2) or { panic(err) }

	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.png_pal('a', path, 8, 8)
	g.png_pal('b', path2, 8, 8)
	assert g.palette.len == 4, 'transparent, red, black, blue: ${g.palette.len}'
	assert g.palette[0] == 0
	a := g.arts[0].pixels
	assert a[0] == 0, 'a transparent pixel is 0'
	assert a[1] != 0 && g.palette[int(a[1])] != 0, 'opaque black gets its own entry'
	assert g.arts[1].pixels.all(it == g.arts[0].pixels[8 * 8 + 7]), 'the same blue, the same index'
	assert g.p.problems.len == 0
}

fn test_a_declared_palette_must_hold_every_colour() {
	dir := workdir('fixed')
	mut pic := new_canvas(8, 8)
	pic.fill(0, 0, 8, 8, 255, 0, 0)
	pic.fill(0, 0, 2, 2, 0, 255, 0)
	path := os.join_path(dir, 'x.png')
	pic.save(path) or { panic(err) }
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.palette([u16(0), cry(255, 0, 0)])
	g.png_pal('x', path, 8, 8)
	text := problems_of(mut g)
	assert text.contains('art `x`: ${path} uses 1 colours that are not in the palette'), text
	assert text.contains('#00ff00 at (0, 0)'), text
}

fn test_a_palette_declared_after_the_pictures_is_refused() {
	dir := workdir('late')
	mut pic := new_canvas(8, 8)
	pic.fill(0, 0, 8, 8, 255, 0, 0)
	path := os.join_path(dir, 'x.png')
	pic.save(path) or { panic(err) }
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.png_pal('x', path, 8, 8)
	g.palette([u16(0), cry(255, 0, 0)])
	assert problems_of(mut g).contains('palette() is called after the pictures ${path} (')
}

fn test_too_many_colours_name_the_files_that_made_them() {
	dir := workdir('colours')
	mut pic := new_canvas(32, 32)
	for i in 0 .. 1024 {
		pic.fill(i % 32, i / 32, 1, 1, (i * 7) % 256, (i * 13) % 256, 255 - i % 256)
	}
	path := os.join_path(dir, 'rainbow.png')
	pic.save(path) or { panic(err) }
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.text_layer('hud', TextConfig{ columns: 8, rows: 1 })
	g.png_pal('rainbow', path, 8, 8)
	text := problems_of(mut g)
	assert text.contains('colours; with 1 text layers there is room for 254'), text
	assert text.contains('the pictures added them: ${path} ('), text
}

fn test_every_asset_mistake_names_the_file_and_the_problem() {
	dir := workdir('mistakes')
	mut pic := new_canvas(40, 20)
	pic.fill(0, 0, 40, 20, 9, 9, 9)
	odd := os.join_path(dir, 'odd.png')
	pic.save(odd) or { panic(err) }
	missing := os.join_path(dir, 'nothing.png')
	garbage := os.join_path(dir, 'garbage.png')
	os.write_file(garbage, 'this is not a picture') or { panic(err) }

	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.png_cry('a', missing, 16, 16)
	g.png_cry('b', garbage, 16, 16)
	g.png_cry('c', odd, 16, 16) // 40x20 is not a multiple of 16
	g.png_cry('d', odd, 10, 20) // 10 pixels of 16 bits do not fill a phrase
	g.png_pal('e', odd, 20, 20) // 20 pixels of 8 bits do not fill a phrase
	g.png_pal('f', odd, 0, 4)
	text := problems_of(mut g)
	for part in [
		'${missing}: the file does not exist',
		'${garbage}: this is not a PNG that can be read',
		'${odd}: the picture is 40x20 pixels, which a grid of 16x16 does not divide (8 columns and 4 lines are left over)',
		'${odd}: a cell 10 pixels wide at 16 bits does not fill whole 64-bit phrases; the width must be a multiple of 4',
		'${odd}: a cell 20 pixels wide at 8 bits does not fill whole 64-bit phrases; the width must be a multiple of 8',
		'${odd}: the cell 0x4 is not a size',
	] {
		assert text.contains(part), 'missing: ${part}\nin:\n${text}'
	}
}

// legend_game is a game with the test tiles and a small legend.
fn legend_game(dir string) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(tiles_png(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`o`, 2, flag_item)
	g.legend_marker(`@`, 'start', 0)
	g.legend_marker(`g`, 'guard', 0)
	return g
}

fn test_a_room_comes_back_as_tiles_and_marker_positions() {
	dir := workdir('room')
	mut g := legend_game(dir)
	lab := g.room('lab', '
#####
#@.g#
#o.g#
#####
')
	width, height := g.room_size(lab)
	assert width == 5 && height == 4
	assert g.markers_of(lab, 'start') == [Point{1, 1}]
	assert g.markers_of(lab, 'guard') == [Point{3, 1}, Point{3, 2}]
	assert g.markers_of(lab, 'nobody').len == 0
	assert g.rooms[0].tiles == [u8(1), 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 2, 0, 0, 1, 1, 1, 1, 1, 1]
	assert g.p.problems.len == 0
	// The flags belong to the tiles.
	flags := g.flag_table()
	assert flags[0] == 0 && flags[1] == flag_solid && flags[2] == flag_item
	assert flags[tile_none] == flag_solid
}

fn test_map_mistakes_are_reported_together() {
	dir := workdir('mapmistakes')
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(tiles_png(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`.`, 2, 0) // given twice
	g.legend_tile(`+`, 9, 0) // the tile set has three tiles
	g.legend_tile(`x`, 1, 0) // the wall tile with other flags
	g.legend_marker(`@`, 'start', 7) // no such tile
	g.legend_marker(`#`, 'wall', 0) // a tile already
	g.room('ragged', '
####
##
####
')
	g.room('strangers', '
#.#
#?!
')
	g.room('empty', '
')
	g.room('huge', '#'.repeat(65))
	text := problems_of(mut g)
	for part in [
		'legend: the character `.` is given twice',
		'legend: the character `#` is both a tile and the marker `wall`',
		'room `ragged`: row 2 has 2 characters, row 1 has 4',
		'room `strangers`: `?` at row 2, column 2 is not in the legend',
		'room `strangers`: `!` at row 2, column 3 is not in the legend',
		'room `empty`: it has no rows',
		'room `huge`: 65x1 tiles; a room is 1..64 wide and high',
		'legend: the character `+` is tile 9, but the tile set ${tiles_png(dir)} has 3 tiles',
		'legend: tile 1 has flags 1 as `#` and 0 as `x`; the flags belong to the tile',
		'legend: the marker `start` is drawn as tile 7',
	] {
		assert text.contains(part), 'missing: ${part}\nin:\n${text}'
	}
}

fn test_a_game_with_rooms_needs_a_tile_set() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.legend_tile(`.`, 0, 0)
	g.room('lab', '..')
	g.build() or {
		assert err.msg().contains('no tile set')
		return
	}
	assert false
}

fn test_a_tile_set_must_be_16_by_16_tiles() {
	dir := workdir('tileset')
	mut pic := new_canvas(24, 16)
	pic.fill(0, 0, 24, 16, 5, 5, 5)
	path := os.join_path(dir, 'tiles.png')
	pic.save(path) or { panic(err) }
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.tileset(path)
	g.tileset(path)
	text := problems_of(mut g)
	assert text.contains('${path}: the picture is 24x16 pixels, which a grid of 16x16 does not divide'), text
	assert text.contains('tileset: the game already has a tile set'), text
}
