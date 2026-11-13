module main

import demos.ghostgrid.robot { Sim, pad, run_frames, scene_of, screen_text }

// Ranks, the saved record, the missions it opens, the chips, the doors, the
// clock: what happens to a mission after the figure has done something.

fn spec() robot.Spec {
	l := layout()
	return robot.Spec{
		build:    build
		describe: describe
		cols:     room_cols
		rows:     room_rows
		maps:     l.maps
		first:    l.first
		rooms:    l.rooms
		range:    sight_range
		half:     sight_half
		image:    build() or { panic(err) }
	}
}

// word is a word of the cartridge's EEPROM.
fn word(b &robot.Booted, k int) int {
	return int(b.p.m.eeprom.words[k])
}

// record_words is the record a game with these missions' bests and this many
// missions open should have written: the header, a word for each mission,
// the number open and the checksum.
fn record_words(bests []int, open int) []int {
	mut words := [0x4700 + 2]
	words << bests
	words << open
	mut sum := 0x5a5a + 0x4700 + 2
	for w in words[1..] {
		sum += w
	}
	words << sum & 0xffff
	return words
}

fn test_a_finished_mission_is_ranked_saved_opens_the_next_and_survives_a_restart() {
	s := spec()
	plan := s.plan_mission(0, robot.Options{}) or {
		assert false, 'no plan'
		return
	}
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		assert word(b, 0) == 0xffff, 'the chip starts erased'
		r := s.play(mut sim, 0, plan, robot.nothing)
		assert r.phase == 1 && r.seen == 0 && r.alerts == 0
		assert r.score == r.secs && r.rank == 4, 'a quick run is an S: ${r}'
		assert scene_of(sim) == robot.scene_result
		// the result: the time, the rank, the best
		assert screen_text(sim, 0, 4, 16) == 'MISSION COMPLETE'
		assert screen_text(sim, 2, 3, 10) == 'TIME  ${robot.clock_text(r.secs)}'
		assert screen_text(sim, 3, 3, 4) == 'SEEN' && screen_text(sim, 3, 9, 3) == '  0'
		assert screen_text(sim, 4, 3, 6) == 'ALERTS'
		assert screen_text(sim, 6, 3, 7) == 'RANK  S'
		assert screen_text(sim, 1, 5, 14) == 'NEW BEST TIME!'
		assert b.field('sprites', 13, 'visible') == 1 && b.field('sprites', 13, 'frame') == 3, 'the S medal'
		assert b.field('sprites', 12, 'visible') == 1, 'the panel behind the text'
		assert screen_text(sim, 10, 5, 12) == 'NEXT MISSION', 'a mission to go on to'
		// the record: header, the mission's rank and time, the next mission open
		mut bests := []int{len: 10}
		bests[0] = 4 << 12 | r.secs
		want := record_words(bests, 2)
		for k, w in want {
			assert word(b, k) == w, 'EEPROM word ${k}: ${word(b, k)}, wanted ${w}'
		}
		// NEXT MISSION plays the second mission at once
		sim.frame(pad(.down))
		run_frames(mut sim, 3, 0)
		sim.frame(pad(.a))
		robot.ready(mut sim)
		assert scene_of(sim) == robot.scene_play && b.value('mission') == 1
			&& b.value('room_at') == 0
		assert b.value('chips_total') == 3
		// the mission select, with the record in it: a new machine with the same chip
		eeprom := b.p.m.eeprom.to_bytes()
		mut c := s.boot(pal)
		c.p.m.eeprom.load_bytes(eeprom)!
		mut cs := Sim(c)
		robot.to_picker(mut cs)
		run_frames(mut cs, 40, 0)
		assert screen_text(cs, 3, 3, 8) == 'DEPOT   ' && screen_text(cs, 3, 12, 1) == 'S'
		assert screen_text(cs, 3, 14, 4) == robot.clock_text(r.secs), 'the best time is shown: ${screen_text(cs,
			3, 14, 4)}'

		assert screen_text(cs, 4, 12, 6) == '-     ', 'the second is open, with no record (and no trace of LOCKED)'
		assert screen_text(cs, 5, 12, 6) == 'LOCKED', 'the third is not'
		assert c.value('unlocked') == 2
		assert c.value('missed_frames') == 0
	}
}

