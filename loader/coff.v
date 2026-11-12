module loader

// Jaguar COFF executables (big-endian, magic 0x0150).
//
// File header, 20 bytes:
//   0x00 u16 magic      0x02 u16 section count   0x08 u32 symbol table offset
//   0x0C u32 symbols    0x10 u16 optional header size   0x12 u16 flags
// Optional (a.out) header, 28 bytes, magic 0x0107 in its first long:
//   +0x04 text size  +0x08 data size  +0x0C bss size  +0x10 entry
// Section headers, 40 bytes each, directly after the optional header:
//   +0x00 name[8]  +0x08 u32 physical address  +0x10 u32 size
//   +0x14 u32 file offset  +0x20 u16 relocation count  +0x24 u32 flags
//
// Every non-empty section is placed by its own header: BSS becomes a zero
// fill, anything else loadable is copied from its file offset to its
// physical address. No payload offset is assumed. Object files (not marked
// executable, or with relocation entries) and files without the optional
// header are refused.

const coff_magic = u16(0x0150)
const coff_file_header_len = 20
const coff_optional_header_len = 28
const coff_section_header_len = 40
const coff_aout_magic = u16(0x0107)
const coff_flag_executable = u16(0x0002)
const coff_section_bss = u32(0x0080)
// Dummy, no-load, copy, comment, overlay and library sections occupy no memory.
const coff_section_not_loaded = u32(0x0001 | 0x0002 | 0x0010 | 0x0200 | 0x0400 | 0x0800)

// CoffSection is the part of a section header the loader uses.
struct CoffSection {
	name        string
	addr        u32
	size        u32
	file_offset u32
	relocations u16
	flags       u32
}

// parse_coff plans a COFF executable from its section table.
fn parse_coff(image []u8, opts Options) !Draft {
	if !has_magic(image, coff_magic) {
		return fail(.bad_header, 'not a COFF executable: expected 0x0150 at offset 0')
	}
	reject_load_addr(opts, 'a COFF executable')!
	span(image, 0, coff_file_header_len, 'COFF file header')!
	section_count := be16(image, 0x02, 'section count')!
	optional_len := be16(image, 0x10, 'optional header size')!
	flags := be16(image, 0x12, 'file flags')!
	if flags & coff_flag_executable == 0 {
		return fail(.unresolved_relocations,
			'COFF file is not marked executable (flags 0x${flags:04x}); it is an object file')
	}
	mut d := Draft{
		kind:    .coff
		variant: 'a.out optional header'
		entry:   read_coff_entry(image, optional_len)!
	}
	table := u64(coff_file_header_len) + optional_len
	if section_count == 0 {
		return fail(.bad_header, 'COFF file has no sections')
	}
	for i in 0 .. int(section_count) {
		section := read_coff_section(image, table + u64(i) * coff_section_header_len, i)!
		add_coff_section(mut d, image, section)!
	}
	return d
}

// read_coff_entry validates the optional header and returns its entry field.
fn read_coff_entry(image []u8, optional_len u16) !u32 {
	if optional_len < coff_optional_header_len {
		return fail(.bad_header,
			'COFF optional header has ${optional_len} bytes, an executable needs ${coff_optional_header_len}; without it there is no entry')
	}
	at := u64(coff_file_header_len)
	span(image, at, optional_len, 'COFF optional header')!
	// The magic is 0x0107 in either half of the first long, depending on
	// whether the linker wrote a version stamp before or after it.
	if be16(image, at, 'a.out magic')! != coff_aout_magic
		&& be16(image, at + 2, 'a.out magic')! != coff_aout_magic {
		return fail(.unsupported_variant,
			'COFF optional header is not the a.out kind (magic 0x0107)')
	}
	return be32(image, at + 0x10, 'COFF entry')
}

// read_coff_section reads the section header at `at`.
fn read_coff_section(image []u8, at u64, index int) !CoffSection {
	header := span(image, at, coff_section_header_len, 'COFF section header ${index}')!
	return CoffSection{
		name:        coff_section_name(header[..8], index)
		addr:        word32(header, 0x08)
		size:        word32(header, 0x10)
		file_offset: word32(header, 0x14)
		relocations: word16(header, 0x20)
		flags:       word32(header, 0x24)
	}
}

// coff_section_name strips the NUL padding and a leading dot; a name that is
// not plain ASCII falls back to the section's index.
fn coff_section_name(raw []u8, index int) string {
	mut name := []u8{}
	for c in raw {
		if c == 0 {
			break
		}
		if c < 0x21 || c > 0x7E {
			return 'section ${index}'
		}
		name << c
	}
	text := name.bytestr().trim_left('.')
	return if text == '' { 'section ${index}' } else { text }
}

// add_coff_section turns one section into a segment, a zero fill, or a note.
fn add_coff_section(mut d Draft, image []u8, s CoffSection) ! {
	if s.relocations != 0 {
		return fail(.unresolved_relocations,
			'COFF section ${s.name} has ${s.relocations} unresolved relocations')
	}
	if s.size == 0 {
		return
	}
	if s.flags & coff_section_not_loaded != 0 {
		d.notes << 'skipped COFF section ${s.name} (flags 0x${s.flags:x}): it occupies no memory'
		return
	}
	if s.flags & coff_section_bss != 0 {
		d.zero_fill << ZeroFill{s.addr, s.size}
		return
	}
	if s.file_offset == 0 {
		return fail(.bad_header, 'COFF section ${s.name} has ${s.size} bytes but no file offset')
	}
	d.segments << Segment{s.addr, span(image, s.file_offset, s.size, 'COFF section ${s.name}')!, s.name}
}
