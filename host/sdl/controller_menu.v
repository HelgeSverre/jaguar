module sdl

import os

// configure loads profiles and optional SDL mappings, then reconciles devices
// already attached. SDL's later ADDED events are harmless duplicates.
pub fn (mut input Input) configure(path string, game string) {
	input.config = load_controller_config(path)
	input.notice = input.config.notice
	input.load_mappings()
	input.set_game(game)
	input.discover()
}

// set_game selects profiles by normalized image hash and releases old inputs.
pub fn (mut input Input) set_game(game string) {
	input.game = game
	input.capturing = false
	input.game_scope = false
	for port in 0 .. 2 {
		input.pads[port].profile = input.config.profile(game, port)
	}
	input.reset_live()
}

fn (mut input Input) load_mappings() {
	if input.config.path == '' { return }
	path := os.join_path(os.dir(input.config.path), 'gamecontrollerdb.txt')
	if os.exists(path) {
		count := C.SDL_AddGamepadMappingsFromFile(path.str)
		input.notice = if count < 0 {
			'Mappings: ${last_error()}'
		} else {
			'Loaded ${count} controller mappings'
		}
	}
}

fn (mut input Input) toggle_controls() {
	input.menu = !input.menu
	input.capturing = false
	input.reset_live()
	// A fast-forward key can be released while the menu consumes keyboard
	// events, even if the menu opens and closes within one event batch.
	input.pending << Event{
		kind:    .command
		command: .fast_forward
		pressed: false
	}
}

fn (input &Input) edit_profile() ControllerProfile {
	return input.config.profile(if input.game_scope { input.game } else { '' }, input.menu_port)
}

fn (mut input Input) store_profile(p ControllerProfile) {
	prefix := if input.game_scope && input.game != '' { input.game } else { 'global' }
	input.config.profiles['${prefix}_${input.menu_port + 1}'] = p
	input.pads[input.menu_port].profile = input.config.profile(input.game, input.menu_port)
	input.reset_live()
	input.save_controls()
}

fn (mut input Input) save_controls() {
	input.config.save() or {
		input.notice = 'Controls not saved: ${err.msg()}'
		return
	}
	input.notice = 'Controls saved'
}

fn (mut input Input) menu_key(key int) {
	if key == int(C.SDL_SCANCODE_ESCAPE) {
		if input.capturing {
			input.capturing = false
		} else {
			input.toggle_controls()
		}
		return
	}
	if input.capturing { return }
	match key {
		int(C.SDL_SCANCODE_UP) {
			input.menu_row = (input.menu_row + 23) % 24
		}
		int(C.SDL_SCANCODE_DOWN) {
			input.menu_row = (input.menu_row + 1) % 24
		}
		int(C.SDL_SCANCODE_TAB) {
			input.menu_port = 1 - input.menu_port
		}
		int(C.SDL_SCANCODE_G) {
			if input.game != '' { input.game_scope = !input.game_scope }
		}
		int(C.SDL_SCANCODE_RETURN), int(C.SDL_SCANCODE_A) {
			if input.menu_row < 22 {
				if input.pads[input.menu_port].handle == unsafe { nil } {
					input.notice = 'Connect a mapped gamepad first'
					return
				}
				input.capturing = true
				input.capture_append = key == int(C.SDL_SCANCODE_A)
				input.capture_mask = 0
				input.pads[input.menu_port].rearm()
			} else if input.menu_row == 23 {
				input.cycle_device()
			}
		}
		int(C.SDL_SCANCODE_LEFT), int(C.SDL_SCANCODE_RIGHT) {
			if input.menu_row == 22 {
				mut p := input.edit_profile()
				step := if key == int(C.SDL_SCANCODE_LEFT) { -5 } else { 5 }
				percent := (p.press * 100 + 16383) / 32767 + step
				if percent >= 10 && percent <= 90 {
					p.press = percent * 32767 / 100
					p.release = (percent - 10) * 32767 / 100
					input.store_profile(p)
				}
			} else if input.menu_row == 23 {
				input.cycle_device()
			}
		}
		int(C.SDL_SCANCODE_BACKSPACE) {
			if input.menu_row < 22 {
				mut p := input.edit_profile()
				p.expressions[input.menu_row] = ''
				p.compile() or { return }
				input.store_profile(p)
			}
		}
		int(C.SDL_SCANCODE_R) {
			input.store_profile(default_profile())
		}
		int(C.SDL_SCANCODE_I) {
			if input.game_scope && input.game != '' {
				input.config.profiles.delete('${input.game}_${input.menu_port + 1}')
				input.pads[input.menu_port].profile = input.config.profile(input.game,
					input.menu_port)
				input.reset_live()
				input.save_controls()
			}
		}
		int(C.SDL_SCANCODE_L) {
			input.load_mappings()
			input.discover()
		}
		int(C.SDL_SCANCODE_D) {
			input.cycle_device()
		}
		else {}
	}
}

