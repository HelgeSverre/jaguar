module main

import jaggame
import demos.ghostgrid.robot { Sim, fixed_of, gstate, gtile, gx, gy, pad, put_figure, run_frames, scene_of }

// The guards of the first mission, the depot, are tested by playing it: the
// image is booted on both television standards and driven through the pad,
// and the guards' positions, facings and states are read from the machine's
// memory by name.

const patrol = robot.patrol
const suspicious = robot.suspicious
const alert = robot.alert
const returning = robot.returning

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

// loaded plays the game from the title to the depot, loaded, with the guards
// on their routes.
fn loaded(s robot.Spec, pal bool) &robot.Booted {
	mut b := s.boot(pal)
	mut sim := Sim(b)
	robot.enter_mission(mut sim, 0)
	return b
}

fn lit_by(s Sim, tile jaggame.Point) int {
	return s.element('lit', tile.y * room_cols + tile.x)
}

fn int_abs(a int) int {
	return if a < 0 { -a } else { a }
}

fn test_the_depot_loads_and_everything_stands_on_its_start() {
	s := spec()
	for pal in [false, true] {
		mut b := loaded(s, pal)
		assert b.value('missed_frames') == 0
		assert b.value('room_width') == room_cols * 16 && b.value('room_height') == room_rows * 16
		start := s.find(0, `@`)[0]
		assert fixed_of(b.value('px')) == start.x * 16 && fixed_of(b.value('py')) == start.y * 16
		// the guards are on their first waypoints, live, in patrol
		firsts := [s.find(0, `1`)[0], s.find(0, `4`)[0], s.find(0, `3`)[0], s.find(0, `5`)[0]]
		for i in 0 .. 4 {
			assert b.field('guards', i, 'live') == 1
			assert gstate(b, i) == patrol
			t := gtile(b, i)
			assert int_abs(t.x - firsts[i].x) + int_abs(t.y - firsts[i].y) < 6, 'guard ${i} is at ${t} near ${firsts[i]}'
		}
		// no camera, and the sprite and the pool are as they should be
		for k in 0 .. 3 {
			assert b.field('cams', k, 'live') == 0
		}
		cx := int(i16(b.value('camera_x')))
		cy := int(i16(b.value('camera_y')))
		want_y := int(fixed_of(b.value('py'))) + 9 - 120
		assert cx == 0 && cy == if want_y < 0 {
			0
		} else {
			want_y
		}, 'the camera is on the figure: ${cx}, ${cy}'
	}
}

// ---- the guards at work ----

fn test_a_figure_that_stands_in_a_guards_path_is_seen_chased_and_caught() {
	s := spec()
	for pal in [false, true] {
		mut b := loaded(s, pal)
		mut sim := Sim(b)
		// the first guard walks east along the corridor; stand in front of him
		put_figure(mut sim, 9, 8)
		mut states := [gstate(sim, 0)]
		mut n := 0
		for b.value('phase') == 0 && n < 900 {
			sim.frame(0)
			n++
			st := gstate(sim, 0)
			if states.last() != st {
				states << st
			}
		}
		assert b.value('phase') == 2, 'the figure was caught (after ${n} frames; the guard went through ${states})'
		assert states.len >= 3, 'the guard went through ${states}'
		assert states[..3] == [patrol, suspicious, alert], 'patrol, then suspicious, then alert: ${states}'
		assert b.value('seen') >= 1 && b.value('alerts') >= 1
		assert n < 400, 'caught in ${n} frames'
		// the end screen is up and the guards have stopped
		run_frames(mut sim, 5, 0)
		gx0 := b.field('guards', 0, 'x')
		run_frames(mut sim, 30, 0)
		assert b.field('guards', 0, 'x') == gx0, 'the guards stop when the mission is over'
		assert b.value('missed_frames') == 0
		// the result is up, and PLAY AGAIN (the first choice) starts the mission again
		assert scene_of(sim) == robot.scene_result
		assert b.value('phase') == 2
		sim.frame(pad(.a))
		robot.ready(mut sim)
		assert scene_of(sim) == robot.scene_play
		assert b.value('phase') == 0 && b.value('seen') == 0 && b.value('alerts') == 0
		start := s.find(0, `@`)[0]
		assert fixed_of(b.value('px')) == start.x * 16
		for i in 0 .. 4 {
			assert gstate(b, i) == patrol
		}
		run_frames(mut sim, 200, 0)
		assert b.value('phase') == 0, 'the new mission is not over at once'
		assert b.value('missed_frames') == 0
	}
}

