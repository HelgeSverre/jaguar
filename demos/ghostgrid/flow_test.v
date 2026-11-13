module main

import os
import jaggame
import jagkit
import demos.ghostgrid.robot { Sim, pad, put_figure, run_frames, scene_of, screen_text, tap }

// The flow of the game from the title to the mission and back: the screens,
// the menus, the fade between scenes, the pause menu, the music and the
// backdrop. And the screenshots of the guide, made from the real image when
// GHOSTGRID_SHOTS names a directory.

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

fn test_the_game_goes_from_the_title_through_the_menus_the_briefing_and_the_pause_menu() {
	s := spec()
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		run_frames(mut sim, 5, 0)
		assert scene_of(sim) == robot.scene_title
		assert screen_text(sim, 3, 7, 9) == 'GHOSTGRID'
		assert b.value('rt_backdrop_on') == 1, 'the backdrop is behind the title'
		tap(mut sim, .a)
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_picker
		run_frames(mut sim, 20, 0)
		assert screen_text(sim, 1, 5, 14) == 'SELECT MISSION'
		assert screen_text(sim, 3, 3, 8) == 'DEPOT   ' && screen_text(sim, 3, 12, 1) == '-', 'no record yet'
		assert screen_text(sim, 4, 3, 8) == 'ARCHIVE ' && screen_text(sim, 4, 12, 6) == 'LOCKED', 'only the first mission is open'
		assert screen_text(sim, 11, 1, 8) == 'PAGE 1/2'
		// a locked mission is refused: the select stays
		tap(mut sim, .down)
		assert b.value('picker_cursor') == 1
		tap(mut sim, .a)
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_picker
		// the other page
		for b.value('picker_cursor') != 5 {
			tap(mut sim, .down)
		}
		assert screen_text(sim, 8, 3, 9) == 'NEXT PAGE'
		tap(mut sim, .a)
		assert b.value('page') == 1
		assert screen_text(sim, 3, 3, 8) == 'STACKS  ' && screen_text(sim, 7, 3, 8) == 'GAUNTLET'
		assert screen_text(sim, 11, 1, 8) == 'PAGE 2/2'
		// BACK goes to the title, through black
		tap(mut sim, .down)
		assert b.value('picker_cursor') == 6 && screen_text(sim, 9, 3, 4) == 'BACK'
		sim.frame(pad(.a))
		run_frames(mut sim, 3, 0)
		assert b.value('scenes_fading') == 1
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_title
		// the title again, the first mission, its briefing
		run_frames(mut sim, 3, 0)
		tap(mut sim, .pause)
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_picker
		tap(mut sim, .a)
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_brief
		assert screen_text(sim, 1, 2, 5) == 'DEPOT' && screen_text(sim, 1, 12, 5) == 'SNEAK'
		assert screen_text(sim, 3, 2, 20) == 'FOUR GUARDS WALK THE'
		assert screen_text(sim, 9, 2, 1) == 'S' && screen_text(sim, 9, 4, 3) == '  9'
		assert screen_text(sim, 11, 2, 17) == 'A START    B BACK'
		// B goes back to the select; A, A starts the mission
		tap(mut sim, .b)
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_picker
		tap(mut sim, .a)
		robot.settle(mut sim)
		tap(mut sim, .a)
		robot.ready(mut sim)
		assert scene_of(sim) == robot.scene_play && b.value('rt_backdrop_on') == 0
		assert b.value('rt_music') == 1, 'the calm track'
		// pause: the guards stand still; resume
		run_frames(mut sim, 30, 0)
		sim.frame(pad(.pause))
		assert b.value('paused') == 1 && b.field('sprites', 12, 'visible') == 1, 'a panel behind the menu'
		g0 := b.field('guards', 0, 'x') + b.field('guards', 0, 'y')
		clock := b.value('clock_elapsed')
		run_frames(mut sim, 40, 0)
		assert b.field('guards', 0, 'x') + b.field('guards', 0, 'y') == g0
			&& b.value('clock_elapsed') == clock
		assert screen_text(sim, 2, 9, 6) == 'PAUSED'
		sim.frame(pad(.a))
		assert b.value('paused') == 0 && b.field('sprites', 12, 'visible') == 0
		run_frames(mut sim, 20, 0)
		assert b.value('clock_elapsed') > clock, 'the mission goes on'
		// restart from the pause menu
		sim.frame(pad(.pause))
		run_frames(mut sim, 3, 0)
		tap(mut sim, .down)
		sim.frame(pad(.a))
		robot.ready(mut sim)
		assert b.value('clock_elapsed') < 100 && b.value('paused') == 0
			&& scene_of(sim) == robot.scene_play
		// quit to the mission select
		sim.frame(pad(.pause))
		run_frames(mut sim, 3, 0)
		for _ in 0 .. 2 {
			tap(mut sim, .down)
		}
		sim.frame(pad(.a))
		robot.settle(mut sim)
		assert scene_of(sim) == robot.scene_picker
		assert b.value('rt_backdrop_on') == 1 && b.value('missed_frames') == 0
	}
}

