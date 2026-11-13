module jaggame

import jagkit
import jaggame.emulated
import jerry

// Sound: effects with priority, music that keeps its tempo on both
// television standards and switches tracks, what reaches the DSP, and that it
// can be heard.

const calm_pattern = Pattern{
	lead:    'A4 . . . C5 . . . E5 . . . C5 . . .'
	harmony: 'E4 . . . . . . . G4 . . . . . . .'
	bass:    'A2 . . . . . . . F2 . . . . . . .'
	drums:   'k . . . . . . . h . . . . . . .'
}

const alert_pattern = Pattern{
	lead:    'E5 F5 E5 - E5 F5 E5 - B4 C5 B4 - B4 C5 B4 -'
	harmony: 'E4 . E4 . E4 . E4 . F4 . F4 . F4 . F4 .'
	bass:    'E2 E2 . E2 E2 . E2 . F2 F2 . F2 F2 . F2 .'
	drums:   'k h s h k h s h k h s h k h s h'
}

// sound_game has two effects on the tone voice (a quiet one and a loud one
// of higher priority), a thud on the noise voice and two tracks. The pad: A
// the quiet effect, B the important one, C the thud, Option the calm track,
// Pause the alert one (held, so the track is asked for every frame), Star
// stops the music.
fn sound_game() &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	g.sfx('quiet', Sfx{
		priority: 1
		volume:   1000
		steps:    [SfxStep{440, 0.5}]
	})
	g.sfx('sting', Sfx{
		priority: 5
		volume:   3000
		decay:    4
		steps:    [SfxStep{660, 0.1}, SfxStep{880, 0.1}, SfxStep{1320, 0.2}]
	})
	g.sfx('thud', Sfx{
		noise:    true
		priority: 2
		volume:   2500
		decay:    3
		slide:    2
		steps:    [SfxStep{300, 0.3}]
	})
	g.track('calm', Track{
		rows_per_second: 6.0
		patterns:        [calm_pattern]
		order:           [0]
	})
	g.track('alert', Track{
		rows_per_second: 10.0
		patterns:        [alert_pattern]
		order:           [0]
	})
	mut c := g.define_update()
	c.if_(g.pressed(.a))
	g.play(mut c, 'quiet')
	c.end()
	c.if_(g.pressed(.b))
	g.play(mut c, 'sting')
	c.end()
	c.if_(g.pressed(.c))
	g.play(mut c, 'thud')
	c.end()
	c.if_(g.held(.pause))
	g.music_play(mut c, 'alert')
	c.else_if(g.held(.option))
	g.music_play(mut c, 'calm')
	c.end()
	c.if_(g.pressed(.star))
	g.music_stop(mut c)
	c.end()
	return g
}

fn pad_of(buttons ...Button) u32 {
	mut mask := u32(0)
	for b in buttons {
		mask |= button_mask(b)
	}
	return mask
}

// pitch and level are a voice's step and volume in the interpreter's mailbox.
fn pitch(it &Interpreter, voice int) i64 {
	return it.element('rt_voice', voice * 2) or { panic(err) }
}

fn level(it &Interpreter, voice int) i64 {
	return it.element('rt_voice', voice * 2 + 1) or { panic(err) }
}

fn test_note_names_are_midi_numbers() {
	assert note_number('A4')! == 69
	assert note_number('C4')! == 60
	assert note_number('Bb3')! == 58
	assert note_number('C#5')! == 73
	assert note_number('C0')! == 12
	if _ := note_number('H4') {
		assert false, 'H is not a note'
	}
	if _ := note_number('A') {
		assert false, 'a note needs an octave'
	}
	if _ := note_number('C9') {
		assert false, 'C9 is out of range'
	}
}

fn test_an_effect_sets_the_voice_and_a_lower_priority_does_not_cut_it_off() {
	mut g := sound_game()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, 0)!
	assert pitch(it, voice_effect_tone) == 0 && level(it, voice_effect_tone) == 0
	g.step(mut it, pad_of(.a))!
	assert pitch(it, voice_effect_tone) == i64(jagkit.hertz_step(440.0))
	assert level(it, voice_effect_tone) == 1000
	// The sting has the higher priority: it takes the voice.
	g.step(mut it, pad_of(.b))!
	assert it.element('rt_sfx_id', 0)! == 2
	assert it.element('rt_sfx_prio', 0)! == 5
	assert pitch(it, voice_effect_tone) == i64(jagkit.hertz_step(660.0))
	// The quiet one now is refused while the sting plays.
	g.step(mut it, pad_of(.a))!
	assert it.element('rt_sfx_id', 0)! == 2, 'the quiet effect did not cut the sting off'
	// The sting walks through its steps, then the voice is free and silent.
	mut seen := []i64{}
	for _ in 0 .. 40 {
		g.step(mut it, 0)!
		st := pitch(it, voice_effect_tone)
		if st != 0 && st !in seen {
			seen << st
		}
	}
	assert seen == [i64(jagkit.hertz_step(660.0)), i64(jagkit.hertz_step(880.0)),
		i64(jagkit.hertz_step(1320.0))], '${seen}'
	assert it.element('rt_sfx_id', 0)! == 0
	assert level(it, voice_effect_tone) == 0
	// Equal priority does cut in: the same effect again starts over.
	g.step(mut it, pad_of(.a))!
	g.step(mut it, 0)!
	g.step(mut it, pad_of(.a))!
	assert it.element('rt_sfx_step', 0)! == 0
}