fn test_a_running_figure_is_heard_where_a_walking_one_is_not() {
	s := spec()
	for pal in [false, true] {
		// the sentinel at the middle of the south hall looks north; two tiles behind
		// him, out of his cone, a figure walks to and fro
		for running in [false, true] {
			mut b := loaded(s, pal)
			mut sim := Sim(b)
			post := s.find(0, `3`)[0]
			put_figure(mut sim, post.x - 1, post.y + 2)
			mut woke := -1
			for n in 0 .. 150 {
				dir := if (n / 12) % 2 == 0 { pad(.right) } else { pad(.left) }
				sim.frame(dir | if running { pad(.a) } else { u32(0) })
				if woke < 0 {
					assert lit_by(sim, robot.ptile(sim)) & 4 == 0, 'the figure is outside the cone: it is heard, not seen'
				}
				if gstate(sim, 2) != patrol && woke < 0 {
					woke = n
				}
			}
			if running {
				assert woke >= 0 && woke < 60, 'the running figure is heard (after ${woke} frames)'
				assert b.value('seen') == 0, 'heard, not seen'
			} else {
				assert woke < 0, 'a walking figure is not heard'
				assert gstate(sim, 2) == patrol
			}
			assert b.value('missed_frames') == 0
		}
	}
}

fn test_a_knock_draws_the_nearest_guard_and_he_goes_back_to_his_post() {
	s := spec()
	knock_place := jaggame.Point{15, 14}
	for pal in [false, true] {
		mut b := loaded(s, pal)
		mut sim := Sim(b)
		// below the wall at (15,15); the sentinel is two tiles away, the others further than a knock is heard
		put_figure(mut sim, knock_place.x, knock_place.y)
		run_frames(mut sim, 3, pad(.down)) // face the wall
		sim.frame(pad(.down, .c))
		assert b.value('flash') > 0, 'the word KNOCK is on the HUD'
		run_frames(mut sim, 2, 0)
		assert gstate(sim, 2) == suspicious, 'the sentinel comes to look: ${robot.state_names[gstate(sim,
			2)]}'

		for i in [0, 1, 3] {
			assert gstate(sim, i) == patrol, 'guard ${i} is too far to hear it'
		}
		assert b.field('guards', 2, 'spot_x') == knock_place.x * 16 + 8, 'he comes to where the knock was'
		// the figure leaves; the sentinel walks to the spot, looks round and goes back
		put_figure(mut sim, 2, 2)
		mut closest := 1000.0
		mut states := []int{}
		for _ in 0 .. 900 {
			sim.frame(0)
			d := (gx(sim, 2) - 15 * 16) * (gx(sim, 2) - 15 * 16) + (gy(sim, 2) -
				14 * 16) * (gy(sim, 2) - 14 * 16)
			closest = if d < closest { d } else { closest }
			st := gstate(sim, 2)
			if states.len == 0 || states.last() != st {
				states << st
			}
		}
		assert closest < 24 * 24, 'he got to within a tile or two of the spot (${closest})'
		assert states == [suspicious, returning, patrol] || states == [suspicious, patrol], 'suspicious, return, patrol: ${states}'
		post := s.find(0, `3`)[0]
		t := gtile(sim, 2)
		assert t.x == post.x && t.y == post.y, 'back at his post: ${t}'
		assert b.value('phase') == 0 && b.value('seen') == 0
		assert b.value('missed_frames') == 0
	}
}

