module main

import jagkit

// The DSP plays three voices: a square wave for kick and bass, a sawtooth
// lead and noise for the hi-hat. The 68000 is the musician: once a frame
// it sets their pitches and lets their volumes decay.

const kick_volume = 9000
const bass_volume = 5500
const lead_volume = 5000
const hat_volume = 3500
const zap_volume = 9000

// The tune is psytrance: 150 beats a minute, a kick on every beat, three
// bass notes rolling behind it, a hi-hat between the beats and an acid
// line on top. A step is a sixteenth note, six frames long.
const song_steps = 256
const step_frames = 6
const root_note = 40 // E

// The bass moves every four bars.
const bass_roots = [0, 0, 3, 1]

// Two acid riffs in E Phrygian, as semitones above the root; -1 is a rest.
const riffs = [
	[0, -1, 12, 0, 3, -1, 0, 7, 0, -1, 12, 1, 0, 5, -1, 3],
	[12, 0, 13, 0, 12, 0, 15, 12, -1, 7, 8, 7, 5, 3, 1, 0],
]

// kick_sweep is the pitch of the kick drum on its first frames: a thump
// is a tone falling fast.
fn kick_sweep() []u32 {
	return [jagkit.hertz_step(190), jagkit.hertz_step(110), jagkit.hertz_step(70),
		jagkit.hertz_step(52)]
}

// bass_line has a note for every step; the steps the kick lands on are
// not used. The last step of every other bar jumps an octave.
fn bass_line() []u32 {
	mut line := []u32{cap: song_steps}
	for step in 0 .. song_steps {
		root := root_note + bass_roots[(step / 64) % bass_roots.len]
		lift := if step % 32 == 31 { 12 } else { 0 }
		line << jagkit.note_step(root + lift)
	}
	return line
}

// lead_line plays a riff a bar: four bars of rest to let the bass in, then
// the first riff, then the second an octave up, then both in turn.
fn lead_line() []u32 {
	mut line := []u32{cap: song_steps}
	for step in 0 .. song_steps {
		bar := step / 16
		if bar < 4 {
			line << 0
			continue
		}
		riff := if bar < 8 {
			0
		} else if bar < 12 {
			1
		} else {
			bar % 2
		}
		interval := riffs[riff][step % 16]
		if interval < 0 {
			line << 0
			continue
		}
		root := root_note + bass_roots[(step / 64) % bass_roots.len]
		lift := if bar >= 12 { 12 } else { 0 }
		line << jagkit.note_step(root + 24 + interval + lift)
	}
	return line
}
