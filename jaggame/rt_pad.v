module jaggame

import jagkit { abs, imm, lbl }

// Button is one button of the Jaguar's controller. The order is the order
// of the bits in `pad`: the matrix of four rows of four lines, then the
// fire buttons, then Pause.
pub enum Button {
	up
	down
	left
	right
	star
	seven
	four
	one
	zero
	eight
	five
	two
	hash
	nine
	six
	three
	a
	b
	c
	option
	pause
	fire // A, B or C
}

// button_mask is the bit (or bits) of `pad` and `pad_pressed` that belong
// to a button. A test that feeds the interpreter builds the pad it wants
// from these.
pub fn button_mask(b Button) u32 {
	if b == .fire {
		return button_mask(.a) | button_mask(.b) | button_mask(.c)
	}
	return u32(1) << u32(int(b))
}

// held is true while a button is down, as a `bool` expression.
pub fn (g &Game) held(b Button) Expr {
	return g.pad.and(i64(button_mask(b))).ne(0)
}

// pressed is true for the one frame in which a button went down.
pub fn (g &Game) pressed(b Button) Expr {
	return g.pad_pressed.and(i64(button_mask(b))).ne(0)
}

// emit_read_pad writes the subroutine `rt.read_pad`. It reads the four
// rows of the controller matrix into one long, in the order of `Button`,
// stores it in `pad`, and stores in `pad_pressed` the bits that were not
// set a frame ago. It changes d0, d1 and d2.
fn (g &Game) emit_read_pad(mut m jagkit.M68k) {
	m.label('rt.read_pad')
	m.moveq(0, d2)
	for row in 0 .. 4 {
		row_select := jagkit.joystick_enable | 0xf0 | (0xf & ~(1 << row))
		m.move(.w, imm(row_select), abs(jagkit.joystick))
		m.move(.w, abs(jagkit.joystick), d0)
		m.move(.w, abs(jagkit.joybuts), d1)
		m.not(.w, d0) // a line is low while its button is held
		m.lsr(.w, imm(8), d0)
		m.and(.l, imm(0xf), d0)
		mut shift := row * 4
		for shift > 0 {
			step := if shift > 8 { 8 } else { shift }
			m.lsl(.l, imm(step), d0)
			shift -= step
		}
		m.orr(.l, d0, d2)
		released := m.unique('rt.released')
		m.btst(1, d1) // the fire button of the row
		m.b(.ne, released)
		m.bset(16 + row, d2)
		m.label(released)
		if row == 0 {
			unpaused := m.unique('rt.unpaused')
			m.btst(0, d1)
			m.b(.ne, unpaused)
			m.bset(20, d2)
			m.label(unpaused)
		}
	}
	m.move(.l, lbl('pad'), d1)
	m.move(.l, d2, lbl('pad'))
	m.not(.l, d1)
	m.and(.l, d2, d1)
	m.move(.l, d1, lbl('pad_pressed'))
	m.rts()
}
