module machine

import hwtypes
import tom

// Compare the console's RAM-copy path with the ordinary bus implementation,
// including the ordering of overlapping pixels and all register writeback.
fn test_blitter_copy_matches_scalar_bus() {
	for variant in 0 .. 26 {
		mut m := new(Config{})
		for i in 0 .. m.ram.len {
			m.ram[i] = u8((i * 37) ^ (i >> 8))
		}
		mut scalar := hwtypes.new_ram_bus(ram_size)
		scalar.mem = m.ram.clone()
		mut reference := tom.Blitter{}
		mut regs := [40]u32{}
		regs[0] = if variant == 16 { u32(0x204000) } else { u32(0x4000) }
		regs[9] = if variant == 17 { u32(0x206000) } else { u32(0x6000) }
		// Width 320, 16 bpp; exercise every phrase pitch and starting slot.
		regs[1] = 0x4220 | u32(variant % 4)
		regs[10] = 0x4220 | u32((variant / 4) % 4)
		regs[3] = u32(variant % 4)
		regs[12] = u32((variant + 1) % 4)
		regs[4] = 0x0001fff0
		regs[13] = 0x0001fff0
		regs[15] = 0x0003000d
		mut cmd := u32(0x01800609)
		match variant {
			8, 9 { // Forward overlap must retain scalar read-before-write order.
				regs[9] = regs[0]
				regs[1] = 0x4220
				regs[10] = 0x4220
				regs[3] = if variant == 8 { u32(1) } else { u32(0) }
				regs[12] = if variant == 8 { u32(0) } else { u32(1) }
			}
			10 {
				cmd |= 1 << 11
			} // Reverse A1/A2 roles.
			11 {
				regs[1] |= 1 << 16
				regs[10] |= 1 << 16
			}
			12 {
				regs[3] = 0xfffc
				regs[12] = 0xfffe
			} // X wraps.
			13 {
				regs[0] = 0x1ffff8
				regs[9] = 0x1ffff0
			} // RAM mirror boundary.
			14 {
				regs[1] |= 1 << 19
			} // Negative X uses scalar fallback.
			15 {
				regs[10] |= 1 << 15
				regs[11] = 0x00000007
			}
			18 {
				cmd |= 1 << 6
				regs[2] = 0x00020008
			} // Clipping.
			19 {
				cmd |= 1 << 27
			} // Data compare.
			20 {
				regs[1] = 0x4218
				regs[10] = 0x4218
			} // 8 bpp.
			21 {
				regs[15] = 0x00030000
			} // Empty rows still step.
			22 {
				regs[15] = 0x00030001
			} // Partial phrase at each end.
			23 {
				cmd &= ~u32(8)
			} // Destination read disabled.
			24 { // Fight for Life's complete pitch-3 background copy.
				regs[1] = 0x4223
				regs[10] = 0x4220
				regs[3] = 0
				regs[12] = 0
				regs[4] = 0x0001fec0
				regs[13] = 0x0001fec0
				regs[15] = 0x00f00140
			}
			25 {
				regs[15] = 0x00000008
			} // No rows.
			else {}
		}

		m.tom.blitter.regs = regs
		reference.regs = regs
		mut bus := m.self_bus
		m.tom.blitter.write32(0x38, cmd, mut bus)
		reference.write32(0x38, cmd, mut scalar)
		assert m.ram == scalar.mem, 'variant ${variant}: memory'
		assert m.tom.blitter.regs == reference.regs, 'variant ${variant}: registers'
		assert m.tom.blitter.intensity == reference.intensity
		assert m.tom.blitter.depth == reference.depth
		assert m.tom.blitter.pixels == reference.pixels
		assert m.tom.blitter.blits == reference.blits
	}
}

fn test_blitter_copy_declines_non_ram_and_crossing_rows_before_writing() {
	mut m := new(Config{})
	for i in 0 .. m.ram.len {
		m.ram[i] = u8(i * 13)
	}
	before := m.ram.clone()
	for addr in [u32(0x400000), 0x800000, 0xe00000, 0xf03000, 0xf02200, 0x1ffff8, 0x3ffff8, 0x4001] {
		assert !m.blit_copy16(addr, 0x4000, 16, 1, 3)
		assert !m.blit_copy16(0x4000, addr, 16, 3, 1)
		assert m.ram == before
	}
	assert !m.blit_copy16(0x4000, 0x6000, 0, 1, 1)
	assert !m.blit_copy16(0x4000, 0x6000, 16, 0, 1)
	assert !m.blit_copy16(0x4000, 0x6000, 16, 1, 5)
}
