module cli

import os
import flag
import time
import machine
import debug

const usage = 'usage: vjag <command> [options]

commands:
  inspect <image>            describe how an image would be loaded
  run <image>                run headlessly for a number of frames
  compat <directory>         boot every image and write a triage report
  bench <image>              measure unthrottled emulation speed

common options:
  --region ntsc|pal          television standard (default ntsc)
  --format <kind>            force the image kind: cart, jagserver, abs, coff, rom, raw
  --load-address <addr>      load address for raw images
  --entry <addr>             entry point override
  --frames <n>               frames to run
  --screenshot <png>         run: save the final frame
  --dump                     run: print machine state at the end'

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
	return name in ['inspect', 'run', 'compat', 'bench', 'help', '--help', '-h']
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
	as_json := parser.bool('json', 0, false, 'machine-readable output')
	dump_state := parser.bool('dump', 0, false,
		'print processor, video and display-list state at the end')
	free := parser.finalize()!
	if free.len != 1 {
		return error('${command}: expected exactly one path\n\n${usage}')
	}
	match command {
		'inspect' { inspect(free[0], options, as_json)! }
		'run' { run_headless(free[0], options, frames, screenshot, dump_state)! }
		'compat' { run_compat(free[0], frames, report, screenshots)! }
		'bench' { bench(free[0], options, frames)! }
		else { return error('unknown command "${command}"\n\n${usage}') }
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

// run_headless runs an image for a fixed number of frames.
fn run_headless(path string, options ImageOptions, frames int, screenshot string, dump_state bool) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	for _ in 0 .. frames {
		if m.run_frame() == .cpu_halted {
			println('68000 halted: ${m.cpu.str_state()}')
			break
		}
	}
	print_counters(m)
	if dump_state {
		print(debug.processors(m))
		print(debug.video_registers(m))
		print(debug.object_list(m, 100))
	}
	if screenshot != '' {
		os.mkdir_all(os.dir(screenshot))!
		write_png(m, screenshot)!
	}
}

// bench measures unthrottled speed against the guest's real-time rate.
fn bench(path string, options ImageOptions, frames int) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	watch := time.new_stopwatch()
	for _ in 0 .. frames {
		m.run_frame()
	}
	host := f64(watch.elapsed().microseconds()) / 1_000_000.0
	guest := m.seconds(m.tick)
	print_counters(m)
	println('guest ${guest:.2f}s in host ${host:.2f}s: ${guest / host * 100.0:.0f}% of real time, ${f64(frames) / host:.0f} frames/s')
}

fn print_counters(m &machine.Machine) {
	println('profile ${machine.timing_profile}: frames=${m.counters.frames} tick=${m.tick}')
	println('  68000 ${m.counters.cpu_instructions} instr, GPU ${m.gpu.instructions}, DSP ${m.dsp.instructions}')
	println('  OP objects ${m.tom.objects}, blits ${m.tom.blitter.blits} (${m.tom.blitter.pixels} px), audio frames ${m.jerry.samples}, timer events ${m.counters.timer_events}')
}
