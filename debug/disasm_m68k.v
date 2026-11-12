module debug

// WordReader returns the big-endian 16-bit word at an even address, without side effects.
pub type WordReader = fn (addr u32) u16

// Addressing-mode sets, one bit per mode in the order: Dn, An, (An), (An)+,
// -(An), d16(An), d8(An,Xn), abs.w, abs.l, d16(PC), d8(PC,Xn), #imm.
const m68k_ea_all = u16(0xfff)
const m68k_ea_data = u16(0xffd)
const m68k_ea_data_no_immediate = u16(0x7fd)
const m68k_ea_control = u16(0x7e4)
const m68k_ea_alterable = u16(0x1ff)
const m68k_ea_data_alterable = u16(0x1fd)
const m68k_ea_memory_alterable = u16(0x1fc)
const m68k_ea_movem_to_memory = u16(0x1f4)
const m68k_ea_movem_to_registers = u16(0x7ec)

const m68k_conditions = ['t', 'f', 'hi', 'ls', 'cc', 'cs', 'ne', 'eq', 'vc', 'vs', 'pl', 'mi',
	'ge', 'lt', 'gt', 'le']!
const m68k_immediate_names = ['ori', 'andi', 'subi', 'addi', '', 'eori', 'cmpi']!
const m68k_bit_names = ['btst', 'bchg', 'bclr', 'bset']!
const m68k_shift_names = ['as', 'ls', 'rox', 'ro']!

// M68kSize is the operand size of an instruction.
enum M68kSize {
	byte
	word
	long
}

// suffix returns the mnemonic suffix for the size, including the dot.
fn (s M68kSize) suffix() string {
	return match s {
		.byte { '.b' }
		.word { '.w' }
		.long { '.l' }
	}
}

// m68k_size decodes the common two-bit size field; the value 3 is not a size.
fn m68k_size(field u16) ?M68kSize {
	return match field & 3 {
		0 { M68kSize.byte }
		1 { M68kSize.word }
		2 { M68kSize.long }
		else { none }
	}
}

// m68k_word_or_long decodes a one-bit size field.
fn m68k_word_or_long(long bool) M68kSize {
	return if long { M68kSize.long } else { M68kSize.word }
}

// M68kDecoder walks the instruction stream one extension word at a time.
struct M68kDecoder {
	read WordReader @[required]
mut:
	next u32
}

fn (mut d M68kDecoder) next_word() u16 {
	word := d.read(d.next)
	d.next += 2
	return word
}

fn (mut d M68kDecoder) next_long() u32 {
	high := u32(d.next_word())
	return high << 16 | d.next_word()
}

// disassemble_m68k decodes one MC68000 instruction at `addr` and returns its
// text and its length in bytes (always even, 2..10).
pub fn disassemble_m68k(read WordReader, addr u32) (string, u32) {
	mut d := M68kDecoder{
		read: read
		next: addr
	}
	opcode := d.next_word()
	text := d.decode(opcode) or { return m68k_data_word(opcode), 2 }
	return text, d.next - addr
}

// m68k_data_word renders an opcode that is not a 68000 instruction.
fn m68k_data_word(opcode u16) string {
	text := 'dc.w ${m68k_hex(opcode, 4)}'
	return match opcode >> 12 {
		0xa { '${text} ; line-A' }
		0xf { '${text} ; line-F' }
		else { text }
	}
}

fn m68k_hex(value u32, digits int) string {
	text := value.hex()
	padding := if text.len < digits { '0'.repeat(digits - text.len) } else { '' }
	return '$' + padding + text
}

// m68k_displacement renders a signed displacement such as `$10` or `-$8`.
fn m68k_displacement(value int) string {
	return if value < 0 { '-' + m68k_hex(u32(-value), 1) } else { m68k_hex(u32(value), 1) }
}

// m68k_target renders the 24-bit address `base + displacement`.
fn m68k_target(base u32, displacement int) string {
	return m68k_hex(u32(i64(base) + displacement) & 0xffffff, 6)
}

fn m68k_address_register(n int) string {
	return if n == 7 { 'sp' } else { 'a${n}' }
}

fn m68k_condition_name(code u16) string {
	return m68k_conditions[code & 0xf]
}

