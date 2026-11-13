module jaggame

import math
import jagkit { abs, imm, inc, lbl, ptr }

// A backdrop: a picture the GPU draws behind everything, for a menu or a
// title. It is a neon grid that drifts, with a bright bar that sweeps
// across it diagonally and a gradient of colours that runs down the screen
// and scrolls. The 68000 does almost nothing: each frame it moves four
// numbers (language code, so the interpreter has them too) and hands them
// to the GPU, which draws 160 by 120 pixels of 16-bit colour (the object
// processor shows them at double size) in a part of a frame.
//
// A pixel is the sum of three table look-ups and a colour:
//
//	grid[across + x] + grid[down + y] + band[slant + x + y] + hues[hue + y]
//
// The first three are a brightness below 256 (a grid line is bright, a
// crossing brighter, the bar adds to it), the last the colour in the high
// byte; the sum is a CRY pixel. The tables repeat, so a position may be any
// of 0..255.
//
// It is a layer of its own, the first object of the display list, so it is
// under the sprites and the text. It costs the GPU's time only while it is
// shown: `backdrop_show` and `backdrop_hide` switch it, and the list leaves
// the object out when it is hidden. It is built to be shown where no room is
// (a room's tile layer is opaque and would cover it).

// backdrop_buffer is where the GPU draws: 160 by 120 pixels of 2 bytes.
const backdrop_buffer = u32(0x90000)
const backdrop_width = 160
const backdrop_height = 120
const backdrop_scale = 2

// The values the two processors share, as offsets from the `shared` label
// of the GPU program.
const shared_go = 4 // set by the 68000 when the GPU may draw
const shared_across = 8
const shared_down = 12
const shared_slant = 16
const shared_hue = 20
const shared_grid = 24 // addresses of the tables and of the picture
const shared_band = 28
const shared_hues = 32
const shared_buffer = 36
const shared_drawn = 40 // pictures finished so far

// Rgb is a colour for the backdrop, each part 0..255.
pub struct Rgb {
pub:
	r int
	g int
	b int
}

// Backdrop is what the backdrop looks like: the colours of its gradient,
// from the top of the screen down and round again, blended.
pub struct Backdrop {
pub:
	colours []Rgb
}

// BackdropParams are the four numbers that say where everything is in a
// frame, each 0..255.
pub struct BackdropParams {
pub:
	across int
	down   int
	slant  int
	hue    int
}

// backdrop_params is where the grid, the bar and the gradient are in a frame.
pub fn backdrop_params(frame u32) BackdropParams {
	return BackdropParams{
		across: int((frame >> 1) & 255)
		down:   int((frame >> 2) & 255)
		slant:  int((frame * 3) & 255)
		hue:    int((frame >> 1) & 255)
	}
}

// BackdropVars is what the backdrop declares in the program.
@[heap]
struct BackdropVars {
	shown  Expr // u8
	across Expr // u32: the numbers the GPU is given
	down   Expr
	slant  Expr
	hue    Expr
}

// backdrop gives the game a backdrop. It starts hidden.
pub fn (mut g Game) backdrop(look Backdrop) {
	if g.backdrop_used {
		g.problem('backdrop: a game has one backdrop')
		return
	}
	if look.colours.len < 1 || look.colours.len > 8 {
		g.problem('backdrop: it needs 1..8 colours, not ${look.colours.len}')
	}
	for c in look.colours {
		if c.r < 0 || c.r > 255 || c.g < 0 || c.g > 255 || c.b < 0 || c.b > 255 {
			g.problem('backdrop: a colour has a part outside 0..255')
		}
	}
	g.backdrop_used = true
	g.backdrop_look = look
	mut p := g.p
	g.bd = &BackdropVars{
		shown:  p.u8('rt_backdrop_on')
		across: p.u32('rt_backdrop_across')
		down:   p.u32('rt_backdrop_down')
		slant:  p.u32('rt_backdrop_slant')
		hue:    p.u32('rt_backdrop_hue')
	}
}

// backdrop_show makes the backdrop visible from the next picture on.
pub fn (mut g Game) backdrop_show(mut c Code) {
	if !g.backdrop_used {
		g.problem('backdrop_show: the game has no backdrop; declare one with backdrop()')
		return
	}
	c.set(g.bd.shown, 1)
}

// backdrop_hide hides the backdrop: the GPU is left alone and the picture
// shows what is behind it.
pub fn (mut g Game) backdrop_hide(mut c Code) {
	if !g.backdrop_used {
		g.problem('backdrop_hide: the game has no backdrop; declare one with backdrop()')
		return
	}
	c.set(g.bd.shown, 0)
}

