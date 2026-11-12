module jagkit

// Size is the operand size of a 68000 instruction.
pub enum Size {
	b
	w
	l
}

// Cc is the condition of a 68000 branch.
pub enum Cc {
	hi = 2
	ls
	cc
	cs
	ne
	eq
	vc
	vs
	pl
	mi
	ge
	lt
	gt
	le
}

enum EaKind {
	data      // Dn
	address   // An
	indirect  // (An)
	postinc   // (An)+
	predec    // -(An)
	disp      // d16(An)
	index     // d8(An,Xn.l)
	absolute  // address.l
	label     // the memory at a label
	pc_label  // label(pc)
	immediate // #value
	label_ptr // #label
}

// Ea is one operand of a 68000 instruction. Build them with the register
// constants and the functions below.
pub struct Ea {
	kind  EaKind
	reg   int
	index int // register number 0..15 (d0..a7) of an indexed operand
	value i64
	name  string
}

pub const d0 = Ea{
	kind: .data
	reg:  0
}
pub const d1 = Ea{
	kind: .data
	reg:  1
}
pub const d2 = Ea{
	kind: .data
	reg:  2
}
pub const d3 = Ea{
	kind: .data
	reg:  3
}
pub const d4 = Ea{
	kind: .data
	reg:  4
}
pub const d5 = Ea{
	kind: .data
	reg:  5
}
pub const d6 = Ea{
	kind: .data
	reg:  6
}
pub const d7 = Ea{
	kind: .data
	reg:  7
}
pub const a0 = Ea{
	kind: .address
	reg:  0
}
pub const a1 = Ea{
	kind: .address
	reg:  1
}
pub const a2 = Ea{
	kind: .address
	reg:  2
}
pub const a3 = Ea{
	kind: .address
	reg:  3
}
pub const a4 = Ea{
	kind: .address
	reg:  4
}
pub const a5 = Ea{
	kind: .address
	reg:  5
}
pub const a6 = Ea{
	kind: .address
	reg:  6
}
pub const sp = Ea{
	kind: .address
	reg:  7
}

fn based(kind EaKind, a Ea) Ea {
	if a.kind != .address {
		panic('jagkit: an address register is required here')
	}
	return Ea{
		kind: kind
		reg:  a.reg
	}
}

// ind is `(An)`.
pub fn ind(a Ea) Ea {
	return based(.indirect, a)
}

// inc is `(An)+`.
pub fn inc(a Ea) Ea {
	return based(.postinc, a)
}

// dec is `-(An)`.
pub fn dec(a Ea) Ea {
	return based(.predec, a)
}

// at is `offset(An)`.
pub fn at(offset int, a Ea) Ea {
	return Ea{
		...based(.disp, a)
		value: offset
	}
}

// idx is `offset(An,Xn.l)`: the base plus a whole index register.
pub fn idx(offset int, a Ea, x Ea) Ea {
	if x.kind !in [.data, .address] {
		panic('jagkit: the index must be a register')
	}
	return Ea{
		...based(.index, a)
		value: offset
		index: if x.kind == .address { x.reg + 8 } else { x.reg }
	}
}

// abs is the memory at a fixed address.
pub fn abs(address u32) Ea {
	return Ea{
		kind:  .absolute
		value: address
	}
}

// imm is `#value`.
pub fn imm(value i64) Ea {
	return Ea{
		kind:  .immediate
		value: value
	}
}

// lbl is the memory at a label, or the label itself for jumps.
pub fn lbl(name string) Ea {
	return Ea{
		kind: .label
		name: name
	}
}

// ptr is `#label`: the address of a label as a value.
pub fn ptr(name string) Ea {
	return Ea{
		kind: .label_ptr
		name: name
	}
}

// rel is `label(pc)`.
pub fn rel(name string) Ea {
	return Ea{
		kind: .pc_label
		name: name
	}
}

fn (e Ea) is_immediate() bool {
	return e.kind in [.immediate, .label_ptr]
}

// field is the six-bit mode and register encoding.
fn (e Ea) field() u16 {
	return match e.kind {
		.data { u16(e.reg) }
		.address { u16(0o10 | e.reg) }
		.indirect { u16(0o20 | e.reg) }
		.postinc { u16(0o30 | e.reg) }
		.predec { u16(0o40 | e.reg) }
		.disp { u16(0o50 | e.reg) }
		.index { u16(0o60 | e.reg) }
		.absolute, .label { u16(0o71) }
		.pc_label { u16(0o72) }
		.immediate, .label_ptr { u16(0o74) }
	}
}

