module sdl

import jerry

// EventKind classifies what the frontend needs to know about a host event.
pub enum EventKind {
	none
	quit
	button  // a guest controller button changed
	command // a frontend command key was pressed
	drop_file
	focus_lost
}

// Command is a frontend action bound to a key.
pub enum Command {
	none
	pause
	reset
	fullscreen
	mute
	overlay
	screenshot
	fast_forward
	quit
}

// Event is one decoded host event.
pub struct Event {
pub:
	kind    EventKind
	port    int
	button  jerry.Button
	pressed bool
	command Command
	path    string
}

// Input tracks attached gamepads; the first two map to ports 0 and 1.
pub struct Input {
mut:
	gamepads [2]voidptr
	ids      [2]u32
}

// poll returns the next pending event, or an event of kind `.none`.
pub fn (mut input Input) poll() Event {
	event := C.SDL_Event{}
	for C.SDL_PollEvent(&event) {
		kind := unsafe { event.type }
		match kind {
			u32(C.SDL_EVENT_QUIT) {
				return Event{
					kind: .quit
				}
			}
			u32(C.SDL_EVENT_WINDOW_FOCUS_LOST) {
				return Event{
					kind: .focus_lost
				}
			}
			u32(C.SDL_EVENT_KEY_DOWN), u32(C.SDL_EVENT_KEY_UP) {
				key := unsafe { event.key }
				if key.repeat {
					continue
				}
				if decoded := decode_key(key.scancode, key.down) {
					return decoded
				}
			}
			u32(C.SDL_EVENT_GAMEPAD_ADDED) {
				input.attach(unsafe { event.gdevice.which })
			}
			u32(C.SDL_EVENT_GAMEPAD_REMOVED) {
				if input.detach(unsafe { event.gdevice.which }) {
					// An unplugged pad releases everything it held.
					return Event{
						kind: .focus_lost
					}
				}
			}
			u32(C.SDL_EVENT_GAMEPAD_BUTTON_DOWN), u32(C.SDL_EVENT_GAMEPAD_BUTTON_UP) {
				pad := unsafe { event.gbutton }
				port := input.port_of(pad.which)
				if port < 0 {
					continue
				}
				if button := decode_gamepad_button(pad.button) {
					return Event{
						kind:    .button
						port:    port
						button:  button
						pressed: pad.down
					}
				}
			}
			u32(C.SDL_EVENT_DROP_FILE) {
				return Event{
					kind: .drop_file
					path: unsafe { cstring_to_vstring(event.drop.data) }
				}
			}
			else {}
		}
	}
	return Event{}
}

// close releases every attached gamepad.
pub fn (mut input Input) close() {
	for port in 0 .. 2 {
		if input.gamepads[port] != unsafe { nil } {
			C.SDL_CloseGamepad(input.gamepads[port])
			input.gamepads[port] = unsafe { nil }
		}
	}
}

fn (mut input Input) attach(id u32) {
	for port in 0 .. 2 {
		if input.gamepads[port] == unsafe { nil } {
			input.gamepads[port] = C.SDL_OpenGamepad(id)
			input.ids[port] = id
			return
		}
	}
}

fn (mut input Input) detach(id u32) bool {
	for port in 0 .. 2 {
		if input.gamepads[port] != unsafe { nil } && input.ids[port] == id {
			C.SDL_CloseGamepad(input.gamepads[port])
			input.gamepads[port] = unsafe { nil }
			return true
		}
	}
	return false
}

fn (input &Input) port_of(id u32) int {
	for port in 0 .. 2 {
		if input.gamepads[port] != unsafe { nil } && input.ids[port] == id {
			return port
		}
	}
	return -1
}

