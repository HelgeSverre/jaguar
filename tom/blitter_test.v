module tom

import hwtypes

const source_base = u32(0x4000)
const target_base = u32(0x8000)

// Flag helpers: 16 bits per pixel, width 64, pitch 1.
const flags_16bpp_w64 = u32((4 << 3) | (6 << 11))
const xadd_pix = u32(1 << 16)

fn (mut b Blitter) set(mut bus hwtypes.RamBus, reg u32, value u32) {
	b.write32(reg, value, mut bus)
}

fn test_pattern_fill_rectangle_with_guards() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	for i in u32(0) .. 64 * 6 {
		bus.write16(target_base + i * 2, 0xeeee)
	}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a1_pixel, (2 << 16) | 3) // y=2, x=3
	b.set(mut bus, b_a1_step, (1 << 16) | u32(u16(-5))) // next line, back 5
	b.set(mut bus, b_patd, 0x1234_1234)
	b.set(mut bus, b_patd + 4, 0x1234_1234)
	b.set(mut bus, b_count, (2 << 16) | 5)
	b.set(mut bus, b_cmd, cmd_patdsel | cmd_upda1)

	for y in u32(0) .. 6 {
		for x in u32(0) .. 64 {
			inside := y >= 2 && y < 4 && x >= 3 && x < 8
			expected := if inside { u16(0x1234) } else { u16(0xeeee) }
			assert bus.read16(target_base + (y * 64 + x) * 2) == expected, 'pixel ${x},${y}'
		}
	}
	assert b.pixels == 10
	assert b.read32(b_cmd) & 1 == 1, 'idle after the blit'
}

fn test_copy_with_logic_functions() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	for i in u32(0) .. 8 {
		bus.write16(source_base + i * 2, u16(0x1100 + i))
		bus.write16(target_base + i * 2, 0x00ff)
	}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a2_base, source_base)
	b.set(mut bus, b_a2_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_count, (1 << 16) | 8)
	b.set(mut bus, b_cmd, cmd_srcen | (0xc << 21)) // LFUNC = source
	for i in u32(0) .. 8 {
		assert bus.read16(target_base + i * 2) == u16(0x1100 + i)
	}

	// XOR needs the destination read.
	b.set(mut bus, b_a1_pixel, 0)
	b.set(mut bus, b_a2_pixel, 0)
	b.set(mut bus, b_count, (1 << 16) | 8)
	b.set(mut bus, b_cmd, cmd_srcen | cmd_dsten | (0x6 << 21))
	for i in u32(0) .. 8 {
		assert bus.read16(target_base + i * 2) == 0
	}
}

fn test_data_comparator_gives_transparency() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	flags_8bpp := u32((3 << 3) | (6 << 11)) | xadd_pix
	pixels := [u8(1), 0, 2, 0]
	for i, p in pixels {
		bus.write8(source_base + u32(i), p)
		bus.write8(target_base + u32(i), 0x99)
	}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_8bpp)
	b.set(mut bus, b_a2_base, source_base)
	b.set(mut bus, b_a2_flags, flags_8bpp)
	b.set(mut bus, b_patd, 0)
	b.set(mut bus, b_patd + 4, 0)
	b.set(mut bus, b_count, (1 << 16) | 4)
	b.set(mut bus, b_cmd, cmd_srcen | cmd_dcompen | (0xc << 21))
	assert bus.mem[target_base..target_base + 4] == [u8(1), 0x99, 2, 0x99]
}

fn test_bit_expansion_from_one_bit_source() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	bus.write8(source_base, 0b1010_0000)
	for i in u32(0) .. 4 {
		bus.write16(target_base + i * 2, 0x5555)
	}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a2_base, source_base)
	b.set(mut bus, b_a2_flags, u32((6 << 11)) | xadd_pix)
	b.set(mut bus, b_patd, 0xabcd_abcd)
	b.set(mut bus, b_patd + 4, 0xabcd_abcd)
	b.set(mut bus, b_count, (1 << 16) | 4)
	b.set(mut bus, b_cmd, cmd_srcen | cmd_bcompen | cmd_patdsel)
	assert bus.read16(target_base) == 0xabcd
	assert bus.read16(target_base + 2) == 0x5555
	assert bus.read16(target_base + 4) == 0xabcd
	assert bus.read16(target_base + 6) == 0x5555
}

