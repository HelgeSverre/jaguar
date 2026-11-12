module m68k

import hwtypes

// op_move executes MOVE `<ea>,<ea>` for one operand size.
@[direct_array_access]
fn (mut c Cpu) op_move(mut bus hwtypes.Bus, size Size) {
	opcode := u32(c.ir)
	src_mode := (opcode >> 3) & 7
	src_reg := opcode & 7
	src := c.read_ea(mut bus, src_mode, src_reg, size)
	if c.aborted {
		return
	}
	dst_mode := (opcode >> 6) & 7
	dst_reg := (opcode >> 9) & 7
	if dst_mode == mode_dn {
		c.set_d(dst_reg, size, src)
		c.set_logic_flags(src, size)
		c.cycles += 4
		return
	}
	addr := c.ea_addr(mut bus, dst_mode, dst_reg, size)
	if size != .byte && addr & 1 != 0 {
		c.move_write_fault(mut bus, addr, src, size)
		return
	}
	c.set_logic_flags(src, size)
	if dst_mode == mode_predec {
		c.store_low_first(mut bus, addr, size, src)
	} else {
		c.store(mut bus, addr, size, src)
	}
	c.cycles += 4
}

// move_write_fault raises the address error for a MOVE whose destination
// address is odd.
fn (mut c Cpu) move_write_fault(mut bus hwtypes.Bus, addr u32, src u32, size Size) {
	c.set_logic_flags(src, size)
	c.address_error(mut bus, addr, .write, c.pc)
}

// op_movea executes MOVEA: the source is sign extended to 32 bits and no
// condition codes change.
@[direct_array_access]
fn (mut c Cpu) op_movea(mut bus hwtypes.Bus, size Size) {
	opcode := u32(c.ir)
	src := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, size)
	if c.aborted {
		return
	}
	c.a[(opcode >> 9) & 7] = if size == .word { hwtypes.sext16(src) } else { src }
	c.cycles += 4
}

// op_moveq executes MOVEQ.
@[direct_array_access]
fn (mut c Cpu) op_moveq() {
	opcode := u32(c.ir)
	value := hwtypes.sext8(opcode)
	c.d[(opcode >> 9) & 7] = value
	c.set_logic_flags(value, .long)
	c.cycles += 4
}

// op_lea executes LEA.
@[direct_array_access]
fn (mut c Cpu) op_lea(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	c.a[(opcode >> 9) & 7] = c.ea_addr(mut bus, mode, reg, .long)
	c.cycles += 4 + index_penalty(mode, reg)
}

// op_pea executes PEA.
fn (mut c Cpu) op_pea(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	addr := c.ea_addr(mut bus, mode, reg, .long)
	c.cycles += index_penalty(mode, reg)
	if c.stack_fault(mut bus, .write) {
		return
	}
	c.push32(mut bus, addr)
	c.cycles += 4
}

// index_penalty is the extra delay LEA and PEA spend on an indexed mode.
@[inline]
fn index_penalty(mode u32, reg u32) u64 {
	indexed := mode == mode_index || (mode == mode_other && reg == other_pc_index)
	return if indexed { u64(2) } else { u64(0) }
}

// op_exg executes EXG between data and/or address registers.
@[direct_array_access]
fn (mut c Cpu) op_exg() {
	opcode := u32(c.ir)
	mut rx := (opcode >> 9) & 7
	mut ry := opcode & 7
	match (opcode >> 3) & 0x1f {
		0x09 {
			rx += 8
			ry += 8
		}
		0x11 {
			ry += 8
		}
		else {}
	}

	tmp := c.reg_value(rx)
	c.set_reg(rx, c.reg_value(ry))
	c.set_reg(ry, tmp)
	c.cycles += 6
}

// op_swap executes SWAP.
@[direct_array_access]
fn (mut c Cpu) op_swap() {
	reg := u32(c.ir) & 7
	value := (c.d[reg] << 16) | (c.d[reg] >> 16)
	c.d[reg] = value
	c.set_logic_flags(value, .long)
	c.cycles += 4
}

// op_ext executes EXT.W and EXT.L.
@[direct_array_access]
fn (mut c Cpu) op_ext() {
	opcode := u32(c.ir)
	reg := opcode & 7
	if opcode & 0x0040 == 0 {
		value := hwtypes.sext8(c.d[reg])
		c.set_d(reg, .word, value)
		c.set_logic_flags(value, .word)
	} else {
		value := hwtypes.sext16(c.d[reg])
		c.d[reg] = value
		c.set_logic_flags(value, .long)
	}
	c.cycles += 4
}

