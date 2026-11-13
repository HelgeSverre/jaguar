module jagkit

import debug
import risc

// Every combination of instruction, size and addressing mode the 68000
// assembler accepts must read back, through the emulator's disassembler,
// as the same operation on the same operands. A combination the processor
// does not have must be refused, not encoded as something else.

// read_back disassembles a piece of code.
fn read_back(code []u8, origin u32) []string {
	read := fn [code, origin] (addr u32) u16 {
		i := int(addr - origin)
		if i < 0 || i + 1 >= code.len {
			return 0
		}
		return (u16(code[i]) << 8) | code[i + 1]
	}
	mut out := []string{}
	mut pc := origin
	for pc < origin + u32(code.len) {
		text, n := debug.disassemble_m68k(read, pc)
		out << text
		pc += n
	}
	return out
}

struct Operand {
	ea   Ea
	text string // as the disassembler writes it; immediates are compared by value
}

fn operands(size Size, value i64) []Operand {
	hex := match size {
		.b { '#$${value:02x}' }
		.w { '#$${value:04x}' }
		.l { '#$${value:08x}' }
	}

	return [
		Operand{d3, 'd3'},
		Operand{a2, 'a2'},
		Operand{ind(a1), '(a1)'},
		Operand{inc(a1), '(a1)+'},
		Operand{dec(a1), '-(a1)'},
		Operand{at(8, a1), '$8(a1)'},
		Operand{idx(2, a1, d4), '$2(a1,d4.l)'},
		Operand{abs(0x100000), '$00100000.l'},
		Operand{imm(value), hex},
	]
}

// family is the operation a mnemonic belongs to: `addq`, `addi` and `adda`
// are all `add`.
fn family(mnemonic string) string {
	for base in ['move', 'add', 'sub', 'cmp', 'and', 'or', 'eor'] {
		if mnemonic in [base, base + 'i', base + 'q', base + 'a', base + 'm'] {
			return base
		}
	}
	return mnemonic
}

// number reads an immediate as the disassembler writes it: `#5`, `#-1`,
// `#$0005`.
fn number(text string) ?i64 {
	if !text.starts_with('#') {
		return none
	}
	body := text[1..]
	if body.starts_with('$') {
		return i64(('0x' + body[1..]).u64())
	}
	return body.i64()
}

// same_operand compares what was asked for with what came back.
fn same_operand(asked string, got string, size Size) bool {
	if asked == got {
		return true
	}
	a := number(asked) or { return false }
	g := number(got) or { return false }
	mask := match size {
		.b { i64(0xff) }
		.w { i64(0xffff) }
		.l { i64(0xffff_ffff) }
	}

	return a & mask == g & mask
}

struct Tally {
mut:
	accepted int
	refused  int
	refusals []string
	wrong    []string
}

// check assembles one instruction and compares its disassembly.
fn (mut t Tally) check(name string, size Size, asked []string, emit fn (mut m M68k)) {
	mut m := new_m68k(0x4000)
	emit(mut m)
	code := m.assemble() or {
		t.refused++
		t.refusals << '${name}.${['b', 'w', 'l'][int(size)]} ${asked.join(',')}'
		return
	}
	lines := read_back(code, 0x4000)
	suffix := ['b', 'w', 'l'][int(size)]
	wanted := '${name}.${suffix} ${asked.join(',')}'
	if lines.len != 1 {
		t.wrong << '${wanted}: read back as ${lines}'
		return
	}
	mnemonic := lines[0].all_before(' ')
	got := lines[0].all_after(' ').split(',')
	// A comma inside brackets belongs to an indexed operand.
	mut joined := []string{}
	for part in got {
		if joined.len > 0 && joined.last().contains('(') && !joined.last().contains(')') {
			joined[joined.len - 1] += ',' + part
		} else {
			joined << part
		}
	}
	mut same := family(mnemonic.all_before('.')) == name && joined.len == asked.len
		&& (mnemonic.all_after('.') == suffix || !mnemonic.contains('.'))
	if same {
		for i, a in asked {
			same = same && same_operand(a, joined[i], size)
		}
	}
	if same {
		t.accepted++
	} else {
		t.wrong << '${wanted}: read back as `${lines[0]}`'
	}
}

