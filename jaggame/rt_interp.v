module jaggame

// Running a game's logic without the machine. The interpreter runs the same
// functions the machine does: `rt_init` once, then `rt_frame` for each frame,
// which counts the frame, moves the timers, calls the game's `update`, moves
// the animations and fades the beep. What it does not do is what the machine
// does around that: reading the real pad, drawing text rows and building
// the display list. So a test can feed it a pad, run frames and compare the
// variables with those of the machine that was given the same buttons.

// interpreter checks the game and starts it in the interpreter, as if on a
// machine of the given standard: the runtime has set up its variables and the
// game's `init` has run. Add all the game's code before calling it; after it,
// the game can no longer be built.
pub fn (mut g Game) interpreter(region Region) !&Interpreter {
	g.define_runtime()
	mut it := g.p.interpreter()!
	it.set_value('rt_pal', if region == .pal { 1 } else { 0 })!
	it.run('rt_init')!
	return it
}

// step runs one frame of the game in the interpreter with a pad: the
// buttons held this frame, built from `button_mask`.
pub fn (g &Game) step(mut it Interpreter, held u32) ! {
	before := it.value('pad')!
	it.set_value('pad_pressed', i64(held & ~u32(before)))!
	it.set_value('pad', i64(held))!
	it.run('rt_frame')!
}