// m68k_quick_value decodes a 3-bit count where 0 means 8.
fn m68k_quick_value(opcode u16) int {
	value := m68k_upper_register(opcode)
	return if value == 0 { 8 } else { value }
}

fn m68k_ea_mode(opcode u16) int {
	return int(opcode >> 3) & 7
}

fn m68k_ea_register(opcode u16) int {
	return int(opcode) & 7
}

fn m68k_upper_register(opcode u16) int {
	return int(opcode >> 9) & 7
}

// m68k_register_list renders a MOVEM mask where bit 0 is d0 and bit 15 is a7.
fn m68k_register_list(mask u16) string {
	if mask == 0 {
		return '#' + m68k_hex(0, 4)
	}
	mut ranges := []string{}
	for bank in 0 .. 2 {
		mut first := 0
		for first < 8 {
			if (mask >> (bank * 8 + first)) & 1 == 0 {
				first++
				continue
			}
			mut last := first
			for last < 7 && (mask >> (bank * 8 + last + 1)) & 1 == 1 {
				last++
			}
			ranges << m68k_register_range(bank, first, last)
			first = last + 1
		}
	}
	return ranges.join('/')
}

fn m68k_register_range(bank int, first int, last int) string {
	name := fn [bank] (n int) string {
		return if bank == 0 { 'd${n}' } else { m68k_address_register(n) }
	}
	return if first == last { name(first) } else { '${name(first)}-${name(last)}' }
}

fn m68k_reverse_bits(mask u16) u16 {
	mut reversed := u16(0)
	for bit in 0 .. 16 {
		reversed |= ((mask >> bit) & 1) << (15 - bit)
	}
	return reversed
}

// m68k_register_pair renders the `Dy,Dx` / `-(Ay),-(Ax)` operands of ADDX, SUBX, ABCD and SBCD.
fn m68k_register_pair(name string, opcode u16) string {
	src := m68k_ea_register(opcode)
	dst := m68k_upper_register(opcode)
	if opcode & 0x0008 == 0 {
		return '${name} d${src},d${dst}'
	}
	return '${name} -(${m68k_address_register(src)}),-(${m68k_address_register(dst)})'
}

// operand decodes the effective address in the low six bits of the opcode.
fn (mut d M68kDecoder) operand(opcode u16, size M68kSize, allowed u16) ?string {
	return d.ea_text(m68k_ea_mode(opcode), m68k_ea_register(opcode), size, allowed)
}

// ea_text decodes an effective address, consuming its extension words. It
// returns none when the mode is not in `allowed` (or is a byte-sized An).
fn (mut d M68kDecoder) ea_text(mode int, reg int, size M68kSize, allowed u16) ?string {
	kind := if mode < 7 { mode } else { 7 + reg }
	if kind > 11 || (allowed >> kind) & 1 == 0 || (kind == 1 && size == .byte) {
		return none
	}
	an := m68k_address_register(reg)
	return match kind {
		0 { 'd${reg}' }
		1 { an }
		2 { '(${an})' }
		3 { '(${an})+' }
		4 { '-(${an})' }
		5 { '${m68k_displacement(i16(d.next_word()))}(${an})' }
		6 { d.indexed_text(an) }
		7 { '${m68k_hex(d.next_word(), 4)}.w' }
		8 { '${m68k_hex(d.next_long(), 8)}.l' }
		9 { d.pc_displacement_text() }
		10 { d.pc_indexed_text() }
		else { d.immediate_text(size) }
	}
}

fn (mut d M68kDecoder) indexed_text(base string) string {
	extension := d.next_word()
	return '${m68k_displacement(i8(extension & 0xff))}(${base},${m68k_index_register(extension)})'
}

fn (mut d M68kDecoder) pc_displacement_text() string {
	base := d.next
	return '${m68k_target(base, i16(d.next_word()))}(pc)'
}

fn (mut d M68kDecoder) pc_indexed_text() string {
	base := d.next
	extension := d.next_word()
	return '${m68k_target(base, i8(extension & 0xff))}(pc,${m68k_index_register(extension)})'
}

// m68k_index_register renders the index part of a brief extension word, e.g. `d1.w`.
fn m68k_index_register(extension u16) string {
	n := int(extension >> 12) & 7
	name := if extension & 0x8000 == 0 { 'd${n}' } else { m68k_address_register(n) }
	return name + m68k_word_or_long(extension & 0x0800 != 0).suffix()
}

