module m68k

import hwtypes

// jump continues execution at `target`. An odd target raises an address
// error on the first instruction fetch, stacking `return_pc`.
@[inline]
fn (mut c Cpu) jump(mut bus hwtypes.Bus, target u32, return_pc u32) {
	if target & 1 != 0 {
		c.address_error(mut bus, target, .fetch, return_pc)
		return
	}
	c.pc = target
	c.cycles += 8
}

// op_bcc executes Bcc and BRA with an 8-bit or 16-bit displacement.
fn (mut c Cpu) op_bcc(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	base := c.pc
	short := opcode & 0xff != 0
	if c.condition(opcode >> 8) {
		target := base + if short {
			hwtypes.sext8(opcode)
		} else {
			hwtypes.sext16(bus.read16(base))
		}
		c.cycles += 2
		c.jump(mut bus, target, base)
	} else if short {
		c.cycles += 8
	} else {
		c.pc = base + 2
		c.cycles += 12
	}
}

// op_bsr executes BSR: the return address is pushed before the branch
// target is fetched.
fn (mut c Cpu) op_bsr(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	base := c.pc
	mut target := base + hwtypes.sext8(opcode)
	mut return_addr := base
	if opcode & 0xff == 0 {
		target = base + hwtypes.sext16(bus.read16(base))
		return_addr = base + 2
	}
	c.cycles += 2
	if c.stack_fault(mut bus, .write) {
		return
	}
	c.push32(mut bus, return_addr)
	c.jump(mut bus, target, target)
}

// op_dbcc executes DBcc: unless the condition holds, the low word of Dn is
// decremented and the branch is taken until it reaches -1.
@[direct_array_access]
fn (mut c Cpu) op_dbcc(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	base := c.pc
	if c.condition(opcode >> 8) {
		c.pc = base + 2
		c.cycles += 12
		return
	}
	reg := opcode & 7
	counter := (c.d[reg] - 1) & 0xffff
	if counter == 0xffff {
		c.set_d(reg, .word, counter)
		c.pc = base + 2
		c.cycles += 14
		return
	}
	target := base + hwtypes.sext16(bus.read16(base))
	c.cycles += 2
	c.jump(mut bus, target, base + 2)
	if !c.aborted {
		c.set_d(reg, .word, counter)
	}
}

// op_scc executes Scc: the destination byte becomes all ones when the
// condition holds and zero otherwise.
@[direct_array_access]
fn (mut c Cpu) op_scc(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	holds := c.condition(opcode >> 8)
	value := if holds { u32(0xff) } else { u32(0) }
	if mode == mode_dn {
		c.set_d(reg, .byte, value)
		c.cycles += if holds { u64(6) } else { u64(4) }
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, .byte)
	c.load(mut bus, addr, .byte)
	c.store(mut bus, addr, .byte, value)
	c.cycles += 4
}

// jump_target resolves the control addressing mode of JMP and JSR. These
// instructions do not prefetch past their extension words, so part of the
// usual extension-word time is not spent.
fn (mut c Cpu) jump_target(mut bus hwtypes.Bus) u32 {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	target := c.ea_addr(mut bus, mode, reg, .long)
	if mode == mode_disp {
		c.cycles -= 2
	} else if mode == mode_other {
		match reg {
			other_abs_w, other_pc_disp { c.cycles -= 2 }
			other_abs_l { c.cycles -= 4 }
			else {}
		}
	}
	return target
}

// op_jmp executes JMP.
fn (mut c Cpu) op_jmp(mut bus hwtypes.Bus) {
	base := c.pc
	target := c.jump_target(mut bus)
	c.jump(mut bus, target, base)
}

// op_jsr executes JSR. The target is fetched before the return address is
// pushed, so an odd target faults with the stack untouched.
fn (mut c Cpu) op_jsr(mut bus hwtypes.Bus) {
	target := c.jump_target(mut bus)
	return_addr := c.pc
	c.jump(mut bus, target, return_addr)
	if c.aborted || c.stack_fault(mut bus, .write) {
		return
	}
	c.push32(mut bus, return_addr)
}

// pop16 reads one word from the active stack.
@[direct_array_access; inline]
fn (mut c Cpu) pop16(mut bus hwtypes.Bus) u32 {
	value := c.load(mut bus, c.a[7], .word)
	c.a[7] += 2
	return value
}

// pop32 reads one long from the active stack.
@[direct_array_access; inline]
fn (mut c Cpu) pop32(mut bus hwtypes.Bus) u32 {
	value := c.load(mut bus, c.a[7], .long)
	c.a[7] += 4
	return value
}

// op_rts executes RTS.
fn (mut c Cpu) op_rts(mut bus hwtypes.Bus) {
	if c.stack_fault(mut bus, .read) {
		return
	}
	target := c.pop32(mut bus)
	c.jump(mut bus, target, c.pc)
}

// op_rtr executes RTR: the condition codes and then the PC are popped.
fn (mut c Cpu) op_rtr(mut bus hwtypes.Bus) {
	if c.stack_fault(mut bus, .read) {
		return
	}
	ccr := c.pop16(mut bus)
	target := c.pop32(mut bus)
	c.set_ccr(ccr)
	c.jump(mut bus, target, c.pc)
}

// op_rte executes the privileged RTE: SR and PC are popped from the
// supervisor stack, possibly returning to user mode.
fn (mut c Cpu) op_rte(mut bus hwtypes.Bus) {
	if !c.require_supervisor(mut bus) || c.stack_fault(mut bus, .read) {
		return
	}
	sr := c.pop16(mut bus)
	target := c.pop32(mut bus)
	c.set_sr(u16(sr))
	c.jump(mut bus, target, c.pc)
}

