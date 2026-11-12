// TOM: video timing, the object processor, the blitter and the interrupt
// controller of the Jaguar's graphics chip. The GPU core lives in `risc`.
module tom

import hwtypes

// Irq numbers the interrupt sources of INT1, which are also the bit numbers.
pub enum Irq {
	video
	gpu
	object
	timer
	jerry
}

// GPU interrupt lines driven by TOM devices.
pub const gpu_irq_timer = u32(2)
pub const gpu_irq_object = u32(3)
pub const gpu_irq_blitter = u32(4)

// Register offsets from 0xF00000.
pub const reg_hc = u32(0x04)
const reg_vc = u32(0x06)
const reg_ob = u32(0x10) // OB0..OB3: the object that raised a GPU interrupt
const reg_olp_low = u32(0x20)
const reg_olp_high = u32(0x22)
const reg_obf = u32(0x26)
const reg_vmode = u32(0x28)
const reg_bord1 = u32(0x2a)
const reg_bord2 = u32(0x2c)
const reg_hp = u32(0x2e)
const reg_hdb1 = u32(0x38)
const reg_hde = u32(0x3c)
const reg_vp = u32(0x3e)
const reg_vdb = u32(0x46)
const reg_vde = u32(0x48)
const reg_vi = u32(0x4e)
const reg_pit0 = u32(0x50)
const reg_pit1 = u32(0x52)
const reg_bg = u32(0x58)
const reg_int1 = u32(0xe0)

const clut_base = u32(0x400)
const clut_end = u32(0x800)
const lbuf_base = u32(0x800)
const lbuf_end = u32(0x2000)

// VMODE bits.
const vmode_video_enable = u16(1 << 0)
const vmode_background_enable = u16(1 << 7)
const vmode_variable_colour = u16(1 << 8)

// lbuf_pixels is the number of 16-bit entries in one line buffer.
const lbuf_pixels = 720

// The part of the raster shown to the user, in horizontal counter ticks and
// in half-lines. These windows match a correctly adjusted television; they
// are a presentation choice, not hardware state.
const visible_hc_width = 1300
const max_frame_width = visible_hc_width
const max_frame_height = 288

struct Raster {
	left_hc     int
	top_vc      int
	bottom_vc   int
	half_period u32 // default HP + 1
	half_lines  u32 // default VP + 1
}

fn raster_for(region hwtypes.Region) Raster {
	return match region {
		.ntsc {
			Raster{
				left_hc:     188
				top_vc:      31
				bottom_vc:   511
				half_period: 845
				half_lines:  525
			}
		}
		.pal {
			Raster{
				left_hc:     204
				top_vc:      67
				bottom_vc:   579
				half_period: 851
				half_lines:  625
			}
		}
	}
}

// Tom is the guest-visible state of the graphics chip apart from the GPU.
@[heap]
pub struct Tom {
pub:
	region hwtypes.Region
	raster Raster
pub mut:
	regs        [128]u16 // 0xF00000..0xF000FF as last written
	clut        [256]u16
	lbuf        []u16 = []u16{len: lbuf_pixels}
	vc          u32 // vertical counter in half-lines
	hc          u16 // refreshed by the machine before the guest reads it
	int_pending u32 // INT1 latches, bit per `Irq`
	int_enable  u32
	gpu_irqs    u32  // interrupt lines for the machine to forward to the GPU
	pit_dirty   bool // the programmable timer was rewritten
	blitter     Blitter
	// Object processor state that survives between scheduler events.
	op_pointer   u32
	op_suspended bool // stopped at a GPU object until OBF is written
	op_flag      bool
	line_vc      u32  // the half-line whose line buffer is being composed
	line_open    bool // a line buffer awaits conversion to the frame
	objects      u64  // objects processed, for diagnostics
	// Completed picture.
	frame          []u32 = []u32{len: max_frame_width * max_frame_height}
	frame_width    int   = 325
	frame_height   int   = 240
	frame_sequence u64
	pixel_divider  u32 = 4 // divider the frame is presented at
	finest_divider u32 // smallest divider of the lines shown so far
}

// new creates TOM for a television standard.
pub fn new(region hwtypes.Region) &Tom {
	raster := raster_for(region)
	return &Tom{
		region:       region
		raster:       raster
		frame_height: (raster.bottom_vc - raster.top_vc) / 2
	}
}

// reset applies the peripheral reset: registers, latches and video counters.
pub fn (mut t Tom) reset() {
	for i in 0 .. t.regs.len {
		t.regs[i] = 0
	}
	t.vc = 0
	t.hc = 0
	t.int_pending = 0
	t.int_enable = 0
	t.gpu_irqs = 0
	t.pit_dirty = true
	t.op_pointer = 0
	t.op_suspended = false
	t.op_flag = false
	t.line_open = false
	t.blitter.reset()
}

