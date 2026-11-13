module main

import os
import jaggame
import demos.ghostgrid.robot { Sim, pad }

// What a frame costs, mission by mission. The worst case of each room is
// played on the machine with the music: every guard of the room chasing the
// figure, which runs, in the open middle of the room, the cameras sweeping,
// the cones moving. Frames in which a scene changes are left out and counted
// apart (they have the new scene's work in them), and so are the frames of a
// room loading, which are measured on their own.

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

// open_spot is the tile of a room with the most floor within five tiles, and
// four places round it, four tiles away, for the guards.
fn open_spot(rows []string) (jaggame.Point, []jaggame.Point) {
	mut best := jaggame.Point{1, 1}
	mut best_n := -1
	for y in 1 .. room_rows - 1 {
		for x in 1 .. room_cols - 1 {
			if !passable(rows[y][x]) {
				continue
			}
			mut n := 0
			for dy in -5 .. 6 {
				for dx in -5 .. 6 {
					yy := y + dy
					xx := x + dx
					if yy >= 0 && yy < room_rows && xx >= 0 && xx < room_cols
						&& passable(rows[yy][xx]) {
						n++
					}
				}
			}
			if n > best_n {
				best_n = n
				best = jaggame.Point{x, y}
			}
		}
	}
	mut places := []jaggame.Point{}
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
		mut found := best
		for r in [4, 3, 2, 1] {
			x := best.x + d[0] * r
			y := best.y + d[1] * r
			if x > 0 && y > 0 && x < room_cols - 1 && y < room_rows - 1 && passable(rows[y][x]) {
				found = jaggame.Point{x, y}
				break
			}
		}
		places << found
	}
	return best, places
}

struct Costs {
	mean   int
	p90    int
	max    int
	over   int // the dearest frame in which a scene changed, left out of the others
	missed int // frames missed while they were measured
	music  int // frames of them in which the alert music was playing
}

// chase_room plays the worst case in the room the mission is in now and
// measures `frames` frames of it.
fn chase_room(mut b robot.Booted, rows []string, guards int, frames int) Costs {
	mut sim := Sim(b)
	spot, places := open_spot(rows)
	robot.put_figure(mut sim, spot.x, spot.y)
	for i in 0 .. guards {
		b.poke_field('guards', i, 'x', places[i].x * 16 * 65536)
		b.poke_field('guards', i, 'y', (places[i].y * 16 - 1) * 65536)
	}
	dirs := [pad(.right), pad(.down), pad(.left), pad(.up)]
	mut all := []int{}
	mut ended := 0
	mut music := 0
	missed0 := b.value('missed_frames')
	for n in -40 .. frames {
		for i in 0 .. guards {
			b.poke_element('guard_ai_state', i, robot.alert)
			b.poke_field('guards', i, 'lost', 0)
		}
		robot.force_play(mut sim)
		cyc := b.cost_frame(dirs[((n + 40) / 45) % 4] | pad(.a))
		if n < 0 {
			continue
		}
		if robot.scene_of(sim) != robot.scene_play {
			ended = if cyc > ended { cyc } else { ended }
			continue
		}
		all << cyc
		if os.getenv('GG_DEBUG') != '' && cyc > 118000 {
			println('  frame ${n}: ${cyc} worked ${b.value('worked')} queued ${b.value('rt_tile_count')} row ${b.value('rt_music_rows')} level ${b.value('level')}')
		}
		if b.value('rt_music') == 2 {
			music++
		}
	}
	all.sort()
	mut total := 0
	for a in all {
		total += a
	}
	return Costs{total / all.len, all[all.len * 9 / 10], all[all.len - 1], ended, b.value('missed_frames') - missed0, music}
}

// at_room plays the robot's plan until the figure is in room `k` of a mission.
fn at_room(s robot.Spec, mut b robot.Booted, mission int, k int) {
	mut sim := Sim(b)
	robot.enter_mission(mut sim, mission)
	if k == 0 {
		return
	}
	plan := s.plan_mission(mission, robot.Options{}) or { panic('no plan for mission ${mission}') }
	for j in 0 .. k {
		s.execute(mut sim, plan.rooms[j], robot.nothing)
		robot.ready(mut sim)
	}
}

