module main

import jaggame
import demos.ghostgrid.robot { Sim, run_frames }

// The cameras of GHOSTGRID, tested in the vault (the fifth mission): a camera
// on each of two pillars, sweeping between 16 and 112 in steps of 8 angle
// units, and one guard on a ring corridor.

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

const vault = 4 // the fifth mission

// in_vault plays the game from the title to the vault; the guard stands
// still (waiting at its first waypoint) so that only the cameras act.
fn in_vault(s robot.Spec, pal bool) &robot.Booted {
	mut b := s.boot(pal)
	mut sim := Sim(b)
	robot.enter_mission(mut sim, vault)
	sim.poke_field('guards', 0, 'pause', 255)
	return b
}

// cam_cells is the cells a camera's bit is set on, from the machine.
fn cam_cells(sim Sim, cam int) []int {
	mut cells := []int{}
	for cell in 0 .. room_cells {
		if sim.element('lit', cell) & (0x10 << u32(cam)) != 0 {
			cells << cell
		}
	}
	return cells
}

fn cell_of(p jaggame.Point) int {
	return p.y * room_cols + p.x
}

fn test_a_camera_sweeps_between_its_angles_and_its_light_is_the_cone_of_each_position() {
	s := spec()
	room := s.first[vault]
	mut g := describe()
	handle := jaggame.Room{
		index: room
		name:  'room${room}'
	}
	for pal in [false, true] {
		mut b := in_vault(s, pal)
		mut sim := Sim(b)
		assert b.field('cams', 0, 'live') == 1 && b.field('cams', 1, 'live') == 1
			&& b.field('cams', 2, 'live') == 0
		assert b.field('cams', 0, 'n') == 13 && b.field('cams', 0, 'a0') == 16
		mut steps := []int{}
		mut changed_at := 0
		mut checked := 0
		mut seen_frames := map[string]bool{}
		for n in 0 .. 24 * 13 * 2 + 40 {
			sim.frame(0)
			step := b.field('cams', 0, 'step')
			if steps.len == 0 || steps.last() != step {
				if steps.len > 0 {
					assert n - changed_at == 24 || changed_at == 0, 'a position lasts 24 frames, not ${n - changed_at}'
				}
				steps << step
				changed_at = n
			}
			spr := 9 // the first camera's sprite
			seen_frames['${b.field('sprites', spr, 'frame')}${b.field('sprites', spr, 'flip')}'] = true
			if n - changed_at == 8 {
				// the cone has been moved: the light is the list that was worked out
				for cam in 0 .. 2 {
					tx := b.field('cams', cam, 'tx')
					ty := b.field('cams', cam, 'ty')
					angle := b.field('cams', cam, 'a0') + 8 * b.field('cams', cam, 'step')
					mut want := []int{}
					for p in g.view_cells(handle, tx, ty, angle, cam_range, cam_half, false) {
						want << cell_of(p)
					}
					want.sort()
					mut have := cam_cells(sim, cam)
					have.sort()
					assert have == want, 'frame ${n}: camera ${cam} at step ${b.field('cams', cam,
						'step')}: the light is ${have.len} tiles, the cone ${want.len}'

					assert want.len >= 1
					checked++
				}
			}
		}
		// to the end, and back to the start, and on: 0 1 .. 12 11 .. 0 1 ..
		assert steps[..14] == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 11], 'the sweep goes out: ${steps}'
		assert steps.contains(0) && steps.index(0) == 0 && steps[24] == 0, 'and comes back: ${steps}'
		assert checked > 40
		// facing right, down and left (the right frame flipped)
		assert seen_frames.len == 3 && '00' in seen_frames, 'the sprite looks right, down, left: ${seen_frames}'
		assert b.value('missed_frames') == 0
	}
}

// the first tile that camera 0's light is on and no wall hides
fn lit_tile(sim Sim) int {
	cells := cam_cells(sim, 0)
	assert cells.len > 0
	return cells[cells.len / 2]
}

