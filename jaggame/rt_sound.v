module jaggame

import jagkit

// Sound: sound effects and music on a small synthesizer in the DSP.
//
// The DSP makes six voices and nothing else: two square waves for the
// melody, a triangle for the bass, a noise voice for drums, and a square
// wave and a noise voice for effects. Each has a pitch (`step`, what its
// phase gains every sample) and a volume that the program writes into a
// mailbox, the array `rt_voice` (two longs for each voice: step, volume), and
// the machine copies to the DSP once a frame.
//
// Everything that decides what sounds is ordinary code of the program, so the
// interpreter runs it too and a test can compare the mailbox of the machine
// with the interpreter's: `rt_sound_tick` runs at the end of every frame and
// moves the effects, the sequencer and the volumes' decay; `play` starts an
// effect; `music_play` and `music_stop` start and stop a track.
//
// Effects have a priority and a voice (a tone or a noise): a new effect
// takes the voice only if it has at least the priority of the one still
// playing there. Music has the other four voices to itself.
//
// Music is data made when the game is built: patterns of 16 rows for four
// channels, written as text with note names (`C4 . . E4 -`: `.` holds, `-`
// is a note off), an order of patterns and a speed in rows a second. The
// sequencer counts rows from the frame count, so the tempo is the same on
// both television standards.

const voice_count = 6
const voice_lead = 0
const voice_harmony = 1
const voice_bass = 2
const voice_drums = 3
const voice_effect_tone = 4
const voice_effect_noise = 5
const pattern_rows = 16
const music_channels = 4

// the drums: 1 kick, 2 snare, 3 hat
const drum_names = ['.', 'k', 's', 'h']

// the volume a channel's notes start at, and how fast they fall (each frame
// a voice loses 1/2^shift of its volume; 0 holds it)
const channel_levels = [1500, 1000, 2000]
const channel_decays = [5, 4, 0]

// Sfx is a sound effect: a sequence of pitches on one voice.
pub struct Sfx {
pub:
	noise    bool // the noise voice (footsteps, knocks); a tone otherwise
	priority int  // 0..255; a new effect needs at least the priority of the one it would cut off
	volume   int  // 1..4000
	decay    int  // the volume loses 1/2^decay of itself each frame; 0 holds it for the whole step
	slide    int  // the pitch loses 1/2^slide of itself each frame; 0 holds it
	steps    []SfxStep
}

// SfxStep is one pitch of an effect and how long it lasts.
pub struct SfxStep {
pub:
	hz      f64 // a tone's frequency, or how fast the noise changes; 0 is silence
	seconds f64
}

// Pattern is 16 rows of music: four channels written as text.
pub struct Pattern {
pub:
	lead    string // 16 notes: `A4`, `C#5`, `Bb3`, `.` to hold, `-` to stop
	harmony string
	bass    string
	drums   string // 16 of `k` kick, `s` snare, `h` hat, `.` nothing
}

// Track is a piece of music: patterns, the order they are played in (a
// pattern may come again) and how fast it goes.
pub struct Track {
pub:
	rows_per_second f64 // 1..30
	patterns        []Pattern
	order           []int // indexes of `patterns`; the track starts over when it reaches the end
}

struct SfxInfo {
	name string
	sfx  Sfx
}

struct TrackInfo {
	name  string
	track Track
}

// SoundVars is what the sound declares in the program, made by `use_sound`.
@[heap]
struct SoundVars {
mut:
	voice      Expr // u32 array: the mailbox
	decay      Expr // u8 array: each voice's decay shift
	slide      Expr // u8 array: each voice's pitch slide shift
	sfx_id     Expr // u8 array: the effect on each of the two effect voices, 1 + its number, 0 for none
	sfx_step   Expr // u8 array: which step it is on
	sfx_wait   Expr // u8 array: frames left in the step
	sfx_prio   Expr // u8 array: its priority
	mus        Expr // u8: the track that plays, 1 + its number, 0 for none
	mus_pos    Expr // u8: the place in its order
	mus_row    Expr // u8: the next row to play
	mus_acc    Expr // fix: rows that are due, a row for each 1.0
	mus_rate   Expr // fix: rows a frame
	mus_rows   Expr // u16: rows played since the game started
	sfx_count  Expr // u8 table: the steps of each effect
	play       Func
	sfx_begin  Func
	music_play Func
	music_stop Func
	tick       Func
	row        Func
}

