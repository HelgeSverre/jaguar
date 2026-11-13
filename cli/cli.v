module cli

import os
import flag
import runtime
import time
import machine
import debug

const usage = 'usage: vjag <command> [options]

commands:
  inspect <image>            describe how an image would be loaded
  run <image>                run headlessly for a number of frames
  compat <directory>         boot every image and write a triage report
  bench <image>              measure unthrottled emulation speed
  trace <image>              show the last GPU or DSP instructions before a stop

common options:
  --region ntsc|pal          television standard (default ntsc)
  --format <kind>            force the image kind: cart, jagserver, abs, coff, rom, raw
  --load-address <addr>      load address for raw images
  --entry <addr>             entry point override
  --frames <n>               frames to run
  --jobs <n>                 compat: parallel workers (default: all cores)
  --screenshot <png>         run: save the final frame
  --wav <file>               run: save the generated audio
  --video <ppm>              run: save every frame as a stream of PPM images
  --video-from <n>           run: first frame saved by --video (default 0)
  --dump                     run: print machine state at the end
  --peek <addr[:len]>        run: print memory at the end (repeatable)
  --list <addr[:count]>      run: disassemble 68000 code at the end (repeatable)
  --press <btn@frame[+n]>    run: hold a pad button for n frames (repeatable)
  --watch-io <lo:hi>         run: log writes to TOM/JERRY addresses in lo..hi
  --cpu m68k|gpu|dsp         trace: processor to follow (default dsp)
  --tail <n>                 trace: instructions to print (default 64)
  --stop-pc <addr>           trace: stop when the processor reaches addr
  --stop-range <lo:hi>       trace: stop when the PC enters lo..hi
  --watch <addr[:mask]>      trace: stop when the long at addr changes
  --skip <n>                 trace: instructions before stop conditions apply'

// main_headless runs a headless command and returns the process exit code.
// `args` excludes the executable name.
pub fn main_headless(args []string) int {
	if args.len == 0 || args[0] in ['help', '--help', '-h'] {
		println(usage)
		return if args.len == 0 { 2 } else { 0 }
	}
	run_command(args[0], args[1..]) or {
		eprintln('vjag: ${err.msg()}')
		return 1
	}
	return 0
}

// is_headless_command reports whether `name` is handled by `main_headless`.
pub fn is_headless_command(name string) bool {
	return name in ['inspect', 'run', 'compat', 'bench', 'trace', 'help', '--help', '-h']
}

// parse_image_args parses the image options shared by every command and
// returns the single image path with them.
pub fn parse_image_args(args []string) !(string, ImageOptions) {
	mut parser := flag.new_flag_parser(args)
	options := image_options(mut parser)!
	free := parser.finalize()!
	if free.len != 1 {
		return error('expected exactly one image path')
	}
	return free[0], options
}

fn image_options(mut parser flag.FlagParser) !ImageOptions {
	region := parse_region(parser.string('region', 0, 'ntsc', 'television standard'))!
	format_name := parser.string('format', 0, '', 'image kind')
	load_text := parser.string('load-address', 0, '', 'load address')
	entry_text := parser.string('entry', 0, '', 'entry point')
	return ImageOptions{
		region:    region
		format:    if format_name == '' { none } else { parse_format(format_name)! }
		load_addr: if load_text == '' { none } else { parse_address(load_text)! }
		entry:     if entry_text == '' { none } else { parse_address(entry_text)! }
	}
}

fn run_command(command string, args []string) ! {
	mut parser := flag.new_flag_parser(args)
	options := image_options(mut parser)!
	frames := parser.int('frames', 0, 600, 'frames to run')
	screenshot := parser.string('screenshot', 0, '', 'write the final frame as PNG')
	screenshots := parser.string('screenshots', 0, '', 'directory for sampled frames')
	report := parser.string('report-json', 0, '', 'write the report as JSON')
	jobs := parser.int('jobs', 0, runtime.nr_cpus(), 'parallel workers for compat')
	as_json := parser.bool('json', 0, false, 'machine-readable output')
	dump_state := parser.bool('dump', 0, false,
		'print processor, video and display-list state at the end')
	peeks := parser.string_multi('peek', 0, 'memory range to print')
	listings := parser.string_multi('list', 0, '68000 code range to disassemble')
	presses := parser.string_multi('press', 0, 'hold a pad button: button@frame[+frames]')
	io_range := parser.string('watch-io', 0, '', 'log register writes in lo:hi')
	wav := parser.string('wav', 0, '', 'write the generated audio as WAV')
	video := parser.string('video', 0, '', 'write every frame as a stream of PPM images')
	video_from := parser.int('video-from', 0, 0, 'first frame written by --video')
	processor := parser.string('cpu', 0, 'dsp', 'processor to trace')
	tail := parser.int('tail', 0, 64, 'instructions to print')
	stop_text := parser.string('stop-pc', 0, '', 'stop address')
	range_text := parser.string('stop-range', 0, '', 'stop when the PC enters lo:hi')
	watch_text := parser.string('watch', 0, '', 'stop when the long at addr[:mask] changes')
	skip := parser.int('skip', 0, 0, 'instructions before stop conditions apply')
	free := parser.finalize()!
	if free.len != 1 {
		return error('${command}: expected exactly one path\n\n${usage}')
	}
	match command {
		'inspect' {
			inspect(free[0], options, as_json)!
		}
		'run' {
			run_headless(free[0], options, RunOptions{
				frames:     frames
				screenshot: screenshot
				dump_state: dump_state
				peeks:      peeks
				listings:   listings
				io_range:   io_range
				wav:        wav
				video:      video
				video_from: video_from
				presses:    presses.map(parse_press(it)!)
			})!
		}
		'compat' {
			run_compat(free[0], frames, report, screenshots, if jobs < 1 { 1 } else { jobs })!
		}
		'bench' {
			bench(free[0], options, frames)!
		}
		'trace' {
			mut stop_low := ?u32(none)
			mut stop_high := u32(0)
			if range_text != '' {
				stop_low = parse_address(range_text.all_before(':'))!
				stop_high = parse_address(range_text.all_after(':'))!
			}
			mut watch := ?u32(none)
			mut watch_mask := u32(0xffff_ffff)
			if watch_text != '' {
				watch = parse_address(watch_text.all_before(':'))!
				if watch_text.contains(':') {
					watch_mask = parse_address(watch_text.all_after(':'))!
				}
			}
			trace(free[0], options, TraceOptions{
				processor:  parse_processor(processor)!
				frames:     frames
				tail:       tail
				skip:       u64(skip)
				stop_pc:    if stop_text == '' { none } else { parse_address(stop_text)! }
				stop_low:   stop_low
				stop_high:  stop_high
				watch:      watch
				watch_mask: watch_mask
			})!
		}
		else {
			return error('unknown command "${command}"\n\n${usage}')
		}
	}
}