fn test_a_scene_change_goes_through_black_the_colour_table_follows_and_no_frame_is_missed() {
	s := spec()
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		run_frames(mut sim, 10, 0)
		// the text colour of the first layer is the last entry of the colour table
		full := int(b.p.m.tom.clut[255]) & 0xff
		assert full > 100 && b.value('rt_fade') == 16
		mut levels := []int{}
		mut dim := []int{}
		mut scenes_at := []int{}
		for n in 0 .. 40 {
			sim.frame(if n == 2 { pad(.a) } else { u32(0) })
			levels << b.value('rt_fade')
			dim << int(b.p.m.tom.clut[255]) & 0xff
			scenes_at << scene_of(sim)
		}
		assert levels[..3] == [16, 16, 16]
		first_dark := levels.index(0)
		assert first_dark > 0 && levels[first_dark - 1] == 2, 'it dims in steps of two to black: ${levels}'
		assert scenes_at[first_dark - 1] == robot.scene_title
			&& scenes_at[first_dark] == robot.scene_picker, 'the scenes change while it is black'
		assert levels.last() == 16, 'and comes back: ${levels}'
		// the colour table dims with it, and is back at the end
		assert dim[first_dark] == 0 && dim.last() == full, 'the colour table: ${dim}'
		mut steps_up := 0
		for k in first_dark + 1 .. levels.len {
			if levels[k] > levels[k - 1] {
				steps_up++
			}
		}
		assert steps_up >= 7, 'it fades in over eight frames: ${steps_up}'
		assert b.value('missed_frames') == 0
	}
}

fn test_the_music_follows_the_alarm_and_keeps_its_tempo() {
	s := spec()
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		// the title already plays the calm track; ten seconds of it keep the tempo (5.5 rows a second)
		run_frames(mut sim, 10 * (if pal { 50 } else { 60 }), 0)
		rows := b.value('rt_music_rows')
		assert rows >= 54 && rows <= 56, '${rows} rows in ten seconds'
		robot.enter_mission(mut sim, 0)
		assert b.value('rt_music') == 1
		put_figure(mut sim, 9, 8)
		mut last_rows := b.value('rt_music_rows')
		mut alert_frames := 0
		mut jumps := 0
		for _ in 0 .. 500 {
			sim.frame(0)
			if b.value('phase') != 0 {
				break
			}
			now := b.value('rt_music_rows')
			if b.value('rt_music') == 2 {
				alert_frames++
				if now - last_rows > 1 {
					jumps++
				}
			}
			last_rows = now
		}
		assert alert_frames > 10, 'the alert track played (${alert_frames} frames)'
		assert jumps == 0, 'the track is not restarted while the alarm goes on'
		// the voices the DSP got come from one of the two tracks
		calm_lead := [57, 62, 64, 65, 67, 69, 72, 74].map(i64(jagkit.note_step(it)))
		alert_lead := [62, 67, 68, 71, 72, 73, 76, 77].map(i64(jagkit.note_step(it)))
		lead := b.element('rt_voice', 0)
		assert lead == 0 || lead in alert_lead || lead in calm_lead
	}
}