// raise latches an interrupt source of INT1.
@[inline]
pub fn (mut t Tom) raise(irq Irq) {
	t.int_pending |= u32(1) << u32(irq)
}

// irq_asserted reports whether TOM drives the 68000 interrupt line.
@[inline]
pub fn (t &Tom) irq_asserted() bool {
	return t.int_pending & t.int_enable != 0
}

// half_period returns the length of one half-line in master ticks.
pub fn (t &Tom) half_period() u32 {
	hp := u32(t.regs[reg_hp >> 1]) & 0x3ff
	return if hp == 0 { t.raster.half_period } else { hp + 1 }
}

// half_lines returns the number of half-lines per field.
fn (t &Tom) half_lines() u32 {
	vp := u32(t.regs[reg_vp >> 1]) & 0x7ff
	return if vp == 0 { t.raster.half_lines } else { vp + 1 }
}

// pit_period returns the programmable timer period in master ticks, or zero
// when the timer is stopped.
pub fn (t &Tom) pit_period() u64 {
	prescaler := u64(t.regs[reg_pit0 >> 1])
	if prescaler == 0 {
		return 0
	}
	return (prescaler + 1) * (u64(t.regs[reg_pit1 >> 1]) + 1)
}

// pit_expired is called by the machine when the programmable timer fires.
pub fn (mut t Tom) pit_expired() {
	t.raise(.timer)
	t.gpu_irqs |= u32(1) << gpu_irq_timer
}

// olp returns the object list pointer. The register pair is word-swapped:
// the word at the lower address holds the low half of the address.
@[inline]
fn (t &Tom) olp() u32 {
	return (u32(t.regs[reg_olp_high >> 1]) << 16) | t.regs[reg_olp_low >> 1]
}

// read16 reads a register, palette or line-buffer word. `offset` is relative
// to 0xF00000 and below 0x2000.
@[direct_array_access]
pub fn (t &Tom) read16(offset u32) u16 {
	if offset < 0x100 {
		return match offset & 0xfe {
			reg_hc { t.hc }
			reg_vc { u16(t.vc) }
			reg_int1 { u16(t.int_pending) }
			else { t.regs[offset >> 1] }
		}
	}
	if offset >= clut_base && offset < clut_end {
		return t.clut[(offset >> 1) & 0xff]
	}
	if offset >= lbuf_base && offset < lbuf_end {
		index := ((offset - lbuf_base) & 0x7ff) >> 1
		return if index < lbuf_pixels { t.lbuf[index] } else { u16(0) }
	}
	return 0
}

// write16 writes a register, palette or line-buffer word.
@[direct_array_access]
pub fn (mut t Tom) write16(offset u32, value u16, mut bus hwtypes.Bus) {
	if offset < 0x100 {
		t.regs[offset >> 1] = value
		match offset & 0xfe {
			reg_int1 {
				t.int_enable = value & 0x1f
				t.int_pending &= ~(u32(value >> 8) & 0x1f)
			}
			reg_obf {
				t.op_flag = value & 1 != 0
				if t.op_suspended {
					t.op_suspended = false
					t.run_object_list(mut bus)
				}
			}
			reg_pit0, reg_pit1 {
				t.pit_dirty = true
			}
			else {}
		}

		return
	}
	if offset >= clut_base && offset < clut_end {
		t.clut[(offset >> 1) & 0xff] = value
		return
	}
	if offset >= lbuf_base && offset < lbuf_end {
		index := ((offset - lbuf_base) & 0x7ff) >> 1
		if index < lbuf_pixels {
			t.lbuf[index] = value
		}
	}
}

// half_line advances the vertical counter by one half-line and does the work
// that belongs to it. It returns true when a field has completed.
pub fn (mut t Tom) half_line(mut bus hwtypes.Bus) bool {
	t.finish_line()
	t.vc++
	mut frame_done := false
	if t.vc >= t.half_lines() {
		t.vc = 0
		t.begin_frame()
		frame_done = true
	}
	if t.vc == u32(t.regs[reg_vi >> 1]) & 0x7ff {
		t.raise(.video)
	}
	if t.vc & 1 == 0 {
		t.begin_line(mut bus)
	}
	return frame_done
}

// begin_frame publishes the finished picture and fixes the geometry of the
// next one from the pixel clock divider.
fn (mut t Tom) begin_frame() {
	t.frame_sequence++
	// The picture is as fine as the finest line of the field just shown; a
	// guest may switch the divider between lines.
	t.pixel_divider = if t.finest_divider == 0 { t.line_divider() } else { t.finest_divider }
	t.finest_divider = 0
	t.frame_width = visible_hc_width / int(t.pixel_divider)
}