// use_sound declares the sound's variables and functions, once. The tables
// and the bodies are made when the game is built, when every effect and
// track is known.
fn (mut g Game) use_sound() {
	if g.sounds {
		return
	}
	g.sounds = true
	mut p := g.p
	g.snd = &SoundVars{
		voice:      p.array_u32('rt_voice', voice_count * 2)
		decay:      p.array_u8('rt_voice_decay', voice_count)
		slide:      p.array_u8('rt_voice_slide', voice_count)
		sfx_id:     p.array_u8('rt_sfx_id', 2)
		sfx_step:   p.array_u8('rt_sfx_step', 2)
		sfx_wait:   p.array_u8('rt_sfx_wait', 2)
		sfx_prio:   p.array_u8('rt_sfx_prio', 2)
		mus:        p.u8('rt_music')
		mus_pos:    p.u8('rt_music_pos')
		mus_row:    p.u8('rt_music_row')
		mus_acc:    p.fix('rt_music_acc')
		mus_rate:   p.fix('rt_music_rate')
		mus_rows:   p.u16('rt_music_rows')
		sfx_count:  invalid('no effects yet')
		play:       p.func('rt_play', [Param{'id', .u8}], .void)
		sfx_begin:  p.func('rt_sfx_begin', [Param{'slot', .u8}], .void)
		music_play: p.func('rt_music_play', [Param{'id', .u8}], .void)
		music_stop: p.func('rt_music_stop', [], .void)
		tick:       p.func('rt_sound_tick', [], .void)
		row:        p.func('rt_music_row_play', [], .void)
	}
}

// sfx declares a sound effect with a name, to start with `play`.
pub fn (mut g Game) sfx(name string, sfx Sfx) {
	g.use_sound()
	for s in g.sfxs {
		if s.name == name {
			g.problem('sound effect `${name}` is defined twice')
			return
		}
	}
	if sfx.steps.len < 1 || sfx.steps.len > 16 {
		g.problem('sound effect `${name}` has ${sfx.steps.len} steps; it must have 1..16')
	}
	if sfx.volume < 1 || sfx.volume > 4000 || sfx.priority < 0 || sfx.priority > 255
		|| sfx.decay < 0 || sfx.decay > 7 || sfx.slide < 0 || sfx.slide > 7 {
		g.problem('sound effect `${name}`: the volume must be 1..4000, the priority 0..255, the decay and the slide 0..7')
	}
	for st in sfx.steps {
		if st.seconds <= 0.0 || st.seconds > 4.0 || st.hz < 0.0 || st.hz > 10000.0 {
			g.problem('sound effect `${name}`: a step of ${st.hz} Hz for ${st.seconds} seconds is out of range (0..10000 Hz, up to 4 seconds)')
		}
	}
	g.sfxs << SfxInfo{name, sfx}
}

// track declares a piece of music with a name, to start with `music_play`.
pub fn (mut g Game) track(name string, track Track) {
	g.use_sound()
	for t in g.tracks {
		if t.name == name {
			g.problem('track `${name}` is defined twice')
			return
		}
	}
	if track.rows_per_second < 1.0 || track.rows_per_second > 30.0 {
		g.problem('track `${name}`: ${track.rows_per_second} rows a second; it must be 1..30')
	}
	if track.patterns.len < 1 || track.order.len < 1 || track.order.len > 64 {
		g.problem('track `${name}` needs patterns and an order of 1..64 of them')
	}
	for at in track.order {
		if at < 0 || at >= track.patterns.len {
			g.problem('track `${name}`: the order names pattern ${at}, and there are ${track.patterns.len}')
		}
	}
	for k, pat in track.patterns {
		for ch, text in [pat.lead, pat.harmony, pat.bass, pat.drums] {
			g.pattern_notes(name, k, ch, text) or { g.problem(err.msg()) }
		}
	}
	g.tracks << TrackInfo{name, track}
}

// play starts a sound effect. It takes the effect voice it belongs on if
// that is free or playing something of lower or equal priority; otherwise
// nothing happens.
pub fn (mut g Game) play(mut c Code, name string) {
	g.use_sound()
	for i, s in g.sfxs {
		if s.name == name {
			c.call(g.snd.play, i + 1)
			return
		}
	}
	g.problem('play(`${name}`): there is no such sound effect; declare it with sfx() before it is played')
}