fn test_the_noise_effect_falls_in_pitch_and_both_effect_voices_play_together() {
	mut g := sound_game()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, pad_of(.a, .c))!
	first := pitch(it, voice_effect_noise)
	g.step(mut it, 0)!
	assert pitch(it, voice_effect_noise) < first, 'the slide lowers the pitch'
	assert level(it, voice_effect_noise) < 2500, 'the volume decays'
	assert it.element('rt_sfx_id', 0)! == 1 && it.element('rt_sfx_id', 1)! == 3
}

fn test_the_tempo_is_the_same_in_seconds_on_both_standards() {
	for region in [Region.ntsc, Region.pal] {
		mut g := sound_game()
		mut it := g.interpreter(region)!
		fps := if region == .pal { 50 } else { 60 }
		g.step(mut it, pad_of(.option))!
		for _ in 0 .. 10 * fps - 1 {
			g.step(mut it, pad_of(.option))!
		}
		rows := int(it.value('rt_music_rows')!)
		// 10 seconds at 6 rows a second: 60, within a row of the frame rounding
		assert rows >= 59 && rows <= 61, '${rows} rows at ${fps} fps'
	}
}

fn test_a_track_that_is_asked_for_every_frame_is_not_restarted() {
	mut g := sound_game()
	mut it := g.interpreter(.ntsc)!
	for _ in 0 .. 40 {
		g.step(mut it, pad_of(.option))!
	}
	rows_before := it.value('rt_music_rows')!
	assert rows_before > 3
	// the same track is asked for again on every frame: the rows go on counting
	for _ in 0 .. 20 {
		g.step(mut it, pad_of(.option))!
	}
	assert it.value('rt_music_rows')! > rows_before + 1
	assert it.value('rt_music')! == 1
	// another track begins at its first row, once
	g.step(mut it, pad_of(.pause))!
	assert it.value('rt_music')! == 2
	assert it.value('rt_music_row')! == 1 && it.value('rt_music_pos')! == 0, 'row 0 played at once'
	rows_alert := it.value('rt_music_rows')!
	for _ in 0 .. 12 {
		g.step(mut it, pad_of(.pause))!
	}
	assert it.value('rt_music')! == 2
	assert it.value('rt_music_rows')! >= rows_alert + 2
	g.step(mut it, pad_of(.star))!
	assert it.value('rt_music')! == 0
}

fn test_the_music_sets_the_voices_from_the_pattern() {
	mut g := sound_game()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, pad_of(.option))!
	assert pitch(it, voice_lead) == i64(jagkit.note_step(69)), 'the first row of the calm pattern: A4'
	assert level(it, voice_lead) > 1000
	assert pitch(it, voice_bass) == i64(jagkit.note_step(45))
	assert level(it, voice_drums) > 1000 && pitch(it, voice_drums) != 0, 'a kick on the first row'
}

fn test_the_dsp_gets_what_the_program_writes_and_it_is_heard() {
	mut g := sound_game()
	img := g.build()!
	synth := game_synth()
	voices := synth.address_of('voices') - jagkit.dsp_ram
	mut p := emulated.boot(img.bytes, false)!
	p.frames(20)
	p.audio()
	// silent before anything plays
	quiet := p.audio()
	mut loudest_quiet := 0
	for s in quiet {
		if s > loudest_quiet {
			loudest_quiet = s
		}
	}
	assert loudest_quiet < 100, 'silent before anything plays'
	p.press(jerry.Button.b)
	p.frames(2)
	p.release(jerry.Button.b)
	p.frames(1)
	mut dsp_step := u32(0)
	for k in 0 .. 4 {
		dsp_step = (dsp_step << 8) | p.m.dsp.read_ram8(voices + 4 + 8 * 4 + u32(k))
	}
	assert dsp_step != 0, 'the sting reached the DSP'
	assert int(img.element(p.m.ram, 'rt_voice', 8)!) == int(dsp_step)
	heard := p.audio()
	mut peak := 0
	for s in heard {
		if s > peak {
			peak = s
		}
	}
	assert peak > 1500, 'it is loud enough: ${peak}'
}

