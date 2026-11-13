module main

import demos.ghostgrid.robot { Sim, scene_of, screen_text }

// The robot plays missions VAULT, STACKS, DASH from the title screen through the menus
// to the result, on NTSC and on PAL, never seen: the way to the exit is
// found from the cones the guards and the cameras will light (see
// robot/plan.v), and the machine plays it with the pad. The result, the rank and the time
// are asserted, and so is the record in the cartridge's EEPROM. The
// missions are then played one after the other from one start, each started
// with NEXT MISSION on the result screen of the one before.

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

// Expect is what the robot's run of a mission comes to: the seconds the clock
// shows and the rank, on NTSC and on PAL (the same frames take more seconds on
// PAL, so a run can earn a lower rank there).
struct Expect {
	mission   int
	ntsc_secs int
	pal_secs  int
	ntsc_rank int
	pal_rank  int
}

const expected = [
	Expect{4, 6, 8, 4, 4},
	Expect{5, 13, 15, 4, 3},
	Expect{6, 6, 8, 3, 3},
]

const rank_letters = ['-', 'C', 'B', 'A', 'S']

// check_result asserts what a finished mission must look like on the machine.
fn check_result(s robot.Spec, b &robot.Booted, mission int, r robot.Result, secs int, rank int, pal bool) {
	def := missions()[mission]
	std := if pal { 'PAL' } else { 'NTSC' }
	assert r.phase == 1, '${def.title} ${std}: the mission is done, not ${r.phase}'
	assert r.seen == 0 && r.alerts == 0, '${def.title} ${std}: never seen'
	assert r.secs == secs, '${def.title} ${std}: ${r.secs} seconds, expected ${secs}'
	assert r.rank == rank, '${def.title} ${std}: rank ${rank_letters[r.rank]}, expected ${rank_letters[rank]} (score ${r.score} against ${def.ranks})'
	assert b.value('missed_frames') == 0, '${def.title} ${std}: ${b.value('missed_frames')} frames missed'
	if def.limit > 0 {
		assert r.secs < def.limit, '${def.title}: inside the limit'
	}
	if s.find(s.first[mission], `$`).len > 0 {
		assert b.value('chips_left') == 0, '${def.title}: every chip is taken'
	}
	assert b.value('room_at') == def.rooms.len - 1, '${def.title}: in the last room'
	assert scene_of(Sim(b)) == robot.scene_result
	// the result screen and the record
	sim := Sim(b)
	assert screen_text(sim, 0, 4, 16) == 'MISSION COMPLETE'
	assert screen_text(sim, 6, 9, 1) == rank_letters[rank]
	assert screen_text(sim, 7, 9, 4) == robot.clock_text(secs)
	word := int(b.p.m.eeprom.words[1 + mission])
	assert word == (rank << 12 | secs), '${def.title}: the record holds ${word}'
}

fn test_the_robot_completes_each_mission_unseen_on_ntsc_and_pal() {
	s := spec()
	println('mission  std   result: time rank  frames  (plan)')
	for e in expected {
		def := missions()[e.mission]
		plan := s.plan_mission(e.mission, robot.Options{}) or {
			assert false, '${def.title}: the robot finds no way that is never seen'
			return
		}
		for pal in [false, true] {
			mut b := s.boot(pal)
			mut sim := Sim(b)
			r := s.play(mut sim, e.mission, plan, robot.nothing)
			secs := if pal { e.pal_secs } else { e.ntsc_secs }
			rank := if pal { e.pal_rank } else { e.ntsc_rank }
			println('${def.title:-8} ${if pal { 'PAL ' } else { 'NTSC' }}  ${r.secs:4} s ${rank_letters[r.rank]}  ${r.frames:5} frames; ${plan.rooms.map(it.len)} steps')
			check_result(s, b, e.mission, r, secs, rank, pal)
		}
	}
}

fn test_the_missions_played_in_order_open_one_another_and_keep_their_records() {
	s := spec()
	mut plans := []robot.Plan{}
	for e in expected {
		plans << s.plan_mission(e.mission, robot.Options{}) or {
			assert false, 'no plan for mission ${e.mission}'
			return
		}
	}
	mut b := s.boot(false)
	mut sim := Sim(b)
	first := expected[0].mission
	mut r := s.play(mut sim, first, plans[0], robot.nothing)
	for k, e in expected {
		if k > 0 {
			robot.next_mission(mut sim)
			assert b.value('mission') == e.mission
			r = s.play_here(mut sim, plans[k], robot.nothing)
		}
		assert r.phase == 1 && r.seen == 0, 'mission ${e.mission}: ${r}'
		assert r.secs == e.ntsc_secs && r.rank == e.ntsc_rank
		word := int(b.p.m.eeprom.words[1 + e.mission])
		assert word == (e.ntsc_rank << 12 | e.ntsc_secs), 'record of mission ${e.mission}: ${word}'
	}
	last := expected.last().mission
	assert int(b.p.m.eeprom.words[11]) >= last + 2 || last == 9, 'the mission after the last is open'
	assert b.value('missed_frames') == 0
}