// backdrop_shown is true while the backdrop is visible.
pub fn (mut g Game) backdrop_shown() Expr {
	if !g.backdrop_used {
		g.problem('backdrop_shown: the game has no backdrop; declare one with backdrop()')
		return invalid('no backdrop')
	}
	return g.bd.shown.ne(0)
}

// define_backdrop writes the part of the frame that moves the numbers.
fn (g &Game) define_backdrop(mut c Code) {
	b := g.bd
	c.if_(b.shown.ne(0))
	c.set(b.across, g.frame.shr(1).and(255))
	c.set(b.down, g.frame.shr(2).and(255))
	c.set(b.slant, g.frame.mul(3).and(255))
	c.set(b.hue, g.frame.shr(1).and(255))
	c.end() // shown
}

// grid_table is a bright line every 16 entries, glowing a little each side,
// over a dim floor; two periods of 256.
fn grid_table() []u8 {
	mut table := []u8{cap: 512}
	for i in 0 .. 512 {
		d := i % 16
		near := if d < 16 - d { d } else { 16 - d }
		table << u8(math.round(10 + 90 * math.exp(-f64(near * near) / 2.2)))
	}
	return table
}

// band_table is a soft bright bar once in 256 entries.
fn band_table() []u8 {
	mut table := []u8{cap: 512}
	for i in 0 .. 512 {
		s := 0.5 + 0.5 * math.sin(2 * math.pi * f64(i) / 256)
		table << u8(math.round(46 * math.pow(s, 8)))
	}
	return table
}

// hue_table is the colours of the gradient as the high byte of a CRY pixel,
// in 256 steps through the colours and back to the first, twice over.
fn (g &Game) hue_table() []u16 {
	colours := g.backdrop_look.colours
	mut table := []u16{cap: 512}
	for i in 0 .. 512 {
		place := f64(i % 256) / 256.0 * f64(colours.len)
		first := int(place) % colours.len
		next := (first + 1) % colours.len
		t := place - math.floor(place)
		a := colours[first]
		z := colours[next]
		blended := jagkit.cry(int(f64(a.r) + t * f64(z.r - a.r)),
			int(f64(a.g) + t * f64(z.g - a.g)), int(f64(a.b) + t * f64(z.b - a.b)))
		table << (blended & 0xff00)
	}
	return table
}

// backdrop_pixel is the pixel the GPU draws at a column and a row for the
// numbers, as the CRY colour.
fn (g &Game) backdrop_pixel(p BackdropParams, x int, y int) u16 {
	grid := grid_table()
	band := band_table()
	hues := g.hue_table()
	return u16(int(grid[p.across + x]) + int(grid[p.down + y]) + int(band[p.slant + x + y]) +
		int(hues[p.hue + y]))
}

// painter is the GPU program: the three loads and the sum of every pixel,
// a colour for each row.
fn backdrop_painter() &jagkit.Risc {
	values := jagkit.Reg.r14 // `load_r14` and `store_r14` reach the shared values
	grid := jagkit.Reg.r15
	band := jagkit.Reg.r16
	hues := jagkit.Reg.r17
	picture := jagkit.Reg.r18
	wait := jagkit.Reg.r19 // jump targets too far away for `jr`
	next_row := jagkit.Reg.r20
	across_start := jagkit.Reg.r21
	down := jagkit.Reg.r22
	slant_start := jagkit.Reg.r23
	hue := jagkit.Reg.r24
	target := jagkit.Reg.r25
	rows := jagkit.Reg.r26
	left := jagkit.Reg.r27
	across := jagkit.Reg.r28
	slant := jagkit.Reg.r29
	row_colour := jagkit.Reg.r30
	colour := jagkit.Reg.r0
	other := jagkit.Reg.r1

	mut s := jagkit.new_risc(jagkit.gpu_ram)
	s.movei_label('shared', values)
	s.movei_label('wait', wait)
	s.movei_label('row', next_row)
	s.load_r14(shared_grid, grid)
	s.load_r14(shared_band, band)
	s.load_r14(shared_hues, hues)
	s.load_r14(shared_buffer, picture)

	// Wait for the 68000 to say go, then take the word back.
	s.label('wait')
	s.load_r14(shared_go, colour)
	s.cmpq(0, colour)
	s.jr(.eq, 'wait')
	s.nop()
	s.moveq(0, colour)
	s.store_r14(colour, shared_go)

	// Where in the tables each thing starts.
	s.load_r14(shared_across, across_start)
	s.add(grid, across_start)
	s.load_r14(shared_down, down)
	s.add(grid, down)
	s.load_r14(shared_slant, slant_start)
	s.add(band, slant_start)
	s.load_r14(shared_hue, hue)
	s.add(hue, hue) // the table is of words
	s.add(hues, hue)
	s.move(picture, target)
	s.movei(backdrop_height, rows)

	s.label('row')
	s.loadb(down, row_colour) // this row's share of the grid
	s.addqt(1, down)
	s.loadw(hue, other) // and its colour
	s.addqt(2, hue)
	s.add(other, row_colour)
	s.move(across_start, across)
	s.move(slant_start, slant)
	s.movei(backdrop_width, left)

	s.label('pixel')
	s.loadb(across, colour)
	s.addqt(1, across)
	s.loadb(slant, other)
	s.addqt(1, slant)
	s.add(other, colour)
	s.add(row_colour, colour)
	s.storew(colour, target)
	s.subq(1, left) // sets the flags the jump tests ...
	s.jr(.ne, 'pixel')
	s.addqt(2, target) // ... and this runs either way, without touching them

	s.addqt(1, slant_start) // the diagonal bar starts one further on each row
	s.subq(1, rows)
	s.jump(.ne, next_row)
	s.nop()

	s.load_r14(shared_drawn, colour)
	s.addq(1, colour)
	s.store_r14(colour, shared_drawn)
	s.jump(.always, wait)
	s.nop()

	s.align_long()
	s.label('shared')
	for _ in 0 .. 12 {
		s.long(0)
	}
	return s
}