fn test_a_record_of_the_old_version_or_a_damaged_one_is_none() {
	s := spec()
	mut bests := []int{len: 10}
	bests[0] = 3 << 12 | 41
	bests[1] = 4 << 12 | 20
	good := record_words(bests, 3)
	mut bytes := []u8{}
	for w in good {
		bytes << u8(w >> 8)
		bytes << u8(w)
	}
	for _ in good.len .. 64 {
		bytes << [u8(0xff), 0xff]
	}
	// the record as it is: two missions have records, three are open
	mut a := s.boot(false)
	a.p.m.eeprom.load_bytes(bytes)!
	mut asim := Sim(a)
	robot.to_picker(mut asim)
	run_frames(mut asim, 40, 0)
	assert screen_text(asim, 3, 12, 1) == 'A' && screen_text(asim, 3, 14, 4) == '0:41'
	assert screen_text(asim, 4, 12, 1) == 'S' && screen_text(asim, 4, 14, 4) == '0:20'
	assert screen_text(asim, 5, 12, 1) == '-'
	assert screen_text(asim, 6, 12, 6) == 'LOCKED'
	assert a.value('unlocked') == 3
	// version 1 of the record (two fields: the best time and the fewest times seen) is none
	mut old := []u8{len: 128, init: 0xff}
	words := [0x4701, 41, 2, (0x5a5a + 0x4701 + 41 + 2) & 0xffff]
	for k, w in words {
		old[2 * k] = u8(w >> 8)
		old[2 * k + 1] = u8(w)
	}
	mut o := s.boot(false)
	o.p.m.eeprom.load_bytes(old)!
	mut osim := Sim(o)
	robot.to_picker(mut osim)
	run_frames(mut osim, 40, 0)
	assert screen_text(osim, 3, 12, 1) == '-' && screen_text(osim, 4, 12, 6) == 'LOCKED', 'the old version is none'
	assert o.value('unlocked') == 1 && o.value('save_m0') == 0
	// a damaged word: the checksum is wrong
	mut bad := bytes.clone()
	bad[7] ^= 0x01
	mut d := s.boot(false)
	d.p.m.eeprom.load_bytes(bad)!
	mut dsim := Sim(d)
	robot.to_picker(mut dsim)
	run_frames(mut dsim, 40, 0)
	assert screen_text(dsim, 3, 12, 1) == '-' && d.value('unlocked') == 1, 'a damaged record is none'
	assert d.value('missed_frames') == 0 && o.value('missed_frames') == 0
}

// result_for plays a mission to its result with a given time, times seen
// and alerts, by setting them (the mission is over at once).
fn result_for(mut sim Sim, mission int, secs int, seen int, alerts int) {
	if scene_of(sim) == robot.scene_result {
		// back to the title without the menus
		sim.poke_element('scene_state', 0, robot.scene_title)
		sim.frame(0)
	}
	robot.enter_mission(mut sim, mission)
	sim.poke('clock_elapsed', secs * sim.value('fps')) // the frames the stopwatch counted
	sim.poke('secs', secs)
	sim.poke('seen', seen)
	sim.poke('alerts', alerts)
	sim.poke('phase', 1)
	run_frames(mut sim, 20, 0)
}

fn test_the_rank_follows_the_score_against_the_missions_own_thresholds() {
	s := spec()
	defs := missions()
	mut b := s.boot(false)
	mut sim := Sim(b)
	mut ranks_seen := map[int]bool{}
	for mission in [0, 5] {
		ranks := defs[mission].ranks
		// a score at a threshold earns that rank; one past it the next lower; the times
		// seen and the alerts count as the guide says
		cases := [[ranks[0], 0, 0], [ranks[0] + 1, 0, 0], [ranks[1], 0, 0],
			[ranks[1] - 10, 2, 0], [ranks[1] - 15, 0, 1], [ranks[1] - 14, 2, 1],
			[ranks[2], 0, 0], [ranks[2] + 1, 0, 0], [1, 0, 0],
			[ranks[0] - 5, 1, 0], [ranks[0] - 5, 0, 1]]
		for c in cases {
			result_for(mut sim, mission, c[0], c[1], c[2])
			score := c[0] + 5 * c[1] + 15 * c[2]
			want := if score <= ranks[0] {
				4
			} else if score <= ranks[1] {
				3
			} else if score <= ranks[2] {
				2
			} else {
				1
			}
			assert b.value('score') == score, 'score ${score} for ${c}'
			assert b.value('rank') == want, 'mission ${mission}: score ${score} against ${ranks} is rank ${want}, not ${b.value('rank')}'
			assert screen_text(sim, 6, 9, 1) == ['-', 'C', 'B', 'A', 'S'][want]
			assert b.field('sprites', 13, 'frame') == want - 1
			ranks_seen[want] = true
		}
	}
	assert ranks_seen.len == 4, 'every rank came up: ${ranks_seen.keys()}'
}

