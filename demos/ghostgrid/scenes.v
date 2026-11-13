// The scenes of GHOSTGRID: the title, the mission select, the briefing, the
// mission itself and its result. The pause menu is part of the mission (it
// stops the guards, not the scene). Each scene is a few lines here; what a
// scene does when it begins and ends, and the setup that is spread over
// frames, are the scene's own. Scenes are changed through black (`go_fade`),
// except into the result, which comes up over the room as it stood.
module main

import jaggame

const picker_rows = 5 // missions on a page of the mission select

// define_scenes writes the five scenes and says where the game starts.
fn (mut m Mission) define_scenes() {
	m.define_title()
	m.define_picker()
	m.define_brief()
	m.define_play()
	m.define_result()
	m.define_reset()
	m.scenes.start('title')
}

// define_reset writes the game's own update, which runs every frame whatever
// the scene: A, B, C and Option held together go back to the title from
// anywhere but the title.
fn (mut m Mission) define_reset() {
	mut game := m.game
	// guide:gg_reset
	mut c := game.define_update()
	all_four := game.held(.a).both(game.held(.b)).both(game.held(.c)).both(game.held(.option))

	c.if_(all_four.both(m.scenes.in_scene('title').invert()).both(m.scenes.settled()))
	game.play(mut c, 'menu_select')
	m.scenes.go_fade(mut c, 'title')
	c.end() // the four buttons
	// guide:end
}

// menu_screen is what a title or a menu has: the backdrop, no room, no
// sprites and no status lines.
fn (mut m Mission) menu_screen(mut c jaggame.Code) {
	mut game := m.game
	// guide:gg_screen
	for s in 0 .. 14 {
		game.sprite(s).hide(mut c)
	}
	game.hide_room(mut c)
	game.backdrop_show(mut c)
	m.hud.clear(mut c)
	m.status.clear(mut c)
	m.msg.clear(mut c)
	// guide:end
}

// define_title writes the title screen: the backdrop, the calm music and a
// prompt that blinks.
fn (mut m Mission) define_title() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_title
	mut c := scenes.on_enter('title')
	m.menu_screen(mut c)
	c.set(m.msg.colour, jaggame.cry(150, 235, 255))
	m.msg.print(mut c, 7, 3, 'GHOSTGRID')
	m.msg.print(mut c, 3, 5, 'A STEALTH TRAINER')
	game.music_play(mut c, 'calm')

	c = scenes.scene('title')
	c.if_(game.music_is('calm').both(game.music_rows().and(8).ne(0)))
	m.msg.print(mut c, 8, 9, 'PRESS A')
	c.else_()
	m.msg.print(mut c, 8, 9, '       ')
	c.end() // blink, on the beat of the music

	c.if_(game.pressed(.a).either(game.pressed(.pause)))
	game.play(mut c, 'menu_select')
	c.set(m.page, 0)
	scenes.go_fade(mut c, 'picker')
	c.end() // go on
	// guide:end
}

// print_padded writes a mission's title in eight cells.
fn (m &Mission) print_padded(mut c jaggame.Code, col int, row jaggame.Val, title string) {
	m.msg.print(mut c, col, row, title + ' '.repeat(8 - title.len))
}

// letter writes the letter of a rank (4 S, 3 A, 2 B, 1 C) or a dash for none.
fn (m &Mission) letter(mut c jaggame.Code, col int, row int, rank jaggame.Expr) {
	c.if_(rank.eq(4))
	m.msg.print(mut c, col, row, 'S')
	c.else_if(rank.eq(3))
	m.msg.print(mut c, col, row, 'A')
	c.else_if(rank.eq(2))
	m.msg.print(mut c, col, row, 'B')
	c.else_if(rank.eq(1))
	m.msg.print(mut c, col, row, 'C')
	c.else_()
	m.msg.print(mut c, col, row, '-')
	c.end() // which rank
}

// clock_at writes seconds as minutes and seconds, 4 cells wide.
fn (m &Mission) clock_at(mut c jaggame.Code, col int, row int, secs jaggame.Expr) {
	m.msg.number(mut c, col, row, secs.div(60), 1)
	m.msg.print(mut c, col + 1, row, ':')
	m.msg.number(mut c, col + 2, row, secs.mod(60).div(10), 1)
	m.msg.number(mut c, col + 3, row, secs.mod(10), 1)
}

