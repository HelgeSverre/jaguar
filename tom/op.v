// The object processor: walks the guest's display list once per line and
// composes bitmap objects into the line buffer.
module tom

import hwtypes

// Object types, the low three bits of the first phrase.
const object_bitmap = u32(0)
const object_scaled = u32(1)
const object_gpu = u32(2)
const object_branch = u32(3)
const object_stop = u32(4)

// max_objects_per_line bounds the work of one line. Real hardware runs out
// of line time long before this; the bound keeps a looping guest list from
// stalling the host.
const max_objects_per_line = 512

// one is 1.0 in the 3.5 fixed-point format of the scaling fields.
const one = 0x20

// BitmapObject is the decoded second phrase of a bitmap object.
struct BitmapObject {
	xpos      int
	depth     u32 // log2 of bits per pixel
	pitch     u32 // phrases from one data phrase to the next
	iwidth    u32 // image width in phrases
	index     u32 // palette offset, already shifted to bit 1
	reflect   bool
	rmw       bool
	trans     bool
	first_pix u32
	data      u32 // address of the line's first phrase
	hscale    u32 // 3.5 fixed point; `one` for unscaled objects
}

@[inline]
fn read_phrase(mut bus hwtypes.Bus, addr u32) u64 {
	return (u64(bus.read32(addr)) << 32) | bus.read32(addr + 4)
}

@[inline]
fn write_phrase(mut bus hwtypes.Bus, addr u32, value u64) {
	bus.write32(addr, u32(value >> 32))
	bus.write32(addr + 4, u32(value))
}

// run_object_list processes objects from `op_pointer` until the list stops,
// a GPU object suspends it, or the per-line bound is reached.
fn (mut t Tom) run_object_list(mut bus hwtypes.Bus) {
	vc := t.line_vc
	for _ in 0 .. max_objects_per_line {
		addr := t.op_pointer & 0x3f_fff8
		p0 := read_phrase(mut bus, addr)
		t.objects++
		link := u32(p0 >> 21) & 0x3f_fff8
		ypos := u32(p0 >> 3) & 0x7ff
		match u32(p0) & 7 {
			object_bitmap {
				height := u32(p0 >> 14) & 0x3ff
				if vc >= ypos && height > 0 {
					p1 := read_phrase(mut bus, addr + 8)
					t.draw_bitmap(mut bus, decode_bitmap(p0, p1, one))
					dwidth := (p1 >> 18) & 0x3ff
					write_phrase(mut bus, addr, advance_bitmap(p0, height - 1, dwidth))
				}
				t.op_pointer = link
			}
			object_scaled {
				height := u32(p0 >> 14) & 0x3ff
				if vc >= ypos && height > 0 {
					p1 := read_phrase(mut bus, addr + 8)
					p2 := read_phrase(mut bus, addr + 16)
					t.draw_bitmap(mut bus, decode_bitmap(p0, p1, u32(p2) & 0xff))
					t.advance_scaled(mut bus, addr, p0, p1, p2)
				}
				t.op_pointer = link
			}
			object_gpu {
				// OB0..OB3 expose the object, low long first.
				t.regs[(reg_ob >> 1)] = u16(p0 >> 16)
				t.regs[(reg_ob >> 1) + 1] = u16(p0)
				t.regs[(reg_ob >> 1) + 2] = u16(p0 >> 48)
				t.regs[(reg_ob >> 1) + 3] = u16(p0 >> 32)
				t.gpu_irqs |= u32(1) << gpu_irq_object
				t.op_pointer = addr + 8
				t.op_suspended = true
				return
			}
			object_branch {
				taken := match u32(p0 >> 14) & 7 {
					0 { vc == ypos || ypos == 0x7ff }
					1 { vc < ypos }
					2 { vc > ypos }
					3 { t.op_flag }
					4 { t.hc & 0x400 != 0 }
					else { false }
				}

				t.op_pointer = if taken { link } else { addr + 8 }
			}
			object_stop {
				if p0 & 8 != 0 {
					t.raise(.object)
				}
				return
			}
			else {
				return
			}
		}
	}
}

// decode_bitmap extracts the drawing parameters of a bitmap object.
fn decode_bitmap(p0 u64, p1 u64, hscale u32) BitmapObject {
	depth := u32(p1 >> 12) & 7
	// The palette index supplies the bits a narrow pixel does not have.
	index_mask := match depth {
		0 { u32(0xfe) }
		1 { u32(0xfc) }
		2 { u32(0xf0) }
		else { u32(0) }
	}

	return BitmapObject{
		xpos:      int(hwtypes.sext(u32(p1) & 0xfff, 12))
		depth:     depth
		pitch:     u32(p1 >> 15) & 7
		iwidth:    u32(p1 >> 28) & 0x3ff
		index:     (u32(p1 >> 37) & 0xfe) & index_mask
		reflect:   p1 & (u64(1) << 45) != 0
		rmw:       p1 & (u64(1) << 46) != 0
		trans:     p1 & (u64(1) << 47) != 0
		first_pix: u32(p1 >> 49) & 0x3f
		data:      u32(p0 >> 40) & 0xff_fff8
		hscale:    hscale
	}
}

