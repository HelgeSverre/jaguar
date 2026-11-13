module jaggame

import jagkit

// Sprites. A sprite is one element of the pool `sprites`, an array of
// records; the runtime draws the visible ones every frame. Its fields are
// ordinary variables, so game code reads and writes them like any other.
//
//   x, y     i16   the top left corner in logical pixels (0,0 is the top left of the screen)
//   art      u8    which picture; the number `art_cry` and `art_pal` return
//   frame    u8    which frame of the art
//   layer    u8    0 is drawn first; a higher layer is drawn over a lower one
//   visible  bool  only visible sprites are drawn
//   flip     bool  mirrored left to right
//   scale    fix   1.0 is full size; 1/32 up to 7.9
//   fixed    bool  stays where it is on the screen when the camera moves (a game with a tile layer
//                  takes x and y as world positions, and subtracts the camera)
//
// The remaining fields (`seq`, `step`, `wait`, `loops`) belong to the
// animation and are changed with `play` and `stop`.

fn sprite_fields() []Field {
	return [Field{'scale', .fix}, Field{'x', .i16}, Field{'y', .i16},
		Field{'wait', .u16}, Field{'art', .u8}, Field{'frame', .u8},
		Field{'layer', .u8}, Field{'visible', .bool}, Field{'flip', .bool},
		Field{'seq', .u8}, Field{'step', .u8}, Field{'loops', .bool},
		Field{'fixed', .bool}]
}

// Art is a picture the sprites can show.
pub struct Art {
pub:
	id   int // the value for a sprite's `art` field
	name string
}

struct ArtInfo {
	name    string
	width   int
	height  int
	frames  int
	bits    int // 16 for CRY pixels, 8 for palette indices
	pixels  []u8
	problem string
}

// frame_bytes is the size of one frame of the art in memory.
fn (a ArtInfo) frame_bytes() int {
	return a.width * a.height * a.bits / 8
}

// line_bytes is the size of one line of the art in memory.
fn (a ArtInfo) line_bytes() int {
	return a.width * a.bits / 8
}

// art_cry declares a picture of 16-bit CRY pixels (see `cry`). The pixels
// are `frames` pictures of `width` by `height`, one after the other, a line
// after a line. The width must be a multiple of 4, so that a line fills
// whole 64-bit phrases. The pixel value 0 is transparent.
pub fn (mut g Game) art_cry(name string, width int, height int, frames int, pixels []u16) Art {
	return g.add_art(name, width, height, frames, 16, jagkit.big_endian16(pixels), pixels.len)
}

// art_pal declares a picture of 8-bit pixels that index the game's
// palette (see `palette`). The width must be a multiple of 8. The pixel
// value 0 is transparent.
pub fn (mut g Game) art_pal(name string, width int, height int, frames int, pixels []u8) Art {
	return g.add_art(name, width, height, frames, 8, pixels.clone(), pixels.len)
}

// palette sets the colours that 8-bit pictures use: entry n is the colour of
// pixel value n. At most 256 minus two for every text layer are allowed
// (the text keeps the top of the colour table).
pub fn (mut g Game) palette(colours []u16) {
	if g.palette_sources.len > 0 {
		g.problem('palette() is called after the pictures ${g.palette_sources.join(', ')} built the palette; declare the palette first, or leave it to the pictures')
	}
	g.palette = colours.clone()
	g.palette_fixed = true
	g.palette_index = map[u16]int{}
	for i, c in colours {
		if c !in g.palette_index {
			g.palette_index[c] = i
		}
	}
}

fn (mut g Game) add_art(name string, width int, height int, frames int, bits int, bytes []u8, count int) Art {
	for a in g.arts {
		if a.name == name {
			g.problem('art `${name}`: the name is already used')
		}
	}
	per_phrase := 64 / bits
	if width < 1 || width % per_phrase != 0 {
		g.problem('art `${name}`: a line of ${width} pixels at ${bits} bits does not fill whole 64-bit phrases; the width must be a multiple of ${per_phrase}')
	}
	if height < 1 || height > 1023 {
		g.problem('art `${name}`: the height ${height} must be 1..1023')
	}
	if frames < 1 || frames > 255 {
		g.problem('art `${name}`: the number of frames ${frames} must be 1..255')
	}
	if count != width * height * frames {
		g.problem('art `${name}`: ${frames} frames of ${width}x${height} need ${width * height * frames} pixels, there are ${count}')
	}
	if width * height * bits / 8 > 65535 {
		g.problem('art `${name}`: a frame may be at most 65535 bytes')
	}
	if g.arts.len >= 255 {
		g.problem('art `${name}`: at most 255 pictures')
	}
	g.arts << ArtInfo{
		name:   name
		width:  width
		height: height
		frames: frames
		bits:   bits
		pixels: bytes
	}
	return Art{
		id:   g.arts.len - 1
		name: name
	}
}

// art_id is the number of a picture, or an error recorded for the build.
fn (mut g Game) art_id(name string) int {
	for i, a in g.arts {
		if a.name == name {
			return i
		}
	}
	if g.arts.len == 0 {
		g.problem('there is no art `${name}`; no picture has been declared')
	} else {
		g.problem('there is no art `${name}`; the pictures are: ${g.arts.map(it.name).join(', ')}')
	}
	return 0
}

