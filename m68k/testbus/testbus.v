// A flat 16 MiB RAM bus for the m68k tests. It implements `hwtypes.Bus`,
// masks addresses to 24 bits, records every access in bus order and
// remembers which bytes were touched so it can be cleared cheaply between
// test cases.
module testbus

const address_mask = u32(0x00ff_ffff)
const max_events = 256

// BusEvent is one byte or word access as seen on the bus.
pub struct BusEvent {
pub:
	write bool
	bytes u8 // 1 or 2
	addr  u32
	data  u16
}

// str formats the event compactly, e.g. `w2:00fe10=1234`.
pub fn (e BusEvent) str() string {
	kind := if e.write { 'w' } else { 'r' }
	return '${kind}${e.bytes}:${e.addr:06x}=${e.data:04x}'
}

// TestBus is the recording RAM bus.
@[heap]
pub struct TestBus {
mut:
	mem     []u8
	touched []u32
pub mut:
	events      [max_events]BusEvent
	event_count int
	overflowed  bool // more than `max_events` accesses happened
	long_access bool // read32 or write32 was called; the 68000 core never may
}

// new allocates an empty bus.
pub fn new() &TestBus {
	return &TestBus{
		mem:     []u8{len: int(address_mask) + 1}
		touched: []u32{cap: 4096}
	}
}

// clear zeroes every byte written since the last clear and empties the log.
pub fn (mut b TestBus) clear() {
	for addr in b.touched {
		b.mem[addr] = 0
	}
	b.touched.clear()
	b.event_count = 0
	b.overflowed = false
	b.long_access = false
}

// poke16 stores a big-endian word without logging it.
pub fn (mut b TestBus) poke16(addr u32, data u16) {
	b.set(addr, u8(data >> 8))
	b.set(addr + 1, u8(data))
}

// peek16 loads a big-endian word without logging it.
pub fn (b &TestBus) peek16(addr u32) u16 {
	return (u16(b.mem[addr & address_mask]) << 8) | b.mem[(addr + 1) & address_mask]
}

fn (mut b TestBus) set(addr u32, data u8) {
	masked := addr & address_mask
	b.mem[masked] = data
	b.touched << masked
}

fn (mut b TestBus) record(write bool, bytes u8, addr u32, data u16) {
	if b.event_count == max_events {
		b.overflowed = true
		return
	}
	b.events[b.event_count] = BusEvent{write, bytes, addr & address_mask, data}
	b.event_count++
}

// read8 implements hwtypes.Bus.
pub fn (mut b TestBus) read8(addr u32) u8 {
	data := b.mem[addr & address_mask]
	b.record(false, 1, addr, data)
	return data
}

// read16 implements hwtypes.Bus.
pub fn (mut b TestBus) read16(addr u32) u16 {
	data := b.peek16(addr)
	b.record(false, 2, addr, data)
	return data
}

// read32 implements hwtypes.Bus; the 68000 core must never call it.
pub fn (mut b TestBus) read32(addr u32) u32 {
	b.long_access = true
	return (u32(b.peek16(addr)) << 16) | b.peek16(addr + 2)
}

// write8 implements hwtypes.Bus.
pub fn (mut b TestBus) write8(addr u32, val u8) {
	b.set(addr, val)
	b.record(true, 1, addr, val)
}

// write16 implements hwtypes.Bus.
pub fn (mut b TestBus) write16(addr u32, val u16) {
	b.poke16(addr, val)
	b.record(true, 2, addr, val)
}

// write32 implements hwtypes.Bus; the 68000 core must never call it.
pub fn (mut b TestBus) write32(addr u32, val u32) {
	b.long_access = true
	b.poke16(addr, u16(val >> 16))
	b.poke16(addr + 2, u16(val))
}