// advance_bitmap returns the first phrase after one displayed line: one line
// less to go and the data pointer moved on by `dwidth` phrases.
fn advance_bitmap(p0 u64, height u32, dwidth u64) u64 {
	data := ((p0 >> 43) + dwidth) & 0x1f_ffff
	return (p0 & 0x0000_07ff_ff00_3fff) | (u64(height) << 14) | (data << 43)
}

// advance_scaled steps a scaled object's vertical remainder by one display
// line and writes the consumed source lines back to the object.
fn (mut t Tom) advance_scaled(mut bus hwtypes.Bus, addr u32, p0 u64, p1 u64, p2 u64) {
	vscale := int(p2 >> 8) & 0xff
	mut remainder := (int(p2 >> 16) & 0xff) - one
	mut height := u32(p0 >> 14) & 0x3ff
	mut lines := u64(0)
	if vscale != 0 {
		for remainder <= 0 {
			remainder += vscale
			lines++
			if height > 0 {
				height--
			}
		}
	}
	if lines > 0 {
		dwidth := (p1 >> 18) & 0x3ff
		write_phrase(mut bus, addr, advance_bitmap(p0, height, dwidth * lines))
	}
	write_phrase(mut bus, addr + 16, (p2 & ~u64(0xff_0000)) | (u64(remainder & 0xff) << 16))
}

// draw_bitmap composes one line of a bitmap object into the line buffer.
// Scaling is destination driven: each source pixel is repeated while the
// horizontal remainder stays positive.
@[direct_array_access]
fn (mut t Tom) draw_bitmap(mut bus hwtypes.Bus, o BitmapObject) {
	if o.depth > 5 || o.hscale == 0 {
		return
	}
	bits := u32(1) << o.depth
	per_phrase := u32(64) >> o.depth
	total := o.iwidth * per_phrase
	pixel_mask := if bits == 32 { u64(0xffff_ffff) } else { (u64(1) << bits) - 1 }
	// 24-bit pixels take two line-buffer entries each.
	limit := if o.depth == 5 { lbuf_pixels / 2 } else { lbuf_pixels }
	step := if o.reflect { -1 } else { 1 }
	hscale := int(o.hscale)

	mut source := o.first_pix >> o.depth
	mut x := o.xpos
	mut remainder := hscale
	mut loaded := u32(0xffff_ffff)
	mut phrase := u64(0)
	for source < total {
		if (step > 0 && x >= limit) || (step < 0 && x < 0) {
			break
		}
		if x >= 0 && x < limit {
			index := source / per_phrase
			if index != loaded {
				phrase = read_phrase(mut bus, o.data + index * o.pitch * 8)
				loaded = index
			}
			shift := 64 - bits * (source % per_phrase + 1)
			pixel := u32((phrase >> shift) & pixel_mask)
			if pixel != 0 || !o.trans {
				t.put_pixel(x, pixel, o)
			}
		}
		x += step
		remainder -= one
		for remainder <= 0 {
			remainder += hscale
			source++
		}
	}
}

// put_pixel stores one object pixel at line-buffer position `x`.
@[direct_array_access; inline]
fn (mut t Tom) put_pixel(x int, pixel u32, o BitmapObject) {
	if o.depth == 5 {
		t.lbuf[x * 2] = u16(pixel >> 16)
		t.lbuf[x * 2 + 1] = u16(pixel)
		return
	}
	colour := if o.depth == 4 { u16(pixel) } else { t.clut[(o.index | pixel) & 0xff] }
	t.lbuf[x] = if o.rmw { blend(t.lbuf[x], colour) } else { colour }
}

// blend implements the read-modify-write object mode: the source's
// luminance and both chroma nibbles are signed offsets added to the line
// buffer with saturation.
fn blend(dst u16, src u16) u16 {
	luma := clamp(int(dst & 0xff) + int(i8(u8(src))), 0xff)
	chroma_low := clamp(int((dst >> 8) & 0xf) + signed_nibble(src >> 8), 0xf)
	chroma_high := clamp(int((dst >> 12) & 0xf) + signed_nibble(src >> 12), 0xf)
	return (u16(chroma_high) << 12) | (u16(chroma_low) << 8) | u16(luma)
}

@[inline]
fn signed_nibble(value u16) int {
	nibble := int(value & 0xf)
	return if nibble >= 8 { nibble - 16 } else { nibble }
}

@[inline]
fn clamp(value int, max int) int {
	if value < 0 {
		return 0
	}
	return if value > max { max } else { value }
}
