// The blitter: two address generators (A1, A2) and a data path that copies,
// fills, shades and Z-tests rectangles and lines of pixels.
//
// Timing profile `functional_v1`: a blit runs to completion when the command
// register is written, pixel by pixel. Phrase mode is modelled by its
// results, not by its bus cycles, so a blit is never observed in progress.
module tom

import hwtypes

// Register offsets from 0xF02200.
const b_a1_base = u32(0x00)
const b_a1_flags = u32(0x04)
const b_a1_clip = u32(0x08)
const b_a1_pixel = u32(0x0c)
const b_a1_step = u32(0x10)
const b_a1_fstep = u32(0x14)
const b_a1_fpixel = u32(0x18)
const b_a1_inc = u32(0x1c)
const b_a1_finc = u32(0x20)
const b_a2_base = u32(0x24)
const b_a2_flags = u32(0x28)
const b_a2_mask = u32(0x2c)
const b_a2_pixel = u32(0x30)
const b_a2_step = u32(0x34)
const b_cmd = u32(0x38)
const b_count = u32(0x3c)
const b_srcd = u32(0x40)
const b_dstd = u32(0x48)
const b_dstz = u32(0x50)
const b_srcz1 = u32(0x58)
const b_patd = u32(0x68)
const b_iinc = u32(0x70)
const b_zinc = u32(0x74)
const b_i3 = u32(0x7c)
const b_z3 = u32(0x8c)
const b_end = u32(0x9c)

// Command register bits.
const cmd_srcen = u32(1 << 0)
const cmd_srcenz = u32(1 << 1)
const cmd_dsten = u32(1 << 3)
const cmd_dstenz = u32(1 << 4)
const cmd_dstwrz = u32(1 << 5)
const cmd_clip_a1 = u32(1 << 6)
const cmd_upda1f = u32(1 << 8)
const cmd_upda1 = u32(1 << 9)
const cmd_upda2 = u32(1 << 10)
const cmd_dsta2 = u32(1 << 11)
const cmd_gourd = u32(1 << 12)
const cmd_gourz = u32(1 << 13)
const cmd_topben = u32(1 << 14)
const cmd_topnen = u32(1 << 15)
const cmd_patdsel = u32(1 << 16)
const cmd_adddsel = u32(1 << 17)
const cmd_cmpdst = u32(1 << 25)
const cmd_bcompen = u32(1 << 26)
const cmd_dcompen = u32(1 << 27)
const cmd_bkgwren = u32(1 << 28)
const cmd_srcshade = u32(1 << 30)

// Address-generator flag bits.
const flag_mask_enable = u32(1 << 15)
const xadd_phrase = u32(0)
const xadd_zero = u32(2)
const xadd_increment = u32(3)

const status_idle = u32(1)

// max_blit_pixels bounds one command so a runaway guest count cannot stall
// the host. No real blit approaches it.
const max_blit_pixels = u64(1) << 24

// Blitter holds the register file. Fixed-point registers are 16.16.
pub struct Blitter {
pub mut:
	regs      [40]u32 // by offset / 4
	intensity [4]u32  // B_I3, B_I2, B_I1, B_I0 as 8.16 values
	depth     [4]u32  // B_Z3..B_Z0 as 16.16 values
	blits     u64     // commands executed
	pixels    u64     // pixels processed
}

fn (mut b Blitter) reset() {
	for i in 0 .. b.regs.len {
		b.regs[i] = 0
	}
	for i in 0 .. 4 {
		b.intensity[i] = 0
		b.depth[i] = 0
	}
}

// read32 reads a blitter register; only the status register reads back.
pub fn (b &Blitter) read32(offset u32) u32 {
	return if offset & 0xfc == b_cmd { status_idle } else { u32(0) }
}

// write32 writes a whole register and runs the blit when it is the command.
@[direct_array_access]
pub fn (mut b Blitter) write32(offset u32, value u32, mut bus hwtypes.Bus) {
	reg := offset & 0xfc
	if reg >= b_end {
		return
	}
	if reg >= b_i3 && reg < b_z3 {
		b.intensity[(reg - b_i3) >> 2] = value & 0x00ff_ffff
		return
	}
	if reg >= b_z3 {
		b.depth[(reg - b_z3) >> 2] = value
		return
	}
	b.regs[reg >> 2] = value
	if reg == b_cmd {
		b.execute(mut bus)
	}
}

