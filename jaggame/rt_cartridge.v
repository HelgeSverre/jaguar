module jaggame

import jagkit { abs, imm, inc, lbl }

// A game as a cartridge image. A `.jag` file is loaded into RAM by a tool; a
// cartridge is read at $800000 as it stands. The cartridge image here is the
// boot area of a cartridge (8 KB: the memory configuration byte four times
// at $400, the start address at $404) followed at $802000 by a few
// instructions that copy the program into RAM at its load address and jump
// into it, then the program itself. The program is the same bytes as in the
// `.jag` file, so everything that works in one works in the other.
//
// What this does not do: a retail console checks a signature in the
// cartridge's boot area before it runs a cartridge, and this image carries
// none. The image starts in the emulator and in anything that does not make
// the check (a development cartridge, a console with the check bypassed). It
// has not been run on hardware.

// cartridge_entry is where a cartridge's code starts.
const cartridge_entry = u32(0x802000)

// cartridge builds the cartridge image of a game image: the length is the next
// power of two of at least 128 KB.
pub fn (img &Image) cartridge() ![]u8 {
	entry := img.symbols['rt.start'] or {
		return error('cartridge: the image has no `rt.start`; it is not a game image')
	}
	longs := (img.payload.len + 3) / 4
	if longs > 65536 {
		return error('cartridge: the program is ${img.payload.len} bytes; the copy loop holds 256 KB')
	}
	mut m := jagkit.new_m68k(cartridge_entry)
	m.move_to_sr(imm(0x2700))
	m.lea(lbl('cart.payload'), a0)
	m.lea(abs(load_address), a1)
	m.move(.w, imm(longs - 1), d0)
	m.label('cart.copy')
	m.move(.l, inc(a0), inc(a1))
	m.dbra(d0, 'cart.copy')
	m.jmp(abs(entry))
	m.align(4)
	m.label('cart.payload')
	m.bytes(img.payload)
	code := m.assemble() or { return error('jaggame compiler bug: ${err.msg()}') }

	mut size := 0x20000
	for size < 0x2000 + code.len {
		size *= 2
	}
	mut rom := []u8{len: size, init: 0xff}
	for k in 0 .. 4 {
		rom[0x400 + k] = 0x04
		rom[0x404 + k] = u8(cartridge_entry >> u32(24 - 8 * k))
	}
	for k, b in code {
		rom[0x2000 + k] = b
	}
	return rom
}