// op_move_to_usp executes the privileged MOVE An,USP.
@[direct_array_access]
fn (mut c Cpu) op_move_to_usp(mut bus hwtypes.Bus) {
	if c.require_supervisor(mut bus) {
		c.usp = c.a[c.ir & 7]
		c.cycles += 4
	}
}

// op_move_from_usp executes the privileged MOVE USP,An.
@[direct_array_access]
fn (mut c Cpu) op_move_from_usp(mut bus hwtypes.Bus) {
	if c.require_supervisor(mut bus) {
		c.a[c.ir & 7] = c.usp
		c.cycles += 4
	}
}

// op_movep executes MOVEP: a word or long is transferred to or from
// alternate bytes of memory, high byte first.
@[direct_array_access]
fn (mut c Cpu) op_movep(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	dn := (opcode >> 9) & 7
	bytes := if opcode & 0x0040 != 0 { u32(4) } else { u32(2) }
	base := c.a[opcode & 7]
	addr := base + hwtypes.sext16(c.fetch16(mut bus))
	if opcode & 0x0080 != 0 {
		value := c.d[dn]
		for i in 0 .. bytes {
			bus.write8(addr + 2 * i, u8(value >> (8 * (bytes - 1 - i))))
		}
	} else {
		mut value := u32(0)
		for i in 0 .. bytes {
			value = (value << 8) | bus.read8(addr + 2 * i)
		}
		c.set_d(dn, if bytes == 4 { Size.long } else { Size.word }, value)
	}
	c.cycles += 4 * bytes + 4
}

// op_movem_to_mem executes MOVEM `<list>,<ea>`. Registers go to ascending
// addresses in the order D0..A7, except for the predecrement mode, which
// stores A7..D0 at descending addresses.
@[direct_array_access]
fn (mut c Cpu) op_movem_to_mem(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	size := if opcode & 0x0040 != 0 { Size.long } else { Size.word }
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	list := c.fetch16(mut bus)
	if mode == mode_predec {
		mut addr := c.a[reg]
		if list != 0 && addr & 1 != 0 {
			c.address_error(mut bus, addr - 2, .write, c.pc + 2)
			return
		}
		for i in u32(0) .. 16 {
			if list & (u32(1) << i) == 0 {
				continue
			}
			value := c.reg_value(15 - i)
			addr -= 2
			bus.write16(addr, u16(value))
			c.cycles += 4
			if size == .long {
				addr -= 2
				bus.write16(addr, u16(value >> 16))
				c.cycles += 4
			}
		}
		c.a[reg] = addr
	} else {
		mut addr := c.ea_addr(mut bus, mode, reg, size)
		if list != 0 && addr & 1 != 0 {
			c.address_error(mut bus, addr, .write, c.pc + 2)
			return
		}
		for i in u32(0) .. 16 {
			if list & (u32(1) << i) != 0 {
				c.store(mut bus, addr, size, c.reg_value(i))
				addr += if size == .long { u32(4) } else { u32(2) }
			}
		}
	}
	c.cycles += 4
}

// op_movem_to_reg executes MOVEM `<ea>,<list>`. Word operands are sign
// extended into the full register. As on the real chip, one extra word is
// read past the last operand.
@[direct_array_access]
fn (mut c Cpu) op_movem_to_reg(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	size := if opcode & 0x0040 != 0 { Size.long } else { Size.word }
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	list := c.fetch16(mut bus)
	mut addr := if mode == mode_postinc { c.a[reg] } else { c.ea_addr(mut bus, mode, reg, size) }
	if addr & 1 != 0 {
		pc_relative := mode == mode_other && reg >= other_pc_disp
		c.address_error(mut bus, addr, if pc_relative { Access.fetch } else { Access.read }, c.pc +
			2)
		return
	}
	for i in u32(0) .. 16 {
		if list & (u32(1) << i) == 0 {
			continue
		}
		if size == .long {
			c.set_reg(i, c.load(mut bus, addr, .long))
			addr += 4
		} else {
			c.set_reg(i, hwtypes.sext16(c.load(mut bus, addr, .word)))
			addr += 2
		}
	}
	bus.read16(addr)
	if mode == mode_postinc {
		c.a[reg] = addr
	}
	c.cycles += 8
}
