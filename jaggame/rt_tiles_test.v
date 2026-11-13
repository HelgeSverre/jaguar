module jaggame

import os
import tom
import jaggame.emulated

// The tile layer, the camera and loading rooms, on the machine. The test
// games are small: a tile set of three tiles (floor, wall, chip) and two
// rooms, a big one (30x20 tiles) and a small one (10x6).

const background = u16(0x0a30)

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

// room_text is a room of `w` by `h` tiles with walls round the edge and
// floor inside; `extra` puts other characters at places.
fn room_text(w int, h int, extra map[string]rune) string {
	mut rows := []string{}
	for y in 0 .. h {
		mut row := []rune{}
		for x in 0 .. w {
			edge := x == 0 || y == 0 || x == w - 1 || y == h - 1
			row << if edge { `#` } else { `.` }
		}
		rows << row.string()
	}
	for key, ch in extra {
		x := key.all_before(',').int()
		y := key.all_after(',').int()
		mut row := rows[y].runes()
		row[x] = ch
		rows[y] = row.string()
	}
	return '\n' + rows.join('\n') + '\n'
}

// map_game is the game of the tile layer's tests. Its update moves nothing
// by itself: the tests set the camera, the follow position and `want`, the
// room to load when A is pressed, and B takes the chip at tile (5, 3) away.
fn map_game(dir string) &Game {
	mut g := new_game(Config{ sprites: 2, layers: 1, background: background })
	g.tileset(tiles_png(dir))
	g.legend_tile(`.`, 0, 0)
	g.legend_tile(`#`, 1, flag_solid)
	g.legend_tile(`o`, 2, flag_item)
	g.legend_marker(`@`, 'start', 0, 0)
	g.room('big', room_text(30, 20, {
		'5,3':   `o`
		'20,10': `o`
		'1,1':   `@`
		'28,18': `@`
	}))
	g.room('small', room_text(10, 6, {
		'2,2': `@`
	}))
	want := g.p.u8('want')
	follow_x := g.p.i16('follow_x')
	follow_y := g.p.i16('follow_y')
	following := g.p.bool('following')
	g.art_cry('box', 16, 16, 1, []u16{len: 256, init: cry(0, 255, 0)})
	mut c := g.define_init()
	g.load_room(mut c, Room{0, 'big'})
	world := g.sprite(0)
	world.put(mut c, 'box', 100, 60, 0)
	world.hide(mut c)
	pinned := g.sprite(1)
	pinned.put(mut c, 'box', 10, 10, 0)
	c.set(pinned.fixed, true)
	pinned.hide(mut c)
	c = g.define_update()
	c.if_(g.pressed(.a))
	g.load_room_number(mut c, want)
	c.end()
	c.if_(g.pressed(.b))
	g.set_tile(mut c, 5, 3, 0)
	c.end()
	c.if_(following)
	g.camera_follow(mut c, follow_x, follow_y)
	c.end()
	return g
}

struct Rig {
	g   &Game
	img Image
	dir string
mut:
	p emulated.Player
	// where the logical screen's top left corner is in the emulator's picture
	ox int
	oy int
}

fn new_rig(name string, pal bool) Rig {
	dir := workdir(name)
	mut g := map_game(dir)
	img := g.build() or { panic(err) }
	return Rig{
		g:   g
		img: img
		dir: dir
		p:   emulated.boot(img.bytes, pal) or { panic(err) }
	}
}

fn (r &Rig) value(name string) int {
	return int(r.img.value(r.p.m.ram, name) or { panic(err) })
}

fn (mut r Rig) poke16(name string, value int) {
	at := r.img.symbols[name]
	r.p.m.ram[at] = u8(value >> 8)
	r.p.m.ram[at + 1] = u8(value)
}

fn (mut r Rig) poke8(name string, value int) {
	r.p.m.ram[r.img.symbols[name]] = u8(value)
}

// camera is where the game's camera is, from the machine's memory.
fn (r &Rig) camera() (int, int) {
	return int(i16(r.value('camera_x'))), int(i16(r.value('camera_y')))
}

