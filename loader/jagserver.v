module loader

// Jaguar Server upload images: the word 0x601A, `JAGR` at 0x1C, then
//   0x20 u16 variant   0x22 u32 load address   0x26 u32 length
// Type 2: payload at 0x2A, entered at the load address.
// Type 3: u32 entry at 0x2A, payload at 0x2E.
// Reading a type-2 file as type 3 would eat its first four code bytes as an
// entry address, so the variant decides and unknown variants are refused.
//
// The length field is unreliable in real files: many leave it zero, and the
// rest declare a few bytes less than the payload that follows (4 short for
// type 3, 10 short for type 2), although headerless builds of the same
// programs contain those bytes. The rule, applied identically to both types:
//   - zero: load everything after the header;
//   - longer than the file: `truncated`;
//   - up to 16 bytes shorter than the file: load everything after the header;
//   - shorter by more: load the declared length, ignore the rest.
// Every case but an exact match is recorded in the plan's notes.

const jagr_prefix = u16(0x601A)
const jagr_tag_offset = 0x1C
const jagr_variant_offset = 0x20
const jagr_load_offset = 0x22
const jagr_length_offset = 0x26
const jagr_type2_payload = 0x2A
const jagr_type3_payload = 0x2E
const jagr_max_undeclared_tail = 16

// has_jagr_tag reports whether `JAGR` sits at 0x1C.
fn has_jagr_tag(image []u8) bool {
	return image.len >= jagr_tag_offset + 4
		&& image[jagr_tag_offset..jagr_tag_offset + 4] == 'JAGR'.bytes()
}

// parse_jagserver plans a type-2 or type-3 Jaguar Server image.
fn parse_jagserver(image []u8, opts Options) !Draft {
	if !has_magic(image, jagr_prefix) || !has_jagr_tag(image) {
		return fail(.bad_header,
			'not a Jaguar Server image: expected 0x601a at 0 and `JAGR` at 0x1c')
	}
	reject_load_addr(opts, 'a Jaguar Server image')!
	variant := be16(image, jagr_variant_offset, 'JAGR variant')!
	load := be32(image, jagr_load_offset, 'JAGR load address')!
	declared := be32(image, jagr_length_offset, 'JAGR length')!
	mut d := Draft{
		kind:    .jaguar_server
		variant: 'JAGR type ${variant}'
		entry:   load
	}
	mut payload_at := jagr_type2_payload
	match variant {
		2 {}
		3 {
			d.entry = be32(image, jagr_type2_payload, 'JAGR type 3 entry')!
			payload_at = jagr_type3_payload
		}
		else {
			return fail(.unsupported_variant,
				'JAGR variant ${variant} is not specified; only types 2 and 3 are supported')
		}
	}

	payload := jagr_payload(image, payload_at, declared, mut d.notes)!
	d.segments << Segment{load, payload, 'payload'}
	return d
}

// jagr_payload applies the length rule documented at the top of this file.
fn jagr_payload(image []u8, at int, declared u32, mut notes []string) ![]u8 {
	rest := image[at..]
	if rest.len == 0 {
		return fail(.truncated, 'JAGR image ends at its header; no payload at 0x${at:x}')
	}
	if declared == 0 {
		notes << 'JAGR length field is zero; loaded all ${rest.len} payload bytes'
		return rest
	}
	if u64(declared) > u64(rest.len) {
		return fail(.truncated,
			'JAGR header declares ${declared} payload bytes, file has ${rest.len}')
	}
	tail := rest.len - int(declared)
	if tail == 0 {
		return rest
	}
	if tail <= jagr_max_undeclared_tail {
		notes << 'JAGR length field is ${tail} bytes short of the payload; loaded all ${rest.len} bytes'
		return rest
	}
	notes << 'ignored ${tail} bytes after the ${declared} declared payload bytes'
	return rest[..int(declared)]
}