fn test_every_accepted_combination_reads_back() {
	mut t := Tally{}
	sizes := [Size.b, .w, .l]
	for size in sizes {
		for value in [i64(5), 0x12] {
			modes := operands(size, value)
			for src in modes {
				for dst in modes {
					asked := [src.text, dst.text]
					t.check('move', size, asked, fn [size, src, dst] (mut m M68k) {
						m.move(size, src.ea, dst.ea)
					})
					t.check('add', size, asked, fn [size, src, dst] (mut m M68k) {
						m.add(size, src.ea, dst.ea)
					})
					t.check('sub', size, asked, fn [size, src, dst] (mut m M68k) {
						m.sub(size, src.ea, dst.ea)
					})
					t.check('cmp', size, asked, fn [size, src, dst] (mut m M68k) {
						m.cmp(size, src.ea, dst.ea)
					})
					t.check('and', size, asked, fn [size, src, dst] (mut m M68k) {
						m.and(size, src.ea, dst.ea)
					})
					t.check('or', size, asked, fn [size, src, dst] (mut m M68k) {
						m.orr(size, src.ea, dst.ea)
					})
					t.check('eor', size, asked, fn [size, src, dst] (mut m M68k) {
						m.eor(size, src.ea, dst.ea)
					})
				}
			}
			for dst in modes {
				asked := [dst.text]
				t.check('clr', size, asked, fn [size, dst] (mut m M68k) {
					m.clr(size, dst.ea)
				})
				t.check('neg', size, asked, fn [size, dst] (mut m M68k) {
					m.neg(size, dst.ea)
				})
				t.check('not', size, asked, fn [size, dst] (mut m M68k) {
					m.not(size, dst.ea)
				})
				t.check('tst', size, asked, fn [size, dst] (mut m M68k) {
					m.tst(size, dst.ea)
				})
				for count in [Operand{imm(3), '#3'}, Operand{d5, 'd5'}] {
					shifted := [count.text, dst.text]
					t.check('asl', size, shifted, fn [size, count, dst] (mut m M68k) {
						m.asl(size, count.ea, dst.ea)
					})
					t.check('lsr', size, shifted, fn [size, count, dst] (mut m M68k) {
						m.lsr(size, count.ea, dst.ea)
					})
					t.check('ror', size, shifted, fn [size, count, dst] (mut m M68k) {
						m.ror(size, count.ea, dst.ea)
					})
				}
			}
		}
	}
	for line in t.wrong {
		println(line)
	}
	println('accepted ${t.accepted}, refused ${t.refused}, wrong ${t.wrong.len}')
	assert t.wrong.len == 0
	assert t.accepted > 500
}

// The forms of the two-operand instructions, word-sized: a row a source, a
// column a destination, a letter an instruction that has the form (Move,
// Add, Sub, Cmp, And, Or, Eor). This is the 68000's own table.
const forms = {
	'd3':          'MASCAOE MASC... MAS.AOE MAS.AOE MAS.AOE MAS.AOE MAS.AOE MAS.AOE .......'
	'a2':          'MASC... MASC... M...... M...... M...... M...... M...... M...... .......'
	'(a1)':        'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'(a1)+':       'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'-(a1)':       'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'$8(a1)':      'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'$2(a1,d4.l)': 'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'$00100000.l': 'MASCAO. MASC... M...... M...... M...... M...... M...... M...... .......'
	'#$0012':      'MASCAOE MASC... MASCAOE MASCAOE MASCAOE MASCAOE MASCAOE MASCAOE .......'
}