// write16 writes half a register. A blit starts on the low half of the
// command, which a 68000 long write delivers last.
@[direct_array_access]
pub fn (mut b Blitter) write16(offset u32, value u16, mut bus hwtypes.Bus) {
	reg := offset & 0xfc
	if reg >= b_end {
		return
	}
	old := if reg >= b_z3 {
		b.depth[(reg - b_z3) >> 2]
	} else if reg >= b_i3 {
		b.intensity[(reg - b_i3) >> 2]
	} else {
		b.regs[reg >> 2]
	}
	if offset & 2 == 0 {
		merged := (old & 0x0000_ffff) | (u32(value) << 16)
		if reg == b_cmd {
			b.regs[reg >> 2] = merged
		} else {
			b.write32(reg, merged, mut bus)
		}
	} else {
		b.write32(reg, (old & 0xffff_0000) | value, mut bus)
	}
}

// Window is one address generator during a blit.
struct Window {
	base         u32
	width        u32 // pixels per line
	psize        u32 // log2 of bits per pixel
	pitch        u32 // phrase spacing
	zoffset      u32 // phrases from pixel data to its Z data
	phrase_mode  bool
	mask_enabled bool
	mask_x       u32
	mask_y       u32
	xadd         u32 // per-pixel increments, 16.16
	yadd         u32
	step_x       u32 // per-line increments, 16.16
	step_y       u32
mut:
	x u32 // 16.16
	y u32
}

const pitch_factor = [u32(1), 2, 4, 3]!

// new_window decodes a flags register into an address generator.
fn new_window(base u32, flags u32, pixel u32, fpixel u32) Window {
	mode := (flags >> 16) & 3
	mut xadd := if mode == xadd_zero { u32(0) } else { u32(0x1_0000) }
	// YADD1 steps Y once per pixel only while X stands still (a vertical
	// run). Commercial software sets it together with a one-pixel X step and
	// a line step of one, and expects rectangles: with X advancing, the flag
	// has no effect on the inner loop. Evidence class: emulator_differential.
	mut yadd := if mode == xadd_zero && flags & (1 << 18) != 0 { u32(0x1_0000) } else { u32(0) }
	if flags & (1 << 19) != 0 {
		xadd = u32(0) - xadd
	}
	if flags & (1 << 20) != 0 {
		yadd = u32(0) - yadd
	}
	psize := (flags >> 3) & 7
	return Window{
		base:        base & 0xffff_fff8
		width:       ((4 | ((flags >> 9) & 3)) << ((flags >> 11) & 0xf)) >> 2
		psize:       if psize > 5 { u32(5) } else { psize }
		pitch:       pitch_factor[flags & 3]
		zoffset:     (flags >> 6) & 7
		phrase_mode: mode == xadd_phrase
		xadd:        xadd
		yadd:        yadd
		x:           ((pixel & 0xffff) << 16) | (fpixel & 0xffff)
		y:           (pixel & 0xffff_0000) | (fpixel >> 16)
	}
}

// phrase_and_slot locates the current pixel: the address of the phrase that
// holds it and its index within that phrase.
@[inline]
fn (w &Window) phrase_and_slot() (u32, u32) {
	// The address generator takes all sixteen bits of X and twelve of Y as
	// plain counts, as the hardware's adder does (Virtual Jaguar's model of
	// the netlist agrees). A program that clears a long run of memory as one
	// line counts X past $7FFF, and that must go on upwards from the base.
	x := (w.x >> 16) & 0xffff
	y := (w.y >> 16) & 0xfff
	index := y * w.width + x
	per_phrase_shift := 6 - w.psize
	phrase := index >> per_phrase_shift
	slot := index & ((u32(1) << per_phrase_shift) - 1)
	return w.base + phrase * w.pitch * 8, slot
}