struct M68kFixup {
	offset   int // byte offset of the field to patch
	label    string
	relative bool // 16-bit distance from the field; otherwise a 32-bit address
}

// M68k assembles a 68000 program. Mistakes are collected and reported
// together by `assemble`.
pub struct M68k {
pub:
	origin u32 // address the program is loaded at
mut:
	code     []u8
	labels   map[string]u32
	fixups   []M68kFixup
	problems []string
	serial   int
}

// new_m68k starts a program that will be loaded at `origin`.
pub fn new_m68k(origin u32) &M68k {
	return &M68k{
		origin: origin
	}
}

// here is the address of the next byte to be emitted.
pub fn (m &M68k) here() u32 {
	return m.origin + u32(m.code.len)
}

// label names the current address.
pub fn (mut m M68k) label(name string) {
	if name in m.labels {
		m.problems << 'label `${name}` defined twice'
	}
	m.labels[name] = m.here()
}

// unique returns a label name that has not been used, for local jumps.
pub fn (mut m M68k) unique(prefix string) string {
	m.serial++
	return '${prefix}.${m.serial}'
}

// address_of returns the address of a label that is already defined.
pub fn (m &M68k) address_of(name string) u32 {
	return m.labels[name] or { panic('jagkit: 68000 label `${name}` is not defined yet') }
}

// symbols returns the address of every label defined so far.
pub fn (m &M68k) symbols() map[string]u32 {
	return m.labels.clone()
}

// assemble resolves the labels and returns the program.
pub fn (mut m M68k) assemble() ![]u8 {
	for f in m.fixups {
		target := m.labels[f.label] or {
			m.problems << 'unknown label `${f.label}`'
			continue
		}
		if f.relative {
			distance := int(target) - int(m.origin) - f.offset
			if distance < -32768 || distance > 32767 {
				m.problems << '`${f.label}` is out of reach of a 16-bit displacement'
				continue
			}
			m.code[f.offset] = u8(distance >> 8)
			m.code[f.offset + 1] = u8(distance)
		} else {
			for i in 0 .. 4 {
				m.code[f.offset + i] = u8(target >> (24 - 8 * i))
			}
		}
	}
	if m.problems.len > 0 {
		return error('68000 program:\n  ' + m.problems.join('\n  '))
	}
	return m.code.clone()
}

// Data.

// byte emits an 8-bit constant.
pub fn (mut m M68k) byte(value int) {
	m.code << u8(value)
}

// word emits a 16-bit constant.
pub fn (mut m M68k) word(value int) {
	m.code << u8(value >> 8)
	m.code << u8(value)
}

// long emits a 32-bit constant.
pub fn (mut m M68k) long(value u32) {
	m.word(int(value >> 16))
	m.word(int(value & 0xffff))
}

// long_label emits the address of a label.
pub fn (mut m M68k) long_label(name string) {
	m.fixups << M68kFixup{
		offset: m.code.len
		label:  name
	}
	m.long(0)
}

// bytes emits raw data.
pub fn (mut m M68k) bytes(data []u8) {
	m.code << data
}

// text emits a zero-terminated string and pads to an even address.
pub fn (mut m M68k) text(s string) {
	m.code << s.bytes()
	m.code << 0
	m.align(2)
}

// align pads with zeroes to a multiple of `n` bytes.
pub fn (mut m M68k) align(n u32) {
	for m.here() % n != 0 {
		m.code << 0
	}
}

fn (mut m M68k) relative(name string) {
	m.fixups << M68kFixup{
		offset:   m.code.len
		label:    name
		relative: true
	}
	m.word(0)
}

// extension emits the words that follow the opcode for one operand.
fn (mut m M68k) extension(e Ea, size Size) {
	match e.kind {
		.data, .address, .indirect, .postinc, .predec {}
		.disp {
			if e.value < -32768 || e.value > 32767 {
				m.problems << 'displacement ${e.value} does not fit 16 bits'
			}
			m.word(int(e.value))
		}
		.index {
			if e.value < -128 || e.value > 127 {
				m.problems << 'index displacement ${e.value} does not fit 8 bits'
			}
			m.word(int((u32(e.index) << 12) | 0x800 | u32(e.value & 0xff)))
		}
		.absolute {
			m.long(u32(e.value))
		}
		.label {
			m.long_label(e.name)
		}
		.pc_label {
			m.relative(e.name)
		}
		.immediate {
			// Signed and unsigned spellings of the same bits are both fine.
			limit := match size {
				.b { i64(0x100) }
				.w { i64(0x1_0000) }
				.l { i64(0x1_0000_0000) }
			}

			if e.value < -limit / 2 || e.value >= limit {
				m.problems << 'immediate ${e.value} does not fit the operand size'
			}
			match size {
				.b { m.word(int(e.value & 0xff)) }
				.w { m.word(int(e.value & 0xffff)) }
				.l { m.long(u32(e.value)) }
			}
		}
		.label_ptr {
			if size != .l {
				m.problems << '#${e.name} needs a long operation'
			}
			m.long_label(e.name)
		}
	}
}

