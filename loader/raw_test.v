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

fn test_heuristic_finds_every_candidate_base() {
	// With 0x3000 bytes of padding the 0x4000/0x5000 and 0x800000/0x802000
	// windows overlap, so containment alone cannot decide; without it they
	// do not. Both must resolve.
	for pad in [0, 0x3000] {
		for base in raw_candidate_bases {
			image := fixtures.program(base, pad)
			p := plan(image, Options{})!
			assert p.segments.len == 1
			assert p.segments[0].addr == base, 'pad ${pad}'
			assert p.segments[0].data == image
			assert p.entry == base
			assert p.ambiguous
			assert p.candidates[0].load_addr == base
			assert p.candidates[0].score > 0
			assert p.variant == 'headerless'
		}
	}
}

fn test_cartridge_space_winner_is_an_alpine_rom() {
	alpine := plan(fixtures.program(0x802000, 0), Options{})!
	assert alpine.kind == .alpine_rom
	assert alpine.needs_cart_boot
	ram := plan(fixtures.program(0x4000, 0), Options{})!
	assert ram.kind == .raw_binary
	assert !ram.needs_cart_boot
	cart_base_image := plan(fixtures.program(0x800000, 0), Options{})!
	assert cart_base_image.kind == .raw_binary
	assert cart_base_image.needs_cart_boot
}

fn test_candidates_are_complete_and_best_first() {
	p := plan(fixtures.program(0x5000, 0x3000), Options{})!
	assert p.candidates.len == raw_candidate_bases.len
	for i in 1 .. p.candidates.len {
		assert p.candidates[i - 1].score >= p.candidates[i].score
	}
	for c in p.candidates {
		assert c.entry == c.load_addr
		assert c.reason != ''
		assert c.kind == if c.load_addr == 0x802000 {
			ImageKind.alpine_rom
		} else {
			ImageKind.raw_binary
		}
	}
	// Two calls on subroutine starts, one data reference.
	assert p.candidates[0].score == 16 * 2 + 4 * 2 + 1
	assert p.notes.any(it.contains('chosen by scoring'))
	assert !p.notes.any(it.contains('not clearly ahead'))
}

fn test_no_evidence_falls_back_to_upload_address() {
	p := plan(fixtures.nops(0x400), Options{})!
	assert p.kind == .raw_binary
	assert p.segments[0].addr == 0x4000
	assert p.entry == 0x4000
	assert p.ambiguous
	assert p.candidates.all(it.score == 0)
	assert p.notes.any(it.contains('fell back'))
}

fn test_weak_evidence_is_reported_as_unclear() {
	// One LEA into a window both 0x4000 and 0x5000 contain.
	mut image := fixtures.words([u16(0x41F9), 0x0000, 0x5010])
	image << fixtures.nops(0x2000)
	p := plan(image, Options{})!
	assert p.segments[0].addr == 0x4000 // a tie resolves in list order
	assert p.notes.any(it.contains('not clearly ahead'))
}

fn test_clear_win_margin() {
	assert is_clear_win(8, 6)
	assert !is_clear_win(8, 7)
	assert !is_clear_win(7, 0)
	assert is_clear_win(100, 75)
	assert !is_clear_win(100, 76)
}

fn test_self_reading_stub_pins_cartridge_space() {
	// MOVEQ #0,D1; MOVEA.L $802054,A0; MOVEA.L $802048,A1; MOVE.L $80204C,D0
	// then an embedded program linked at 0x4000, as copy stubs carry.
	mut image := fixtures.words([u16(0x7200), 0x2079, 0x0080, 0x2054, 0x2279, 0x0080, 0x2048, 0x2039,
		0x0080, 0x204C])
	image << fixtures.nops(0x60 - image.len)
	image << fixtures.program(0x4000 - 0x60, 0x800)
	p := plan(image, Options{})!
	assert p.kind == .alpine_rom
	assert p.segments[0].addr == 0x802000
	assert p.candidates[0].reason.contains('stub')
}

fn test_implausible_first_word_is_noted() {
	mut image := fixtures.program(0x4000, 0)
	image[0] = 0xA0
	p := plan(image, Options{})!
	assert p.notes.any(it.contains('not a plausible 68000 instruction'))
}

