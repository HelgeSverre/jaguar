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
	sync_pad // authoritative live state after a lifecycle change
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
	shell  // dress or undress the window
	shrink // make the shell smaller
	grow   // make the shell larger
	quit
}

// Event is one decoded host event.
pub struct Event {
pub:
	kind      EventKind
	port      int
	button    jerry.Button
	pressed   bool
	immediate bool // lifecycle releases bypass the frontend's short-tap delay
	command   Command
	path      string
	buttons   u32
}

// Input owns host state; only aggregate guest transitions leave this module.
pub struct Input {
mut:
	pads           [2]PadState
	keys           map[int]jerry.Button
	mouse          u32
	combined       [2]u32
	pending        []Event
	focused        bool = true
	config         ControllerConfig
	game           string
	menu           bool
	menu_port      int
	menu_row       int
	game_scope     bool
	capturing      bool
	capture_mask   u64
	capture_append bool
	notice         string
pub mut:
	shell &Shell = unsafe { nil }
}

// poll returns the next aggregate input transition or frontend event.
pub fn (mut input Input) poll() Event {
	if input.pending.len > 0 { return input.pop() }
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
				input.focused = false
				input.capturing = false
				input.reset_live()
				input.pending << Event{
					kind: .focus_lost
				}
			}
			u32(C.SDL_EVENT_WINDOW_FOCUS_GAINED) {
				input.focused = true
				for port in 0 .. 2 {
					input.sample_and_rearm(port)
				}
			}
			u32(C.SDL_EVENT_KEY_DOWN), u32(C.SDL_EVENT_KEY_UP) {
				key := unsafe { event.key }
				if key.repeat || !input.focused {
					continue
				}
				if key.scancode == int(C.SDL_SCANCODE_K) {
					if key.down { input.toggle_controls() }
				} else if input.menu {
					if key.down { input.menu_key(key.scancode) }
				} else if decoded := decode_key(key.scancode, key.down) {
					input.keyboard(key.scancode, decoded)
				}
			}
			u32(C.SDL_EVENT_GAMEPAD_ADDED) {
				input.attach(unsafe { event.gdevice.which })
			}
			u32(C.SDL_EVENT_GAMEPAD_REMOVED) {
				input.detach(unsafe { event.gdevice.which })
			}
			u32(C.SDL_EVENT_GAMEPAD_REMAPPED) {
				port := input.port_of(unsafe { event.gdevice.which })
				if port >= 0 {
					input.sample_and_rearm(port)
					input.reconcile(true)
					input.sync_port(port)
				}
			}
			u32(C.SDL_EVENT_GAMEPAD_AXIS_MOTION) {
				axis := unsafe { event.gaxis }
				port := input.port_of(axis.which)
				if port >= 0 {
					input.pads[port].axis(int(axis.axis), axis.value)
					input.pad_changed(port)
				}
			}
			u32(C.SDL_EVENT_GAMEPAD_BUTTON_DOWN), u32(C.SDL_EVENT_GAMEPAD_BUTTON_UP) {
				pad := unsafe { event.gbutton }
				port := input.port_of(pad.which)
				if port >= 0 && int(pad.button) < control_names.len {
					bit := u64(1) << pad.button
					if pad.down {
						input.pads[port].raw |= bit
					} else {
						input.pads[port].raw &= ~bit
					}
					input.pad_changed(port)
				}
			}
			u32(C.SDL_EVENT_MOUSE_MOTION) {
				if input.shell != unsafe { nil } {
					motion := unsafe { event.motion }
					input.shell.hover = input.shell.control_at_point(motion.x, motion.y)
				}
			}
			u32(C.SDL_EVENT_WINDOW_MOUSE_LEAVE) {
				if input.shell != unsafe { nil } { input.shell.hover = Control{} }
			}
			u32(C.SDL_EVENT_MOUSE_BUTTON_DOWN), u32(C.SDL_EVENT_MOUSE_BUTTON_UP) {
				click := unsafe { event.button }
				if input.shell == unsafe { nil } || click.button != 1 || input.menu
					|| !input.focused {
					continue
				}
				if decoded := input.shell.click(click.x, click.y, click.down) {
					if decoded.kind == .button {
						input.mouse = if decoded.pressed {
							u32(1) << u32(decoded.button)
						} else {
							u32(0)
						}
						input.reconcile(false)
					} else {
						input.pending << decoded
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

		if input.pending.len > 0 { return input.pop() }
	}
	return Event{}
}

fn (mut input Input) pop() Event {
	event := input.pending[0]
	input.pending.delete(0)
	return event
}

// click presses or releases the shell control under the pointer. A button
// acts when pressed; a keypad key is held until the mouse button comes up,
// wherever the pointer is by then.
fn (mut s Shell) click(x f32, y f32, down bool) ?Event {
	if !down {
		held := s.held
		s.held = Control{}
		if held.kind == .key {
			return Event{
				kind:   .button
				button: shell_keys[held.index]
			}
		}
		return none
	}
	s.held = s.control_at_point(x, y)
	return match s.held.kind {
		.none {
			none
		}
		.command {
			Event{
				kind:    .command
				command: shell_commands[s.held.index]
				pressed: true
			}
		}
		.key {
			Event{
				kind:    .button
				button:  shell_keys[s.held.index]
				pressed: true
			}
		}
	}
}

// decode_key maps a keyboard scancode to a controller button on port 0 or
// to a frontend command. A scancode names a key by its place, not its label,
// and the punctuation and function keys are awkward on many keyboards (a
// Norwegian one has no `[`, `]`, `=` or `` ` `` of its own; a laptop wants Fn
// for F5), so each of those also has a letter, comma, full stop or the
// space bar: keys that sit in the same place on every layout.
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
		int(C.SDL_SCANCODE_Q), int(C.SDL_SCANCODE_MINUS), int(C.SDL_SCANCODE_KP_MULTIPLY) { jerry.Button.star }
		int(C.SDL_SCANCODE_W), int(C.SDL_SCANCODE_EQUALS), int(C.SDL_SCANCODE_KP_DIVIDE) { jerry.Button.hash }
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
		int(C.SDL_SCANCODE_F5), int(C.SDL_SCANCODE_R) { Command.reset }
		int(C.SDL_SCANCODE_F11), int(C.SDL_SCANCODE_F) { Command.fullscreen }
		int(C.SDL_SCANCODE_M) { Command.mute }
		int(C.SDL_SCANCODE_F1), int(C.SDL_SCANCODE_I) { Command.overlay }
		int(C.SDL_SCANCODE_F12), int(C.SDL_SCANCODE_S) { Command.screenshot }
		int(C.SDL_SCANCODE_GRAVE), int(C.SDL_SCANCODE_SPACE) { Command.fast_forward }
		int(C.SDL_SCANCODE_F2), int(C.SDL_SCANCODE_H) { Command.shell }
		int(C.SDL_SCANCODE_LEFTBRACKET), int(C.SDL_SCANCODE_COMMA) { Command.shrink }
		int(C.SDL_SCANCODE_RIGHTBRACKET), int(C.SDL_SCANCODE_PERIOD) { Command.grow }
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
