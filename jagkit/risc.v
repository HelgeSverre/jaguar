module jagkit

// Reg is one of the 32 registers of the GPU or the DSP.
pub enum Reg {
	r0
	r1
	r2
	r3
	r4
	r5
	r6
	r7
	r8
	r9
	r10
	r11
	r12
	r13
	r14
	r15
	r16
	r17
	r18
	r19
	r20
	r21
	r22
	r23
	r24
	r25
	r26
	r27
	r28
	r29
	r30
	r31
}

// Cond is the condition of a RISC jump. After `cmp a,b` (which computes
// b - a) `cs` means b < a unsigned and `mi` means b < a signed.
pub enum Cond {
	always = 0x00
	ne     = 0x01
	eq     = 0x02
	cc     = 0x04
	hi     = 0x05
	cs     = 0x08
	pl     = 0x14
	mi     = 0x18
}

struct RiscFixup {
	index int // word index of the instruction to patch
	label string
	jump  bool // a `jr` offset; otherwise the two words of a `movei`
}

// Risc assembles a program for the GPU or the DSP. Both share one
// instruction format; the few opcodes that differ have their own methods.
// Mistakes (a quick value out of range, an unknown label) are collected and
// reported together by `assemble`.
pub struct Risc {
pub:
	origin u32 // address the program runs at
mut:
	words    []u16
	labels   map[string]u32
	fixups   []RiscFixup
	problems []string
}

// new_risc starts a program that will run at `origin`.
pub fn new_risc(origin u32) &Risc {
	return &Risc{
		origin: origin
	}
}

// here is the address of the next word to be emitted.
pub fn (r &Risc) here() u32 {
	return r.origin + u32(r.words.len) * 2
}

// label names the current address.
pub fn (mut r Risc) label(name string) {
	if name in r.labels {
		r.problems << 'label `${name}` defined twice'
	}
	r.labels[name] = r.here()
}

// address_of returns the address of a label that is already defined.
pub fn (r &Risc) address_of(name string) u32 {
	return r.labels[name] or { panic('jagkit: RISC label `${name}` is not defined yet') }
}

// assemble resolves the labels and returns the program, big-endian.
pub fn (mut r Risc) assemble() ![]u8 {
	for f in r.fixups {
		target := r.labels[f.label] or {
			r.problems << 'unknown label `${f.label}`'
			continue
		}
		if f.jump {
			// The offset counts words from the instruction after the jump.
			after := r.origin + u32(f.index + 1) * 2
			offset := (int(target) - int(after)) / 2
			if offset < -16 || offset > 15 {
				r.problems << 'jr to `${f.label}` is ${offset} words away; the reach is -16..15'
				continue
			}
			r.words[f.index] |= u16(offset & 31) << 5
		} else {
			r.words[f.index + 1] = u16(target)
			r.words[f.index + 2] = u16(target >> 16)
		}
	}
	if r.problems.len > 0 {
		return error('RISC program at 0x${r.origin:06x}:\n  ' + r.problems.join('\n  '))
	}
	mut bytes := []u8{cap: r.words.len * 2}
	for w in r.words {
		bytes << u8(w >> 8)
		bytes << u8(w)
	}
	return bytes
}

fn (mut r Risc) emit(opcode int, first int, second Reg) {
	r.words << (u16(opcode) << 10) | (u16(first & 31) << 5) | u16(second)
}

fn (mut r Risc) rr(opcode int, src Reg, dst Reg) {
	r.emit(opcode, int(src), dst)
}

// quick emits an instruction whose first field is a count of 1..32.
fn (mut r Risc) quick(name string, opcode int, n int, dst Reg) {
	if n < 1 || n > 32 {
		r.problems << '${name} #${n}: the value must be 1..32'
	}
	r.emit(opcode, n & 31, dst)
}

// bit emits an instruction whose first field is 0..31.
fn (mut r Risc) bit(name string, opcode int, n int, dst Reg) {
	if n < 0 || n > 31 {
		r.problems << '${name} #${n}: the value must be 0..31'
	}
	r.emit(opcode, n, dst)
}

