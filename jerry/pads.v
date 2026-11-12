module jerry

// Button is a logical controller button. The order within each group of
// four is the order of the matrix columns.
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
}

// Pads models the two controller ports: logical button levels on one side,
// the row-select latch and active-low matrix read-back on the other.
pub struct Pads {
pub mut:
	buttons       [2]u32 // bit per `Button`, set while held
	row_select    u16    // low byte of the last write to JOYSTICK
	audio_enabled bool   // bit 8 of JOYSTICK gates the audio output
	region_ntsc   bool = true
}

fn (mut p Pads) reset() {
	p.row_select = 0xff
	p.audio_enabled = false
}

// set changes the level of one button on port 0 or 1.
pub fn (mut p Pads) set(port int, button Button, pressed bool) {
	bit := u32(1) << u32(button)
	if pressed {
		p.buttons[port] |= bit
	} else {
		p.buttons[port] &= ~bit
	}
}

// release_all lets go of every button on both ports.
pub fn (mut p Pads) release_all() {
	p.buttons[0] = 0
	p.buttons[1] = 0
}

// write_select implements a write to JOYSTICK (0xF14000).
pub fn (mut p Pads) write_select(value u16) {
	p.row_select = value & 0xff
	p.audio_enabled = value & 0x100 != 0
}

// row_is_selected reports whether matrix row 0..3 of a port is driven low.
// Port 0 selects rows with bits 0..3; port 1 uses bits 7..4 in reverse.
@[inline]
fn (p &Pads) row_is_selected(port int, row u32) bool {
	bit := if port == 0 { row } else { 7 - row }
	return p.row_select & (u16(1) << bit) == 0
}

// read_columns implements a read of JOYSTICK: four active-low column bits
// per port, bits 11..8 for port 0 and 15..12 for port 1.
pub fn (p &Pads) read_columns() u16 {
	mut value := u16(0xffff)
	for port in 0 .. 2 {
		for row in u32(0) .. 4 {
			if !p.row_is_selected(port, row) {
				continue
			}
			columns := u16(p.buttons[port] >> (row * 4)) & 0xf
			value &= ~(columns << (8 + u32(port) * 4))
		}
	}
	return value
}

// read_buttons implements a read of JOYBUTS: per port one fire-button bit
// and the pause bit, both active low, plus the video standard in bit 4.
pub fn (p &Pads) read_buttons() u16 {
	mut value := u16(0xffef)
	if p.region_ntsc {
		value |= 0x10
	}
	for port in 0 .. 2 {
		fire_bit := u16(1) << (1 + u32(port) * 2)
		pause_bit := u16(1) << (u32(port) * 2)
		for row in u32(0) .. 4 {
			if !p.row_is_selected(port, row) {
				continue
			}
			// Rows 0..3 carry A, B, C and Option on the fire line.
			if p.buttons[port] & (u32(1) << (u32(Button.a) + row)) != 0 {
				value &= ~fire_bit
			}
			if row == 0 && p.buttons[port] & (u32(1) << u32(Button.pause)) != 0 {
				value &= ~pause_bit
			}
		}
	}
	return value
}