// read_pixel reads the pixel under the generator.
fn (w &Window) read_pixel(mut bus hwtypes.Bus) u32 {
	phrase, slot := w.phrase_and_slot()
	bit := slot << w.psize
	addr := phrase + (bit >> 3)
	match w.psize {
		0, 1, 2 {
			bits := u32(1) << w.psize
			shift := 8 - bits - (bit & 7)
			return (u32(bus.read8(addr)) >> shift) & ((u32(1) << bits) - 1)
		}
		3 {
			return bus.read8(addr)
		}
		4 {
			return bus.read16(addr)
		}
		else {
			return bus.read32(addr)
		}
	}
}

// write_pixel writes the pixel under the generator.
fn (w &Window) write_pixel(mut bus hwtypes.Bus, value u32) {
	phrase, slot := w.phrase_and_slot()
	bit := slot << w.psize
	addr := phrase + (bit >> 3)
	match w.psize {
		0, 1, 2 {
			bits := u32(1) << w.psize
			shift := 8 - bits - (bit & 7)
			mask := ((u32(1) << bits) - 1) << shift
			old := u32(bus.read8(addr))
			bus.write8(addr, u8((old & ~mask) | ((value << shift) & mask)))
		}
		3 {
			bus.write8(addr, u8(value))
		}
		4 {
			bus.write16(addr, u16(value))
		}
		else {
			bus.write32(addr, value)
		}
	}
}

// z_address returns where the 16-bit depth of the current pixel is stored.
@[inline]
fn (w &Window) z_address() u32 {
	phrase, slot := w.phrase_and_slot()
	return phrase + w.zoffset * 8 + ((slot & 3) << 1)
}

// advance moves the generator on by one pixel.
@[inline]
fn (mut w Window) advance() {
	w.x += w.xadd
	w.y += w.yadd
	if w.mask_enabled {
		w.x &= w.mask_x
		w.y &= w.mask_y
	}
}

// end_line applies the per-line step. A phrase-mode pass always ends on a
// phrase boundary, so the pointer is first rounded up to the next one.
@[inline]
fn (mut w Window) end_line() {
	if w.phrase_mode {
		per_phrase := u32(64) >> w.psize
		over := (w.x >> 16) & (per_phrase - 1)
		if over != 0 {
			w.x += (per_phrase - over) << 16
		}
	}
	w.x += w.step_x
	w.y += w.step_y
}

// register_pixel extracts the pixel a 64-bit data register supplies for the
// generator's position. Phrase mode takes the pixel's own slot, most
// significant first; pixel mode takes the low bits of the first long.
@[inline]
fn register_pixel(high u32, low u32, w &Window) u32 {
	bits := u32(1) << w.psize
	if bits == 32 {
		return if w.phrase_mode && (w.x >> 16) & 1 != 0 { low } else { high }
	}
	mask := (u32(1) << bits) - 1
	if !w.phrase_mode {
		return high & mask
	}
	per_phrase := u32(64) >> w.psize
	slot := (w.x >> 16) & (per_phrase - 1)
	shift := 64 - bits * (slot + 1)
	return u32(((u64(high) << 32) | low) >> shift) & mask
}