fn test_z_buffer_rejects_farther_pixels() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	// Pixel phrase then Z phrase: pitch 2, Z offset 1.
	flags := u32(1 | (4 << 3) | (1 << 6) | (6 << 11)) | xadd_pix
	for i in u32(0) .. 4 {
		bus.write16(target_base + i * 2, 0x1111)
		bus.write16(target_base + 8 + i * 2, u16(0x4000))
	}
	bus.write16(target_base + 8 + 2, 0x0100) // pixel 1 already has something nearer
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags)
	b.set(mut bus, b_patd, 0x2222_2222)
	b.set(mut bus, b_patd + 4, 0x2222_2222)
	b.set(mut bus, b_srcz1, 0x2000_2000)
	b.set(mut bus, b_srcz1 + 4, 0x2000_2000)
	b.set(mut bus, b_count, (1 << 16) | 4)
	// Inhibit when the source is farther (greater) than the destination.
	b.set(mut bus, b_cmd, cmd_patdsel | cmd_dstenz | cmd_dstwrz | (4 << 18))
	assert bus.read16(target_base) == 0x2222
	assert bus.read16(target_base + 2) == 0x1111, 'the nearer pixel survives'
	assert bus.read16(target_base + 8) == 0x2000, 'depth written with the pixel'
	assert bus.read16(target_base + 8 + 2) == 0x0100
}

fn test_clipping_inhibits_writes_outside_the_window() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a1_clip, (10 << 16) | 2)
	b.set(mut bus, b_patd, 0x7777_7777)
	b.set(mut bus, b_patd + 4, 0x7777_7777)
	b.set(mut bus, b_count, (1 << 16) | 4)
	b.set(mut bus, b_cmd, cmd_patdsel | cmd_clip_a1)
	assert bus.read16(target_base) == 0x7777
	assert bus.read16(target_base + 2) == 0x7777
	assert bus.read16(target_base + 4) == 0
}

fn test_runaway_count_is_bounded() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_count, 0xffff_ffff)
	b.set(mut bus, b_cmd, cmd_patdsel)
	assert b.pixels == max_blit_pixels
}

fn test_word_writes_start_the_blit_on_the_low_half() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_patd, 0x0bad_0bad)
	b.write16(b_count, 1, mut bus)
	b.write16(b_count + 2, 1, mut bus)
	b.write16(b_cmd, u16(cmd_patdsel >> 16), mut bus)
	assert b.blits == 0, 'the high half alone does not start a blit'
	b.write16(b_cmd + 2, 0, mut bus)
	assert b.blits == 1
	assert bus.read16(target_base) == 0x0bad
}

fn test_negative_x_addresses_the_previous_line() {
	// Source lines of 4 pixels stored back to back in a window declared 64
	// wide: the step of 1 line and -64 pixels walks them contiguously.
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut b := Blitter{}
	for i in u32(0) .. 8 {
		bus.write16(source_base + i * 2, u16(0x100 + i))
	}
	b.set(mut bus, b_a1_base, target_base)
	b.set(mut bus, b_a1_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a1_step, (1 << 16) | u32(u16(-4)))
	b.set(mut bus, b_a2_base, source_base)
	b.set(mut bus, b_a2_flags, flags_16bpp_w64 | xadd_pix)
	b.set(mut bus, b_a2_step, (1 << 16) | u32(u16(-64)))
	b.set(mut bus, b_count, (2 << 16) | 4)
	b.set(mut bus, b_cmd, cmd_srcen | cmd_upda1 | cmd_upda2 | (0xc << 21))
	for i in u32(0) .. 4 {
		assert bus.read16(target_base + i * 2) == u16(0x100 + i)
		assert bus.read16(target_base + (64 + i) * 2) == u16(0x104 + i)
	}
}
