module m68k

// Op names one instruction handler. Every 16-bit opcode maps to exactly one
// Op; encodings the MC68000 does not implement map to `illegal`, `line_a`
// or `line_f` and raise the corresponding exception.
enum Op as u8 {
	illegal
	line_a
	line_f
	ori
	andi
	subi
	addi
	eori
	cmpi
	logic_ccr
	logic_sr
	bit_dynamic
	bit_static
	movep
	move_b
	move_w
	move_l
	movea_w
	movea_l
	negx
	clr
	neg
	not
	tst
	tas
	nbcd
	move_from_sr
	move_to_ccr
	move_to_sr
	chk
	lea
	pea
	swap
	ext
	movem_to_mem
	movem_to_reg
	trap
	link
	unlk
	move_to_usp
	move_from_usp
	reset
	nop
	stop
	rte
	rts
	trapv
	rtr
	jsr
	jmp
	addq
	subq
	scc
	dbcc
	bsr
	bcc
	moveq
	or_to_reg
	or_to_mem
	and_to_reg
	and_to_mem
	add_to_reg
	add_to_mem
	sub_to_reg
	sub_to_mem
	cmp
	eor
	adda
	suba
	cmpa
	cmpm
	addx
	subx
	abcd
	sbcd
	mulu
	muls
	divu
	divs
	exg
	shift_reg
	shift_mem
}

// Addressing-mode categories as bit sets: bit n stands for mode n (0..6) or
// for mode 7 with register field n-7. They are plain literals because the
// decode table below is built during constant initialisation.
const ea_postinc = u16(0x008)
const ea_predec = u16(0x010)
const ea_imm = u16(0x800)
const ea_all = u16(0xfff)
const ea_data = u16(0xffd)
const ea_control = u16(0x7e4)
const ea_alterable = u16(0x1ff)
const ea_data_alterable = u16(0x1fd)
const ea_memory_alterable = u16(0x1fc)
const ea_control_alterable = u16(0x1e4)

// op_table maps every opcode to its handler. It is built once at start-up.
const op_table = build_op_table()

fn build_op_table() []Op {
	mut table := []Op{len: 0x10000}
	for opcode in 0 .. 0x10000 {
		table[opcode] = decode(u32(opcode))
	}
	return table
}

// ea_ok reports whether the addressing mode in the low six bits of `opcode`
// exists and belongs to the `allowed` category.
fn ea_ok(opcode u32, allowed u16) bool {
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode < 7 {
		return (u16(1) << mode) & allowed != 0
	}
	return reg <= 4 && (u16(0x80) << reg) & allowed != 0
}

// when returns `op` if the opcode's addressing mode is in `allowed`, and
// `illegal` otherwise.
fn when(opcode u32, allowed u16, op Op) Op {
	return if ea_ok(opcode, allowed) { op } else { Op.illegal }
}

// decode classifies one opcode.
fn decode(opcode u32) Op {
	return match opcode >> 12 {
		0x0 {
			decode_immediate_and_bit(opcode)
		}
		0x1 {
			decode_move(opcode, .move_b, .illegal)
		}
		0x2 {
			decode_move(opcode, .move_l, .movea_l)
		}
		0x3 {
			decode_move(opcode, .move_w, .movea_w)
		}
		0x4 {
			decode_misc(opcode)
		}
		0x5 {
			decode_quick(opcode)
		}
		0x6 {
			decode_branch(opcode)
		}
		0x7 {
			if opcode & 0x0100 == 0 {
				Op.moveq
			} else {
				Op.illegal
			}
		}
		0x8 {
			decode_or_div(opcode)
		}
		0x9 {
			decode_add_sub(opcode, .sub_to_reg, .sub_to_mem, .suba, .subx)
		}
		0xa {
			Op.line_a
		}
		0xb {
			decode_cmp_eor(opcode)
		}
		0xc {
			decode_and_mul(opcode)
		}
		0xd {
			decode_add_sub(opcode, .add_to_reg, .add_to_mem, .adda, .addx)
		}
		0xe {
			decode_shift(opcode)
		}
		else {
			Op.line_f
		}
	}
}