fn test_a_crouched_figure_behind_cover_is_not_seen_where_a_standing_one_is() {
	s := spec()
	for pal in [false, true] {
		for crouched in [false, true] {
			mut b := loaded(s, pal)
			mut sim := Sim(b)
			// the first guard stands in the start room facing west, two cover blocks (5,4) and (6,4)
			// between him and the figure
			sim.poke_field('guards', 0, 'pause', 255)
			sim.poke_field('guards', 0, 'x', 8 * 16 * 65536)
			sim.poke_field('guards', 0, 'y', (4 * 16 - 1) * 65536)
			sim.poke_field('guards', 0, 'face', 128)
			sim.poke_field('guards', 0, 'stale', 1)
			put_figure(mut sim, 4, 4)
			mut first_seen := -1
			for n in 0 .. 120 {
				sim.frame(if crouched { pad(.b) } else { u32(0) })
				if b.value('seen') > 0 && first_seen < 0 {
					first_seen = n
				}
			}
			if crouched {
				assert first_seen < 0, 'a crouched figure behind a cover block is not seen'
				assert gstate(sim, 0) == patrol
				// it is in a lit tile, though: the cone does reach it
				assert lit_by(sim, robot.ptile(sim)) & 1 != 0, 'the tile is lit'
			} else {
				assert first_seen >= 0 && first_seen < 40, 'a standing figure there is seen (${first_seen})'
				assert gstate(sim, 0) != patrol
			}
			assert b.value('missed_frames') == 0
		}
	}
}

// inside_wall tells whether a box overlaps a wall or cover block: the box is
// 10 by 10, 3 and 4 from the corner of the picture.
fn inside_wall(map_rows []string, px f64, py f64) bool {
	left := int(px) + 3
	top := int(py) + 4
	for y in [top, top + 9] {
		for x in [left, left + 9] {
			if x < 0 || y < 0 || y / 16 >= map_rows.len || x / 16 >= map_rows[0].len {
				return true
			}
			if robot.is_blocking(map_rows[y / 16][x / 16]) {
				return true
			}
		}
	}
	return false
}

fn test_guards_never_walk_through_a_wall_and_never_stay_stuck() {
	s := spec()
	map_rows := s.rows_of(0)
	for pal in [false, true] {
		mut b := loaded(s, pal)
		mut sim := Sim(b)
		// the figure waits in its corner where nobody looks
		mut last_wp := [0, 0, 0, 0]
		mut changes := [0, 0, 0, 0]
		mut last_moved := [0, 0, 0, 0]
		mut last_pos := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
		frames := if pal { 2000 } else { 2400 }
		for n in 0 .. frames {
			sim.frame(0)
			for i in 0 .. 4 {
				assert !inside_wall(map_rows, gx(sim, i), gy(sim, i)), 'guard ${i} is in a wall at ${gx(sim,
					i)}, ${gy(sim, i)} after ${n} frames'

				wp := b.field('guards', i, 'wp')
				if wp != last_wp[i] {
					changes[i]++
					last_wp[i] = wp
				}
				if gx(sim, i) != last_pos[i][0] || gy(sim, i) != last_pos[i][1] {
					last_moved[i] = n
					last_pos[i] = [gx(sim, i), gy(sim, i)]
				}
				if i != 2 && i != 3 {
					assert n - last_moved[i] < 120, 'guard ${i} has not moved for ${n - last_moved[i]} frames at ${gx(sim,
						i)}, ${gy(sim, i)}'
				}
			}
			assert b.value('phase') == 0, 'nobody sees the figure in the corner (frame ${n})'
		}
		// the two patrolling guards go to and fro (a leg is about 300 frames)
		assert changes[0] > frames / 600 && changes[1] > frames / 600, 'every guard that has a route makes progress along it: ${changes}'
		assert b.value('missed_frames') == 0
	}
}

