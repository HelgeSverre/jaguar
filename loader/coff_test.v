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

fn text_section() fixtures.CoffSection {
	return fixtures.CoffSection{
		name:  '.text'
		addr:  0x4000
		data:  fixtures.nops(0x140)
		flags: fixtures.coff_text
	}
}

fn data_section() fixtures.CoffSection {
	return fixtures.CoffSection{
		name:  '.data'
		addr:  0x4140
		data:  fixtures.words([u16(0x0102), 0x0304, 0x0506])
		flags: fixtures.coff_data
	}
}

fn bss_section() fixtures.CoffSection {
	return fixtures.CoffSection{
		name:  '.bss'
		addr:  0x8000
		size:  0x200
		flags: fixtures.coff_bss
	}
}

fn executable() fixtures.Coff {
	return fixtures.Coff{
		sections: [text_section(), data_section(), bss_section()]
		entry:    0x4000
	}
}

fn test_coff_loads_each_section_at_its_address() {
	p := plan(executable().bytes(), Options{})!
	assert p.kind == .coff
	assert p.segments.len == 2
	assert p.segments[0].name == 'text'
	assert p.segments[0].addr == 0x4000
	assert p.segments[0].data == text_section().data
	assert p.segments[1].name == 'data'
	assert p.segments[1].addr == 0x4140
	assert p.segments[1].data == data_section().data
	assert p.zero_fill == [ZeroFill{0x8000, 0x200}]
	assert p.entry == 0x4000
	assert !p.ambiguous
}

fn test_coff_payload_offset_comes_from_the_section_table() {
	// One and five sections put the first payload byte at 0x58 and 0xf8,
	// never at the 0xa8 a three-section file happens to use.
	one := fixtures.Coff{
		sections: [text_section()]
		entry:    0x4000
	}
	assert plan(one.bytes(), Options{})!.segments[0].data == text_section().data
	extra := fixtures.CoffSection{
		name:  '.rodata'
		addr:  0x9000
		data:  fixtures.words([u16(0xCAFE)])
		flags: fixtures.coff_data
	}
	comment := fixtures.CoffSection{
		name:  '.note'
		addr:  0
		data:  fixtures.words([u16(0x4E4F)])
		flags: fixtures.coff_noload
	}
	five := fixtures.Coff{
		sections: [comment, text_section(), data_section(), bss_section(), extra]
		entry:    0x4002
	}
	p := plan(five.bytes(), Options{})!
	assert p.segments.map(it.name) == ['text', 'data', 'rodata']
	assert p.segments[0].data == text_section().data
	assert p.segments[2].addr == 0x9000
	assert p.entry == 0x4002
	assert p.notes.any(it.contains('skipped COFF section note'))
}

fn test_coff_in_cartridge_space_with_ram_bss() {
	c := fixtures.Coff{
		sections: [
			fixtures.CoffSection{
				...text_section()
				addr: 0x802000
			},
			fixtures.CoffSection{
				...bss_section()
				addr: 0x5000
			},
		]
		entry:    0x802000
	}
	p := plan(c.bytes(), Options{})!
	assert p.needs_cart_boot
	assert p.zero_fill[0].addr == 0x5000
}

fn test_coff_with_relocations_is_refused() {
	with_relocs := fixtures.Coff{
		sections: [
			fixtures.CoffSection{
				...text_section()
				relocations: 3
			},
		]
		entry:    0x4000
	}
	assert refusal(with_relocs.bytes(), Options{}) == .unresolved_relocations
	object_file := fixtures.Coff{
		...executable()
		flags: 0x0000
	}
	assert refusal(object_file.bytes(), Options{}) == .unresolved_relocations
}

fn test_coff_optional_header_is_required() {
	missing := fixtures.Coff{
		...executable()
		optional_len: 0
	}
	short := fixtures.Coff{
		...executable()
		optional_len: 20
	}
	wrong_kind := fixtures.Coff{
		...executable()
		aout_magic: 0x010B
	}
	assert refusal(missing.bytes(), Options{}) == .bad_header
	assert refusal(short.bytes(), Options{}) == .bad_header
	assert refusal(wrong_kind.bytes(), Options{}) == .unsupported_variant
}

fn test_coff_truncations_are_errors() {
	image := executable().bytes()
	for cut in 2 .. image.len {
		plan(image[..cut], Options{}) or {
			assert code_of(err) == .truncated
			continue
		}
		assert false, 'cut at ${cut} gave a plan'
	}
	// File header, optional header, section table, section data.
	for cut in [19, 20, 47, 48, 48 + 39, 48 + 119, image.len - 1] {
		assert refusal(image[..cut], Options{}) == .truncated
	}
}

fn test_coff_section_table_inconsistencies() {
	no_sections := fixtures.Coff{
		entry: 0x4000
	}
	assert refusal(no_sections.bytes(), Options{}) == .bad_header
	only_bss := fixtures.Coff{
		sections: [bss_section()]
		entry:    0x8000
	}
	assert refusal(only_bss.bytes(), Options{}) == .bad_header
	no_offset := fixtures.Coff{
		sections: [
			fixtures.CoffSection{
				...text_section()
				no_offset: true
			},
		]
		entry:    0x4000
	}
	assert refusal(no_offset.bytes(), Options{}) == .bad_header
	mut huge := executable().bytes()
	fixtures.put32(mut huge, 48 + 0x10, 0xFFFFFFFF)
	assert refusal(huge, Options{}) == .truncated
}

fn test_coff_overlaps_ranges_and_entry() {
	overlapping := fixtures.Coff{
		sections: [
			text_section(),
			fixtures.CoffSection{
				...data_section()
				addr: 0x4100
			},
		]
		entry:    0x4000
	}
	bss_over_text := fixtures.Coff{
		sections: [
			text_section(),
			fixtures.CoffSection{
				...bss_section()
				addr: 0x3F00
			},
		]
		entry:    0x4000
	}
	in_mmio := fixtures.Coff{
		sections: [
			fixtures.CoffSection{
				...text_section()
				addr: 0xF02000
			},
		]
		entry:    0xF02000
	}
	assert refusal(overlapping.bytes(), Options{}) == .overlap
	assert refusal(bss_over_text.bytes(), Options{}) == .overlap
	assert refusal(in_mmio.bytes(), Options{}) == .bad_range
	odd := fixtures.Coff{
		...executable()
		entry: 0x4001
	}
	outside := fixtures.Coff{
		...executable()
		entry: 0x8000
	}
	assert refusal(odd.bytes(), Options{}) == .odd_entry
	assert refusal(outside.bytes(), Options{}) == .bad_range
	assert refusal(executable().bytes(), Options{ load_addr: 0x5000 }) == .bad_option
	assert plan(executable().bytes(), Options{ entry: 0x4010 })!.entry == 0x4010
}
