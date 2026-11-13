// JAGUAR HERO: a rhythm game for the Atari Jaguar, written as a V program
// that assembles itself. Run it to produce the image:
//
//     v run demos/hero            # writes demos/hero.jag
//
// The DSP is a ten-voice synthesizer, the 68000 runs the sequencer, judges
// the player and builds a display list every frame; the object processor
// draws the highway, the notes and everything else from it. songs.v holds
// the five songs, art.v computes every picture and table.
module main

import os
import math
import jagkit

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/hero.jag' }
	built := build() or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(output, built.image) or {
		eprintln(err)
		exit(1)
	}
	println('${output}: ${built.image.len} bytes')
}

// whole_longs pads a program to a multiple of four bytes, for copying.
fn whole_longs(code []u8) []u8 {
	mut padded := code.clone()
	for padded.len % 4 != 0 {
		padded << 0
	}
	return padded
}

// Built is the finished image, where its 68000 labels ended up, and the
// songs it holds.
struct Built {
	image   []u8
	symbols map[string]u32
	songs   []Song
}

fn build() !Built {
	all := songs()
	mut dsp := synthesizer()
	dsp_code := whole_longs(dsp.assemble()!)
	if dsp_code.len > jagkit.dsp_ram_size {
		return error('the DSP program does not fit its RAM')
	}
	mut m := jagkit.new_m68k(load_address)
	mut g := Game{
		m:       m
		voices:  dsp.address_of('voice_0')
		globals: dsp.address_of('globals')
	}
	g.start_up(dsp_code.len / 4, dsp.address_of('start'))
	g.frame_interrupt()
	g.read_pad()
	g.menus()
	g.sequencer()
	g.start_song()
	g.play_state()
	g.judge()
	g.effects()
	g.hud()
	g.results()
	g.colours()
	g.emitter()
	g.list_builder()
	g.beams()
	g.scenes()
	g.text_routines()
	g.variables()
	g.pal_timing()
	g.strings()
	g.tables()
	g.song_data(all)!
	m.label('dsp_program')
	m.bytes(dsp_code)
	g.pictures()!
	g.profiles()!
	payload := m.assemble()!
	// Nothing the program writes to may lie on top of the image or of
	// anything else.
	jagkit.check_regions([
		jagkit.Region{'image', load_address, payload.len},
		jagkit.Region{'display list a', list_a, 32 + list_slots * 32},
		jagkit.Region{'display list b', list_b, 32 + list_slots * 32},
		jagkit.Region{'text', text_address, text_bytes},
		jagkit.Region{'echo', echo_address, echo_mask + 2},
		jagkit.Region{'note state', note_state, max_notes},
	])!
	return Built{
		image:   jagkit.jag_image(load_address, m.address_of('entry'), payload)
		symbols: m.symbols()
		songs:   all
	}
}

fn (mut g Game) strings() {
	mut m := g.m
	m.label('text_blank')
	m.text(' ')
	m.label('text_arrow')
	m.text('~')
	m.label('text_block')
	m.text('|')
	m.label('text_bpm')
	m.text('BPM')
	m.label('text_best')
	m.text('BEST')
	m.label('stars_text')
	for stars in 1 .. 6 {
		m.text('@'.repeat(stars) + '^'.repeat(5 - stars))
	}
	for i, text in event_texts {
		m.label('event_${i}')
		pad := (20 - text.len) / 2
		m.text((' '.repeat(pad) + text + ' '.repeat(20)).substr(0, 20))
	}
	m.align(4)
	m.label('event_texts')
	for i in 0 .. event_texts.len {
		m.long_label('event_${i}')
	}
}

fn words(values []int) []u8 {
	mut out := []u16{}
	for v in values {
		out << u16(v)
	}
	return jagkit.big_endian16(out)
}

// place is a table entry for an object centred on (x, y) at a scale: x,
// half-line and scale words, and a pad.
fn place(x f64, y f64, width int, height int, scale f64) []int {
	s := fixed_3_5(scale)
	actual := f64(s) / 32
	return [int(x - width * actual / 2 + 0.5), int((y - height * actual / 2) * 2 + 0.5), s | (s << 8),
		0]
}

