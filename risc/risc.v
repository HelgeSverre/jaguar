// Jaguar RISC processors: the TOM GPU and the JERRY DSP.
//
// Both share one 16-bit instruction format and most of one instruction set;
// `Variant` selects the handful of opcodes, the accumulator width and the
// register block that differ. The processor owns its local RAM and its
// control registers; every other address goes out on the system bus.
module risc

import hwtypes

pub enum Variant {
	gpu
	dsp
}

// Bits of the FLAGS register (G_FLAGS / D_FLAGS).
pub const flag_zero = u32(1 << 0)
pub const flag_carry = u32(1 << 1)
pub const flag_negative = u32(1 << 2)
pub const flag_imask = u32(1 << 3)
pub const flag_regpage = u32(1 << 14)

// Bits of the CTRL register (G_CTRL / D_CTRL).
pub const ctrl_go = u32(1 << 0)
pub const ctrl_cpuint = u32(1 << 1)
pub const ctrl_forceint0 = u32(1 << 2)

// Offsets of the control registers from `ctrl_base`.
const reg_flags = u32(0x00)
const reg_mtxc = u32(0x04)
const reg_mtxa = u32(0x08)
const reg_end = u32(0x0c)
const reg_pc = u32(0x10)
const reg_ctrl = u32(0x14)
const reg_hidata_mod = u32(0x18) // G_HIDATA on the GPU, D_MOD on the DSP
const reg_remain_divctrl = u32(0x1c)
const reg_machi = u32(0x20) // DSP only: accumulator bits 39..32

const ctrl_block_size = u32(0x24)
const interrupt_vector_spacing = u32(0x10)

// Risc is the complete guest-visible state of one RISC processor.
@[heap]
pub struct Risc {
pub:
	variant   Variant
	ram_base  u32
	ram_size  u32 // power of two
	ctrl_base u32
	irq_lines u32 // number of interrupt sources: 5 on the GPU, 6 on the DSP
pub mut:
	regs           [64]u32 // bank 0 in 0..31, bank 1 in 32..63
	bank           u32     // index of the active bank's r0: 0 or 32
	pc             u32
	zf             u32 // each 0 or 1
	cf             u32
	nf             u32
	flags_ctl      u32 // FLAGS without Z/C/N and without the write-only clear bits
	running        bool
	latches        u32 // pending interrupt latches, bit n = source n
	acc            i64 // multiply-accumulate register, sign-extended
	hidata         u32 // GPU: high long of phrase transfers
	modulo         u32 // DSP: ADDQMOD/SUBQMOD mask
	remain         u32
	div_ctrl       u32
	mtxc           u32
	mtxa           u32
	endian         u32
	branch_pending bool // a taken jump waits for its delay slot
	branch_target  u32
	host_irq       bool // CPUINT was written: the machine routes it to the 68000
	irq_dirty      bool // latches or masks changed; re-evaluate before the next instruction
	ram            []u8
	instructions   u64
}

// new_gpu creates the TOM graphics processor: 4 KiB of local RAM at 0xF03000.
pub fn new_gpu() &Risc {
	return &Risc{
		variant:   .gpu
		ram_base:  0xf03000
		ram_size:  0x1000
		ctrl_base: 0xf02100
		irq_lines: 5
		ram:       []u8{len: 0x1000}
	}
}

// new_dsp creates the JERRY signal processor: 8 KiB of local RAM at 0xF1B000.
pub fn new_dsp() &Risc {
	return &Risc{
		variant:   .dsp
		ram_base:  0xf1b000
		ram_size:  0x2000
		ctrl_base: 0xf1a100
		irq_lines: 6
		ram:       []u8{len: 0x2000}
	}
}

// reset returns the processor to its stopped power-on state. Local RAM keeps
// its contents, as it does across a warm reset on the console.
pub fn (mut c Risc) reset() {
	for i in 0 .. c.regs.len {
		c.regs[i] = 0
	}
	c.bank = 0
	c.pc = c.ram_base
	c.zf = 0
	c.cf = 0
	c.nf = 0
	c.flags_ctl = 0
	c.running = false
	c.latches = 0
	c.acc = 0
	c.hidata = 0
	c.modulo = 0
	c.remain = 0
	c.div_ctrl = 0
	c.mtxc = 0
	c.mtxa = 0
	c.endian = 0
	c.branch_pending = false
	c.branch_target = 0
	c.host_irq = false
	c.irq_dirty = false
}

