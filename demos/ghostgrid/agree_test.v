module main

import demos.ghostgrid.robot { Sim }

// The same game runs in the interpreter and, compiled, on the emulated 68000;
// the two must agree. The robot plays one whole mission of each kind (and one
// with cameras) on both at once, frame by frame from the title screen, and
// every variable that matters is compared after every frame; at the end
// every variable of the program is.

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

const watched = ['px', 'py', 'phase', 'seen', 'alerts', 'secs', 'clock_elapsed', 'room_at',
	'entering', 'chips_left', 'level', 'scenes_fading', 'rt_fade', 'camera_x', 'camera_y',
	'limit_left', 'unlocked']

// compare asserts that the machine and the interpreter are in the same state.
fn compare(b &robot.Booted, it &robot.Rig, n int) {
	for name in watched {
		assert b.value(name) == it.value(name), 'frame ${n}: ${name}: machine ${b.value(name)}, interpreter ${it.value(name)}'
	}
	assert robot.scene_of(Sim(b)) == robot.scene_of(Sim(it)), 'frame ${n}: scene'
	for i in 0 .. 4 {
		assert robot.gstate(Sim(b), i) == robot.gstate(Sim(it), i), 'frame ${n}: guard ${i}: state'
		for field in ['x', 'y', 'face', 'wp', 'mleft', 'look', 'stuck', 'cone_n', 'live'] {
			assert b.field('guards', i, field) == it.field('guards', i, field), 'frame ${n}: guard ${i} ${field}: machine ${b.field('guards',
				i, field)}, interpreter ${it.field('guards', i, field)}'
		}
	}
	for c in 0 .. 3 {
		for field in ['step', 'dir', 'wait', 'exposure', 'alarm', 'cone_n', 'live'] {
			assert b.field('cams', c, field) == it.field('cams', c, field), 'frame ${n}: camera ${c} ${field}: machine ${b.field('cams',
				c, field)}, interpreter ${it.field('cams', c, field)}'
		}
	}
	if n % 5 == 0 {
		for cell in 0 .. room_cells {
			assert b.element('lit', cell) == it.element('lit', cell), 'frame ${n}: lit ${cell}'
		}
	}
}

// both plays a mission's plan on the machine and the interpreter together.
fn both(s robot.Spec, mission int, pal bool) ! {
	plan := s.plan_mission(mission, robot.Options{}) or {
		return error('no plan for mission ${mission}')
	}
	mut b := s.boot(pal)
	mut it := s.rig(pal)
	mut msim := Sim(b)
	mut isim := Sim(it)
	robot.enter_mission(mut msim, mission)
	robot.enter_mission(mut isim, mission)
	mut n := 0
	lockstep := fn [mut b, mut it, mut n] (mut sim Sim) {
		it.frame(b.pad_log.last())
		compare(b, it, n)
		n++
	}
	for k, actions in plan.rooms {
		s.execute(mut msim, actions, lockstep)
		if k < plan.rooms.len - 1 {
			robot.ready(mut msim)
			robot.ready(mut isim)
		}
	}
	for _ in 0 .. 16 {
		msim.frame(0)
		isim.frame(0)
		compare(b, it, n)
		n++
	}
	assert b.value('phase') == 1 && b.value('seen') == 0
	mut differences := b.img.differences(it.it, b.p.m.ram)
	differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale')
		&& !it.contains('rt_eeprom') && !it.contains('rt_fade_applied'))
	assert differences.len == 0, differences.join('\n')
	// the record the machine's chip holds is the interpreter's chip
	for k in 0 .. 14 {
		assert it.it.element('rt_eeprom', k)! == b.p.m.eeprom.words[k], 'EEPROM word ${k}'
	}
	println('mission ${mission} ${if pal { 'PAL' } else { 'NTSC' }}: ${n} frames, the machine and the interpreter agree')
}

fn test_the_interpreter_agrees_on_a_whole_sneak_mission() ! {
	both(spec(), 0, false)!
}

fn test_the_interpreter_agrees_on_a_whole_collect_mission() ! {
	both(spec(), 1, false)!
}

fn test_the_interpreter_agrees_on_a_whole_timed_mission() ! {
	both(spec(), 2, false)!
}

fn test_the_interpreter_agrees_on_a_whole_mission_of_two_rooms_on_pal() ! {
	both(spec(), 3, true)!
}

fn test_the_interpreter_agrees_on_a_mission_with_cameras() ! {
	both(spec(), 4, false)!
}
