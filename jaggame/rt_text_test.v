module jaggame

import jagkit
import jaggame.emulated

// Text layers, missed frames and the mistakes a game can make.

fn white(px u32) bool {
	return (px >> 16) & 0xff > 150 && (px >> 8) & 0xff > 150 && px & 0xff > 150
}

fn lit_pixel(px u32) bool {
	return px != 0
}

// glyph_pixels is the number of set pixels in the font for a string.
fn glyph_pixels(text string) int {
	font := jagkit.font_8x8()
	mut count := 0
	for ch in text {
		for row in 0 .. 8 {
			mut bits := font[(int(ch) - jagkit.font_first) * 8 + row]
			for bits != 0 {
				count += int(bits & 1)
				bits >>= 1
			}
		}
	}
	return count
}

// text_game has a layer of 16 cells by 2 rows. The pad changes what it
// says: A prints a number from `n`, B clears it.
fn text_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	n := g.p.u32('n')
	hud := g.text_layer('hud', TextConfig{ columns: 16, rows: 2, x: 8, y: 16 })
	mut c := g.define_init()
	hud.print(mut c, 0, 0, 'HI 5')
	c = g.define_update()
	c.if_(g.pressed(.a))
	hud.number(mut c, 4, 1, n, 5)
	c.end()
	c.if_(g.pressed(.b))
	hud.clear(mut c)
	c.end()
	return g
}

fn interpreter_cells(it &Interpreter, name string, count int) []int {
	mut found := []int{}
	for i in 0 .. count {
		found << int(it.element(name, i) or { panic(err) })
	}
	return found
}

fn machine_cells(img Image, p &emulated.Player, name string, count int) []int {
	mut found := []int{}
	for i in 0 .. count {
		found << int(img.element(p.m.ram, name, i) or { panic(err) })
	}
	return found
}

fn glyph(c u8) int {
	return int(c) - jagkit.font_first
}

fn test_print_writes_glyphs_into_the_cells() {
	mut g := text_game()
	mut it := g.interpreter(.ntsc) or { panic(err) }
	got := interpreter_cells(it, 'hud_cells', 32)
	assert got[..4] == [glyph(`H`), glyph(`I`), 0, glyph(`5`)]
	assert got[4..].all(it == 0)
	assert interpreter_cells(it, 'hud_dirty', 2) == [1, 0], 'row 0 is marked to be drawn again'
}

fn test_a_number_is_right_aligned_in_its_width() {
	mut g := text_game()
	mut it := g.interpreter(.ntsc) or { panic(err) }
	for value, shown in {
		i64(0):     '    0'
		7:          '    7'
		1234:       ' 1234'
		99999:      '99999'
		123456:     '23456'
		4294967295: '67295'
	} {
		it.set_value('n', value)!
		g.step(mut it, button_mask(.a))!
		g.step(mut it, 0)!
		mut want := []int{}
		for ch in shown {
			want << if ch == ` ` { 0 } else { glyph(ch) }
		}
		assert interpreter_cells(it, 'hud_cells', 32)[16 + 4..16 + 9] == want, 'the number ${value}'
	}
}

fn test_clear_blanks_the_layer() {
	mut g := text_game()
	mut it := g.interpreter(.ntsc) or { panic(err) }
	g.step(mut it, button_mask(.b))!
	assert interpreter_cells(it, 'hud_cells', 32).all(it == 0)
	assert interpreter_cells(it, 'hud_dirty', 2) == [1, 1]
}

fn test_the_machine_draws_the_rows_that_changed() {
	mut g := text_game()
	img := g.build() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(3)
	pic := p.picture()
	text := pic.bounds(0, 0, pic.width, pic.height, white)
	assert text.count == glyph_pixels('HI 5'), 'exactly the pixels of the font'
	assert text.right - text.left < 4 * 8
	assert machine_cells(img, &p, 'hud_dirty', 2) == [0, 0], 'drawn rows are marked done'

	// A number appears when A is pressed: n is 0, so the digit 0.
	p.hold(.a, 2)
	p.frames(2)
	pic2 := p.picture()
	both := pic2.bounds(0, 0, pic2.width, pic2.height, white)
	assert both.count == glyph_pixels('HI 5') + glyph_pixels('0')
	assert both.bottom - both.top > 8, 'the number is on the second row'

	// B blanks everything.
	p.hold(.b, 2)
	p.frames(2)
	pic3 := p.picture()
	assert pic3.bounds(0, 0, pic3.width, pic3.height, white).count == 0
}

