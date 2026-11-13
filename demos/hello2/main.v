// HELLO2: hello, written with jaggame. Two lines of text, a ball you move
// with the pad, a beep when you press fire, and a little more: a spinning
// coin, a small ball that rides on the big one, an arrow that turns to face
// the way you go, and numbers that count. There is no assembly in this
// file: the game is described to jaggame, which checks it, compiles it and
// writes the image.
//
//     v run demos/hello2          # writes demos/hello2.jag
//
// docs/jaggame/guide.md, chapter 2, walks through this file.
module main

import math
import os
import jaggame

const ball_size = 32
const speed = 2 // pixels a frame

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/hello2.jag' }
	img := build() or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(output, img.bytes) or {
		eprintln(err)
		exit(1)
	}
	println('${output}: ${img.bytes.len} bytes')
}

// build compiles the game into an image. The test builds it too.
fn build() !jaggame.Image {
	mut g := describe()
	return g.build()!
}

// ball is the picture: a shaded sphere, 16 bits a pixel. Colour 0 is
// transparent, so the corners stay empty.
fn ball() []u16 {
	mut pixels := []u16{cap: ball_size * ball_size}
	radius := f64(ball_size) / 2
	for y in 0 .. ball_size {
		for x in 0 .. ball_size {
			dx := (x + 0.5 - radius) / radius
			dy := (y + 0.5 - radius) / radius
			if dx * dx + dy * dy > 1 {
				pixels << 0
				continue
			}
			// Lit from the top left.
			height := math.sqrt(1 - dx * dx - dy * dy)
			light := math.max(0.15, (height - 0.5 * dx - 0.5 * dy) / 1.5)
			pixels << jaggame.cry(int(255 * light), int(150 * light), int(40 * light))
		}
	}
	return pixels
}

// coin is four frames of a spinning coin, 16x16 pixels of 8 bits: the
// numbers are colours of the palette. 0 is transparent.
fn coin() []u8 {
	mut pixels := []u8{}
	for half_width in [7.5, 5.0, 1.5, 5.0] {
		for y in 0 .. 16 {
			for x in 0 .. 16 {
				dx := (x + 0.5 - 8) / half_width
				dy := (y + 0.5 - 8) / 7.5
				d := dx * dx + dy * dy
				if d > 1 {
					pixels << 0
				} else if d > 0.7 {
					pixels << 1 // the rim
				} else if dx + dy < 0 {
					pixels << 3 // the lit side
				} else {
					pixels << 2
				}
			}
		}
	}
	return pixels
}

fn coin_palette() []u16 {
	return [u16(0), jaggame.cry(150, 100, 10), jaggame.cry(230, 170, 30),
		jaggame.cry(255, 240, 150)]
}

// arrow points right, 32x16 pixels: a shaft and a head.
fn arrow() []u16 {
	mut pixels := []u16{}
	for y in 0 .. 16 {
		for x in 0 .. 32 {
			spread := f64(31 - x) / 2.0 // the head narrows towards the tip
			in_shaft := x < 16 && y >= 5 && y < 11
			in_head := x >= 16 && math.abs(f64(y) + 0.5 - 8.0) <= spread
			pixels << if in_shaft || in_head { jaggame.cry(80, 230, 120) } else { u16(0) }
		}
	}
	return pixels
}

// describe describes everything: pictures, text, timers, and what happens at
// start-up and in each frame.
fn describe() &jaggame.Game {
	mut game := jaggame.new_game(jaggame.Config{
		sprites:    4
		layers:     4
		background: jaggame.cry(0, 0, 60)
	})

	// guide:declare
	game.art_cry('ball', ball_size, ball_size, 1, ball())
	game.art_pal('coin', 16, 16, 4, coin())
	game.palette(coin_palette())
	game.art_cry('arrow', 32, 16, 1, arrow())
	game.sequence('spin', [jaggame.Step{0, 0.1}, jaggame.Step{1, 0.1},
		jaggame.Step{2, 0.1}, jaggame.Step{3, 0.1}])
	// A short A that fades out: the A above concert pitch, 880 Hz.
	game.sfx('beep', jaggame.Sfx{
		volume: 3000
		decay:  3
		steps:  [jaggame.SfxStep{880, 0.4}]
	})

	title := game.text_layer('title', jaggame.TextConfig{
		columns: 40
		rows:    2
		y:       8
	})
	hud := game.text_layer('hud', jaggame.TextConfig{
		columns: 24
		rows:    3
		x:       8
		y:       200
		colour:  jaggame.cry(255, 220, 90)
	})
	beat := game.timer('beat')
	watch := game.timer('watch')
	beats := game.p.u16('beats')
	// guide:end

	// guide:init
	ball_sprite := game.sprite(0)
	coin_sprite := game.sprite(1)
	moon := game.sprite(2)
	pointer := game.sprite(3)

	mut c := game.define_init()
	ball_sprite.put(mut c, 'ball', 144, 104, 1)
	coin_sprite.put(mut c, 'coin', 40, 90, 0)
	coin_sprite.play(mut c, 'spin', true)
	moon.put(mut c, 'ball', 168, 98, 2)
	c.set(moon.scale, 0.5)
	pointer.put(mut c, 'arrow', 140, 160, 3)

	title.print(mut c, 13, 0, 'HELLO, JAGUAR!')
	title.print(mut c, 8, 1, 'ARROWS MOVE. FIRE BEEPS.')
	hud.print(mut c, 0, 0, 'FRAMES')
	hud.print(mut c, 0, 1, 'SECONDS')
	hud.print(mut c, 0, 2, 'BEATS')
	beat.start(mut c, game.seconds(0.5))
	watch.stopwatch(mut c)
	// guide:end

	// guide:update
	c = game.define_update()

	c.if_(game.held(.left))
	c.set(ball_sprite.x, ball_sprite.x.sub(speed))
	c.set(pointer.flip, true)
	c.end()

	c.if_(game.held(.right))
	c.set(ball_sprite.x, ball_sprite.x.add(speed))
	c.set(pointer.flip, false)
	c.end()

	c.if_(game.held(.up))
	c.set(ball_sprite.y, ball_sprite.y.sub(speed))
	c.end()

	c.if_(game.held(.down))
	c.set(ball_sprite.y, ball_sprite.y.add(speed))
	c.end()

	// The ball stops at the edges of the screen.
	c.set(ball_sprite.x, ball_sprite.x.max(0).min(jaggame.logical_width - ball_size))
	c.set(ball_sprite.y, ball_sprite.y.max(0).min(jaggame.logical_height - ball_size))

	// The small ball rides on the big one, and runs off the screen with it.
	c.set(moon.x, ball_sprite.x.add(24))
	c.set(moon.y, ball_sprite.y.sub(6))

	c.if_(game.pressed(.fire))
	game.play(mut c, 'beep')
	c.end()

	c.if_(beat.fired)
	c.inc(beats)
	beat.start(mut c, game.seconds(0.5))
	c.end()

	hud.number(mut c, 7, 0, game.frame, 5)
	hud.number(mut c, 8, 1, game.whole_seconds(watch.elapsed), 3)
	hud.number(mut c, 6, 2, beats, 3)
	// guide:end
	return game
}
