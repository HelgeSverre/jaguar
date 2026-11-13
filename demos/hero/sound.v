module main

import math
import jagkit

// The DSP is a ten-voice synthesizer with an echo. The 68000 is the
// musician: it sets a voice's pitch and level and bumps its trigger; the DSP
// notices, restarts the voice's envelope and lets it decay, sample by
// sample, on its own.

const sclk_value = 19 // about 20.8 kHz

fn sample_rate() f64 {
	return jagkit.ntsc.sample_rate(sclk_value)
}

// The voices, in the order of their records.
const voice_kick = 0
const voice_snare = 1
const voice_hat = 2
const voice_crash = 3
const voice_bass = 4
const voice_chord = 5 // the rhythm guitar: a distorted power chord
const voice_keys = 6
const voice_hero = 7 // the lead guitar the player plays
const voice_harmony = 8 // its twin
const voice_sfx = 9 // the sound of a miss
const voice_count = 10

// Offsets in a voice rec_reg, from the rec_reg's address. The 68000 owns the
// first five, the DSP the rest.
const v_step = 4 // added to the phase every sample
const v_level = 8 // where the envelope starts, 0..32767
const v_rate = 12 // how fast it falls: 65536ths of the level a sample
const v_trigger = 16 // bumped by the 68000 to start a note
const v_sweep = 20 // extra pitch at the start of a note, falling away
const v_seen = 24 // the trigger the DSP last answered
const v_env = 28 // the envelope, level << 8
const v_phase = 32
const v_phase2 = 36 // the second oscillator of a doubled voice
const v_excess = 40 // what is left of the sweep
const voice_bytes = 48

// Offsets in the globals record.
const g_delay1 = 4 // echo taps, in bytes back from the write position
const g_delay2 = 8
const g_back = 12 // echo feedback, of 256
const g_wet = 16 // echo level, of 256
const g_lfo_phase = 20
const g_lfo_step = 24

const echo_address = u32(0x1d0000) // 8192 samples of echo, in main RAM
const echo_mask = 0x3ffe
const clip_level = 0x6000 // where the guitars distort
const vibrato_hz = 5.5

enum Kind {
	kick  // a triangle that drops in pitch
	snare // noise over a falling triangle
	hiss  // bright noise: hats and cymbals
	bass  // saw and square
	chord // root and fifth, two saws, clipped
	keys  // two detuned squares
	lead  // two detuned saws with vibrato, clipped
	sfx   // a falling square
}

const kinds = [Kind.kick, .snare, .hiss, .hiss, .bass, .chord, .keys, .lead, .lead, .sfx]

// Voices whose sound also feeds the echo.
const wet_voices = [voice_keys, voice_hero, voice_harmony]

// sweep_shift is how fast a kind's pitch sweep falls: the excess loses
// 1/2^shift of itself every sample.
fn sweep_shift(k Kind) int {
	return match k {
		.kick { 9 }
		.snare { 8 }
		.sfx { 11 }
		else { 0 }
	}
}

// phase_step is what a voice adds to its 32-bit osc_phase every sample to
// sound a frequency.
fn phase_step(hertz f64) u32 {
	return u32(hertz / sample_rate() * 4294967296.0)
}

fn midi_hertz(note int) f64 {
	return 440.0 * math.pow(2, f64(note - 69) / 12)
}

// decay_rate is the envelope rate that brings a note to a third of its
// level in `ms` milliseconds.
fn decay_rate(ms int) int {
	samples := f64(ms) / 1000.0 * sample_rate()
	return int(math.max(1.0, math.min(65535.0, 65536.0 / samples)))
}