// decode_key maps a keyboard scancode to a controller button on port 0 or
// to a frontend command.
fn decode_key(scancode int, down bool) ?Event {
	button := match scancode {
		int(C.SDL_SCANCODE_UP) { jerry.Button.up }
		int(C.SDL_SCANCODE_DOWN) { jerry.Button.down }
		int(C.SDL_SCANCODE_LEFT) { jerry.Button.left }
		int(C.SDL_SCANCODE_RIGHT) { jerry.Button.right }
		int(C.SDL_SCANCODE_Z) { jerry.Button.c }
		int(C.SDL_SCANCODE_X) { jerry.Button.b }
		int(C.SDL_SCANCODE_C) { jerry.Button.a }
		int(C.SDL_SCANCODE_RETURN) { jerry.Button.pause }
		int(C.SDL_SCANCODE_TAB) { jerry.Button.option }
		int(C.SDL_SCANCODE_0), int(C.SDL_SCANCODE_KP_0) { jerry.Button.zero }
		int(C.SDL_SCANCODE_1), int(C.SDL_SCANCODE_KP_1) { jerry.Button.one }
		int(C.SDL_SCANCODE_2), int(C.SDL_SCANCODE_KP_2) { jerry.Button.two }
		int(C.SDL_SCANCODE_3), int(C.SDL_SCANCODE_KP_3) { jerry.Button.three }
		int(C.SDL_SCANCODE_4), int(C.SDL_SCANCODE_KP_4) { jerry.Button.four }
		int(C.SDL_SCANCODE_5), int(C.SDL_SCANCODE_KP_5) { jerry.Button.five }
		int(C.SDL_SCANCODE_6), int(C.SDL_SCANCODE_KP_6) { jerry.Button.six }
		int(C.SDL_SCANCODE_7), int(C.SDL_SCANCODE_KP_7) { jerry.Button.seven }
		int(C.SDL_SCANCODE_8), int(C.SDL_SCANCODE_KP_8) { jerry.Button.eight }
		int(C.SDL_SCANCODE_9), int(C.SDL_SCANCODE_KP_9) { jerry.Button.nine }
		int(C.SDL_SCANCODE_MINUS), int(C.SDL_SCANCODE_KP_MULTIPLY) { jerry.Button.star }
		int(C.SDL_SCANCODE_EQUALS), int(C.SDL_SCANCODE_KP_DIVIDE) { jerry.Button.hash }
		else { return decode_command(scancode, down) }
	}

	return Event{
		kind:    .button
		port:    0
		button:  button
		pressed: down
	}
}

// decode_command maps a key press to a frontend command. Fast-forward is
// the one command that also reports its release.
fn decode_command(scancode int, down bool) ?Event {
	command := match scancode {
		int(C.SDL_SCANCODE_ESCAPE) { Command.quit }
		int(C.SDL_SCANCODE_P) { Command.pause }
		int(C.SDL_SCANCODE_F5) { Command.reset }
		int(C.SDL_SCANCODE_F11), int(C.SDL_SCANCODE_F) { Command.fullscreen }
		int(C.SDL_SCANCODE_M) { Command.mute }
		int(C.SDL_SCANCODE_F1) { Command.overlay }
		int(C.SDL_SCANCODE_F12) { Command.screenshot }
		int(C.SDL_SCANCODE_GRAVE) { Command.fast_forward }
		else { return none }
	}

	if !down && command != .fast_forward {
		return none
	}
	return Event{
		kind:    .command
		command: command
		pressed: down
	}
}

// decode_gamepad_button maps the standard gamepad layout to the Jaguar pad:
// the three face buttons read C, B, A from left to right.
fn decode_gamepad_button(button u8) ?jerry.Button {
	return match int(button) {
		int(C.SDL_GAMEPAD_BUTTON_DPAD_UP) { jerry.Button.up }
		int(C.SDL_GAMEPAD_BUTTON_DPAD_DOWN) { jerry.Button.down }
		int(C.SDL_GAMEPAD_BUTTON_DPAD_LEFT) { jerry.Button.left }
		int(C.SDL_GAMEPAD_BUTTON_DPAD_RIGHT) { jerry.Button.right }
		int(C.SDL_GAMEPAD_BUTTON_WEST) { jerry.Button.c }
		int(C.SDL_GAMEPAD_BUTTON_SOUTH) { jerry.Button.b }
		int(C.SDL_GAMEPAD_BUTTON_EAST) { jerry.Button.a }
		int(C.SDL_GAMEPAD_BUTTON_NORTH) { jerry.Button.option }
		int(C.SDL_GAMEPAD_BUTTON_START) { jerry.Button.pause }
		int(C.SDL_GAMEPAD_BUTTON_BACK) { jerry.Button.option }
		int(C.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER) { jerry.Button.star }
		int(C.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER) { jerry.Button.hash }
		else { return none }
	}
}