// music_play starts a track, unless it is the one playing: calling it every
// frame is fine. Another track that was playing is cut off at once.
pub fn (mut g Game) music_play(mut c Code, name string) {
	g.use_sound()
	for i, t in g.tracks {
		if t.name == name {
			c.call(g.snd.music_play, i + 1)
			return
		}
	}
	g.problem('music_play(`${name}`): there is no such track; declare it with track() first')
}

// music_stop stops the music; the notes that sound fade out.
pub fn (mut g Game) music_stop(mut c Code) {
	g.use_sound()
	c.call(g.snd.music_stop)
}

// music_is is true while the named track is playing. Declare the track
// first.
pub fn (mut g Game) music_is(name string) Expr {
	g.use_sound()
	for i, t in g.tracks {
		if t.name == name {
			return g.snd.mus.eq(i + 1)
		}
	}
	g.problem('music_is(`${name}`): there is no such track')
	return invalid('no track ${name}')
}

// music_rows is the number of rows the sequencer has played since the game
// started (a `u16` expression): a clock that runs at the track's tempo.
pub fn (mut g Game) music_rows() Expr {
	g.use_sound()
	return g.snd.mus_rows
}

// note_number is the MIDI number of a note name like `A4`, `C#5` or `Bb3`;
// C4 is 60 and A4 is 69.
fn note_number(name string) !int {
	letters := {
		`C`: 0
		`D`: 2
		`E`: 4
		`F`: 5
		`G`: 7
		`A`: 9
		`B`: 11
	}
	if name.len < 2 {
		return error('`${name}` is not a note')
	}
	base := letters[rune(name[0])] or { return error('`${name}` is not a note') }
	mut at := 1
	mut semitone := base
	if name[at] == `#` {
		semitone++
		at++
	} else if name[at] == `b` {
		semitone--
		at++
	}
	if at >= name.len || !name[at..].bytes().all(it >= `0` && it <= `9`) {
		return error('`${name}` is not a note')
	}
	number := 12 * (name[at..].int() + 1) + semitone
	if number < 12 || number > 108 {
		return error('the note `${name}` is out of range (C0 to C8)')
	}
	return number
}

// row_codes turns one channel of a pattern into a code for each row: 0 holds
// what plays, 1 stops it (for the drums, 1..3 are the drums), 2.. are MIDI
// notes.
fn row_codes(text string, drums bool) ![]int {
	words := text.fields()
	if words.len != pattern_rows {
		return error('${words.len} entries, there must be ${pattern_rows}')
	}
	mut codes := []int{}
	for word in words {
		if word == '.' {
			codes << 0
		} else if drums {
			at := drum_names.index(word)
			if at < 1 {
				return error('`${word}` is not a drum (k, s, h or .)')
			}
			codes << at
		} else if word == '-' {
			codes << 1
		} else {
			codes << note_number(word)!
		}
	}
	return codes
}

// pattern_notes checks one channel of a pattern, for the message's sake.
fn (g &Game) pattern_notes(track string, pattern int, channel int, text string) ! {
	row_codes(text, channel == 3) or {
		return error('track `${track}`, pattern ${pattern}, ${['lead', 'harmony', 'bass', 'drums'][channel]}: ${err.msg()}')
	}
}

// drum_sounds are the pitch (the noise's rate, in Hz), the volume, the decay
// and the slide of each drum, from 1.
const drum_steps_hz = [0.0, 90.0, 9000.0, 14000.0]
const drum_volumes = [0, 2600, 1800, 800]
const drum_decays = [0, 3, 3, 1]
const drum_slides = [0, 3, 0, 0]

// sound_hertz_step is the phase step of a frequency.
fn sound_hertz_step(hz f64) i64 {
	return i64(jagkit.hertz_step(hz))
}

// padded is a list that is not empty: a table has to have an element.
fn padded(values []int) []int {
	if values.len > 0 {
		return values
	}
	return [0]
}

fn padded_long(values []i64) []i64 {
	if values.len > 0 {
		return values
	}
	return [i64(0)]
}

// define_sound writes the functions of the sound and makes its tables.
fn (mut g Game) define_sound() {
	g.define_effects()
	g.define_music()
	g.define_tick()
}