fn (mut m M68k) data_register(name string, e Ea) u16 {
	if e.kind != .data {
		m.problems << '${name}: a data register is required'
	}
	return u16(e.reg)
}

fn (mut m M68k) address_register(name string, e Ea) u16 {
	if e.kind != .address {
		m.problems << '${name}: an address register is required'
	}
	return u16(e.reg)
}

fn (mut m M68k) writable(name string, e Ea) {
	if e.kind in [.immediate, .label_ptr, .pc_label] {
		m.problems << '${name}: the destination cannot be written'
	}
}

fn size_bits(size Size) u16 {
	return u16(size) << 6
}

// Moves.

// move copies src to dst; an address-register destination is `movea`.
pub fn (mut m M68k) move(size Size, src Ea, dst Ea) {
	m.writable('move', dst)
	if dst.kind == .address && size == .b {
		m.problems << 'move.b to an address register'
	}
	bits := match size {
		.b { u16(0x1000) }
		.w { u16(0x3000) }
		.l { u16(0x2000) }
	}

	field := dst.field()
	m.word(bits | ((field & 7) << 9) | ((field >> 3) << 6) | src.field())
	m.extension(src, size)
	m.extension(dst, size)
}

// moveq loads -128..127 into a whole data register.
pub fn (mut m M68k) moveq(value int, dst Ea) {
	if value < -128 || value > 127 {
		m.problems << 'moveq #${value}: the value must be -128..127'
	}
	m.word(0x7000 | (m.data_register('moveq', dst) << 9) | u16(value & 0xff))
}

// lea loads the address of src into an address register.
pub fn (mut m M68k) lea(src Ea, dst Ea) {
	m.word(0x41c0 | (m.address_register('lea', dst) << 9) | src.field())
	m.extension(src, .l)
}

// move_to_sr sets the status register; supervisor only.
pub fn (mut m M68k) move_to_sr(src Ea) {
	m.word(0x46c0 | src.field())
	m.extension(src, .w)
}

// push is `movem.l registers,-(sp)`.
pub fn (mut m M68k) push(registers []Ea) {
	mut mask := u16(0)
	for r in registers {
		mask |= u16(0x8000) >> movem_bit(r)
	}
	m.word(0x48e7)
	m.word(mask)
}

// pop is `movem.l (sp)+,registers`.
pub fn (mut m M68k) pop(registers []Ea) {
	mut mask := u16(0)
	for r in registers {
		mask |= u16(1) << movem_bit(r)
	}
	m.word(0x4cdf)
	m.word(mask)
}

fn movem_bit(r Ea) u32 {
	return match r.kind {
		.data { u32(r.reg) }
		.address { u32(r.reg + 8) }
		else { panic('jagkit: movem takes registers') }
	}
}

// One-operand instructions.

fn (mut m M68k) unary(name string, opcode u16, size Size, dst Ea) {
	m.writable(name, dst)
	m.word(opcode | size_bits(size) | dst.field())
	m.extension(dst, size)
}

// clr zeroes dst.
pub fn (mut m M68k) clr(size Size, dst Ea) {
	m.unary('clr', 0x4200, size, dst)
}

// neg negates dst.
pub fn (mut m M68k) neg(size Size, dst Ea) {
	m.unary('neg', 0x4400, size, dst)
}

// not flips every bit of dst.
pub fn (mut m M68k) not(size Size, dst Ea) {
	m.unary('not', 0x4600, size, dst)
}

// tst sets the flags for dst.
pub fn (mut m M68k) tst(size Size, dst Ea) {
	m.unary('tst', 0x4a00, size, dst)
}

// swap exchanges the two words of a data register.
pub fn (mut m M68k) swap(dst Ea) {
	m.word(0x4840 | m.data_register('swap', dst))
}

