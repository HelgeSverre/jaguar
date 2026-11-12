module hwtypes

// RamBus is flat big-endian memory behind the `Bus` interface: the whole
// address space is RAM, mirrored at the size of the buffer. Device and
// processor tests use it in place of the console's bus.
pub struct RamBus {
pub mut:
	mem []u8
}

// new_ram_bus allocates `size` bytes; `size` must be a power of two.
pub fn new_ram_bus(size int) &RamBus {
	return &RamBus{
		mem: []u8{len: size}
	}
}

// read8 implements Bus.
@[direct_array_access; inline]
pub fn (mut b RamBus) read8(addr u32) u8 {
	return b.mem[addr & u32(b.mem.len - 1)]
}

// read16 implements Bus.
pub fn (mut b RamBus) read16(addr u32) u16 {
	return (u16(b.read8(addr)) << 8) | b.read8(addr + 1)
}

// read32 implements Bus.
pub fn (mut b RamBus) read32(addr u32) u32 {
	return (u32(b.read16(addr)) << 16) | b.read16(addr + 2)
}

// write8 implements Bus.
@[direct_array_access; inline]
pub fn (mut b RamBus) write8(addr u32, val u8) {
	b.mem[addr & u32(b.mem.len - 1)] = val
}

// write16 implements Bus.
pub fn (mut b RamBus) write16(addr u32, val u16) {
	b.write8(addr, u8(val >> 8))
	b.write8(addr + 1, u8(val))
}

// write32 implements Bus.
pub fn (mut b RamBus) write32(addr u32, val u32) {
	b.write16(addr, u16(val >> 16))
	b.write16(addr + 2, u16(val))
}

// read64 reads a big-endian phrase.
pub fn (mut b RamBus) read64(addr u32) u64 {
	return (u64(b.read32(addr)) << 32) | b.read32(addr + 4)
}

// write64 writes a big-endian phrase.
pub fn (mut b RamBus) write64(addr u32, val u64) {
	b.write32(addr, u32(val >> 32))
	b.write32(addr + 4, u32(val))
}
