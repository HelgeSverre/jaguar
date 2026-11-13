module jaggame

import jagkit

// Timers count frames for the game. A timer is four variables,
// `<name>_left`, `<name>_elapsed`, `<name>_running` and `<name>_fired`,
// that the runtime updates once a frame, before the game's `update`.

struct TimerInfo {
	name    string
	left    Expr
	elapsed Expr
	running Expr
	fired   Expr
}

// Timer is a handle on a timer.
pub struct Timer {
pub:
	name    string
	left    Expr // u16: frames to go; counts down while the timer runs
	elapsed Expr // u16: frames since it started, up to 65535
	running Expr // bool
	fired   Expr // bool: true for the one frame in which a countdown reached 0
}

// timer declares a timer, stopped.
pub fn (mut g Game) timer(name string) Timer {
	left := g.p.u16('${name}_left')
	elapsed := g.p.u16('${name}_elapsed')
	running := g.p.bool('${name}_running')
	fired := g.p.bool('${name}_fired')
	g.timers << TimerInfo{
		name:    name
		left:    left
		elapsed: elapsed
		running: running
		fired:   fired
	}
	return Timer{
		name:    name
		left:    left
		elapsed: elapsed
		running: running
		fired:   fired
	}
}

// start counts `frames` down to 0 (use `seconds` for the number). When it
// gets there the timer stops and `fired` is true for one frame. Starting a
// running timer starts it over.
pub fn (t Timer) start(mut c Code, frames Val) {
	c.set(t.left, frames)
	c.set(t.elapsed, 0)
	c.set(t.fired, false)
	c.set(t.running, true)
}

// stopwatch counts the frames since now in `elapsed`, until it is stopped.
pub fn (t Timer) stopwatch(mut c Code) {
	t.start(mut c, 0)
}

// stop stops the timer; `left` and `elapsed` keep their values.
pub fn (t Timer) stop(mut c Code) {
	c.set(t.running, false)
}

// define_timers writes the function that moves every timer on one frame.
fn (mut g Game) define_timers(f Func) {
	mut c := g.p.define(f)
	for t in g.timers {
		c.set(t.fired, false)

		c.if_(t.running)
		c.if_(t.elapsed.lt(65535))
		c.inc(t.elapsed)
		c.end()

		c.if_(t.left.gt(0))
		c.dec(t.left)
		c.if_(t.left.eq(0))
		c.set(t.fired, true)
		c.set(t.running, false)
		c.end() // reached 0
		c.end() // had frames to go
		c.end() // running
	}
}

// beep plays a short note on the sound chip's sawtooth voice and lets it
// fade out in about 20 frames. `note` is a MIDI note number 0..127 (69 is
// the A at 440 Hz) and `volume` a few thousand.
//
// This is provisional: proper sound, with several voices, effects and music,
// comes in a later slice, and this call will then change or go.
pub fn (mut g Game) beep(mut c Code, note Val, volume Val) {
	g.use_sound()
	c.set(g.beep_step, g.notes.at(lit(note).as_(.u8).and(127)))
	c.set(g.beep_volume, volume)
}

// use_sound declares what a beep needs, once.
fn (mut g Game) use_sound() {
	if g.sounds {
		return
	}
	g.sounds = true
	steps := []i64{len: 128, init: i64(jagkit.note_step(index))}
	g.notes = g.p.table_u32('rt_note_steps', steps)
	g.beep_step = g.p.u32('rt_beep_step')
	g.beep_volume = g.p.u32('rt_beep_volume')
}