fn test_the_title_shows_the_backdrop_and_the_mission_does_not() {
	s := spec()
	mut b := s.boot(false)
	mut sim := Sim(b)
	run_frames(mut sim, 20, 0)
	assert b.value('rt_backdrop_on') == 1
	mailbox := jaggame.backdrop_mailbox()
	drawn := b.p.m.peek32(mailbox + 40)
	run_frames(mut sim, 10, 0)
	assert b.p.m.peek32(mailbox + 40) > drawn, 'the GPU draws the backdrop on the title'
	robot.enter_mission(mut sim, 0)
	run_frames(mut sim, 5, 0)
	stopped := b.p.m.peek32(mailbox + 40)
	run_frames(mut sim, 30, 0)
	assert b.p.m.peek32(mailbox + 40) == stopped, 'and is left alone in the mission'
}

fn test_the_four_buttons_together_go_back_to_the_title_and_the_pause_menu_dims_the_room() {
	s := spec()
	mut b := s.boot(false)
	mut sim := Sim(b)
	robot.enter_mission(mut sim, 0)
	run_frames(mut sim, 20, 0)
	assert b.value('rt_fade') == 16
	full := int(b.p.m.tom.clut[1]) & 0xff
	assert full > 20, 'a colour of the palette: ${full}'
	// the pause menu halves the brightness of the room behind it
	sim.frame(pad(.pause))
	run_frames(mut sim, 3, 0)
	assert b.value('rt_fade') == 8 && b.value('paused') == 1
	assert int(b.p.m.tom.clut[1]) & 0xff == full / 2, 'the colour table is at half: ${int(b.p.m.tom.clut[1]) & 0xff} of ${full}'
	sim.frame(pad(.a)) // RESUME
	run_frames(mut sim, 3, 0)
	assert b.value('rt_fade') == 16 && int(b.p.m.tom.clut[1]) & 0xff == full
	// A, B, C and Option together: through black to the title, from the mission
	sim.frame(pad(.a, .b, .c, .option))
	run_frames(mut sim, 3, 0)
	assert b.value('scenes_fading') == 1
	robot.settle(mut sim)
	assert scene_of(sim) == robot.scene_title
	assert b.value('rt_backdrop_on') == 1 && b.value('paused') == 0
	// on the title the four buttons are just A: on to the mission select
	sim.frame(pad(.a, .b, .c, .option))
	robot.settle(mut sim)
	assert scene_of(sim) == robot.scene_picker
	assert b.value('missed_frames') == 0
}

// ---- the picture ----

// tile_colours are the colours of the tile set as the machine shows them:
// 16 by 16 pixels for each tile, 0x00RRGGBB.
fn tile_colours() [][]u32 {
	return robot.tile_colours(os.join_path(art_dir(), 'tiles.png'))
}

fn test_the_picture_shows_the_room_and_the_cones_as_lit_floor() {
	s := spec()
	tiles := tile_colours()
	assert tiles.len == 12
	for pal in [false, true] {
		mut b := s.boot(pal)
		mut sim := Sim(b)
		robot.enter_mission(mut sim, 0)
		run_frames(mut sim, 100, 0)
		b.find_origin(tiles, jaggame.cry(6, 8, 20))
		for n in 0 .. 3 {
			run_frames(mut sim, 37, 0)
			// the picture is a frame behind and the tiles a few more
			run_frames(mut sim, 3, 0)
			good, all := b.matches(tiles, jaggame.cry(6, 8, 20), 1)
			assert all > 60000, 'most of the screen is room: ${all}'
			// a tile is drawn in place while it may be on its way to the screen, so a
			// few pixels of a tile that changed this frame can be old
			assert good * 100 >= all * 99, 'the picture shows the map (round ${n}): ${all - good} of ${all} pixels are wrong'
		}
		// and there is light on the floor
		pic := b.p.picture()
		mut lit_pixels := 0
		for sy in 0 .. 240 {
			for sx in 0 .. 320 {
				if pic.at(sx + b.ox, sy + b.oy) == tiles[tile_floor_lit][5 * 16 + 5] {
					lit_pixels++
				}
			}
		}
		assert lit_pixels > 20, 'the lit floor is in the picture: ${lit_pixels}'
	}
}

// ---- the screenshots of the guide ----