// execute runs the blit described by the register file.
@[direct_array_access]
fn (mut b Blitter) execute(mut bus hwtypes.Bus) {
	cmd := b.regs[b_cmd >> 2]
	b.blits++

	a1_flags := b.regs[b_a1_flags >> 2]
	a2_flags := b.regs[b_a2_flags >> 2]
	mut a1 := new_window(b.regs[b_a1_base >> 2], a1_flags, b.regs[b_a1_pixel >> 2],
		b.regs[b_a1_fpixel >> 2])
	mut a2 := new_window(b.regs[b_a2_base >> 2], a2_flags, b.regs[b_a2_pixel >> 2], 0)
	if (a1_flags >> 16) & 3 == xadd_increment {
		inc := b.regs[b_a1_inc >> 2]
		finc := b.regs[b_a1_finc >> 2]
		a1 = Window{
			...a1
			xadd: signed_increment(((inc & 0xffff) << 16) | (finc & 0xffff),
				a1_flags & (1 << 19) != 0)
			yadd: signed_increment((inc & 0xffff_0000) | (finc >> 16), a1_flags & (1 << 20) != 0)
		}
	}
	mut step_x := u32(0)
	mut step_y := u32(0)
	if cmd & cmd_upda1 != 0 {
		step_x = (b.regs[b_a1_step >> 2] & 0xffff) << 16
		step_y = b.regs[b_a1_step >> 2] & 0xffff_0000
	}
	if cmd & cmd_upda1f != 0 {
		step_x |= b.regs[b_a1_fstep >> 2] & 0xffff
		step_y |= b.regs[b_a1_fstep >> 2] >> 16
	}
	a1 = Window{
		...a1
		step_x: step_x
		step_y: step_y
	}
	if cmd & cmd_upda2 != 0 {
		a2 = Window{
			...a2
			step_x: (b.regs[b_a2_step >> 2] & 0xffff) << 16
			step_y: b.regs[b_a2_step >> 2] & 0xffff_0000
		}
	}
	if a2_flags & flag_mask_enable != 0 {
		a2 = Window{
			...a2
			mask_enabled: true
			mask_x:       ((b.regs[b_a2_mask >> 2] & 0xffff) << 16) | 0xffff
			mask_y:       (b.regs[b_a2_mask >> 2] & 0xffff_0000) | 0xffff
		}
	}

	count := b.regs[b_count >> 2]
	inner := count & 0xffff
	outer := count >> 16
	clip_x := b.regs[b_a1_clip >> 2] & 0x7fff
	clip_y := (b.regs[b_a1_clip >> 2] >> 16) & 0x7fff
	dst_is_a2 := cmd & cmd_dsta2 != 0
	lfunc := (cmd >> 21) & 0xf
	zmode := (cmd >> 18) & 7
	iinc := hwtypes.sext(b.regs[b_iinc >> 2] & 0x00ff_ffff, 24)
	zinc := b.regs[b_zinc >> 2]
	patd_high := b.regs[b_patd >> 2]
	patd_low := b.regs[(b_patd >> 2) + 1]
	mut budget := max_blit_pixels

	for _ in 0 .. outer {
		for _ in 0 .. inner {
			if budget == 0 {
				return
			}
			budget--
			b.pixels++
			mut dst := if dst_is_a2 { &a2 } else { &a1 }
			mut src := if dst_is_a2 { &a1 } else { &a2 }
			// In phrase mode each of the four pixels of a phrase has its own
			// intensity and depth register; pixel mode uses the first.
			lane := if dst.phrase_mode { (dst.x >> 16) & 3 } else { u32(0) }

			srcdata := if cmd & cmd_srcen != 0 {
				src.read_pixel(mut bus)
			} else {
				register_pixel(b.regs[b_srcd >> 2], b.regs[(b_srcd >> 2) + 1], dst)
			}
			dstdata := if cmd & cmd_dsten != 0 {
				dst.read_pixel(mut bus)
			} else {
				register_pixel(b.regs[b_dstd >> 2], b.regs[(b_dstd >> 2) + 1], dst)
			}
			mut srcz := if cmd & cmd_gourz != 0 {
				b.depth[lane] >> 16
			} else if cmd & cmd_srcenz != 0 {
				u32(bus.read16(src.z_address()))
			} else {
				register_pixel(b.regs[b_srcz1 >> 2], b.regs[(b_srcz1 >> 2) + 1], dst) & 0xffff
			}
			dstz := if cmd & cmd_dstenz != 0 {
				u32(bus.read16(dst.z_address()))
			} else {
				register_pixel(b.regs[b_dstz >> 2], b.regs[(b_dstz >> 2) + 1], dst) & 0xffff
			}
			patdata := register_pixel(patd_high, patd_low, dst)

			mut inhibit := false
			if cmd & cmd_bcompen != 0 {
				compared := if cmd & cmd_cmpdst != 0 { dstdata } else { srcdata }
				inhibit = compared == 0
			}
			if cmd & cmd_dcompen != 0 {
				compared := if cmd & cmd_cmpdst != 0 { dstdata } else { srcdata }
				if compared == patdata {
					inhibit = true
				}
			}
			if cmd & cmd_clip_a1 != 0 {
				x := (a1.x >> 16) & 0xffff
				y := (a1.y >> 16) & 0xffff
				if x & 0x8000 != 0 || y & 0x8000 != 0 || x >= clip_x || y >= clip_y {
					inhibit = true
				}
			}
			if (zmode & 1 != 0 && srcz < dstz) || (zmode & 2 != 0 && srcz == dstz)
				|| (zmode & 4 != 0 && srcz > dstz) {
				inhibit = true
			}

			mut writedata := dstdata
			if inhibit {
				srcz = dstz
			} else {
				writedata = if cmd & cmd_patdsel != 0 {
					patdata
				} else if cmd & cmd_adddsel != 0 {
					add_pixels(srcdata, dstdata, cmd)
				} else {
					logic_function(lfunc, srcdata, dstdata)
				}
				if cmd & cmd_gourd != 0 {
					writedata = (patdata & 0xff00) | ((b.intensity[lane] >> 16) & 0xff)
				}
				if cmd & cmd_srcshade != 0 {
					writedata = (srcdata & 0xff00) | shade(srcdata & 0xff, iinc)
				}
			}
			if !inhibit || cmd & cmd_bkgwren != 0 {
				dst.write_pixel(mut bus, writedata)
				if cmd & cmd_dstwrz != 0 {
					bus.write16(dst.z_address(), u16(srcz))
				}
			}

			if cmd & cmd_gourd != 0 {
				b.intensity[lane] = saturate_intensity(b.intensity[lane] + iinc,
					cmd & cmd_topben != 0)
			}
			if cmd & cmd_gourz != 0 {
				b.depth[lane] += zinc
			}
			a1.advance()
			a2.advance()
		}
		a1.end_line()
		a2.end_line()
	}
	// The generators' final positions read back through the pixel registers.
	b.regs[b_a1_pixel >> 2] = (a1.y & 0xffff_0000) | (a1.x >> 16)
	b.regs[b_a1_fpixel >> 2] = ((a1.y & 0xffff) << 16) | (a1.x & 0xffff)
	b.regs[b_a2_pixel >> 2] = (a2.y & 0xffff_0000) | (a2.x >> 16)
}