fn (mut d M68kDecoder) immediate_text(size M68kSize) string {
	return match size {
		.byte { '#' + m68k_hex(d.next_word() & 0xff, 2) }
		.word { '#' + m68k_hex(d.next_word(), 4) }
		.long { '#' + m68k_hex(d.next_long(), 8) }
	}
}

// decode returns the instruction text, or none for an opcode the 68000 does not implement.
fn (mut d M68kDecoder) decode(opcode u16) ?string {
	match opcode >> 12 {
		0x0 { return d.decode_immediate_and_bit(opcode) }
		0x1 { return d.decode_move(opcode, .byte) }
		0x2 { return d.decode_move(opcode, .long) }
		0x3 { return d.decode_move(opcode, .word) }
		0x4 { return d.decode_miscellaneous(opcode) }
		0x5 { return d.decode_quick(opcode) }
		0x6 { return d.decode_branch(opcode) }
		0x7 { return m68k_decode_moveq(opcode) }
		0x8 { return d.decode_or_divide(opcode) }
		0x9 { return d.decode_add_subtract('sub', opcode) }
		0xb { return d.decode_compare_eor(opcode) }
		0xc { return d.decode_and_multiply(opcode) }
		0xd { return d.decode_add_subtract('add', opcode) }
		0xe { return d.decode_shift(opcode) }
		else { return none }
	}
}

// decode_immediate_and_bit handles line 0: ORI/ANDI/SUBI/ADDI/EORI/CMPI, bit operations and MOVEP.
fn (mut d M68kDecoder) decode_immediate_and_bit(opcode u16) ?string {
	if opcode & 0x0100 != 0 {
		if m68k_ea_mode(opcode) == 1 {
			return d.decode_movep(opcode)
		}
		return d.decode_bit_operation(opcode, 'd${m68k_upper_register(opcode)}', m68k_ea_data)
	}
	group := m68k_upper_register(opcode)
	if group == 4 {
		bit := d.next_word() & 0xff
		return d.decode_bit_operation(opcode, '#${bit}', m68k_ea_data_no_immediate)
	}
	if group == 7 {
		return none
	}
	size := m68k_size(opcode >> 6)?
	name := m68k_immediate_names[group] + size.suffix()
	immediate := d.immediate_text(size)
	if opcode & 0x3f == 0x3c {
		if group !in [0, 1, 5] || size == .long {
			return none
		}
		register := if size == .byte { 'ccr' } else { 'sr' }
		return '${name} ${immediate},${register}'
	}
	dst := d.operand(opcode, size, m68k_ea_data_alterable)?
	return '${name} ${immediate},${dst}'
}

// decode_bit_operation handles BTST/BCHG/BCLR/BSET; only BTST accepts the `btst_allowed` modes.
fn (mut d M68kDecoder) decode_bit_operation(opcode u16, bit string, btst_allowed u16) ?string {
	kind := (opcode >> 6) & 3
	allowed := if kind == 0 { btst_allowed } else { m68k_ea_data_alterable }
	dst := d.operand(opcode, .byte, allowed)?
	return '${m68k_bit_names[kind]} ${bit},${dst}'
}

fn (mut d M68kDecoder) decode_movep(opcode u16) string {
	name := 'movep' + m68k_word_or_long(opcode & 0x0040 != 0).suffix()
	data := 'd${m68k_upper_register(opcode)}'
	address := m68k_address_register(m68k_ea_register(opcode))
	memory := '${m68k_displacement(i16(d.next_word()))}(${address})'
	return if opcode & 0x0080 == 0 {
		'${name} ${memory},${data}'
	} else {
		'${name} ${data},${memory}'
	}
}

// decode_move handles lines 1-3: MOVE and MOVEA.
fn (mut d M68kDecoder) decode_move(opcode u16, size M68kSize) ?string {
	src := d.operand(opcode, size, m68k_ea_all)?
	dst_mode := int(opcode >> 6) & 7
	dst := d.ea_text(dst_mode, m68k_upper_register(opcode), size, m68k_ea_alterable)?
	name := if dst_mode == 1 { 'movea' } else { 'move' }
	return '${name}${size.suffix()} ${src},${dst}'
}

