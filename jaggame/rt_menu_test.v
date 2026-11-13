module jaggame

import jaggame.emulated
import jerry

// Menus: the cursor, the repeat, choosing and going back, the same on the
// interpreter and the machine, on both television standards.

fn menu_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	layer := g.text_layer('ui', TextConfig{ columns: 16, rows: 4, x: 8, y: 16 })
	menu := g.menu('pick', layer, 0, 0, ['ONE', 'TWO', 'THREE'])
	mut c := g.define_init()
	menu.open(mut c)
	c = g.define_update()
	menu.update(mut c)
	return g
}

fn build_error(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}

fn glyph(c u8) int {
	return int(c) - 32
}

fn menu_pad(buttons ...Button) u32 {
	mut mask := u32(0)
	for b in buttons {
		mask |= button_mask(b)
	}
	return mask
}

fn test_the_cursor_moves_once_per_press_wraps_and_repeats_after_a_delay() {
	for region in [Region.ntsc, Region.pal] {
		mut g := menu_game()
		mut it := g.interpreter(region)!
		fps := if region == .pal { 50 } else { 60 }
		g.step(mut it, 0)!
		assert it.value('pick_cursor')! == 0
		// Down: moves at the press, not again until 0.3 seconds have passed.
		mut moves := []int{}
		for frame in 0 .. 3 * fps {
			g.step(mut it, menu_pad(.down))!
			if it.value('pick_moved')! != 0 {
				moves << frame
			}
		}
		first := int(f64(fps) * 0.3 + 0.5)
		again := int(f64(fps) * 0.1 + 0.5)
		assert moves[0] == 0
		assert moves[1] == first, 'the first repeat: ${moves[..3]} at ${fps} fps'
		assert moves[2] - moves[1] == again, 'the pace: ${moves[..3]}'
		// A different number of frames on the two standards, the same time.
		assert f64(moves[1]) / f64(fps) > 0.28 && f64(moves[1]) / f64(fps) < 0.35
		// Three items: wrapping both ways.
		g.step(mut it, 0)!
		before := int(it.value('pick_cursor')!)
		g.step(mut it, menu_pad(.up))!
		assert int(it.value('pick_cursor')!) == (before + 2) % 3
	}
}

fn test_a_chosen_item_and_back_show_for_one_frame() {
	mut g := menu_game()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, 0)!
	assert it.value('pick_chosen')! == 255
	g.step(mut it, menu_pad(.down))!
	g.step(mut it, 0)!
	g.step(mut it, menu_pad(.a))!
	assert it.value('pick_chosen')! == 1
	g.step(mut it, menu_pad(.a))! // held, not pressed
	assert it.value('pick_chosen')! == 255
	g.step(mut it, 0)!
	g.step(mut it, menu_pad(.b))!
	assert it.value('pick_backed')! == 1
	g.step(mut it, 0)!
	assert it.value('pick_backed')! == 0
}

fn test_the_machine_draws_the_cursor_where_the_interpreter_says() {
	mut g := menu_game()
	img := g.build()!
	mut h := menu_game()
	mut it := h.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!
	for k in 0 .. 40 {
		held := if k == 3 || (k > 20 && k < 30) { menu_pad(.down) } else { u32(0) }
		h.step(mut it, held)!
		if held != 0 {
			p.press(jerry.Button.down)
		} else {
			p.release(jerry.Button.down)
		}
		p.frames(1)
	}
	mut differences := img.differences(it, p.m.ram)
	differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale'))
	assert differences.len == 0, differences.join('\n')
	cursor := int(it.value('pick_cursor')!)
	assert cursor > 0, 'it moved'
	for row in 0 .. 3 {
		cell := int(it.element('ui_cells', row * 16)!)
		assert cell == (if row == cursor {
			glyph(`>`)
		} else {
			0
		}), 'row ${row}'
	}
}

fn test_a_menu_that_does_not_fit_its_layer_is_reported() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	layer := g.text_layer('ui', TextConfig{ columns: 8, rows: 2, x: 0, y: 0 })
	g.menu('wide', layer, 0, 0, ['A VERY LONG ITEM', 'B', 'C'])
	message := build_error(mut g)
	assert message.contains('does not fit the layer `ui`'), message
}