// Registers of the sample interrupt. Those from r15 up keep their values
// from one sample to the next.
const tmp0 = jagkit.Reg.r0
const tmp1 = jagkit.Reg.r1
const osc_env = jagkit.Reg.r2
const osc_step = jagkit.Reg.r3
const osc_phase = jagkit.Reg.r4
const osc_wave = jagkit.Reg.r5
const tap1 = jagkit.Reg.r6
const tap2 = jagkit.Reg.r7
const tmp2 = jagkit.Reg.r8
const tmp3 = jagkit.Reg.r9
const mix_bus = jagkit.Reg.r10
const wet_bus = jagkit.Reg.r11
const noise_reg = jagkit.Reg.r12
const lfo_reg = jagkit.Reg.r13
const rec_reg = jagkit.Reg.r14
const bright_noise = jagkit.Reg.r15 // this sample's high-passed noise
const last_noise = jagkit.Reg.r16
const k7fff = jagkit.Reg.r17
const clip_high = jagkit.Reg.r18
const clip_low = jagkit.Reg.r19
const echo_base = jagkit.Reg.r20
const echo_wrap = jagkit.Reg.r21
const echo_at = jagkit.Reg.r22
const out_high = jagkit.Reg.r23
const out_low = jagkit.Reg.r24
const k8000 = jagkit.Reg.r25
const left_dac = jagkit.Reg.r26
const right_dac = jagkit.Reg.r27
const scratch_reg = jagkit.Reg.r28
const flags_reg = jagkit.Reg.r29
const flags_addr = jagkit.Reg.r30
const stack_reg = jagkit.Reg.r31

// synthesizer is the DSP program: start-up code and the sample interrupt.
fn synthesizer() &jagkit.Risc {
	mut s := jagkit.new_risc(jagkit.dsp_ram)
	s.pad_to(jagkit.dsp_i2s_vector)
	s.movei_label('sample', scratch_reg)
	s.jump(.always, scratch_reg)
	s.nop()
	s.pad_to(jagkit.dsp_ram + 0x60)

	s.label('start')
	s.movei(jagkit.dsp_ram + jagkit.dsp_ram_size, stack_reg)
	s.movei(jagkit.d_flags, flags_addr)
	s.movei(jagkit.l_dac, left_dac)
	s.movei(jagkit.r_dac, right_dac)
	s.movei(0x2545f491, noise_reg)
	s.moveq(0, last_noise)
	s.movei(0x7fff, k7fff)
	s.movei(0x8000, k8000)
	s.movei(clip_level, clip_high)
	s.movei(u32(-clip_level), clip_low)
	s.movei(echo_address, echo_base)
	s.movei(echo_mask, echo_wrap)
	s.moveq(0, echo_at)
	s.movei(32767, out_high)
	s.movei(u32(-32767), out_low)
	s.movei(jagkit.sclk, tmp0)
	s.moveq(sclk_value, tmp1)
	s.store(tmp1, tmp0)
	s.movei(jagkit.smode, tmp0)
	s.moveq(jagkit.smode_internal, tmp1)
	s.store(tmp1, tmp0)
	s.load(flags_addr, tmp0)
	s.bset(jagkit.dsp_flag_i2s_enable, tmp0)
	s.store(tmp0, flags_addr)
	s.label('idle')
	s.jr(.always, 'idle')
	s.nop()

	// The DSP enters with the vector's address in r30, so the handler has
	// to point it at the flags_reg again.
	s.label('sample')
	s.movei(jagkit.d_flags, flags_addr)
	s.load(flags_addr, flags_reg)
	s.moveq(0, mix_bus)
	s.moveq(0, wet_bus)
	noise_and_lfo(mut s)
	for i, kind in kinds {
		voice(mut s, i, kind)
	}
	echo_and_output(mut s)
	// Leave the interrupt: unmask, acknowledge, return past the
	// interrupted instruction.
	s.bclr(jagkit.flag_imask, flags_reg)
	s.bset(jagkit.dsp_flag_i2s_clear, flags_reg)
	s.load(stack_reg, scratch_reg)
	s.addq(2, scratch_reg)
	s.addq(4, stack_reg)
	s.jump(.always, scratch_reg)
	s.store(flags_reg, flags_addr) // delay slot

	s.align_long()
	for i in 0 .. voice_count {
		s.label('voice_${i}')
		for _ in 0 .. voice_bytes / 4 {
			s.long(0)
		}
	}
	s.long(0) // the last rec_reg's last field
	s.label('globals')
	s.long(0)
	s.long(0) // delay1
	s.long(0) // delay2
	s.long(0) // feedback
	s.long(0) // wet
	s.long(0) // lfo phase
	s.long(phase_step(vibrato_hz)) // lfo step
	s.long(0)
	return s
}

