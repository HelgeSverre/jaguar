module jagkit

// Ready-made 68000 subroutines for the things every program needs: reading
// the pad and printing text. Each call emits the routine once; the program
// then calls it by its label with `bsr`.

// Bits of the pad, as `read_pad` reports them.
pub const pad_fire = 0 // A, B or C
pub const pad_a = 1
pub const pad_b = 2
pub const pad_c = 3
pub const pad_up = 4
pub const pad_down = 5
pub const pad_left = 6
pub const pad_right = 7

// pad_reader emits the subroutine `read_pad` and two word variables it
// keeps up to date: `pad`, the buttons of the first controller that are
// held, and `pressed`, the ones that went down since the last call. Call
// it once a frame. It changes d0 and d1.
pub fn (mut m M68k) pad_reader() {
	// The pad is a matrix: select a row, read its columns. A line is low
	// while its button is held. Each row has one fire button.
	rows := joystick_enable | 0xf0
	m.label('read_pad')
	m.move(.w, imm(rows | 0xe), abs(joystick)) // row 0: the directions and A
	m.move(.w, abs(joystick), d0)
	m.not(.w, d0)
	m.lsr(.w, imm(4), d0)
	m.and(.w, imm(0xf0), d0)
	for row, line in [0xe, 0xd, 0xb] {
		released := m.unique('released')
		m.move(.w, imm(rows | line), abs(joystick))
		m.move(.w, abs(joybuts), d1)
		m.btst(1, d1)
		m.b(.ne, released)
		m.orr(.w, imm((1 << pad_fire) | (1 << (pad_a + row))), d0)
		m.label(released)
	}
	m.move(.w, lbl('pad'), d1)
	m.move(.w, d0, lbl('pad'))
	m.not(.w, d1)
	m.and(.w, d0, d1)
	m.move(.w, d1, lbl('pressed'))
	m.rts()
	m.label('pad')
	m.word(0)
	m.label('pressed')
	m.word(0)
}

// TextScreen is a picture made of 8x8 character cells, one bit a pixel,
// somewhere in RAM.
pub struct TextScreen {
pub:
	address u32
	columns int = 40 // a multiple of 8, so that a line fills whole phrases
	rows    int = 25
	digits  int = 5 // how many digits `number` writes
}

// bytes is the size of the screen in memory.
pub fn (t TextScreen) bytes() int {
	return t.columns * t.rows * 8
}

// bitmap is the object that shows the screen with its top left corner at
// (x, y). The letters have colour `colour` of the colour table, which must
// be odd; everything else is transparent.
pub fn (t TextScreen) bitmap(x int, y int, colour int) Bitmap {
	return Bitmap{
		x:           x
		y:           y
		width:       t.columns * 8
		height:      t.rows * 8
		data:        t.address
		depth:       .bpp1
		palette:     colour - 1
		transparent: true
	}
}

// text_routines emits the font and three subroutines for a text screen:
//
//   print       draws the zero-terminated string at a0 at column d0, row d1.
//   number      turns d0 (0..65535) into `digits` digits and leaves a0
//               pointing at them, ready for `print`.
//   clear_text  blanks the screen.
//
// They change d0..d3 and a0..a3. The font has capitals, digits and
// punctuation only.
pub fn (mut m M68k) text_routines(screen TextScreen) {
	if screen.columns % 8 != 0 || screen.address % 8 != 0 || screen.digits < 1 || screen.digits > 5 {
		m.problems << 'text screen: columns and address must be multiples of 8, digits 1..5'
	}
	m.label('print')
	m.mulu(imm(screen.columns * 8), d1)
	m.add(.w, d0, d1)
	m.lea(abs(screen.address), a1)
	m.add(.l, d1, a1)
	m.label('print_next')
	m.moveq(0, d2)
	m.move(.b, inc(a0), d2)
	m.b(.eq, 'print_done')
	m.sub(.w, imm(font_first), d2)
	m.lsl(.w, imm(3), d2)
	m.lea(lbl('font'), a2)
	m.add(.w, d2, a2)
	m.move(.l, a1, a3)
	m.moveq(7, d3)
	m.label('print_row')
	m.move(.b, inc(a2), ind(a3))
	m.lea(at(screen.columns, a3), a3)
	m.dbra(d3, 'print_row')
	m.add(.l, imm(1), a1)
	m.bra('print_next')
	m.label('print_done')
	m.rts()

	m.label('number')
	m.lea(lbl('digits_end'), a0)
	m.moveq(screen.digits - 1, d2)
	m.label('next_digit')
	m.and(.l, imm(0xffff), d0)
	m.divu(imm(10), d0)
	m.swap(d0) // the remainder
	m.add(.b, imm(int(`0`)), d0)
	m.move(.b, d0, dec(a0))
	m.move(.w, imm(0), d0)
	m.swap(d0) // the quotient
	m.dbra(d2, 'next_digit')
	m.rts()

	m.label('clear_text')
	m.lea(abs(screen.address), a0)
	m.move(.w, imm(screen.bytes() / 4 - 1), d0)
	m.label('clear_text_long')
	m.move(.l, imm(0), inc(a0))
	m.dbra(d0, 'clear_text_long')
	m.rts()

	m.label('digits')
	m.bytes([]u8{len: screen.digits})
	m.label('digits_end')
	m.byte(0)
	m.label('font')
	m.bytes(font_8x8())
	m.align(2)
}

// print_at emits a call that prints a string constant at a text cell. The
// string is stored in line, with a branch around it.
pub fn (mut m M68k) print_at(column int, row int, text string) {
	for c in text {
		if int(c) < font_first || int(c) >= font_first + font_count {
			m.problems << 'print_at: the font has no `${rune(c)}` (in "${text}")'
			break
		}
	}
	name := m.unique('text')
	skip := m.unique('after_text')
	m.lea(lbl(name), a0)
	m.moveq(column, d0)
	m.moveq(row, d1)
	m.bsr('print')
	m.bra(skip)
	m.label(name)
	m.text(text)
	m.label(skip)
}