// decode_miscellaneous handles line 4.
fn (mut d M68kDecoder) decode_miscellaneous(opcode u16) ?string {
	if opcode == 0x4afc {
		return 'illegal'
	}
	if opcode & 0x0100 != 0 {
		return d.decode_chk_lea(opcode)
	}
	is_size := opcode & 0x00c0 != 0x00c0
	match m68k_upper_register(opcode) {
		0 {
			if is_size {
				return d.decode_unary('negx', opcode)
			}
			dst := d.operand(opcode, .word, m68k_ea_data_alterable)?
			return 'move.w sr,${dst}'
		}
		1 {
			return d.decode_unary('clr', opcode)
		}
		2 {
			if is_size {
				return d.decode_unary('neg', opcode)
			}
			src := d.operand(opcode, .word, m68k_ea_data)?
			return 'move.w ${src},ccr'
		}
		3 {
			if is_size {
				return d.decode_unary('not', opcode)
			}
			src := d.operand(opcode, .word, m68k_ea_data)?
			return 'move.w ${src},sr'
		}
		4 {
			return d.decode_nbcd_swap_pea_ext_movem(opcode)
		}
		5 {
			if is_size {
				return d.decode_unary('tst', opcode)
			}
			dst := d.operand(opcode, .byte, m68k_ea_data_alterable)?
			return 'tas ${dst}'
		}
		6 {
			if opcode & 0x0080 == 0 {
				return none
			}
			return d.decode_movem(opcode)
		}
		else {
			return d.decode_control(opcode)
		}
	}
}

fn (mut d M68kDecoder) decode_chk_lea(opcode u16) ?string {
	match (opcode >> 6) & 3 {
		2 {
			src := d.operand(opcode, .word, m68k_ea_data)?
			return 'chk.w ${src},d${m68k_upper_register(opcode)}'
		}
		3 {
			src := d.operand(opcode, .long, m68k_ea_control)?
			return 'lea ${src},${m68k_address_register(m68k_upper_register(opcode))}'
		}
		else {
			return none
		}
	}
}

// decode_unary handles the sized single-operand instructions NEGX, CLR, NEG, NOT and TST.
fn (mut d M68kDecoder) decode_unary(name string, opcode u16) ?string {
	size := m68k_size(opcode >> 6)?
	dst := d.operand(opcode, size, m68k_ea_data_alterable)?
	return '${name}${size.suffix()} ${dst}'
}

// decode_nbcd_swap_pea_ext_movem handles opcodes $4800-$48ff.
fn (mut d M68kDecoder) decode_nbcd_swap_pea_ext_movem(opcode u16) ?string {
	is_data_register := m68k_ea_mode(opcode) == 0
	data := 'd${m68k_ea_register(opcode)}'
	match (opcode >> 6) & 3 {
		0 {
			dst := d.operand(opcode, .byte, m68k_ea_data_alterable)?
			return 'nbcd ${dst}'
		}
		1 {
			if is_data_register {
				return 'swap ${data}'
			}
			src := d.operand(opcode, .long, m68k_ea_control)?
			return 'pea ${src}'
		}
		else {
			if is_data_register {
				return 'ext${m68k_word_or_long(opcode & 0x0040 != 0).suffix()} ${data}'
			}
			return d.decode_movem(opcode)
		}
	}
}

fn (mut d M68kDecoder) decode_movem(opcode u16) ?string {
	name := 'movem' + m68k_word_or_long(opcode & 0x0040 != 0).suffix()
	mask := d.next_word()
	if opcode & 0x0400 != 0 {
		src := d.operand(opcode, .long, m68k_ea_movem_to_registers)?
		return '${name} ${src},${m68k_register_list(mask)}'
	}
	dst := d.operand(opcode, .long, m68k_ea_movem_to_memory)?
	// The predecrement form stores the mask reversed: bit 0 is a7 and bit 15 is d0.
	registers := if m68k_ea_mode(opcode) == 4 { m68k_reverse_bits(mask) } else { mask }
	return '${name} ${m68k_register_list(registers)},${dst}'
}

// decode_control handles opcodes $4e00-$4eff: TRAP, LINK, UNLK, MOVE USP, JSR, JMP and friends.
fn (mut d M68kDecoder) decode_control(opcode u16) ?string {
	match (opcode >> 6) & 3 {
		0 {
			return none
		}
		1 {
			return d.decode_trap_link_system(opcode)
		}
		2 {
			dst := d.operand(opcode, .long, m68k_ea_control)?
			return 'jsr ${dst}'
		}
		else {
			dst := d.operand(opcode, .long, m68k_ea_control)?
			return 'jmp ${dst}'
		}
	}
}

