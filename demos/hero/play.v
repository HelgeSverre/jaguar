module main

import jagkit { abs, at, idx, imm, inc, ind, lbl }

// Playing a song: the sequencer that turns step records into notes on the
// DSP, and the judge that compares the player's presses with the chart.

// Word variables cleared when a song starts.
const song_counters = ['clock', 'judge_first', 'draw_first', 'combo', 'max_combo', 'tier', 'perfects',
	'greats', 'goods', 'misses', 'song_over', 'failed', 'finish_timer', 'event_timer', 'paused',
	'flash', 'line_index', 'next_line', 'hero_quiet', 'harmony_quiet', 'strays']

const lane_effects = ['lane_glow', 'target_flash', 'target_kind', 'target_state', 'burst_time',
	'burst_kind']

const burst_frames_shown = 12
const judge_frames_shown = 30
const event_column = 10 // event banners are padded to twenty characters
const event_row = 8
const cut_rate = 65535 // silences a voice within a sample
const fade_rate = 400

// mute fast-fades the voices that sustain.
fn (mut g Game) mute(rate int) {
	for v in [voice_bass, voice_chord, voice_keys, voice_hero, voice_harmony] {
		g.m.move(.l, imm(rate), g.voice(v, v_rate))
	}
}

// trigger starts a note on a voice; the pitch, level and rate are already
// in place.
fn (mut g Game) trigger(v int) {
	g.m.add(.l, imm(1), g.voice(v, v_trigger))
}

// sfx plays the miss sound: a square falling from `from` to `to` Hz.
fn (mut g Game) sfx(from f64, to f64, level int, ms int) {
	mut m := g.m
	m.move(.l, imm(phase_step(to)), g.voice(voice_sfx, v_step))
	m.move(.l, imm(phase_step(from - to)), g.voice(voice_sfx, v_sweep))
	m.move(.l, imm(level), g.voice(voice_sfx, v_level))
	m.move(.l, imm(decay_rate(ms)), g.voice(voice_sfx, v_rate))
	g.trigger(voice_sfx)
}