fn (mut g Game) tables() {
	mut m := g.m
	m.align(4)
	m.label('midi_steps')
	mut steps := []u32{}
	for note in 0 .. 128 {
		steps << phase_step(midi_hertz(note))
	}
	m.bytes(jagkit.big_endian32(steps))
	m.label('lane_table')
	m.bytes(jagkit.big_endian16(lane_colours()))
	m.label('target_table')
	m.bytes(jagkit.big_endian16(target_colours()))
	m.label('rail_table')
	m.bytes(jagkit.big_endian16(rail_colours()))
	m.label('background_table')
	m.bytes(jagkit.big_endian16(background_colours()))
	m.label('meter_table')
	m.bytes(jagkit.big_endian16(meter_colours()))
	m.label('rainbow')
	m.bytes(jagkit.big_endian16(rainbow(64)))
	m.label('attract_wave')
	for i in 0 .. 64 {
		wave := math.max(0.0, math.sin(2 * math.pi * f64(i) / 64))
		m.byte(int(wave * wave * 11))
	}
	m.label('judge_points')
	m.bytes(words(judge_points))
	m.label('judge_health')
	m.bytes(words(judge_health))
	m.label('tier_factors')
	m.bytes(words(tier_factors))
	m.label('font')
	m.bytes(jagkit.big_endian16(font_2bpp()))
	// Where the bursts go: big for a perfect, smaller otherwise.
	m.label('burst_place')
	for scale in [1.35, 0.95] {
		for lane in 0 .. lanes {
			m.bytes(words(place(lane_centre(lane), strike_row, burst_size, burst_size, scale)))
		}
	}
	// The judgement lands big and settles.
	m.label('pop_table')
	for i in 0 .. judge_words.len {
		word := judge_word(i)
		for t in 0 .. judge_frames_shown {
			m.bytes(words(place(160, 128, word.width, word.height, pop_scale(t))))
		}
	}
	// The rank falls into place.
	m.label('rank_place')
	letter := rank_letter(0)
	for t in 0 .. 64 {
		k := math.max(0.0, 1 - f64(t) / 14)
		m.bytes(words(place(246, 104, letter.width, letter.height, 2.0 + 3.5 * k * k)))
	}
	// The logo breathes with the beat.
	m.label('logo_place')
	for line, picture in logos() {
		for phase in 0 .. 16 {
			pulse := math.pow(1 - f64(phase) / 16, 3)
			y := [34.0, 98.0][line]
			m.bytes(words(place(160, y, picture.width, picture.height, 1.0 + 0.06 * pulse)))
		}
	}
	// Links: each object slot of a list points at the next.
	for name, list in {
		'links_a': list_a
		'links_b': list_b
	} {
		m.label(name)
		mut links := []u32{}
		for slot in 0 .. list_slots {
			next := list + u32(prefix_bytes + 32 * (slot + 1))
			links << next >> 11
			links << ((next >> 3) & 0xff) << 24
		}
		m.bytes(jagkit.big_endian32(links))
	}
}

fn logos() []Picture {
	return [block_text('JAGUAR', 5, chrome), block_text('HERO', 9, fire)]
}

// look_ahead is how many frames of a song the highway shows.
fn look_ahead(s Song) int {
	return view_beats * s.fps * s.spb
}