fn (mut d M68kDecoder) decode_trap_link_system(opcode u16) ?string {
	address := m68k_address_register(m68k_ea_register(opcode))
	match m68k_ea_mode(opcode) {
		0, 1 { return 'trap #${opcode & 0xf}' }
		2 { return 'link ${address},#${i16(d.next_word())}' }
		3 { return 'unlk ${address}' }
		4 { return 'move.l ${address},usp' }
		5 { return 'move.l usp,${address}' }
		6 { return d.decode_system(opcode) }
		else { return none }
	}
}

fn (mut d M68kDecoder) decode_system(opcode u16) ?string {
	match opcode & 7 {
		0 { return 'reset' }
		1 { return 'nop' }
		2 { return 'stop #${m68k_hex(d.next_word(), 4)}' }
		3 { return 'rte' }
		5 { return 'rts' }
		6 { return 'trapv' }
		7 { return 'rtr' }
		else { return none }
	}
}

// decode_quick handles line 5: ADDQ, SUBQ, Scc and DBcc.
fn (mut d M68kDecoder) decode_quick(opcode u16) ?string {
	if opcode & 0x00c0 == 0x00c0 {
		condition := m68k_condition_name(opcode >> 8)
		if m68k_ea_mode(opcode) == 1 {
			name := if condition == 'f' { 'dbra' } else { 'db${condition}' }
			base := d.next
			return '${name} d${m68k_ea_register(opcode)},${m68k_target(base, i16(d.next_word()))}'
		}
		dst := d.operand(opcode, .byte, m68k_ea_data_alterable)?
		return 's${condition} ${dst}'
	}
	size := m68k_size(opcode >> 6)?
	name := if opcode & 0x0100 == 0 { 'addq' } else { 'subq' }
	dst := d.operand(opcode, size, m68k_ea_alterable)?
	return '${name}${size.suffix()} #${m68k_quick_value(opcode)},${dst}'
}

// decode_branch handles line 6: BRA, BSR and Bcc.
fn (mut d M68kDecoder) decode_branch(opcode u16) string {
	condition := (opcode >> 8) & 0xf
	name := match condition {
		0 { 'bra' }
		1 { 'bsr' }
		else { 'b' + m68k_condition_name(condition) }
	}

	base := d.next
	displacement := i8(opcode & 0xff)
	if displacement == 0 {
		return '${name}.w ${m68k_target(base, i16(d.next_word()))}'
	}
	return '${name}.s ${m68k_target(base, displacement)}'
}

fn m68k_decode_moveq(opcode u16) ?string {
	if opcode & 0x0100 != 0 {
		return none
	}
	return 'moveq #${i8(opcode & 0xff)},d${m68k_upper_register(opcode)}'
}

// decode_or_divide handles line 8: OR, DIVU, DIVS and SBCD.
fn (mut d M68kDecoder) decode_or_divide(opcode u16) ?string {
	match (opcode >> 6) & 7 {
		3 {
			return d.decode_multiply_divide('divu', opcode)
		}
		7 {
			return d.decode_multiply_divide('divs', opcode)
		}
		4 {
			if m68k_ea_mode(opcode) < 2 {
				return m68k_register_pair('sbcd', opcode)
			}
		}
		else {}
	}

	return d.decode_register_and_ea('or', opcode, m68k_ea_data)
}

// decode_and_multiply handles line C: AND, MULU, MULS, ABCD and EXG.
fn (mut d M68kDecoder) decode_and_multiply(opcode u16) ?string {
	match (opcode >> 6) & 7 {
		3 {
			return d.decode_multiply_divide('mulu', opcode)
		}
		7 {
			return d.decode_multiply_divide('muls', opcode)
		}
		4 {
			if m68k_ea_mode(opcode) < 2 {
				return m68k_register_pair('abcd', opcode)
			}
		}
		else {}
	}

	if text := m68k_decode_exg(opcode) {
		return text
	}
	return d.decode_register_and_ea('and', opcode, m68k_ea_data)
}

