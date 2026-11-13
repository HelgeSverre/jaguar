module sdl

import jerry

// push_key queues a keyboard event the way the operating system would.
fn push_key(scancode int, down bool) {
	key := C.SDL_KeyboardEvent{
		type:     if down { u32(C.SDL_EVENT_KEY_DOWN) } else { u32(C.SDL_EVENT_KEY_UP) }
		scancode: scancode
		down:     down
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&key) })
}

fn test_keys_reach_the_pad_through_the_event_queue() {
	assert C.SDL_Init(u32(C.SDL_INIT_EVENTS))
	defer {
		C.SDL_Quit()
	}
	mut input := Input{}
	for input.poll().kind != .none {}

	push_key(int(C.SDL_SCANCODE_X), true)
	push_key(int(C.SDL_SCANCODE_LEFT), true)
	push_key(int(C.SDL_SCANCODE_X), false)
	push_key(int(C.SDL_SCANCODE_RETURN), true)
	push_key(int(C.SDL_SCANCODE_F1), true)

	fire := input.poll()
	assert fire.kind == .button && fire.button == jerry.Button.b && fire.pressed && fire.port == 0
	left := input.poll()
	assert left.kind == .button && left.button == jerry.Button.left && left.pressed
	release := input.poll()
	assert release.kind == .button && release.button == jerry.Button.b && !release.pressed
	pause := input.poll()
	assert pause.kind == .button && pause.button == jerry.Button.pause && pause.pressed
	overlay := input.poll()
	assert overlay.kind == .command && overlay.command == .overlay
	assert input.poll().kind == .none
}

fn test_every_awkward_key_has_one_that_is_on_every_keyboard() {
	star := decode_key(int(C.SDL_SCANCODE_Q), true) or { panic('Q is not bound') }
	assert star.kind == .button && star.button == jerry.Button.star && star.pressed
	hash := decode_key(int(C.SDL_SCANCODE_W), true) or { panic('W is not bound') }
	assert hash.kind == .button && hash.button == jerry.Button.hash && hash.pressed

	scancodes := [int(C.SDL_SCANCODE_R), int(C.SDL_SCANCODE_I), int(C.SDL_SCANCODE_S),
		int(C.SDL_SCANCODE_H), int(C.SDL_SCANCODE_F), int(C.SDL_SCANCODE_COMMA),
		int(C.SDL_SCANCODE_PERIOD), int(C.SDL_SCANCODE_SPACE)]
	commands := [Command.reset, .overlay, .screenshot, .shell, .fullscreen, .shrink, .grow,
		.fast_forward]
	for i, scancode in scancodes {
		event := decode_key(scancode, true) or { panic('key ${i} is not bound') }
		assert event.kind == .command
		assert event.command == commands[i]
	}
	// Fast-forward lasts as long as the space bar is down.
	release := decode_key(int(C.SDL_SCANCODE_SPACE), false) or { panic('no release') }
	assert release.command == .fast_forward
	assert !release.pressed
}

fn test_a_dropped_file_reports_its_path() {
	assert C.SDL_Init(u32(C.SDL_INIT_EVENTS))
	defer {
		C.SDL_Quit()
	}
	mut input := Input{}
	for input.poll().kind != .none {}

	drop := C.SDL_DropEvent{
		type: u32(C.SDL_EVENT_DROP_FILE)
		data: c'/games/some image (1994).j64'
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&drop) })
	event := input.poll()
	assert event.kind == .drop_file
	assert event.path == '/games/some image (1994).j64'
}

fn test_face_buttons_read_c_b_a_from_left_to_right() {
	assert decode_key(int(C.SDL_SCANCODE_Z), true)?.button == jerry.Button.c
	assert decode_key(int(C.SDL_SCANCODE_X), true)?.button == jerry.Button.b
	assert decode_key(int(C.SDL_SCANCODE_C), true)?.button == jerry.Button.a
	assert decode_gamepad_button(u8(C.SDL_GAMEPAD_BUTTON_SOUTH))? == jerry.Button.b
}

fn test_unbound_keys_and_command_releases_are_ignored() {
	assert decode_key(int(C.SDL_SCANCODE_J), true) == none
	assert decode_key(int(C.SDL_SCANCODE_F5), false) == none
	assert decode_key(int(C.SDL_SCANCODE_GRAVE), false)?.command == .fast_forward
}
