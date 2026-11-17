module sdl

import jerry
import os

fn push_key(scancode int, down bool) {
	key := C.SDL_KeyboardEvent{
		type:     if down { u32(C.SDL_EVENT_KEY_DOWN) } else { u32(C.SDL_EVENT_KEY_UP) }
		scancode: scancode
		down:     down
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&key) })
}

fn virtual_pad() (u32, voidptr) {
	desc := C.SDL_VirtualJoystickDesc{
		version:     u32(sizeof(C.SDL_VirtualJoystickDesc))
		type:        u16(C.SDL_JOYSTICK_TYPE_GAMEPAD)
		vendor_id:   0xbeef
		product_id:  0x2355
		naxes:       6
		nbuttons:    26
		button_mask: 0x3ffffff
		axis_mask:   63
		name:        c'vjag virtual test pad'
	}
	id := C.SDL_AttachVirtualJoystick(&desc)
	assert id != 0, last_error()
	joystick := C.SDL_OpenJoystick(id)
	assert joystick != unsafe { nil }
	assert C.SDL_SetJoystickVirtualAxis(joystick, 4, -32768)
	assert C.SDL_SetJoystickVirtualAxis(joystick, 5, -32768)
	C.SDL_UpdateJoysticks()
	return id, joystick
}

fn start_gamepads() {
	// Real pads plugged into the test machine must not claim the virtual
	// players' slots or get opened by the tests. This hint is process-local.
	C.SDL_SetHint(c'SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT', c'0xbeef/0x2355,0xbeef/0x2356')
	C.SDL_SetHint(c'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS', c'1')
	assert C.SDL_Init(u32(C.SDL_INIT_GAMEPAD))
}

fn drain(mut input Input) []Event {
	mut events := []Event{}
	for {
		event := input.poll()
		if event.kind == .none { return events }
		events << event
	}
	return events
}

fn bit(button jerry.Button) u32 {
	return u32(1) << u32(button)
}

fn test_real_sdl_mapping_and_overlapping_inputs() {
	start_gamepads()
	id, joystick := virtual_pad()
	mut input := Input{}
	defer {
		input.close()
		C.SDL_CloseJoystick(joystick)
		C.SDL_DetachVirtualJoystick(id)
		C.SDL_Quit()
	}
	drain(mut input)
	assert input.port_of(id) == 0
	// North and Back both hold Option; releasing one cannot release the other.
	assert C.SDL_SetJoystickVirtualButton(joystick, 3, true)
	drain(mut input)
	assert input.combined[0] == bit(.option)
	assert C.SDL_SetJoystickVirtualButton(joystick, 4, true)
	assert drain(mut input).len == 0
	assert C.SDL_SetJoystickVirtualButton(joystick, 3, false)
	assert drain(mut input).len == 0
	assert input.combined[0] == bit(.option)
	assert C.SDL_SetJoystickVirtualButton(joystick, 4, false)
	drain(mut input)
	assert input.combined[0] == 0
	// A keyboard release cannot cancel a still-held controller button.
	push_key(int(C.SDL_SCANCODE_X), true)
	drain(mut input)
	assert C.SDL_SetJoystickVirtualButton(joystick, 0, true)
	drain(mut input)
	push_key(int(C.SDL_SCANCODE_X), false)
	assert drain(mut input).len == 0
	assert input.combined[0] == bit(.b)
	assert C.SDL_SetJoystickVirtualButton(joystick, 0, false)
	drain(mut input)
	assert input.combined[0] == 0
	// Stick diagonal, hysteresis, d-pad overlap and a direct reversal.
	assert C.SDL_SetJoystickVirtualAxis(joystick, 0, 16000)
	assert C.SDL_SetJoystickVirtualAxis(joystick, 1, -16000)
	drain(mut input)
	assert input.combined[0] == bit(.right) | bit(.up)
	assert C.SDL_SetJoystickVirtualAxis(joystick, 0, 8000)
	drain(mut input)
	assert input.combined[0] & bit(.right) != 0
	assert C.SDL_SetJoystickVirtualButton(joystick, 14, true)
	assert C.SDL_SetJoystickVirtualAxis(joystick, 0, 5000)
	drain(mut input)
	assert input.combined[0] & bit(.right) != 0
	assert C.SDL_SetJoystickVirtualButton(joystick, 14, false)
	assert C.SDL_SetJoystickVirtualAxis(joystick, 0, -16000)
	drain(mut input)
	assert input.combined[0] == bit(.left) | bit(.up)
}

