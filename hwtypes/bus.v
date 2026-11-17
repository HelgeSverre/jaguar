// Leaf definitions shared by every processor and device model.
//
// Nothing in this module may import another project module: processors and
// devices depend on these types, and `machine` composes them.
module hwtypes

// Bus is the system bus as seen by one bus master.
//
// Addresses are 24 bits wide; implementations mask the upper byte. Multi-byte
// values are big-endian, as on the real machine. An access never panics the
// host: unmapped regions follow the per-region open-bus policy of the
// implementation.
pub interface Bus {
mut:
	read8(addr u32) u8
	read16(addr u32) u16
	read32(addr u32) u32
	write8(addr u32, val u8)
	write16(addr u32, val u16)
	write32(addr u32, val u32)
}

// BlitCopyBus optionally accelerates a forward row of 16-bit pixels. Each
// pitch is the distance between 64-bit phrases, in phrases (1..4). Addresses
// are word-aligned and may begin inside a phrase. Implementations must retain
// pixel-by-pixel read-before-write order for overlaps. Return false without
// accessing memory when the row cannot be handled without device side effects.
pub interface BlitCopyBus {
mut:
	blit_copy16(src u32, dst u32, pixels u32, src_pitch u32, dst_pitch u32) bool
}
