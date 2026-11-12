// Module fixtures builds synthetic Jaguar images for the loader tests: every
// header is assembled field by field, so no test depends on a real ROM.
// Nothing outside the tests imports it.
module fixtures

// put16 stores a big-endian u16 at `at`.
pub fn put16(mut b []u8, at int, v u16) {
	b[at] = u8(v >> 8)
	b[at + 1] = u8(v)
}

// put32 stores a big-endian u32 at `at`.
pub fn put32(mut b []u8, at int, v u32) {
	put16(mut b, at, u16(v >> 16))
	put16(mut b, at + 2, u16(v))
}

// words encodes 16-bit words big-endian.
pub fn words(ws []u16) []u8 {
	mut b := []u8{len: ws.len * 2}
	for i, w in ws {
		put16(mut b, i * 2, w)
	}
	return b
}

// nops returns `len` bytes of 68000 NOPs: valid code with no absolute operand.
pub fn nops(len int) []u8 {
	return []u8{len: len, init: if index & 1 == 0 {
		u8(0x4E)
	} else {
		u8(0x71)
	}}
}

// cartridge returns a `len`-byte cartridge image: NOPs with the given memory
// configuration byte four times at 0x400 and `entry` at 0x404.
pub fn cartridge(len int, config u8, entry u32) []u8 {
	mut b := nops(len)
	for i in 0 .. 4 {
		b[0x400 + i] = config
	}
	put32(mut b, 0x404, entry)
	return b
}

// jagr_header returns the first 0x2A bytes of a Jaguar Server image.
pub fn jagr_header(variant u16, load u32, declared u32) []u8 {
	mut b := []u8{len: 0x2A}
	put16(mut b, 0, 0x601A)
	b[0x1C] = `J`
	b[0x1D] = `A`
	b[0x1E] = `G`
	b[0x1F] = `R`
	put16(mut b, 0x20, variant)
	put32(mut b, 0x22, load)
	put32(mut b, 0x26, declared)
	return b
}

// jagr_type2 returns a type-2 image: header, then the payload at 0x2A.
pub fn jagr_type2(load u32, declared u32, payload []u8) []u8 {
	mut b := jagr_header(2, load, declared)
	b << payload
	return b
}

// jagr_type3 returns a type-3 image: header, entry at 0x2A, payload at 0x2E.
pub fn jagr_type3(load u32, declared u32, entry u32, payload []u8) []u8 {
	mut b := jagr_header(3, load, declared)
	b << [u8(0), 0, 0, 0]
	put32(mut b, 0x2A, entry)
	b << payload
	return b
}

// Abs describes a DRI ABS (0x601B) executable.
pub struct Abs {
pub:
	text       []u8
	data       []u8
	bss        u32
	symbols    int
	text_base  u32
	data_base  u32
	bss_base   u32
	reloc_flag u16 = 0xFFFF
}

// bytes assembles the 36-byte header, text, data and symbol bytes.
pub fn (a Abs) bytes() []u8 {
	mut b := []u8{len: 0x24}
	put16(mut b, 0, 0x601B)
	put32(mut b, 0x02, u32(a.text.len))
	put32(mut b, 0x06, u32(a.data.len))
	put32(mut b, 0x0A, a.bss)
	put32(mut b, 0x0E, u32(a.symbols))
	put32(mut b, 0x16, a.text_base)
	put16(mut b, 0x1A, a.reloc_flag)
	put32(mut b, 0x1C, a.data_base)
	put32(mut b, 0x20, a.bss_base)
	b << a.text
	b << a.data
	b << []u8{len: a.symbols, init: 0x53}
	return b
}

// Gemdos describes a GEMDOS-style (0x601A, no `JAGR`) executable.
pub struct Gemdos {
pub:
	text        []u8
	data        []u8
	bss         u32
	symbols     int
	abs_flag    u16
	has_table   bool = true
	first_fixup u32
}

