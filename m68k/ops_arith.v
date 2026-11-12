module m68k

import hwtypes

// Alu selects the operation of the two-operand integer instructions.
enum Alu as u8 {
	add
	sub
	cmp
	bit_and
	bit_or
	bit_xor
}

// Unary selects the operation of the single-operand instructions.
enum Unary as u8 {
	negx
	clr
	neg
	not
}

// alu computes `dst op src`, sets the condition codes and returns the
// unmasked result. CMP returns `dst` unchanged.
@[inline]
fn (mut c Cpu) alu(op Alu, src u32, dst u32, size Size) u32 {
	match op {
		.add {
			res := dst + src
			c.set_xnzvc(add_ccr(src, dst, res, size))
			return res
		}
		.sub {
			res := dst - src
			c.set_xnzvc(sub_ccr(src, dst, res, size))
			return res
		}
		.cmp {
			c.set_nzvc(sub_ccr(src, dst, dst - src, size))
			return dst
		}
		.bit_and {
			res := dst & src
			c.set_logic_flags(res, size)
			return res
		}
		.bit_or {
			res := dst | src
			c.set_logic_flags(res, size)
			return res
		}
		.bit_xor {
			res := dst ^ src
			c.set_logic_flags(res, size)
			return res
		}
	}
}

// unary computes the single-operand operation `kind` on `dst`, sets the
// condition codes and returns the unmasked result.
@[inline]
fn (mut c Cpu) unary(kind Unary, dst u32, size Size) u32 {
	match kind {
		.negx {
			res := 0 - dst - c.x_bit()
			c.set_xnzvc_sticky_z(sub_ccr(dst, 0, res, size))
			return res
		}
		.clr {
			c.set_nzvc(flag_z)
			return 0
		}
		.neg {
			res := 0 - dst
			c.set_xnzvc(sub_ccr(dst, 0, res, size))
			return res
		}
		.not {
			res := ~dst
			c.set_logic_flags(res, size)
			return res
		}
	}
}

// op_alu_to_reg executes ADD, SUB, AND, OR and CMP with a data register
// destination: `<ea>,Dn`.
@[direct_array_access]
fn (mut c Cpu) op_alu_to_reg(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	src := c.read_ea(mut bus, mode, reg, size)
	if c.aborted {
		return
	}
	dn := (opcode >> 9) & 7
	res := c.alu(op, src, c.d[dn], size)
	c.set_d(dn, size, res)
	c.cycles += 4
	if size == .long {
		c.cycles += if op == .cmp || is_memory_ea(mode, reg) { u64(2) } else { u64(4) }
	}
}

// op_alu_to_mem executes ADD, SUB, AND, OR and EOR with a memory
// destination: `Dn,<ea>`.
@[direct_array_access]
fn (mut c Cpu) op_alu_to_mem(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	addr := c.ea_read_addr(mut bus, (opcode >> 3) & 7, opcode & 7, size)
	if c.aborted {
		return
	}
	dst := c.load(mut bus, addr, size)
	res := c.alu(op, c.d[(opcode >> 9) & 7], dst, size)
	c.store_low_first(mut bus, addr, size, res)
	c.cycles += 4
}

// op_eor executes EOR `Dn,<ea>`, whose destination may also be a data
// register.
@[direct_array_access]
fn (mut c Cpu) op_eor(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	if (opcode >> 3) & 7 != mode_dn {
		c.op_alu_to_mem(mut bus, .bit_xor)
		return
	}
	size := size_field(opcode >> 6)
	reg := opcode & 7
	res := c.alu(.bit_xor, c.d[(opcode >> 9) & 7], c.d[reg], size)
	c.set_d(reg, size, res)
	c.cycles += if size == .long { u64(8) } else { u64(4) }
}

// op_alu_immediate executes ORI, ANDI, SUBI, ADDI, EORI and CMPI.
@[direct_array_access]
fn (mut c Cpu) op_alu_immediate(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	src := c.fetch_imm(mut bus, size)
	if mode == mode_dn {
		res := c.alu(op, src, c.d[reg], size)
		c.set_d(reg, size, res)
		c.cycles += 4
		if size == .long {
			c.cycles += if op == .cmp { u64(2) } else { u64(4) }
		}
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, size)
	if c.aborted {
		return
	}
	res := c.alu(op, src, c.load(mut bus, addr, size), size)
	if op != .cmp {
		c.store_low_first(mut bus, addr, size, res)
	}
	c.cycles += 4
}

// op_quick executes ADDQ and SUBQ.
@[direct_array_access]
fn (mut c Cpu) op_quick(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	mut src := (opcode >> 9) & 7
	if src == 0 {
		src = 8
	}
	match mode {
		mode_dn {
			res := c.alu(op, src, c.d[reg], size)
			c.set_d(reg, size, res)
			c.cycles += if size == .long { u64(8) } else { u64(4) }
		}
		mode_an {
			// The whole address register is affected and no flags change.
			c.a[reg] = if op == .add { c.a[reg] + src } else { c.a[reg] - src }
			c.cycles += 8
		}
		else {
			addr := c.ea_read_addr(mut bus, mode, reg, size)
			if c.aborted {
				return
			}
			res := c.alu(op, src, c.load(mut bus, addr, size), size)
			c.store_low_first(mut bus, addr, size, res)
			c.cycles += 4
		}
	}
}