// ext sign-extends a byte to a word (`.w`) or a word to a long (`.l`).
pub fn (mut m M68k) ext(size Size, dst Ea) {
	if size == .b {
		m.problems << 'ext.b does not exist'
	}
	m.word((if size == .l { u16(0x48c0) } else { u16(0x4880) }) | m.data_register('ext', dst))
}

// Two-operand arithmetic and logic. The right encoding is chosen from the
// operands: quick, immediate, address-register or plain.

struct Family {
	name      string
	plain     u16 // <ea>,Dn; bit 8 set gives Dn,<ea>
	immediate u16
	quick     u16  // 0 when the family has no quick form
	address   bool // has an address-register form
	to_memory bool // has the Dn,<ea> form
	from_ea   bool // has the <ea>,Dn form
}

fn (mut m M68k) binary(f Family, size Size, src Ea, dst Ea) {
	m.writable(f.name, dst)
	if f.quick != 0 && src.kind == .immediate && src.value >= 1 && src.value <= 8
		&& !(dst.kind == .address && size == .b) {
		m.word(f.quick | (u16(src.value & 7) << 9) | size_bits(size) | dst.field())
		m.extension(dst, size)
		return
	}
	if dst.kind == .address {
		if !f.address || size == .b {
			m.problems << '${f.name}: no such address-register form'
		}
		m.word(f.plain | (u16(dst.reg) << 9) | (if size == .l { u16(0x1c0) } else { u16(0xc0) }) | src.field())
		m.extension(src, size)
		return
	}
	if src.is_immediate() {
		m.word(f.immediate | size_bits(size) | dst.field())
		m.extension(src, size)
		m.extension(dst, size)
		return
	}
	if dst.kind == .data && f.from_ea {
		if src.kind == .address && size == .b {
			m.problems << '${f.name}.b from an address register'
		}
		m.word(f.plain | (u16(dst.reg) << 9) | size_bits(size) | src.field())
		m.extension(src, size)
		return
	}
	if src.kind == .data && f.to_memory {
		m.word(f.plain | 0x100 | (u16(src.reg) << 9) | size_bits(size) | dst.field())
		m.extension(dst, size)
		return
	}
	m.problems << '${f.name}: one operand must be a data register or an immediate'
}

// add adds src to dst.
pub fn (mut m M68k) add(size Size, src Ea, dst Ea) {
	m.binary(Family{'add', 0xd000, 0x0600, 0x5000, true, true, true}, size, src, dst)
}

// sub subtracts src from dst.
pub fn (mut m M68k) sub(size Size, src Ea, dst Ea) {
	m.binary(Family{'sub', 0x9000, 0x0400, 0x5100, true, true, true}, size, src, dst)
}

// cmp sets the flags of dst - src.
pub fn (mut m M68k) cmp(size Size, src Ea, dst Ea) {
	m.binary(Family{'cmp', 0xb000, 0x0c00, 0, true, false, true}, size, src, dst)
}

// and keeps the bits set in both.
pub fn (mut m M68k) and(size Size, src Ea, dst Ea) {
	m.binary(Family{'and', 0xc000, 0x0200, 0, false, true, true}, size, src, dst)
}

// orr is `or`: it keeps the bits set in either.
pub fn (mut m M68k) orr(size Size, src Ea, dst Ea) {
	m.binary(Family{'or', 0x8000, 0x0000, 0, false, true, true}, size, src, dst)
}

// eor flips the bits set in src.
pub fn (mut m M68k) eor(size Size, src Ea, dst Ea) {
	m.binary(Family{'eor', 0xb000, 0x0a00, 0, false, true, false}, size, src, dst)
}

fn (mut m M68k) multiply(name string, opcode u16, src Ea, dst Ea) {
	m.word(opcode | (m.data_register(name, dst) << 9) | src.field())
	m.extension(src, .w)
}

// mulu multiplies two unsigned words into a long.
pub fn (mut m M68k) mulu(src Ea, dst Ea) {
	m.multiply('mulu', 0xc0c0, src, dst)
}

// muls multiplies two signed words into a long.
pub fn (mut m M68k) muls(src Ea, dst Ea) {
	m.multiply('muls', 0xc1c0, src, dst)
}

// divu divides a long by a word: quotient in the low word, remainder above.
pub fn (mut m M68k) divu(src Ea, dst Ea) {
	m.multiply('divu', 0x80c0, src, dst)
}

// Shifts of a data register by 1..8 or by another data register.