fn test_explicit_load_address_wins_and_is_not_ambiguous() {
	image := fixtures.program(0x4000, 0)
	p := plan(image, Options{ load_addr: 0x6000 })!
	assert p.kind == .raw_binary
	assert p.segments[0].addr == 0x6000
	assert p.entry == 0x6000
	assert !p.ambiguous
	assert p.candidates.len == 0
	q := plan(image, Options{ load_addr: 0x6000, entry: 0x6020 })!
	assert q.entry == 0x6020
	assert plan(image, Options{ load_addr: 0x802000 })!.kind == .alpine_rom
}

fn test_explicit_addresses_are_validated() {
	image := fixtures.program(0x4000, 0)
	assert refusal(image, Options{ load_addr: 0xF00000 }) == .bad_range
	assert refusal(image, Options{ load_addr: 0x1FFFF0 }) == .bad_range
	assert refusal(image, Options{ load_addr: 0xFFFFFFFE }) == .bad_range
	assert refusal(image, Options{ load_addr: 0x4001 }) == .odd_entry
	assert refusal(image, Options{ entry: 0x4021 }) == .odd_entry
	assert refusal(image, Options{ entry: 0x9000 }) == .bad_range
	assert refusal(image, Options{ entry: u32(0x4000 + image.len) }) == .bad_range
}

fn test_forced_format_beats_detection() {
	cart := fixtures.cartridge(0x3000, 0x04, 0x802000)
	raw := plan(cart, Options{ format: .raw_binary, load_addr: 0x10000 })!
	assert raw.kind == .raw_binary
	assert raw.segments[0].addr == 0x10000
	assert !raw.needs_cart_boot
	alpine := plan(fixtures.program(0x4000, 0), Options{ format: .alpine_rom })!
	assert alpine.kind == .alpine_rom
	assert alpine.segments[0].addr == 0x802000
	assert !alpine.ambiguous
	// A forced raw load still scores, and keeps its kind at 0x802000.
	forced := plan(fixtures.program(0x802000, 0), Options{ format: .raw_binary })!
	assert forced.kind == .raw_binary
	assert forced.segments[0].addr == 0x802000
	assert forced.ambiguous
	jagr := fixtures.jagr_type2(0x5000, 0, fixtures.nops(0x20))
	as_raw := plan(jagr, Options{ format: .raw_binary, load_addr: 0x4000 })!
	assert as_raw.segments[0].data == jagr
}

fn test_images_too_large_for_any_base() {
	// Fits cartridge space only, with nothing to say it belongs there.
	assert refusal(fixtures.nops(0x300000), Options{}) == .ambiguous_needs_override
	assert refusal(fixtures.nops(0x600002), Options{}) == .too_large
	assert plan(fixtures.nops(0x300000), Options{ load_addr: 0x800000 })!.needs_cart_boot
}

fn test_scan_reads_each_operand_form() {
	image := fixtures.words([
		u16(0x4EB9),
		0x0000,
		0x4000, // JSR
		0x4EF9,
		0x0000,
		0x4002, // JMP
		0x4DF9,
		0x0000,
		0x4004, // LEA ...,A6
		0x4879,
		0x0000,
		0x4006, // PEA
		0x2039,
		0x0000,
		0x4008, // MOVE.L abs,D0
		0x33C1,
		0x0000,
		0x400A, // MOVE.W D1,abs
		0x23FC,
		0x1111,
		0x2222,
		0x0000,
		0x400C, // MOVE.L #,abs
		0x33FC,
		0x1111,
		0x0000,
		0x400E, // MOVE.W #,abs
		0x4E71,
	])
	refs := scan_abs_refs(image)
	assert refs.map(it.target) == [u32(0x4000), 0x4002, 0x4004, 0x4006, 0x4008, 0x400A, 0x400C,
		0x400E]
	assert refs.map(it.kind) == [RefKind.call, .call, .address, .address, .load, .store, .store,
		.store]
}

fn test_scan_never_reads_past_the_image() {
	for tail in [u16(0x4EB9), 0x23FC, 0x33FC] {
		for extra in 0 .. 4 {
			mut image := fixtures.words([tail])
			image << []u8{len: extra, init: 0x40}
			assert scan_abs_refs(image).len == 0
			plan(image, Options{})!
		}
	}
}
