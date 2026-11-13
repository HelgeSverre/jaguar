// Package emulated runs images in the emulator, for tests: it boots an
// image, runs frames until the program says it is done and hands back the
// machine's memory. It knows nothing of jaggame, so that jaggame's own
// tests can use it.
module emulated

import loader
import machine

// Runner boots images, one after another, in one emulated machine.
pub struct Runner {
mut:
	m &machine.Machine
}

// new makes a runner with an NTSC machine.
pub fn new() Runner {
	return Runner{
		m: machine.new(machine.Config{})
	}
}

// run boots an image and runs frames until the byte at `done` is not 0. It
// returns the number of frames that took, or an error after `max_frames`.
pub fn (mut r Runner) run(image []u8, done u32, max_frames int) !int {
	plan := loader.plan(image, loader.Options{})!
	r.m.load_direct(plan)
	for frame in 1 .. max_frames + 1 {
		r.m.run_frame()
		if r.m.ram[done] != 0 {
			return frame
		}
	}
	return error('the program did not finish in ${max_frames} frames (pc ${r.m.cpu.pc:08x})')
}

// ram is the machine's main memory.
pub fn (r &Runner) ram() []u8 {
	return r.m.ram
}