// draw_page writes the page of the mission select that is up: the title of
// each mission, its best rank and best time, or LOCKED. The record of a
// mission is in `bests`: the rank in the top four bits and the seconds below.
fn (mut m Mission) draw_page(mut c jaggame.Code) {
	// guide:gg_page
	for k, def in m.world.defs {
		row := 3 + k % picker_rows

		c.if_(m.page.eq(k / picker_rows))
		m.print_padded(mut c, 3, row, def.title)

		c.if_(m.unlocked.gt(k))
		rank := m.bests.at(k).shr(12)
		secs := m.bests.at(k).and(0xfff)
		m.msg.print(mut c, 12, row, '  ')
		m.letter(mut c, 12, row, rank)

		c.if_(rank.ne(0))
		m.clock_at(mut c, 14, row, secs)
		c.else_()
		m.msg.print(mut c, 14, row, '    ')
		c.end() // a record, or none
		c.else_()
		m.msg.print(mut c, 12, row, 'LOCKED')
		c.end() // open, or locked
		c.end() // this page
	}
	m.msg.number(mut c, 6, 11, m.page.add(1), 1)
	// guide:end
}

// define_picker writes the mission select: five missions a page, the best
// rank and time of each, read from the saved record.
fn (mut m Mission) define_picker() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_picker
	mut c := scenes.on_enter('picker')
	m.menu_screen(mut c)
	c.set(m.best_up, false)
	m.save.load(mut c)

	// The screen is written in two frames, behind the black of the fade.
	c = scenes.setup('picker', 2)
	c.if_(scenes.step.eq(0))
	c.set(m.msg.colour, jaggame.cry(255, 255, 255))
	m.msg.print(mut c, 5, 1, 'SELECT MISSION')
	m.msg.print(mut c, 1, 11, 'PAGE')
	m.msg.print(mut c, 7, 11, '/2')
	m.picker.open(mut c)
	c.end() // the frame and the menu
	c.if_(scenes.step.eq(1))
	m.draw_page(mut c)
	c.end() // the missions

	c = scenes.scene('picker')
	m.picker.update(mut c)

	c.if_(m.picker.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	// The record is read a word a frame; when it is in, the page is drawn again.
	c.if_(m.save.busy().invert().both(m.best_up.invert()))
	c.set(m.best_up, true)
	m.load_record(mut c)
	m.draw_page(mut c)
	c.end() // the record arrived

	c.if_(m.picker.chosen.lt(picker_rows))
	c.set(m.mission, m.page.mul(picker_rows).add(m.picker.chosen))

	c.if_(m.mission.lt(m.unlocked))
	game.play(mut c, 'menu_select')
	scenes.go_fade(mut c, 'brief')
	c.else_()
	game.play(mut c, 'denied')
	c.end() // open, or locked
	c.else_if(m.picker.chosen.eq(picker_rows))
	game.play(mut c, 'menu_select')
	c.set(m.page, m.page.xor(1))
	m.draw_page(mut c)
	c.else_if(m.picker.chosen.eq(picker_rows + 1).either(m.picker.backed))
	game.play(mut c, 'menu_select')
	scenes.go_fade(mut c, 'title')
	c.end() // what was chosen
	// guide:end
}

// load_record copies the saved record into the game's variables: a record
// for each mission, and how many are open (at least the first).
fn (m &Mission) load_record(mut c jaggame.Code) {
	// guide:gg_record
	for k in 0 .. mission_count {
		c.set(m.bests.at(k), m.save.field('m${k}'))
	}
	c.set(m.unlocked, m.save.field('open').max(1))
	// guide:end
}

// store_record copies the game's variables into the record and writes it.
fn (m &Mission) store_record(mut c jaggame.Code) {
	for k in 0 .. mission_count {
		c.set(m.save.field('m${k}'), m.bests.at(k))
	}
	c.set(m.save.field('open'), m.unlocked)
	m.save.store(mut c)
}