fn test_the_machine_and_the_interpreter_make_the_same_cells() {
	mut g := text_game()
	img := g.build() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	mut h := text_game()
	mut it := h.interpreter(.ntsc) or { panic(err) }
	p.frames(1)
	h.step(mut it, 0)!
	for n in [i64(31415), 7] {
		it.set_value('n', n)!
		// The machine's n is set by hand too.
		p.m.write32(img.symbols['n'], u32(n))
		p.press(.a)
		p.frames(1)
		p.release(.a)
		h.step(mut it, button_mask(.a))!
		p.frames(2)
		h.step(mut it, 0)!
		h.step(mut it, 0)!
		assert machine_cells(img, &p, 'hud_cells', 32) == interpreter_cells(it, 'hud_cells', 32)
	}
}

fn test_every_layer_has_its_own_colour() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	one := g.text_layer('one', TextConfig{ columns: 8, rows: 1, x: 8, y: 8 })
	two := g.text_layer('two', TextConfig{
		columns: 8
		rows:    1
		x:       8
		y:       40
		colour:  cry(255, 0, 0)
	})
	mut c := g.define_init()
	one.print(mut c, 0, 0, 'ABC')
	two.print(mut c, 0, 0, 'ABC')
	c = g.define_update()
	c.if_(g.pressed(.a))
	c.set(one.colour, cry(0, 255, 0))
	c.end()
	img := g.build() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(3)
	pic := p.picture()
	top := pic.bounds(0, 0, pic.width, 30, lit_pixel)
	bottom := pic.bounds(0, 30, pic.width, 80, lit_pixel)
	assert top.count == glyph_pixels('ABC') && bottom.count == glyph_pixels('ABC')
	assert pic.bounds(0, 0, pic.width, 30, white).count == top.count, 'the first layer is white'
	assert pic.bounds(0, 30, pic.width, 80, fn (px u32) bool {
		return (px >> 16) & 0xff > 150 && px & 0xff < 100
	}).count == bottom.count, 'the second layer is red'

	p.hold(.a, 2)
	p.frames(2)
	pic2 := p.picture()
	assert pic2.bounds(0, 0, pic2.width, 30, fn (px u32) bool {
		return (px >> 8) & 0xff > 150 && (px >> 16) & 0xff < 100
	}).count == top.count, 'a layer changes colour when its variable does'
}

fn test_a_normal_game_misses_no_frames_and_a_slow_one_does() {
	mut g := text_game()
	img := g.build() or { panic(err) }
	for pal in [false, true] {
		mut p := emulated.boot(img.bytes, pal) or { panic(err) }
		p.frames(300)
		assert img.value(p.m.ram, 'frame')! == 300, 'one interrupt for each frame'
		assert img.value(p.m.ram, 'missed_frames')! == 0
	}

	// An update that takes longer than a frame.
	mut slow := new_game(Config{ sprites: 1, layers: 1 })
	slow.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	x := slow.p.u32('x')
	mut c := slow.define_update()
	c.repeat(1200) // about 400,000 cycles; a frame is 221,000
	c.set(x, x.mul(7).add(1))
	c.end()
	slow_img := slow.build() or { panic(err) }
	mut p := emulated.boot(slow_img.bytes, false) or { panic(err) }
	for _ in 0 .. 20 {
		p.m.run_frame()
	}
	missed := slow_img.value(p.m.ram, 'missed_frames')!
	frames := slow_img.value(p.m.ram, 'frame')!
	assert missed >= 8, 'an update of more than a frame is counted: ${missed}'
	assert frames < 15, 'and the frames it took are lost: ${frames} of 20'

	// Half a frame of work is no trouble.
	mut busy := new_game(Config{ sprites: 1, layers: 1 })
	busy.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	y := busy.p.u32('y')
	c = busy.define_update()
	c.repeat(450)
	c.set(y, y.add(1))
	c.end()
	busy_img := busy.build() or { panic(err) }
	mut q := emulated.boot(busy_img.bytes, false) or { panic(err) }
	q.frames(60)
	assert busy_img.value(q.m.ram, 'missed_frames')! == 0
	assert busy_img.value(q.m.ram, 'frame')! == 60
}

