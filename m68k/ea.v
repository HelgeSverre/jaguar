module m68k

import hwtypes

// Addressing modes as encoded in the three-bit mode field. Mode 7 selects
// the absolute, PC-relative and immediate forms through the register field.
const mode_dn = u32(0)
const mode_an = u32(1)
const mode_indirect = u32(2)
const mode_postinc = u32(3)
const mode_predec = u32(4)
const mode_disp = u32(5)
const mode_index = u32(6)
const mode_other = u32(7)

const other_abs_w = u32(0)
const other_abs_l = u32(1)
const other_pc_disp = u32(2)
const other_pc_index = u32(3)
const other_imm = u32(4)

// fetch16 consumes the next word of the instruction stream.
@[inline]
fn (mut c Cpu) fetch16(mut bus hwtypes.Bus) u32 {
	word := bus.read16(c.pc)
	c.pc += 2
	c.cycles += 4
	return word
}

// fetch32 consumes the next two words of the instruction stream.
@[inline]
fn (mut c Cpu) fetch32(mut bus hwtypes.Bus) u32 {
	hi := c.fetch16(mut bus)
	return (hi << 16) | c.fetch16(mut bus)
}

// fetch_imm consumes an immediate operand of `size`.
@[inline]
fn (mut c Cpu) fetch_imm(mut bus hwtypes.Bus, size Size) u32 {
	return match size {
		.byte { c.fetch16(mut bus) & 0xff }
		.word { c.fetch16(mut bus) }
		.long { c.fetch32(mut bus) }
	}
}

// load reads an operand of `size` from memory. Longs are read high word
// first. The caller guarantees an even address for word and long accesses.
@[inline]
fn (mut c Cpu) load(mut bus hwtypes.Bus, addr u32, size Size) u32 {
	match size {
		.byte {
			c.cycles += 4
			return bus.read8(addr)
		}
		.word {
			c.cycles += 4
			return bus.read16(addr)
		}
		.long {
			c.cycles += 8
			hi := u32(bus.read16(addr))
			return (hi << 16) | bus.read16(addr + 2)
		}
	}
}

// store writes an operand of `size` to memory, longs high word first, as
// MOVE and the stacking instructions do.
@[inline]
fn (mut c Cpu) store(mut bus hwtypes.Bus, addr u32, size Size, value u32) {
	match size {
		.byte {
			c.cycles += 4
			bus.write8(addr, u8(value))
		}
		.word {
			c.cycles += 4
			bus.write16(addr, u16(value))
		}
		.long {
			c.cycles += 8
			bus.write16(addr, u16(value >> 16))
			bus.write16(addr + 2, u16(value))
		}
	}
}

// store_low_first writes like `store` but puts the low word of a long on the
// bus first, as read-modify-write instructions and predecrement moves do.
@[inline]
fn (mut c Cpu) store_low_first(mut bus hwtypes.Bus, addr u32, size Size, value u32) {
	if size == .long {
		c.cycles += 8
		bus.write16(addr + 2, u16(value))
		bus.write16(addr, u16(value >> 16))
	} else {
		c.store(mut bus, addr, size, value)
	}
}

// is_memory_ea reports whether `mode`/`reg` names a memory operand, as
// opposed to a register or immediate one.
@[inline]
fn is_memory_ea(mode u32, reg u32) bool {
	return mode >= mode_indirect && !(mode == mode_other && reg == other_imm)
}

// an_step returns the amount (An)+ and -(An) move the register by. A byte
// access through the stack pointer keeps it word aligned.
@[inline]
fn an_step(reg u32, size Size) u32 {
	return match size {
		.byte {
			if reg == 7 {
				u32(2)
			} else {
				u32(1)
			}
		}
		.word {
			u32(2)
		}
		.long {
			u32(4)
		}
	}
}

// indexed resolves `base` plus the brief extension word's 8-bit displacement
// and index register.
@[direct_array_access; inline]
fn (mut c Cpu) indexed(mut bus hwtypes.Bus, base u32) u32 {
	ext := c.fetch16(mut bus)
	c.cycles += 2
	mut index := c.reg_value(ext >> 12)
	if ext & 0x0800 == 0 {
		index = hwtypes.sext16(index)
	}
	return base + hwtypes.sext8(ext) + index
}