fn (mut g Game) sequencer() {
	mut m := g.m

	// song_record points a5 at the record of song d0.
	m.label('song_record')
	m.lea(lbl('song_table'), a5)
	m.and(.l, imm(0xffff), d0)
	m.mulu(imm(rec_bytes), d0)
	m.add(.l, d0, a5)
	m.rts()

	// setup_voices tunes the synthesizer for the song at a5 and copies its
	// tempo to where the frame routines want it.
	m.label('setup_voices')
	m.move(.l, a5, lbl('song_rec'))
	m.move(.l, at(rec_setup, a5), a0)
	m.label('setup_next')
	m.move(.l, inc(a0), d0)
	m.b(.eq, 'setup_done')
	m.move(.l, d0, a1)
	m.move(.l, inc(a0), ind(a1))
	m.bra('setup_next')
	m.label('setup_done')
	m.move(.w, at(rec_fps + 2, a5), lbl('fps'))
	m.move(.w, at(rec_spb + 2, a5), lbl('spb'))
	m.move(.w, at(rec_beat_frames + 2, a5), lbl('beat_frames'))
	m.move(.w, at(rec_look + 2, a5), lbl('look'))
	for name in ['step_timer', 'step_in_beat', 'beat_timer', 'beat_parity', 'hero_quiet',
		'harmony_quiet'] {
		m.move(.w, imm(0), lbl(name))
	}
	m.move(.w, imm(1), lbl('hero_live'))
	m.rts()

	// preview_song plays a few bars of song d0, over and over.
	m.label('preview_song')
	m.move(.w, d0, lbl('song'))
	m.bsr('song_record')
	m.bsr('setup_voices')
	m.move(.l, at(rec_preview, a5), d0)
	m.lsl(.l, imm(3), d0)
	m.add(.l, at(rec_steps, a5), d0)
	m.move(.l, d0, lbl('seq_ptr'))
	m.move(.l, d0, lbl('seq_loop'))
	m.move(.w, at(rec_preview_steps + 2, a5), lbl('seq_left'))
	m.move(.w, imm(seq_preview), lbl('seq_mode'))
	m.move(.w, imm(0), lbl('tier'))
	m.rts()

	// sequence runs once a frame: on the first frame of a step it plays the
	// step, and it keeps count of the beats.
	m.label('sequence')
	m.cmp(.w, imm(63), lbl('beat_timer'))
	m.b(.cc, 'beat_counted')
	m.add(.w, imm(1), lbl('beat_timer'))
	m.label('beat_counted')
	m.tst(.w, lbl('seq_mode'))
	m.b(.eq, 'sequence_done')
	m.tst(.w, lbl('step_timer'))
	m.b(.ne, 'step_wait')
	m.move(.l, lbl('seq_ptr'), a0)
	m.bsr('play_step')
	m.add(.l, imm(8), lbl('seq_ptr'))
	m.tst(.w, lbl('step_in_beat'))
	m.b(.ne, 'not_a_beat')
	m.move(.w, imm(0), lbl('beat_timer'))
	m.eor(.w, imm(1), lbl('beat_parity'))
	m.label('not_a_beat')
	m.add(.w, imm(1), lbl('step_in_beat'))
	m.move(.w, lbl('step_in_beat'), d0)
	m.cmp(.w, lbl('spb'), d0)
	m.b(.ne, 'beat_kept')
	m.move(.w, imm(0), lbl('step_in_beat'))
	m.label('beat_kept')
	m.sub(.w, imm(1), lbl('seq_left'))
	m.b(.ne, 'step_timed')
	m.cmp(.w, imm(seq_preview), lbl('seq_mode'))
	m.b(.ne, 'sequence_stop')
	m.move(.l, lbl('seq_loop'), lbl('seq_ptr'))
	m.move(.l, lbl('song_rec'), a5)
	m.move(.w, at(rec_preview_steps + 2, a5), lbl('seq_left'))
	m.bra('step_timed')
	m.label('sequence_stop')
	m.move(.w, imm(seq_off), lbl('seq_mode'))
	m.label('step_timed')
	m.move(.w, lbl('fps'), lbl('step_timer'))
	m.label('step_wait')
	m.sub(.w, imm(1), lbl('step_timer'))
	m.label('sequence_done')
	m.rts()

	// note_step turns MIDI note d0 into a phase step.
	m.label('note_step')
	m.and(.l, imm(0x7f), d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('midi_steps'), a1)
	m.move(.l, idx(0, a1, d0), d0)
	m.rts()

	// play_step plays the step record at a0: drums, bass, rhythm guitar,
	// keys, the two lead guitars, releases, and a banner or the end.
	m.label('play_step')
	m.move(.l, lbl('song_rec'), a5)
	m.move(.b, ind(a0), d7)
	m.btst(0, d7)
	m.b(.eq, 'no_kick')
	g.trigger(voice_kick)
	m.label('no_kick')
	m.btst(1, d7)
	m.b(.eq, 'no_snare')
	m.move(.l, at(rec_snare_level, a5), d0)
	m.btst(5, d7)
	m.b(.eq, 'snare_loud')
	m.move(.l, at(rec_ghost_level, a5), d0)
	m.label('snare_loud')
	m.move(.l, d0, g.voice(voice_snare, v_level))
	m.move(.l, at(rec_snare_step, a5), d0)
	m.btst(6, d7)
	m.b(.eq, 'snare_tuned')
	m.move(.l, at(rec_tom_step, a5), d0)
	m.label('snare_tuned')
	m.move(.l, d0, g.voice(voice_snare, v_step))
	g.trigger(voice_snare)
	m.label('no_snare')
	m.btst(2, d7)
	m.b(.eq, 'no_hat')
	m.move(.l, at(rec_hat_closed, a5), g.voice(voice_hat, v_rate))
	g.trigger(voice_hat)
	m.label('no_hat')
	m.btst(3, d7)
	m.b(.eq, 'no_open_hat')
	m.move(.l, at(rec_hat_open, a5), g.voice(voice_hat, v_rate))
	g.trigger(voice_hat)
	m.label('no_open_hat')
	m.btst(4, d7)
	m.b(.eq, 'no_crash')
	g.trigger(voice_crash)
	m.move(.w, imm(12), lbl('flash'))
	m.label('no_crash')

	m.move(.b, at(6, a0), d6) // the flags
	m.moveq(0, d0)
	m.move(.b, at(1, a0), d0)
	m.b(.eq, 'no_bass')
	m.bsr('note_step')
	m.move(.l, d0, g.voice(voice_bass, v_step))
	m.move(.l, at(rec_bass_rate, a5), g.voice(voice_bass, v_rate))
	g.trigger(voice_bass)
	m.label('no_bass')
	m.moveq(0, d0)
	m.move(.b, at(2, a0), d0)
	m.b(.eq, 'no_chord')
	m.bsr('note_step')
	m.move(.l, d0, g.voice(voice_chord, v_step))
	m.move(.l, at(rec_chord_ring, a5), d0)
	m.btst(0, d6)
	m.b(.eq, 'chord_rings')
	m.move(.l, at(rec_chord_mute, a5), d0)
	m.label('chord_rings')
	m.move(.l, d0, g.voice(voice_chord, v_rate))
	g.trigger(voice_chord)
	m.label('no_chord')
	m.moveq(0, d0)
	m.move(.b, at(3, a0), d0)
	m.b(.eq, 'no_keys')
	m.bsr('note_step')
	m.move(.l, d0, g.voice(voice_keys, v_step))
	g.trigger(voice_keys)
	m.label('no_keys')
	// The lead guitars sound only while the player keeps up.
	for i, v in [voice_hero, voice_harmony] {
		skip := m.unique('no_lead')
		heard := m.unique('lead_heard')
		quiet := ['hero_quiet', 'harmony_quiet'][i]
		m.moveq(0, d0)
		m.move(.b, at(4 + i, a0), d0)
		m.b(.eq, skip)
		m.bsr('note_step')
		m.move(.l, d0, g.voice(v, v_step))
		m.move(.l, at(rec_hero_sustain, a5), g.voice(v, v_rate))
		m.move(.l, at([rec_hero_level, rec_harmony_level][i], a5), d0)
		m.move(.w, imm(0), lbl(quiet))
		m.tst(.w, lbl('hero_live'))
		m.b(.ne, heard)
		m.moveq(0, d0)
		m.move(.w, imm(1), lbl(quiet))
		m.label(heard)
		m.move(.l, d0, g.voice(v, v_level))
		g.trigger(v)
		m.label(skip)
	}
	m.btst(1, d6)
	m.b(.eq, 'no_lead_release')
	m.move(.l, at(rec_hero_release, a5), g.voice(voice_hero, v_rate))
	m.move(.l, at(rec_hero_release, a5), g.voice(voice_harmony, v_rate))
	m.label('no_lead_release')
	m.btst(2, d6)
	m.b(.eq, 'no_bass_release')
	m.move(.l, at(rec_release, a5), g.voice(voice_bass, v_rate))
	m.label('no_bass_release')
	m.btst(3, d6)
	m.b(.eq, 'no_chord_release')
	m.move(.l, at(rec_release, a5), g.voice(voice_chord, v_rate))
	m.label('no_chord_release')
	m.moveq(0, d0)
	m.move(.b, at(7, a0), d0)
	m.b(.eq, 'step_played')
	m.cmp(.w, imm(seq_play), lbl('seq_mode'))
	m.b(.ne, 'step_played')
	m.cmp(.w, imm(event_end), d0)
	m.b(.ne, 'show_event')
	m.move(.w, imm(1), lbl('song_over'))
	m.label('step_played')
	m.rts()

	// show_event raises banner d0 over the highway for a while.
	m.label('show_event')
	m.and(.l, imm(0xff), d0)
	m.lsl(.w, imm(2), d0)
	m.lea(lbl('event_texts'), a1)
	m.move(.l, idx(0, a1, d0), a0)
	m.moveq(event_column, d0)
	m.moveq(event_row, d1)
	m.moveq(2, d2)
	m.bsr('print')
	m.move(.w, imm(150), lbl('event_timer'))
	m.rts()
}

