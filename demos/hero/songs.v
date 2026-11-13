module main

// The music. A song is written as sections of bars: a chord per bar (or
// per half bar), a drum pattern, rhythm strings for bass, rhythm guitar and
// keys, and a melody for the lead guitar, the "hero" part. The composer
// turns that into one record per sequencer step, which the 68000 plays.
// The chart, what the player presses, is the hero part itself.

// Scales, as semitones above the key.
const natural_minor = [0, 2, 3, 5, 7, 8, 10]
const harmonic_minor = [0, 2, 3, 5, 7, 8, 11]
const phrygian = [0, 1, 3, 5, 7, 8, 10]

// Drum bits of a step record.
const drum_kick = 0x01
const drum_snare = 0x02
const drum_hat = 0x04
const drum_open_hat = 0x08
const drum_crash = 0x10
const drum_ghost = 0x20 // the snare, quietly
const drum_tom = 0x40 // the snare voice, tuned down

// Flag bits of a step record.
const flag_chord_mute = 0x01 // a palm-muted chug: short decay
const flag_hero_release = 0x02
const flag_bass_release = 0x04
const flag_chord_release = 0x08
const flag_harmony_charted = 0x10 // the harmony note is a chart note too

// Banners a step can raise. The last one ends the song.
const event_texts = ['', 'GET READY', 'GUITAR SOLO!', 'KEY CHANGE!', 'BREAKDOWN', 'FINAL CHORUS!',
	'SHRED!', 'HERE IT COMES', 'FULL POWER!', 'OVERDRIVE! X8', '100 NOTE STREAK!', '150 NOTE STREAK!',
	'200 NOTE STREAK!', '250 NOTE STREAK!', 'UNSTOPPABLE!']
const event_ready = 1
const event_solo = 2
const event_key_change = 3
const event_breakdown = 4
const event_final = 5
const event_shred = 6
const event_coming = 7
const event_power = 8
const event_overdrive = 9
const event_streak = 10 // and on, for every fifty notes from a hundred
const streak_step = 50
const streak_banners = 5
const event_end = 255

// Step is what happens on one sequencer step. Notes are MIDI numbers; 0
// means nothing new.
struct Step {
mut:
	drums   u8
	bass    u8
	chord   u8
	keys    u8
	hero    u8
	harmony u8
	flags   u8
	event   u8
}

fn (s Step) bytes() []u8 {
	return [s.drums, s.bass, s.chord, s.keys, s.hero, s.harmony, s.flags, s.event]
}

// Section is a run of bars that share their patterns. Patterns repeat bar
// by bar; the hero line runs through the whole section, one token every
// `res` steps.
struct Section {
	bars   int
	chords string   // a scale degree per bar; `0/5` changes chord halfway
	drums  []string // one pattern per bar, repeated
	fill   string   // replaces the drums of the last bar
	bass   string   // r root, o octave up, f fifth, - release
	rhythm string   // X ringing power chord, x palm-muted chug, - release
	keys   string   // 0-3 root, third, fifth, octave; 4-7 the same an octave up
	hero   string
	res    int = 2
	twin   bool // a second guitar a third below the hero
	shift  int  // semitones up, for key changes
	event  int
	crash  bool = true
}

// Mix is the sound of a song: levels, and how long notes ring, in
// milliseconds to fall to a third.
struct Mix {
	bass_ms         int = 400
	chord_ring_ms   int = 1400
	chord_mute_ms   int = 70
	chord_level     int = 3600
	keys_level      int = 2600
	keys_ms         int = 260
	hero_level      int = 5200
	hero_sustain_ms int = 2600
	hero_release_ms int = 50
	echo_delay      int = 4096 // samples
	echo_wet        int = 90   // of 256
	echo_back       int = 110  // feedback, of 256
}

struct Composer {
	name      string
	style     string
	key       int // MIDI note of the key in the bass register
	scale     []int
	hero_base int // MIDI note of degree 0 of the hero part
	bar_steps int
	spb       int // steps per beat
	fps       int // frames per step
	stars     int
	mix       Mix
mut:
	steps []Step
}

// Song is a finished song: the steps and the chart derived from them.
struct Song {
	name      string
	style     string
	fps       int
	spb       int
	bar_steps int
	stars     int
	mix       Mix
	steps     []Step
	notes     []Note
	preview   int // first step of the bars played on the song select screen
	bpm       int
	end_frame int // the frame of the last step
}

// Note is one chart note: when, which lane, and what it sounds.
struct Note {
	frame   int
	lane    int
	pitch   int
	harmony bool // played by the second guitar
}