// op_link executes LINK.
@[direct_array_access]
fn (mut c Cpu) op_link(mut bus hwtypes.Bus) {
	reg := u32(c.ir) & 7
	disp := hwtypes.sext16(c.fetch16(mut bus))
	if c.stack_fault(mut bus, .write) {
		return
	}
	frame := c.a[reg]
	c.a[7] -= 4
	c.store(mut bus, c.a[7], .long, frame)
	c.a[reg] = c.a[7]
	c.a[7] += disp
	c.cycles += 4
}

// op_unlk executes UNLK.
@[direct_array_access]
fn (mut c Cpu) op_unlk(mut bus hwtypes.Bus) {
	reg := u32(c.ir) & 7
	frame := c.a[reg]
	if frame & 1 != 0 {
		c.address_error(mut bus, frame, .read, c.pc + 2)
		return
	}
	c.a[7] = frame + 4
	c.a[reg] = c.load(mut bus, frame, .long)
	c.cycles += 4
}

// op_trap executes TRAP #n.
fn (mut c Cpu) op_trap(mut bus hwtypes.Bus) {
	c.exception(mut bus, vector_trap + (c.ir & 15), c.pc, 34)
}

// op_trapv executes TRAPV.
fn (mut c Cpu) op_trapv(mut bus hwtypes.Bus) {
	if c.sr & flag_v != 0 {
		c.exception(mut bus, vector_trapv, c.pc, 34)
	} else {
		c.cycles += 4
	}
}

// op_chk executes CHK: a trap is taken when the low word of Dn is negative
// or greater than the bound.
@[direct_array_access]
fn (mut c Cpu) op_chk(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	bound := i32(i16(c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)))
	if c.aborted {
		return
	}
	value := i32(i16(c.d[(opcode >> 9) & 7]))
	c.sr &= ~(flag_n | flag_z | flag_v | flag_c)
	if value < 0 {
		c.sr |= flag_n
	}
	// The microcode first subtracts the bound. It takes the trap at once
	// when that 16-bit difference is positive or overflows, and needs one
	// more microcycle to notice a negative value otherwise.
	difference := value - bound
	if value > bound || difference < -0x8000 {
		c.exception(mut bus, vector_chk, c.pc, 38)
	} else if value < 0 {
		c.exception(mut bus, vector_chk, c.pc, 40)
	} else {
		c.cycles += 10
	}
}

// op_stop executes the privileged STOP: the immediate operand is loaded
// into SR and the processor waits for an interrupt.
fn (mut c Cpu) op_stop(mut bus hwtypes.Bus) {
	if c.require_supervisor(mut bus) {
		c.set_sr(u16(c.fetch16(mut bus)))
		c.stopped = true
	}
}

// op_reset executes the privileged RESET: the external reset line is
// pulsed for 124 clocks and the processor state is unaffected.
fn (mut c Cpu) op_reset(mut bus hwtypes.Bus) {
	if c.require_supervisor(mut bus) {
		c.reset_line_pulsed = true
		c.cycles += 132
	}
}

// op_move_from_sr executes MOVE SR,<ea>. The 68000 reads a memory
// destination before writing it.
fn (mut c Cpu) op_move_from_sr(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode == mode_dn {
		c.set_d(reg, .word, c.sr)
		c.cycles += 6
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, .word)
	if c.aborted {
		return
	}
	c.load(mut bus, addr, .word)
	c.store(mut bus, addr, .word, c.sr)
	c.cycles += 4
}

// op_move_to_ccr executes MOVE <ea>,CCR.
fn (mut c Cpu) op_move_to_ccr(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	value := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	c.set_ccr(value)
	c.cycles += 12
}

// op_move_to_sr executes the privileged MOVE <ea>,SR.
fn (mut c Cpu) op_move_to_sr(mut bus hwtypes.Bus) {
	if !c.require_supervisor(mut bus) {
		return
	}
	opcode := u32(c.ir)
	value := c.read_ea(mut bus, (opcode >> 3) & 7, opcode & 7, .word)
	if c.aborted {
		return
	}
	c.set_sr(u16(value))
	c.cycles += 12
}

// logic_immediate applies the ORI (0), ANDI (1) or EORI (5) selected by the
// opcode to `value`.
@[inline]
fn (c &Cpu) logic_immediate(value u32, operand u32) u32 {
	return match (c.ir >> 9) & 7 {
		0 { value | operand }
		1 { value & operand }
		else { value ^ operand }
	}
}

// op_logic_ccr executes ORI, ANDI and EORI to CCR.
fn (mut c Cpu) op_logic_ccr(mut bus hwtypes.Bus) {
	operand := c.fetch16(mut bus)
	c.set_ccr(c.logic_immediate(c.sr, operand))
	c.cycles += 16
}

// op_logic_sr executes the privileged ORI, ANDI and EORI to SR.
fn (mut c Cpu) op_logic_sr(mut bus hwtypes.Bus) {
	if !c.require_supervisor(mut bus) {
		return
	}
	operand := c.fetch16(mut bus)
	c.set_sr(u16(c.logic_immediate(c.sr, operand)))
	c.cycles += 16
}

// op_tas executes TAS: the byte is tested and its top bit set.
@[direct_array_access]
fn (mut c Cpu) op_tas(mut bus hwtypes.Bus) {
	opcode := u32(c.ir)
	mode := (opcode >> 3) & 7
	reg := opcode & 7
	if mode == mode_dn {
		c.set_logic_flags(c.d[reg], .byte)
		c.d[reg] |= 0x80
		c.cycles += 4
		return
	}
	addr := c.ea_read_addr(mut bus, mode, reg, .byte)
	value := c.load(mut bus, addr, .byte)
	c.set_logic_flags(value, .byte)
	c.cycles += 2
	c.store(mut bus, addr, .byte, value | 0x80)
	c.cycles += 4
}
