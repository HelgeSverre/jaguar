module main

import os
import cli
import jerry
import loader
import machine

// The game is tested by playing it: the image is built, booted in the
// emulator and played by a robot that reads the chart out of the game's
// memory through the assembler's symbol table.
//
// HERO_SHOTS=dir also writes screenshots of the title, song select, play
// and results screens there.

const lane_keys = [jerry.Button.one, .two, .three, .four, .five]
const frame_cycles = 221_000 // the 68000's cycles in an NTSC frame, roughly

struct Player {
	symbols map[string]u32
	songs   []Song
mut:
	m       &machine.Machine
	run     int // frames run since boot
	loudest int
	samples i64
	audio   []i16 // everything heard, when HERO_WAV asks for it
}

fn boot() Player {
	built := build() or { panic(err) }
	plan := loader.plan(built.image, loader.Options{}) or { panic(err) }
	mut m := machine.new(machine.Config{})
	m.load_direct(plan)
	return Player{
		symbols: built.symbols
		songs:   built.songs
		m:       m
	}
}

fn (p &Player) word(name string) int {
	return int(p.m.peek32(p.symbols[name]) >> 16)
}

fn (p &Player) long(name string) u32 {
	return p.m.peek32(p.symbols[name])
}

fn (mut p Player) frames(count int) {
	mut audio := []i16{len: 4096}
	for _ in 0 .. count {
		p.m.run_frame()
		p.run++
		got := p.m.drain_audio(mut audio)
		if os.getenv('HERO_WAV') != '' {
			p.audio << audio[..got * 2]
		}
		for s in audio[..got * 2] {
			level := if s < 0 { -int(s) } else { int(s) }
			if level > p.loudest {
				p.loudest = level
			}
			p.samples++
		}
	}
}

fn (mut p Player) tap(button jerry.Button) {
	p.m.set_button(0, button, true)
	p.frames(3)
	p.m.set_button(0, button, false)
	p.frames(3)
}

// save_wav writes what was heard as a 16-bit stereo WAV file.
fn (p &Player) save_wav(name string) {
	dir := os.getenv('HERO_WAV')
	if dir == '' {
		return
	}
	rate := u32(p.m.audio_rate())
	mut b := []u8{}
	data_bytes := u32(p.audio.len * 2)
	put := fn (mut b []u8, v u32, n int) {
		for i in 0 .. n {
			b << u8(v >> (8 * i))
		}
	}
	b << 'RIFF'.bytes()
	put(mut b, 36 + data_bytes, 4)
	b << 'WAVEfmt '.bytes()
	put(mut b, 16, 4)
	put(mut b, 1, 2)
	put(mut b, 2, 2)
	put(mut b, rate, 4)
	put(mut b, rate * 4, 4)
	put(mut b, 4, 2)
	put(mut b, 16, 2)
	b << 'data'.bytes()
	put(mut b, data_bytes, 4)
	for s in p.audio {
		put(mut b, u32(u16(s)), 2)
	}
	os.write_file_array(os.join_path(dir, '${name}.wav'), b) or { panic(err) }
}

fn (mut p Player) shot(name string) {
	dir := os.getenv('HERO_SHOTS')
	if dir != '' {
		cli.write_png(p.m, os.join_path(dir, 'jaguar-hero-${name}.png')) or { panic(err) }
	}
}

// start_song goes from wherever the menus are to song `index`.
fn (mut p Player) start_song(index int) {
	p.frames(30)
	if p.word('state') == state_title {
		p.tap(.b)
	}
	assert p.word('state') == state_select
	for p.word('chosen') != index {
		p.tap(.down)
	}
	p.tap(.a)
	assert p.word('state') == state_play
	assert p.word('song') == index
}

// autoplay presses, for the coming frame, the lane of every note that is
// on the strike line in it, reading the chart and the clock out of the
// game.
fn (mut p Player) autoplay() {
	clock := p.word('clock') - input_lag
	chart := p.long('chart_ptr')
	first := p.word('judge_first')
	mut down := []bool{len: lanes}
	for i in first .. first + 24 {
		entry := p.m.peek32(chart + u32(i * 4))
		time := int(entry >> 16)
		if time > clock {
			break
		}
		if time == clock {
			down[int(entry >> 8) & 0xff] = true
		}
	}
	for lane in 0 .. lanes {
		p.m.set_button(0, lane_keys[lane], down[lane])
	}
	p.frames(1)
}