fn decode_immediate_and_bit(opcode u32) Op {
	mode := (opcode >> 3) & 7
	kind := (opcode >> 6) & 3
	if opcode & 0x0100 != 0 {
		if mode == mode_an {
			return .movep
		}
		// BTST accepts every data mode; the modifying forms need a
		// data-alterable destination.
		return when(opcode, if kind == 0 { ea_data } else { ea_data_alterable }, .bit_dynamic)
	}
	group := (opcode >> 9) & 7
	if group == 4 {
		return when(opcode, if kind == 0 { ea_data & ~ea_imm } else { ea_data_alterable },
			.bit_static)
	}
	if group == 7 {
		return .illegal
	}
	if opcode & 0xff == 0x3c {
		return if group in [u32(0), 1, 5] { Op.logic_ccr } else { Op.illegal }
	}
	if opcode & 0xff == 0x7c {
		return if group in [u32(0), 1, 5] { Op.logic_sr } else { Op.illegal }
	}
	if kind == 3 {
		return .illegal
	}
	op := match group {
		0 { Op.ori }
		1 { Op.andi }
		2 { Op.subi }
		3 { Op.addi }
		5 { Op.eori }
		else { Op.cmpi }
	}

	return when(opcode, ea_data_alterable, op)
}

fn decode_move(opcode u32, move Op, movea Op) Op {
	dst_mode := (opcode >> 6) & 7
	dst_reg := (opcode >> 9) & 7
	// A byte move cannot use an address register on either side.
	src_allowed := if movea == .illegal { ea_data } else { ea_all }
	if !ea_ok(opcode, src_allowed) {
		return .illegal
	}
	if dst_mode == mode_an {
		return movea
	}
	return when((dst_mode << 3) | dst_reg, ea_data_alterable, move)
}

fn decode_misc(opcode u32) Op {
	mode := (opcode >> 3) & 7
	if opcode & 0x0100 != 0 {
		return match (opcode >> 6) & 3 {
			2 { when(opcode, ea_data, .chk) }
			3 { when(opcode, ea_control, .lea) }
			else { Op.illegal }
		}
	}
	kind := (opcode >> 6) & 3
	match (opcode >> 9) & 7 {
		0 {
			return when(opcode, ea_data_alterable,
				if kind == 3 { Op.move_from_sr } else { Op.negx })
		}
		1 {
			return if kind == 3 { Op.illegal } else { when(opcode, ea_data_alterable, .clr) }
		}
		2 {
			return if kind == 3 {
				when(opcode, ea_data, .move_to_ccr)
			} else {
				when(opcode, ea_data_alterable, .neg)
			}
		}
		3 {
			return if kind == 3 {
				when(opcode, ea_data, .move_to_sr)
			} else {
				when(opcode, ea_data_alterable, .not)
			}
		}
		4 {
			return match kind {
				0 {
					when(opcode, ea_data_alterable, .nbcd)
				}
				1 {
					if mode == mode_dn {
						Op.swap
					} else {
						when(opcode, ea_control, .pea)
					}
				}
				else {
					if mode == mode_dn {
						Op.ext
					} else {
						when(opcode, ea_control_alterable | ea_predec, .movem_to_mem)
					}
				}
			}
		}
		5 {
			return when(opcode, ea_data_alterable, if kind == 3 { Op.tas } else { Op.tst })
		}
		6 {
			return if kind >= 2 {
				when(opcode, ea_control | ea_postinc, .movem_to_reg)
			} else {
				Op.illegal
			}
		}
		else {
			return decode_control(opcode)
		}
	}
}