fn test_the_accepted_forms_are_the_processors() {
	mut t := Tally{}
	modes := operands(.w, 0x12)
	for src in modes {
		mut cells := []string{}
		for dst in modes {
			mut cell := ''
			for name in ['move', 'add', 'sub', 'cmp', 'and', 'or', 'eor'] {
				before := t.refused
				t.check(name, .w, [src.text, dst.text], fn [name, src, dst] (mut m M68k) {
					match name {
						'move' { m.move(.w, src.ea, dst.ea) }
						'add' { m.add(.w, src.ea, dst.ea) }
						'sub' { m.sub(.w, src.ea, dst.ea) }
						'cmp' { m.cmp(.w, src.ea, dst.ea) }
						'and' { m.and(.w, src.ea, dst.ea) }
						'or' { m.orr(.w, src.ea, dst.ea) }
						else { m.eor(.w, src.ea, dst.ea) }
					}
				})
				cell += if t.refused == before { name[..1].to_upper() } else { '.' }
			}
			cells << cell
		}
		assert cells.join(' ') == forms[src.text], 'from ${src.text}'
	}
	assert t.wrong.len == 0
}

// The instructions with one flexible operand.
fn test_single_operand_forms_read_back() {
	mut t := Tally{}
	for mode in operands(.w, 0x12) {
		t.check('mulu', .w, [mode.text, 'd6'], fn [mode] (mut m M68k) {
			m.mulu(mode.ea, d6)
		})
		t.check('muls', .w, [mode.text, 'd6'], fn [mode] (mut m M68k) {
			m.muls(mode.ea, d6)
		})
		t.check('divu', .w, [mode.text, 'd6'], fn [mode] (mut m M68k) {
			m.divu(mode.ea, d6)
		})
		t.check('lea', .l, [mode.text, 'a5'], fn [mode] (mut m M68k) {
			m.lea(mode.ea, a5)
		})
		t.check('jsr', .l, [mode.text], fn [mode] (mut m M68k) {
			m.jsr(mode.ea)
		})
		t.check('jmp', .l, [mode.text], fn [mode] (mut m M68k) {
			m.jmp(mode.ea)
		})
		t.check('btst', .b, ['#3', mode.text], fn [mode] (mut m M68k) {
			m.btst(3, mode.ea)
		})
		t.check('bset', .b, ['#3', mode.text], fn [mode] (mut m M68k) {
			m.bset(3, mode.ea)
		})
		t.check('bclr', .b, ['#3', mode.text], fn [mode] (mut m M68k) {
			m.bclr(3, mode.ea)
		})
	}
	for line in t.wrong {
		println(line)
	}
	println('accepted ${t.accepted}, refused ${t.refused}: ${t.refusals}')
	assert t.wrong.len == 0
}

// The quick values of the RISC instructions are packed in different ways
// (1..32 with 32 as zero, a left shift as 32 - n, a signed five bits); each
// must read back as the number asked for, in every register.
fn test_risc_quick_values_read_back() {
	mut g := new_risc(gpu_ram)
	mut wanted := []string{}
	for n in 1 .. 33 {
		reg := unsafe { Reg(n - 1) }
		name := 'r${n - 1}'
		g.addq(n, reg)
		wanted << 'addq #${n},${name}'
		g.subqt(n, reg)
		wanted << 'subqt #${n},${name}'
		g.shlq(n, reg)
		wanted << 'shlq #${n},${name}'
		g.shrq(n, reg)
		wanted << 'shrq #${n},${name}'
		g.sharq(n, reg)
		wanted << 'sharq #${n},${name}'
		g.rorq(n, reg)
		wanted << 'rorq #${n},${name}'
		g.moveq(n - 1, reg)
		wanted << 'moveq #${n - 1},${name}'
		g.cmpq(n - 17, reg)
		wanted << 'cmpq #${n - 17},${name}'
		g.bset(n - 1, reg)
		wanted << 'bset #${n - 1},${name}'
		if n <= 32 {
			g.load_r14(n * 4, reg)
			wanted << 'load (r14+${n * 4}),${name}'
			g.store_r14(reg, n * 4)
			wanted << 'store ${name},(r14+${n * 4})'
		}
	}
	code := g.assemble()!
	read := fn [code] (addr u32) u16 {
		i := int(addr - gpu_ram)
		return (u16(code[i]) << 8) | code[i + 1]
	}
	mut pc := gpu_ram
	for line in wanted {
		text, n := debug.disassemble_risc(read, risc.Variant.gpu, pc)
		assert text == line
		pc += n
	}
}
