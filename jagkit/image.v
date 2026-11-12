module jagkit

import os
import tom

// jag_image wraps a program in a Jaguar Server header (`JAGR`, type 3): the
// payload is loaded into RAM at `load` and started at `entry`.
pub fn jag_image(load u32, entry u32, payload []u8) []u8 {
	mut image := []u8{len: 0x2e, cap: 0x2e + payload.len}
	image[0] = 0x60
	image[1] = 0x1a
	for i, c in 'JAGR' {
		image[0x1c + i] = c
	}
	image[0x21] = 3
	put32(mut image, 0x22, load)
	put32(mut image, 0x26, u32(payload.len))
	put32(mut image, 0x2a, entry)
	image << payload
	return image
}

// write_jag writes a program as a `.jag` file.
pub fn write_jag(path string, load u32, entry u32, payload []u8) ! {
	os.write_file_array(path, jag_image(load, entry, payload))!
}

fn put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 {
		bytes[at + i] = u8(value >> (24 - 8 * i))
	}
}

// big_endian16 serialises words the way the Jaguar reads them.
pub fn big_endian16(words []u16) []u8 {
	mut bytes := []u8{cap: words.len * 2}
	for w in words {
		bytes << u8(w >> 8)
		bytes << u8(w)
	}
	return bytes
}

// big_endian32 serialises longs the way the Jaguar reads them.
pub fn big_endian32(longs []u32) []u8 {
	mut bytes := []u8{cap: longs.len * 4}
	for v in longs {
		bytes << u8(v >> 24)
		bytes << u8(v >> 16)
		bytes << u8(v >> 8)
		bytes << u8(v)
	}
	return bytes
}

// cry returns the CRY pixel nearest to an RGB colour, each part 0..255. CRY
// keeps the brightness in its low byte and one of 256 hues in its high
// byte, so scaling the low byte fades a colour without changing it.
pub fn cry(r int, g int, b int) u16 {
	mut luma := if r > g { r } else { g }
	if b > luma {
		luma = b
	}
	if luma <= 0 {
		return 0
	}
	mut best := 0
	mut best_error := max_int
	for chroma in 0 .. 256 {
		full := tom.cry_to_rgb(u32(chroma << 8) | 0xff)
		dr := int(full >> 16) - r * 255 / luma
		dg := int((full >> 8) & 0xff) - g * 255 / luma
		db := int(full & 0xff) - b * 255 / luma
		distance := dr * dr + dg * dg + db * db
		if distance < best_error {
			best = chroma
			best_error = distance
		}
	}
	return u16(best << 8) | u16(if luma > 255 {
		255
	} else {
		luma
	})
}
