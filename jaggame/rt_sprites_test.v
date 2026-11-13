module jaggame

import jaggame.emulated

// Sprites on the machine: layer order, clipping, scale, flip, palette art and
// frames, looked at in the display list that the runtime builds and in the
// picture the emulator draws.

fn solid(w int, h int, colour u16) []u16 {
	return []u16{len: w * h, init: colour}
}

fn red() u16 {
	return cry(255, 0, 0)
}

fn green() u16 {
	return cry(0, 255, 0)
}

fn blue() u16 {
	return cry(0, 0, 255)
}

fn is_red(px u32) bool {
	return (px >> 16) & 0xff > 150 && (px >> 8) & 0xff < 100 && px & 0xff < 100
}

fn is_green(px u32) bool {
	return (px >> 8) & 0xff > 150 && (px >> 16) & 0xff < 100 && px & 0xff < 100
}

fn is_blue(px u32) bool {
	return px & 0xff > 150 && (px >> 16) & 0xff < 100 && (px >> 8) & 0xff < 100
}

fn lit_pixel(px u32) bool {
	return px != 0
}

fn boot_image(img Image, pal bool) emulated.Player {
	mut p := emulated.boot(img.bytes, pal) or { panic(err) }
	p.frames(5)
	return p
}

// front is the display list the object processor shows next.
fn front(img Image, p &emulated.Player) u32 {
	return p.peek32(img.symbols['rt.front'])
}

// shown is a game with one 16x16 red sprite at a place, and what the
// runtime made of it.
fn shown(x int, y int, scale f64, pal bool) (Image, emulated.Player) {
	mut g := new_game(Config{ sprites: 2, layers: 2 })
	g.art_cry('box', 16, 16, 1, solid(16, 16, red()))
	mut c := g.define_init()
	mut s := g.sprite(0)
	s.put(mut c, 'box', x, y, 0)
	c.set(s.scale, scale)
	img := g.build() or { panic(err) }
	p := boot_image(img, pal)
	return img, p
}

fn test_a_sprite_is_drawn_where_it_is() {
	img, p := shown(100, 50, 1.0, false)
	objects := p.list_objects(front(img, p))
	assert objects.len == 1
	o := objects[0]
	// NTSC: the picture starts at half-line 25 and at pixel 16 of the display window.
	assert o.ypos == 25 + 2 * 50
	assert o.xpos == 16 + 100
	assert o.height == 16
	assert o.kind == 0
	assert o.data == img.symbols['rt.art.0']
	assert o.depth == 4 && o.iwidth == 4 && o.trans
	pic := p.picture()
	box := pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
	assert box.count == 256
	assert box.right - box.left == 15 && box.bottom - box.top == 15
}

fn test_the_lists_take_turns_and_the_picture_stays() {
	img, mut p := shown(100, 50, 1.0, false)
	mut seen := map[u32]int{}
	for _ in 0 .. 12 {
		p.frames(1)
		seen[front(img, p)]++
		pic := p.picture()
		assert pic.bounds(0, 0, pic.width, pic.height, lit_pixel).count == 256, 'every frame needs a fresh list: the object processor uses one up'
	}
	assert seen.len == 2
	for _, n in seen {
		assert n == 6
	}
}

// layer_game has three overlapping 16x16 sprites: red on layer 2 (the first
// in the pool), green on layer 0, blue on layer 1, and two more on one layer.
fn test_layers_decide_the_order_not_the_pool() {
	mut g := new_game(Config{ sprites: 5, layers: 3 })
	g.art_cry('red', 16, 16, 1, solid(16, 16, red()))
	g.art_cry('green', 16, 16, 1, solid(16, 16, green()))
	g.art_cry('blue', 16, 16, 1, solid(16, 16, blue()))
	mut c := g.define_init()
	mut a := g.sprite(0)
	mut b := g.sprite(1)
	mut d := g.sprite(2)
	a.put(mut c, 'red', 100, 100, 2)
	b.put(mut c, 'green', 104, 104, 0)
	d.put(mut c, 'blue', 108, 108, 1)
	// Two on one layer: the later one in the pool is on top.
	mut e := g.sprite(3)
	mut f := g.sprite(4)
	e.put(mut c, 'red', 200, 100, 1)
	f.put(mut c, 'green', 204, 100, 1)
	img := g.build() or { panic(err) }
	p := boot_image(img, false)

	objects := p.list_objects(front(img, p))
	datas := objects.map(it.data)
	art := fn [img] (n int) u32 {
		return img.symbols['rt.art.${n}']
	}
	// Layer 0 (green), then layer 1 in pool order (blue, red, green), then layer 2 (red).
	assert datas == [art(1), art(2), art(0), art(1), art(0)]

	pic := p.picture()
	all := pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
	ox := all.left - 100
	oy := all.top - 100
	assert is_red(pic.at(110 + ox, 110 + oy)), 'red is on layer 2: above the others'
	assert is_red(pic.at(105 + ox, 105 + oy)), 'red over green'
	assert is_blue(pic.at(118 + ox, 112 + oy)), 'blue (layer 1) over green (layer 0)'
	assert is_green(pic.at(210 + ox, 105 + oy)), 'on one layer the later sprite of the pool is on top'
	assert is_red(pic.at(202 + ox, 105 + oy))
}