fn test_the_worst_frame_of_every_room_is_under_60_percent_of_a_frame_with_music() {
	s := spec()
	l := layout()
	defs := missions()
	println('mission  room  std   guards cams   mean    p90    max   max%  missed')
	mut worst := 0
	for pal in [false, true] {
		budget := robot.frame_cycles(pal)
		for m, def in defs {
			if os.getenv('GG_MISSIONS') != ''
				&& !os.getenv('GG_MISSIONS').split(',').contains('${m}') {
				continue
			}
			for k, room in def.rooms {
				mut b := s.boot(pal)
				at_room(s, mut b, m, k)
				mut sim := Sim(b)
				robot.run_frames(mut sim, 30, 0)
				costs := chase_room(mut b, s.rows_of(l.first[m] + k), room.guards.len, 500)
				pct := costs.max * 100 / budget
				println('${def.title:-8} ${k}     ${if pal { 'PAL ' } else { 'NTSC' }}  ${room.guards.len}      ${room.cameras.len}    ${costs.mean:6} ${costs.p90:6} ${costs.max:6}  ${pct:3}%  ${costs.missed}')
				assert costs.music * 2 > 500, '${def.title}: the alert music plays (${costs.music} frames)'
				assert costs.max * 100 <= budget * 60, '${def.title} room ${k}: the most expensive frame is ${costs.max} of ${budget} cycles'
				assert costs.missed == 0, '${def.title} room ${k}: ${costs.missed} frames missed'
				if costs.max > worst {
					worst = costs.max
				}
			}
		}
	}
	println('the most expensive frame of all: ${worst}')
}

// What a scene change and a room load cost, from the title to the mission and
// back through a door: the dearest frame of each kind, and the frames missed.
// They may blank the picture; they may not miss frames.
fn test_room_loads_scene_changes_and_fades_miss_no_frame() {
	s := spec()
	mut fade_max := 0
	mut load_max := 0
	mut enter_max := 0
	mut other_max := 0
	for pal in [false, true] {
		budget := robot.frame_cycles(pal)
		mut b := s.boot(pal)
		mut sim := Sim(b)
		mut last_scene := -1
		script := [[10, int(pad(.a))], [80, int(pad(.a))], [140, int(pad(.a))]]
		mut frames_in_play := 0
		mut first := 0
		for n in 0 .. 420 {
			mut mask := u32(0)
			for sc in script {
				if n == sc[0] {
					mask = u32(sc[1])
				}
			}
			cyc := b.cost_frame(mask)
			if n == 0 {
				first = cyc // the first frame after power on, before any picture
				continue
			}
			scene := robot.scene_of(sim)
			fading := b.value('scenes_fading') != 0
			loading := b.value('loading') != 0
			if scene != last_scene {
				enter_max = if cyc > enter_max { cyc } else { enter_max }
				last_scene = scene
			} else if loading {
				load_max = if cyc > load_max { cyc } else { load_max }
			} else if fading {
				fade_max = if cyc > fade_max { cyc } else { fade_max }
			} else if n > 5 {
				other_max = if cyc > other_max { cyc } else { other_max }
			}
			if scene == robot.scene_play {
				frames_in_play++
			}
			assert cyc < budget, 'frame ${n} (scene ${scene}) took ${cyc} of ${budget}'
		}
		assert frames_in_play > 100
		assert b.value('missed_frames') == 0, '${b.value('missed_frames')} frames missed'
		println('${if pal { 'PAL ' } else { 'NTSC' }}: the first frame ${first}, a frame that changes scene up to ${enter_max}, a room loading ${load_max}, a fade ${fade_max}, anything else ${other_max}; missed ${b.value('missed_frames')}')
	}
}