fn (c &Composer) degree(d int) int {
	octave := if d >= 0 { d / 7 } else { -((-d + 6) / 7) }
	return 12 * octave + c.scale[d - 7 * octave]
}

// melody_note reads a hero token: a scale degree, `,` for an octave down,
// `#` or `b` for a semitone up or down.
fn (c &Composer) melody_note(token string, shift int) int {
	mut t := token
	mut extra := 0
	for t.starts_with(',') {
		extra -= 12
		t = t[1..]
	}
	for t.ends_with('#') {
		extra++
		t = t[..t.len - 1]
	}
	for t.ends_with('b') {
		extra--
		t = t[..t.len - 1]
	}
	return c.hero_base + shift + extra + c.degree(t.int())
}

// harmony_note is the note two scale degrees below a hero token, for the
// second guitar; it keeps to the scale, ignoring accidentals.
fn (c &Composer) harmony_note(token string, shift int) int {
	mut t := token.trim_right('#b')
	mut extra := 0
	for t.starts_with(',') {
		extra -= 12
		t = t[1..]
	}
	return c.hero_base + shift + extra + c.degree(t.int() - 2)
}

// chord_root is a degree's root in the bass register, kept within a fifth
// of the key so the bass line stays put.
fn (c &Composer) chord_root(d int, shift int) int {
	mut semis := c.scale[d % 7]
	if semis > 7 {
		semis -= 12
	}
	return c.key + shift + semis
}

fn tokens(text string) []string {
	return text.split(' ').filter(it != '' && it != '|')
}

fn (mut c Composer) add(s Section) {
	chords := tokens(s.chords)
	hero := tokens(s.hero)
	half := c.bar_steps / 2
	start := c.steps.len
	// A hero line may be longer than its section: a repeat can reuse the
	// start of an earlier line.
	if hero.len > 0 && hero.len < s.bars * c.bar_steps / s.res {
		panic('${c.name}: a hero line of ${hero.len} tokens in a section of ${s.bars * c.bar_steps / s.res}')
	}
	for bar in 0 .. s.bars {
		chord_token := chords[bar % chords.len]
		parts := chord_token.split('/')
		for i in 0 .. c.bar_steps {
			deg := if parts.len > 1 && i >= half { parts[1].int() } else { parts[0].int() }
			root := c.chord_root(deg, s.shift)
			mut st := Step{}
			pattern := if bar == s.bars - 1 && s.fill != '' {
				s.fill
			} else {
				s.drums[bar % s.drums.len]
			}
			st.drums = drum_bits(pattern[i % pattern.len])
			if s.bass != '' {
				match s.bass[i % s.bass.len] {
					`r` { st.bass = u8(root) }
					`o` { st.bass = u8(root + 12) }
					`f` { st.bass = u8(root + 7) }
					`-` { st.flags |= flag_bass_release }
					else {}
				}
			}
			if s.rhythm != '' {
				match s.rhythm[i % s.rhythm.len] {
					`X` {
						st.chord = u8(root + 12)
					}
					`x` {
						st.chord = u8(root + 12)
						st.flags |= flag_chord_mute
					}
					`-` {
						st.flags |= flag_chord_release
					}
					else {}
				}
			}
			if s.keys != '' {
				k := s.keys[i % s.keys.len]
				if k >= `0` && k <= `7` {
					tone := int(k - `0`)
					degrees := [deg, deg + 2, deg + 4, deg + 7]
					semis := c.degree(degrees[tone % 4]) + 12 * (tone / 4)
					st.keys = u8(c.key + 24 + s.shift + semis)
				}
			}
			at := bar * c.bar_steps + i
			if at % s.res == 0 && at / s.res < hero.len {
				token := hero[at / s.res]
				if token == '_' {
					st.flags |= flag_hero_release
				} else if token != '.' {
					pair := token.split('+')
					st.hero = u8(c.melody_note(pair[0], s.shift))
					if pair.len > 1 {
						st.harmony = u8(c.melody_note(pair[1], s.shift))
						st.flags |= flag_harmony_charted
					} else if s.twin {
						st.harmony = u8(c.harmony_note(pair[0], s.shift))
					}
				}
			}
			c.steps << st
		}
	}
	if s.crash {
		c.steps[start].drums |= drum_crash | drum_kick
	}
	if s.event != 0 {
		c.steps[start].event = u8(s.event)
	}
}

