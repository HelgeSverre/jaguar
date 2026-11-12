// Module loader turns the bytes of a Jaguar cartridge or executable image
// into a validated LoadPlan: what to copy where, what to clear, and where the
// 68000 starts. It is pure: it never reads files and never touches a machine.
//
// Detection is by content only, strongest structure first:
//   1. cartridge header at 0x400/0x404 (also behind a byte swap or a
//      prepended 0x200-byte copier header),
//   2. executable containers by magic: DRI ABS (0x601B), COFF (0x0150),
//      Jaguar Server (0x601A + `JAGR`), GEMDOS-style 0x601A programs,
//   3. a cartridge whose first 0x2000 bytes were erased,
//   4. headerless code, placed by the scoring heuristic in raw.v.
// Explicit `Options` always win over detection.
module loader

import crypto.sha256

// ImageKind names the container or convention an image was loaded as.
pub enum ImageKind {
	cartridge     // mapped at 0x800000, header at 0x400
	jaguar_server // 0x601A + `JAGR` upload image
	dri_abs       // DRI/Alcyon absolute executable (0x601B, or 0x601A GEMDOS-style)
	coff          // Jaguar COFF executable (0x0150)
	alpine_rom    // headerless payload for 0x802000 (no 0x2000-byte cartridge header)
	raw_binary    // headerless code at a RAM (or explicit) base
}

// Segment is one run of bytes to copy into guest memory.
pub struct Segment {
pub:
	addr u32    // guest load address
	data []u8   // bytes to copy; aliases the input image unless it was normalized
	name string // e.g. 'cart', 'text', 'data'
}

// ZeroFill is a guest range to clear before start (BSS).
pub struct ZeroFill {
pub:
	addr u32 // first guest address to clear
	len  u32 // number of bytes to clear
}

// Candidate is one interpretation the heuristics weighed, with its evidence.
pub struct Candidate {
pub:
	kind      ImageKind // kind the image would get under this interpretation
	variant   string    // variant label, as in LoadPlan.variant
	load_addr u32       // guest base the image would load at
	entry     u32       // entry the image would start at
	score     int       // evidence score; higher is better, 0 is no evidence
	reason    string    // the evidence behind the score
}

// LoadPlan is a fully validated description of how to load one image.
pub struct LoadPlan {
pub:
	kind            ImageKind
	variant         string      // e.g. 'JAGR type 2', 'headerless', 'erased header'
	segments        []Segment   // non-empty, non-overlapping, inside RAM or the cartridge window
	zero_fill       []ZeroFill  // BSS ranges, disjoint from the segments
	entry           u32         // even 68000 start address
	needs_cart_boot bool        // true when any segment is mapped in the cartridge window (0x800000..); a real cartridge is normally entered through its header at 0x404
	original_hash   string      // sha256 hex of the input bytes
	normalized_hash string      // sha256 hex after normalization (== original_hash when none)
	normalizations  []string    // each applied normalization with its reason
	ambiguous       bool        // true when detection relied on a heuristic choice among candidates
	candidates      []Candidate // every candidate considered for heuristic kinds, best first
	notes           []string    // tolerated oddities and decisions worth showing the user
}

// Options are the explicit overrides; each one wins over detection.
pub struct Options {
pub:
	format    ?ImageKind // parse as this kind instead of detecting
	load_addr ?u32       // load base, for kinds whose header carries none (raw_binary, alpine_rom, GEMDOS-style dri_abs)
	entry     ?u32       // start address, for every kind
}

const ram_end = u32(0x200000)
const cart_base = u32(0x800000)
const cart_end = u32(0xE00000)

// Draft is a parser's unvalidated result; `finish` turns it into a LoadPlan.
struct Draft {
mut:
	kind           ImageKind
	variant        string
	segments       []Segment
	zero_fill      []ZeroFill
	entry          u32
	normalized     []u8 // the normalized image, empty when nothing was normalized
	normalizations []string
	ambiguous      bool
	candidates     []Candidate
	notes          []string
}

