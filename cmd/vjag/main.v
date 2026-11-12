// vjag: the desktop application. Headless commands (inspect, run, compat,
// bench) are shared with vjag_test; anything else is an image to play.
module main

import os
import cli
import host.sdl

const usage = 'usage: vjag <image> [--region ntsc|pal] [--format kind] [--load-address addr] [--entry addr]
       vjag <command> ...    headless commands, see `vjag help`

keys: arrows = d-pad   Z X C = C B A   Enter = Pause   Tab = Option
      0-9 - = keypad (- is *, = is #)   P pause   F5 reset   F11 fullscreen
      M mute   F1 status overlay   F12 screenshot   ` fast-forward   Esc quit'

fn main() {
	args := os.args[1..]
	if args.len == 0 {
		println(usage)
		exit(2)
	}
	if cli.is_headless_command(args[0]) {
		exit(cli.main_headless(args))
	}
	play(args) or {
		eprintln('vjag: ${err.msg()}')
		exit(1)
	}
}

// App is the state of an interactive session.
struct App {
mut:
	session     cli.Session
	options     cli.ImageOptions
	video       sdl.Video
	audio       sdl.Audio
	input       sdl.Input
	paused      bool
	fast        bool
	overlay     bool
	running     bool = true
	speed       f64  = 1.0 // measured guest time over host time
	screenshots int
}

fn play(args []string) ! {
	path, options := cli.parse_image_args(args)!
	mut session := cli.open_session(path, options)!
	cli.load_save(mut session) or { eprintln('vjag: save not loaded: ${err.msg()}') }
	sdl.init()!
	defer {
		sdl.quit()
	}
	mut app := App{
		session: session
		options: options
		video:   sdl.new_video('vjag', 960, 720)!
		audio:   sdl.new_audio()!
	}
	app.video.set_title('vjag - ${os.file_name(path)}')
	app.run()
	cli.flush_save(mut app.session) or { eprintln('vjag: save not written: ${err.msg()}') }
	app.input.close()
	app.audio.close()
	app.video.close()
}

// run is the main loop: host events, one guest frame, presentation, pacing.
// Pacing follows guest time, so the guest clock ratios never depend on the
// host; only how often the loop sleeps does.
fn (mut app App) run() {
	mut pcm := []i16{len: 8192}
	mut deadline := sdl.ticks_ns()
	mut window_start := deadline
	mut window_guest := u64(0)
	for app.running {
		app.handle_events()
		mut m := app.session.machine
		if app.paused {
			sdl.sleep_ns(16_000_000)
			deadline = sdl.ticks_ns()
		} else {
			before := m.tick
			m.run_frame()
			elapsed := m.tick - before
			window_guest += elapsed
			frames := m.drain_audio(mut pcm)
			if !app.fast {
				app.audio.push(pcm, frames, m.audio_rate())
			}
			deadline += u64(m.seconds(elapsed) * 1_000_000_000.0)
		}
		pixels, info := m.frame()
		app.video.present(pixels, info, app.overlay_lines()) or {
			eprintln('vjag: ${err.msg()}')
			app.running = false
		}
		now := sdl.ticks_ns()
		if app.fast || deadline + 100_000_000 < now {
			// Fast-forwarding, or too far behind to catch up: resynchronise.
			deadline = now
		} else if deadline > now {
			sdl.sleep_ns(deadline - now)
		}
		if now - window_start >= 1_000_000_000 {
			app.speed = app.session.machine.seconds(window_guest) * 1_000_000_000.0 / f64(now - window_start)
			window_start = now
			window_guest = 0
			cli.flush_save(mut app.session) or {}
		}
	}
}

fn (mut app App) handle_events() {
	for {
		event := app.input.poll()
		match event.kind {
			.none {
				return
			}
			.quit {
				app.running = false
			}
			.button {
				app.session.machine.set_button(event.port, event.button, event.pressed)
			}
			.focus_lost {
				app.session.machine.jerry.pads.release_all()
			}
			.drop_file {
				app.load(event.path)
			}
			.command {
				app.command(event.command, event.pressed)
			}
		}
	}
}

fn (mut app App) command(command sdl.Command, pressed bool) {
	match command {
		.quit {
			app.running = false
		}
		.pause {
			app.paused = !app.paused
			app.audio.clear()
		}
		.reset {
			app.load(app.session.path)
		}
		.fullscreen {
			app.video.toggle_fullscreen()
		}
		.mute {
			app.audio.muted = !app.audio.muted
			app.audio.clear()
		}
		.overlay {
			app.overlay = !app.overlay
		}
		.fast_forward {
			app.fast = pressed
			app.audio.clear()
		}
		.screenshot {
			app.screenshots++
			name := 'vjag-${app.screenshots:03}.png'
			cli.write_png(app.session.machine, name) or { eprintln('vjag: ${err.msg()}') }
		}
		.none {}
	}
}

// load replaces the running session. A failed load keeps the current one.
fn (mut app App) load(path string) {
	mut session := cli.open_session(path, app.options) or {
		eprintln('vjag: ${err.msg()}')
		return
	}
	cli.flush_save(mut app.session) or { eprintln('vjag: save not written: ${err.msg()}') }
	cli.load_save(mut session) or { eprintln('vjag: save not loaded: ${err.msg()}') }
	app.session = session
	app.audio.clear()
	app.video.set_title('vjag - ${os.file_name(path)}')
}

fn (app &App) overlay_lines() []string {
	if !app.overlay {
		return []
	}
	m := app.session.machine
	_, info := m.frame()
	return [
		'${m.config.region} direct boot  ${info.width}x${info.height}  speed ${app.speed * 100.0:.0f}%',
		'audio ${m.audio_rate():.0f} Hz  queued ${app.audio.queued_ms()} ms  dropped ${app.audio.overruns}',
		'68000 ${m.cpu.pc:06x}  GPU ${if m.gpu.running {
			'run'
		} else {
			'off'
		}}  DSP ${if m.dsp.running {
			'run'
		} else {
			'off'
		}}',
		'blits ${m.tom.blitter.blits}  objects ${m.tom.objects}',
	]
}
