module main

import math
import jagkit

// The DSP plays three voices: a square-wave bass, a sawtooth lead and
// noise. The 68000 is the musician: once a frame it sets their pitches and
// lets their volumes decay.

// Offsets of the voice settings from the `voices` label of the DSP program.
const voice_bass_step = 4 // added to the phase every sample
const voice_bass_volume = 8
const voice_lead_step = 12
const voice_lead_volume = 16
const voice_noise_volume = 20

const sclk_value = 19 // about 20.8 kHz
const bass_volume = 5500
const lead_volume = 5000
const noise_volume = 12000

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

// The tune: eight bars of 32 steps, one chord a bar. A step lasts four
// frames.
const song_steps = 256
const chords = [
	[45, 48, 52], // A minor
	[41, 45, 48], // F
	[48, 52, 55], // C
	[43, 47, 50], // G
	[45, 48, 52], // A minor
	[41, 45, 48], // F
	[43, 47, 50], // G
	[40, 44, 47], // E
]

// phase_step is what a voice adds to its 32-bit phase every sample to
// sound a MIDI note.
fn phase_step(note int) u32 {
	hertz := 440.0 * math.pow(2, f64(note - 69) / 12)
	return u32(hertz / jagkit.ntsc.sample_rate(sclk_value) * 4294967296.0)
}

// bass_line gives the bass a note on a 3-3-2 rhythm; zero lets it ring.
fn bass_line() []u32 {
	mut line := []u32{cap: song_steps}
	for step in 0 .. song_steps {
		root := chords[step / 32][0]
		line << match step % 8 {
			0, 3 { phase_step(root) }
			6 { phase_step(if step % 32 >= 24 { root + 12 } else { root }) }
			else { u32(0) }
		}
	}
	return line
}

// lead_line runs up and down the chord, an octave higher every other half
// bar.
fn lead_line() []u32 {
	pattern := [0, 1, 2, 3, 2, 1, 2, 3]
	mut line := []u32{cap: song_steps}
	for step in 0 .. song_steps {
		chord := chords[step / 32]
		degree := pattern[step % 8]
		note := if degree == 3 { chord[0] + 12 } else { chord[degree] }
		lift := if (step / 16) % 2 == 1 { 36 } else { 24 }
		line << phase_step(note + lift)
	}
	return line
}
