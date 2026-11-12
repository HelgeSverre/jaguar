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

fn test_face_buttons_read_c_b_a_from_left_to_right() {
	assert decode_key(int(C.SDL_SCANCODE_Z), true)?.button == jerry.Button.c
	assert decode_key(int(C.SDL_SCANCODE_X), true)?.button == jerry.Button.b
	assert decode_key(int(C.SDL_SCANCODE_C), true)?.button == jerry.Button.a
	assert decode_gamepad_button(u8(C.SDL_GAMEPAD_BUTTON_SOUTH))? == jerry.Button.b
}

fn test_unbound_keys_and_command_releases_are_ignored() {
	assert decode_key(int(C.SDL_SCANCODE_Q), true) == none
	assert decode_key(int(C.SDL_SCANCODE_F5), false) == none
	assert decode_key(int(C.SDL_SCANCODE_GRAVE), false)?.command == .fast_forward
}