// bytes assembles the 28-byte header, text, data, symbols and fixup table.
pub fn (g Gemdos) bytes() []u8 {
	mut b := []u8{len: 0x1C}
	put16(mut b, 0, 0x601A)
	put32(mut b, 0x02, u32(g.text.len))
	put32(mut b, 0x06, u32(g.data.len))
	put32(mut b, 0x0A, g.bss)
	put32(mut b, 0x0E, u32(g.symbols))
	put16(mut b, 0x1A, g.abs_flag)
	b << g.text
	b << g.data
	b << []u8{len: g.symbols, init: 0x53}
	if g.has_table {
		b << [u8(0), 0, 0, 0]
		put32(mut b, b.len - 4, g.first_fixup)
	}
	return b
}

pub const coff_text = u32(0x20)
pub const coff_data = u32(0x40)
pub const coff_bss = u32(0x80)
pub const coff_noload = u32(0x02)

// CoffSection describes one COFF section. BSS takes its size from `size`;
// every other section from `data`.
pub struct CoffSection {
pub:
	name        string
	addr        u32
	data        []u8
	size        u32
	flags       u32
	relocations u16
	no_offset   bool // write a zero file offset even though the section has data
}

// Coff describes a COFF executable.
pub struct Coff {
pub:
	sections     []CoffSection
	entry        u32
	flags        u16 = 0x0003
	optional_len int = 28
	aout_magic   u16 = 0x0107
}

// bytes assembles file header, optional header, section table and section data.
pub fn (c Coff) bytes() []u8 {
	table := 20 + c.optional_len
	mut b := []u8{len: table + 40 * c.sections.len}
	put16(mut b, 0, 0x0150)
	put16(mut b, 2, u16(c.sections.len))
	put16(mut b, 0x10, u16(c.optional_len))
	put16(mut b, 0x12, c.flags)
	if c.optional_len >= 28 {
		put16(mut b, 22, c.aout_magic)
		put32(mut b, 20 + 0x10, c.entry)
	}
	for i, s in c.sections {
		at := table + 40 * i
		for j, ch in s.name.bytes() {
			b[at + j] = ch
		}
		put32(mut b, at + 0x08, s.addr)
		put32(mut b, at + 0x0C, s.addr)
		put32(mut b, at + 0x10, if s.data.len > 0 { u32(s.data.len) } else { s.size })
		put32(mut b, at + 0x14, if s.no_offset { u32(0) } else { u32(b.len) })
		put16(mut b, at + 0x20, s.relocations)
		put32(mut b, at + 0x24, s.flags)
		b << s.data
	}
	return b
}

// program returns a small 68000 program linked at `base`: a start-up that
// writes a hardware register, calls two subroutines by absolute address and
// takes the address of a data table, followed by `pad` bytes of NOPs.
//
//   00  MOVE.L #$00070007,$F0210C
//   0A  JSR    sub1
//   10  JSR    sub2
//   16  LEA    table,A0
//   1C  BRA.S  *
//   1E  RTS
//   20  sub1:  NOP / RTS
//   24  sub2:  NOP / RTS
//   28  table: two longs
pub fn program(base u32, pad int) []u8 {
	mut b := words([u16(0x23FC), 0x0007, 0x0007, 0x00F0, 0x210C, 0x4EB9, 0, 0, 0x4EB9, 0, 0, 0x41F9,
		0, 0, 0x60FE, 0x4E75, 0x4E71, 0x4E75, 0x4E71, 0x4E75, 0x1234, 0x5678, 0x9ABC, 0xDEF0])
	put32(mut b, 0x0C, base + 0x20)
	put32(mut b, 0x12, base + 0x24)
	put32(mut b, 0x18, base + 0x28)
	b << nops(pad)
	return b
}

// Rng is a small deterministic xorshift generator for the robustness tests.
pub struct Rng {
mut:
	state u32 = 0x9E3779B9
}

// next returns the next pseudo-random u32.
pub fn (mut r Rng) next() u32 {
	r.state ^= r.state << 13
	r.state ^= r.state >> 17
	r.state ^= r.state << 5
	return r.state
}

// below returns a pseudo-random int in 0 .. n.
pub fn (mut r Rng) below(n int) int {
	return int(r.next() % u32(n))
}

// bytes returns `len` pseudo-random bytes.
pub fn (mut r Rng) bytes(len int) []u8 {
	mut b := []u8{len: len}
	for i in 0 .. len {
		b[i] = u8(r.next() >> 11)
	}
	return b
}