// record_bytes is a record with the first `done` missions done: each with a
// rank and a time, and `done + 1` missions open.
fn record_bytes(done int) []u8 {
	ranks := [4, 3, 4, 3, 2, 3, 3, 1, 2, 4]
	times := [11, 52, 18, 40, 63, 47, 20, 130, 77, 15]
	mut words := [0x4702]
	for k in 0 .. 10 {
		mut word := 0
		if k < done {
			word = ranks[k] * 4096 + times[k]
		}
		words << word
	}
	words << done + 1
	mut sum := 0x5a5a
	for w in words {
		sum += w
	}
	words << sum & 0xffff
	mut bytes := []u8{}
	for w in words {
		bytes << u8(w >> 8)
		bytes << u8(w)
	}
	for _ in words.len .. 64 {
		bytes << [u8(0xff), 0xff]
	}
	return bytes
}

fn test_the_screenshots_of_the_guide() {
	dir := os.getenv('GHOSTGRID_SHOTS')
	if dir == '' {
		return
	}
	s := spec()
	shot := fn [dir] (b &robot.Booted, name string) {
		b.save_picture(os.join_path(dir, 'ghostgrid-${name}.png')) or { panic(err) }
	}
	// the title, and the mission select with a record
	mut t := s.boot(false)
	mut tsim := Sim(t)
	run_frames(mut tsim, 110, 0)
	shot(t, 'title')
	mut p := s.boot(false)
	p.p.m.eeprom.load_bytes(record_bytes(7))!
	mut psim := Sim(p)
	robot.to_picker(mut psim)
	run_frames(mut psim, 40, 0)
	tap(mut psim, .down)
	tap(mut psim, .down)
	shot(p, 'picker')
	// the first mission as it starts, and scrolled to the exit; a chase
	mut r := s.boot(false)
	mut rsim := Sim(r)
	robot.enter_mission(mut rsim, 0)
	run_frames(mut rsim, 120, 0)
	shot(r, 'room')
	exit := s.find(0, `X`)[0]
	put_figure(mut rsim, exit.x - 1, exit.y + 1)
	run_frames(mut rsim, 20, 0)
	shot(r, 'scrolled')
	mut g := s.boot(false)
	mut gsim := Sim(g)
	robot.enter_mission(mut gsim, 0)
	put_figure(mut gsim, 9, 8)
	mut waited := 0
	for g.value('level') != 2 && waited < 400 {
		gsim.frame(0)
		waited++
	}
	run_frames(mut gsim, 8, 0)
	shot(g, 'alert')
	mut gd := s.boot(false)
	mut gdsim := Sim(gd)
	robot.enter_mission(mut gdsim, 0)
	run_frames(mut gdsim, 220, 0)
	shot(gd, 'guards')
	// the new kinds: chips, the clock, a second room, a camera that has seen the figure
	mut c := s.boot(false)
	mut csim := Sim(c)
	robot.enter_mission(mut csim, 1)
	chips := s.find(s.first[1], `$`)
	put_figure(mut csim, chips[0].x, chips[0].y)
	run_frames(mut csim, 40, 0)
	shot(c, 'collect')
	mut tm := s.boot(false)
	mut tmsim := Sim(tm)
	robot.enter_mission(mut tmsim, 2)
	run_frames(mut tmsim, 150, pad(.right))
	shot(tm, 'timed')
	mut rm := s.boot(false)
	mut rmsim := Sim(rm)
	robot.enter_mission(mut rmsim, 3)
	door := s.find(s.first[3], `D`)[0]
	put_figure(mut rmsim, door.x, door.y)
	run_frames(mut rmsim, 3, 0)
	robot.ready(mut rmsim)
	run_frames(mut rmsim, 60, 0)
	shot(rm, 'rooms')
	mut cm := s.boot(false)
	mut cmsim := Sim(cm)
	robot.enter_mission(mut cmsim, 4)
	run_frames(mut cmsim, 30, 0)
	mut seen_cell := -1
	for cell in 0 .. room_cells {
		if cm.element('lit', cell) & 0x10 != 0 {
			seen_cell = cell
		}
	}
	put_figure(mut cmsim, seen_cell % room_cols, seen_cell / room_cols)
	run_frames(mut cmsim, 30, 0)
	shot(cm, 'cameras')
	// the result of a mission done by the robot, with a rank
	plan := s.plan_mission(0, robot.Options{}) or {
		assert false, 'no plan'
		return
	}
	mut d := s.boot(false)
	mut dsim := Sim(d)
	s.play(mut dsim, 0, plan, robot.nothing)
	shot(d, 'result')
}