fn test_a_better_time_replaces_the_record_a_worse_one_does_not_and_the_rank_only_goes_up() {
	s := spec()
	mut b := s.boot(false)
	mut sim := Sim(b)
	result_for(mut sim, 0, 30, 0, 0) // score 30: B (limits 9, 18, 30)
	assert b.value('rank') == 2 && b.value('new_best') == 1
	assert word(b, 1) == (2 << 12 | 30)
	result_for(mut sim, 0, 40, 0, 0) // slower and worse: C, nothing changes
	assert b.value('new_best') == 0 && word(b, 1) == (2 << 12 | 30)
	result_for(mut sim, 0, 25, 3, 0) // faster, but seen three times: score 40, still C; the time is better
	assert b.value('new_best') == 1 && word(b, 1) == (2 << 12 | 25), 'the better time is kept with the best rank: ${word(b,
		1)}'

	result_for(mut sim, 0, 15, 0, 0) // score 15: A (limits 9, 18, 30)
	assert word(b, 1) == (3 << 12 | 15)
	assert word(b, 11) == 2, 'one mission open, the next'
	assert b.value('missed_frames') == 0
}

fn test_a_mission_that_is_not_won_saves_nothing_and_the_menu_has_no_next_mission() {
	s := spec()
	for caught in [true, false] {
		mut b := s.boot(false)
		mut sim := Sim(b)
		robot.enter_mission(mut sim, 2)
		run_frames(mut sim, 5, 0)
		if caught {
			sim.poke('phase', 2)
		} else {
			// the clock runs out: 40 seconds
			mut n := 0
			for b.value('phase') == 0 && n < 40 * 60 + 100 {
				sim.frame(0)
				n++
			}
			assert n > 40 * 60 - 60 && n < 40 * 60 + 20, 'the countdown took ${n} frames'
		}
		run_frames(mut sim, 16, 0)
		assert scene_of(sim) == robot.scene_result
		assert screen_text(sim, 0, 4, 15) == if caught {
			'YOU WERE CAUGHT'
		} else {
			'TIME IS UP     '
		}
		assert b.value('phase') == if caught {
			2
		} else {
			3
		}
		assert b.field('sprites', 13, 'visible') == 0, 'no medal'
		assert screen_text(sim, 9, 5, 10) == 'PLAY AGAIN'
			&& screen_text(sim, 10, 5, 14) == 'MISSION SELECT'
		assert word(b, 0) == 0xffff, 'nothing was written'
		// PLAY AGAIN: the same mission, from the start
		sim.frame(pad(.a))
		robot.ready(mut sim)
		assert b.value('phase') == 0 && b.value('mission') == 2 && b.value('seen') == 0
		assert b.value('limit_running') == 1
		assert b.value('missed_frames') == 0
	}
}

fn test_the_countdown_shows_the_seconds_left_and_stands_still_in_the_pause_menu() {
	s := spec()
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		robot.enter_mission(mut sim, 2)
		fps := if pal { 50 } else { 60 }
		run_frames(mut sim, 2 * fps, 0)
		left := b.value('limit_left')
		assert left > 37 * fps && left < 39 * fps + 10, 'about 38 seconds left: ${left} frames'
		assert robot.layer_text(sim, 'status', 8, 2, 0, 7) == 'LEFT ${(left + fps - 1) / fps:2}', robot.layer_text(sim,
			'status', 8, 2, 0, 7)

		sim.frame(pad(.pause))
		run_frames(mut sim, 3, 0)
		held := b.value('limit_left')
		run_frames(mut sim, 120, 0)
		assert b.value('limit_left') == held, 'the countdown waits while the game is paused'
		sim.frame(pad(.a)) // RESUME
		run_frames(mut sim, 60, 0)
		assert b.value('limit_left') < held - 55 && b.value('limit_left') > held - 65, 'it counts again after RESUME: ${held} then ${b.value('limit_left')}'
	}
}

