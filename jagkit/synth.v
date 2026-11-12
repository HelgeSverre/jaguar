module jagkit

import math

// A small synthesizer for the DSP: a square wave, a sawtooth and noise,
// mixed to both channels. It only makes the waves. The 68000 is the
// musician: it writes each voice's pitch and volume, and lets the volumes
// decay, usually once a frame.

// Offsets of the voice settings from the `voices` label of the DSP program.
pub const voice_bass_step = 4 // added to the phase every sample
pub const voice_bass_volume = 8
pub const voice_lead_step = 12
pub const voice_lead_volume = 16
pub const voice_noise_volume = 20

// synth_sclk sets the sample rate: about 20.8 kHz.
pub const synth_sclk = 19

// synth is the DSP program: start-up code and the sample interrupt. Start
// it at its `start` label; its settings are at its `voices` label.
pub fn synth() &Risc {
	stack := Reg.r31
	flags_address := Reg.r30
	flags := Reg.r29
	scratch := Reg.r28
	voices := Reg.r14
	left_dac := Reg.r20
	right_dac := Reg.r21
	bass_phase := Reg.r10
	lead_phase := Reg.r11
	noise := Reg.r12
	mix := Reg.r1
	a := Reg.r0
	b := Reg.r2
	c := Reg.r3

	mut s := new_risc(dsp_ram)
	// The interrupt vectors are 16 bytes apart; only the sample interrupt
	// is used.
	s.pad_to(dsp_i2s_vector)
	s.movei_label('sample', scratch)
	s.jump(.always, scratch)
	s.nop()
	s.pad_to(dsp_ram + 0x60)

	s.label('start')
	s.movei(dsp_ram + dsp_ram_size, stack)
	s.movei(d_flags, flags_address)
	s.movei_label('voices', voices)
	s.movei(l_dac, left_dac)
	s.movei(r_dac, right_dac)
	s.moveq(0, bass_phase)
	s.moveq(0, lead_phase)
	s.movei(0x2545f491, noise)
	s.movei(sclk, a)
	s.moveq(synth_sclk, b)
	s.store(b, a)
	s.movei(smode, a)
	s.moveq(smode_internal, b)
	s.store(b, a)
	s.load(flags_address, a)
	s.bset(dsp_flag_i2s_enable, a)
	s.store(a, flags_address)
	s.label('idle')
	s.jr(.always, 'idle')
	s.nop()

	// The DSP enters with the vector's address in r30, so the handler has
	// to point it at the flags again.
	s.label('sample')
	s.movei(d_flags, flags_address)
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
	s.bclr(flag_imask, flags)
	s.bset(dsp_flag_i2s_clear, flags)
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

// hertz_step is what a voice adds to its 32-bit phase every sample to
// sound a frequency.
pub fn hertz_step(hertz f64) u32 {
	return u32(hertz / ntsc.sample_rate(synth_sclk) * 4294967296.0)
}

// note_step is the same for a MIDI note.
pub fn note_step(note int) u32 {
	return hertz_step(440.0 * math.pow(2, f64(note - 69) / 12))
}
