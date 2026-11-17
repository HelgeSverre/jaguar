module main

import cli
import host.sdl
import jerry
import machine

fn queue_key(scancode int, down bool) {
	key := C.SDL_KeyboardEvent{
		type:     if down { u32(C.SDL_EVENT_KEY_DOWN) } else { u32(C.SDL_EVENT_KEY_UP) }
		scancode: scancode
		down:     down
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&key) })
}

fn test_fast_taps_survive_one_guest_frame_and_controls_clear_pending_taps() {
	assert C.SDL_Init(u32(C.SDL_INIT_EVENTS))
	defer { C.SDL_Quit() }
	mut app := App{
		session: cli.Session{
			machine: machine.new(machine.Config{})
		}
		input:   sdl.Input{}
	}
	app.handle_events()
	queue_key(int(C.SDL_SCANCODE_X), true)
	queue_key(int(C.SDL_SCANCODE_X), false)
	app.handle_events()
	assert app.session.machine.jerry.pads.buttons[0] == u32(1) << u32(jerry.Button.b)
	assert app.deferred[0] != 0
	app.handle_events()
	assert app.session.machine.jerry.pads.buttons[0] == 0
	queue_key(int(C.SDL_SCANCODE_X), true)
	queue_key(int(C.SDL_SCANCODE_X), false)
	queue_key(int(C.SDL_SCANCODE_K), true)
	app.handle_events()
	assert app.input.controls_open()
	assert app.session.machine.jerry.pads.buttons[0] == 0
	assert app.deferred[0] == 0
	queue_key(int(C.SDL_SCANCODE_K), true)
	app.handle_events()
	assert !app.input.controls_open()
	queue_key(int(C.SDL_SCANCODE_SPACE), true)
	queue_key(int(C.SDL_SCANCODE_K), true)
	queue_key(int(C.SDL_SCANCODE_SPACE), false)
	queue_key(int(C.SDL_SCANCODE_K), true)
	app.handle_events()
	assert !app.input.controls_open()
	assert !app.fast, 'releasing Space inside a short-lived menu must stop fast-forward'
}

fn test_replay_owns_buttons_across_live_input_focus_loss_and_controls() {
	assert C.SDL_Init(u32(C.SDL_INIT_EVENTS))
	defer { C.SDL_Quit() }
	mut app := App{
		session:     cli.Session{
			machine: machine.new(machine.Config{})
		}
		input:       sdl.Input{}
		replay:      true
		presses:     [cli.parse_press('b@0+10')!]
		guest_frame: 1
	}
	app.session.machine.set_button(0, .b, true)
	queue_key(int(C.SDL_SCANCODE_C), true)
	app.handle_events()
	assert app.session.machine.jerry.pads.buttons[0] == u32(1) << u32(jerry.Button.b)
	loss := C.SDL_WindowEvent{
		type: u32(C.SDL_EVENT_WINDOW_FOCUS_LOST)
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&loss) })
	app.handle_events()
	assert app.session.machine.jerry.pads.buttons[0] == u32(1) << u32(jerry.Button.b)
	gain := C.SDL_WindowEvent{
		type: u32(C.SDL_EVENT_WINDOW_FOCUS_GAINED)
	}
	assert C.SDL_PushEvent(unsafe { &C.SDL_Event(&gain) })
	queue_key(int(C.SDL_SCANCODE_K), true)
	app.handle_events()
	assert app.input.controls_open()
	assert app.session.machine.jerry.pads.buttons[0] == u32(1) << u32(jerry.Button.b)
}