// pc_in_program reports whether the 68000 is somewhere in the program's
// code.
fn (p &Player) pc_in_program() bool {
	pc := p.m.cpu.pc
	return pc >= load_address && pc < p.symbols['state']
}

fn test_title_waits_and_the_menus_answer() {
	mut p := boot()
	p.frames(120)
	assert p.word('state') == state_title
	assert p.word('frame') > 110, 'the frame interrupt must run once a frame'
	pixels, info := p.m.frame()
	mut colours := map[u32]bool{}
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			colours[pixels[y * info.pitch + x] & 0xffffff] = true
		}
	}
	assert colours.len > 64, 'the title must be colourful'
	p.shot('title')
	p.tap(.b)
	assert p.word('state') == state_select
	p.tap(.down)
	p.tap(.down)
	assert p.word('chosen') == 2
	p.tap(.up)
	assert p.word('chosen') == 1
	p.frames(40)
	p.shot('select')
	p.tap(.option)
	assert p.word('state') == state_title
	assert p.loudest > 2000, 'the menus play music'
}

fn test_a_robot_plays_the_finale_perfectly() {
	mut p := boot()
	finale := p.songs.len - 1
	p.start_song(finale)
	notes := p.word('note_count')
	assert notes == p.songs[finale].notes.len
	frame_before := p.word('frame')
	run_before := p.run
	mut deepest := 0
	mut lead := 0
	mut busiest := u64(0)
	for p.word('state') == state_play {
		cycles := p.m.cpu.cycles
		p.autoplay()
		// The frame that clears the screen for the results does not count.
		if p.word('state') == state_play && p.m.cpu.cycles - cycles > busiest {
			busiest = p.m.cpu.cycles - cycles
		}
		if p.hero_level() > lead {
			lead = p.hero_level()
		}
		if p.word('combo') > deepest {
			deepest = p.word('combo')
		}
		clock := p.word('clock')
		if clock == 2490 {
			p.shot('play')
		}
		if '${clock}' in os.getenv('HERO_SHOT_CLOCKS').split(',') {
			p.shot('play-${clock}')
		}
		assert p.run - run_before < 8000, 'the song must end'
	}
	// The 68000 must never miss a frame, however busy the song.
	assert (p.word('frame') - frame_before) & 0xffff == p.run - run_before
	assert busiest < frame_cycles / 2, 'the busiest frame took ${busiest} cycles'
	assert p.word('state') == state_results
	assert p.word('perfects') == notes, 'every note on time is a perfect'
	assert p.word('misses') == 0
	assert p.word('strays') == 0
	assert p.word('max_combo') == notes
	assert p.word('accuracy') == 100
	assert p.word('rank') == 0
	assert p.word('failed') == 0
	assert p.long('score') > u32(notes * 100 * 4)
	assert p.m.peek32(p.symbols['best'] + u32(finale * 4)) == p.long('score'), 'a new best score'
	assert p.loudest > 8000, 'the song must be loud'
	assert lead > 3000, 'a player who keeps up hears the lead guitar'
	p.frames(70)
	p.shot('results')
	p.tap(.a)
	assert p.word('state') == state_select
	eprintln('finale: ${notes} notes, score ${p.long('score')}, ${p.run - run_before} frames, busiest frame ${busiest} of ${frame_cycles} 68000 cycles')
}

// hero_level is the lead guitar's envelope, read out of the DSP.
fn (p &Player) hero_level() int {
	mut dsp := synthesizer()
	record := dsp.address_of('voice_0') + u32(voice_hero * voice_bytes)
	return int(p.m.peek32(record + u32(v_env)) >> 8)
}

fn test_a_player_who_does_nothing_fails() {
	mut p := boot()
	p.start_song(0)
	mut loudest_after_miss := 0
	for _ in 0 .. 3000 {
		p.frames(1)
		if p.word('state') != state_play {
			break
		}
		// After the first miss the lead guitar falls silent and stays so.
		if p.word('misses') > 0 && p.word('hero_live') == 0 {
			level := p.hero_level()
			if level > loudest_after_miss {
				loudest_after_miss = level
			}
		}
	}
	assert loudest_after_miss < 50, 'a missed note silences the lead guitar'
	assert p.word('state') == state_results
	assert p.word('failed') == 1
	assert p.word('misses') > 5
	assert p.word('perfects') == 0
	assert p.long('score') == 0
	assert p.word('rank') == rank_letters.len - 1
}

