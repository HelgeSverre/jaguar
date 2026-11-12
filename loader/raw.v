module loader

// Headerless images: raw 68000 code with nothing that says where it loads.
//
// With an explicit `Options.load_addr` there is nothing to guess. Otherwise
// the load base is chosen from a fixed list by a deterministic score, and the
// plan is marked ambiguous and carries every candidate with its evidence.
//
// Evidence comes from absolute-long operands in the first 64 KiB, read at
// every even offset: JSR/JMP, LEA/PEA, MOVE from abs.l, MOVE to abs.l. An
// operand counts for a base when its target is even and inside
// [base, base + image length). Per candidate base:
//
//   subs   JSR/JMP targets that land on the image start or directly after an
//          RTS/RTE/RTR, i.e. on a subroutine start. Under a wrong base this
//          is a coincidence (about 1 call in 100), under the right one it is
//          the rule, so it separates overlapping bases such as 0x4000/0x5000.
//   calls  all JSR/JMP targets inside the image. Code is in the image;
//          variables often are not, so calls outweigh data references.
//   data   LEA/PEA/MOVE operands inside the image.
//   tables LEA/PEA targets whose first long is a Jaguar I/O address
//          (0xF00000..0xF1FFFF): the {destination, ...} descriptor of a
//          start-up that uploads GPU/DSP code. A tie-breaker only.
//
//   score = 16*subs + 4*calls + data + 2*tables
//
// One structural rule outranks the score: a start-up stub that loads two or
// more longs from its own first 0x100 bytes through absolute addresses within
// its first 0x40 bytes pins the base those addresses imply. Such stubs copy an
// embedded program elsewhere, so the program's own references would
// otherwise vote for the copy destination.
//
// The best score wins; equal scores resolve in list order. The choice is
// called clear when the score is at least 8 and leads the runner-up by at
// least a quarter of itself; otherwise the best candidate is still returned
// and the notes say so. With no evidence at all the image goes to the
// customary upload address 0x4000. A winning 0x802000 makes the image an
// `alpine_rom` (cartridge-space payload without the boot area).

// Candidate load bases, in tie-break order: the two customary upload
// addresses, two bases larger homebrew is linked at, then cartridge space.
const raw_candidate_bases = [u32(0x4000), 0x5000, 0x10000, 0x20000, 0x802000, 0x800000]!
const alpine_base = u32(0x802000)
const raw_scan_len = 0x10000
const raw_stub_code_len = 0x40
const raw_stub_header_len = 0x100
const raw_stub_min_loads = 2
const raw_stub_pin_score = 1_000_000
const raw_clear_min_score = 8

// RefKind is what an instruction does with its absolute-long operand.
enum RefKind {
	call    // JSR, JMP
	address // LEA, PEA
	load    // MOVE abs.l,Dn / MOVEA abs.l,An
	store   // MOVE Dn/An/#imm,abs.l
}

// AbsRef is one absolute-long operand found in the scan window.
struct AbsRef {
	kind   RefKind
	at     int // image offset of the opcode
	target u32
}

// Operand says where an opcode keeps its absolute-long operand.
struct Operand {
	kind   RefKind
	offset int // from the opcode word
}

// abs_operand recognizes the opcodes that carry an absolute-long operand.
fn abs_operand(op u16) ?Operand {
	if op == 0x4EB9 || op == 0x4EF9 {
		return Operand{.call, 2}
	}
	if op & 0xF1FF == 0x41F9 || op == 0x4879 {
		return Operand{.address, 2}
	}
	if op & 0xF1FF in [u16(0x1039), 0x2039, 0x2079, 0x3039, 0x3079] {
		return Operand{.load, 2}
	}
	if op & 0xFFF8 in [u16(0x13C0), 0x23C0, 0x23C8, 0x33C0] {
		return Operand{.store, 2}
	}
	if op == 0x23FC {
		return Operand{.store, 6}
	}
	if op == 0x13FC || op == 0x33FC {
		return Operand{.store, 4}
	}
	return none
}

// scan_abs_refs collects every absolute-long operand in the scan window.
fn scan_abs_refs(image []u8) []AbsRef {
	limit := if image.len < raw_scan_len { image.len } else { raw_scan_len }
	mut refs := []AbsRef{}
	for at := 0; at + 2 <= limit; at += 2 {
		operand := abs_operand(word16(image, at)) or { continue }
		if at + operand.offset + 4 <= limit {
			refs << AbsRef{operand.kind, at, word32(image, at + operand.offset)}
		}
	}
	return refs
}

// Evidence counts what supports one candidate base.
struct Evidence {
mut:
	subs       int
	calls      int
	data       int
	tables     int
	stub_loads int
}

