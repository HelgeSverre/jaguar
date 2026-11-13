module sdl

import jerry

fn test_the_red_buttons_are_the_frontend_commands() {
	labels := ['POWER', 'RESET', 'PAUSE', 'MUTE', 'FULLSCREEN']
	for i, centre in shell_button_centres {
		control := control_at(centre, shell_button_y)
		assert control.kind == .command
		assert shell_commands[control.index] == [Command.quit, .reset, .pause, .mute, .fullscreen][i]
		assert control.label() == labels[i]
	}
	// Buttons are round: the corner of the bounding square misses.
	assert control_at(shell_button_centres[0] - 40, shell_button_y - 40).kind == .none
}

fn test_the_keypad_is_laid_out_like_the_controller() {
	rows := [[jerry.Button.one, .two, .three], [jerry.Button.four, .five, .six],
		[jerry.Button.seven, .eight, .nine], [jerry.Button.star, .zero, .hash]]
	for row, keys in rows {
		for column, key in keys {
			control := control_at(shell_keypad.x + column * shell_keypad_pitch_x + 30,

				shell_keypad.y + row * shell_keypad_pitch_y + 20)
			assert control.kind == .key
			assert shell_keys[control.index] == key
		}
	}
	assert control_at(shell_keypad.x + 30, shell_keypad.y + 20).label() == 'KEYPAD 1'
	assert control_at(shell_keypad.x + 30 + shell_keypad_pitch_x, shell_keypad.y + 20 +
		3 * shell_keypad_pitch_y).label() == 'KEYPAD 0'
	assert control_at(shell_keypad.x + 30, shell_keypad.y + 20 + 3 * shell_keypad_pitch_y).label() == 'KEYPAD *'
	// The gap between two keys is not a key.
	assert control_at(shell_keypad.x + shell_keypad.w + 5, shell_keypad.y + 20).kind == .none
}

fn test_the_screen_and_the_readout_hold_no_controls() {
	assert control_at(shell_screen.x + shell_screen.w / 2, shell_screen.y + shell_screen.h / 2).kind == .none
	assert control_at(shell_readout.x + 10, shell_readout.y + 10).kind == .none
}

fn test_a_keypad_key_stays_down_until_the_mouse_button_comes_up() {
	mut shell := Shell{
		scale:  0.5
		active: true
	}
	// Window points are artwork pixels times the scale.
	x := f32(shell_keypad.x + 30) * 0.5
	y := f32(shell_keypad.y + 20) * 0.5
	press := shell.click(x, y, true)?
	assert press.kind == .button && press.button == jerry.Button.one && press.pressed
	assert shell.held.kind == .key
	// The release counts even after the pointer has left the key.
	release := shell.click(0, 0, false)?
	assert release.kind == .button && release.button == jerry.Button.one && !release.pressed
	assert shell.held.kind == .none
}

fn test_a_red_button_acts_once_when_pressed() {
	mut shell := Shell{
		active: true
	}
	press := shell.click(f32(shell_button_centres[2]), f32(shell_button_y), true)?
	assert press.kind == .command && press.command == .pause && press.pressed
	assert shell.click(f32(shell_button_centres[2]), f32(shell_button_y), false) == none
}

fn test_a_fullscreen_window_has_no_controls() {
	mut shell := Shell{}
	shell.active = false
	assert shell.click(f32(shell_button_centres[0]), f32(shell_button_y), true) == none
}

fn test_only_the_console_body_moves_the_window() {
	mut shell := Shell{
		alpha:  []u8{len: shell_width * shell_height}
		active: true
	}
	// A solid patch of body left of the screen, and nothing in the corner.
	shell.alpha[500 * shell_width + 100] = 255
	body := C.SDL_Point{100, 500}
	corner := C.SDL_Point{2, 2}
	button := C.SDL_Point{shell_button_centres[0], shell_button_y}
	screen := C.SDL_Point{shell_screen.x + 50, shell_screen.y + 50}
	assert shell_hit_test(unsafe { nil }, &body, &shell) == int(C.SDL_HITTEST_DRAGGABLE)
	assert shell_hit_test(unsafe { nil }, &screen, &shell) == int(C.SDL_HITTEST_DRAGGABLE)
	assert shell_hit_test(unsafe { nil }, &corner, &shell) == int(C.SDL_HITTEST_NORMAL)
	assert shell_hit_test(unsafe { nil }, &button, &shell) == int(C.SDL_HITTEST_NORMAL)
}

fn test_the_bezel_covers_none_of_the_picture() {
	art := $embed_file('shell.png')
	decoded := C.SDL_LoadPNG_IO(C.SDL_IOFromConstMem(art.data(), usize(art.len)), true)
	assert decoded != unsafe { nil }
	surface := C.SDL_ConvertSurface(decoded, u32(C.SDL_PIXELFORMAT_RGBA32))
	C.SDL_DestroySurface(decoded)
	assert surface != unsafe { nil }
	defer {
		C.SDL_DestroySurface(surface)
	}
	p := shell_picture
	assert p.w * 3 == p.h * 4 || (p.w * 3 - p.h * 4) * (p.w * 3 - p.h * 4) < 16, 'the picture box is 4:3'
	mut covered := 0
	for y in p.y .. p.y + p.h {
		row := unsafe { &u8(surface.pixels) + y * surface.pitch }
		for x in p.x .. p.x + p.w {
			if unsafe { row[x * 4 + 3] } != 0 {
				covered++
			}
		}
	}
	assert covered == 0
}
