module jaggame

import jagkit

// The runtime: a game is a Program plus a fixed runtime that runs it once a
// frame in the vertical interrupt. Everything a game can see of the runtime
// (the sprites, the pad, the frame counter, the text, the timers) is an
// ordinary variable of the program, so the interpreter can run the same
// game logic without the machine.
//
// Names that begin with `rt_` and `rt.` belong to the runtime.

const d6 = jagkit.d6
const d7 = jagkit.d7
const a1 = jagkit.a1
const a2 = jagkit.a2
const a3 = jagkit.a3
const a4 = jagkit.a4
const a5 = jagkit.a5
const a6 = jagkit.a6

// logical_width and logical_height are the size of the screen a game draws on.
pub const logical_width = 320
pub const logical_height = 240

// Where the runtime keeps things in main memory, above the image.
const list_address = u32(0x80000)
const max_sprites = 255
const max_layers = 16
const max_text_layers = 8

// Config is what a game decides before it declares anything.
pub struct Config {
pub:
	sprites    int = 16 // the size of the sprite pool
	layers     int = 4  // sprite layers 0..layers-1; a higher layer is drawn over a lower one
	background u16 // the colour behind everything, CRY; see `cry`
}

// Region is the television standard a game runs on.
pub enum Region {
	ntsc
	pal
}

// Game is a Program with a runtime around it. Declare the game's own
// variables and functions on `p`; the runtime's are listed on the struct.
@[heap]
pub struct Game {
pub:
	config        Config
	frame         Expr // u32: frames since start-up
	missed_frames Expr // u16: interrupts that arrived while the last one was still running
	fps           Expr // u8: 60 on NTSC, 50 on PAL
	pad           Expr // u32: the buttons held; see `Button`
	pad_pressed   Expr // u32: the buttons that went down this frame
	sprites       Expr // the sprite pool: an array of records
pub mut:
	p &Program
mut:
	record      Record
	pal         Expr // u8: 0 on NTSC, 1 on PAL
	arts        []ArtInfo
	palette     []u16
	seqs        []SeqInfo
	texts       []TextInfo
	timers      []TimerInfo
	sounds      bool // a beep is used
	beep_step   Expr
	beep_volume Expr
	notes       Expr
	init_func   Func
	update_func Func
	has_init    bool
	has_update  bool
	built       bool
	defined     bool           // the runtime's own functions are written
	strings     map[string]int // the offset of each string constant in `pool`
	pool        []u8
}

// new_game starts a game with the runtime's variables declared.
pub fn new_game(config Config) &Game {
	mut p := new_program()
	if config.sprites < 1 || config.sprites > max_sprites {
		p.problems << 'game: the sprite pool must hold 1..${max_sprites} sprites, not ${config.sprites}'
	}
	if config.layers < 1 || config.layers > max_layers {
		p.problems << 'game: the number of layers must be 1..${max_layers}, not ${config.layers}'
	}
	record := p.record('Sprite', sprite_fields())
	sprites := p.array_of('sprites', record, if config.sprites < 1 { 1 } else { config.sprites })
	return &Game{
		config:        config
		frame:         p.u32('frame')
		missed_frames: p.u16('missed_frames')
		fps:           p.u8('fps', 60)
		pad:           p.u32('pad')
		pad_pressed:   p.u32('pad_pressed')
		sprites:       sprites
		p:             p
		record:        record
		pal:           p.u8('rt_pal')
		beep_step:     invalid('no beep was declared')
		beep_volume:   invalid('no beep was declared')
		notes:         invalid('no beep was declared')
		init_func:     p.func('rt_user_init', [], .void)
		update_func:   p.func('rt_user_update', [], .void)
	}
}

// cry is the CRY colour nearest to an RGB colour, each part 0..255, for
// art, palettes, text and the background.
pub fn cry(r int, g int, b int) u16 {
	return jagkit.cry(r, g, b)
}

// problem records a mistake in the description of the game. All of them are
// reported together when the game is built.
fn (mut g Game) problem(message string) {
	g.p.problems << 'game: ${message}'
}

// define_init returns the block that collects the statements of the
// function that runs once, before the first frame.
pub fn (mut g Game) define_init() &Code {
	g.has_init = true
	return g.p.define(g.init_func)
}

// define_update returns the block that collects the statements of the
// function that runs once every frame, in the vertical interrupt.
pub fn (mut g Game) define_update() &Code {
	g.has_update = true
	return g.p.define(g.update_func)
}

// seconds is a number of frames: the right one for the television
// standard the game finds itself on, decided when it starts. Use it for
// durations: `seconds(1.5)` is 90 on NTSC and 75 on PAL. The result is a `u16`.
pub fn (g &Game) seconds(s Val) Expr {
	return g.fps.as_(.fix).mul(s).add(0.5).as_(.u16)
}

// whole_seconds is a whole number of frames as seconds, rounded down,
// for showing elapsed time.
pub fn (g &Game) whole_seconds(frames Val) Expr {
	return lit(frames).as_(.u32).div(g.fps.as_(.u32))
}

// layout is where the runtime puts the display lists and the text.
struct Layout {
	list_bytes int // one display list
	lists      [2]u32
	text       []u32 // the address of each text layer's picture
	text_end   u32
}

// objects is how many objects a display list can hold: the sprites, the
// jump to the text, and the text layers.
fn (g &Game) objects() int {
	return g.config.sprites + 1 + g.texts.len
}

fn (g &Game) layout() Layout {
	list_bytes := 32 + 32 * g.objects()
	spacing := u32((list_bytes + 255) / 256 * 256)
	mut at := list_address + 2 * spacing
	mut text := []u32{}
	for t in g.texts {
		text << at
		at += u32((t.columns * t.rows * 8 + 63) / 64 * 64)
	}
	return Layout{
		list_bytes: list_bytes
		lists:      [list_address, list_address + spacing]!
		text:       text
		text_end:   at
	}
}