fn test_disconnect_is_per_device_and_waiting_pad_fills_vacancy() {
	start_gamepads()
	id1, joy1 := virtual_pad()
	id2, joy2 := virtual_pad()
	id3, joy3 := virtual_pad()
	mut input := Input{}
	defer {
		input.close()
		C.SDL_CloseJoystick(joy1)
		C.SDL_CloseJoystick(joy2)
		C.SDL_CloseJoystick(joy3)
		C.SDL_DetachVirtualJoystick(id2)
		C.SDL_DetachVirtualJoystick(id3)
		C.SDL_Quit()
	}
	drain(mut input)
	assert input.port_of(id1) == 0
	assert input.port_of(id2) == 1
	assert input.port_of(id3) == -1
	input.attach(id1)
	assert input.port_of(id2) == 1, 'duplicate add must not claim player two'
	assert C.SDL_SetJoystickVirtualButton(joy1, 0, true)
	assert C.SDL_SetJoystickVirtualButton(joy2, 1, true)
	push_key(int(C.SDL_SCANCODE_X), true)
	drain(mut input)
	assert C.SDL_DetachVirtualJoystick(id1)
	events := drain(mut input)
	assert events.all(it.kind != .focus_lost)
	assert input.combined[0] == bit(.b), 'keyboard still holds B'
	assert input.combined[1] == bit(.a), 'player two still holds A'
	assert input.port_of(id3) == 0
	assert input.port_of(id1) == -1
	push_key(int(C.SDL_SCANCODE_X), false)
	drain(mut input)
	assert input.combined[0] == 0
	input.toggle_controls()
	input.menu_port = 0
	input.cycle_device()
	assert input.port_of(id2) == 0
	assert input.port_of(id3) == 1
	assert input.combined == [u32(0), 0]!, 'reassignment releases and rearms both slots'
}

fn test_keypad_latches_held_key_and_consumes_confirmation() {
	start_gamepads()
	id, joy := virtual_pad()
	mut input := Input{}
	defer {
		input.close()
		C.SDL_CloseJoystick(joy)
		C.SDL_DetachVirtualJoystick(id)
		C.SDL_Quit()
	}
	drain(mut input)
	assert C.SDL_SetJoystickVirtualAxis(joy, 4, 32767)
	drain(mut input)
	assert input.pads[0].layer
	assert input.control_lines().len == 5
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.five)
	assert C.SDL_SetJoystickVirtualButton(joy, 14, true)
	drain(mut input)
	assert input.pads[0].selected == 5
	assert input.combined[0] == bit(.five), 'selection cannot move a held key'
	assert C.SDL_SetJoystickVirtualAxis(joy, 4, -32768)
	drain(mut input)
	assert input.combined[0] == 0, 'closing layer must not fire B or move right'
	assert C.SDL_SetJoystickVirtualButton(joy, 0, false)
	assert C.SDL_SetJoystickVirtualButton(joy, 14, false)
	drain(mut input)
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.b)
}

fn test_focus_reset_requires_release_and_preserves_new_presses() {
	mut input := Input{}
	input.pads[0].raw = control_bit('south')!
	input.pads[0].update()
	input.reconcile(false)
	assert input.combined[0] == bit(.b)
	input.reset_live()
	assert input.combined[0] == 0
	input.pad_changed(0)
	assert input.combined[0] == 0
	input.pads[0].raw = 0
	input.pad_changed(0)
	input.pads[0].raw = control_bit('south')!
	input.pad_changed(0)
	assert input.combined[0] == bit(.b)
}

fn test_all_keypad_buttons_and_chords_are_bindable() {
	mut pad := PadState{}
	pad.raw = control_bit('lefttrigger')! | control_bit('south')!
	for i, button in keypad_buttons {
		pad.selected = i
		pad.held_key = -1
		pad.update()
		assert pad.output == bit(button)
	}
	mut p := default_profile()
	p.expressions[int(jerry.Button.one)] = 'rightshoulder+south|righttrigger'
	p.expressions[int(jerry.Button.nine)] = 'rightshoulder+south'
	p.compile()!
	result := p.targets(control_bit('rightshoulder')! | control_bit('south')!)
	assert result & (bit(.one) | bit(.nine)) == bit(.one) | bit(.nine)
	assert result & (bit(.b) | bit(.hash)) == 0, 'chords consume their individual bindings'
	assert p.targets(control_bit('righttrigger')!) == bit(.one)
	assert chord_mask('invented') or { u64(0) } == 0
}