fn drum_bits(c u8) u8 {
	return match c {
		`h` { u8(drum_hat) }
		`o` { u8(drum_open_hat) }
		`k` { u8(drum_kick) }
		`K` { u8(drum_kick | drum_hat) }
		`s` { u8(drum_snare) }
		`S` { u8(drum_snare | drum_hat) }
		`b` { u8(drum_kick | drum_snare) }
		`B` { u8(drum_kick | drum_snare | drum_hat) }
		`c` { u8(drum_crash | drum_kick) }
		`C` { u8(drum_crash | drum_kick | drum_snare) }
		`g` { u8(drum_ghost | drum_snare) }
		`t` { u8(drum_tom | drum_snare) }
		`T` { u8(drum_tom | drum_snare | drum_kick) }
		`O` { u8(drum_kick | drum_open_hat) }
		else { u8(0) }
	}
}

// finish ends the song and derives the chart from the hero part.
fn (mut c Composer) finish(preview_bar int) Song {
	mut end := Step{}
	end.event = event_end
	end.flags = flag_hero_release | flag_chord_release | flag_bass_release
	c.steps << end
	return Song{
		name:      c.name
		style:     c.style
		fps:       c.fps
		spb:       c.spb
		bar_steps: c.bar_steps
		stars:     c.stars
		mix:       c.mix
		steps:     c.steps
		notes:     chart(c.steps, c.fps, 2 * c.bar_steps)
		preview:   preview_bar * c.bar_steps
		bpm:       int(3600.0 / f64(c.fps * c.spb) + 0.5)
		end_frame: (c.steps.len - 1) * c.fps
	}
}

// chart turns the hero part into notes. Within each window of steps the
// distinct pitches are ranked, and the ranks spread over the five lanes:
// higher notes are further right, a repeated note stays in its lane.
fn chart(steps []Step, fps int, window int) []Note {
	mut notes := []Note{}
	for start := 0; start < steps.len; start += window {
		stop := if start + window < steps.len { start + window } else { steps.len }
		mut pitches := []int{}
		for st in steps[start..stop] {
			if st.hero != 0 && int(st.hero) !in pitches {
				pitches << int(st.hero)
			}
		}
		pitches.sort()
		for i in start .. stop {
			st := steps[i]
			if st.hero == 0 {
				continue
			}
			rank := pitches.index(int(st.hero))
			mut lane := spread(rank, pitches.len)
			if st.flags & flag_harmony_charted != 0 {
				// A two-note chord: two lanes apart.
				if lane > 2 {
					lane = 2
				}
				notes << Note{
					frame: i * fps
					lane:  lane
					pitch: st.hero
				}
				notes << Note{
					frame:   i * fps
					lane:    lane + 2
					pitch:   st.harmony
					harmony: true
				}
				continue
			}
			notes << Note{
				frame: i * fps
				lane:  lane
				pitch: st.hero
			}
		}
	}
	return notes
}

fn spread(rank int, count int) int {
	return match count {
		1 { 2 }
		2 { [1, 3][rank] }
		3 { [1, 2, 3][rank] }
		4 { [0, 1, 3, 4][rank] }
		5 { rank }
		else { (rank * 4 + (count - 1) / 2) / (count - 1) }
	}
}

// songs returns the five songs, easiest first.
fn songs() []Song {
	return [midnight_engine(), colossus(), iron_gallop(), neon_seraph(),
		omega_overdrive()]
}