// define_brief writes the briefing: the mission's name and kind, what it
// asks in a few lines of text broken at build time, and the scores that earn
// the ranks.
fn (mut m Mission) define_brief() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_brief
	mut c := scenes.on_enter('brief')
	m.menu_screen(mut c)

	c = scenes.setup('brief', 2)
	c.if_(scenes.step.eq(0))
	c.set(m.msg.colour, jaggame.cry(255, 255, 255))
	for k, def in m.world.defs {
		c.if_(m.mission.eq(k))
		m.msg.print(mut c, 2, 1, def.title)
		m.msg.print(mut c, 12, 1, def.kind.label())
		lines := m.msg.print_wrapped(mut c, 2, 3, 20, def.brief)
		check(lines <= 5, '${def.title}: the briefing has ${lines} lines, at most 5 fit')
		c.end() // this mission
	}
	c.end() // the mission's own words
	c.if_(scenes.step.eq(1))
	m.msg.print(mut c, 2, 9, 'S')
	m.msg.print(mut c, 8, 9, 'A')
	m.msg.print(mut c, 14, 9, 'B')
	m.msg.number(mut c, 4, 9, m.ms_rank_s.at(m.mission), 3)
	m.msg.number(mut c, 10, 9, m.ms_rank_a.at(m.mission), 3)
	m.msg.number(mut c, 16, 9, m.ms_rank_b.at(m.mission), 3)
	m.msg.print(mut c, 2, 11, 'A START    B BACK')
	c.end() // the scores and the keys

	c = scenes.scene('brief')
	c.if_(game.pressed(.a).either(game.pressed(.pause)))
	game.play(mut c, 'menu_select')
	m.start_mission(mut c, 'play')
	c.else_if(game.pressed(.b))
	game.play(mut c, 'menu_select')
	scenes.go_fade(mut c, 'picker')
	c.end() // go on, or back
	// guide:end
}

// define_play writes the mission as a scene: it loads the room when it
// begins and puts everything on its start in the frames after, then the
// update runs.
fn (mut m Mission) define_play() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_play
	mut c := scenes.on_enter('play')

	c.if_(game.backdrop_shown())
	game.backdrop_hide(mut c)
	c.end() // the backdrop is behind a menu
	game.load_room_number(mut c, m.room_of())
	c.set(m.clear_at, 0)
	game.music_play(mut c, 'calm')

	c = scenes.on_leave('play')
	c.set(m.paused, false)
	m.panel.hide(mut c)
	m.limit.stop(mut c)

	c = scenes.setup('play', max_guards + 2)
	m.define_play_setup(mut c)

	c = scenes.scene('play')
	m.define_play_update(mut c)
	// guide:end
}