// ea_addr resolves a memory addressing mode to its address. It applies the
// (An)+ and -(An) register updates, consumes extension words and charges
// the indexing delay; it performs no operand access and no alignment check.
@[direct_array_access; inline]
fn (mut c Cpu) ea_addr(mut bus hwtypes.Bus, mode u32, reg u32, size Size) u32 {
	match mode {
		mode_indirect {
			return c.a[reg]
		}
		mode_postinc {
			addr := c.a[reg]
			c.a[reg] = addr + an_step(reg, size)
			return addr
		}
		mode_predec {
			addr := c.a[reg] - an_step(reg, size)
			c.a[reg] = addr
			return addr
		}
		mode_disp {
			return c.a[reg] + hwtypes.sext16(c.fetch16(mut bus))
		}
		mode_index {
			return c.indexed(mut bus, c.a[reg])
		}
		else {
			match reg {
				other_abs_w {
					return hwtypes.sext16(c.fetch16(mut bus))
				}
				other_abs_l {
					return c.fetch32(mut bus)
				}
				other_pc_disp {
					base := c.pc
					return base + hwtypes.sext16(c.fetch16(mut bus))
				}
				else {
					return c.indexed(mut bus, c.pc)
				}
			}
		}
	}
}

// ea_read_addr resolves a memory operand that is read first: on top of
// `ea_addr` it charges the predecrement delay and raises an address error
// for an odd word or long address. Callers must return when `c.aborted`.
@[inline]
fn (mut c Cpu) ea_read_addr(mut bus hwtypes.Bus, mode u32, reg u32, size Size) u32 {
	if mode == mode_predec {
		c.cycles += 2
	}
	addr := c.ea_addr(mut bus, mode, reg, size)
	if size != .byte && addr & 1 != 0 {
		c.ea_read_fault(mut bus, mode, reg, size, addr)
	}
	return addr
}

// ea_read_fault raises the address error for an operand read through
// `mode`/`reg`. The stacked PC and the state of An depend on how far the
// addressing microcode had progressed when the bus cycle was refused.
@[direct_array_access]
fn (mut c Cpu) ea_read_fault(mut bus hwtypes.Bus, mode u32, reg u32, size Size, addr u32) {
	mut return_pc := c.pc
	mut access := Access.read
	match mode {
		mode_postinc {
			if size == .long {
				// The increment happens after the first word arrives.
				c.a[reg] = addr
			}
		}
		mode_predec {
			if size == .word {
				return_pc += 2
			}
		}
		mode_disp, mode_index {
			return_pc -= 2
		}
		mode_other {
			if reg == other_pc_disp || reg == other_pc_index {
				return_pc -= 2
				access = .fetch
			}
		}
		else {}
	}

	c.address_error(mut bus, addr, access, return_pc)
}

// read_ea fetches the source operand named by `mode`/`reg`: a register, an
// immediate or a memory operand. Callers must return when `c.aborted`.
@[direct_array_access; inline]
fn (mut c Cpu) read_ea(mut bus hwtypes.Bus, mode u32, reg u32, size Size) u32 {
	if mode == mode_dn {
		return c.d[reg] & size.mask()
	}
	if mode == mode_an {
		return c.a[reg] & size.mask()
	}
	if mode == mode_other && reg == other_imm {
		return c.fetch_imm(mut bus, size)
	}
	addr := c.ea_read_addr(mut bus, mode, reg, size)
	if c.aborted {
		return 0
	}
	return c.load(mut bus, addr, size)
}

// push32 pushes a long onto the active stack, high word first.
@[direct_array_access; inline]
fn (mut c Cpu) push32(mut bus hwtypes.Bus, value u32) {
	c.a[7] -= 4
	c.store(mut bus, c.a[7], .long, value)
}

// stack_fault raises the address error for an odd stack pointer and returns
// true when it did. Stack accesses of the 68000 are always word sized.
@[direct_array_access; inline]
fn (mut c Cpu) stack_fault(mut bus hwtypes.Bus, access Access) bool {
	if c.a[7] & 1 == 0 {
		return false
	}
	c.address_error(mut bus, c.a[7], access, c.pc)
	return true
}