fn test_a_layer_above_the_last_is_drawn_with_the_last() {
	mut g := new_game(Config{ sprites: 2, layers: 2 })
	g.art_cry('red', 16, 16, 1, solid(16, 16, red()))
	g.art_cry('green', 16, 16, 1, solid(16, 16, green()))
	mut c := g.define_init()
	mut a := g.sprite(0)
	mut b := g.sprite(1)
	a.put(mut c, 'red', 100, 100, 200)
	b.put(mut c, 'green', 100, 100, 1)
	img := g.build() or { panic(err) }
	p := boot_image(img, false)
	datas := p.list_objects(front(img, p)).map(it.data)
	assert datas == [img.symbols['rt.art.0'], img.symbols['rt.art.1']]
}

// objects_at is the list the runtime builds for a red 16x16 sprite at a
// position, on NTSC.
fn objects_at(x int, y int, scale f64) []emulated.Object {
	img, p := shown(x, y, scale, false)
	return p.list_objects(front(img, p))
}

fn test_a_sprite_wholly_off_the_screen_is_not_drawn() {
	for place in [[-16, 100], [320, 100], [100, -16], [100, 240],
		[-1000, 0], [30000, 30000], [-30000, -30000]] {
		assert objects_at(place[0], place[1], 1.0).len == 0, 'at ${place}'
	}
}

fn test_a_sprite_that_touches_the_screen_is_drawn() {
	for place in [[-15, 100], [319, 100], [100, -15], [100, 239],
		[-15, -15], [319, 239]] {
		assert objects_at(place[0], place[1], 1.0).len == 1, 'at ${place}'
	}
}

fn test_the_top_and_the_bottom_are_cut_by_showing_fewer_lines() {
	img, p := shown(100, -5, 1.0, false)
	top := p.list_objects(front(img, p))[0]
	assert top.height == 11, 'lines 5..15 of the picture'
	assert top.ypos == 25, 'the first line of the screen'
	assert top.data == img.symbols['rt.art.0'] + 5 * 32, 'five lines of 32 bytes are left out'

	for y, lines in {
		230: 10
		235: 5
		239: 1
		224: 16
	} {
		objects := objects_at(100, y, 1.0)
		assert objects[0].height == lines, 'at y ${y}'
		assert objects[0].ypos == 25 + 2 * y
	}
}

fn test_a_sprite_that_runs_off_a_side_is_left_to_the_object_processor() {
	left := objects_at(-5, 100, 1.0)[0]
	assert left.xpos == 16 - 5, 'a negative position, as the object processor takes it'
	assert left.height == 16 && left.iwidth == 4
	right := objects_at(315, 100, 1.0)[0]
	assert right.xpos == 16 + 315
}

fn test_a_scaled_sprite_is_cut_in_source_lines() {
	img, p := shown(100, -10, 2.0, false)
	top := p.list_objects(front(img, p))[0]
	assert top.kind == 1
	assert top.hscale == 64 && top.vscale == 64
	assert top.height == 11, 'ten lines on the screen are five of the picture'
	assert top.data == img.symbols['rt.art.0'] + 5 * 32
	assert top.ypos == 25

	bottom := objects_at(100, 220, 2.0)[0]
	assert bottom.height == 10, 'twenty lines are left, ten of the picture'
	assert bottom.hscale == 64
	// A scaled sprite that fits is not cut.
	assert objects_at(100, 100, 2.0)[0].height == 16
	assert objects_at(100, 100, 1.0)[0].kind == 0, 'full size is the plain kind of object'
}

// the picture on PAL, where the logical screen has a border above and below
// that the emulator shows.
fn test_nothing_is_drawn_above_or_below_the_screen_on_pal() {
	mut boxes := map[int]emulated.Box{}
	for y in [100, -5, 230] {
		img, p := shown(100, y, 1.0, true)
		pic := p.picture()
		boxes[y] = pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
		_ = img
	}
	reference := boxes[100]
	top_of_screen := reference.top - 100
	assert boxes[-5].count == 16 * 11
	assert boxes[-5].top == top_of_screen, 'cut at the top edge of the screen, not above'
	assert boxes[230].count == 16 * 10
	assert boxes[230].bottom == top_of_screen + 239, 'cut at the bottom edge of the screen'
	assert boxes[230].left == reference.left
}

fn test_a_sprite_does_not_wrap_around() {
	mut g := new_game(Config{ sprites: 2, layers: 2 })
	g.art_cry('box', 16, 16, 1, solid(16, 16, red()))
	mut c := g.define_init()
	mut a := g.sprite(0)
	mut b := g.sprite(1)
	a.put(mut c, 'box', -10, 100, 0)
	b.put(mut c, 'box', 314, 160, 0)
	img := g.build() or { panic(err) }
	p := boot_image(img, false)
	pic := p.picture()
	left := pic.bounds(0, 90, 40, 120, lit_pixel)
	assert left.count > 0
	assert pic.bounds(100, 90, pic.width, 120, lit_pixel).count == 0, 'nothing at the other side'
	right_box := pic.bounds(0, 150, pic.width, 180, lit_pixel)
	assert right_box.left >= 300
	assert pic.bounds(0, 150, 200, 180, lit_pixel).count == 0
}

