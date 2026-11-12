// vjag: the desktop application. Headless commands (inspect, run, compat,
// bench) are shared with vjag_test; anything else is an image to play.
module main

import os
import jerry
import cli
import host.sdl

const usage = 'usage: vjag [image] [--region ntsc|pal] [--format kind] [--load-address addr] [--entry addr]
                    [--exit-after frames] [--capture-window file.bmp]
       vjag <command> ...    headless commands, see `vjag help`

Without an image the window opens empty; drop an image on it to play.

keys: arrows = d-pad   Z X C = C B A   Enter = Pause   Tab = Option
      0-9 - = keypad (- is *, = is #)   P pause   F5 reset   F11 fullscreen
      M mute   F1 status overlay   F12 screenshot   ` fast-forward   Esc quit'

fn main() {
	args := os.args[1..]
	if args.len > 0 && args[0] in ['--help', '-h'] {
		println(usage)
		return
	}
	if args.len > 0 && cli.is_headless_command(args[0]) {
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
	exit_after  int    // stop after this many frames; 0 runs until closed
	capture     string // BMP of the window's last frame before `exit_after`
	frames      int
	notice      string // why the last image could not be opened
	fresh       [2]u32 // buttons pressed in the current batch of host events
	deferred    [2]u32 // releases held back so a short tap lasts one frame
}

fn play(args []string) ! {
	// Two options only the windowed app takes: stop after a number of
	// frames, and save the window's rendering of the last one. Together they
	// let a script check the presentation path.
	mut rest := []string{}
	mut exit_after := 0
	mut capture := ''
	mut i := 0
	for i < args.len {
		match args[i] {
			'--exit-after' {
				exit_after = args[i + 1] or { '' }.int()
				i += 2
			}
			'--capture-window' {
				capture = args[i + 1] or { '' }
				i += 2
			}
			else {
				rest << args[i]
				i++
			}
		}
	}
	// Without an image the window opens empty and waits for a dropped file.
	mut session := cli.Session{}
	mut options := cli.ImageOptions{}
	if rest.len > 0 {
		path, parsed := cli.parse_image_args(rest)!
		options = parsed
		session = cli.open_session(path, options)!
		cli.load_save(mut session) or { eprintln('vjag: save not loaded: ${err.msg()}') }
	}
	sdl.init()!
	defer {
		sdl.quit()
	}
	mut app := App{
		session:    session
		options:    options
		video:      sdl.new_video('vjag', 960, 720)!
		audio:      sdl.new_audio()!
		exit_after: exit_after
		capture:    capture
	}
	if session.loaded() {
		app.video.set_title('vjag - ${os.file_name(session.path)}')
	}
	app.run()
	app.flush_save()
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
		if !app.session.loaded() {
			app.idle()
			deadline = sdl.ticks_ns()
			window_start = deadline
			continue
		}
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
		app.frames++
		if app.exit_after > 0 && app.frames >= app.exit_after {
			app.running = false
			if app.capture != '' {
				app.video.capture_next_frame(app.capture)
			}
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
			app.flush_save()
		}
	}
}

// idle shows the empty window: what to do, and why the last drop failed.
fn (mut app App) idle() {
	mut lines := ['Drop a Jaguar image here', '.j64  .jag  .rom  .abs  .cof  .bin', '', 'Esc quits']
	if app.notice != '' {
		lines << ['', app.notice]
	}
	app.video.present_message(lines) or {
		eprintln('vjag: ${err.msg()}')
		app.running = false
	}
	app.frames++
	if app.exit_after > 0 && app.frames >= app.exit_after {
		app.running = false
	}
	if app.capture != '' && app.exit_after > 0 && app.frames == app.exit_after - 1 {
		app.video.capture_next_frame(app.capture)
	}
	sdl.sleep_ns(16_000_000)
}

// flush_save persists the cartridge EEPROM of the running image, if any.
fn (mut app App) flush_save() {
	if app.session.loaded() {
		cli.flush_save(mut app.session) or { eprintln('vjag: save not written: ${err.msg()}') }
	}
}

// handle_events applies every pending host event. A key tapped faster than
// one frame delivers its press and release together; the release then waits
// for the next frame so the guest still sees the button down once.
fn (mut app App) handle_events() {
	for port in 0 .. 2 {
		for button in 0 .. 32 {
			if app.deferred[port] & (u32(1) << button) != 0 {
				app.session.machine.set_button(port, unsafe { jerry.Button(button) }, false)
			}
		}
		app.deferred[port] = 0
		app.fresh[port] = 0
	}
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
				if !app.session.loaded() {
					continue
				}
				bit := u32(1) << u32(event.button)
				if event.pressed {
					app.fresh[event.port] |= bit
					app.deferred[event.port] &= ~bit
				} else if app.fresh[event.port] & bit != 0 {
					app.deferred[event.port] |= bit
					continue
				}
				app.session.machine.set_button(event.port, event.button, event.pressed)
			}
			.focus_lost {
				if app.session.loaded() {
					app.session.machine.jerry.pads.release_all()
				}
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
			if app.session.loaded() {
				app.load(app.session.path)
			}
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
			if !app.session.loaded() {
				return
			}
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
		app.notice = '${os.file_name(path)}: ${err.msg()}'
		return
	}
	app.flush_save()
	cli.load_save(mut session) or { eprintln('vjag: save not loaded: ${err.msg()}') }
	app.session = session
	app.notice = ''
	app.paused = false
	app.fresh = [2]u32{}
	app.deferred = [2]u32{}
	app.audio.clear()
	app.video.set_title('vjag - ${os.file_name(path)}')
}

fn (app &App) overlay_lines() []string {
	if !app.overlay || !app.session.loaded() {
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