// plan detects what `image` is and returns a validated LoadPlan, or a
// LoadError. It is deterministic: the same bytes and options always give the
// same plan, and nothing but the bytes and options is consulted.
pub fn plan(image []u8, opts Options) !LoadPlan {
	if image.len < 2 {
		return fail(.too_small, 'image has ${image.len} bytes')
	}
	draft := detect(image, opts)!
	return finish(image, draft, opts)
}

// detect picks the parser: the forced one, else the strongest structure present.
fn detect(image []u8, opts Options) !Draft {
	if kind := opts.format {
		return parse_forced(kind, image, opts)
	}
	if all_bytes_are(image, image[0]) {
		return fail(.blank_image,
			'all ${image.len} bytes are 0x${image[0]:02x}; this is an erased or failed dump')
	}
	if layout := find_cart_layout(image) {
		return plan_cartridge(image, layout, opts)
	}
	if has_magic(image, abs_magic) {
		return parse_abs(image, opts)
	}
	if has_magic(image, coff_magic) {
		return parse_coff(image, opts)
	}
	if has_magic(image, jagr_prefix) {
		if has_jagr_tag(image) {
			return parse_jagserver(image, opts)
		}
		return parse_gemdos(image, opts)
	}
	if has_erased_cart_header(image) {
		return plan_erased_cartridge(image, opts)
	}
	return plan_raw(image, opts, none)
}

// parse_forced runs the parser the caller asked for, whatever the bytes suggest.
fn parse_forced(kind ImageKind, image []u8, opts Options) !Draft {
	match kind {
		.cartridge {
			return plan_forced_cartridge(image, opts)
		}
		.jaguar_server {
			return parse_jagserver(image, opts)
		}
		.dri_abs {
			if has_magic(image, jagr_prefix) {
				return parse_gemdos(image, opts)
			}
			return parse_abs(image, opts)
		}
		.coff {
			return parse_coff(image, opts)
		}
		.alpine_rom, .raw_binary {
			return plan_raw(image, opts, kind)
		}
	}
}

// reject_load_addr refuses a load-address override for kinds whose header
// fixes every address; silently ignoring it would hide a user mistake.
fn reject_load_addr(opts Options, what string) ! {
	if addr := opts.load_addr {
		return fail(.bad_option,
			'load address ${hex32(addr)} given, but ${what} fixes its own addresses; use format raw_binary to force a raw load')
	}
}

// finish applies the entry override, validates the draft and seals the plan.
fn finish(image []u8, d Draft, opts Options) !LoadPlan {
	mut notes := d.notes.clone()
	mut entry := d.entry
	if forced := opts.entry {
		if forced != d.entry {
			notes << 'entry ${hex32(forced)} given explicitly (detected ${hex32(d.entry)})'
		}
		entry = forced
	}
	segments := d.segments.filter(it.data.len > 0)
	zero_fill := d.zero_fill.filter(it.len > 0)
	if segments.len == 0 {
		return fail(.bad_header, 'image declares no bytes to load')
	}
	check_regions(segments, zero_fill)!
	check_entry(d.kind, entry, segments)!
	original := sha256.sum(image).hex()
	return LoadPlan{
		kind:            d.kind
		variant:         d.variant
		segments:        segments
		zero_fill:       zero_fill
		entry:           entry
		needs_cart_boot: segments.any(it.addr >= cart_base)
		original_hash:   original
		normalized_hash: if d.normalized.len > 0 { sha256.sum(d.normalized).hex() } else { original }
		normalizations:  d.normalizations
		ambiguous:       d.ambiguous
		candidates:      d.candidates
		notes:           notes
	}
}

// Region is a half-open guest range used for destination and overlap checks.
struct Region {
	start u64
	end   u64
	label string
}