// Arithmetic and logic. The destination is always the second operand.

// add adds src to dst.
pub fn (mut r Risc) add(src Reg, dst Reg) {
	r.rr(0, src, dst)
}

// addc adds src and the carry to dst.
pub fn (mut r Risc) addc(src Reg, dst Reg) {
	r.rr(1, src, dst)
}

// addq adds 1..32.
pub fn (mut r Risc) addq(n int, dst Reg) {
	r.quick('addq', 2, n, dst)
}

// addqt adds without changing the flags.
pub fn (mut r Risc) addqt(n int, dst Reg) {
	r.quick('addqt', 3, n, dst)
}

// sub subtracts src from dst.
pub fn (mut r Risc) sub(src Reg, dst Reg) {
	r.rr(4, src, dst)
}

// subc subtracts src and the carry from dst.
pub fn (mut r Risc) subc(src Reg, dst Reg) {
	r.rr(5, src, dst)
}

// subq subtracts 1..32.
pub fn (mut r Risc) subq(n int, dst Reg) {
	r.quick('subq', 6, n, dst)
}

// subqt subtracts without changing the flags.
pub fn (mut r Risc) subqt(n int, dst Reg) {
	r.quick('subqt', 7, n, dst)
}

// neg negates dst.
pub fn (mut r Risc) neg(dst Reg) {
	r.emit(8, 0, dst)
}

// and keeps the bits set in both.
pub fn (mut r Risc) and(src Reg, dst Reg) {
	r.rr(9, src, dst)
}

// orr is `or`: it keeps the bits set in either.
pub fn (mut r Risc) orr(src Reg, dst Reg) {
	r.rr(10, src, dst)
}

// xor flips the bits set in src.
pub fn (mut r Risc) xor(src Reg, dst Reg) {
	r.rr(11, src, dst)
}

// not flips every bit of dst.
pub fn (mut r Risc) not(dst Reg) {
	r.emit(12, 0, dst)
}

// btst sets Z when bit n is clear.
pub fn (mut r Risc) btst(n int, dst Reg) {
	r.bit('btst', 13, n, dst)
}

// bset sets bit n.
pub fn (mut r Risc) bset(n int, dst Reg) {
	r.bit('bset', 14, n, dst)
}

// bclr clears bit n.
pub fn (mut r Risc) bclr(n int, dst Reg) {
	r.bit('bclr', 15, n, dst)
}

// mult multiplies the low 16 bits of both, unsigned, into 32 bits.
pub fn (mut r Risc) mult(src Reg, dst Reg) {
	r.rr(16, src, dst)
}

// imult multiplies the low 16 bits of both, signed, into 32 bits.
pub fn (mut r Risc) imult(src Reg, dst Reg) {
	r.rr(17, src, dst)
}

// div divides dst by src, unsigned.
pub fn (mut r Risc) div(src Reg, dst Reg) {
	r.rr(21, src, dst)
}

// abs makes dst positive.
pub fn (mut r Risc) abs(dst Reg) {
	r.emit(22, 0, dst)
}

// shlq shifts left by 1..32.
pub fn (mut r Risc) shlq(n int, dst Reg) {
	if n < 1 || n > 32 {
		r.problems << 'shlq #${n}: the value must be 1..32'
	}
	r.emit(24, (32 - n) & 31, dst)
}

// shrq shifts right by 1..32, filling with zeroes.
pub fn (mut r Risc) shrq(n int, dst Reg) {
	r.quick('shrq', 25, n, dst)
}

// sharq shifts right by 1..32, keeping the sign.
pub fn (mut r Risc) sharq(n int, dst Reg) {
	r.quick('sharq', 27, n, dst)
}

// rorq rotates right by 1..32.
pub fn (mut r Risc) rorq(n int, dst Reg) {
	r.quick('rorq', 29, n, dst)
}

// cmp sets the flags of dst - src.
pub fn (mut r Risc) cmp(src Reg, dst Reg) {
	r.rr(30, src, dst)
}