// noise_and_lfo steps the noise generator, high-passes it for the cymbals
// and moves the vibrato.
fn noise_and_lfo(mut s jagkit.Risc) {
	// A xorshift generator.
	s.move(noise_reg, tmp0)
	s.shlq(13, tmp0)
	s.xor(tmp0, noise_reg)
	s.move(noise_reg, tmp0)
	s.shrq(17, tmp0)
	s.xor(tmp0, noise_reg)
	s.move(noise_reg, tmp0)
	s.shlq(5, tmp0)
	s.xor(tmp0, noise_reg)
	// The difference of two noise samples has its energy up high.
	s.move(noise_reg, bright_noise)
	s.sharq(17, bright_noise)
	s.move(bright_noise, tmp0)
	s.sub(last_noise, bright_noise)
	s.move(tmp0, last_noise)
	// The vibrato: a slow triangle, -32768..32767.
	s.movei_label('globals', rec_reg)
	s.load_r14(g_lfo_phase, tmp0)
	s.load_r14(g_lfo_step, tmp1)
	s.add(tmp1, tmp0)
	s.store_r14(tmp0, g_lfo_phase)
	triangle(mut s, tmp0, lfo_reg)
}

// triangle turns a phase into a triangle wave, -32768..32767.
fn triangle(mut s jagkit.Risc, from jagkit.Reg, to jagkit.Reg) {
	s.move(from, to)
	s.move(from, tmp3)
	s.sharq(31, tmp3)
	s.xor(tmp3, to)
	s.shrq(15, to)
	s.sub(k8000, to)
}

// square turns a phase into a square wave, -32768 or 32767.
fn square(mut s jagkit.Risc, from jagkit.Reg, to jagkit.Reg) {
	s.move(from, to)
	s.sharq(31, to)
	s.xor(k7fff, to)
}

// clip limits a register to -limit..limit, hard: the distortion.
fn clip(mut s jagkit.Risc, value jagkit.Reg, high jagkit.Reg, low jagkit.Reg) {
	below := 'below_${s.here()}'
	above := 'above_${s.here()}'
	s.cmp(high, value)
	s.jr(.mi, below)
	s.nop()
	s.move(high, value)
	s.label(below)
	s.cmp(low, value)
	s.jr(.pl, above)
	s.nop()
	s.move(low, value)
	s.label(above)
}

// second_oscillator advances the voice's second osc_phase by the first's step
// plus 1/2^shift of it, leaving the phase in tmp2.
fn second_oscillator(mut s jagkit.Risc, shift int) {
	s.move(osc_step, tmp1)
	s.shrq(shift, tmp1)
	s.add(osc_step, tmp1)
	s.load_r14(v_phase2, tmp2)
	s.add(tmp1, tmp2)
	s.store_r14(tmp2, v_phase2)
}

