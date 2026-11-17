module sdl

import jerry

const keypad_buttons = [jerry.Button.one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
	.star, .zero, .hash]!
const keypad_labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#']!

struct PadState {
mut:
	handle     voidptr
	id         u32
	identity   string
	name       string
	raw        u64
	blocked    u64
	axes       [6]i16
	profile    ControllerProfile = default_profile()
	output     u32
	layer      bool
	selected   int = 4
	held_key   int = -1
	navigation u64
	chord_used u64
}

// Hysteresis applies independently to each direction, including direct reversals.
fn (mut pad PadState) axis(axis int, value i16) {
	if axis < 0 || axis >= 6 { return }
	pad.axes[axis] = value
	for sign in 0 .. 2 {
		bit := u64(1) << (32 + axis * 2 + sign)
		level := if sign == 0 { -int(value) } else { int(value) }
		threshold := if pad.raw & bit != 0 { pad.profile.release } else { pad.profile.press }
		if (axis < 4 || sign == 1) && level > threshold {
			pad.raw |= bit
		} else {
			pad.raw &= ~bit
		}
	}
}

fn (mut pad PadState) rearm() {
	pad.blocked = pad.raw
	pad.output = 0
	pad.layer = false
	pad.held_key = -1
	pad.navigation = 0
	pad.chord_used = 0
}

fn (mut pad PadState) update() {
	pad.blocked &= pad.raw
	mut active := pad.raw & ~pad.blocked
	chords := pad.profile.consumed(active)
	// Finishing a chord cannot turn its remaining held buttons into plain presses.
	pad.blocked |= pad.raw & pad.chord_used & ~chords
	pad.chord_used = chords
	active &= ~pad.blocked
	targets := pad.profile.targets(active)
	layer := targets & (u32(1) << 21) != 0
	// Directions used to navigate the keypad and South to confirm are consumed.
	nav_mask := (u64(15) << 11) | (u64(15) << 36)
	consumed := nav_mask | u64(1)
	if !layer && pad.layer {
		// Holding confirm while closing the layer must not become Jaguar B.
		pad.blocked |= pad.raw & consumed
		active &= ~consumed
	}
	if layer {
		nav := active & nav_mask
		fresh := nav & ~pad.navigation
		mut row := pad.selected / 3
		mut col := pad.selected % 3
		if fresh & ((u64(1) << 11) | (u64(1) << 38)) != 0 { row-- }
		if fresh & ((u64(1) << 12) | (u64(1) << 39)) != 0 { row++ }
		if fresh & ((u64(1) << 13) | (u64(1) << 36)) != 0 { col-- }
		if fresh & ((u64(1) << 14) | (u64(1) << 37)) != 0 { col++ }
		row = if row < 0 {
			0
		} else if row > 3 {
			3
		} else {
			row
		}
		col = if col < 0 {
			0
		} else if col > 2 {
			2
		} else {
			col
		}
		pad.selected = row * 3 + col
		pad.navigation = nav
		if active & 1 == 0 {
			pad.held_key = -1
		} else if pad.held_key < 0 {
			pad.held_key = pad.selected
		}
		active &= ~consumed
		for binding in pad.profile.bindings {
			if binding.target == 21 && (pad.raw & ~pad.blocked) & binding.chord == binding.chord {
				active &= ~binding.chord
			}
		}
	} else {
		pad.held_key = -1
		pad.navigation = 0
	}
	pad.layer = layer
	pad.output = pad.profile.targets(active) & 0x1fffff
	if pad.held_key >= 0 { pad.output |= u32(1) << u32(keypad_buttons[pad.held_key]) }
}

fn (mut input Input) reconcile(immediate bool) {
	mut keyboard := u32(0)
	for _, button in input.keys {
		keyboard |= u32(1) << u32(button)
	}
	for port in 0 .. 2 {
		mut state := input.pads[port].output
		if port == 0 { state |= keyboard | input.mouse }
		if !input.focused || input.menu { state = 0 }
		changed := state ^ input.combined[port]
		for button in 0 .. 21 {
			bit := u32(1) << button
			if changed & bit != 0 {
				input.pending << Event{
					kind:      .button
					port:      port
					button:    unsafe { jerry.Button(button) }
					pressed:   state & bit != 0
					immediate: immediate
				}
			}
		}
		input.combined[port] = state
	}
}