// backdrop_code is the assembled GPU program, padded to whole longs, and
// where its shared values are.
fn backdrop_code() !([]u8, u32) {
	mut s := backdrop_painter()
	mut code := s.assemble()!
	for code.len % 4 != 0 {
		code << 0
	}
	return code, s.address_of('shared')
}

// emit_backdrop_start writes what start-up does for the GPU: copy its program
// in, tell it where its tables and its picture are and start it. It waits for
// the first `go`.
fn (g &Game) emit_backdrop_start(mut m jagkit.M68k, longs int, mailbox u32) {
	m.lea(lbl('rt.gpu_program'), a0)
	m.lea(abs(jagkit.gpu_ram), a1)
	m.move(.w, imm(longs - 1), d0)
	m.label('rt.copy_gpu')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'rt.copy_gpu')
	m.move(.l, ptr('rt.grid'), abs(mailbox + u32(shared_grid)))
	m.move(.l, ptr('rt.band'), abs(mailbox + u32(shared_band)))
	m.move(.l, ptr('rt.hues'), abs(mailbox + u32(shared_hues)))
	m.move(.l, imm(backdrop_buffer), abs(mailbox + u32(shared_buffer)))
	m.move(.l, imm(jagkit.gpu_ram), abs(jagkit.g_pc))
	m.move(.l, imm(jagkit.risc_go), abs(jagkit.g_ctrl))
}

// emit_backdrop_send writes `rt.send_backdrop`: while the backdrop is shown,
// the numbers go to the GPU and it is told to draw.
fn (g &Game) emit_backdrop_send(mut m jagkit.M68k, mailbox u32) {
	m.label('rt.send_backdrop')
	m.tst(.b, lbl('rt_backdrop_on'))
	m.b(.eq, 'rt.send_backdrop_done')
	m.move(.l, lbl('rt_backdrop_across'), abs(mailbox + u32(shared_across)))
	m.move(.l, lbl('rt_backdrop_down'), abs(mailbox + u32(shared_down)))
	m.move(.l, lbl('rt_backdrop_slant'), abs(mailbox + u32(shared_slant)))
	m.move(.l, lbl('rt_backdrop_hue'), abs(mailbox + u32(shared_hue)))
	m.move(.l, imm(1), abs(mailbox + u32(shared_go)))
	m.label('rt.send_backdrop_done')
	m.rts()
}

// emit_backdrop_data writes the tables the GPU reads and its program.
fn (g &Game) emit_backdrop_data(mut m jagkit.M68k, code []u8) {
	m.align(4)
	m.label('rt.grid')
	m.bytes(grid_table())
	m.label('rt.band')
	m.bytes(band_table())
	m.align(2)
	m.label('rt.hues')
	m.bytes(jagkit.big_endian16(g.hue_table()))
	m.align(4)
	m.label('rt.gpu_program')
	m.bytes(code)
}

// backdrop_bitmap is the backdrop as the object processor shows it: the
// logical screen, the picture magnified.
fn backdrop_bitmap(left int, top int) jagkit.Bitmap {
	return jagkit.Bitmap{
		x:      left
		y:      top
		width:  backdrop_width
		height: backdrop_height
		data:   backdrop_buffer
		depth:  .bpp16
		hscale: backdrop_scale
		vscale: backdrop_scale
	}
}