// MIDNIGHT ENGINE: a synth-wave anthem in D minor at 112 BPM. Arpeggios
// and four-on-the-floor; the chorus climbs, the last one a tone higher.
fn midnight_engine() Song {
	mut c := Composer{
		name:      'MIDNIGHT ENGINE'
		style:     'SYNTHWAVE ANTHEM'
		key:       38
		scale:     natural_minor
		hero_base: 62
		bar_steps: 16
		spb:       4
		fps:       8
		stars:     1
		mix:       Mix{
			chord_ring_ms:   900
			chord_level:     2600
			keys_level:      2900
			keys_ms:         180
			hero_sustain_ms: 3000
			echo_delay:      7800 // a dotted eighth
			echo_wet:        120
			echo_back:       130
		}
	}
	floor := 'K.o.b.o.K.o.b.o.'
	verse := 'K.h.S.h.K.hKS.h.'
	arp := '0124012401240124'
	pump := 'r.o.r.o.r.o.r.o.'
	c.add(Section{
		bars:   1
		chords: '0'
		drums:  ['h...h...h...h.hh']
		event:  event_ready
		crash:  false
	})
	c.add(Section{
		bars:   4
		chords: '0 5 2 6'
		drums:  ['k...k...k...k...']
		fill:   'k...k...k.s.ssss'
		keys:   arp
		bass:   'r.......r.......'
		hero:   '4 . . . 2 . 0 . | 5 . . . 4 . 2 . | 2 . . . 4 . 6 . | 6 . . . 8 . . _'
	})
	verse_line := '_ 0 2 4 . 2 4 7 | . 5 4 2 . _ 4 5 | 6 . 5 4 . 2 4 . | 1 . . . _ . 0 1 | 2 . 0 2 4 . 2 4 | 5 . 7 . 5 4 2 . | 4 . 2 4 6 . 5 4 | 8 . . . 7 . 6 .'
	c.add(Section{
		bars:   8
		chords: '0 5 2 6'
		drums:  [verse]
		keys:   arp
		bass:   pump
		hero:   verse_line
	})
	c.add(Section{
		bars:   4
		chords: '5 6 0 6'
		drums:  [verse]
		fill:   's.s.s.s.ssssssss'
		keys:   '0123012301230123'
		bass:   'rrrrrrrrrrrrrrrr'
		rhythm: 'x.x.x.x.x.x.x.x.'
		hero:   '2 2 4 . 2 2 5 . | 4 4 6 . 4 4 8 . | 7 . 6 . 4 . 2 . | 1 . 2 . 3 . 4 .'
		event:  event_coming
	})
	chorus := '9 . . . 8 . 9 . | 10 . . . 8 . 6 . | 7 . . . 9 . 11 . | 12 . . . 11 . 9 . | 9 . . 8 9 . 11 . | 10 . . 11 10 . 8 . | 9 . 7 . 9 . 11 . | 12 . . . 11 . 10 .'
	c.add(Section{
		bars:   8
		chords: '2 6 0 5'
		drums:  [floor]
		keys:   arp
		bass:   pump
		rhythm: 'X.......X...X...'
		hero:   chorus
		twin:   true
	})
	c.add(Section{
		bars:   4
		chords: '0 5 2 6'
		drums:  ['k...k...k...k...', 'k...k...k...k...', 'k...k...k...k...', 'k...k...']
		fill:   's...s...s.s.ssss'
		keys:   '0124567401245674'
		hero:   '0 . 4 . 7 . 4 . | 5 . 9 . 12 . 9 . | 2 . 6 . 9 . 6 . | 6 . 8 . 10 . . _'
		event:  event_breakdown
	})
	c.add(Section{
		bars:   8
		chords: '2 6 0 5'
		drums:  [floor]
		keys:   arp
		bass:   pump
		rhythm: 'X.......X...X...'
		hero:   chorus
		twin:   true
		shift:  2
		event:  event_key_change
	})
	c.add(Section{
		bars:   2
		chords: '5 0'
		drums:  ['K.o.b.o.K.o.bbbb', 'c...............']
		rhythm: 'X...............'
		bass:   'r...............'
		keys:   '0123............'
		hero:   '12 . 11 . 10 . 11 . | 0+4 . . . . . . _'
		shift:  2
	})
	return c.finish(13)
}