// reset_live clears host state on focus changes, cartridge replacement and menus.
// Raw controller levels stay blocked until released, avoiding phantom presses.
pub fn (mut input Input) reset_live() {
	input.keys.clear()
	input.mouse = 0
	if input.shell != unsafe { nil } { input.shell.held = Control{} }
	for port in 0 .. 2 {
		input.pads[port].rearm()
	}
	input.reconcile(true)
	for port in 0 .. 2 {
		input.sync_port(port)
	}
}

fn (mut input Input) sync_port(port int) {
	input.pending << Event{
		kind:    .sync_pad
		port:    port
		buttons: input.combined[port]
	}
}

fn (mut input Input) keyboard(scancode int, decoded Event) {
	if decoded.kind != .button {
		input.pending << decoded
		return
	}
	if decoded.pressed {
		input.keys[scancode] = decoded.button
	} else {
		input.keys.delete(scancode)
	}
	input.reconcile(false)
}

fn (mut input Input) pad_changed(port int) {
	was_layer := input.pads[port].layer
	was_chord := input.pads[port].chord_used
	input.pads[port].blocked &= input.pads[port].raw
	if input.menu {
		input.capture_control(port)
		input.pads[port].output = 0
	} else if !input.focused {
		input.pads[port].rearm()
	} else {
		input.pads[port].update()
	}
	// Entering a chord withdraws its plain bindings immediately; letting go
	// of the chord itself retains the frontend's normal short-tap guarantee.
	input.reconcile(was_layer != input.pads[port].layer
		|| (input.pads[port].chord_used != 0 && was_chord != input.pads[port].chord_used))
}

fn (mut input Input) attach(id u32) {
	if input.port_of(id) >= 0 { return }
	mut port := -1
	for i in 0 .. 2 {
		if input.pads[i].handle == unsafe { nil } {
			port = i
			break
		}
	}
	if port < 0 { return }
	handle := C.SDL_OpenGamepad(id)
	if handle == unsafe { nil } {
		input.notice = 'Cannot open controller: ${last_error()}'
		return
	}
	name := c_text(C.SDL_GetGamepadName(handle))
	serial := c_text(C.SDL_GetGamepadSerial(handle))
	identity := '${C.SDL_GetGamepadVendor(handle):04x}:${C.SDL_GetGamepadProduct(handle):04x}:${name}:${serial}'
	// Preferences are hints: absent/indistinguishable devices still get usable slots.
	for i in 0 .. 2 {
		if input.pads[i].handle == unsafe { nil } && input.config.preferred[i] == identity {
			port = i
			break
		}
	}
	input.pads[port] = PadState{
		handle:   handle
		id:       id
		name:     name
		identity: identity
		profile:  input.config.profile(input.game, port)
	}
	input.sample_and_rearm(port)
}

fn (mut input Input) sample_and_rearm(port int) {
	mut pad := &input.pads[port]
	pad.raw = 0
	if pad.handle != unsafe { nil } {
		for button in 0 .. control_names.len {
			if C.SDL_GetGamepadButton(pad.handle, button) { pad.raw |= u64(1) << button }
		}
		for axis in 0 .. 6 {
			pad.axis(axis, C.SDL_GetGamepadAxis(pad.handle, axis))
		}
	}
	pad.rearm()
}

fn (mut input Input) detach(id u32) {
	port := input.port_of(id)
	if port < 0 { return }
	C.SDL_CloseGamepad(input.pads[port].handle)
	input.pads[port] = PadState{
		profile: input.config.profile(input.game, port)
	}
	input.reconcile(true)
	// SDL may send synthetic button-up events before REMOVED. The snapshot
	// also cancels frontend tap delays created by those earlier releases.
	input.sync_port(port)
	input.discover()
}

fn (input &Input) port_of(id u32) int {
	for port in 0 .. 2 {
		if input.pads[port].handle != unsafe { nil } && input.pads[port].id == id { return port }
	}
	return -1
}

fn (mut input Input) discover() {
	mut count := 0
	ids := C.SDL_GetGamepads(&count)
	if ids == unsafe { nil } { return }
	for i in 0 .. count {
		input.attach(unsafe { ids[i] })
	}
	C.SDL_free(ids)
}

// close releases all open controller handles before SDL quits.
pub fn (mut input Input) close() {
	for port in 0 .. 2 {
		if input.pads[port].handle != unsafe { nil } { C.SDL_CloseGamepad(input.pads[port].handle) }
		input.pads[port] = PadState{}
	}
}