// weigh counts the references that fit `image` loaded at `base`.
fn weigh(image []u8, base u32, refs []AbsRef) Evidence {
	mut e := Evidence{}
	for r in refs {
		if r.target & 1 != 0 || !in_window(r.target, 2, base, u32(u64(base) + u64(image.len))) {
			continue
		}
		rel := int(r.target - base)
		if r.kind == .call {
			e.calls++
			if rel == 0 || is_return(word16(image, rel - 2)) {
				e.subs++
			}
			continue
		}
		e.data++
		if r.kind == .address && rel + 4 <= image.len && is_io_address(word32(image, rel)) {
			e.tables++
		}
		if r.kind == .load && r.at < raw_stub_code_len && rel < raw_stub_header_len {
			e.stub_loads++
		}
	}
	return e
}

fn is_return(op u16) bool {
	return op == 0x4E75 || op == 0x4E73 || op == 0x4E77
}

fn is_io_address(v u32) bool {
	return v >= 0xF00000 && v <= 0xF1FFFF
}

// is_stub reports whether the start-up reads its own header (the pin rule).
fn (e Evidence) is_stub() bool {
	return e.stub_loads >= raw_stub_min_loads
}

fn (e Evidence) score() int {
	pin := if e.is_stub() { raw_stub_pin_score } else { 0 }
	return 16 * e.subs + 4 * e.calls + e.data + 2 * e.tables + pin
}

fn (e Evidence) reason() string {
	if e.calls == 0 && e.data == 0 {
		return 'no absolute reference lands in the image'
	}
	mut parts := ['${e.calls} calls into the image (${e.subs} on subroutine starts)',
		'${e.data} data references']
	if e.tables > 0 {
		parts << '${e.tables} hardware tables'
	}
	if e.is_stub() {
		parts << 'start-up stub reads its own header at this base'
	}
	return parts.join(', ')
}

// is_plausible_opcode rejects words no program starts with: erased or zero
// memory, the unimplemented line-A/line-F opcodes, and ILLEGAL.
fn is_plausible_opcode(op u16) bool {
	return op != 0x0000 && op != 0x4AFC && op >> 12 != 0xA && op >> 12 != 0xF
}

// raw_kind is the kind a headerless image gets at `base`.
fn raw_kind(base u32) ImageKind {
	return if base == alpine_base { ImageKind.alpine_rom } else { ImageKind.raw_binary }
}

// plan_raw plans a headerless image: at the explicit base, at 0x802000 for a
// forced Alpine ROM, else at the best-scoring candidate base.
fn plan_raw(image []u8, opts Options, forced ?ImageKind) !Draft {
	mut d := Draft{
		variant: 'headerless'
	}
	mut base := alpine_base
	wanted := forced or { ImageKind.raw_binary }
	if addr := opts.load_addr {
		base = addr
	} else if wanted != .alpine_rom {
		base = choose_raw_base(image, mut d)!
	}
	d.kind = forced or { raw_kind(base) }
	d.entry = base
	d.segments << Segment{base, image, 'raw'}
	if !is_plausible_opcode(word16(image, 0)) {
		d.notes << 'the first word 0x${word16(image, 0):04x} is not a plausible 68000 instruction'
	}
	return d
}

// choose_raw_base scores the candidate bases, records them in the draft and
// returns the winner.
fn choose_raw_base(image []u8, mut d Draft) !u32 {
	d.candidates = rank_raw_candidates(image)
	d.ambiguous = true
	if d.candidates.len == 0 {
		return fail(.too_large,
			'headerless image of ${image.len} bytes fits neither main RAM nor the cartridge window at any candidate base')
	}
	best := d.candidates[0]
	if best.score == 0 {
		if best.load_addr != default_upload_addr {
			return fail(.ambiguous_needs_override,
				'nothing identifies this ${image.len}-byte image and it does not fit at ${hex32(default_upload_addr)}; give format and load address explicitly')
		}
		d.notes << 'no absolute reference identifies a load base; fell back to the customary upload address ${hex32(default_upload_addr)}'
		return best.load_addr
	}
	d.notes << 'load base ${hex32(best.load_addr)} chosen by scoring absolute references: ${best.reason}'
	if d.candidates.len > 1 {
		second := d.candidates[1]
		if !is_clear_win(best.score, second.score) {
			d.notes << 'the choice is not clearly ahead (score ${best.score}, runner-up ${hex32(second.load_addr)} with ${second.score}); give a load address explicitly if it is wrong'
		}
	}
	return best.load_addr
}

// is_clear_win is the margin rule: enough evidence, and a lead of at least a
// quarter of the winning score.
fn is_clear_win(best int, second int) bool {
	return best >= raw_clear_min_score && (best - second) * 4 >= best
}

// rank_raw_candidates scores every base the image fits at, best first; equal
// scores keep list order.
fn rank_raw_candidates(image []u8) []Candidate {
	refs := scan_abs_refs(image)
	mut ranked := []Candidate{}
	for base in raw_candidate_bases {
		if !is_loadable(base, u64(image.len)) {
			continue
		}
		e := weigh(image, base, refs)
		c := Candidate{
			kind:      raw_kind(base)
			variant:   'headerless'
			load_addr: base
			entry:     base
			score:     e.score()
			reason:    e.reason()
		}
		mut at := ranked.len
		for at > 0 && ranked[at - 1].score < c.score {
			at--
		}
		ranked.insert(at, c)
	}
	return ranked
}