// wait_loaded runs frames until the room is loaded and its picture has
// reached the screen, and returns how many frames the loading took.
fn (mut r Rig) wait_loaded() int {
	r.p.frames(2) // the machine starts and the room begins to load
	mut n := 2
	for r.value('loading') != 0 {
		r.p.frames(1)
		n++
		assert n < 400, 'the room never finished loading'
	}
	r.p.frames(3)
	return n
}

// rgb_of is the picture's colour for a palette entry of the game.
fn (r &Rig) rgb_of(index int) u32 {
	return tom.cry_to_rgb(u32(r.g.palette[index]))
}

// tile_rgb is the colour of pixel (x, y) of a tile of the tile set, as the
// machine should show it.
fn (r &Rig) tile_rgb(tile int, x int, y int) u32 {
	art := r.g.arts[r.g.tileset_art]
	index := art.pixels[tile * 256 + y * 16 + x]
	return r.rgb_of(int(index))
}

// expected is what the logical screen should show at (sx, sy) with the
// camera at (cx, cy): the room, from the map in the machine's memory, or
// the background.
fn (r &Rig) expected(cx int, cy int, sx int, sy int) u32 {
	wx := sx + cx
	wy := sy + cy
	w := r.value('rt_room_w')
	h := r.value('rt_room_h')
	if wx < 0 || wy < 0 || wx >= w * 16 || wy >= h * 16 {
		return tom.cry_to_rgb(u32(background))
	}
	tile := int(r.img.element(r.p.m.ram, 'rt_map', (wy / 16) * w + wx / 16) or { panic(err) })
	return r.tile_rgb(tile, wx % 16, wy % 16)
}

// matches counts the pixels of a grid of samples of the logical screen that
// the picture shows as expected, with the screen's corner at (ox, oy).
fn (r &Rig) matches(cx int, cy int, ox int, oy int, step int) (int, int) {
	pic := r.p.picture()
	mut good := 0
	mut all := 0
	for sy := 0; sy < 240; sy += step {
		for sx := 0; sx < 320; sx += step {
			if sx + ox < 0 || sy + oy < 0 || sx + ox >= pic.width || sy + oy >= pic.height {
				continue // the emulator does not show the whole display window
			}
			all++
			if pic.at(sx + ox, sy + oy) == r.expected(cx, cy, sx, sy) {
				good++
			}
		}
	}
	return good, all
}

// find_origin looks for the place of the logical screen in the emulator's
// picture, which shows only the middle of the display window, and keeps it.
fn (mut r Rig) find_origin() {
	cx, cy := r.camera()
	mut best := 0
	for oy in -8 .. 9 {
		for ox in -8 .. 9 {
			good, _ := r.matches(cx, cy, ox, oy, 7)
			if good > best {
				best = good
				r.ox = ox
				r.oy = oy
			}
		}
	}
}

// assert_screen checks the whole logical screen against what it should be.
fn (r &Rig) assert_screen(what string) {
	cx, cy := r.camera()
	good, all := r.matches(cx, cy, r.ox, r.oy, 1)
	assert all > 320 * 230 * 9 / 10, 'most of the screen is in the picture: ${all}'
	assert good == all, '${what}: camera (${cx}, ${cy}): ${all - good} of ${all} pixels are not as expected'
}

fn test_a_room_loads_in_slices_and_then_shows() {
	for pal in [false, true] {
		mut r := new_rig('load', pal)
		r.p.frames(2)
		assert r.value('loading') == 1
		start := r.value('frame')
		// Blank while it loads: only the background.
		pic := r.p.picture()
		blank := pic.bounds(0, 0, pic.width, pic.height, fn (px u32) bool {
			return px != tom.cry_to_rgb(u32(background))
		})
		assert blank.count == 0, 'no tiles and no sprites while a room loads'
		r.wait_loaded()
		// 600 tiles, 48 a frame (13 frames), and a frame to blank the picture first.
		frames := r.value('frame') - 3 - start + 2
		assert frames == 1 + (600 + tiles_per_frame - 1) / tiles_per_frame, 'frames to load: ${frames}'
		assert r.value('missed_frames') == 0
		assert r.value('room_width') == 480 && r.value('room_height') == 320
		r.find_origin()
		println('the logical screen starts at ${r.ox}, ${r.oy} of the emulator picture (${if pal {
			'PAL'
		} else {
			'NTSC'
		}})')
		r.assert_screen('the first screen')
	}
}

