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

fn cart_space_abs() fixtures.Abs {
	return fixtures.Abs{
		text:      fixtures.nops(0x50C)
		data:      fixtures.words([u16(0x1111), 0x2222, 0x3333])
		bss:       0x428
		symbols:   0x30
		text_base: 0x802000
		data_base: 0x80250C
		bss_base:  0x4000
	}
}

fn test_abs_loads_text_and_data_and_clears_bss() {
	a := cart_space_abs()
	p := plan(a.bytes(), Options{})!
	assert p.kind == .dri_abs
	assert p.variant == 'DRI ABS (0x601b)'
	assert p.segments.len == 2
	assert p.segments[0].name == 'text'
	assert p.segments[0].addr == 0x802000
	assert p.segments[0].data == a.text
	assert p.segments[1].name == 'data'
	assert p.segments[1].addr == 0x80250C
	assert p.segments[1].data == a.data
	assert p.zero_fill == [ZeroFill{0x4000, 0x428}]
	assert p.entry == 0x802000
	assert p.needs_cart_boot
	assert !p.ambiguous
}

fn test_abs_in_ram_with_empty_data_and_bss() {
	a := fixtures.Abs{
		text:      fixtures.nops(0x80)
		text_base: 0x4000
		data_base: 0x4080
		bss_base:  0x4080
	}
	p := plan(a.bytes(), Options{})!
	assert p.segments.len == 1
	assert p.zero_fill.len == 0
	assert p.entry == 0x4000
	assert !p.needs_cart_boot
}

fn test_abs_truncations_are_errors() {
	image := cart_space_abs().bytes()
	for cut in 2 .. 0x24 + 0x50C + 6 {
		plan(image[..cut], Options{}) or {
			assert code_of(err) in [.truncated, .bad_header]
			continue
		}
		assert false, 'cut at ${cut} gave a plan'
	}
	assert refusal(image[..0x23], Options{}) == .truncated
	assert refusal(image[..0x24], Options{}) == .truncated
	assert refusal(image[..0x24 + 0x50C + 5], Options{}) == .truncated
	// Missing symbols do not matter: nothing loads from them.
	assert plan(image[..0x24 + 0x50C + 6], Options{})!.segments.len == 2
}

fn test_abs_sizes_that_would_wrap_are_truncated() {
	mut image := cart_space_abs().bytes()
	fixtures.put32(mut image, 0x02, 0xFFFFFFF0)
	fixtures.put32(mut image, 0x06, 0x00000020)
	assert refusal(image, Options{}) == .truncated
}

fn test_abs_overlaps_and_bad_ranges() {
	base := cart_space_abs()
	data_in_text := fixtures.Abs{
		...base
		data_base: 0x802100
	}
	bss_in_text := fixtures.Abs{
		...base
		bss_base: 0x802000
	}
	bss_in_mmio := fixtures.Abs{
		...base
		bss_base: 0xF00000
	}
	text_past_ram := fixtures.Abs{
		...base
		text_base: 0x1FFE00
	}
	assert refusal(data_in_text.bytes(), Options{}) == .overlap
	assert refusal(bss_in_text.bytes(), Options{}) == .overlap
	assert refusal(bss_in_mmio.bytes(), Options{}) == .bad_range
	assert refusal(text_past_ram.bytes(), Options{}) == .bad_range
}

fn test_abs_header_rejections() {
	base := cart_space_abs()
	relocatable := fixtures.Abs{
		...base
		reloc_flag: 0
	}
	odd := fixtures.Abs{
		...base
		text_base: 0x802001
		data_base: 0x802510
	}
	no_text := fixtures.Abs{
		...base
		text: []u8{}
	}
	assert refusal(relocatable.bytes(), Options{}) == .unresolved_relocations
	assert refusal(odd.bytes(), Options{}) == .odd_entry
	assert refusal(no_text.bytes(), Options{}) == .bad_header
	assert refusal(base.bytes(), Options{ load_addr: 0x4000 }) == .bad_option
	assert refusal(fixtures.nops(0x100), Options{ format: .dri_abs }) == .bad_header
}

fn gemdos_program() fixtures.Gemdos {
	return fixtures.Gemdos{
		text:    fixtures.nops(0xEBE)
		data:    fixtures.words([u16(0xAAAA), 0xBBBB])
		bss:     0x100
		symbols: 0x40
	}
}

fn test_gemdos_program_without_fixups_loads_at_upload_address() {
	g := gemdos_program()
	p := plan(g.bytes(), Options{})!
	assert p.kind == .dri_abs
	assert p.variant == 'GEMDOS-style (0x601a), relocation-free'
	assert p.segments.len == 2
	assert p.segments[0].addr == 0x4000
	assert p.segments[0].data == g.text
	assert p.segments[1].addr == 0x4000 + 0xEBE
	assert p.segments[1].data == g.data
	assert p.zero_fill == [ZeroFill{0x4000 + 0xEBE + 4, 0x100}]
	assert p.entry == 0x4000
	assert p.notes.len == 1
}

fn test_gemdos_program_honours_load_address() {
	p := plan(gemdos_program().bytes(), Options{ load_addr: 0x20000 })!
	assert p.segments[0].addr == 0x20000
	assert p.entry == 0x20000
	assert p.notes.len == 0
	assert refusal(gemdos_program().bytes(), Options{ load_addr: 0x1FFF00 }) == .bad_range
	assert refusal(gemdos_program().bytes(), Options{ load_addr: 0xFFFFFF00 }) == .bad_range
}

fn test_gemdos_program_with_fixups_is_relocatable() {
	with_fixups := fixtures.Gemdos{
		...gemdos_program()
		first_fixup: 2
	}
	assert refusal(with_fixups.bytes(), Options{}) == .unresolved_relocations
	// The absolute flag says there is no table, whatever follows the symbols.
	absolute := fixtures.Gemdos{
		...gemdos_program()
		abs_flag:    1
		first_fixup: 2
	}
	assert plan(absolute.bytes(), Options{})!.entry == 0x4000
	no_table := fixtures.Gemdos{
		...gemdos_program()
		has_table: false
	}
	assert plan(no_table.bytes(), Options{})!.entry == 0x4000
}

fn test_gemdos_truncations_are_errors() {
	image := gemdos_program().bytes()
	for cut in 2 .. 0x1C + 0xEBE + 4 {
		plan(image[..cut], Options{}) or { continue }
		assert false, 'cut at ${cut} gave a plan'
	}
	assert refusal(image[..0x1B], Options{}) == .truncated
	assert refusal(image[..0x1C + 0xEBE + 3], Options{}) == .truncated
}