fn (mut m M68k) shift(name string, kind u16, left bool, size Size, count Ea, dst Ea) {
	mut opcode := u16(0xe000) | (kind << 3) | size_bits(size) | m.data_register(name, dst)
	if left {
		opcode |= 0x100
	}
	match count.kind {
		.immediate {
			if count.value < 1 || count.value > 8 {
				m.problems << '${name} #${count.value}: the count must be 1..8'
			}
			opcode |= u16(count.value & 7) << 9
		}
		.data {
			opcode |= 0x20 | (u16(count.reg) << 9)
		}
		else {
			m.problems << '${name}: the count must be immediate or a data register'
		}
	}

	m.word(opcode)
}

// asl shifts left, arithmetically.
pub fn (mut m M68k) asl(size Size, count Ea, dst Ea) {
	m.shift('asl', 0, true, size, count, dst)
}

// asr shifts right, keeping the sign.
pub fn (mut m M68k) asr(size Size, count Ea, dst Ea) {
	m.shift('asr', 0, false, size, count, dst)
}

// lsl shifts left, filling with zeroes.
pub fn (mut m M68k) lsl(size Size, count Ea, dst Ea) {
	m.shift('lsl', 1, true, size, count, dst)
}

// lsr shifts right, filling with zeroes.
pub fn (mut m M68k) lsr(size Size, count Ea, dst Ea) {
	m.shift('lsr', 1, false, size, count, dst)
}

// roxl rotates left through the X flag.
pub fn (mut m M68k) roxl(size Size, count Ea, dst Ea) {
	m.shift('roxl', 2, true, size, count, dst)
}

// rol rotates left.
pub fn (mut m M68k) rol(size Size, count Ea, dst Ea) {
	m.shift('rol', 3, true, size, count, dst)
}

// ror rotates right.
pub fn (mut m M68k) ror(size Size, count Ea, dst Ea) {
	m.shift('ror', 3, false, size, count, dst)
}

// Single bits. In memory the operation is on a byte, in a data register on
// the whole long.

fn (mut m M68k) bit(name string, opcode u16, n int, dst Ea) {
	limit := if dst.kind == .data { 31 } else { 7 }
	if n < 0 || n > limit {
		m.problems << '${name} #${n}: the bit must be 0..${limit}'
	}
	m.word(opcode | dst.field())
	m.word(n)
	m.extension(dst, .b)
}

// btst sets Z when a bit is clear.
pub fn (mut m M68k) btst(n int, dst Ea) {
	m.bit('btst', 0x0800, n, dst)
}

// bclr tests a bit, then clears it.
pub fn (mut m M68k) bclr(n int, dst Ea) {
	m.bit('bclr', 0x0880, n, dst)
}

// bset tests a bit, then sets it.
pub fn (mut m M68k) bset(n int, dst Ea) {
	m.bit('bset', 0x08c0, n, dst)
}

// Control flow. Branches always use a 16-bit displacement.

// bra jumps to a label.
pub fn (mut m M68k) bra(name string) {
	m.word(0x6000)
	m.relative(name)
}

// bsr calls a subroutine.
pub fn (mut m M68k) bsr(name string) {
	m.word(0x6100)
	m.relative(name)
}

// b branches when the condition holds.
pub fn (mut m M68k) b(cc Cc, name string) {
	m.word(int(0x6000 | (u32(cc) << 8)))
	m.relative(name)
}

// dbra counts a data register's low word down and branches until it
// passes zero: the loop body runs count + 1 times.
pub fn (mut m M68k) dbra(counter Ea, name string) {
	m.word(0x51c8 | m.data_register('dbra', counter))
	m.relative(name)
}

// jmp continues at target.
pub fn (mut m M68k) jmp(target Ea) {
	m.word(0x4ec0 | target.field())
	m.extension(target, .l)
}

// jsr calls the subroutine at target.
pub fn (mut m M68k) jsr(target Ea) {
	m.word(0x4e80 | target.field())
	m.extension(target, .l)
}

// rts returns from a subroutine.
pub fn (mut m M68k) rts() {
	m.word(0x4e75)
}

// rte returns from an interrupt.
pub fn (mut m M68k) rte() {
	m.word(0x4e73)
}

// nop does nothing.
pub fn (mut m M68k) nop() {
	m.word(0x4e71)
}

// stop loads the status register and waits for an interrupt.
pub fn (mut m M68k) stop(status int) {
	m.word(0x4e72)
	m.word(status)
}