fn (mut input Input) capture_control(port int) {
	if !input.capturing || input.menu_port != port { return }
	active := input.pads[port].raw & ~input.pads[port].blocked
	// Keep the largest simultaneously held chord. Accumulating all directions
	// of a rolling stick would create an impossible left+right binding.
	if control_count(active) > control_count(input.capture_mask) { input.capture_mask = active }
	if active != 0 || input.capture_mask == 0 { return }
	mut p := input.edit_profile()
	expression := controls_text(input.capture_mask)
	if input.capture_append && p.expressions[input.menu_row] != '' {
		p.expressions[input.menu_row] += '|' + expression
	} else {
		p.expressions[input.menu_row] = expression
	}
	p.compile() or {
		input.notice = err.msg()
		input.capturing = false
		return
	}
	input.capturing = false
	input.store_profile(p)
}

fn control_count(mask u64) int {
	mut bits := mask
	mut count := 0
	for bits != 0 {
		bits &= bits - 1
		count++
	}
	return count
}

fn (mut input Input) cycle_device() {
	mut count := 0
	ids := C.SDL_GetGamepads(&count)
	if ids == unsafe { nil } { return }
	defer { C.SDL_free(ids) }
	if count == 0 {
		input.notice = 'No mapped gamepads found'
		return
	}
	port := input.menu_port
	mut index := -1
	for i in 0 .. count {
		if unsafe { ids[i] } == input.pads[port].id { index = i }
	}
	id := unsafe { ids[(index + 1) % count] }
	mut other := input.port_of(id)
	if other < 0 {
		if input.pads[port].handle != unsafe { nil } { C.SDL_CloseGamepad(input.pads[port].handle) }
		input.pads[port] = PadState{}
		input.attach(id)
		other = input.port_of(id)
	}
	if other < 0 { return }
	if other != port {
		temporary := input.pads[port]
		input.pads[port] = input.pads[other]
		input.pads[other] = temporary
	}
	for i in 0 .. 2 {
		input.pads[i].profile = input.config.profile(input.game, i)
		input.config.preferred[i] = input.pads[i].identity
	}
	input.reset_live()
	input.save_controls()
}

fn button_label(handle voidptr, button int) string {
	label := C.SDL_GetGamepadButtonLabel(handle, button)
	return match label {
		int(C.SDL_GAMEPAD_BUTTON_LABEL_A) { 'A' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_B) { 'B' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_X) { 'X' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_Y) { 'Y' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_CROSS) { 'Cross' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE) { 'Circle' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_SQUARE) { 'Square' }
		int(C.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE) { 'Triangle' }
		else { control_names[button] }
	}
}