// Sprite is a handle on one element of the sprite pool. Its fields are
// expressions, usable as values and as destinations.
pub struct Sprite {
pub:
	x       Expr
	y       Expr
	art     Expr
	frame   Expr
	layer   Expr
	visible Expr
	flip    Expr
	scale   Expr
	fixed   Expr
	playing Expr // true while an animation is running
	element Expr
	game    &Game
}

// sprite is element `index` of the pool. A number that is not in the pool
// is a build error.
pub fn (mut g Game) sprite(index int) Sprite {
	if index < 0 || index >= g.config.sprites {
		g.problem('sprite ${index} is not in the pool of ${g.config.sprites}')
		return g.sprite_at(0) // so that one mistake is not reported again for every use
	}
	return g.sprite_at(index)
}

// sprite_at is the element of the pool that an expression selects: use it
// in a loop, `game.sprite_at(i)`. The interpreter stops on an index
// outside the pool; the machine does not check.
pub fn (g &Game) sprite_at(index Val) Sprite {
	e := g.sprites.at(index)
	return Sprite{
		x:       e.field('x')
		y:       e.field('y')
		art:     e.field('art')
		frame:   e.field('frame')
		layer:   e.field('layer')
		visible: e.field('visible')
		flip:    e.field('flip')
		scale:   e.field('scale')
		fixed:   e.field('fixed')
		playing: e.field('seq').ne(0)
		element: e
		game:    unsafe { g }
	}
}

// put shows a sprite: it sets the picture, the position and the layer,
// frame 0, full size, and makes it visible.
pub fn (s Sprite) put(mut c Code, art string, x Val, y Val, layer int) {
	mut game := s.game
	id := game.art_id(art)
	c.set(s.art, id)
	c.set(s.frame, 0)
	c.set(s.x, x)
	c.set(s.y, y)
	c.set(s.layer, layer)
	c.set(s.scale, 1.0)
	c.set(s.flip, false)
	c.set(s.fixed, false)
	c.set(s.visible, true)
}

// hide stops drawing a sprite.
pub fn (s Sprite) hide(mut c Code) {
	c.set(s.visible, false)
}

// Step is one step of an animation: which frame to show, and for how long.
pub struct Step {
pub:
	frame   int
	seconds f64 // the time the frame stays; the runtime turns it into frames for each standard
}

struct SeqInfo {
	name  string
	steps []Step
}

// sequence declares a named animation: the frames to show one after the
// other, each for its time. A time is in seconds, so that the animation
// runs at the same speed on both television standards; it is rounded to
// whole frames, at least 1.
pub fn (mut g Game) sequence(name string, steps []Step) {
	for s in g.seqs {
		if s.name == name {
			g.problem('animation `${name}`: the name is already used')
		}
	}
	if steps.len == 0 || g.seqs.len >= 255 {
		g.problem('animation `${name}`: it needs between 1 and 255 steps')
	}
	for st in steps {
		if st.frame < 0 || st.frame > 254 {
			g.problem('animation `${name}`: the frame ${st.frame} must be 0..254')
		}
		if st.seconds <= 0 || st.seconds > 600 {
			g.problem('animation `${name}`: a step must last more than 0 and at most 600 seconds, not ${st.seconds}')
		}
	}
	g.seqs << SeqInfo{
		name:  name
		steps: steps.clone()
	}
}

fn (g &Game) seq_index(name string) int {
	for i, s in g.seqs {
		if s.name == name {
			return i
		}
	}
	return -1
}

// frames_for turns a time into whole frames at a rate.
fn frames_for(seconds f64, fps int) int {
	n := int(seconds * f64(fps) + 0.5)
	return if n < 1 { 1 } else { n }
}

// play starts a named animation on the sprite: it shows the first step now
// and the runtime moves on every frame. With `repeat` it starts again
// after the last step; without, the sprite stays on the last frame and
// `playing` becomes false.
pub fn (s Sprite) play(mut c Code, name string, repeat bool) {
	mut game := s.game
	i := game.seq_index(name)
	if i < 0 {
		if game.seqs.len == 0 {
			game.problem('there is no animation `${name}`; no animation has been declared')
		} else {
			game.problem('there is no animation `${name}`; the animations are: ${game.seqs.map(it.name).join(', ')}')
		}
		return
	}
	first := game.seqs[i].steps[0]
	c.set(s.element.field('seq'), i + 1)
	c.set(s.element.field('step'), 0)
	c.set(s.element.field('loops'), repeat)
	c.set(s.frame, first.frame)
	c.set(s.element.field('wait'), frames_for(first.seconds, 60))
	c.if_(game.pal.ne(0))
	c.set(s.element.field('wait'), frames_for(first.seconds, 50))
	c.end()
}

// stop ends the animation of a sprite; it keeps the frame it shows.
pub fn (s Sprite) stop(mut c Code) {
	c.set(s.element.field('seq'), 0)
}
