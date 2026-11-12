module debug

import risc
import machine

const gpu_mnemonics = ['add', 'addc', 'addq', 'addqt', 'sub', 'subc', 'subq', 'subqt', 'neg', 'and',
	'or', 'xor', 'not', 'btst', 'bset', 'bclr', 'mult', 'imult', 'imultn', 'resmac', 'imacn', 'div',
	'abs', 'sh', 'shlq', 'shrq', 'sha', 'sharq', 'ror', 'rorq', 'cmp', 'cmpq', 'sat8', 'sat16',
	'move', 'moveq', 'moveta', 'movefa', 'movei', 'loadb', 'loadw', 'load', 'loadp', 'load', 'load',
	'storeb', 'storew', 'store', 'storep', 'store', 'store', 'move', 'jump', 'jr', 'mmult', 'mtoi',
	'normi', 'nop', 'load', 'load', 'store', 'store', 'sat24', 'pack']

// Shape is the operand layout of an instruction.
enum Shape {
	reg_reg    // op Rm,Rn
	quick_reg  // op #n,Rn with 0 meaning 32
	imm_reg    // op #n,Rn with the raw field
	signed_reg // op #n,Rn sign-extended
	shift_left // shlq: 32 - n
	reg_only   // op Rn
	load_ind   // op (Rm),Rn
	store_ind  // op Rn,(Rm)
	load_disp  // op (R14/15+n),Rn
	store_disp
	load_idx // op (R14/15+Rm),Rn
	store_idx
	move_pc
	jump
	jr
	movei
	nop
}

fn shape_of(opcode u32, variant risc.Variant) Shape {
	return match opcode {
		2, 3, 6, 7, 25, 27, 29 {
			Shape.quick_reg
		}
		13, 14, 15, 35 {
			Shape.imm_reg
		}
		31 {
			Shape.signed_reg
		}
		24 {
			Shape.shift_left
		}
		8, 12, 19, 22, 33, 62 {
			Shape.reg_only
		}
		32, 63 {
			if variant == .gpu {
				Shape.reg_only
			} else {
				Shape.quick_reg
			}
		}
		42 {
			if variant == .gpu {
				Shape.load_ind
			} else {
				Shape.reg_only
			}
		}
		48 {
			if variant == .gpu {
				Shape.store_ind
			} else {
				Shape.reg_only
			}
		}
		39, 40, 41 {
			Shape.load_ind
		}
		45, 46, 47 {
			Shape.store_ind
		}
		43, 44 {
			Shape.load_disp
		}
		49, 50 {
			Shape.store_disp
		}
		58, 59 {
			Shape.load_idx
		}
		60, 61 {
			Shape.store_idx
		}
		51 {
			Shape.move_pc
		}
		52 {
			Shape.jump
		}
		53 {
			Shape.jr
		}
		38 {
			Shape.movei
		}
		57 {
			Shape.nop
		}
		else {
			Shape.reg_reg
		}
	}
}

fn mnemonic(opcode u32, variant risc.Variant, src u32) string {
	if variant == .dsp {
		match opcode {
			32 { return 'subqmod' }
			33 { return 'sat16s' }
			42 { return 'sat32s' }
			48 { return 'mirror' }
			62 { return 'illegal' }
			63 { return 'addqmod' }
			else {}
		}
	} else if opcode == 63 && src != 0 {
		return 'unpack'
	}
	return gpu_mnemonics[opcode]
}

fn condition_name(code u32) string {
	return match code {
		0x00 { '' }
		0x01 { 'ne,' }
		0x02 { 'eq,' }
		0x04 { 'cc,' }
		0x05 { 'hi,' }
		0x08 { 'cs,' }
		0x14 { 'pl,' }
		0x18 { 'mi,' }
		else { '${code:02x},' }
	}
}

// signed5 sign-extends a five-bit field.
fn signed5(field u32) int {
	return if field >= 16 { int(field) - 32 } else { int(field) }
}

// disassemble_risc decodes one GPU or DSP instruction at `addr` and returns
// its text and its length in bytes.
pub fn disassemble_risc(read WordReader, variant risc.Variant, addr u32) (string, u32) {
	word := u32(read(addr))
	opcode := word >> 10
	src := (word >> 5) & 31
	dst := word & 31
	name := mnemonic(opcode, variant, src)
	base := if opcode in [u32(43), 49, 58, 60] { 14 } else { 15 }
	quick := if src == 0 { u32(32) } else { src }
	text := match shape_of(opcode, variant) {
		.reg_reg {
			'${name} r${src},r${dst}'
		}
		.quick_reg {
			'${name} #${quick},r${dst}'
		}
		.imm_reg {
			'${name} #${src},r${dst}'
		}
		.signed_reg {
			'${name} #${signed5(src)},r${dst}'
		}
		.shift_left {
			'${name} #${32 - src},r${dst}'
		}
		.reg_only {
			'${name} r${dst}'
		}
		.load_ind {
			'${name} (r${src}),r${dst}'
		}
		.store_ind {
			'${name} r${dst},(r${src})'
		}
		.load_disp {
			'${name} (r${base}+${quick * 4}),r${dst}'
		}
		.store_disp {
			'${name} r${dst},(r${base}+${quick * 4})'
		}
		.load_idx {
			'${name} (r${base}+r${src}),r${dst}'
		}
		.store_idx {
			'${name} r${dst},(r${base}+r${src})'
		}
		.move_pc {
			'move pc,r${dst}'
		}
		.jump {
			'jump ${condition_name(dst)}(r${src})'
		}
		.jr {
			target := u32(int(addr) + 2 + signed5(src) * 2)
			'jr ${condition_name(dst)}${target:06x}'
		}
		.movei {
			low := u32(read(addr + 2))
			high := u32(read(addr + 4))
			'movei #${(high << 16) | low:08x},r${dst}'
		}
		.nop {
			'nop'
		}
	}

	return text, if opcode == 38 {
		u32(6)
	} else {
		u32(2)
	}
}

// risc_listing disassembles `count` instructions starting at `addr`.
pub fn risc_listing(m &machine.Machine, variant risc.Variant, addr u32, count int) string {
	read := word_reader(m)
	mut lines := []string{}
	mut pc := addr
	for _ in 0 .. count {
		text, length := disassemble_risc(read, variant, pc)
		lines << '${pc:06x}  ${text}'
		pc += length
	}
	return lines.join('\n') + '\n'
}

// hex_dump formats `count` bytes of memory as 16-bit words.
pub fn hex_dump(m &machine.Machine, addr u32, count u32) string {
	mut lines := []string{}
	for row := u32(0); row < count; row += 16 {
		mut words := []string{}
		for i := u32(0); i < 16 && row + i < count; i += 2 {
			words << '${m.peek8(addr + row + i):02x}${m.peek8(addr + row + i + 1):02x}'
		}
		lines << '${addr + row:06x}  ${words.join(' ')}'
	}
	return lines.join('\n') + '\n'
}

// registers_risc formats the active register bank of a RISC processor.
pub fn registers_risc(c &risc.Risc) string {
	mut lines := []string{}
	for row in 0 .. 4 {
		mut parts := []string{}
		for i in row * 8 .. row * 8 + 8 {
			parts << 'r${i}=${c.regs[c.bank + u32(i)]:08x}'
		}
		lines << parts.join(' ')
	}
	return lines.join('\n') + '\n'
}