fn test_the_camera_scrolls_by_single_pixels_and_stops_where_the_poked_values_put_it() {
	for pal in [false, true] {
		mut r := new_rig('scroll', pal)
		r.wait_loaded()
		r.find_origin()
		for cam in [[0, 0], [1, 0], [2, 0], [7, 0], [8, 0], [9, 1],
			[15, 15], [16, 17], [100, 60], [159, 79], [160, 80],
			[3, 80], [160, 0], [161, 81]] {
			r.poke16('camera_x', cam[0])
			r.poke16('camera_y', cam[1])
			r.p.frames(3)
			if cam[0] > 160 || cam[1] > 80 {
				continue // past the room: only checked for not crashing
			}
			r.assert_screen('scrolled')
		}
		assert r.value('missed_frames') == 0
	}
}

fn test_follow_centres_clamps_and_centres_a_small_room() {
	mut r := new_rig('follow', false)
	r.wait_loaded()
	r.poke8('following', 1)
	for pos in [[240, 160, 80, 40], [0, 0, 0, 0], [479, 319, 160, 80],
		[300, 100, 140, 0], [10, 300, 0, 80]] {
		r.poke16('follow_x', pos[0])
		r.poke16('follow_y', pos[1])
		r.p.frames(3)
		cx, cy := r.camera()
		assert [cx, cy] == [pos[2], pos[3]], 'follow (${pos[0]}, ${pos[1]}): camera ${cx}, ${cy}'
	}
	r.find_origin()
	r.assert_screen('following')

	// The small room, 160x96 pixels, is centred: the camera is negative.
	r.poke8('want', 1)
	r.p.hold(.a, 1)
	r.wait_loaded()
	r.p.frames(3)
	cx, cy := r.camera()
	assert cx == -80 && cy == -72, 'centred: ${cx}, ${cy}'
	assert r.value('room_width') == 160 && r.value('room_height') == 96
	r.assert_screen('the small room')
	// And its picture sits in the middle: the background on all sides.
	pic := r.p.picture()
	assert pic.at(r.ox + 10, r.oy + 10) == tom.cry_to_rgb(u32(background))
	assert pic.at(r.ox + 160, r.oy + 120) != tom.cry_to_rgb(u32(background))
}

fn test_changing_a_tile_changes_the_picture() {
	mut r := new_rig('settile', false)
	r.wait_loaded()
	r.find_origin()
	assert r.value('rt_map') == 1
	chip := r.img.element(r.p.m.ram, 'rt_map', 3 * 30 + 5)!
	assert chip == 2
	r.assert_screen('before')
	assert r.p.picture().at(r.ox + 5 * 16 + 8, r.oy + 3 * 16 + 8) == r.tile_rgb(2, 8, 8), 'the chip is white in the middle'
	r.p.hold(.b, 1)
	r.p.frames(3)
	assert r.img.element(r.p.m.ram, 'rt_map', 3 * 30 + 5)! == 0
	assert r.p.picture().at(r.ox + 5 * 16 + 8, r.oy + 3 * 16 + 8) != r.tile_rgb(2, 8, 8)
	r.assert_screen('after')
	assert r.value('rt_tile_lost') == 0
}

fn is_green(px u32) bool {
	return (px >> 8) & 0xff > 200 && (px >> 16) & 0xff < 80
}