fn test_a_figure_pushed_about_at_random_never_enters_a_wall() {
	s := spec()
	map_rows := s.rows_of(0)
	mut b := loaded(s, false)
	mut sim := Sim(b)
	mut seed := u32(12345)
	mut mask := u32(0)
	for n in 0 .. 3000 {
		if n % 12 == 0 {
			seed = seed * 1664525 + 1013904223
			mask = (seed >> 16) & 0xf // a direction: up, down, left, right
			if (seed >> 20) & 1 == 1 {
				mask |= pad(.a)
			}
		}
		sim.frame(mask)
		assert !inside_wall(map_rows, fixed_of(b.value('px')), fixed_of(b.value('py'))), 'in a wall after ${n} frames'
		if b.value('phase') != 0 {
			robot.force_play(mut sim) // caught or through: it does not matter here
		}
	}
	assert b.value('missed_frames') == 0
}

fn test_the_chase_and_the_search_are_the_same_in_the_interpreter_and_on_the_machine() {
	s := spec()
	for pal in [false, true] {
		mut b := loaded(s, pal)
		mut sim := Sim(b)
		mut it := s.rig(pal)
		mut its := Sim(it)
		robot.enter_mission(mut its, 0)
		mut seed := u32(99)
		mut mask := u32(0)
		mut visited := map[int]bool{}
		for n in 0 .. 2000 {
			if n % 20 == 0 {
				seed = seed * 1664525 + 1013904223
				mask = (seed >> 16) & 0xf
				if (seed >> 20) & 3 == 0 {
					mask |= pad(.a)
				}
				if (seed >> 22) & 7 == 0 {
					mask |= pad(.b)
				}
				if (seed >> 25) & 7 == 0 {
					mask |= pad(.c)
				}
			}
			if n % 250 == 5 {
				// put the figure in front of a guard (the same on both)
				seed = seed * 1664525 + 1013904223
				g := int((seed >> 16) % 4)
				t := gtile(sim, g)
				for ps in [Sim(b), Sim(it)] {
					mut one := ps
					put_figure(mut one, int_max(1, int_min(26, t.x + 2)), t.y)
				}
			}
			if n % 250 == 90 {
				// and away again, so that whoever chased has lost it
				for ps in [Sim(b), Sim(it)] {
					mut one := ps
					put_figure(mut one, 2, 2)
				}
			}
			if b.value('phase') != 0 {
				mask = pad(.a) // play again
			}
			// guide:gg_compare
			sim.frame(mask)
			its.frame(mask)
			for name in ['px', 'py', 'phase', 'seen', 'alerts', 'level', 'secs', 'camera_x',
				'camera_y'] {
				assert b.value(name) == it.value(name), 'frame ${n}: ${name}: machine ${b.value(name)}, interpreter ${it.value(name)}'
			}
			for i in 0 .. 4 {
				assert gstate(b, i) == gstate(it, i), 'frame ${n}: guard ${i}: machine ${robot.state_names[gstate(b,
					i)]}, interpreter ${robot.state_names[gstate(it, i)]}'

				visited[gstate(b, i)] = true
				for field in ['x', 'y', 'face', 'wp', 'mleft', 'look', 'stuck', 'cone_n'] {
					assert b.field('guards', i, field) == it.field('guards', i, field), 'frame ${n}: guard ${i} ${field}: machine ${b.field('guards',
						i, field)}, interpreter ${it.field('guards', i, field)}'
				}
			}
			// guide:end
		}
		assert visited.len >= 3 && visited[alert], 'the guards were suspicious and chased: ${visited.keys()}'
		mut differences := b.img.differences(it.it, b.p.m.ram)
		differences = differences.filter(!it.contains('_dirty') && !it.contains('_stale')
			&& !it.contains('rt_eeprom') && !it.contains('rt_fade_applied'))
		assert differences.len == 0, differences.join('\n')
		assert b.value('missed_frames') == 0
	}
}
