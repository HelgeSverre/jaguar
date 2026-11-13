module main

import os
import cli
import jaggame.emulated
import demos.ghostgrid.robot { Sim, scene_of, screen_text }

// The robot's run of the first four missions, played one after the other
// from the title, is kept as a press script for `just roboplay ghostgrid`:
// the desktop app holds the buttons it names, frame for frame. This test
// plays that file on a fresh machine the way the app does (a press applied
// before each frame, nothing else) and asserts the robot's results, so the
// file is known to be in step with the game.
//
// GHOSTGRID_ROBOPLAY=1 plans the missions again and rewrites the file.

const roboplay_path = os.join_path(os.dir(@FILE), 'roboplay.press')

// the seconds and the rank of each mission on NTSC, as robots_1_test.v has them
const replay_secs = [7, 16, 7, 14]
const replay_ranks = [4, 4, 4, 4]

// frames the replay runs on after the last press, for the result screen
const replay_tail = 240

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

// record plays the four missions with the robot and writes its pad.
fn record(s robot.Spec) ! {
	mut b := s.boot(false)
	mut sim := Sim(b)
	for mission in 0 .. replay_secs.len {
		plan := s.plan_mission(mission, robot.Options{}) or {
			return error('no plan for mission ${mission}')
		}
		if mission == 0 {
			s.play(mut sim, mission, plan, robot.nothing)
		} else {
			robot.next_mission(mut sim)
			s.play_here(mut sim, plan, robot.nothing)
		}
	}
	presses := cli.presses_of(b.pad_log.map(robot.button_bits(it)))
	os.write_file(roboplay_path, cli.script_of(presses))!
	println('${presses.len} presses over ${b.pad_log.len} frames in ${roboplay_path}')
}

fn test_the_robots_press_file_plays_four_missions_in_step() {
	s := spec()
	if os.getenv('GHOSTGRID_ROBOPLAY') != '' {
		record(s)!
	}
	presses := cli.read_presses(roboplay_path)!
	mut end := 0
	for press in presses {
		if press.last > end {
			end = press.last
		}
	}
	mut p := emulated.boot(s.image.bytes, false)!
	for frame in 0 .. end + 1 + replay_tail {
		cli.apply_presses(mut p.m, presses, frame)
		p.m.run_frame()
	}
	mut b := &robot.Booted{
		img: s.image
		p:   p
	}
	sim := Sim(b)
	assert scene_of(sim) == robot.scene_result
	assert screen_text(sim, 0, 4, 16) == 'MISSION COMPLETE'
	assert b.value('mission') == replay_secs.len - 1
	assert b.value('phase') == 1 && b.value('seen') == 0 && b.value('alerts') == 0
	for mission, secs in replay_secs {
		word := int(b.p.m.eeprom.words[1 + mission])
		assert word == replay_ranks[mission] * 4096 + secs, 'the record of mission ${mission} holds ${word}'
	}
	println('${presses.len} presses, ${end + 1} frames: four missions done unseen')
}
