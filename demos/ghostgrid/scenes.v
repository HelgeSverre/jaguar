// The scenes of GHOSTGRID: the title, the mission select, the mission itself
// and its result. The pause menu is part of the mission (it stops the
// guards, not the scene). Each scene is a few lines here; what a scene does
// when it begins and ends, and the setup that is spread over frames, are the
// scene's own.
module main

import jaggame

// mission_titles are the missions of the select screen, in order; the
// screen adds a way back. There is one mission now: more are a name here
// and a room.
const mission_titles = ['DEPOT']

// define_scenes writes the four scenes and says where the game starts.
fn (mut m Mission) define_scenes() {
	m.define_title()
	m.define_picker()
	m.define_play()
	m.define_result()
	m.scenes.start('title')
}

// menu_screen is what a title or a menu has: the backdrop, no room, no
// sprites and no status lines.
fn (mut m Mission) menu_screen(mut c jaggame.Code) {
	mut game := m.game
	// guide:gg_screen
	for s in 0 .. 9 {
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
	c.if_(scenes.time().mod(60).eq(0))
	m.msg.print(mut c, 8, 9, 'PRESS A')
	c.else_if(scenes.time().mod(60).eq(35))
	m.msg.print(mut c, 8, 9, '       ')
	c.end() // blink

	c.if_(game.pressed(.a).either(game.pressed(.pause)))
	game.play(mut c, 'menu_select')
	scenes.go(mut c, 'picker')
	c.end() // go on
	// guide:end
}

// define_picker writes the mission select: the missions and the best time
// of each, read from the saved record.
fn (mut m Mission) define_picker() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_picker
	mut c := scenes.on_enter('picker')
	m.menu_screen(mut c)
	c.set(m.msg.colour, jaggame.cry(255, 255, 255))
	m.msg.print(mut c, 5, 1, 'SELECT MISSION')
	m.picker.open(mut c)
	c.set(m.best_up, false)
	m.save.load(mut c)

	c = scenes.scene('picker')
	m.picker.update(mut c)

	c.if_(m.picker.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	// The record is read a word a frame; when it is in, the best is shown.
	c.if_(m.save.busy().invert().both(m.best_up.invert()))
	c.set(m.best_up, true)
	m.print_best(mut c, m.msg, 3, 3)
	c.end() // the record arrived

	c.if_(m.picker.chosen.eq(0))
	game.play(mut c, 'menu_select')
	scenes.go(mut c, 'play')
	c.else_if(m.picker.chosen.eq(mission_titles.len).either(m.picker.backed))
	game.play(mut c, 'menu_select')
	scenes.go(mut c, 'title')
	c.end() // what was chosen
	// guide:end
}

// print_best writes the best time and the fewest times seen, or that there
// is none, at a column and a row of a layer.
fn (m &Mission) print_best(mut c jaggame.Code, layer jaggame.TextLayer, col int, row int) {
	best := m.save.field('best_time')
	c.if_(best.ne(0))
	layer.print(mut c, col, row, 'BEST')
	layer.number(mut c, col + 5, row, best.div(60), 1)
	layer.print(mut c, col + 6, row, ':')
	layer.number(mut c, col + 7, row, best.mod(60).div(10), 1)
	layer.number(mut c, col + 8, row, best.mod(10), 1)
	layer.print(mut c, col + 11, row, 'SEEN')
	layer.number(mut c, col + 16, row, m.save.field('least_seen'), 2)
	c.else_()
	layer.print(mut c, col, row, 'NO TIME YET')
	c.end() // a record, or none
}

// define_play writes the mission as a scene: it loads the room when it
// begins and puts everything on its start in the frames after, then the
// update runs.
fn (mut m Mission) define_play() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_play
	mut c := scenes.on_enter('play')
	game.backdrop_hide(mut c)
	game.load_room(mut c, m.room)
	c.set(m.clear_at, 0)
	game.music_play(mut c, 'calm')

	c = scenes.setup('play', guard_count + 1)
	m.define_play_setup(mut c)

	c = scenes.scene('play')
	m.define_play_update(mut c)
	// guide:end
}

// define_result writes the result: the room stands as it was with the
// result over it. The best is worked out and saved when the scene begins,
// and the screen is written a few lines a frame.
fn (mut m Mission) define_result() {
	mut game := m.game
	mut scenes := m.scenes
	// guide:gg_result
	mut c := scenes.on_enter('result')
	changed := c.local_bool('changed')
	best := m.save.field('best_time')
	least := m.save.field('least_seen')
	c.set(m.new_best, false)
	game.music_stop(mut c)

	c.if_(m.phase.eq(1))
	game.play(mut c, 'complete')

	c.if_(best.eq(0))
	c.set(best, m.secs)
	c.set(least, m.seen)
	c.set(m.new_best, true)
	c.set(changed, true)
	c.else_()

	c.if_(m.secs.lt(best))
	c.set(best, m.secs)
	c.set(m.new_best, true)
	c.set(changed, true)
	c.end() // a faster time

	c.if_(m.seen.lt(least))
	c.set(least, m.seen)
	c.set(changed, true)
	c.end() // fewer times seen
	c.end() // a first time, or not
	c.else_()
	game.play(mut c, 'caught')
	c.end() // done or caught

	c.if_(changed)
	m.save.store(mut c)
	c.end() // something to keep

	c = scenes.setup('result', 4)
	step := scenes.step
	c.if_(step.eq(0))
	m.msg.clear(mut c)
	c.set(m.msg.colour, jaggame.cry(255, 255, 255))

	c.if_(m.phase.eq(1))
	m.msg.print(mut c, 4, 0, 'MISSION COMPLETE')
	c.else_()
	m.msg.print(mut c, 4, 0, 'YOU WERE CAUGHT')
	c.end() // done or caught
	c.end() // title

	c.if_(step.eq(1))
	m.msg.print(mut c, 4, 2, 'TIME')
	m.msg.number(mut c, 10, 2, m.secs.div(60), 1)
	m.msg.print(mut c, 11, 2, ':')
	m.msg.number(mut c, 12, 2, m.secs.mod(60).div(10), 1)
	m.msg.number(mut c, 13, 2, m.secs.mod(10), 1)
	m.msg.print(mut c, 4, 3, 'SEEN')
	m.msg.number(mut c, 10, 3, m.seen, 3)
	c.end() // this mission

	c.if_(step.eq(2))
	m.print_best(mut c, m.msg, 4, 5)

	c.if_(m.new_best)
	m.msg.print(mut c, 4, 6, 'NEW BEST TIME!')
	c.end() // a record
	c.end() // the best
	c.if_(step.eq(3))
	m.after.open(mut c)
	c.end() // the menu

	c = scenes.scene('result')
	m.after.update(mut c)

	c.if_(m.after.moved)
	game.play(mut c, 'menu_move')
	c.end() // the cursor moved

	c.if_(m.after.chosen.eq(0))
	game.play(mut c, 'menu_select')
	scenes.go(mut c, 'play')
	c.else_if(m.after.chosen.eq(1).either(m.after.backed))
	game.play(mut c, 'menu_select')
	scenes.go(mut c, 'picker')
	c.end() // what was chosen
	// guide:end
}
