module main

import math
import jagkit

// The DSP plays three voices: a square wave for kick and bass, a sawtooth
// lead and noise for the hi-hat. The 68000 is the musician: once a frame
// it sets their pitches and lets their volumes decay.

// Offsets of the voice settings from the `voices` label of the DSP program.
const voice_bass_step = 4 // added to the phase every sample
const voice_bass_volume = 8
const voice_lead_step = 12
const voice_lead_volume = 16
const voice_noise_volume = 20

const sclk_value = 19 // about 20.8 kHz
const kick_volume = 9000
const bass_volume = 5500
const lead_volume = 5000
const hat_volume = 3500
const zap_volume = 9000

// synthesizer is the DSP program: start-up code and the sample interrupt.
fn synthesizer() &jagkit.Risc {
	stack := jagkit.Reg.r31
	flags_address := jagkit.Reg.r30
	flags := jagkit.Reg.r29
	scratch := jagkit.Reg.r28
	voices := jagkit.Reg.r14
	left_dac := jagkit.Reg.r20
	right_dac := jagkit.Reg.r21
	bass_phase := jagkit.Reg.r10
	lead_phase := jagkit.Reg.r11
	noise := jagkit.Reg.r12
	mix := jagkit.Reg.r1
	a := jagkit.Reg.r0
	b := jagkit.Reg.r2
	c := jagkit.Reg.r3

	mut s := jagkit.new_risc(jagkit.dsp_ram)
	// The interrupt vectors are 16 bytes apart; only the sample interrupt
	// is used.
	s.pad_to(jagkit.dsp_i2s_vector)
	s.movei_label('sample', scratch)
	s.jump(.always, scratch)
	s.nop()
	s.pad_to(jagkit.dsp_ram + 0x60)

	s.label('start')
	s.movei(jagkit.dsp_ram + jagkit.dsp_ram_size, stack)
	s.movei(jagkit.d_flags, flags_address)
	s.movei_label('voices', voices)
	s.movei(jagkit.l_dac, left_dac)
	s.movei(jagkit.r_dac, right_dac)
	s.moveq(0, bass_phase)
	s.moveq(0, lead_phase)
	s.movei(0x2545f491, noise)
	s.movei(jagkit.sclk, a)
	s.moveq(sclk_value, b)
	s.store(b, a)
	s.movei(jagkit.smode, a)
	s.moveq(jagkit.smode_internal, b)
	s.store(b, a)
	s.load(flags_address, a)
	s.bset(jagkit.dsp_flag_i2s_enable, a)
	s.store(a, flags_address)
	s.label('idle')
	s.jr(.always, 'idle')
	s.nop()

	// The DSP enters with the vector's address in r30, so the handler has
	// to point it at the flags again.
	s.label('sample')
	s.movei(jagkit.d_flags, flags_address)
	s.load(flags_address, flags)
	// Bass: +volume while the phase is positive, -volume while negative.
	s.load_r14(voice_bass_step, a)
	s.add(a, bass_phase)
	s.load_r14(voice_bass_volume, mix)
	s.move(bass_phase, b)
	s.sharq(31, b)
	s.xor(b, mix)
	s.sub(b, mix)
	// Lead: the top of the phase is the sawtooth itself.
	s.load_r14(voice_lead_step, a)
	s.add(a, lead_phase)
	s.load_r14(voice_lead_volume, c)
	s.move(lead_phase, b)
	s.sharq(16, b)
	s.imult(c, b)
	s.sharq(15, b)
	s.add(b, mix)
	// Noise: a xorshift generator, used like the bass phase.
	s.move(noise, b)
	s.shlq(13, b)
	s.xor(b, noise)
	s.move(noise, b)
	s.shrq(17, b)
	s.xor(b, noise)
	s.move(noise, b)
	s.shlq(5, b)
	s.xor(b, noise)
	s.load_r14(voice_noise_volume, c)
	s.move(noise, b)
	s.sharq(31, b)
	s.xor(b, c)
	s.sub(b, c)
	s.add(c, mix)
	s.store(mix, left_dac)
	s.store(mix, right_dac)
	// Leave the interrupt: unmask, acknowledge, return past the
	// interrupted instruction.
	s.bclr(jagkit.flag_imask, flags)
	s.bset(jagkit.dsp_flag_i2s_clear, flags)
	s.load(stack, scratch)
	s.addq(2, scratch)
	s.addq(4, stack)
	s.jump(.always, scratch)
	s.store(flags, flags_address) // delay slot

	s.align_long()
	s.label('voices')
	for _ in 0 .. 6 {
		s.long(0)
	}
	return s
}

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

// hertz_step is what a voice adds to its 32-bit phase every sample to
// sound a frequency.
fn hertz_step(hertz f64) u32 {
	return u32(hertz / jagkit.ntsc.sample_rate(sclk_value) * 4294967296.0)
}

// phase_step is the same for a MIDI note.
fn phase_step(note int) u32 {
	return hertz_step(440.0 * math.pow(2, f64(note - 69) / 12))
}

// kick_sweep is the pitch of the kick drum on its first frames: a thump
// is a tone falling fast.
fn kick_sweep() []u32 {
	return [hertz_step(190), hertz_step(110), hertz_step(70),
		hertz_step(52)]
}

// bass_line has a note for every step; the steps the kick lands on are
// not used. The last step of every other bar jumps an octave.
fn bass_line() []u32 {
	mut line := []u32{cap: song_steps}
	for step in 0 .. song_steps {
		root := root_note + bass_roots[(step / 64) % bass_roots.len]
		lift := if step % 32 == 31 { 12 } else { 0 }
		line << phase_step(root + lift)
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
		line << phase_step(root + 24 + interval + lift)
	}
	return line
}