// owns_ram reports whether `addr` lies in this processor's local RAM.
@[inline]
pub fn (c &Risc) owns_ram(addr u32) bool {
	return addr - c.ram_base < c.ram_size
}

// owns_ctrl reports whether `addr` lies in this processor's register block.
@[inline]
pub fn (c &Risc) owns_ctrl(addr u32) bool {
	return addr - c.ctrl_base < ctrl_block_size
}

// flags composes the FLAGS register as the guest reads it.
@[inline]
pub fn (c &Risc) flags() u32 {
	return c.zf | (c.cf << 1) | (c.nf << 2) | c.flags_ctl
}

// interrupt_enable_mask extracts the per-source enable bits from FLAGS.
@[inline]
fn (c &Risc) interrupt_enable_mask() u32 {
	return ((c.flags_ctl >> 4) & 0x1f) | ((c.flags_ctl >> 11) & 0x20)
}

// set_flags implements a guest write to FLAGS: condition codes, interrupt
// enables, latch clears, the register page and the interrupt mask.
fn (mut c Risc) set_flags(value u32) {
	c.zf = value & 1
	c.cf = (value >> 1) & 1
	c.nf = (value >> 2) & 1
	// Only the interrupt logic sets IMASK. Writing 1 leaves it as it is and
	// writing 0 clears it.
	imask := c.flags_ctl & value & flag_imask
	c.flags_ctl = (value & 0x0001_c1f0) | imask
	clear := ((value >> 9) & 0x1f) | ((value >> 12) & 0x20)
	c.latches &= ~clear
	c.select_bank()
	c.irq_dirty = true
}

// select_bank applies REGPAGE; interrupt service always runs in bank 0.
@[inline]
fn (mut c Risc) select_bank() {
	c.bank = if c.flags_ctl & flag_regpage != 0 && c.flags_ctl & flag_imask == 0 {
		u32(32)
	} else {
		u32(0)
	}
}

// ctrl composes the CTRL register as the guest reads it.
fn (c &Risc) ctrl() u32 {
	go_bit := if c.running { ctrl_go } else { u32(0) }
	version := u32(0x2000)
	return go_bit | ((c.latches & 0x1f) << 6) | ((c.latches & 0x20) << 11) | version
}

// set_ctrl implements a guest write to CTRL.
fn (mut c Risc) set_ctrl(value u32) {
	c.running = value & ctrl_go != 0
	if value & ctrl_cpuint != 0 {
		c.host_irq = true
	}
	if value & ctrl_forceint0 != 0 {
		c.raise_irq(0)
	}
}

// raise_irq requests interrupt source `line`. The enable bit in FLAGS gates
// the request into its latch: a request for a disabled source is lost, it
// does not wait for the source to be enabled. A latched request is served
// at the next instruction boundary where interrupts are unmasked.
pub fn (mut c Risc) raise_irq(line u32) {
	bit := u32(1) << line
	if line < c.irq_lines && c.interrupt_enable_mask() & bit != 0 {
		c.latches |= bit
		c.irq_dirty = true
	}
}

// read_ctrl32 reads a control register; `offset` is relative to `ctrl_base`.
pub fn (c &Risc) read_ctrl32(offset u32) u32 {
	return match offset & 0x3c {
		reg_flags {
			c.flags()
		}
		reg_mtxc {
			c.mtxc
		}
		reg_mtxa {
			c.mtxa
		}
		reg_end {
			c.endian
		}
		reg_pc {
			c.pc
		}
		reg_ctrl {
			c.ctrl()
		}
		reg_hidata_mod {
			if c.variant == .gpu {
				c.hidata
			} else {
				c.modulo
			}
		}
		reg_remain_divctrl {
			c.remain
		}
		reg_machi {
			if c.variant == .dsp {
				u32(u64(c.acc) >> 32) & 0xff
			} else {
				u32(0)
			}
		}
		else {
			0
		}
	}
}

// write_ctrl32 writes a control register; `offset` is relative to `ctrl_base`.
pub fn (mut c Risc) write_ctrl32(offset u32, value u32) {
	match offset & 0x3c {
		reg_flags {
			c.set_flags(value)
		}
		reg_mtxc {
			c.mtxc = value & 0x1f
		}
		reg_mtxa {
			c.mtxa = value & 0xffff_fffc
		}
		reg_end {
			c.endian = value
		}
		reg_pc {
			c.pc = value & 0xffff_fffe
			c.branch_pending = false
		}
		reg_ctrl {
			c.set_ctrl(value)
		}
		reg_hidata_mod {
			if c.variant == .gpu {
				c.hidata = value
			} else {
				c.modulo = value
			}
		}
		reg_remain_divctrl {
			c.div_ctrl = value
		}
		else {}
	}
}