// op_address_arith executes ADDA, SUBA and CMPA. A word source is sign
// extended and the operation is always 32 bits wide.
@[direct_array_access]
fn (mut c Cpu) op_address_arith(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := if opcode & 0x0100 != 0 { Size.long } else { Size.word }
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	mut src := c.read_ea(mut bus, mode, reg, size)
	if c.aborted {
		return
	}
	if size == .word {
		src = hwtypes.sext16(src)
	}
	an := (opcode >> 9) & 7
	dst := c.a[an]
	match op {
		.add {
			c.a[an] = dst + src
		}
		.sub {
			c.a[an] = dst - src
		}
		else {
			c.set_nzvc(sub_ccr(src, dst, dst - src, .long))
			c.cycles += 6
			return
		}
	}

	c.cycles += if size == .long && is_memory_ea(mode, reg) { u64(6) } else { u64(8) }
}

// op_cmpm executes CMPM `(Ay)+,(Ax)+`.
@[direct_array_access]
fn (mut c Cpu) op_cmpm(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	// A refused source read leaves Ay advanced by two; a refused
	// destination read leaves Ax untouched.
	src := c.postinc_load(mut bus, opcode & 7, size, 2)
	if c.aborted {
		return
	}
	dst := c.postinc_load(mut bus, (opcode >> 9) & 7, size, 0)
	if c.aborted {
		return
	}
	c.alu(.cmp, src, dst, size)
	c.cycles += 4
}

// postinc_load reads a CMPM operand through `(An)+`. If the address is odd
// the register is left `fault_step` past its original value.
@[direct_array_access]
fn (mut c Cpu) postinc_load(mut bus hwtypes.Bus, reg u32, size Size, fault_step u32) u32 {
	addr := c.a[reg]
	if size != .byte && addr & 1 != 0 {
		c.a[reg] = addr + fault_step
		c.address_error(mut bus, addr, .read, c.pc + 2)
		return 0
	}
	c.a[reg] = addr + an_step(reg, size)
	return c.load(mut bus, addr, size)
}

// extended computes ADDX or SUBX: the X flag joins the operation and Z is
// only ever cleared.
@[inline]
fn (mut c Cpu) extended(op Alu, src u32, dst u32, size Size) u32 {
	if op == .add {
		res := dst + src + c.x_bit()
		c.set_xnzvc_sticky_z(add_ccr(src, dst, res, size))
		return res
	}
	res := dst - src - c.x_bit()
	c.set_xnzvc_sticky_z(sub_ccr(src, dst, res, size))
	return res
}

// op_extended executes ADDX and SUBX in their `Dy,Dx` and `-(Ay),-(Ax)`
// forms.
@[direct_array_access]
fn (mut c Cpu) op_extended(mut bus hwtypes.Bus, op Alu) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	ry := opcode & 7
	rx := (opcode >> 9) & 7
	if opcode & 0x0008 == 0 {
		res := c.extended(op, c.d[ry], c.d[rx], size)
		c.set_d(rx, size, res)
		c.cycles += if size == .long { u64(8) } else { u64(4) }
		return
	}
	c.cycles += 2
	src := c.predec_load(mut bus, ry, size)
	if c.aborted {
		return
	}
	dst := c.predec_load(mut bus, rx, size)
	if c.aborted {
		return
	}
	res := c.extended(op, src, dst, size)
	c.store_low_first(mut bus, c.a[rx], size, res)
	c.cycles += 4
}

// predec_load reads a multi-precision operand through `-(An)`. Unlike the
// general predecrement mode, a long is fetched low word first with the
// register stepping down by two before each word.
@[direct_array_access]
fn (mut c Cpu) predec_load(mut bus hwtypes.Bus, reg u32, size Size) u32 {
	if size != .long {
		addr := c.a[reg] - an_step(reg, size)
		c.a[reg] = addr
		if size == .word && addr & 1 != 0 {
			c.address_error(mut bus, addr, .read, c.pc + 2)
			return 0
		}
		return c.load(mut bus, addr, size)
	}
	low_addr := c.a[reg] - 2
	if low_addr & 1 != 0 {
		c.address_error(mut bus, low_addr, .read, c.pc + 2)
		return 0
	}
	lo := c.load(mut bus, low_addr, .word)
	c.a[reg] = low_addr - 2
	return (c.load(mut bus, low_addr - 2, .word) << 16) | lo
}

// op_unary executes NEGX, CLR, NEG and NOT.
@[direct_array_access]
fn (mut c Cpu) op_unary(mut bus hwtypes.Bus, kind Unary) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode == mode_dn {
		res := c.unary(kind, c.d[reg], size)
		c.set_d(reg, size, res)
		c.cycles += if size == .long { u64(6) } else { u64(4) }
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, size)
	if c.aborted {
		return
	}
	// Even CLR reads the operand before writing it on the 68000.
	res := c.unary(kind, c.load(mut bus, addr, size), size)
	c.store_low_first(mut bus, addr, size, res)
	c.cycles += 4
}

// op_tst executes TST.
fn (mut c Cpu) op_tst(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	size := size_field(opcode >> 6)
	value := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, size)
	if c.aborted {
		return
	}
	c.set_logic_flags(value, size)
	c.cycles += 4
}