fn test_scale_changes_the_size_on_the_screen() {
	mut sizes := map[string]int{}
	mut heights := map[string]int{}
	for scale in [0.5, 1.0, 1.5, 2.0, 3.0] {
		_, p := shown(100, 100, scale, false)
		pic := p.picture()
		box := pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
		sizes['${scale}'] = box.right - box.left + 1
		heights['${scale}'] = box.bottom - box.top + 1
	}
	assert sizes == {
		'0.5': 8
		'1.0': 16
		'1.5': 24
		'2.0': 32
		'3.0': 48
	}
	// The object processor's rule for the vertical remainder can add or drop a line.
	for scale, width in sizes {
		assert heights[scale] - width in [-1, 0, 1], 'scale ${scale}'
	}
}

fn test_a_flipped_sprite_is_mirrored_in_the_same_place() {
	// Left half red, right half blue.
	mut pixels := []u16{}
	for _ in 0 .. 16 {
		for x in 0 .. 16 {
			pixels << if x < 8 { red() } else { blue() }
		}
	}
	mut sides := []bool{}
	mut lefts := []int{}
	for flipped in [false, true] {
		mut g := new_game(Config{ sprites: 1, layers: 1 })
		g.art_cry('half', 16, 16, 1, pixels)
		mut c := g.define_init()
		mut s := g.sprite(0)
		s.put(mut c, 'half', 100, 100, 0)
		c.set(s.flip, flipped)
		img := g.build() or { panic(err) }
		p := boot_image(img, false)
		pic := p.picture()
		box := pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
		assert box.count == 256
		lefts << box.left
		sides << is_red(pic.at(box.left + 2, box.top + 5))
		assert is_red(pic.at(box.left + 2, box.top + 5)) != is_red(pic.at(box.right - 2,
			box.top + 5))
	}
	assert sides == [true, false], 'the red half is on the left, then on the right'
	assert lefts[0] == lefts[1], 'the sprite does not move when it is flipped'
}

fn test_palette_art_draws_in_the_palettes_colours() {
	mut g := new_game(Config{ sprites: 2, layers: 1 })
	g.palette([u16(0), green(), blue()])
	g.art_pal('pal', 8, 8, 1, []u8{len: 64, init: 2})
	g.art_cry('cry', 8, 8, 1, solid(8, 8, blue()))
	mut c := g.define_init()
	mut a := g.sprite(0)
	mut b := g.sprite(1)
	a.put(mut c, 'pal', 50, 100, 0)
	b.put(mut c, 'cry', 150, 100, 0)
	img := g.build() or { panic(err) }
	p := boot_image(img, false)
	pic := p.picture()
	left := pic.bounds(0, 0, 100, pic.height, lit_pixel)
	right := pic.bounds(100, 0, pic.width, pic.height, lit_pixel)
	assert left.count == 64 && right.count == 64
	assert pic.at(left.left + 2, left.top + 2) == pic.at(right.left + 2, right.top + 2)
	assert is_blue(pic.at(left.left + 2, left.top + 2))
	// Pixel 0 is transparent.
	assert p.list_objects(front(img, p))[0].depth == 3
}

fn test_a_frame_of_the_art_is_chosen_by_the_frame_field() {
	mut pixels := solid(8, 8, red())
	pixels << solid(8, 8, green())
	mut colours := []string{}
	for frame in [0, 1, 7] {
		mut g := new_game(Config{ sprites: 1, layers: 1 })
		g.art_cry('two', 8, 8, 2, pixels)
		mut c := g.define_init()
		mut s := g.sprite(0)
		s.put(mut c, 'two', 100, 100, 0)
		c.set(s.frame, frame)
		img := g.build() or { panic(err) }
		p := boot_image(img, false)
		pic := p.picture()
		box := pic.bounds(0, 0, pic.width, pic.height, lit_pixel)
		colours << if is_red(pic.at(box.left + 1, box.top + 1)) { 'red' } else { 'green' }
	}
	assert colours == ['red', 'green', 'red'], 'a frame the art does not have shows frame 0'
}

fn test_a_full_pool_and_two_text_layers_fit_the_list() {
	mut g := new_game(Config{ sprites: 6, layers: 2 })
	g.art_cry('box', 8, 8, 1, solid(8, 8, red()))
	g.text_layer('one', TextConfig{ columns: 8, rows: 1 })
	g.text_layer('two', TextConfig{ columns: 8, rows: 1, y: 16 })
	mut c := g.define_init()
	for i in 0 .. 6 {
		mut s := g.sprite(i)
		s.put(mut c, 'box', 20 * i, 100, i % 2)
	}
	img := g.build() or { panic(err) }
	p := boot_image(img, false)
	objects := p.list_objects(front(img, p))
	assert objects.len == 8, 'six sprites and two text layers'
	assert objects[6].depth == 0 && objects[7].depth == 0, 'the text is last, one bit a pixel'
}