// cmpq sets the flags of dst - n for n in -16..15.
pub fn (mut r Risc) cmpq(n int, dst Reg) {
	if n < -16 || n > 15 {
		r.problems << 'cmpq #${n}: the value must be -16..15'
	}
	r.emit(31, n & 31, dst)
}

// Moves.

// move copies src to dst.
pub fn (mut r Risc) move(src Reg, dst Reg) {
	r.rr(34, src, dst)
}

// moveq loads 0..31.
pub fn (mut r Risc) moveq(n int, dst Reg) {
	r.bit('moveq', 35, n, dst)
}

// movei loads any 32-bit value. It takes three words and must not sit in
// the delay slot of a jump.
pub fn (mut r Risc) movei(value u32, dst Reg) {
	r.emit(38, 0, dst)
	r.words << u16(value)
	r.words << u16(value >> 16)
}

// movei_label loads the address of a label.
pub fn (mut r Risc) movei_label(name string, dst Reg) {
	r.fixups << RiscFixup{
		index: r.words.len
		label: name
	}
	r.movei(0, dst)
}

// move_pc copies the address of this instruction.
pub fn (mut r Risc) move_pc(dst Reg) {
	r.emit(51, 0, dst)
}

// Memory. Loads read `(addr)` into dst; stores write src to `(addr)`.

// loadb reads a byte.
pub fn (mut r Risc) loadb(addr Reg, dst Reg) {
	r.rr(39, addr, dst)
}

// loadw reads a word.
pub fn (mut r Risc) loadw(addr Reg, dst Reg) {
	r.rr(40, addr, dst)
}

// load reads a long.
pub fn (mut r Risc) load(addr Reg, dst Reg) {
	r.rr(41, addr, dst)
}

// storeb writes a byte.
pub fn (mut r Risc) storeb(src Reg, addr Reg) {
	r.rr(45, addr, src)
}

// storew writes a word.
pub fn (mut r Risc) storew(src Reg, addr Reg) {
	r.rr(46, addr, src)
}

// store writes a long.
pub fn (mut r Risc) store(src Reg, addr Reg) {
	r.rr(47, addr, src)
}

// offset_field checks the byte offset of a `(r14+n)` or `(r15+n)` access.
fn (mut r Risc) offset_field(offset int) int {
	if offset < 4 || offset > 128 || offset % 4 != 0 {
		r.problems << 'indexed access +${offset}: the offset must be a multiple of 4 in 4..128'
	}
	return (offset / 4) & 31
}

// load_r14 reads the long at r14 + offset; the offset is 4..128.
pub fn (mut r Risc) load_r14(offset int, dst Reg) {
	r.emit(43, r.offset_field(offset), dst)
}

// store_r14 writes a long to r14 + offset; the offset is 4..128.
pub fn (mut r Risc) store_r14(src Reg, offset int) {
	r.emit(49, r.offset_field(offset), src)
}

// Control flow. Every jump executes the instruction after it first.

// jr jumps to a label at most 16 words back or 15 words ahead.
pub fn (mut r Risc) jr(cond Cond, name string) {
	r.fixups << RiscFixup{
		index: r.words.len
		label: name
		jump:  true
	}
	r.words << u16(53 << 10) | u16(cond)
}

// jump goes to the address in a register.
pub fn (mut r Risc) jump(cond Cond, addr Reg) {
	r.words << u16(52 << 10) | (u16(addr) << 5) | u16(cond)
}

// nop does nothing.
pub fn (mut r Risc) nop() {
	r.emit(57, 0, .r0)
}

// Data.

// align_long pads with zero words to a multiple of four bytes.
pub fn (mut r Risc) align_long() {
	for r.here() & 3 != 0 {
		r.words << 0
	}
}

// long emits a 32-bit constant.
pub fn (mut r Risc) long(value u32) {
	r.words << u16(value >> 16)
	r.words << u16(value)
}

// pad_to emits zero words up to `address`.
pub fn (mut r Risc) pad_to(address u32) {
	if address < r.here() || address & 1 != 0 {
		r.problems << 'cannot pad to 0x${address:06x} from 0x${r.here():06x}'
		return
	}
	for r.here() < address {
		r.words << 0
	}
}
