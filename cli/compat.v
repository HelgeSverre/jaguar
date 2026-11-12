module cli

import os
import json
import time
import jerry
import machine

// Verdict is the automated triage of one image. It measures activity, not
// correctness: a human still has to look at the pictures.
pub enum Verdict {
	load_error     // the loader refused the image
	halted         // the 68000 double-faulted
	blank          // every sampled frame was a single colour
	static_picture // a picture appeared and never changed
	animated       // the picture changed between samples
}

// CompatResult is one row of the compatibility report.
pub struct CompatResult {
pub:
	name             string
	kind             string
	verdict          string
	detail           string
	frames           u64
	cpu_instructions u64
	gpu_instructions u64
	dsp_instructions u64
	blits            u64
	objects          u64
	audio_frames     u64
	colours          int
	lit              f64
	distinct_frames  int
	seconds          f64
}

// CompatReport is the whole sweep.
pub struct CompatReport {
pub:
	timing_profile string
	frames         int
	results        []CompatResult
}

// compat_sample_frames are the frame numbers at which a picture is sampled.
const compat_samples = 6

// press_script holds the controller down at a fixed cadence so that titles
// waiting for a button move on. The same script runs for every image.
fn press_script(mut m machine.Machine, frame int) {
	if frame < 150 {
		return
	}
	phase := frame % 90
	m.set_button(0, jerry.Button.b, phase < 6)
	m.set_button(0, jerry.Button.a, phase >= 30 && phase < 36)
	m.set_button(0, jerry.Button.c, phase >= 60 && phase < 66)
}

// run_compat_image boots one image headlessly and triages it.
pub fn run_compat_image(path string, frames int, screenshot_dir string) CompatResult {
	name := os.file_name(path)
	started := time.now()
	mut session := open_session(path, ImageOptions{}) or {
		return CompatResult{
			name:    name
			verdict: Verdict.load_error.str()
			detail:  err.msg()
		}
	}
	mut m := session.machine
	mut checksums := map[u64]bool{}
	mut last := FrameStats{}
	mut best := FrameStats{}
	mut halted := false
	interval := if frames >= compat_samples { frames / compat_samples } else { 1 }
	for frame in 1 .. frames + 1 {
		press_script(mut m, frame)
		if m.run_frame() == .cpu_halted {
			halted = true
			break
		}
		if frame % interval == 0 {
			last = frame_stats(m)
			checksums[last.checksum] = true
			if last.colours >= best.colours {
				best = last
			}
			if screenshot_dir != '' {
				stem := name.all_before_last('.')
				write_png(m, os.join_path(screenshot_dir, '${stem}.${frame:05}.png')) or {}
			}
		}
	}
	verdict := if halted {
		Verdict.halted
	} else if best.colours <= 1 {
		Verdict.blank
	} else if checksums.len <= 1 {
		Verdict.static_picture
	} else {
		Verdict.animated
	}
	return CompatResult{
		name:             name
		kind:             '${session.plan.kind} ${session.plan.variant}'.trim_space()
		verdict:          verdict.str()
		detail:           if halted { m.cpu.str_state() } else { '' }
		frames:           m.counters.frames
		cpu_instructions: m.counters.cpu_instructions
		gpu_instructions: m.gpu.instructions
		dsp_instructions: m.dsp.instructions
		blits:            m.tom.blitter.blits
		objects:          m.tom.objects
		audio_frames:     m.jerry.samples
		colours:          best.colours
		lit:              best.lit
		distinct_frames:  checksums.len
		seconds:          f64(time.since(started).milliseconds()) / 1000.0
	}
}

// run_compat sweeps a directory of images and writes the report.
pub fn run_compat(dir string, frames int, report_path string, screenshot_dir string) ! {
	mut paths := os.ls(dir)!.filter(os.is_file(os.join_path(dir, it)) && !it.starts_with('.'))
	paths.sort()
	if screenshot_dir != '' {
		os.mkdir_all(screenshot_dir)!
	}
	mut results := []CompatResult{}
	mut tally := map[string]int{}
	for name in paths {
		result := run_compat_image(os.join_path(dir, name), frames, screenshot_dir)
		tally[result.verdict]++
		println('${result.verdict:-15} ${result.seconds:6.1f}s colours=${result.colours:-5} frames=${result.distinct_frames} gpu=${result.gpu_instructions} dsp=${result.dsp_instructions} blits=${result.blits}  ${name}')
		results << result
	}
	println('')
	for verdict, count in tally {
		println('${verdict:-15} ${count}')
	}
	if report_path != '' {
		os.mkdir_all(os.dir(report_path))!
		report := CompatReport{
			timing_profile: machine.timing_profile
			frames:         frames
			results:        results
		}
		os.write_file(report_path, json.encode_pretty(report))!
	}
}