// decode_control classifies the 0x4E00..0x4EFF block.
fn decode_control(opcode u32) Op {
	match (opcode >> 6) & 3 {
		0 {
			return .illegal
		}
		1 {
			match (opcode >> 3) & 7 {
				0, 1 { return .trap }
				2 { return .link }
				3 { return .unlk }
				4 { return .move_to_usp }
				5 { return .move_from_usp }
				6 {}
				else { return .illegal }
			}

			return match opcode & 7 {
				0 { Op.reset }
				1 { Op.nop }
				2 { Op.stop }
				3 { Op.rte }
				5 { Op.rts }
				6 { Op.trapv }
				7 { Op.rtr }
				else { Op.illegal }
			}
		}
		2 {
			return when(opcode, ea_control, .jsr)
		}
		else {
			return when(opcode, ea_control, .jmp)
		}
	}
}

fn decode_quick(opcode u32) Op {
	mode := (opcode >> 3) & 7
	if (opcode >> 6) & 3 == 3 {
		return if mode == mode_an { Op.dbcc } else { when(opcode, ea_data_alterable, .scc) }
	}
	// Byte arithmetic on an address register does not exist.
	allowed := if (opcode >> 6) & 3 == 0 { ea_data_alterable } else { ea_alterable }
	return when(opcode, allowed, if opcode & 0x0100 == 0 { Op.addq } else { Op.subq })
}

fn decode_branch(opcode u32) Op {
	return match (opcode >> 8) & 15 {
		1 { Op.bsr }
		else { Op.bcc }
	}
}

fn decode_or_div(opcode u32) Op {
	mode := (opcode >> 3) & 7
	return match (opcode >> 6) & 7 {
		0, 1, 2 {
			when(opcode, ea_data, .or_to_reg)
		}
		3 {
			when(opcode, ea_data, .divu)
		}
		7 {
			when(opcode, ea_data, .divs)
		}
		4 {
			if mode <= mode_an {
				Op.sbcd
			} else {
				when(opcode, ea_memory_alterable, .or_to_mem)
			}
		}
		else {
			when(opcode, ea_memory_alterable, .or_to_mem)
		}
	}
}

fn decode_add_sub(opcode u32, to_reg Op, to_mem Op, to_an Op, extended Op) Op {
	mode := (opcode >> 3) & 7
	opmode := (opcode >> 6) & 7
	if opmode == 3 || opmode == 7 {
		return when(opcode, ea_all, to_an)
	}
	if opmode < 3 {
		return when(opcode, if opmode == 0 { ea_data } else { ea_all }, to_reg)
	}
	if mode <= mode_an {
		return extended
	}
	return when(opcode, ea_memory_alterable, to_mem)
}

fn decode_cmp_eor(opcode u32) Op {
	mode := (opcode >> 3) & 7
	opmode := (opcode >> 6) & 7
	if opmode == 3 || opmode == 7 {
		return when(opcode, ea_all, .cmpa)
	}
	if opmode < 3 {
		return when(opcode, if opmode == 0 { ea_data } else { ea_all }, .cmp)
	}
	if mode == mode_an {
		return .cmpm
	}
	return when(opcode, ea_data_alterable, .eor)
}

fn decode_and_mul(opcode u32) Op {
	mode := (opcode >> 3) & 7
	return match (opcode >> 6) & 7 {
		0, 1, 2 {
			when(opcode, ea_data, .and_to_reg)
		}
		3 {
			when(opcode, ea_data, .mulu)
		}
		7 {
			when(opcode, ea_data, .muls)
		}
		4 {
			if mode <= mode_an {
				Op.abcd
			} else {
				when(opcode, ea_memory_alterable, .and_to_mem)
			}
		}
		5 {
			if mode <= mode_an {
				Op.exg
			} else {
				when(opcode, ea_memory_alterable, .and_to_mem)
			}
		}
		else {
			if mode == mode_an {
				Op.exg
			} else {
				when(opcode, ea_memory_alterable, .and_to_mem)
			}
		}
	}
}

fn decode_shift(opcode u32) Op {
	if (opcode >> 6) & 3 != 3 {
		return .shift_reg
	}
	// Memory shifts encode the operation in bits 10..9; bit 11 set is a
	// 68020 bit-field instruction.
	if opcode & 0x0800 != 0 {
		return .illegal
	}
	return when(opcode, ea_memory_alterable, .shift_mem)
}