fn test_unknown_joystick_gets_mapping_at_runtime() {
	start_gamepads()
	desc := C.SDL_VirtualJoystickDesc{
		version:    u32(sizeof(C.SDL_VirtualJoystickDesc))
		type:       u16(C.SDL_JOYSTICK_TYPE_FLIGHT_STICK)
		vendor_id:  0xbeef
		product_id: 0x2356
		naxes:      4
		nbuttons:   4
		name:       c'vjag unmapped test joystick'
	}
	id := C.SDL_AttachVirtualJoystick(&desc)
	assert id != 0
	joy := C.SDL_OpenJoystick(id)
	dir := os.join_path(os.temp_dir(), 'vjag-mapping-${os.getpid()}')
	os.mkdir_all(dir)!
	mut input := Input{}
	defer {
		input.close()
		C.SDL_CloseJoystick(joy)
		C.SDL_DetachVirtualJoystick(id)
		C.SDL_Quit()
		os.rmdir_all(dir) or {}
	}
	input.configure(os.join_path(dir, 'controllers.toml'), '')
	drain(mut input)
	assert !C.SDL_IsGamepad(id)
	assert input.port_of(id) == -1
	input.toggle_controls()
	assert input.control_lines().any(it.contains('Needs mapping:'))
	mapping := '${joystick_guid(id)},vjag mapped test,a:b0,b:b1,x:b2,y:b3,leftx:a0,lefty:a1,rightx:a2,righty:a3,platform:${c_text(C.SDL_GetPlatform())},\n'
	os.write_file(os.join_path(dir, 'gamecontrollerdb.txt'), mapping)!
	input.load_mappings()
	input.discover()
	drain(mut input)
	assert C.SDL_IsGamepad(id)
	assert input.port_of(id) == 0
	assert input.pads[1].handle == unsafe { nil }, 'enumeration plus ADDED must open only once'
	input.toggle_controls()
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.b)
	// Replacing a mapping while held clears the old guest button and requires
	// neutral before the newly mapped button is allowed to act.
	os.write_file(os.join_path(dir, 'gamecontrollerdb.txt'), mapping.replace('a:b0,b:b1',
		'a:b1,b:b0'))!
	input.load_mappings()
	drain(mut input)
	assert input.combined[0] == 0
	assert input.port_of(id) == 0
	assert input.pads[1].handle == unsafe { nil }
	assert C.SDL_SetJoystickVirtualButton(joy, 0, false)
	drain(mut input)
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.a)
}

fn test_controls_capture_chords_persist_and_do_not_reach_guest() {
	start_gamepads()
	id, joy := virtual_pad()
	dir := os.join_path(os.temp_dir(), 'vjag-bind-${os.getpid()}')
	mut input := Input{}
	defer {
		input.close()
		C.SDL_CloseJoystick(joy)
		C.SDL_DetachVirtualJoystick(id)
		C.SDL_Quit()
		os.rmdir_all(dir) or {}
	}
	input.configure(os.join_path(dir, 'controllers.toml'), 'abc123')
	drain(mut input)
	input.toggle_controls()
	input.menu_key(int(C.SDL_SCANCODE_G))
	input.menu_row = int(jerry.Button.one)
	input.menu_key(int(C.SDL_SCANCODE_RETURN))
	assert input.capturing
	assert C.SDL_SetJoystickVirtualButton(joy, 10, true)
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == 0
	assert C.SDL_SetJoystickVirtualButton(joy, 0, false)
	assert C.SDL_SetJoystickVirtualButton(joy, 10, false)
	drain(mut input)
	assert !input.capturing
	assert input.config.profile('abc123', 0).expressions[int(jerry.Button.one)] == 'south+rightshoulder'
	assert input.config.profile('', 0).expressions[int(jerry.Button.one)] == ''
	loaded := load_controller_config(input.config.path)
	assert loaded.profile('abc123', 0).expressions[int(jerry.Button.one)] == 'south+rightshoulder'
	input.toggle_controls()
	assert C.SDL_SetJoystickVirtualButton(joy, 10, true)
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.one)
	input.set_game('another_game')
	drain(mut input)
	assert input.combined[0] == 0
	assert input.pads[0].profile.expressions[int(jerry.Button.one)] == ''
}