fn m68k_decode_exg(opcode u16) ?string {
	upper := m68k_upper_register(opcode)
	lower := m68k_ea_register(opcode)
	match opcode & 0x01f8 {
		0x0140 { return 'exg d${upper},d${lower}' }
		0x0148 { return 'exg ${m68k_address_register(upper)},${m68k_address_register(lower)}' }
		0x0188 { return 'exg d${upper},${m68k_address_register(lower)}' }
		else { return none }
	}
}

fn (mut d M68kDecoder) decode_multiply_divide(name string, opcode u16) ?string {
	src := d.operand(opcode, .word, m68k_ea_data)?
	return '${name}.w ${src},d${m68k_upper_register(opcode)}'
}

// decode_register_and_ea handles the `op <ea>,Dn` / `op Dn,<ea>` pair shared by ADD, SUB, AND and OR.
fn (mut d M68kDecoder) decode_register_and_ea(name string, opcode u16, source_allowed u16) ?string {
	size := m68k_size(opcode >> 6)?
	data := 'd${m68k_upper_register(opcode)}'
	if opcode & 0x0100 == 0 {
		src := d.operand(opcode, size, source_allowed)?
		return '${name}${size.suffix()} ${src},${data}'
	}
	dst := d.operand(opcode, size, m68k_ea_memory_alterable)?
	return '${name}${size.suffix()} ${data},${dst}'
}

// decode_address_arithmetic handles ADDA, SUBA and CMPA.
fn (mut d M68kDecoder) decode_address_arithmetic(name string, opcode u16) ?string {
	size := m68k_word_or_long(opcode & 0x0100 != 0)
	src := d.operand(opcode, size, m68k_ea_all)?
	return '${name}a${size.suffix()} ${src},${m68k_address_register(m68k_upper_register(opcode))}'
}

// decode_add_subtract handles lines 9 and D: ADD/ADDA/ADDX and SUB/SUBA/SUBX.
fn (mut d M68kDecoder) decode_add_subtract(name string, opcode u16) ?string {
	if opcode & 0x00c0 == 0x00c0 {
		return d.decode_address_arithmetic(name, opcode)
	}
	if opcode & 0x0100 != 0 && m68k_ea_mode(opcode) < 2 {
		size := m68k_size(opcode >> 6)?
		return m68k_register_pair('${name}x${size.suffix()}', opcode)
	}
	return d.decode_register_and_ea(name, opcode, m68k_ea_all)
}

// decode_compare_eor handles line B: CMP, CMPA, CMPM and EOR.
fn (mut d M68kDecoder) decode_compare_eor(opcode u16) ?string {
	if opcode & 0x00c0 == 0x00c0 {
		return d.decode_address_arithmetic('cmp', opcode)
	}
	size := m68k_size(opcode >> 6)?
	upper := m68k_upper_register(opcode)
	if opcode & 0x0100 == 0 {
		src := d.operand(opcode, size, m68k_ea_all)?
		return 'cmp${size.suffix()} ${src},d${upper}'
	}
	if m68k_ea_mode(opcode) == 1 {
		src := m68k_address_register(m68k_ea_register(opcode))
		return 'cmpm${size.suffix()} (${src})+,(${m68k_address_register(upper)})+'
	}
	dst := d.operand(opcode, size, m68k_ea_data_alterable)?
	return 'eor${size.suffix()} d${upper},${dst}'
}

// decode_shift handles line E: ASL/ASR, LSL/LSR, ROXL/ROXR and ROL/ROR.
fn (mut d M68kDecoder) decode_shift(opcode u16) ?string {
	direction := if opcode & 0x0100 == 0 { 'r' } else { 'l' }
	if opcode & 0x00c0 == 0x00c0 {
		if opcode & 0x0800 != 0 {
			return none
		}
		dst := d.operand(opcode, .word, m68k_ea_memory_alterable)?
		return '${m68k_shift_names[(opcode >> 9) & 3]}${direction}.w ${dst}'
	}
	size := m68k_size(opcode >> 6)?
	name := m68k_shift_names[(opcode >> 3) & 3] + direction + size.suffix()
	count := if opcode & 0x0020 == 0 {
		'#${m68k_quick_value(opcode)}'
	} else {
		'd${m68k_upper_register(opcode)}'
	}
	return '${name} ${count},d${m68k_ea_register(opcode)}'
}
