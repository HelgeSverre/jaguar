// vjag: the desktop application. Headless commands (inspect, run, compat,
// bench) are shared with vjag_test; anything else is an image to play.
module main

import os
import math
import jerry
import cli
import host.sdl

const usage = 'usage: vjag [image] [--region ntsc|pal] [--format kind] [--load-address addr] [--entry addr]
                    [--shell | --no-shell] [--exit-after frames] [--capture-window file.bmp]
                    [--press button@frame[+frames]]...
       vjag <command> ...    headless commands, see `vjag help`

Without an image the window opens empty; drop an image on it to play.

keys: arrows = d-pad   Z X C = C B A   Enter = Pause   Tab = Option
      0-9 = keypad   Q or - = *   W or = is #
      P pause   R or F5 reset   F or F11 fullscreen   M mute   Esc quit
      I or F1 status overlay   S or F12 screenshot   Space or ` fast-forward (hold)
      H or F2 console shell on/off   , . or [ ] shell size'

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
	settings    Settings
	presses     []cli.Press // scripted pad input, by guest frame
	guest_frame int
	glow        f32    // how brightly the shell's eyes burn, 0..1
	fresh       [2]u32 // buttons pressed in the current batch of host events
	deferred    [2]u32 // releases held back so a short tap lasts one frame
}

fn play(args []string) ! {
	// Options only the windowed app takes: the shell for this run, and three
	// that let a script check the presentation path: scripted pad input,
	// stopping after a number of frames, and saving the window's rendering
	// of the last one.
	mut settings := load_settings(settings_path())
	mut rest := []string{}
	mut exit_after := 0
	mut capture := ''
	mut presses := []cli.Press{}
	mut i := 0
	for i < args.len {
		match args[i] {
			'--exit-after' {
				exit_after = args[i + 1] or { '' }.int()
				i += 2
			}
			'--shell' {
				settings.shell = true
				i++
			}
			'--no-shell' {
				settings.shell = false
				i++
			}
			'--press' {
				presses << cli.parse_press(args[i + 1] or { '' })!
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
		audio:      sdl.new_audio()!
		exit_after: exit_after
		capture:    capture
		settings:   settings
		presses:    presses
	}
	app.open_window()!
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
		if app.session.loaded() && !app.paused {
			mut m := app.session.machine
			cli.apply_presses(mut m, app.presses, app.guest_frame)
			app.guest_frame++
			before := m.tick
			m.run_frame()
			elapsed := m.tick - before
			window_guest += elapsed
			frames := m.drain_audio(mut pcm)
			if !app.fast {
				app.audio.push(pcm, frames, m.audio_rate())
			}
			app.follow_sound(pcm, frames)
			deadline += u64(m.seconds(elapsed) * 1_000_000_000.0)
		} else {
			// Nothing to emulate: idle at display rate with the eyes breathing.
			sdl.sleep_ns(16_000_000)
			deadline = sdl.ticks_ns()
			app.glow = f32(0.2 + 0.15 * math.sin(f64(deadline) / 600_000_000.0))
		}
		app.frames++
		if app.exit_after > 0 && app.frames >= app.exit_after {
			app.running = false
			if app.capture != '' {
				app.video.capture_next_frame(app.capture)
			}
		}
		app.video.present(app.scene()) or {
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
			if app.session.loaded() {
				app.speed = app.session.machine.seconds(window_guest) * 1_000_000_000.0 / f64(now - window_start)
			}
			window_start = now
			window_guest = 0
			app.flush_save()
		}
	}
}

// open_window creates the window the settings ask for: dressed as a
// console, or plain and resizable.
fn (mut app App) open_window() ! {
	if app.settings.shell {
		app.video = sdl.new_shell_video('vjag', app.settings.shell_scale)!
	} else {
		app.video = sdl.new_video('vjag', 960, 720)!
	}
	app.input.shell = app.video.shell()
	if app.session.loaded() {
		app.video.set_title('vjag - ${os.file_name(app.session.path)}')
	}
}

// toggle_shell swaps the window for the other kind and remembers the
// choice. The new window opens before the old one closes, so a failure
// leaves the old one in place.
fn (mut app App) toggle_shell() {
	mut old := app.video
	app.settings.shell = !app.settings.shell
	app.open_window() or {
		eprintln('vjag: ${err.msg()}')
		app.settings.shell = !app.settings.shell
		return
	}
	old.close()
	app.save_settings()
}

// resize_shell steps the shell's size and remembers it.
fn (mut app App) resize_shell(step f32) {
	if !app.settings.shell {
		return
	}
	app.settings.shell_scale = clamp_scale(app.settings.shell_scale + step)
	app.video.set_shell_scale(app.settings.shell_scale)
	app.save_settings()
}

fn (app &App) save_settings() {
	app.settings.save(settings_path()) or { eprintln('vjag: settings not saved: ${err.msg()}') }
}

// follow_sound makes the eyes flare with the loudest sample of the frame
// and fade between hits.
fn (mut app App) follow_sound(pcm []i16, frames int) {
	mut peak := 0
	for sample in pcm[..frames * 2] {
		level := if sample < 0 { -int(sample) } else { int(sample) }
		if level > peak {
			peak = level
		}
	}
	level := if app.audio.muted { f32(0) } else { f32(peak) / 16384.0 }
	app.glow = if level > app.glow { level } else { app.glow * 0.9 }
	if app.glow > 1 {
		app.glow = 1
	}
}

// scene describes what the window shows this frame.
fn (app &App) scene() sdl.Scene {
	if !app.session.loaded() {
		mut message := ['Drop a Jaguar image here', 'j64 jag rom abs cof bin']
		if app.notice != '' {
			message << ['', app.notice]
		}
		return sdl.Scene{
			message: message
			readout: app.readout()
			glow:    app.glow
		}
	}
	pixels, info := app.session.machine.frame()
	return sdl.Scene{
		pixels:  pixels
		info:    info
		overlay: app.overlay_lines()
		readout: app.readout()
		glow:    app.glow
	}
}

// readout is the text on the shell's status strip: the control under the
// pointer, else what the machine is doing.
fn (app &App) readout() string {
	shell := app.video.shell()
	if shell == unsafe { nil } {
		return ''
	}
	if shell.hover.kind != .none {
		return shell.hover.label()
	}
	if !app.session.loaded() {
		return if app.notice != '' { 'CANNOT LOAD' } else { 'NO CARTRIDGE' }
	}
	if app.paused {
		return 'PAUSED'
	}
	// The title is the file name without its extension and dump tags.
	name := os.file_name(app.session.path).all_before_last('.')
	mut text := printable(name.all_before(' (').all_before(' [')).to_upper()
	if app.audio.muted {
		text += '  [MUTED]'
	}
	if app.fast {
		text += '  >>'
	}
	return text
}

// printable keeps the characters the readout's 7-bit font can draw.
fn printable(text string) string {
	mut out := []u8{cap: text.len}
	for ch in text {
		out << if ch >= 0x20 && ch < 0x7f { ch } else { `?` }
	}
	return out.bytestr()
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
		.shell {
			if pressed {
				app.toggle_shell()
			}
		}
		.shrink {
			app.resize_shell(-shell_scale_step)
		}
		.grow {
			app.resize_shell(shell_scale_step)
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