// COLOSSUS: heavy half-time in C# phrygian. Ringing two-note chords and a
// stomping riff; the last pass goes up a semitone over a blast beat.
fn colossus() Song {
	mut c := Composer{
		name:      'COLOSSUS'
		style:     'HEAVY HALF-TIME'
		key:       37
		scale:     phrygian
		hero_base: 49
		bar_steps: 16
		spb:       4
		fps:       7
		stars:     2
		mix:       Mix{
			bass_ms:         700
			chord_ring_ms:   2400
			chord_mute_ms:   90
			chord_level:     4200
			keys_level:      2000
			keys_ms:         900
			hero_level:      5600
			hero_sustain_ms: 3000
			echo_delay:      6800 // a quarter note
			echo_wet:        80
			echo_back:       100
		}
	}
	half := 'K..kh.k.S...h.k.'
	chug := 'x..x..x.x...x.x.'
	c.add(Section{
		bars:   1
		chords: '0'
		drums:  ['h...h...h...t.tt']
		event:  event_ready
		crash:  false
	})
	c.add(Section{
		bars:   4
		chords: '0 1 0 6'
		drums:  ['c...............']
		fill:   'c...t...T.T.TTTT'
		rhythm: 'X...............'
		bass:   'r...............'
		hero:   '0+4 . . . | 1+5 . . . | 0+4 . . . | 6+10 . . _'
		res:    4
	})
	riff := '0 . . 0 . . 1 . 0 . . . 3 . 2 . | 0 . . 0 . . 1 . 0 . . . 6 . 5 . | 1 . . 1 . . 2 . 1 . . . 4 . 3 . | 0 . . 0 . . 1 . 0+4 . . . . . . . | 0 . . 0 . . 1 . 0 . . . 3 . 2 . | 0 . . 0 . . 1 . 0 . . . 6 . 5 . | 6 . . 6 . . 5 . 6 . . . 8 . 7 . | 0+4 . . . . . . . 1+5 . . . . . _ .'
	c.add(Section{
		bars:   8
		chords: '0 0 1 0 0 0 6 0/1'
		drums:  [half]
		rhythm: chug
		bass:   'r..r..r.r...r.r.'
		hero:   riff
		res:    1
	})
	c.add(Section{
		bars:   8
		chords: '0 0 1 1 0 0 6 6'
		drums:  ['K...h.k.S...h...', 'K..kh...S...h.k.']
		fill:   'K...h.k.S.s.ssss'
		rhythm: 'x..x..x.x..x..x.'
		bass:   'r..r..r.r..r..r.'
		keys:   '0.......2.......'
		hero:   '7 . . . 8 . . . | 7 . 5 . 4 . . . | 8 . . . 9 . . . | 8 . 7 . 5 . . . | 7 . . . 8 . 10 . | 11 . 10 . 8 . 7 . | 6 . . . 5 . 4 . | 3 . . . _ . . .'
	})
	c.add(Section{
		bars:   4
		chords: '0 0 0 1'
		drums:  ['K.......S.......']
		fill:   'K.....k.S.s.ssss'
		rhythm: 'X..X..X.....X...'
		bass:   'r..r..r.....r...'
		hero:   '0+4 . . 0+4 . . 0+4 . . . . . 1+5 . . . | 0+4 . . 0+4 . . 0+4 . . . . . 6+10 . . . | 0+4 . . 0+4 . . 0+4 . . . . . 1+5 . . . | 1+5 . . 1+5 . . 1+5 . 3+7 . . . 2+6 . 1+5 .'
		res:    1
		event:  event_breakdown
	})
	c.add(Section{
		bars:   8
		chords: '0 0 1 0 0 0 6 0/1'
		drums:  ['KhShKhShKhShKhSh']
		fill:   'KhShKhShS.s.ssss'
		rhythm: chug
		bass:   'r..r..r.r...r.r.'
		hero:   riff
		res:    1
		shift:  1
		event:  event_power
	})
	c.add(Section{
		bars:   4
		chords: '0 1 0 0'
		drums:  ['c.......S.......', 'c.......S.......', 'c...t.t.T.T.TTTT', 'c...............']
		rhythm: 'X...............'
		bass:   'r...............'
		hero:   '0+4 . . . | 1+5 . . . | 0+4 . . . | 0+4 . . _'
		res:    4
		shift:  1
	})
	return c.finish(5)
}