fn (mut g Game) start_song() {
	mut m := g.m
	m.label('start_song')
	// Silence what the menu was playing, echo and all.
	g.mute(cut_rate)
	m.lea(abs(echo_address), a0)
	m.move(.w, imm(echo_mask / 4), d0)
	m.bsr('clear')
	m.move(.w, lbl('chosen'), d0)
	m.move(.w, d0, lbl('song'))
	m.bsr('song_record')
	m.bsr('setup_voices')
	m.move(.l, at(rec_steps, a5), lbl('seq_ptr'))
	m.move(.w, at(rec_step_count + 2, a5), lbl('seq_left'))
	m.move(.w, imm(seq_play), lbl('seq_mode'))
	m.move(.l, at(rec_chart, a5), lbl('chart_ptr'))
	m.move(.l, at(rec_view, a5), lbl('view_ptr'))
	m.move(.w, at(rec_note_count + 2, a5), lbl('note_count'))
	m.lea(abs(note_state), a0)
	m.move(.w, imm(max_notes / 4 - 1), d0)
	m.bsr('clear')
	for name in song_counters {
		m.move(.w, imm(0), lbl(name))
	}
	m.move(.l, imm(0), lbl('score'))
	m.move(.l, imm(-1), lbl('shown_score'))
	m.move(.w, imm(-1), lbl('progress_shown'))
	m.move(.w, imm(health_start), lbl('health'))
	m.move(.w, imm(judge_frames_shown), lbl('judge_time'))
	for lane in 0 .. lanes {
		m.move(.w, imm(burst_frames_shown), lbl('burst_time_${lane}'))
	}
	m.move(.w, imm(state_play), lbl('state'))
	m.bsr('clear_text')
	m.move(.l, lbl('song_rec'), a5)
	m.move(.l, at(rec_name, a5), a0)
	m.moveq(1, d0)
	m.moveq(1, d1)
	m.moveq(3, d2)
	m.bsr('print')
	g.say(1, 2, 1, '-'.repeat(progress_cells))
	g.say(31, 1, 1, 'SCORE')
	g.say(1, 10, 3, 'COMBO')
	g.say(36, 6, 1, 'LIFE')
	m.rts()
}