fn test_reconnect_changes_id_and_held_controls_need_neutral() {
	start_gamepads()
	id, joy := virtual_pad()
	mut input := Input{}
	drain(mut input)
	assert C.SDL_SetJoystickVirtualButton(joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.b)
	assert C.SDL_DetachVirtualJoystick(id)
	events := drain(mut input)
	assert events.any(it.kind == .sync_pad && it.buttons == 0)
	assert input.combined[0] == 0
	C.SDL_CloseJoystick(joy)
	new_id, new_joy := virtual_pad()
	defer {
		input.close()
		C.SDL_CloseJoystick(new_joy)
		C.SDL_DetachVirtualJoystick(new_id)
		C.SDL_Quit()
	}
	assert new_id != id
	assert C.SDL_SetJoystickVirtualButton(new_joy, 0, true)
	C.SDL_UpdateJoysticks()
	input.discover()
	drain(mut input)
	assert input.combined[0] == 0
	assert C.SDL_SetJoystickVirtualButton(new_joy, 0, false)
	drain(mut input)
	assert C.SDL_SetJoystickVirtualButton(new_joy, 0, true)
	drain(mut input)
	assert input.combined[0] == bit(.b)
}

fn test_profiles_round_trip_without_mutating_global_defaults() {
	path := os.join_path(os.temp_dir(), 'vjag-controllers-${os.getpid()}', 'controllers.toml')
	defer { os.rmdir_all(os.dir(path)) or {} }
	mut config := load_controller_config(path)
	config.profiles['global_1'] = default_profile()
	mut game := config.profile('abc123', 0)
	game.expressions[int(jerry.Button.one)] = 'south+rightshoulder'
	game.compile()!
	config.profiles['abc123_1'] = game
	config.preferred[0] = 'Sony "Pad"\\test'
	config.save()!
	loaded := load_controller_config(path)
	assert loaded.notice == ''
	assert loaded.preferred[0] == config.preferred[0]
	assert loaded.profile('', 0).expressions[int(jerry.Button.one)] == ''
	assert loaded.profile('abc123', 0).expressions[int(jerry.Button.one)] == 'south+rightshoulder'
	assert loaded.profile('', 1).expressions == default_profile().expressions
	os.write_file(path, '[profiles.global_1]\npress=5\nrelease=50\nsouth="typo"\none="imaginary"\n')!
	invalid := load_controller_config(path)
	assert invalid.notice != ''
	assert invalid.profile('', 0).press == default_profile().press
	os.write_file(path, 'this is not TOML')!
	broken := load_controller_config(path)
	broken.save() or { return }
	assert false, 'unreadable configuration must not be overwritten'
}

fn test_rolling_stick_capture_keeps_a_possible_simultaneous_chord() {
	mut input := Input{
		menu:      true
		capturing: true
		menu_row:  int(jerry.Button.one)
	}
	input.pads[0].raw = control_bit('leftx_pos')!
	input.capture_control(0)
	input.pads[0].raw |= control_bit('lefty_neg')!
	input.capture_control(0)
	input.pads[0].raw = control_bit('leftx_neg')! | control_bit('lefty_neg')!
	input.capture_control(0)
	input.pads[0].raw = 0
	input.capture_control(0)
	assert input.config.profile('', 0).expressions[int(jerry.Button.one)] == 'leftx_pos+lefty_neg'
}

fn test_chord_release_does_not_fire_remaining_buttons_or_lose_short_taps() {
	mut input := Input{}
	input.pads[0].profile.expressions[int(jerry.Button.one)] = 'rightshoulder+south'
	input.pads[0].profile.compile()!
	input.pads[0].raw = control_bit('rightshoulder')! | control_bit('south')!
	input.pad_changed(0)
	assert input.combined[0] == bit(.one)
	input.pending.clear()
	input.pads[0].raw = control_bit('south')!
	input.pad_changed(0)
	assert input.combined[0] == 0
	assert input.pending.len == 1
	assert !input.pending[0].pressed && !input.pending[0].immediate
	input.pads[0].raw = 0
	input.pad_changed(0)
	input.pads[0].raw = control_bit('south')!
	input.pad_changed(0)
	assert input.combined[0] == bit(.b)
}

fn test_keypad_shortcut_cannot_take_its_own_confirmation_control() {
	mut p := default_profile()
	p.expressions[21] = 'leftshoulder+south'
	p.compile() or {
		assert err.msg().contains('leave South')
		return
	}
	assert false
}