// define_effects writes `rt_play`: the tables of the effects and the start
// of an effect, and the step that moves it on.
fn (mut g Game) define_effects() {
	mut p := g.p
	s := g.snd
	mut first := []int{}
	mut counts := []int{}
	mut voices := []int{}
	mut prios := []int{}
	mut vols := []int{}
	mut decays := []int{}
	mut slides := []int{}
	mut steps := []i64{}
	mut ntsc := []int{}
	mut pal := []int{}
	for info in g.sfxs {
		first << steps.len
		counts << info.sfx.steps.len
		voices << if info.sfx.noise { voice_effect_noise } else { voice_effect_tone }
		prios << info.sfx.priority
		vols << info.sfx.volume
		decays << info.sfx.decay
		slides << info.sfx.slide
		for st in info.sfx.steps {
			steps << sound_hertz_step(st.hz)
			ntsc << frames_for(st.seconds, 60)
			pal << frames_for(st.seconds, 50)
		}
	}
	total := steps.len
	mut both := ntsc.clone()
	both << pal
	t_first := p.table_u16('rt_sfx_first', padded(first))
	t_count := p.table_u8('rt_sfx_count', padded(counts))
	t_voice := p.table_u8('rt_sfx_voice', padded(voices))
	t_prio := p.table_u8('rt_sfx_priority', padded(prios))
	t_vol := p.table_u16('rt_sfx_volume', padded(vols))
	t_decay := p.table_u8('rt_sfx_decay', padded(decays))
	t_slide := p.table_u8('rt_sfx_slide', padded(slides))
	t_step := p.table_u32('rt_sfx_pitch', padded_long(steps))
	t_frames := p.table_u8('rt_sfx_frames', padded(both))

	// rt_sfx_begin(slot): start the step the slot is on.
	g.snd.sfx_count = t_count
	begin := s.sfx_begin
	mut c := p.define(begin)
	slot := begin.arg('slot')
	index := c.local_u16('index')
	id := c.local_u16('id')
	voice := c.local_u8('voice')
	c.set(id, s.sfx_id.at(slot).sub(1))
	c.set(voice, slot.add(voice_effect_tone))
	c.set(index, t_first.at(id).add(s.sfx_step.at(slot)))
	c.set(s.voice.at(voice.mul(2)), t_step.at(index))
	c.set(s.voice.at(voice.mul(2).add(1)), t_vol.at(id))

	c.if_(t_step.at(index).eq(0))
	c.set(s.voice.at(voice.mul(2).add(1)), 0)
	c.end() // a silent step
	c.set(s.sfx_wait.at(slot), t_frames.at(index.add(g.pal.as_(.u16).mul(total))))

	// rt_play(id): `id` is 1 + the effect's number.
	c = p.define(s.play)
	pid := s.play.arg('id')
	eid := c.local_u16('eid')
	pslot := c.local_u8('pslot')
	c.set(eid, pid.sub(1))
	c.set(pslot, t_voice.at(eid).sub(voice_effect_tone))

	c.if_(s.sfx_id.at(pslot).ne(0).both(t_prio.at(eid).lt(s.sfx_prio.at(pslot))))
	c.ret_void() // what plays there matters more
	c.end()
	c.set(s.sfx_id.at(pslot), pid)
	c.set(s.sfx_step.at(pslot), 0)
	c.set(s.sfx_prio.at(pslot), t_prio.at(eid))
	c.set(s.decay.at(pslot.add(voice_effect_tone)), t_decay.at(eid))
	c.set(s.slide.at(pslot.add(voice_effect_tone)), t_slide.at(eid))
	c.call(begin, pslot)
}

