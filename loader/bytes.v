module loader

// Checked big-endian readers. Every offset and length is widened to u64
// before it is added, so a hostile header cannot wrap a sum into range.

// span returns `len` bytes at `off`, or a `truncated` error naming `what`.
fn span(b []u8, off u64, len u64, what string) ![]u8 {
	if off > u64(b.len) || len > u64(b.len) - off {
		return fail(.truncated,
			'${what}: needs ${len} bytes at offset 0x${off:x}, file has ${b.len}')
	}
	return b[int(off)..int(off + len)]
}

// be16 reads a big-endian u16 at `off`.
fn be16(b []u8, off u64, what string) !u16 {
	s := span(b, off, 2, what)!
	return u16(s[0]) << 8 | u16(s[1])
}

// be32 reads a big-endian u32 at `off`.
fn be32(b []u8, off u64, what string) !u32 {
	s := span(b, off, 4, what)!
	return word32(s, 0)
}

// word16 reads a big-endian u16 the caller has already bounds-checked.
@[inline]
fn word16(b []u8, off int) u16 {
	return u16(b[off]) << 8 | u16(b[off + 1])
}

// word32 reads a big-endian u32 the caller has already bounds-checked.
@[inline]
fn word32(b []u8, off int) u32 {
	return u32(b[off]) << 24 | u32(b[off + 1]) << 16 | u32(b[off + 2]) << 8 | u32(b[off + 3])
}

// has_magic reports whether the image starts with the big-endian word `magic`.
fn has_magic(b []u8, magic u16) bool {
	return b.len >= 2 && word16(b, 0) == magic
}

// all_bytes_are reports whether every byte of `b` equals `value`.
fn all_bytes_are(b []u8, value u8) bool {
	for x in b {
		if x != value {
			return false
		}
	}
	return true
}

// byte_swapped returns a copy with every byte pair exchanged; an odd final
// byte stays in place.
fn byte_swapped(b []u8) []u8 {
	mut out := b.clone()
	for i := 0; i + 1 < out.len; i += 2 {
		out[i], out[i + 1] = out[i + 1], out[i]
	}
	return out
}

// hex32 formats a guest address or size the way the notes and errors show it.
fn hex32(v u32) string {
	return '0x${v:06x}'
}
