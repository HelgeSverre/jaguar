module loader

import loader.fixtures

fn code_of(err IError) ErrorCode {
	if err is LoadError {
		return err.code
	}
	panic('not a LoadError: ${err}')
}

fn refusal(image []u8, opts Options) ErrorCode {
	plan(image, opts) or { return code_of(err) }
	panic('expected a LoadError, got a plan')
}

// A payload whose first long would be a valid-looking entry if misread.
fn payload() []u8 {
	mut code := fixtures.words([u16(0x0000), 0x5008])
	code << fixtures.nops(0x40)
	return code
}

fn test_type2_payload_starts_at_0x2a_and_enters_at_load_address() {
	code := payload()
	p := plan(fixtures.jagr_type2(0x5000, u32(code.len), code), Options{})!
	assert p.kind == .jaguar_server
	assert p.variant == 'JAGR type 2'
	assert p.segments.len == 1
	assert p.segments[0].addr == 0x5000
	assert p.segments[0].data == code
	assert p.entry == 0x5000
	assert !p.needs_cart_boot
	assert !p.ambiguous
	assert p.notes.len == 0
}

fn test_type3_reads_entry_then_payload_at_0x2e() {
	code := payload()
	p := plan(fixtures.jagr_type3(0x4FE4, u32(code.len), 0x5000, code), Options{})!
	assert p.variant == 'JAGR type 3'
	assert p.segments[0].addr == 0x4FE4
	assert p.segments[0].data == code
	assert p.entry == 0x5000
}

fn test_type2_is_not_read_as_type3() {
	// Read as type 3, the first four payload bytes (0x00005008) would
	// become the entry and vanish from the loaded code.
	code := payload()
	p := plan(fixtures.jagr_type2(0x5000, u32(code.len), code), Options{})!
	assert p.entry == 0x5000
	assert p.segments[0].data[..4] == [u8(0x00), 0x00, 0x50, 0x08]
	assert p.segments[0].data.len == code.len
}

fn test_unknown_variants_are_unsupported() {
	for variant in [u16(0), 1, 4, 10, 0xFFFF] {
		mut image := fixtures.jagr_header(variant, 0x5000, 0)
		image << payload()
		assert refusal(image, Options{}) == .unsupported_variant
	}
}

fn test_zero_length_field_loads_everything() {
	code := payload()
	p := plan(fixtures.jagr_type3(0x4000, 0, 0x4000, code), Options{})!
	assert p.segments[0].data == code
	assert p.notes.any(it.contains('length field is zero'))
}

fn test_slightly_short_length_field_loads_everything() {
	code := payload()
	for short in [u32(4), 10, 16] {
		p := plan(fixtures.jagr_type2(0x5000, u32(code.len) - short, code), Options{})!
		assert p.segments[0].data == code
		assert p.notes.any(it.contains('${short} bytes short'))
	}
}

fn test_long_tail_beyond_declared_length_is_ignored() {
	code := payload()
	p := plan(fixtures.jagr_type2(0x5000, u32(code.len) - 17, code), Options{})!
	assert p.segments[0].data == code[..code.len - 17]
	assert p.notes.any(it.contains('ignored 17 bytes'))
}

fn test_declared_length_beyond_file_is_truncated() {
	code := payload()
	assert refusal(fixtures.jagr_type2(0x5000, u32(code.len) + 1, code), Options{}) == .truncated
	assert refusal(fixtures.jagr_type3(0x5000, 0xFFFFFFFF, 0x5000, code), Options{}) == .truncated
}

fn test_every_header_truncation_is_an_error() {
	code := payload()
	type2 := fixtures.jagr_type2(0x5000, 0, code)
	type3 := fixtures.jagr_type3(0x5000, 0, 0x5000, code)
	for cut in 2 .. 0x2A + 1 {
		plan(type2[..cut], Options{}) or { continue }
		assert false, 'type 2 cut at ${cut} gave a plan'
	}
	for cut in 2 .. 0x2E + 1 {
		plan(type3[..cut], Options{}) or { continue }
		assert false, 'type 3 cut at ${cut} gave a plan'
	}
	// Header boundaries: tag only, variant only, no length, no payload.
	for cut in [0x20, 0x22, 0x26, 0x2A] {
		assert refusal(type2[..cut], Options{}) == .truncated
	}
	assert refusal(type3[..0x2C], Options{}) == .truncated
	assert refusal(type3[..0x2E], Options{}) == .truncated
}

fn test_destinations_outside_ram_are_refused() {
	code := payload()
	assert refusal(fixtures.jagr_type2(0x00F00000, 0, code), Options{}) == .bad_range
	assert refusal(fixtures.jagr_type2(0x001FFFF0, 0, code), Options{}) == .bad_range
	assert refusal(fixtures.jagr_type2(0x00300000, 0, code), Options{}) == .bad_range
	assert refusal(fixtures.jagr_type2(0xFFFFFFF0, 0, code), Options{}) == .bad_range
}

fn test_entry_must_be_even_and_inside_the_payload() {
	code := payload()
	assert refusal(fixtures.jagr_type3(0x5000, 0, 0x5001, code), Options{}) == .odd_entry
	assert refusal(fixtures.jagr_type2(0x5001, 0, code), Options{}) == .odd_entry
	assert refusal(fixtures.jagr_type3(0x5000, 0, 0x6000, code), Options{}) == .bad_range
	assert refusal(fixtures.jagr_type3(0x5000, 0, u32(0x5000 + code.len), code), Options{}) == .bad_range
}

fn test_overrides_on_a_jaguar_server_image() {
	code := payload()
	image := fixtures.jagr_type2(0x5000, 0, code)
	assert plan(image, Options{ entry: 0x5004 })!.entry == 0x5004
	assert refusal(image, Options{ load_addr: 0x6000 }) == .bad_option
	assert refusal(fixtures.nops(0x100), Options{ format: .jaguar_server }) == .bad_header
}