// inspect prints the load plan of an image without running it.
fn inspect(path string, options ImageOptions, as_json bool) ! {
	session := open_session(path, options)!
	if as_json {
		println(plan_json(session.plan))
	} else {
		println(session.plan.describe())
	}
}

// RunOptions are the outputs requested from a headless run.
struct RunOptions {
	frames     int
	screenshot string   // PNG of the final frame
	wav        string   // generated audio
	video      string   // every frame, as concatenated binary PPM images
	video_from int      // first frame written to `video`
	dump_state bool     // processor, video and display-list state at the end
	peeks      []string // memory ranges `addr[:len]` to print
	listings   []string // 68000 code ranges `addr[:count]` to disassemble
	io_range   string   // `lo:hi` register range whose writes are logged
	presses    []Press  // scripted controller input
}

// run_headless runs an image for a fixed number of frames and produces the
// requested diagnostics.
fn run_headless(path string, options ImageOptions, run RunOptions) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	if run.io_range != '' {
		m.watch_io(parse_address(run.io_range.all_before(':'))!,
			parse_address(run.io_range.all_after(':'))!)
	}
	mut pcm := []i16{len: 8192}
	mut recording := WavWriter{}
	mut film := Film{}
	if run.video != '' {
		os.mkdir_all(os.dir(run.video))!
		film.file = os.create(run.video)!
	}
	defer {
		film.file.close()
	}
	for frame in 0 .. run.frames {
		apply_presses(mut m, run.presses, frame)
		if m.run_frame() == .cpu_halted {
			println('68000 halted: ${m.cpu.str_state()}')
			break
		}
		if run.wav != '' && frame >= run.video_from {
			recording.append(pcm, m.drain_audio(mut pcm), m.audio_rate())
		} else if run.wav != '' {
			m.drain_audio(mut pcm)
		}
		if run.video != '' && frame >= run.video_from {
			film.add(m)!
		}
	}
	if run.wav != '' {
		recording.save(run.wav)!
	}
	print_counters(m)
	if run.dump_state {
		print(debug.processors(m))
		print(debug.m68k_listing(m, m.cpu.pc, 12))
		if m.gpu.running {
			print(debug.registers_risc(m.gpu))
			print(debug.risc_listing(m, .gpu, m.gpu.pc - 24, 28))
		}
		if m.dsp.running {
			print(debug.registers_risc(m.dsp))
			print(debug.risc_listing(m, .dsp, m.dsp.pc - 24, 28))
		}
		print(debug.video_registers(m))
		print(debug.object_list(m, 100))
	}
	for w in m.io_watch.writes {
		println('tick ${w.tick:10} pc=${w.cpu_pc:06x} ${w.addr:06x} <- ${w.value:08x} (${w.bits} bits)')
	}
	for peek in run.peeks {
		addr := parse_address(peek.all_before(':'))!
		length := if peek.contains(':') { parse_address(peek.all_after(':'))! } else { u32(64) }
		print(debug.hex_dump(m, addr, length))
	}
	for listing in run.listings {
		addr := parse_address(listing.all_before(':'))!
		count := if listing.contains(':') { int(parse_address(listing.all_after(':'))!) } else { 24 }
		print(debug.m68k_listing(m, addr, count))
	}
	if run.screenshot != '' {
		os.mkdir_all(os.dir(run.screenshot))!
		write_png(m, run.screenshot)!
	}
}

// bench measures unthrottled speed against the guest's real-time rate.
fn bench(path string, options ImageOptions, frames int) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	allocated_before := gc_heap_usage().total_bytes
	watch := time.new_stopwatch()
	for _ in 0 .. frames {
		m.run_frame()
	}
	host := f64(watch.elapsed().microseconds()) / 1_000_000.0
	allocated := gc_heap_usage().total_bytes - allocated_before
	guest := m.seconds(m.tick)
	print_counters(m)
	println('guest ${guest:.2f}s in host ${host:.2f}s: ${guest / host * 100.0:.0f}% of real time, ${f64(frames) / host:.0f} frames/s')
	println('host heap allocated while running: ${allocated} bytes')
}

fn print_counters(m &machine.Machine) {
	println('profile ${machine.timing_profile}: frames=${m.counters.frames} tick=${m.tick}')
	println('  68000 ${m.counters.cpu_instructions} instr, GPU ${m.gpu.instructions}, DSP ${m.dsp.instructions}')
	println('  OP objects ${m.tom.objects}, blits ${m.tom.blitter.blits} (${m.tom.blitter.pixels} px), audio frames ${m.jerry.samples}, timer events ${m.counters.timer_events}')
}