fn test_a_late_and_sloppy_player_scores_less() {
	mut p := boot()
	p.start_song(1)
	for _ in 0 .. 1800 {
		// Two frames late, every time.
		clock := p.word('clock') - input_lag - 2
		chart := p.long('chart_ptr')
		first := p.word('judge_first')
		mut down := []bool{len: lanes}
		for i in first .. first + 24 {
			entry := p.m.peek32(chart + u32(i * 4))
			if int(entry >> 16) == clock {
				down[int(entry >> 8) & 0xff] = true
			}
		}
		for lane in 0 .. lanes {
			p.m.set_button(0, lane_keys[lane], down[lane])
		}
		p.frames(1)
	}
	assert p.word('state') == state_play
	assert p.word('perfects') == 0
	assert p.word('greats') > 10
	assert p.word('misses') == 0
}

fn test_every_song_starts_and_plays() {
	for index in 0 .. song_count {
		mut p := boot()
		p.start_song(index)
		for _ in 0 .. 600 {
			p.autoplay()
		}
		assert p.word('state') == state_play, '${p.songs[index].name} must still be playing'
		assert p.word('clock') >= 600
		assert p.pc_in_program(), '${p.songs[index].name}: the 68000 left the program'
		assert p.word('misses') == 0
		assert p.word('combo') > 0
		assert p.loudest > 4000
		p.save_wav('song-${index}')
	}
}

fn test_songs_are_long_enough_and_different() {
	all := songs()
	mut tempos := map[int]bool{}
	for s in all {
		seconds := f64(s.end_frame) / 60
		assert seconds > 55 && seconds < 95, '${s.name} lasts ${seconds:.0f} s'
		assert s.notes.len > 100
		tempos[s.bpm] = true
		// No two notes in a lane closer than a press and a release.
		mut last := []int{len: lanes, init: -100}
		for n in s.notes {
			assert n.frame - last[n.lane] >= 3, '${s.name}: notes too close in lane ${n.lane}'
			last[n.lane] = n.frame
		}
		mut per_lane := []int{len: lanes}
		for n in s.notes {
			per_lane[n.lane]++
		}
		eprintln('${s.name}: ${s.bpm} BPM, ${seconds:.0f} s, ${s.notes.len} notes, ${f64(s.notes.len) / seconds:.1f} a second, lanes ${per_lane}')
	}
	assert tempos.len >= 4
}

fn test_pause_freezes_the_song_and_option_quits() {
	mut p := boot()
	p.start_song(2)
	p.frames(200)
	p.tap(.pause)
	assert p.word('paused') == 1
	clock := p.word('clock')
	p.frames(60)
	assert p.word('clock') == clock, 'a paused song stands still'
	p.tap(.pause)
	assert p.word('paused') == 0
	p.frames(10)
	assert p.word('clock') > clock
	p.tap(.pause)
	p.tap(.option)
	assert p.word('state') == state_select
}

fn test_lanes_answer_keys_and_pad() {
	mut p := boot()
	p.frames(30)
	keypad := [jerry.Button.one, .two, .three, .four, .five]
	pad := [jerry.Button.left, .up, .right, .b, .a]
	for lane in 0 .. lanes {
		for button in [keypad[lane], pad[lane]] {
			p.m.set_button(0, button, true)
			p.frames(1)
			assert p.word('pad') & 0x1f == 1 << lane, '${button} must be lane ${lane + 1}'
			p.m.set_button(0, button, false)
			p.frames(1)
		}
	}
	// Down is lane 2 as well, and C is lane 3.
	for button, lane in {
		jerry.Button.down: 1
		jerry.Button.c:    2
	} {
		p.m.set_button(0, button, true)
		p.frames(1)
		assert p.word('pad') & 0x1f == 1 << lane
		p.m.set_button(0, button, false)
		p.frames(1)
	}
}

// With HERO_FULL set, the robot plays every song to the end (a minute or
// so of extra test time).
fn test_every_song_to_the_end() {
	if os.getenv('HERO_FULL') == '' {
		return
	}
	for index in 0 .. song_count {
		mut p := boot()
		p.start_song(index)
		frame_before := p.word('frame')
		run_before := p.run
		for p.word('state') == state_play {
			p.autoplay()
			assert p.run - run_before < 8000, '${p.songs[index].name} must end'
		}
		notes := p.word('note_count')
		assert (p.word('frame') - frame_before) & 0xffff == p.run - run_before
		assert p.word('perfects') == notes
		assert p.word('max_combo') == notes
		assert p.word('rank') == 0
		eprintln('${p.songs[index].name}: ${notes} notes, score ${p.long('score')}, ${f64(p.run - run_before) / 60:.0f} s')
	}
}