// IRON GALLOP: driving rock in E minor at 150 BPM, galloping bass drum
// and chugs, a twin-guitar chorus, a solo, and the last chorus a tone up.
fn iron_gallop() Song {
	mut c := Composer{
		name:      'IRON GALLOP'
		style:     'GALLOPING ROCK'
		key:       40
		scale:     natural_minor
		hero_base: 64
		bar_steps: 16
		spb:       4
		fps:       6
		stars:     3
		mix:       Mix{
			chord_mute_ms:   55
			chord_level:     3800
			hero_level:      5000
			hero_sustain_ms: 2000
			echo_delay:      5200 // a dotted eighth
			echo_wet:        70
			echo_back:       90
		}
	}
	gallop := 'K.kkS.kkK.kkS.kk'
	rock := 'K.h.S.hKK.h.S.h.'
	chugs := 'x.xxx.xxx.xxx.xx'
	gallop_bass := 'r.rrr.rrr.rrr.rr'
	c.add(Section{
		bars:   1
		chords: '0'
		drums:  ['h...h...h...h.h.']
		event:  event_ready
		crash:  false
	})
	c.add(Section{
		bars:   4
		chords: '0 0 5 6'
		drums:  [gallop]
		fill:   'K.kkS.kkt.t.T.TT'
		rhythm: chugs
		bass:   gallop_bass
		hero:   '7 . 6 . 7 . 4 . | 5 . 4 . 2 . 4 . | 5 . 4 . 5 . 7 . | 8 . 7 . 6 . 4 .'
	})
	verse := '0 . 0 2 3 . 2 0 | 4 . 3 2 0 . _ . | 5 . 5 4 3 . 4 5 | 6 . . . _ . 4 6 | 7 . 6 4 3 . 4 6 | 7 . 6 4 3 . 2 0 | 3 . 2 3 5 . 4 3 | 4 . 2 . ,6# . . .'
	c.add(Section{
		bars:   8
		chords: '0 0 5 6 0 0 3 4'
		drums:  [rock]
		fill:   'K.h.S.hKS.SsS.ss'
		rhythm: chugs
		bass:   gallop_bass
		hero:   verse
	})
	chorus := '7 . . . 9 . 7 . | 8 . . . 10 . 8 . | 9 . 8 . 7 . 6 . | 7 . . . . . _ . | 7 . . 7 9 . 11 . | 12 . 11 . 10 . 8 . | 11 . . . 8 . 6# . | 11 . . . . . _ .'
	c.add(Section{
		bars:   8
		chords: '5 6 0 0 5 6 4 4'
		drums:  [gallop]
		fill:   'K.kkS.kkS.SsS.SS'
		rhythm: 'X.xxx.xxX.xxx.xx'
		bass:   gallop_bass
		keys:   '0...2...3...2...'
		hero:   chorus
		twin:   true
	})
	c.add(Section{
		bars:   8
		chords: '0 5 6 0 0 5 6 4'
		drums:  [gallop]
		fill:   'K.kkS.kkt.t.T.TT'
		rhythm: chugs
		bass:   gallop_bass
		hero:   '7 . 6 . 7 . 4 . 3 4 3 2 0 . . . | 5 . 4 . 5 . 7 . 9 8 7 5 4 . . . | 6 . 8 . 10 . 8 . 6 5 4 3 2 . . . | 0 . 2 . 4 . 7 . 4 . 7 . 9 . 11 . | 14 . 11 . 9 . 7 . 11 . 9 . 7 . 4 . | 12 . 11 9 7 . 9 11 12 . 11 9 7 . . . | 13 . 12 10 8 . 10 12 13 . 12 10 8 . . . | 11 . . . 10 . . . 8 . . . 6# . . .'
		res:    1
		event:  event_solo
	})
	c.add(Section{
		bars:   4
		chords: '0 0 5 6'
		drums:  [rock]
		fill:   'K.kkS.kkS.SsS.SS'
		rhythm: chugs
		bass:   gallop_bass
		hero:   verse
	})
	c.add(Section{
		bars:   8
		chords: '5 6 0 0 5 6 4 4'
		drums:  [gallop]
		fill:   'K.kkS.kkS.SsS.SS'
		rhythm: 'X.xxx.xxX.xxx.xx'
		bass:   gallop_bass
		keys:   '0...2...3...2...'
		hero:   chorus
		twin:   true
		shift:  2
		event:  event_key_change
	})
	c.add(Section{
		bars:   2
		chords: '0 0'
		drums:  ['K.kkS.kkK.kkC...', 'c...............']
		rhythm: 'x.xxx.xxx.xxX...'
		bass:   'r.rrr.rrr.rrr...'
		hero:   '7 . 6 . 7 . 11 . | 7+11 . . . . . . _'
		shift:  2
	})
	return c.finish(13)
}

