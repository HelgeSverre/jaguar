module loader

// DRI/Alcyon executables. Two headers share the 0x601x family:
//
// Absolute (0x601B), 36 bytes:
//   0x02 text size   0x06 data size   0x0A bss size   0x0E symbol size
//   0x16 text base   0x1A relocation flag (non-zero: none)
//   0x1C data base   0x20 bss base    0x24 text, data, symbols
// Text and data are loaded at their own bases, BSS is cleared at its base,
// and execution starts at the text base.
//
// GEMDOS-style (0x601A without `JAGR`), 28 bytes:
//   0x02 text size   0x06 data size   0x0A bss size   0x0E symbol size
//   0x1A absolute flag (zero: a relocation table follows the symbols)
//   0x1C text, data, symbols, relocation table
// This header carries no address. It is supported only when the program needs
// no fixups (absolute flag set, or an empty table), in which case it runs
// wherever it is put: at `Options.load_addr`, else at the customary upload
// address 0x4000. Programs with fixups are refused as relocatable.

const abs_magic = u16(0x601B)
const abs_header_len = 0x24
const gemdos_header_len = 0x1C
const default_upload_addr = u32(0x4000)

// DriSizes are the four size fields both headers share.
struct DriSizes {
	text    u32
	data    u32
	bss     u32
	symbols u32
}

// read_dri_sizes reads the shared size fields and requires some text.
fn read_dri_sizes(image []u8) !DriSizes {
	sizes := DriSizes{
		text:    be32(image, 0x02, 'text size')!
		data:    be32(image, 0x06, 'data size')!
		bss:     be32(image, 0x0A, 'bss size')!
		symbols: be32(image, 0x0E, 'symbol size')!
	}
	if sizes.text == 0 {
		return fail(.bad_header, 'executable declares an empty text section')
	}
	return sizes
}

// parse_abs plans a 0x601B absolute executable.
fn parse_abs(image []u8, opts Options) !Draft {
	if !has_magic(image, abs_magic) {
		return fail(.bad_header, 'not a DRI ABS executable: expected 0x601b at offset 0')
	}
	reject_load_addr(opts, 'a DRI ABS executable')!
	span(image, 0, abs_header_len, 'DRI ABS header')!
	sizes := read_dri_sizes(image)!
	text_base := be32(image, 0x16, 'text base')!
	if be16(image, 0x1A, 'relocation flag')! == 0 {
		return fail(.unresolved_relocations,
			'DRI ABS relocation flag is clear; the file is relocatable, not absolute')
	}
	data_base := be32(image, 0x1C, 'data base')!
	bss_base := be32(image, 0x20, 'bss base')!
	mut d := Draft{
		kind:    .dri_abs
		variant: 'DRI ABS (0x601b)'
		entry:   text_base
	}
	d.segments << Segment{text_base, span(image, abs_header_len, sizes.text, 'text')!, 'text'}
	d.segments << Segment{data_base, span(image, u64(abs_header_len) + sizes.text, sizes.data,
		'data')!, 'data'}
	d.zero_fill << ZeroFill{bss_base, sizes.bss}
	return d
}

// parse_gemdos plans a relocation-free 0x601A program.
fn parse_gemdos(image []u8, opts Options) !Draft {
	if !has_magic(image, jagr_prefix) {
		return fail(.bad_header, 'not a GEMDOS-style executable: expected 0x601a at offset 0')
	}
	span(image, 0, gemdos_header_len, 'GEMDOS-style header')!
	sizes := read_dri_sizes(image)!
	text := span(image, gemdos_header_len, sizes.text, 'text')!
	data := span(image, u64(gemdos_header_len) + sizes.text, sizes.data, 'data')!
	check_no_fixups(image, sizes)!
	mut d := Draft{
		kind:    .dri_abs
		variant: 'GEMDOS-style (0x601a), relocation-free'
	}
	base := opts.load_addr or {
		d.notes << 'the header carries no load address and the program needs no fixups; placed at the customary upload address ${hex32(default_upload_addr)}'
		default_upload_addr
	}

	// Reject bases that cannot hold the image before 32-bit sums could wrap.
	total := u64(sizes.text) + sizes.data + sizes.bss
	if !is_loadable(base, total) {
		return fail(.bad_range, 'program of ${total} bytes does not fit at ${hex32(base)}')
	}
	d.entry = base
	d.segments << Segment{base, text, 'text'}
	d.segments << Segment{base + sizes.text, data, 'data'}
	d.zero_fill << ZeroFill{base + sizes.text + sizes.data, sizes.bss}
	return d
}

// check_no_fixups refuses a GEMDOS-style program whose relocation table has
// entries. The table starts with the offset of the first fixup; zero, or a
// missing table, means there are none.
fn check_no_fixups(image []u8, sizes DriSizes) ! {
	if be16(image, 0x1A, 'absolute flag')! != 0 {
		return
	}
	table := u64(gemdos_header_len) + sizes.text + sizes.data + sizes.symbols
	if table + 4 > u64(image.len) {
		return
	}
	if be32(image, table, 'relocation table')! != 0 {
		return fail(.unresolved_relocations,
			'GEMDOS-style program has a relocation table; relocatable programs are not supported')
	}
}
