module sdl

import jerry

// The shell is a picture of a console drawn around the guest screen in a
// borderless, transparent window. Its red buttons are frontend commands, its
// keypad is the controller's keypad, its dark strip is a status readout and
// its two red slits brighten with the sound.
//
// Every position below is in pixels of the artwork, `shell.png`.
pub const shell_width = 1477
pub const shell_height = 996

// The opening in the artwork bulges like a picture tube: `shell_screen` is
// the box around it, whose corners the bezel covers. `shell_picture` is the
// largest 4:3 box that lies wholly inside the opening, so the bezel hides
// nothing of the guest's picture.
const shell_screen = Box{265, 241, 737, 538}
const shell_picture = Box{311, 266, 651, 488}
const shell_readout = Box{818, 862, 336, 54}
const shell_eyes = [Box{467, 187, 111, 25}, Box{756, 186, 113, 26}]

// The five round buttons under the screen, left to right.
const shell_button_centres = [272, 383, 492, 603, 715]
const shell_button_y = 885
const shell_button_radius = 43
const shell_commands = [Command.quit, .reset, .pause, .mute, .fullscreen]

// The keypad is a grid of three columns and four rows.
const shell_keypad = Box{1101, 451, 62, 44} // top-left key
const shell_keypad_pitch_x = 75
const shell_keypad_pitch_y = 68
const shell_keys = [jerry.Button.one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
	.star, .zero, .hash]

// Box is a rectangle of the artwork.
pub struct Box {
pub:
	x int
	y int
	w int
	h int
}

fn (b Box) contains(x int, y int) bool {
	return x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h
}

// ControlKind says what a point of the shell does when clicked.
pub enum ControlKind {
	none
	command // one of the red buttons
	key     // one of the keypad keys
}

// Control is one clickable part of the shell.
pub struct Control {
pub:
	kind  ControlKind
	index int // into `shell_commands` or `shell_keys`
	box   Box
}

// label names the control on the readout.
pub fn (c Control) label() string {
	return match c.kind {
		.none {
			''
		}
		.command {
			match shell_commands[c.index] {
				.quit { 'POWER' }
				.reset { 'RESET' }
				.pause { 'PAUSE' }
				.mute { 'MUTE' }
				.fullscreen { 'FULLSCREEN' }
				else { '' }
			}
		}
		.key {
			'KEYPAD ' + '123456789*0#'[c.index].ascii_str()
		}
	}
}

// control_at returns the control under a point of the artwork.
pub fn control_at(x int, y int) Control {
	for i, centre in shell_button_centres {
		dx := x - centre
		dy := y - shell_button_y
		if dx * dx + dy * dy <= shell_button_radius * shell_button_radius {
			return Control{
				kind:  .command
				index: i
				box:   Box{centre - shell_button_radius, shell_button_y - shell_button_radius, shell_button_radius * 2, shell_button_radius * 2}
			}
		}
	}
	for i in 0 .. shell_keys.len {
		box := Box{shell_keypad.x + (i % 3) * shell_keypad_pitch_x, shell_keypad.y +
			(i / 3) * shell_keypad_pitch_y, shell_keypad.w, shell_keypad.h}
		if box.contains(x, y) {
			return Control{
				kind:  .key
				index: i
				box:   box
			}
		}
	}
	return Control{}
}

// Shell is the loaded artwork and the pointer's relation to it. It lives on
// the heap because SDL keeps a pointer to it for window hit testing.
@[heap]
pub struct Shell {
mut:
	texture voidptr
	alpha   []u8 // one byte per artwork pixel
pub mut:
	scale  f32 = 1.0 // window points per artwork pixel
	active bool // false while the window is fullscreen
	hover  Control
	held   Control
}

// load_shell decodes the embedded artwork into a texture of `renderer`.
fn load_shell(renderer voidptr) !&Shell {
	art := $embed_file('shell.png')
	stream := C.SDL_IOFromConstMem(art.data(), usize(art.len))
	decoded := C.SDL_LoadPNG_IO(stream, true)
	if decoded == unsafe { nil } {
		return error('shell artwork: ${last_error()}')
	}
	surface := C.SDL_ConvertSurface(decoded, u32(C.SDL_PIXELFORMAT_RGBA32))
	C.SDL_DestroySurface(decoded)
	if surface == unsafe { nil } {
		return error('shell artwork: ${last_error()}')
	}
	defer {
		C.SDL_DestroySurface(surface)
	}
	if surface.w != shell_width || surface.h != shell_height {
		return error('shell artwork is ${surface.w}x${surface.h}, layout expects ${shell_width}x${shell_height}')
	}
	mut alpha := []u8{len: shell_width * shell_height}
	for y in 0 .. shell_height {
		row := unsafe { &u8(surface.pixels) + y * surface.pitch }
		for x in 0 .. shell_width {
			alpha[y * shell_width + x] = unsafe { row[x * 4 + 3] }
		}
	}
	texture := C.SDL_CreateTextureFromSurface(renderer, surface)
	if texture == unsafe { nil } {
		return error('shell artwork: ${last_error()}')
	}
	C.SDL_SetTextureScaleMode(texture, int(C.SDL_SCALEMODE_LINEAR))
	return &Shell{
		texture: texture
		alpha:   alpha
		active:  true
	}
}

// solid reports whether a point of the artwork is part of the console and
// not the see-through margin around it. The screen counts as solid.
fn (s &Shell) solid(x int, y int) bool {
	if x < 0 || y < 0 || x >= shell_width || y >= shell_height {
		return false
	}
	return shell_screen.contains(x, y) || s.alpha[y * shell_width + x] > 32
}

// control_at_point maps a pointer position in window points to a control.
fn (s &Shell) control_at_point(x f32, y f32) Control {
	if !s.active {
		return Control{}
	}
	return control_at(int(x / s.scale), int(y / s.scale))
}

// shell_hit_test tells SDL which parts of the borderless window move it:
// everything solid that is not a control.
fn shell_hit_test(_ voidptr, point &C.SDL_Point, data voidptr) int {
	shell := unsafe { &Shell(data) }
	if !shell.active {
		return int(C.SDL_HITTEST_NORMAL)
	}
	x := int(f32(point.x) / shell.scale)
	y := int(f32(point.y) / shell.scale)
	if control_at(x, y).kind == .none && shell.solid(x, y) {
		return int(C.SDL_HITTEST_DRAGGABLE)
	}
	return int(C.SDL_HITTEST_NORMAL)
}
