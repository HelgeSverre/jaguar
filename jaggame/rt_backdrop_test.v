module jaggame

import jaggame.emulated

// The backdrop: the GPU's picture against a model written in V (as the
// plasma demo's test does), the object in the display list while it is shown
// and not when it is hidden, the places the GPU must not touch, and what it
// costs the 68000.

// backdrop_game shows the backdrop at the start. The pad: B hides it, A
// shows it again.
fn backdrop_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	g.backdrop(Backdrop{
		colours: [Rgb{40, 120, 255}, Rgb{150, 60, 255}, Rgb{20, 220, 200}]
	})
	g.text_layer('title', TextConfig{
		columns: 16
		rows:    1
		x:       32
		y:       100
	})
	mut c := g.define_init()
	g.backdrop_show(mut c)
	c = g.define_update()
	c.if_(g.pressed(.b))
	g.backdrop_hide(mut c)
	c.end()
	c.if_(g.pressed(.a))
	g.backdrop_show(mut c)
	c.end()
	return g
}

fn built_backdrop() Image {
	mut g := backdrop_game()
	return g.build() or { panic(err) }
}

fn word_at(p &emulated.Player, address u32) int {
	return p.peek16(address)
}

fn test_the_gpu_draws_what_the_model_says() {
	mut g := backdrop_game()
	img := g.build()!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(40)
	frame := u32(img.value(p.m.ram, 'frame')!)
	now := backdrop_params(frame)
	before := backdrop_params(frame - 1)
	assert now.across == int(img.value(p.m.ram, 'rt_backdrop_across')!)
	mut fresh := 0
	for y in 0 .. backdrop_height {
		for x in 0 .. backdrop_width {
			pixel := u16(word_at(p, backdrop_buffer + u32((y * backdrop_width + x) * 2)))
			a := g.backdrop_pixel(now, x, y)
			b := g.backdrop_pixel(before, x, y)
			assert pixel == a || pixel == b, 'pixel ${x},${y}: ${pixel:04x}, now ${a:04x}, before ${b:04x}'
			if pixel == a && pixel != b {
				fresh++
			}
		}
	}
	assert fresh > 0, 'the GPU has started on the new picture'
}

fn test_the_picture_moves_and_reaches_the_screen_under_the_text() {
	mut g := backdrop_game()
	img := g.build()!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(30)
	before := p.peek16(backdrop_buffer + 400)
	mut changed := false
	for _ in 0 .. 30 {
		p.frames(1)
		if p.peek16(backdrop_buffer + 400) != before {
			changed = true
		}
	}
	assert changed, 'the picture changes'
	pic := p.picture()
	mut seen := map[u32]bool{}
	mut dark := 0
	for y in 0 .. pic.height {
		for x in 0 .. pic.width {
			px := pic.at(x, y) & 0xffffff
			seen[px] = true
			if px == 0 {
				dark++
			}
		}
	}
	assert seen.len > 60, 'many colours: ${seen.len}'
	assert dark < pic.width * pic.height / 10, 'it covers the screen: ${dark} black pixels of ${pic.width * pic.height}'
}

fn test_it_is_the_first_object_while_shown_and_gone_when_hidden() {
	mut g := backdrop_game()
	img := g.build()!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(10)
	lists := [list_address, list_address + u32((32 + 32 * g.objects() + 255) / 256 * 256)]
	for base in lists {
		objects := p.list_objects(base)
		assert objects[0].data == backdrop_buffer, 'the backdrop first'
		assert objects[0].kind == 1 && objects[0].depth == 4, 'scaled, 16 bits'
	}
	drawn := img.value(p.m.ram, 'rt_backdrop_on')!
	assert drawn == 1
	p.hold(.b, 2)
	p.frames(3)
	for base in lists {
		for obj in p.list_objects(base) {
			assert obj.data != backdrop_buffer, 'hidden'
		}
	}
	// And it comes back.
	p.hold(.a, 2)
	p.frames(3)
	for base in lists {
		assert p.list_objects(base)[0].data == backdrop_buffer
	}
}

fn test_the_gpu_works_only_while_it_is_shown_and_leaves_the_tile_buffer_alone() {
	mut g := backdrop_game()
	img := g.build()!
	mut p := emulated.boot(img.bytes, true)!
	// a mark in the tile buffer's place, which a game with rooms keeps its picture in
	for k in 0 .. 4096 {
		p.m.ram[tile_buffer + u32(k)] = 0xa5
	}
	p.frames(20)
	_, mailbox := backdrop_code()!
	drawn := p.m.peek32(mailbox + u32(shared_drawn))
	assert drawn > 10, 'a picture every frame: ${drawn}'
	p.hold(.b, 2)
	p.frames(3)
	stopped := p.m.peek32(mailbox + u32(shared_drawn))
	p.frames(30)
	assert p.m.peek32(mailbox + u32(shared_drawn)) == stopped, 'the GPU is left alone while the backdrop is hidden'
	for k in 0 .. 4096 {
		assert p.m.ram[tile_buffer + u32(k)] == 0xa5, 'the tile buffer is untouched at ${k}'
	}
	assert img.value(p.m.ram, 'missed_frames')! == 0
}

fn test_the_backdrop_costs_the_68000_little() {
	mut g := backdrop_game()
	img := g.build()!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(20)
	shown := p.busy_cycles(60)
	p.hold(.b, 2)
	p.frames(5)
	hidden := p.busy_cycles(60)
	println('backdrop: ${shown} cycles a frame while shown, ${hidden} hidden (the GPU does the drawing)')
	assert shown - hidden < 2500
}

fn test_the_backdrop_mistakes_are_reported() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	mut c := g.define_update()
	g.backdrop_show(mut c)
	g.backdrop(Backdrop{})
	g.backdrop(Backdrop{
		colours: [Rgb{1, 2, 3}]
	})
	message := build_error(mut g)
	assert message.contains('backdrop_show: the game has no backdrop'), message
	assert message.contains('it needs 1..8 colours, not 0'), message
	assert message.contains('a game has one backdrop'), message
}

fn build_error(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}