fn (mut g Game) song_data(all []Song) ! {
	mut m := g.m
	for i, s in all {
		if s.notes.len >= max_notes {
			return error('${s.name} has too many notes')
		}
		m.align(4)
		m.label('steps_${i}')
		for st in s.steps {
			m.bytes(st.bytes())
		}
		m.label('chart_${i}')
		for n in s.notes {
			m.word(n.frame)
			m.byte(n.lane)
			voice := if n.harmony { 0x80 } else { 0 }
			m.byte(n.pitch | voice)
		}
		for _ in 0 .. 4 {
			m.word(0x7fff)
			m.word(0)
		}
		m.label('view_${i}')
		m.bytes(view_bytes(view_table(look_ahead(s))))
		m.label('phase_${i}')
		beat := s.fps * s.spb
		for t in 0 .. 64 {
			m.byte(clampi(t * 16 / beat, 0, 15))
		}
		m.label('name_${i}')
		m.text(s.name)
		m.label('style_${i}')
		m.text(s.style)
		m.align(4)
		m.label('setup_${i}')
		mix := s.mix
		mut setup := [][]u32{}
		setup << [g.voices + u32(voice_kick * voice_bytes + v_step), phase_step(46)]
		setup << [g.voices + u32(voice_kick * voice_bytes + v_sweep), phase_step(46 * 5)]
		setup << [g.voices + u32(voice_kick * voice_bytes + v_level), u32(11000)]
		setup << [g.voices + u32(voice_kick * voice_bytes + v_rate), u32(decay_rate(220))]
		setup << [g.voices + u32(voice_snare * voice_bytes + v_rate), u32(decay_rate(120))]
		setup << [g.voices + u32(voice_snare * voice_bytes + v_sweep), phase_step(150)]
		setup << [g.voices + u32(voice_hat * voice_bytes + v_level), u32(2400)]
		setup << [g.voices + u32(voice_crash * voice_bytes + v_level), u32(3000)]
		setup << [g.voices + u32(voice_crash * voice_bytes + v_rate), u32(decay_rate(900))]
		setup << [g.voices + u32(voice_bass * voice_bytes + v_level), u32(6000)]
		setup << [g.voices + u32(voice_chord * voice_bytes + v_level), u32(mix.chord_level)]
		setup << [g.voices + u32(voice_keys * voice_bytes + v_level), u32(mix.keys_level)]
		setup << [g.voices + u32(voice_keys * voice_bytes + v_rate), u32(decay_rate(mix.keys_ms))]
		delay := u32(math.min(mix.echo_delay, 8000) * 2)
		setup << [g.globals + u32(g_delay1), delay]
		setup << [g.globals + u32(g_delay2), (delay * 3 / 4) & ~u32(1)]
		setup << [g.globals + u32(g_back), u32(mix.echo_back)]
		setup << [g.globals + u32(g_wet), u32(mix.echo_wet)]
		for pair in setup {
			m.long(pair[0])
			m.long(pair[1])
		}
		m.long(0)
	}
	m.label('song_table')
	for i, s in all {
		mix := s.mix
		for name in ['steps', 'chart', 'view', 'name', 'setup', 'phase', 'style'] {
			m.long_label('${name}_${i}')
		}
		values := [s.steps.len, s.notes.len, s.fps, s.spb, s.fps * s.spb, look_ahead(s),
			s.preview, preview_bars * s.bar_steps, s.bpm, s.stars]
		for v in values {
			m.long(u32(v))
		}
		m.long(phase_step(190)) // snare
		m.long(phase_step(98)) // tom
		m.long(u32(7000))
		m.long(u32(2200))
		m.long(u32(decay_rate(28)))
		m.long(u32(decay_rate(170)))
		m.long(u32(decay_rate(mix.bass_ms)))
		m.long(u32(decay_rate(mix.chord_ring_ms)))
		m.long(u32(decay_rate(mix.chord_mute_ms)))
		m.long(u32(mix.hero_level))
		m.long(u32(mix.hero_level * 7 / 10))
		m.long(u32(decay_rate(mix.hero_sustain_ms)))
		m.long(u32(decay_rate(mix.hero_release_ms)))
		m.long(u32(decay_rate(60)))
		m.long(u32(s.end_frame))
		m.long(u32(i * 2 * background_phases * background_colours * 2))
	}
}

// template is an object's three phrases with the link and position left
// for the 68000 to fill in.
fn template(b jagkit.Bitmap, rmw bool) ![]u8 {
	list := jagkit.object_list(0, jagkit.ntsc, [b])!
	mut bytes := list.bytes[32..32 + template_bytes].clone()
	bytes[4] = 0
	bytes[3] = 0
	bytes[2] &= 0xf8
	bytes[22] = 0 // the scale, too, is the 68000's to fill in
	bytes[23] = 0
	if rmw {
		bytes[10] |= 0x40
	}
	return bytes
}

fn (mut g Game) picture(name string, p Picture) {
	g.m.align(8)
	g.m.label(name)
	g.m.bytes(jagkit.big_endian16(p.pixels))
}