// crossings counts how often a recording crosses zero, a measure of pitch;
// energy is its mean square.
fn crossings(samples []i16) int {
	mut count := 0
	mut last := 0
	for k in 0 .. samples.len / 2 {
		s := int(samples[k * 2])
		if (s > 200 && last < -200) || (s < -200 && last > 200) {
			count++
		}
		if s > 200 || s < -200 {
			last = s
		}
	}
	return count
}

fn test_calm_and_alert_sound_different_and_the_machine_agrees_with_the_interpreter() {
	mut g := sound_game()
	img := g.build()!
	mut h := sound_game()
	mut it := h.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!
	p.frames(10)
	for _ in 0 .. 10 {
		h.step(mut it, 0)!
	}
	p.audio()
	mut calm_samples := []i16{}
	mut alert_samples := []i16{}
	for track in [Button.option, .pause] {
		p.press(if track == .option { jerry.Button.option } else { jerry.Button.pause })
		for _ in 0 .. 150 {
			h.step(mut it, button_mask(track))!
			p.frames(1)
		}
		if track == .option {
			calm_samples << p.audio()
		} else {
			alert_samples << p.audio()
		}
		p.release(if track == .option { jerry.Button.option } else { jerry.Button.pause })
	}
	assert calm_samples.len > 20000 && alert_samples.len > 20000
	calm_energy := energy(calm_samples)
	alert_energy := energy(alert_samples)
	println('calm: energy ${calm_energy}, crossings ${crossings(calm_samples)}; alert: energy ${alert_energy}, crossings ${crossings(alert_samples)}')
	assert calm_energy > 100_000, 'the calm track is not silent'
	assert alert_energy > calm_energy * 3 / 2, 'the alert track is louder than the calm one'
	assert crossings(alert_samples) != crossings(calm_samples)
	// the two sides agree on the mailbox
	for k in 0 .. voice_count * 2 {
		assert img.element(p.m.ram, 'rt_voice', k)! == it.element('rt_voice', k)!, 'voice word ${k}'
	}
	assert img.value(p.m.ram, 'rt_music')! == 2
}

fn energy(samples []i16) i64 {
	mut total := i64(0)
	for s in samples {
		total += i64(s) * i64(s)
	}
	return total / i64(samples.len)
}

fn test_the_sound_costs_little_in_every_frame() {
	mut quiet := new_game(Config{ sprites: 1, layers: 1 })
	quiet.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	quiet.define_update()
	quiet_img := quiet.build()!
	mut g := sound_game()
	img := g.build()!
	mut q := emulated.boot(quiet_img.bytes, false)!
	q.frames(10)
	base := q.busy_cycles(120)
	mut p := emulated.boot(img.bytes, false)!
	p.frames(10)
	p.press(jerry.Button.pause)
	p.frames(3)
	mut worst := 0
	mut total := 0
	for _ in 0 .. 120 {
		used := p.busy_cycles(1)
		total += used
		if used > worst {
			worst = used
		}
	}
	mean := total / 120
	println('sound: an empty game uses ${base} cycles a frame; with the alert music ${mean} on average, ${worst} at most (a row of music every 6 frames)')
	assert mean - base < 6000, 'the sound costs ${mean - base} cycles a frame on average'
	assert worst - base < 14000, 'and ${worst - base} in the worst frame'
}

fn test_sound_mistakes_are_reported_together() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	g.sfx('a', Sfx{
		volume: 100
		steps:  [SfxStep{440, 0.1}]
	})
	g.sfx('a', Sfx{
		volume: 100
		steps:  [SfxStep{440, 0.1}]
	})
	g.sfx('loud', Sfx{
		volume: 9000
		steps:  []
	})
	g.track('bad', Track{
		rows_per_second: 99.0
		patterns:        [
			Pattern{
				lead:    'A4 . .'
				harmony: 'H4 . . . . . . . . . . . . . . .'
				bass:    'A2 . . . . . . . . . . . . . . .'
				drums:   'x . . . . . . . . . . . . . . .'
			},
		]
		order:           [3]
	})
	mut c := g.define_update()
	g.play(mut c, 'nothing')
	g.music_play(mut c, 'nowhere')
	message := build_error(mut g)
	assert message.contains('sound effect `a` is defined twice'), message
	assert message.contains('sound effect `loud` has 0 steps'), message
	assert message.contains('99.0 rows a second'), message
	assert message.contains('the order names pattern 3'), message
	assert message.contains('pattern 0, lead: 3 entries, there must be 16'), message
	assert message.contains('pattern 0, harmony: `H4` is not a note'), message
	assert message.contains('pattern 0, drums: `x` is not a drum'), message
	assert message.contains('play(`nothing`): there is no such sound effect'), message
	assert message.contains('music_play(`nowhere`): there is no such track'), message
}

fn build_error(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}