fn test_a_sprite_takes_world_coordinates_unless_it_is_fixed() {
	for pal in [false, true] {
		mut r := new_rig('sprites', pal)
		r.wait_loaded()
		r.find_origin()
		for i in 0 .. 2 {
			r.p.m.ram[r.img.field_address('sprites', i, 'visible')!] = 1
		}
		r.poke16('camera_x', 50)
		r.poke16('camera_y', 40)
		r.p.frames(3)
		pic := r.p.picture()
		// The world sprite is at (100, 60): on the screen at (50, 20).
		world := pic.bounds(r.ox + 40, r.oy + 10, r.ox + 80, r.oy + 50, is_green)
		assert world.count == 256, 'the world sprite is drawn once, whole: ${world.count}'
		assert world.left == r.ox + 50 && world.top == r.oy + 20, 'at ${world.left - r.ox}, ${world.top - r.oy}'
		// The fixed sprite stays at (10, 10) whatever the camera does.
		pinned := pic.bounds(r.ox, r.oy, r.ox + 40, r.oy + 40, is_green)
		assert pinned.count == 256 && pinned.left == r.ox + 10 && pinned.top == r.oy + 10
		r.poke16('camera_x', 90)
		r.poke16('camera_y', 0)
		r.p.frames(3)
		pic2 := r.p.picture()
		moved := pic2.bounds(r.ox, r.oy + 55, r.ox + 40, r.oy + 80, is_green)
		assert moved.left == r.ox + 10 && moved.top == r.oy + 60, 'the world sprite moved to ${moved.left - r.ox}, ${moved.top - r.oy}'
		still := pic2.bounds(r.ox, r.oy, r.ox + 40, r.oy + 40, is_green)
		assert still.left == r.ox + 10 && still.top == r.oy + 10, 'the fixed one did not'
		assert r.value('missed_frames') == 0
	}
}

fn test_the_markers_come_back_as_positions_in_the_loaded_room() {
	dir := workdir('markers')
	mut g := map_game(dir)
	first_x := g.p.i16('first_x')
	first_y := g.p.i16('first_y')
	second_x := g.p.i16('second_x')
	missing := g.p.i16('missing')
	count := g.p.u8('count')
	// The update of map_game is already defined; add a second function the
	// test calls by name.
	probe := g.p.func('probe', [], .void)
	mut c := g.p.define(probe)
	c.set(first_x, g.marker_x('start', 0))
	c.set(first_y, g.marker_y('start', 0))
	c.set(second_x, g.marker_x('start', 1))
	c.set(missing, g.marker_x('start', 2))
	c.set(count, g.marker_count('start'))
	mut it := g.interpreter(.ntsc)!
	for _ in 0 .. 30 {
		g.step(mut it, 0)!
	}
	it.run('probe')!
	// The big room has two places for the player: (1, 1) and (28, 18).
	assert [it.value('first_x')!, it.value('first_y')!, it.value('second_x')!,
		it.value('missing')!, it.value('count')!] == [i64(1), 1, 28, -1, 2]
	// The small room has one: (2, 2).
	it.set_value('want', 1)!
	g.step(mut it, button_mask(.a))!
	it.run('probe')!
	assert [it.value('first_x')!, it.value('first_y')!, it.value('second_x')!,
		it.value('count')!] == [
		i64(2),
		2,
		-1,
		1,
	]
	assert g.markers_of(Room{0, 'big'}, 'start') == [Point{1, 1},
		Point{28, 18}]
}

fn test_what_the_tile_layer_costs() {
	// The same game without a tile layer.
	mut plain := new_game(Config{ sprites: 2, layers: 1, background: background })
	plain.art_cry('box', 16, 16, 1, []u16{len: 256, init: cry(0, 255, 0)})
	plain.define_init()
	plain.define_update()
	plain_img := plain.build() or { panic(err) }
	mut q := emulated.boot(plain_img.bytes, false) or { panic(err) }
	q.frames(30)
	without := q.busy_cycles(30)

	mut r := new_rig('cost', false)
	r.wait_loaded()
	with_layer := r.p.busy_cycles(30)
	r.poke8('following', 1)
	r.p.frames(3)
	following := r.p.busy_cycles(30)
	r.poke8('following', 0)
	for cam in 0 .. 60 {
		r.poke16('camera_x', cam)
		r.p.frames(1)
	}
	println('tile layer: ${with_layer - without} cycles a frame (empty game ${without}), with the camera following ${following - without}')
	assert with_layer - without < 3500, 'the layer costs ${with_layer - without}'
	assert following - without < 7000

	// A room loading: what its frames cost.
	mut l := new_rig('loadcost', false)
	l.p.frames(2)
	mut worst := 0
	mut n := 2
	for l.value('loading') != 0 {
		worst = int_max(worst, l.p.busy_cycles(1))
		n++
		assert n < 100
	}
	println('room load: the 30x20 room takes ${n} frames, at most ${worst} cycles a frame')
	assert worst < 180000
	assert l.value('missed_frames') == 0
}