// read_ram8 reads local RAM for another bus master. `offset` is relative
// to `ram_base` and wraps at the RAM size.
@[direct_array_access; inline]
pub fn (c &Risc) read_ram8(offset u32) u8 {
	return c.ram[offset & (c.ram_size - 1)]
}

// write_ram8 writes local RAM for another bus master. `offset` is relative
// to `ram_base` and wraps at the RAM size.
@[direct_array_access; inline]
pub fn (mut c Risc) write_ram8(offset u32, value u8) {
	c.ram[offset & (c.ram_size - 1)] = value
}

@[direct_array_access; inline]
fn (c &Risc) ram16(addr u32) u32 {
	i := (addr - c.ram_base) & (c.ram_size - 2)
	return (u32(c.ram[i]) << 8) | c.ram[i + 1]
}

@[direct_array_access; inline]
fn (c &Risc) ram32(addr u32) u32 {
	i := (addr - c.ram_base) & (c.ram_size - 4)
	return (u32(c.ram[i]) << 24) | (u32(c.ram[i + 1]) << 16) | (u32(c.ram[i + 2]) << 8) | c.ram[i +
		3]
}

@[direct_array_access; inline]
fn (mut c Risc) set_ram32(addr u32, value u32) {
	i := (addr - c.ram_base) & (c.ram_size - 4)
	c.ram[i] = u8(value >> 24)
	c.ram[i + 1] = u8(value >> 16)
	c.ram[i + 2] = u8(value >> 8)
	c.ram[i + 3] = u8(value)
}

// load32 is a processor-initiated long read.
@[inline]
fn (mut c Risc) load32(mut bus hwtypes.Bus, addr u32) u32 {
	if c.owns_ram(addr) {
		return c.ram32(addr)
	}
	if c.owns_ctrl(addr) {
		return c.read_ctrl32(addr - c.ctrl_base)
	}
	// The external bus is 16 bits wide: a long is two word transfers and
	// needs only word alignment.
	return bus.read32(addr & 0xffff_fffe)
}

// store32 is a processor-initiated long write.
@[inline]
fn (mut c Risc) store32(mut bus hwtypes.Bus, addr u32, value u32) {
	if c.owns_ram(addr) {
		c.set_ram32(addr, value)
	} else if c.owns_ctrl(addr) {
		c.write_ctrl32(addr - c.ctrl_base, value)
	} else {
		bus.write32(addr & 0xffff_fffe, value)
	}
}

// is_internal reports whether `addr` is served by the processor's own 32-bit
// storage, where byte and word transfers are widened to whole longs.
@[inline]
fn (c &Risc) is_internal(addr u32) bool {
	return c.owns_ram(addr) || c.owns_ctrl(addr)
}

// fetch16 reads the instruction word at the program counter and advances it.
@[inline]
fn (mut c Risc) fetch16(mut bus hwtypes.Bus) u32 {
	pc := c.pc
	c.pc = pc + 2
	if c.owns_ram(pc) {
		return c.ram16(pc)
	}
	return bus.read16(pc)
}

// service_interrupts enters the highest-priority enabled pending interrupt.
// It does nothing while a service routine is active (IMASK) or while a taken
// jump still owes its delay slot.
fn (mut c Risc) service_interrupts(mut bus hwtypes.Bus) {
	if c.branch_pending {
		return
	}
	c.irq_dirty = false
	if c.flags_ctl & flag_imask != 0 {
		return
	}
	pending := c.latches & c.interrupt_enable_mask()
	if pending == 0 {
		return
	}
	mut line := c.irq_lines - 1
	for pending & (u32(1) << line) == 0 {
		line--
	}
	c.flags_ctl |= flag_imask
	c.select_bank()
	// The hardware pushes the address of the last executed instruction; the
	// service routine adds two before returning through it.
	sp := c.regs[31] - 4
	c.regs[31] = sp
	c.store32(mut bus, sp, c.pc - 2)
	vector := c.ram_base + line * interrupt_vector_spacing
	c.regs[30] = vector
	c.pc = vector
}