fn test_mistakes_in_the_description_are_reported_together() {
	mut g := new_game(Config{ sprites: 4, layers: 2 })
	g.art_cry('wide', 6, 8, 1, []u16{len: 48}) // 6 pixels do not fill a phrase
	g.art_cry('short', 8, 8, 2, []u16{len: 64}) // two frames need 128 pixels
	g.art_pal('indexed', 8, 8, 1, []u8{len: 64, init: 3})
	g.sequence('walk', [Step{0, 0.1}])
	hud := g.text_layer('hud', TextConfig{ columns: 8, rows: 1 })
	g.text_layer('wide_text', TextConfig{ columns: 12, rows: 1 })
	mut c := g.define_init()
	mut s := g.sprite(9)
	s.put(mut c, 'missing', 0, 0, 0)
	s.play(mut c, 'wlak', true)
	hud.print(mut c, 6, 0, 'TOO LONG')
	hud.print(mut c, 0, 0, 'lower case')
	hud.print(mut c, 0, 5, 'X')
	g.build() or {
		text := err.msg()
		for part in [
			'art `wide`: a line of 6 pixels at 16 bits does not fill whole 64-bit phrases',
			'art `short`: 2 frames of 8x8 need 128 pixels, there are 64',
			'a palette picture but no palette',
			'sprite 9 is not in the pool of 4',
			'there is no art `missing`; the pictures are: wide, short, indexed',
			'there is no animation `wlak`; the animations are: walk',
			'text layer `hud`: "TOO LONG" at column 6, row 0 is outside the layer of 8x1 cells',
			'text layer `hud`: the font has no `l`',
			'text layer `hud`: "X" at column 0, row 5 is outside the layer',
			'text layer `wide_text`: the columns (12) must be a multiple of 8',
		] {
			assert text.contains(part), 'missing: ${part}\nin:\n${text}'
		}
		return
	}
	assert false, 'a game with mistakes must not build'
}

fn test_a_picture_too_large_for_memory_is_refused() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('big', 64, 64, 255, []u16{len: 64 * 64 * 255})
	g.build() or {
		assert err.msg().contains('overlap'), err.msg()
		return
	}
	assert false
}

fn test_a_game_builds_once_and_the_image_is_the_same_each_time() {
	mut first := text_game()
	mut second := text_game()
	a := first.build()!
	b := second.build()!
	assert a.bytes == b.bytes
	mut g := text_game()
	g.build()!
	g.build() or {
		assert err.msg().contains('built once')
		return
	}
	assert false
}

fn test_the_image_loads_and_starts_on_the_entry() {
	mut g := text_game()
	img := g.build()!
	assert img.symbols['rt.start'] == load_address
	assert img.symbols['sprites'] % 4 == 0
}

fn test_words_wrap_at_the_spaces() {
	assert wrap_words('GET THE CHIPS AND LEAVE BY THE GREEN PAD', 12) == ['GET THE', 'CHIPS AND',
		'LEAVE BY THE', 'GREEN PAD']
	assert wrap_words('  ONE   TWO ', 20) == ['ONE TWO']
	assert wrap_words('', 10).len == 0
	assert wrap_words('ABCDEFGHIJKL MN', 5) == ['ABCDEFGHIJKL', 'MN']
}

fn test_a_wrapped_text_is_printed_line_by_line_and_a_long_word_is_an_error() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	layer := g.text_layer('note', TextConfig{
		columns: 16
		rows:    6
	})
	mut c := g.define_init()
	used := layer.print_wrapped(mut c, 1, 1, 10, 'SNEAK PAST THE GUARDS AND REACH THE EXIT')
	assert used == 4
	g.build()!
	mut h := new_game(Config{ sprites: 1, layers: 1 })
	h.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	l2 := h.text_layer('note', TextConfig{
		columns: 16
		rows:    6
	})
	mut c2 := h.define_init()
	l2.print_wrapped(mut c2, 0, 0, 5, 'EXTRAORDINARY DAY')
	h.build() or {
		assert err.msg().contains('EXTRAORDINARY')
		return
	}
	assert false, 'a word wider than the lines is reported'
}
