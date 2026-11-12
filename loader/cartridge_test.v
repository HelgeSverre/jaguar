module loader

import loader.fixtures

const cart_len = 0x2000 + 0x123 // deliberately not a power of two

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

fn test_plain_cartridge_maps_at_cart_base() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	p := plan(image, Options{})!
	assert p.kind == .cartridge
	assert p.variant == 'memory config 0x04'
	assert p.segments.len == 1
	assert p.segments[0].addr == 0x800000
	assert p.segments[0].name == 'cart'
	assert p.segments[0].data == image
	assert p.zero_fill.len == 0
	assert p.entry == 0x802000
	assert p.needs_cart_boot
	assert !p.ambiguous
	assert p.candidates.len == 0
	assert p.normalizations.len == 0
	assert p.original_hash.len == 64
	assert p.normalized_hash == p.original_hash
}

fn test_cartridge_accepts_other_memory_configs_and_entries() {
	for config in [u8(0x00), 0x02, 0x04, 0x06] {
		p := plan(fixtures.cartridge(cart_len, config, 0x802010), Options{})!
		assert p.kind == .cartridge
		assert p.entry == 0x802010
	}
}

fn test_cartridge_entry_beyond_image_is_noted() {
	p := plan(fixtures.cartridge(cart_len, 0x04, 0x900000), Options{})!
	assert p.kind == .cartridge
	assert p.notes.any(it.contains('mirroring'))
}

fn test_invalid_cartridge_headers_are_not_cartridges() {
	odd_entry := fixtures.cartridge(cart_len, 0x04, 0x802001)
	outside := fixtures.cartridge(cart_len, 0x04, 0x00F00000)
	bad_config := fixtures.cartridge(cart_len, 0x41, 0x802000)
	too_short := fixtures.cartridge(0x1FFE, 0x04, 0x802000)
	for image in [odd_entry, outside, bad_config, too_short] {
		p := plan(image, Options{})!
		assert p.kind != .cartridge
	}
}

fn test_byte_swapped_cartridge_is_normalized() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	p := plan(byte_swapped(image), Options{})!
	reference := plan(image, Options{})!
	assert p.kind == .cartridge
	assert p.entry == 0x802000
	assert p.segments[0].data == image
	assert p.normalizations.len == 1
	assert p.normalizations[0].starts_with('byte-swapped')
	assert p.normalized_hash == reference.original_hash
	assert p.original_hash != p.normalized_hash
}

fn test_prepended_header_is_stripped() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	mut headered := []u8{len: 0x200}
	headered << image
	p := plan(headered, Options{})!
	assert p.kind == .cartridge
	assert p.segments[0].data == image
	assert p.normalizations.len == 1
	assert p.normalizations[0].starts_with('stripped 0x000200-byte')
	assert p.normalized_hash == plan(image, Options{})!.original_hash
}

fn test_prepended_header_and_byte_swap_combine() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	mut headered := []u8{len: 0x200}
	headered << byte_swapped(image)
	p := plan(headered, Options{})!
	assert p.segments[0].data == image
	assert p.normalizations.len == 2
}

fn test_blank_images_are_refused() {
	assert refusal([]u8{len: 0x200000, init: 0xFF}, Options{}) == .blank_image
	assert refusal([]u8{len: 0x4000}, Options{}) == .blank_image
}

fn test_empty_and_one_byte_images_are_too_small() {
	assert refusal([]u8{}, Options{}) == .too_small
	assert refusal([u8(0x60)], Options{}) == .too_small
}

fn test_cartridge_size_limit_is_six_mebibytes() {
	full := fixtures.cartridge(0x600000, 0x04, 0x802000)
	assert plan(full, Options{})!.segments[0].data.len == 0x600000
	assert refusal(fixtures.cartridge(0x600002, 0x04, 0x802000), Options{}) == .too_large
}

fn test_erased_header_cartridge_starts_at_conventional_entry() {
	mut image := fixtures.nops(0x4000)
	for i in 0 .. 0x2000 {
		image[i] = 0xFF
	}
	p := plan(image, Options{})!
	assert p.kind == .cartridge
	assert p.variant == 'erased header'
	assert p.entry == 0x802000
	assert p.segments[0].addr == 0x800000
	assert p.notes.len == 2
}

fn test_cartridge_rejects_a_load_address() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	assert refusal(image, Options{ load_addr: 0x4000 }) == .bad_option
}

fn test_cartridge_entry_override_is_validated() {
	image := fixtures.cartridge(cart_len, 0x04, 0x802000)
	assert plan(image, Options{ entry: 0x802004 })!.entry == 0x802004
	assert refusal(image, Options{ entry: 0x802005 }) == .odd_entry
	assert refusal(image, Options{ entry: 0x4000 }) == .bad_range
}

fn test_forced_cartridge_without_header_needs_an_entry() {
	image := fixtures.nops(0x3000)
	assert refusal(image, Options{ format: .cartridge }) == .bad_header
	p := plan(image, Options{ format: .cartridge, entry: 0x800000 })!
	assert p.kind == .cartridge
	assert p.entry == 0x800000
	assert p.segments[0].addr == 0x800000
}