// voice generates one voice's sample and adds it to the mix_bus.
fn voice(mut s jagkit.Risc, index int, kind Kind) {
	held := 'held_${index}'
	s.movei_label('voice_${index}', rec_reg)
	// A new note: restart the envelope and the sweep.
	s.load_r14(v_trigger, tmp0)
	s.load_r14(v_seen, tmp1)
	s.cmp(tmp0, tmp1)
	s.jr(.eq, held)
	s.nop()
	s.store_r14(tmp0, v_seen)
	s.load_r14(v_level, tmp1)
	s.shlq(8, tmp1)
	s.store_r14(tmp1, v_env)
	s.load_r14(v_sweep, tmp1)
	s.store_r14(tmp1, v_excess)
	s.label(held)

	// The envelope falls by level * rate / 65536 every sample.
	s.load_r14(v_env, osc_env)
	s.move(osc_env, tmp1)
	s.shrq(8, tmp1)
	s.load_r14(v_rate, tmp0)
	s.mult(tmp1, tmp0)
	s.shrq(8, tmp0)
	s.sub(tmp0, osc_env)
	s.store_r14(osc_env, v_env)
	s.shrq(8, osc_env) // the level this sample

	// Pitch, with the sweep on top.
	s.load_r14(v_step, osc_step)
	shift := sweep_shift(kind)
	if shift > 0 {
		s.load_r14(v_excess, tmp1)
		s.move(tmp1, tmp0)
		s.shrq(shift, tmp0)
		s.sub(tmp0, tmp1)
		s.store_r14(tmp1, v_excess)
		s.add(tmp1, osc_step)
	}
	if kind == .lead {
		s.move(osc_step, tmp0)
		s.shrq(14, tmp0)
		s.imult(lfo_reg, tmp0)
		s.sharq(9, tmp0)
		s.add(tmp0, osc_step)
	}
	s.load_r14(v_phase, osc_phase)
	s.add(osc_step, osc_phase)
	s.store_r14(osc_phase, v_phase)

	match kind {
		.kick {
			triangle(mut s, osc_phase, osc_wave)
		}
		.snare {
			triangle(mut s, osc_phase, osc_wave)
			s.sharq(1, osc_wave)
			s.move(noise_reg, tmp0)
			s.sharq(17, tmp0)
			s.add(tmp0, osc_wave)
		}
		.hiss {
			s.move(bright_noise, osc_wave)
		}
		.bass {
			s.move(osc_phase, osc_wave)
			s.sharq(17, osc_wave)
			square(mut s, osc_phase, tmp0)
			s.sharq(1, tmp0)
			s.add(tmp0, osc_wave)
		}
		.chord {
			second_oscillator(mut s, 1) // a fifth above
			s.move(osc_phase, osc_wave)
			s.sharq(16, osc_wave)
			s.sharq(16, tmp2)
			s.add(tmp2, osc_wave)
			s.add(osc_wave, osc_wave)
			clip(mut s, osc_wave, clip_high, clip_low)
		}
		.keys {
			second_oscillator(mut s, 8)
			square(mut s, osc_phase, osc_wave)
			s.sharq(1, osc_wave)
			square(mut s, tmp2, tmp0)
			s.sharq(1, tmp0)
			s.add(tmp0, osc_wave)
		}
		.lead {
			second_oscillator(mut s, 8)
			s.move(osc_phase, osc_wave)
			s.sharq(16, osc_wave)
			s.sharq(16, tmp2)
			s.add(tmp2, osc_wave)
			clip(mut s, osc_wave, clip_high, clip_low)
		}
		.sfx {
			square(mut s, osc_phase, osc_wave)
		}
	}

	s.imult(osc_env, osc_wave)
	s.sharq(15, osc_wave)
	s.add(osc_wave, mix_bus)
	if index in wet_voices {
		s.add(osc_wave, wet_bus)
	}
}

// echo_and_output runs the echo: two taps of a delay line in main RAM, one
// for each side, the first fed back. Then both sides go to the DACs.
fn echo_and_output(mut s jagkit.Risc) {
	s.movei_label('globals', rec_reg)
	for i, tap in [tap1, tap2] {
		s.load_r14(if i == 0 { g_delay1 } else { g_delay2 }, tmp0)
		s.move(echo_at, tmp1)
		s.sub(tmp0, tmp1)
		s.and(echo_wrap, tmp1)
		s.add(echo_base, tmp1)
		s.loadw(tmp1, tap)
		s.shlq(16, tap)
		s.sharq(16, tap)
	}
	// Into the line: half the wet_bus voices and some of what comes out.
	s.load_r14(g_back, tmp0)
	s.move(tap1, tmp1)
	s.imult(tmp0, tmp1)
	s.sharq(8, tmp1)
	s.move(wet_bus, tmp2)
	s.sharq(1, tmp2)
	s.add(tmp2, tmp1)
	clip(mut s, tmp1, out_high, out_low)
	s.move(echo_at, tmp2)
	s.add(echo_base, tmp2)
	s.storew(tmp1, tmp2)
	s.addqt(2, echo_at)
	s.and(echo_wrap, echo_at)
	s.load_r14(g_wet, tmp0)
	s.imult(tmp0, tap1)
	s.sharq(8, tap1)
	s.imult(tmp0, tap2)
	s.sharq(8, tap2)
	for tap, dac in {
		tap1: left_dac
		tap2: right_dac
	} {
		s.move(mix_bus, tmp1)
		s.add(tap, tmp1)
		clip(mut s, tmp1, out_high, out_low)
		s.store(tmp1, dac)
	}
}