// line_divider returns the pixel clock divider currently programmed.
@[inline]
fn (t &Tom) line_divider() u32 {
	return ((u32(t.regs[reg_vmode >> 1]) >> 9) & 7) + 1
}

// frame_info describes the most recently completed frame.
pub fn (t &Tom) frame_info() hwtypes.FrameInfo {
	// Four pixel clocks per pixel give square-ish pixels on a 4:3 screen.
	return hwtypes.FrameInfo{
		width:        t.frame_width
		height:       t.frame_height
		pitch:        max_frame_width
		sequence:     t.frame_sequence
		pixel_aspect: f64(t.pixel_divider) / 4.0
	}
}

// linear_hc converts a horizontal register value to ticks from line start.
// Bit 10 of the counter marks the second half of the line.
@[inline]
fn (t &Tom) linear_hc(value u16) int {
	position := int(value & 0x3ff)
	return if value & 0x400 != 0 { position + int(t.half_period()) } else { position }
}

// begin_line composes the line buffer for the current half-line.
fn (mut t Tom) begin_line(mut bus hwtypes.Bus) {
	vmode := t.regs[reg_vmode >> 1]
	t.line_vc = t.vc
	t.line_open = true
	t.op_suspended = false
	if !t.line_is_active() {
		return
	}
	if vmode & vmode_background_enable != 0 {
		background := t.regs[reg_bg >> 1]
		for i in 0 .. lbuf_pixels {
			t.lbuf[i] = background
		}
	}
	t.op_pointer = t.olp()
	t.run_object_list(mut bus)
}

// line_is_active reports whether the open line lies in the display window.
fn (t &Tom) line_is_active() bool {
	if t.regs[reg_vmode >> 1] & vmode_video_enable == 0 {
		return false
	}
	vdb := u32(t.regs[reg_vdb >> 1]) & 0x7ff
	vde := u32(t.regs[reg_vde >> 1])
	return t.line_vc >= vdb && t.line_vc < vde
}

// finish_line converts the open line buffer to display pixels.
@[direct_array_access]
fn (mut t Tom) finish_line() {
	if !t.line_open {
		return
	}
	t.line_open = false
	row := (int(t.line_vc) - t.raster.top_vc) / 2
	if int(t.line_vc) < t.raster.top_vc || row >= t.frame_height {
		return
	}
	width := t.frame_width
	base := row * max_frame_width
	border := (u32(t.regs[reg_bord1 >> 1] & 0xff) << 16) | (u32(t.regs[reg_bord1 >> 1] >> 8) << 8) | (t.regs[reg_bord2 >> 1] & 0xff)
	if !t.line_is_active() {
		for x in 0 .. width {
			t.frame[base + x] = border
		}
		return
	}
	// Each output pixel samples the line buffer at its own horizontal
	// counter position, so lines with a coarser divider than the frame's
	// are widened.
	divider := int(t.line_divider())
	if t.finest_divider == 0 || u32(divider) < t.finest_divider {
		t.finest_divider = u32(divider)
	}
	frame_divider := int(t.pixel_divider)
	display_begin := t.linear_hc(t.regs[reg_hdb1 >> 1])
	display_end := t.linear_hc(t.regs[reg_hde >> 1])
	vmode := t.regs[reg_vmode >> 1]
	mode := (vmode >> 1) & 3
	variable := vmode & vmode_variable_colour != 0
	for x in 0 .. width {
		hc := t.raster.left_hc + x * frame_divider
		if hc < display_begin || hc >= display_end {
			t.frame[base + x] = border
			continue
		}
		source := (hc - display_begin) / divider
		t.frame[base + x] = match mode {
			0 {
				if source >= lbuf_pixels {
					border
				} else if variable && t.lbuf[source] & 1 != 0 {
					rgb16_to_rgb(t.lbuf[source])
				} else {
					cry_to_rgb(t.lbuf[source])
				}
			}
			1 {
				// 24-bit pixels occupy two entries: green:red, then x:blue.
				if source * 2 + 1 >= lbuf_pixels {
					border
				} else {
					high := u32(t.lbuf[source * 2])
					((high & 0xff) << 16) | (high & 0xff00) | (t.lbuf[source * 2 + 1] & 0xff)
				}
			}
			else {
				if source >= lbuf_pixels {
					border
				} else if variable && t.lbuf[source] & 1 == 0 {
					cry_to_rgb(t.lbuf[source])
				} else {
					rgb16_to_rgb(t.lbuf[source])
				}
			}
		}
	}
}