// define_result writes the result: the room stands as it was behind a panel
// with the result on it. The rank, the record and the missions it opens are
// worked out and saved when the scene begins, and the screen is written a
// few lines a frame.
fn (mut m Mission) define_result() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_result
	mut c := scenes.on_enter('result')
	changed := c.local_bool('changed')
	packed := c.local_u16('packed')
	old_rank := c.local_u16('old_rank')
	old_time := c.local_u16('old_time')
	time := c.local_u16('time')
	c.set(m.new_best, false)
	c.set(m.has_next, false)
	game.music_stop(mut c)

	c.if_(m.phase.eq(1))
	game.play(mut c, 'complete')
	// the score: seconds, and 5 for each time seen, 15 for each alert
	c.set(m.score, m.secs.add(m.seen.mul(5)).add(m.alerts.mul(15)))
	c.set(m.rank,
		m.score.le(m.ms_rank_b.at(m.mission)).as_(.u8).add(m.score.le(m.ms_rank_a.at(m.mission)).as_(.u8)).add(m.score.le(m.ms_rank_s.at(m.mission)).as_(.u8)).add(1))
	c.set(packed, m.bests.at(m.mission))
	c.set(old_rank, packed.shr(12))
	c.set(old_time, packed.and(0xfff))
	c.set(time, m.secs.min(4095))

	c.if_(old_rank.eq(0).either(time.lt(old_time)))
	c.set(m.new_best, true)
	c.set(old_time, time)
	c.end() // a faster time
	c.set(changed, m.new_best.either(m.rank.as_(.u16).gt(old_rank)))
	c.set(m.bests.at(m.mission), old_rank.max(m.rank.as_(.u16)).shl(12).or_(old_time))

	// The next mission opens.
	c.if_(m.unlocked.lt(m.mission.as_(.u16).add(2)).both(m.mission.add(1).lt(mission_count)))
	c.set(m.unlocked, m.mission.as_(.u16).add(2))
	c.set(changed, true)
	c.end() // something new is open
	c.set(m.has_next, m.mission.add(1).lt(mission_count))

	c.if_(changed)
	m.store_record(mut c)
	c.end() // something to keep
	c.else_if(m.phase.eq(2))
	game.play(mut c, 'caught')
	c.else_()
	game.play(mut c, 'timeup')
	c.end() // done, caught or out of time

	c = scenes.setup('result', 4)
	step := scenes.step
	c.if_(step.eq(0))
	m.msg.clear(mut c)
	c.set(m.msg.colour, jaggame.cry(255, 255, 255))
	m.show_panel(mut c)

	c.if_(m.phase.eq(1))
	m.msg.print(mut c, 4, 0, 'MISSION COMPLETE')
	c.else_if(m.phase.eq(2))
	m.msg.print(mut c, 4, 0, 'YOU WERE CAUGHT')
	c.else_()
	m.msg.print(mut c, 4, 0, 'TIME IS UP')
	c.end() // done, caught or out of time
	c.end() // the title

	c.if_(step.eq(1))
	m.msg.print(mut c, 3, 2, 'TIME')
	m.clock_at(mut c, 9, 2, m.secs)
	m.msg.print(mut c, 3, 3, 'SEEN')
	m.msg.number(mut c, 9, 3, m.seen, 3)
	m.msg.print(mut c, 3, 4, 'ALERTS')
	m.msg.number(mut c, 10, 4, m.alerts, 2)
	c.end() // what happened

	c.if_(step.eq(2).both(m.phase.eq(1)))
	m.msg.print(mut c, 3, 5, 'SCORE')
	m.msg.number(mut c, 9, 5, m.score, 3)
	m.msg.print(mut c, 3, 6, 'RANK')
	m.letter(mut c, 9, 6, m.rank.as_(.u16))
	m.msg.print(mut c, 3, 7, 'BEST')
	m.clock_at(mut c, 9, 7, m.bests.at(m.mission).and(0xfff))

	c.if_(m.new_best)
	m.msg.print(mut c, 5, 1, 'NEW BEST TIME!')
	c.end() // a record
	c.end() // the rank

	c.if_(step.eq(3))

	c.if_(m.phase.eq(1))
	m.medal.put(mut c, 'medal', 212, 74, 3)
	c.set(m.medal.scale, 2.0)
	c.set(m.medal.fixed, true)
	c.set(m.medal.frame, m.rank.sub(1))
	c.end() // a medal
	c.if_(m.has_next)
	m.win.open(mut c)
	c.else_()
	m.lose.open(mut c)
	c.end() // which menu
	c.end() // the menu

	c = scenes.scene('result')
	c.if_(m.has_next)
	m.win.update(mut c)

	c.if_(m.win.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	c.if_(m.win.chosen.eq(0))
	game.play(mut c, 'menu_select')
	m.start_mission(mut c, 'play')
	c.else_if(m.win.chosen.eq(1))
	game.play(mut c, 'menu_select')
	c.inc(m.mission)
	m.start_mission(mut c, 'play')
	c.else_if(m.win.chosen.eq(2).either(m.win.backed))
	game.play(mut c, 'menu_select')
	m.scenes.go_fade(mut c, 'picker')
	c.end() // what was chosen
	c.else_()
	m.lose.update(mut c)

	c.if_(m.lose.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	c.if_(m.lose.chosen.eq(0))
	game.play(mut c, 'menu_select')
	m.start_mission(mut c, 'play')
	c.else_if(m.lose.chosen.eq(1).either(m.lose.backed))
	game.play(mut c, 'menu_select')
	m.scenes.go_fade(mut c, 'picker')
	c.end() // what was chosen
	c.end() // which menu
	// guide:end
}