// define_music writes the tables of the music and `rt_music_play`,
// `rt_music_stop` and the function that plays one row.
fn (mut g Game) define_music() {
	mut p := g.p
	s := g.snd
	mut notes := []int{}
	mut order_first := []int{}
	mut order_len := []int{}
	mut order_pattern := []int{}
	mut speeds := []f64{}
	mut pattern_at := 0
	for info in g.tracks {
		order_first << order_pattern.len
		order_len << info.track.order.len
		speeds << info.track.rows_per_second
		for at in info.track.order {
			order_pattern << pattern_at + at
		}
		for pat in info.track.patterns {
			columns := [pat.lead, pat.harmony, pat.bass, pat.drums]
			mut by_channel := [][]int{}
			for ch, text in columns {
				by_channel << (row_codes(text, ch == 3) or { []int{len: pattern_rows} })
			}
			for row in 0 .. pattern_rows {
				for ch in 0 .. music_channels {
					notes << by_channel[ch][row]
				}
			}
		}
		pattern_at += info.track.patterns.len
	}
	mut note_steps := []i64{len: 128}
	for n in 0 .. 128 {
		note_steps[n] = i64(jagkit.note_step(n))
	}
	t_notes := p.table_u8('rt_pattern_notes', padded(notes))
	t_first := p.table_u16('rt_order_first', padded(order_first))
	t_len := p.table_u8('rt_order_length', padded(order_len))
	t_pattern := p.table_u8('rt_order_pattern', padded(order_pattern))
	t_speed := p.table_fix('rt_track_speed', if speeds.len > 0 { speeds } else { [1.0] })
	t_pitch := p.table_u32('rt_note_steps', note_steps)
	mut drum_pitch := []i64{}
	for hz in drum_steps_hz {
		drum_pitch << sound_hertz_step(hz)
	}
	t_drum_pitch := p.table_u32('rt_drum_pitch', drum_pitch)
	t_drum_vol := p.table_u16('rt_drum_volume', drum_volumes)
	t_drum_decay := p.table_u8('rt_drum_decay', drum_decays)
	t_drum_slide := p.table_u8('rt_drum_slide', drum_slides)
	t_level := p.table_u16('rt_channel_level', channel_levels)
	t_decay := p.table_u8('rt_channel_decay', channel_decays)

	// rt_music_play(id): a track other than the one that plays begins at its first row.
	mut c := p.define(s.music_play)
	c.if_(s.mus.ne(s.music_play.arg('id')))
	c.set(s.mus, s.music_play.arg('id'))
	c.set(s.mus_pos, 0)
	c.set(s.mus_row, 0)
	c.set(s.mus_acc, 1.0) // the first row is due now
	c.set(s.mus_rate, t_speed.at(s.music_play.arg('id').sub(1).as_(.u16)).div(g.fps.as_(.fix)))
	c.end()

	c = p.define(s.music_stop)
	c.set(s.mus, 0)
	k := c.local_u8('k')
	c.for_(k, 0, voice_drums + 1)
	c.set(s.voice.at(k.mul(2).add(1)), 0)
	c.end()

	// rt_music_row_play: the notes of the next row, then on to the one after.
	c = p.define(s.row)
	track := c.local_u16('track')
	at := c.local_u16('at')
	note := c.local_u8('note')
	c.set(track, s.mus.sub(1).as_(.u16))
	c.set(at,
		t_pattern.at(t_first.at(track).add(s.mus_pos)).as_(.u16).mul(pattern_rows * music_channels).add(s.mus_row.as_(.u16).mul(music_channels)))
	for lane in 0 .. int(voice_drums) {
		c.set(note, t_notes.at(at.add(lane)))

		c.if_(note.eq(1))
		c.set(s.voice.at(lane * 2 + 1), 0)
		c.else_if(note.gt(1))
		c.set(s.voice.at(lane * 2), t_pitch.at(note))
		c.set(s.voice.at(lane * 2 + 1), t_level.at(lane))
		c.set(s.decay.at(lane), t_decay.at(lane))
		c.end() // stop, or start a note
	}
	c.set(note, t_notes.at(at.add(voice_drums)))

	c.if_(note.ne(0))
	c.set(s.voice.at(voice_drums * 2), t_drum_pitch.at(note))
	c.set(s.voice.at(voice_drums * 2 + 1), t_drum_vol.at(note))
	c.set(s.decay.at(voice_drums), t_drum_decay.at(note))
	c.set(s.slide.at(voice_drums), t_drum_slide.at(note))
	c.end() // a drum
	c.inc(s.mus_rows)
	c.inc(s.mus_row)

	c.if_(s.mus_row.ge(pattern_rows))
	c.set(s.mus_row, 0)
	c.inc(s.mus_pos)

	c.if_(s.mus_pos.ge(t_len.at(track)))
	c.set(s.mus_pos, 0)
	c.end() // the end of the order
	c.end() // the end of a pattern
}

