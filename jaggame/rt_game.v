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

// logical_width is the width of the screen a game draws on, in pixels.
pub const logical_width = 320

// logical_height is the height of the screen a game draws on, in lines.
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
	camera_x      Expr // i16: the world position shown at the left edge of the screen; negative when the room is narrower than the screen
	camera_y      Expr // i16: the world position shown at the top
	loading       Expr // bool: a room is being drawn; the picture is blank until it is done
	room_number   Expr // u8: the room that is loaded or loading
	room_width    Expr // i16: the width of that room in pixels
	room_height   Expr // i16: its height in pixels
	fade          Expr // u8: the brightness of everything drawn with the palette, 0 (black) to 16 (as drawn); see `Scenes.go_fade`
pub mut:
	p &Program
mut:
	record  Record
	pal     Expr // u8: 0 on NTSC, 1 on PAL
	applied Expr // u8: the brightness the colour table has now
	arts    []ArtInfo
	palette []u16
	// palette_fixed is true once the author declared the palette; until
	// then the PNGs that are imported build it.
	palette_fixed   bool
	palette_index   map[u16]int // the entry of each colour
	palette_sources []string    // the files that added colours, with how many
	seqs            []SeqInfo
	texts           []TextInfo
	timers          []TimerInfo
	sounds          bool // an effect or a track is declared: the synthesizer is in the image
	snd             &SoundVars = unsafe { nil } // the sound's variables and functions, once `sounds`
	sfxs            []SfxInfo
	tracks          []TrackInfo
	save_info       []SaveInfo // the game's record, if it has one
	backdrop_used   bool
	backdrop_look   Backdrop
	bd              &BackdropVars = unsafe { nil } // the backdrop's variables, once `backdrop_used`
	init_func       Func
	update_func     Func
	// The tile layer: see assets_map.v and rt_tiles.v.
	has_tileset    bool
	tileset_path   string
	tileset_art    int
	tile_count     int
	legend_tiles   []LegendTile
	legend_markers []LegendMarker
	rooms          []RoomInfo
	rooms_parsed   bool
	tv             &TileVars = unsafe { nil } // the tile layer's variables and functions, once `map_ready`
	map_ready      bool // the tile layer's variables and functions are declared
	sight          &SightVars = unsafe { nil } // line of sight and hearing, once `sight_ready`
	sight_ready    bool
	scene_ref      &Scenes = unsafe { nil } // the scenes, once `scene_set`
	scene_set      bool
	has_init       bool
	has_update     bool
	built          bool
	defined        bool           // the runtime's own functions are written
	strings        map[string]int // the offset of each string constant in `pool`
	pool           []u8
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
		camera_x:      p.i16('camera_x')
		camera_y:      p.i16('camera_y')
		loading:       p.bool('loading')
		room_number:   p.u8('room_number')
		room_width:    p.i16('room_width')
		room_height:   p.i16('room_height')
		fade:          p.u8('rt_fade', 16)
		p:             p
		record:        record
		pal:           p.u8('rt_pal')
		applied:       p.u8('rt_fade_applied', 16)
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
	return g.slots() + g.texts.len
}

// slots is the places in a display list before the text: the backdrop's
// object and the tile layer's if there are any, the sprites and the jump to
// the text.
fn (g &Game) slots() int {
	return g.config.sprites + 1 + if g.has_tileset {
		1
	} else {
		0
	} + if g.backdrop_used {
		1
	} else {
		0
	}
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