@[inline]
fn signed_increment(value u32, negate bool) u32 {
	return if negate { u32(0) - value } else { value }
}

// logic_function combines source and destination with the four minterm
// enables of LFUNC.
@[inline]
fn logic_function(lfunc u32, src u32, dst u32) u32 {
	mut result := u32(0)
	if lfunc & 1 != 0 {
		result |= ~src & ~dst
	}
	if lfunc & 2 != 0 {
		result |= ~src & dst
	}
	if lfunc & 4 != 0 {
		result |= src & ~dst
	}
	if lfunc & 8 != 0 {
		result |= src & dst
	}
	return result
}

// add_pixels is the ADDDSEL data path: luminance and the two chroma nibbles
// of a CRY pixel are added separately and saturate unless disabled.
fn add_pixels(src u32, dst u32, cmd u32) u32 {
	mut luma := (src & 0xff) + (dst & 0xff)
	if luma > 0xff && cmd & cmd_topben == 0 {
		luma = 0xff
	}
	mut low := (src & 0x0f00) + (dst & 0x0f00)
	if low > 0x0f00 && cmd & cmd_topnen == 0 {
		low = 0x0f00
	}
	mut high := (src & 0xf000) + (dst & 0xf000)
	if high > 0xf000 && cmd & cmd_topnen == 0 {
		high = 0xf000
	}
	return (high & 0xf000) | (low & 0x0f00) | (luma & 0xff)
}

// shade adds the integer part of the intensity increment to a luminance and
// saturates.
@[inline]
fn shade(luma u32, iinc u32) u32 {
	sum := int(luma) + int(i8(u8(iinc >> 16)))
	if sum < 0 {
		return 0
	}
	return if sum > 0xff { u32(0xff) } else { u32(sum) }
}

// saturate_intensity keeps an 8.16 intensity inside its 24 bits.
@[inline]
fn saturate_intensity(value u32, wrap bool) u32 {
	if wrap {
		return value & 0x00ff_ffff
	}
	if value & 0x8000_0000 != 0 {
		return 0
	}
	return if value > 0x00ff_ffff { u32(0x00ff_ffff) } else { value }
}