// NEON SERAPH: neo-classical shred in A harmonic minor, 150 BPM in
// triplets. Harpsichord sweeps underneath, a run section, a key change.
fn neon_seraph() Song {
	mut c := Composer{
		name:      'NEON SERAPH'
		style:     'NEO-CLASSICAL SHRED'
		key:       45
		scale:     harmonic_minor
		hero_base: 57
		bar_steps: 24
		spb:       6
		fps:       4
		stars:     4
		mix:       Mix{
			bass_ms:         250
			chord_level:     3000
			keys_level:      2400
			keys_ms:         110
			hero_level:      4800
			hero_sustain_ms: 1800
			hero_release_ms: 40
			echo_delay:      5541 // two triplet eighths
			echo_wet:        100
			echo_back:       120
		}
	}
	drive := 'K.k.k.S.k.k.K.k.k.S.k.k.'
	sweep := '012321012321012321012321'
	triplets := 'r.r.r.r.r.r.r.r.r.r.r.r.'
	c.add(Section{
		bars:   1
		chords: '0'
		drums:  ['h.....h.....h.....h.h.h.']
		event:  event_ready
		crash:  false
	})
	c.add(Section{
		bars:   4
		chords: '0 3 4 0'
		drums:  ['K.....h.....S.....h.....']
		fill:   'K.....h.....S.....s.s.s.'
		keys:   sweep
		bass:   'r...........r...........'
		hero:   '7 . 6 . | 5 . 3 . | 4 . 6 . | 7 . . _'
		res:    6
	})
	theme_a := '7 . 9 11 . 9 7 9 11 14 . . | 12 . 10 7 . 10 12 10 7 5 . . | 6 . 8 11 . 8 6 8 11 13 . . | 14 . 13 11 . 9 7 . . _ . . | 12 . 9 5 . 9 12 14 12 9 . . | 10 . 12 14 . 12 10 9 7 5 . . | 4 . 6 8 . 11 13 11 8 6 . . | 4 . . 8 . . 11 . . 13 . .'
	c.add(Section{
		bars:   8
		chords: '0 3 4 0 5 3 4 4'
		drums:  [drive]
		fill:   'K.k.k.S.k.k.s.s.s.ssssss'
		keys:   sweep
		bass:   triplets
		rhythm: 'X.....x.x.x.X.....x.x.x.'
		hero:   theme_a
	})
	c.add(Section{
		bars:   8
		chords: '5 2 3 0 5 2 4 4'
		drums:  ['K.....k.k.S.....k.k.k.S.']
		keys:   '012345543210012345543210'
		bass:   'r.....r.....r.....r.....'
		rhythm: 'X.....................-.'
		hero:   '9 . . . . 12 11 . 9 7 . . | 9 . . . . 11 9 . 7 9 . . | 10 . . . . 12 10 . 9 7 . . | 7 . . 4 . . 7 . 9 11 . . | 12 . . . . 14 12 . 11 9 . . | 11 . . . . 9 11 . 12 14 . . | 13 . 11 13 . 15 13 . 11 8 . . | 11 . . . . . 13 . . . . _'
		twin:   true
	})
	c.add(Section{
		bars:   8
		chords: '0 3 4 0 0 3 4 4'
		drums:  [drive]
		fill:   'K.k.k.S.k.k.s.s.s.ssssss'
		keys:   sweep
		bass:   triplets
		rhythm: 'x.x.x.x.x.x.x.x.x.x.x.x.'
		hero:   '7 9 11 14 11 9 7 9 11 14 11 9 | 5 7 10 12 10 7 5 7 10 12 10 7 | 4 6 8 11 8 6 4 6 8 11 13 11 | 7 . . 9 11 14 11 9 7 4 . . | 14 13 12 11 12 11 10 9 8 7 . . | 12 11 10 9 10 9 8 7 6 5 . . | 6 8 11 13 11 8 6 8 11 13 . . | 11 . . 13 . . 15 . . . . _'
		event:  event_shred
	})
	c.add(Section{
		bars:   4
		chords: '5 6 4 4'
		drums:  ['K.....h.....S.....h.....']
		fill:   'K.....k.....S.s.s.ssssss'
		keys:   sweep
		bass:   'r...........r...........'
		hero:   '12 . 11 . | 9 . 8 . | 11 . 13 . | 15 . . _'
		res:    6
		event:  event_coming
	})
	c.add(Section{
		bars:   8
		chords: '0 3 4 0 5 3 4 4'
		drums:  [drive]
		fill:   'K.k.k.S.k.k.s.s.s.ssssss'
		keys:   sweep
		bass:   triplets
		rhythm: 'X.....x.x.x.X.....x.x.x.'
		hero:   theme_a
		twin:   true
		shift:  2
		event:  event_key_change
	})
	c.add(Section{
		bars:   2
		chords: '4 0'
		drums:  ['K.k.k.S.k.k.K.k.k.C.....', 'c.......................']
		rhythm: 'X.....................-.'
		bass:   'r.......................'
		keys:   '0123....................'
		hero:   '4 . 6 . | 7+11 . . _'
		res:    6
		shift:  2
	})
	return c.finish(13)
}