fn (mut g Game) pictures() ! {
	mut m := g.m
	m.align(8)
	m.label('stage')
	m.bytes(stage())
	m.label('meter_bar')
	m.bytes(meter_bar())
	m.label('meter_frame')
	m.bytes(meter_frame())
	mut gems := []Picture{}
	for lane in 0 .. lanes {
		for fog in 0 .. 3 {
			gems << gem(lane, fog)
		}
	}
	for i, p in gems {
		g.picture('gem_${i}', p)
	}
	g.picture('gem_grey', gem(-1, 1))
	g.picture('line_beat', beat_line(false))
	g.picture('line_bar', beat_line(true))
	mut bursts := []Picture{}
	for lane in 0 .. lanes {
		for frame in 0 .. burst_frames {
			bursts << burst(lane, frame)
		}
	}
	for i, p in bursts {
		g.picture('burst_${i}', p)
	}
	mut judged := []Picture{}
	for i in 0 .. judge_words.len {
		judged << judge_word(i)
	}
	for i, p in judged {
		g.picture('judge_${i}', p)
	}
	mut digits := []Picture{}
	for hot in [false, true] {
		for c in digit_glyphs {
			digits << big_digit(c, hot)
		}
	}
	for i, p in digits {
		g.picture('digit_${i}', p)
	}
	mut ranks := []Picture{}
	for i in 0 .. rank_letters.len {
		ranks << rank_letter(i)
	}
	for i, p in ranks {
		g.picture('rank_${i}', p)
	}
	mut beams := []Picture{}
	for side in 0 .. 2 {
		for level in 0 .. beam_levels {
			beams << beam(side, level)
		}
	}
	for i, p in beams {
		g.picture('beam_${i}', p)
	}
	title := logos()
	for i, p in title {
		g.picture('logo_${i}', p)
	}

	// The templates.
	m.align(4)
	m.label('tpl_stage')
	m.bytes(template(jagkit.Bitmap{
		width:  screen_width
		height: screen_height
		data:   m.address_of('stage')
		depth:  .bpp8
	}, false)!)
	for name, palette in {
		'tpl_text':   0
		'tpl_shadow': clut_shadow - 1
	} {
		m.label(name)
		m.bytes(template(jagkit.Bitmap{
			width:       screen_width
			height:      screen_height
			data:        text_address
			depth:       .bpp2
			palette:     palette
			transparent: true
		}, false)!)
	}
	m.label('tpl_meter')
	mut meter := template(jagkit.Bitmap{
		width:  meter_width
		height: 1
		data:   m.address_of('meter_bar')
		depth:  .bpp8
	}, false)!
	meter[5] = 0
	meter[6] &= 0x3f
	m.bytes(meter)
	m.label('tpl_frame')
	m.bytes(template(jagkit.Bitmap{
		width:       meter_frame_width
		height:      meter_height + 4
		data:        m.address_of('meter_frame')
		depth:       .bpp8
		transparent: true
	}, false)!)
	g.sprites('tpl_gems', 'gem', gems, false)!
	g.sprite('tpl_grey', 'gem_grey', gem(-1, 1), false)!
	g.sprite('tpl_line', 'line_beat', beat_line(false), true)!
	g.sprite('tpl_bar', 'line_bar', beat_line(true), true)!
	g.sprites('tpl_bursts', 'burst', bursts, false)!
	g.sprites('tpl_judge', 'judge', judged, false)!
	g.sprites('tpl_digits', 'digit', digits, false)!
	g.sprites('tpl_ranks', 'rank', ranks, false)!
	g.sprites('tpl_logo', 'logo', title, false)!
	g.sprites('tpl_beams', 'beam', beams, true)!
}

// sprite emits the template of a scaled, transparent picture.
fn (mut g Game) sprite(name string, picture string, p Picture, rmw bool) ! {
	g.m.label(name)
	g.m.bytes(template(jagkit.Bitmap{
		width:       p.width
		height:      p.height
		data:        g.m.address_of(picture)
		transparent: true
		hscale:      1
		vscale:      1
	}, rmw)!)
}

fn (mut g Game) sprites(name string, prefix string, pictures []Picture, rmw bool) ! {
	g.m.label(name)
	for i, p in pictures {
		g.m.bytes(template(jagkit.Bitmap{
			width:       p.width
			height:      p.height
			data:        g.m.address_of('${prefix}_${i}')
			transparent: true
			hscale:      1
			vscale:      1
		}, rmw)!)
	}
}

// profiles holds what differs between the television standards: the
// display window, where the picture sits in it, and the start of the
// display lists.
fn (mut g Game) profiles() ! {
	mut m := g.m
	for video in [jagkit.ntsc, jagkit.pal] {
		m.label('profile_${video.name.to_lower()}')
		m.word(video.hdb)
		m.word(video.hde)
		m.word(video.vdb)
		m.word(video.vde | 1)
		m.word((video.width - screen_width) / 2)
		m.word(video.vdb + (video.height - screen_height) / 2 * 2)
		for list in [list_a, list_b] {
			m.bytes(jagkit.object_list(list, video, [])!.bytes)
		}
	}
}