// in_window reports whether [addr, addr+len) lies inside [lo, hi).
fn in_window(addr u32, len u64, lo u32, hi u32) bool {
	return addr >= lo && u64(addr) + len <= u64(hi)
}

// is_loadable reports whether a range lies wholly in main RAM or wholly in the
// cartridge window. Nothing else, MMIO in particular, is a legal destination.
fn is_loadable(addr u32, len u64) bool {
	return in_window(addr, len, 0, ram_end) || in_window(addr, len, cart_base, cart_end)
}

// check_regions verifies every destination range and that none overlap.
fn check_regions(segments []Segment, zero_fill []ZeroFill) ! {
	mut regions := []Region{cap: segments.len + zero_fill.len}
	for s in segments {
		regions << Region{u64(s.addr), u64(s.addr) + u64(s.data.len), 'segment ${s.name}'}
	}
	for z in zero_fill {
		regions << Region{u64(z.addr), u64(z.addr) + u64(z.len), 'zero fill'}
	}
	for r in regions {
		if !is_loadable(u32(r.start), r.end - r.start) {
			return fail(.bad_range,
				'${r.label} 0x${r.start:06x}..0x${r.end:06x} is not inside RAM (0x000000..0x1fffff) or the cartridge window (0x800000..0xdfffff)')
		}
	}
	regions.sort(a.start < b.start)
	for i in 1 .. regions.len {
		a, b := regions[i - 1], regions[i]
		if b.start < a.end {
			return fail(.overlap,
				'${a.label} 0x${a.start:06x}..0x${a.end:06x} overlaps ${b.label} 0x${b.start:06x}..0x${b.end:06x}')
		}
	}
}

// check_entry verifies the start address: even, and inside a loaded segment.
// A cartridge may start anywhere in its window (the board may mirror it).
fn check_entry(kind ImageKind, entry u32, segments []Segment) ! {
	if entry & 1 != 0 {
		return fail(.odd_entry, 'entry ${hex32(entry)} is odd; the 68000 cannot start there')
	}
	if kind == .cartridge && in_window(entry, 2, cart_base, cart_end) {
		return
	}
	for s in segments {
		if entry >= s.addr && u64(entry) + 2 <= u64(s.addr) + u64(s.data.len) {
			return
		}
	}
	return fail(.bad_range, 'entry ${hex32(entry)} is not inside any loaded segment')
}

// describe renders the plan as a multi-line summary for logs and the CLI.
pub fn (p &LoadPlan) describe() string {
	mut out := []string{}
	out << 'kind: ${p.kind}' + if p.variant != '' { ' (${p.variant})' } else { '' }
	out << 'entry: ${hex32(p.entry)}'
	out << 'cart boot: ${yes_no(p.needs_cart_boot)}'
	out << 'ambiguous: ${yes_no(p.ambiguous)}'
	out << 'segments:'
	for s in p.segments {
		out << '  ${s.name}: ${hex32(s.addr)}..${hex32(s.addr + u32(s.data.len) - 1)} (${s.data.len} bytes)'
	}
	if p.zero_fill.len > 0 {
		out << 'zero fill:'
		for z in p.zero_fill {
			out << '  ${hex32(z.addr)}..${hex32(z.addr + z.len - 1)} (${z.len} bytes)'
		}
	}
	out << 'sha256: ${p.original_hash}'
	if p.normalizations.len > 0 {
		out << 'sha256 normalized: ${p.normalized_hash}'
		out << 'normalizations:'
		out << p.normalizations.map('  ${it}')
	}
	if p.candidates.len > 0 {
		out << 'candidates:'
		for c in p.candidates {
			out << '  ${c.kind} at ${hex32(c.load_addr)}, entry ${hex32(c.entry)}, score ${c.score}: ${c.reason}'
		}
	}
	if p.notes.len > 0 {
		out << 'notes:'
		out << p.notes.map('  ${it}')
	}
	return out.join('\n')
}

fn yes_no(b bool) string {
	return if b { 'yes' } else { 'no' }
}