// define_tick writes `rt_sound_tick`: once a frame the effects move on, the
// sequencer plays the rows that are due and every sounding voice decays.
fn (mut g Game) define_tick() {
	mut p := g.p
	s := g.snd
	mut c := p.define(s.tick)
	slot := c.local_u8('slot')

	c.if_(s.sfx_id.at(0).or_(s.sfx_id.at(1)).ne(0))
	c.for_(slot, 0, 2)

	c.if_(s.sfx_id.at(slot).ne(0))
	c.dec(s.sfx_wait.at(slot))

	c.if_(s.sfx_wait.at(slot).eq(0))
	c.inc(s.sfx_step.at(slot))

	c.if_(s.sfx_step.at(slot).ge(s.sfx_count.at(s.sfx_id.at(slot).sub(1).as_(.u16))))
	c.set(s.voice.at(slot.add(voice_effect_tone).mul(2).add(1)), 0)
	c.set(s.sfx_id.at(slot), 0)
	c.set(s.sfx_prio.at(slot), 0)
	c.else_()
	c.call(s.sfx_begin, slot)
	c.end() // the last step, or another
	c.end() // the step is over
	c.end() // an effect plays
	c.end() // each effect voice
	c.end() // some effect plays

	c.if_(s.mus.ne(0))
	c.set(s.mus_acc, s.mus_acc.add(s.mus_rate))

	c.if_(s.mus_acc.ge(1.0))
	c.set(s.mus_acc, s.mus_acc.sub(1.0))
	c.call(s.row)
	c.end() // a row is due
	c.end() // music plays

	c.native(fn (mut m jagkit.M68k) {
		emit_envelopes(mut m)
	}, fn (mut it Interpreter) ! {
		run_envelopes(mut it)!
	})
}

// emit_envelopes writes the machine code of the last step of the tick: every
// sounding voice loses 1/2^decay of its volume (at least 1) and 1/2^slide of
// its pitch. It was a loop of the language and cost about 4,000 cycles a
// frame; this costs a fifth of that.
fn emit_envelopes(mut m jagkit.M68k) {
	next := m.unique('rt.env_next')
	slide := m.unique('rt.env_slide')
	again := m.unique('rt.env_again')
	loop := m.unique('rt.env')
	m.lea(jagkit.lbl('rt_voice'), a0)
	m.lea(jagkit.lbl('rt_voice_decay'), a1)
	m.lea(jagkit.lbl('rt_voice_slide'), a2)
	m.moveq(voice_count - 1, d5)
	m.label(loop)
	m.move(.l, jagkit.at(4, a0), d0)
	m.b(.eq, next)
	m.moveq(0, d1)
	m.move(.b, jagkit.ind(a1), d1)
	m.b(.eq, slide)
	m.move(.l, d0, d2)
	m.lsr(.l, d1, d2)
	m.b(.ne, again)
	m.moveq(1, d2)
	m.label(again)
	m.sub(.l, d2, d0)
	m.move(.l, d0, jagkit.at(4, a0))
	m.label(slide)
	m.moveq(0, d1)
	m.move(.b, jagkit.ind(a2), d1)
	m.b(.eq, next)
	m.move(.l, jagkit.ind(a0), d2)
	m.move(.l, d2, d3)
	m.lsr(.l, d1, d3)
	m.sub(.l, d3, d2)
	m.move(.l, d2, jagkit.ind(a0))
	m.label(next)
	m.lea(jagkit.at(8, a0), a0)
	m.lea(jagkit.at(1, a1), a1)
	m.lea(jagkit.at(1, a2), a2)
	m.dbra(d5, loop)
}

// run_envelopes is what the interpreter does for `emit_envelopes`.
fn run_envelopes(mut it Interpreter) ! {
	for v in 0 .. voice_count {
		level := it.get_label('rt_voice', v * 2 + 1)!
		if level == 0 {
			continue
		}
		decay := it.get_label('rt_voice_decay', v)!
		if decay != 0 {
			mut cut := level >> u64(decay)
			if cut == 0 {
				cut = 1
			}
			it.put_label('rt_voice', v * 2 + 1, level - cut)!
		}
		slide := it.get_label('rt_voice_slide', v)!
		if slide != 0 {
			pitch := it.get_label('rt_voice', v * 2)!
			it.put_label('rt_voice', v * 2, pitch - (pitch >> u64(slide)))!
		}
	}
}

// emit_sound_copy writes `rt.send_voices`: the mailbox is copied into the
// DSP's voice settings (past the first long, which the DSP leaves unused).
fn (g &Game) emit_sound_copy(mut m jagkit.M68k, voices u32) {
	m.label('rt.send_voices')
	m.lea(jagkit.lbl('rt_voice'), a0)
	m.lea(jagkit.abs(voices + 4), a1)
	m.moveq(voice_count * 2 - 1, d0)
	m.label('rt.send_voice')
	m.move(.l, jagkit.inc(a0), jagkit.inc(a1))
	m.dbra(d0, 'rt.send_voice')
	m.rts()
}