fn test_chips_are_taken_one_by_one_and_the_exit_waits_for_all_of_them() {
	s := spec()
	mut b := s.boot(false)
	mut sim := Sim(b)
	robot.enter_mission(mut sim, 1)
	room := s.first[1]
	chips := s.find(room, `$`)
	exit := s.find(room, `X`)[0]
	assert chips.len == 3 && b.value('chips_total') == 3 && b.value('chips_left') == 3
	assert robot.layer_text(sim, 'status', 8, 1, 0, 8) == 'CHIP 0/3'
	// the exit does nothing while chips are left
	robot.put_figure(mut sim, exit.x, exit.y)
	run_frames(mut sim, 6, 0)
	assert b.value('phase') == 0, 'the exit pad is shut'
	// take them: the tile is the floor again
	for k, chip in chips {
		robot.put_figure(mut sim, chip.x, chip.y)
		run_frames(mut sim, 4, 0)
		assert b.value('chips_left') == 2 - k, 'chip ${k} is taken'
		assert b.element('rt_map', chip.y * room_cols + chip.x) in [tile_floor, tile_floor_lit], 'the tile is the floor again'
		assert robot.layer_text(sim, 'status', 8, 1, 0, 8) == 'CHIP ${k + 1}/3'
	}
	// taken once: standing on the same tile again takes nothing
	robot.put_figure(mut sim, chips[0].x, chips[0].y)
	run_frames(mut sim, 4, 0)
	assert b.value('chips_left') == 0
	robot.put_figure(mut sim, exit.x, exit.y)
	run_frames(mut sim, 4, 0)
	assert b.value('phase') == 1, 'with every chip taken the exit works'
}

fn test_a_door_leads_to_the_next_room_and_back_and_each_room_starts_over() {
	s := spec()
	mission := 3
	first := s.first[mission]
	mut b := s.boot(false)
	mut sim := Sim(b)
	robot.enter_mission(mut sim, mission)
	assert b.value('room_at') == 0 && b.value('room_number') == first
	assert robot.layer_text(sim, 'status', 8, 1, 0, 8) == 'ROOM 1/2'
	// a mark of what the mission carries: a time seen, and the clock
	run_frames(mut sim, 90, 0)
	sim.poke('seen', 2)
	secs := b.value('secs')
	assert secs >= 1
	door := s.find(first, `D`)[0]
	robot.put_figure(mut sim, door.x, door.y)
	run_frames(mut sim, 3, 0)
	assert b.value('scenes_fading') == 1, 'it fades out'
	robot.ready(mut sim)
	assert b.value('room_at') == 1 && b.value('entering') == 1
		&& b.value('room_number') == first + 1
	arrive := s.find(first + 1, `[`)[0]
	assert robot.fixed_of(b.value('px')) == arrive.x * 16, 'the figure comes in beside the door'
	assert b.value('secs') >= secs && b.value('seen') == 2, 'the clock and the times seen go on'
	assert robot.layer_text(sim, 'status', 8, 1, 0, 8) == 'ROOM 2/2'
	assert b.field('guards', 0, 'live') == 1 && b.field('guards', 1, 'live') == 0, 'the other room has its own guards'
	// leave the first room's guard where it is: when we come back it is at its post
	back := s.find(first + 1, `U`)[0]
	robot.put_figure(mut sim, back.x, back.y)
	run_frames(mut sim, 3, 0)
	robot.ready(mut sim)
	assert b.value('room_at') == 0 && b.value('entering') == 2 && b.value('room_number') == first
	beside := s.find(first, `]`)[0]
	assert robot.fixed_of(b.value('px')) == beside.x * 16
	assert b.value('seen') == 2, 'what was seen stays'
	assert robot.gstate(sim, 0) == robot.patrol
	start := s.find(first, `1`)[0]
	t := robot.gtile(sim, 0)
	assert (t.x - start.x) * (t.x - start.x) + (t.y - start.y) * (t.y - start.y) < 9, 'the guard is at the start of its route again'
	// the exit is in the last room
	assert s.find(first, `X`).len == 0 && s.find(first + 1, `X`).len == 1
	assert b.value('missed_frames') == 0
}