fn test_the_light_is_what_sees_and_the_guards_near_come_and_then_chase() {
	s := spec()
	for pal in [false, true] {
		mut b := in_vault(s, pal)
		mut sim := Sim(b)
		run_frames(mut sim, 30, 0)
		// the guard stands near the camera, within 12 tiles: it will be called
		sim.poke_field('guards', 0, 'x', 5 * 16 * 65536)
		sim.poke_field('guards', 0, 'y', (2 * 16 - 1) * 65536)
		sim.poke_field('guards', 0, 'pause', 255)
		mut cell := lit_tile(sim)
		// a tile the guard's own cone does not light
		robot.put_figure(mut sim, cell % room_cols, cell / room_cols)
		step := b.field('cams', 0, 'step')
		mut seen_after := -1
		mut alarm_after := -1
		mut called := -1
		for n in 0 .. 90 {
			sim.frame(0)
			if b.value('seen') > 0 && seen_after < 0 {
				seen_after = n
			}
			if robot.gstate(sim, 0) != robot.patrol && called < 0 {
				called = n
			}
			if b.field('cams', 0, 'alarm') == 2 && alarm_after < 0 {
				alarm_after = n
			}
			if n == 20 {
				assert b.field('cams', 0, 'step') == step, 'the camera holds still while the figure is in its light'
				assert b.field('sprites', 9, 'frame') >= 3, 'its lens is red'
			}
		}
		// seen_after counts the frames from the figure being put there: the exposure
		// begins when the light is next worked out and takes 12 frames
		assert seen_after >= 10 && seen_after <= 16, 'the camera has seen it after ${seen_after} frames'
		assert b.value('seen') == 1, 'one time seen: ${b.value('seen')}'
		assert called >= 10 && called <= 18, 'the guard is called with it (${called})'
		assert alarm_after >= 56 && alarm_after <= 64, 'the alarm after 60 frames (${alarm_after})'
		assert robot.gstate(sim, 0) in [robot.alert, robot.suspicious]
		assert b.value('alerts') >= 1, 'the guard chases: an alert is counted'
		assert b.value('missed_frames') == 0
	}
}

fn test_cover_does_not_hide_the_figure_from_a_camera() {
	s := spec()
	mut b := in_vault(s, false)
	mut sim := Sim(b)
	run_frames(mut sim, 30, 0)
	cell := lit_tile(sim)
	robot.put_figure(mut sim, cell % room_cols, cell / room_cols)
	run_frames(mut sim, 30, robot.pad(.b)) // crouching
	assert b.value('crouched') == 1
	assert b.value('seen') == 1, 'a crouching figure in the light is seen by a camera'
}

fn test_a_guard_far_from_the_camera_is_not_called_and_the_light_fades_when_the_figure_leaves() {
	s := spec()
	mut b := in_vault(s, false)
	mut sim := Sim(b)
	run_frames(mut sim, 30, 0)
	// the guard is far to the south east: more than 12 tiles from the camera
	sim.poke_field('guards', 0, 'x', 24 * 16 * 65536)
	sim.poke_field('guards', 0, 'y', (15 * 16 - 1) * 65536)
	sim.poke_field('guards', 0, 'pause', 255)
	cell := lit_tile(sim)
	robot.put_figure(mut sim, cell % room_cols, cell / room_cols)
	run_frames(mut sim, 30, 0)
	assert b.value('seen') == 1
	assert robot.gstate(sim, 0) == robot.patrol, 'a guard that is far away is not called'
	// the figure leaves the light: the exposure fades, the camera sweeps on, and
	// when it finds the figure again that counts as another time seen
	robot.put_figure(mut sim, 1, 18)
	run_frames(mut sim, 80, 0)
	assert b.field('cams', 0, 'exposure') == 0 && b.field('cams', 0, 'alarm') == 0
	step := b.field('cams', 0, 'step')
	run_frames(mut sim, 30, 0)
	assert b.field('cams', 0, 'step') != step, 'the camera sweeps on'
	cell2 := lit_tile(sim)
	robot.put_figure(mut sim, cell2 % room_cols, cell2 / room_cols)
	run_frames(mut sim, 30, 0)
	assert b.value('seen') == 2, 'seen again: ${b.value('seen')}'
}

fn test_what_a_robot_sees_in_the_light_is_the_same_in_the_interpreter() {
	s := spec()
	mut b := in_vault(s, false)
	mut sim := Sim(b)
	mut it := s.rig(false)
	mut its := Sim(it)
	robot.enter_mission(mut its, vault)
	its.poke_field('guards', 0, 'pause', 255)
	run_frames(mut sim, 30, 0)
	run_frames(mut its, 30, 0)
	cell := lit_tile(sim)
	for one in [Sim(b), Sim(it)] {
		mut x := one
		robot.put_figure(mut x, cell % room_cols, cell / room_cols)
	}
	for n in 0 .. 200 {
		sim.frame(0)
		its.frame(0)
		for name in ['seen', 'alerts', 'level', 'phase'] {
			assert b.value(name) == it.value(name), 'frame ${n}: ${name}'
		}
		for c in 0 .. 2 {
			for field in ['step', 'dir', 'wait', 'exposure', 'alarm', 'cone_n'] {
				assert b.field('cams', c, field) == it.field('cams', c, field), 'frame ${n}: camera ${c} ${field}'
			}
		}
		if b.value('phase') != 0 {
			break
		}
	}
	for c in 0 .. room_cells {
		assert b.element('lit', c) == it.element('lit', c), 'cell ${c}'
	}
}
