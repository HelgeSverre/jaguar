module jaggame

import jagkit

// The DSP program of the sound (see rt_sound.v): six voices mixed to both
// channels at about 20.8 kHz. The program writes pitches and volumes into
// the `voices` block of the DSP's memory (a long that is not used, then a
// step and a volume for each voice) and the DSP only makes the waves.
//
//	0 lead      square
//	1 harmony   square
//	2 bass      triangle
//	3 drums     noise: it changes at the rate its step gives
//	4 tone      square, for effects
//	5 noise     for effects
//
// A square wave is +volume while its phase is below half and -volume above.
// The noise voices hold a random sign and take a new one each time the top
// bit of their phase flips, so a small step is a rumble and the biggest is
// white noise.
//
// The registers from r15 up keep their values from one sample to the next;
// those below are set up again in every sample (the interrupt does not keep
// them), as in the demos.

const synth_first_voice = 4 // the offset of the first voice's step in `voices`

// synth_voice_step is the offset of a voice's step in the `voices` block;
// its volume is 4 further.
fn synth_voice_step(index int) int {
	return synth_first_voice + 8 * index
}

// game_synth is the DSP program: start-up code and the sample interrupt.
// Start it at its `start` label; its settings are at its `voices` label.
fn game_synth() &jagkit.Risc {
	stack := jagkit.Reg.r31
	flags_address := jagkit.Reg.r30
	flags := jagkit.Reg.r29
	scratch := jagkit.Reg.r28
	left_dac := jagkit.Reg.r20
	right_dac := jagkit.Reg.r21
	noise := jagkit.Reg.r22
	held_drums := jagkit.Reg.r23
	held_effect := jagkit.Reg.r24
	phases := [jagkit.Reg.r15, .r16, .r17, .r18, .r19, .r25]
	base := jagkit.Reg.r14
	mix := jagkit.Reg.r1
	a := jagkit.Reg.r0
	b := jagkit.Reg.r2
	c := jagkit.Reg.r3

	mut s := jagkit.new_risc(jagkit.dsp_ram)
	s.pad_to(jagkit.dsp_i2s_vector)
	s.movei_label('sample', scratch)
	s.jump(.always, scratch)
	s.nop()
	s.pad_to(jagkit.dsp_ram + 0x60)

	s.label('start')
	s.movei(jagkit.dsp_ram + jagkit.dsp_ram_size, stack)
	s.movei(jagkit.d_flags, flags_address)
	s.movei(jagkit.l_dac, left_dac)
	s.movei(jagkit.r_dac, right_dac)
	for r in phases {
		s.moveq(0, r)
	}
	s.moveq(0, held_drums)
	s.moveq(0, held_effect)
	s.movei(0x2545f491, noise)
	s.movei(jagkit.sclk, a)
	s.moveq(jagkit.synth_sclk, b)
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
	s.movei_label('voices', base)
	s.moveq(0, mix)
	square(mut s, 0, phases[0], a, b, c, mix)
	square(mut s, 1, phases[1], a, b, c, mix)
	triangle(mut s, 2, phases[2], a, b, c, mix)
	pitched_noise(mut s, 3, phases[3], noise, held_drums, a, b, c, mix)
	square(mut s, 4, phases[4], a, b, c, mix)
	pitched_noise(mut s, 5, phases[5], noise, held_effect, a, b, c, mix)
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
	for _ in 0 .. 1 + 2 * voice_count {
		s.long(0)
	}
	return s
}

// square adds a voice's square wave to the mix.
fn square(mut s jagkit.Risc, voice int, phase jagkit.Reg, a jagkit.Reg, b jagkit.Reg, c jagkit.Reg, mix jagkit.Reg) {
	s.load_r14(synth_voice_step(voice), a)
	s.add(a, phase)
	s.load_r14(synth_voice_step(voice) + 4, c)
	s.move(phase, b)
	s.sharq(31, b)
	s.xor(b, c)
	s.sub(b, c)
	s.add(c, mix)
}

// triangle adds a voice's triangle wave to the mix: the phase folded at its
// top bit, then scaled by the volume.
fn triangle(mut s jagkit.Risc, voice int, phase jagkit.Reg, a jagkit.Reg, b jagkit.Reg, c jagkit.Reg, mix jagkit.Reg) {
	s.load_r14(synth_voice_step(voice), a)
	s.add(a, phase)
	s.load_r14(synth_voice_step(voice) + 4, c)
	s.move(phase, b)
	s.move(phase, a)
	s.sharq(31, a)
	s.xor(a, b)
	s.shrq(15, b)
	s.movei(0x8000, a)
	s.sub(a, b)
	s.imult(c, b)
	s.sharq(15, b)
	s.add(b, mix)
}

// pitched_noise adds a noise voice to the mix. The voice's sign changes to a
// new random one when the top bit of its phase flips.
fn pitched_noise(mut s jagkit.Risc, voice int, phase jagkit.Reg, noise jagkit.Reg, held jagkit.Reg, a jagkit.Reg, b jagkit.Reg, c jagkit.Reg, mix jagkit.Reg) {
	keep := 'keep_noise_${voice}'
	s.load_r14(synth_voice_step(voice), a)
	s.move(phase, b)
	s.add(a, phase)
	s.xor(phase, b)
	s.jr(.pl, keep)
	s.nop()
	// A xorshift generator, and the sign of what it makes.
	s.move(noise, a)
	s.shlq(13, a)
	s.xor(a, noise)
	s.move(noise, a)
	s.shrq(17, a)
	s.xor(a, noise)
	s.move(noise, a)
	s.shlq(5, a)
	s.xor(a, noise)
	s.move(noise, held)
	s.sharq(31, held)
	s.label(keep)
	s.load_r14(synth_voice_step(voice) + 4, c)
	s.move(held, b)
	s.xor(b, c)
	s.sub(b, c)
	s.add(c, mix)
}