// control_lines describes the controls panel or active keypads, with or without a cartridge.
pub fn (input &Input) control_lines() []string {
	if !input.menu {
		mut lines := []string{}
		for port in 0 .. 2 {
			pad := input.pads[port]
			if !pad.layer {
				continue
			}
			lines << 'PLAYER ${port + 1} KEYPAD - directions + South'
			for row in 0 .. 4 {
				mut cells := []string{}
				for col in 0 .. 3 {
					i := row * 3 + col
					label := keypad_labels[i]
					cells << if pad.held_key == i {
						'*${label}*'
					} else if pad.selected == i {
						'[${label}]'
					} else {
						' ${label} '
					}
				}
				lines << cells.join(' ')
			}
		}
		return lines
	}
	port := input.menu_port
	pad := input.pads[port]
	p := input.edit_profile()
	mut lines := [
		'CONTROLS - Player ${port + 1} / ${if input.game_scope { 'this game' } else { 'global' }}',
		'K/Esc close  Tab player  G scope  D device',
		'Up/Down select  Enter replace  A add binding',
		'Backspace clear  R defaults  I inherit  L mappings',
	]
	if input.capturing {
		lines << 'Hold desired control/chord, then release. Esc cancels.'
	} else {
		lines << 'Bindings save automatically. Keypad layer keeps game running.'
	}
	start := if input.menu_row > 4 { input.menu_row - 4 } else { 0 }
	end := if start + 7 < 24 { start + 7 } else { 24 }
	for row in start .. end {
		prefix := if row == input.menu_row { '> ' } else { '  ' }
		if row < 22 {
			lines << '${prefix}${target_names[row]}: ${if p.expressions[row] == '' {
				'(unbound)'
			} else {
				p.expressions[row]
			}}'
		} else if row == 22 {
			lines << '${prefix}Dead zone: ${(p.press * 100 + 16383) / 32767}% on / ${(
				p.release * 100 + 16383) / 32767}% off (Left/Right)'
		} else {
			lines << '${prefix}Device: Enter cycles connected gamepads'
		}
	}
	version := C.SDL_GetVersion()
	lines << 'SDL ${version / 1000000}.${version / 1000 % 1000}.${version % 1000} | ${if pad.name == '' {
		'No mapped gamepad assigned'
	} else {
		pad.name
	}}'
	if pad.handle != unsafe { nil } {
		connection := match C.SDL_GetGamepadConnectionState(pad.handle) {
			int(C.SDL_JOYSTICK_CONNECTION_WIRED) { 'wired' }
			int(C.SDL_JOYSTICK_CONNECTION_WIRELESS) { 'wireless' }
			else { 'connection unknown' }
		}

		mut percent := -1
		C.SDL_GetGamepadPowerInfo(pad.handle, &percent)
		battery := if percent < 0 { 'battery unknown' } else { 'battery ${percent}%' }
		lines << '${connection}, ${battery} | West/South/East: ${button_label(pad.handle, 2)}/${button_label(pad.handle, 0)}/${button_label(pad.handle, 1)}'
		lines << 'Held: ${controls_text(pad.raw)}'
		mut buttons := 0
		mut axes := 0
		for i in 0 .. control_names.len {
			if C.SDL_GamepadHasButton(pad.handle, i) { buttons++ }
		}
		for i in 0 .. 6 {
			if C.SDL_GamepadHasAxis(pad.handle, i) { axes++ }
		}
		mapping := C.SDL_GetGamepadMapping(pad.handle)
		mapping_id := c_text(mapping).all_before(',')
		C.SDL_free(mapping)
		lines << '${buttons} buttons, ${axes} axes | Mapping ${mapping_id}'
	}
	mut count := 0
	ids := C.SDL_GetJoysticks(&count)
	if ids != unsafe { nil } {
		mut unknown := 0
		for i in 0 .. count {
			id := unsafe { ids[i] }
			if !C.SDL_IsGamepad(id) {
				unknown++
				if unknown <= 2 {
					lines << 'Needs mapping: ${c_text(C.SDL_GetJoystickNameForID(id))}'
					lines << 'GUID: ${joystick_guid(id)}'
				}
			}
		}
		lines << '${count} devices visible; ${unknown} need SDL mappings (gamecontrollerdb.txt)'
		C.SDL_free(ids)
	}
	if input.notice != '' { lines << input.notice }
	return lines
}

// controls_open tells the frontend to pause guest execution while editing.
pub fn (input &Input) controls_open() bool {
	return input.menu
}