// OMEGA OVERDRIVE: the finale. F# minor at 180 BPM over a d-beat, tremolo
// chugs, a blast-beat solo, and two key changes on the way out.
fn omega_overdrive() Song {
	mut c := Composer{
		name:      'OMEGA OVERDRIVE'
		style:     'FRANTIC FINALE'
		key:       42
		scale:     natural_minor
		hero_base: 54
		bar_steps: 16
		spb:       4
		fps:       5
		stars:     5
		mix:       Mix{
			bass_ms:         220
			chord_mute_ms:   45
			chord_level:     3400
			hero_level:      5000
			hero_sustain_ms: 1600
			hero_release_ms: 40
			echo_delay:      3463 // an eighth note
			echo_wet:        70
			echo_back:       80
		}
	}
	dbeat := 'KhShKhShKhShKhSh'
	drive := 'K.S.K.S.K.S.K.SK'
	tremolo := 'xxxxxxxxxxxxxxxx'
	eighths := 'r.r.r.r.r.r.r.r.'
	c.add(Section{
		bars:   1
		chords: '0'
		drums:  ['h...h...h...hhhh']
		event:  event_ready
		crash:  false
	})
	c.add(Section{
		bars:   4
		chords: '0 5 6 0'
		drums:  [drive]
		fill:   'K.S.K.S.S.SsSSSS'
		rhythm: tremolo
		bass:   eighths
		hero:   '7 . 7 . 9 . 10 . | 12 . 10 . 9 . 7 . | 8 . 9 . 11 . 9 . | 7 . . . _ . . .'
	})
	verse := '0 . 2 3 4 . 3 2 | 0 . 2 3 4 . 7 . | 5 . 4 3 2 . 3 4 | 6 . . . 4 . 6 . | 7 . 6 4 3 . 4 6 | 7 . 9 . 7 . 4 . | 3 . 5 . 7 . 8 . | 4 . 6# . 8 . 11 .'
	c.add(Section{
		bars:   8
		chords: '0 0 5 6 0 0 3 4'
		drums:  [dbeat]
		fill:   'KhShKhShS.SsS.SS'
		rhythm: 'x.x.x.x.x.x.x.x.'
		bass:   eighths
		hero:   verse
	})
	chorus := '12 . . . 11 . 12 . 14 . . . 12 . 11 . | 13 . . . 12 . 13 . 15 . . . 13 . 12 . | 14 . . . 12 . 11 . 9 . 10 . 11 . 12 . | 14 . . . . . . . _ . . . 7 9 11 12 | 12 . . . 11 . 12 . 14 . . . 16 . 14 . | 13 . . . 12 . 13 . 15 . . . 16 . 15 . | 11 . . . 13# . . . 15 . . . 13# . . . | 11 . 13# . 15 . 18 . _ . . . . . . .'
	c.add(Section{
		bars:   8
		chords: '5 6 0 0 5 6 4 4'
		drums:  [drive]
		fill:   'K.S.K.S.S.SsSSSS'
		rhythm: 'X.x.x.x.X.x.x.x.'
		bass:   'rrrrrrrrrrrrrrrr'
		keys:   '0.2.3.2.0.2.3.2.'
		hero:   chorus
		res:    1
		twin:   true
	})
	c.add(Section{
		bars:   4
		chords: '0 0 5 6'
		drums:  [dbeat]
		fill:   'KhShKhShS.SsS.SS'
		rhythm: 'x.x.x.x.x.x.x.x.'
		bass:   eighths
		hero:   verse
	})
	c.add(Section{
		bars:   4
		chords: '3 5 6 6'
		drums:  ['K...h...S...h...']
		fill:   'K...h...S.s.ssss'
		rhythm: 'X.......X.......'
		bass:   'r.......r.......'
		keys:   '0123456701234567'
		hero:   '10 9 7 9 | 12 10 9 10 | 13 12 10 12 | 13 . . _'
		res:    4
		event:  event_breakdown
	})
	c.add(Section{
		bars:   8
		chords: '0 5 6 0 0 5 6 4'
		drums:  ['bhbhbhbhbhbhbhbh']
		fill:   'bhbhbhbhS.SsSSSS'
		rhythm: tremolo
		bass:   'rrrrrrrrrrrrrrrr'
		hero:   '7 9 10 12 14 12 10 9 7 . . . 7 . . . | 5 7 9 10 12 10 9 7 5 . . . 5 . . . | 6 8 10 11 13 11 10 8 6 . . . 13 . . . | 14 . 13 . 12 . 11 . 10 . 9 . 8 . 7 . | 7 . 10 . 14 . 10 . 7 . 10 . 14 . 17 . | 5 . 9 . 12 . 9 . 5 . 9 . 12 . 16 . | 6 . 10 . 13 . 10 . 6 . 10 . 13 . 17 . | 11 . . . 13# . . . 15 . . . 18 . . .'
		res:    1
		shift:  2
		event:  event_solo
	})
	c.add(Section{
		bars:   8
		chords: '5 6 0 0 5 6 4 4'
		drums:  [drive]
		fill:   'K.S.K.S.S.SsSSSS'
		rhythm: 'X.x.x.x.X.x.x.x.'
		bass:   'rrrrrrrrrrrrrrrr'
		keys:   '0.2.3.2.0.2.3.2.'
		hero:   chorus
		res:    1
		twin:   true
		shift:  4
		event:  event_final
	})
	c.add(Section{
		bars:   4
		chords: '5 6 0 0'
		drums:  ['bhbhbhbhbhbhbhbh', 'bhbhbhbhbhbhbhbh', 'K.S.K.S.S.SsSSSS', 'c...............']
		rhythm: 'X.x.x.x.X.x.x.x.'
		bass:   'r.r.r.r.r.r.r.r.'
		hero:   '12 . 13 . 14 . . . | 13 . 14 . 16 . . . | 14 . . . . . . . | 7+11 . . . . . . _'
		shift:  4
	})
	return c.finish(14)
}
