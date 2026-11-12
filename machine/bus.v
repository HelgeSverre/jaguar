// The system bus: address decoding for every bus master.
//
// Map (24-bit addresses):
//   0x000000..0x3FFFFF  main RAM, 2 MiB mirrored once
//   0x400000..0x7FFFFF  unpopulated second DRAM bank (reads as ones)
//   0x800000..0xDFFFFF  cartridge
//   0xE00000..0xEFFFFF  boot ROM (128 KiB, reads as ones beyond it)
//   0xF00000..0xF0FFFF  TOM, with its 32-bit window repeated at +0x8000
//   0xF10000..0xF1FFFF  JERRY
//
// Registers are 16 bits wide in TOM and JERRY proper and 32 bits wide in
// the GPU, blitter, DSP and serial audio blocks. Narrower accesses to a
// 32-bit block read-modify-write the whole register, which is how a 68000
// long write (two word transfers) reaches them.
module machine

import hwtypes

const address_mask = u32(0xff_ffff)
const ram_mirror_end = u32(0x40_0000)
const io_base = u32(0xf0_0000)
const jerry_base = u32(0xf1_0000)

// Offsets inside TOM's 64 KiB block.
const tom_window = u32(0x8000)
const tom_registers_end = u32(0x2000)
const gpu_ctrl = u32(0x2100)
const gpu_ctrl_end = u32(0x2124)
const blitter = u32(0x2200)
const blitter_end = u32(0x22a0)
const gpu_ram = u32(0x3000)
const gpu_ram_end = u32(0x4000)
const tom_hc = u32(0x04)

// Offsets inside JERRY's 64 KiB block.
const jerry_registers_end = u32(0x40)
const joystick = u32(0x4000)
const joybuts = u32(0x4002)
const eeprom_clock = u32(0x4800)
const eeprom_select = u32(0x5000)
const dsp_ctrl = u32(0xa100)
const dsp_ctrl_end = u32(0xa124)
const i2s = u32(0xa140)
const i2s_end = u32(0xa158)
const dsp_ram = u32(0xb000)
const dsp_ram_end = u32(0xd000)
const wavetable = u32(0xd000)
const wavetable_end = u32(0xe000)

// read8 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) read8(addr u32) u8 {
	a := addr & address_mask
	if a < ram_mirror_end {
		return m.ram[a & (ram_size - 1)]
	}
	if a >= io_base {
		return m.io_read8(a)
	}
	return m.rom_read8(a)
}

// read16 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) read16(addr u32) u16 {
	a := addr & address_mask
	if a < ram_mirror_end {
		i := a & (ram_size - 2)
		return (u16(m.ram[i]) << 8) | m.ram[i + 1]
	}
	if a >= io_base {
		return m.io_read16(a & 0xff_fffe)
	}
	return (u16(m.rom_read8(a)) << 8) | m.rom_read8(a + 1)
}

// read32 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) read32(addr u32) u32 {
	a := addr & address_mask
	if a < ram_mirror_end {
		i := a & (ram_size - 4)
		return (u32(m.ram[i]) << 24) | (u32(m.ram[i + 1]) << 16) | (u32(m.ram[i + 2]) << 8) | m.ram[
			i + 3]
	}
	if a >= io_base {
		return m.io_read32(a & 0xff_fffc)
	}
	return (u32(m.read16(a)) << 16) | m.read16(a + 2)
}

// write8 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) write8(addr u32, val u8) {
	a := addr & address_mask
	if a < ram_mirror_end {
		m.ram[a & (ram_size - 1)] = val
	} else if a >= io_base {
		m.io_write8(a, val)
	}
}

// write16 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) write16(addr u32, val u16) {
	a := addr & address_mask
	if a < ram_mirror_end {
		i := a & (ram_size - 2)
		m.ram[i] = u8(val >> 8)
		m.ram[i + 1] = u8(val)
	} else if a >= io_base {
		m.io_write16(a & 0xff_fffe, val)
	}
}

// write32 implements hwtypes.Bus.
@[direct_array_access]
pub fn (mut m Machine) write32(addr u32, val u32) {
	a := addr & address_mask
	if a < ram_mirror_end {
		i := a & (ram_size - 4)
		m.ram[i] = u8(val >> 24)
		m.ram[i + 1] = u8(val >> 16)
		m.ram[i + 2] = u8(val >> 8)
		m.ram[i + 3] = u8(val)
	} else if a >= io_base {
		m.io_write32(a & 0xff_fffc, val)
	}
}

// rom_read8 reads the cartridge and boot ROM windows and the unpopulated
// DRAM bank. Bytes outside an installed image read as ones.
@[direct_array_access; inline]
fn (m &Machine) rom_read8(a u32) u8 {
	if a >= cart_base && a < bios_base {
		i := a - cart_base
		return if i < u32(m.rom.len) { m.rom[i] } else { u8(0xff) }
	}
	if a >= bios_base {
		i := a - bios_base
		return if i < u32(m.bios.len) { m.bios[i] } else { u8(0xff) }
	}
	return 0xff
}

// tom_offset folds TOM's +0x8000 window onto the primary block.
@[inline]
fn tom_offset(a u32) u32 {
	offset := a & 0xffff
	return if offset >= tom_window { offset - tom_window } else { offset }
}

// io_read32 reads a long from TOM or JERRY; `a` is long-aligned.
fn (mut m Machine) io_read32(a u32) u32 {
	if a < jerry_base {
		offset := tom_offset(a)
		if offset >= gpu_ram && offset < gpu_ram_end {
			return ram_long(m.gpu.ram, offset - gpu_ram)
		}
		if offset >= gpu_ctrl && offset < gpu_ctrl_end {
			return m.gpu.read_ctrl32(offset - gpu_ctrl)
		}
		if offset >= blitter && offset < blitter_end {
			return m.tom.blitter.read32(offset - blitter)
		}
	} else {
		offset := a & 0xffff
		if offset >= dsp_ram && offset < dsp_ram_end {
			return ram_long(m.dsp.ram, offset - dsp_ram)
		}
		if offset >= dsp_ctrl && offset < dsp_ctrl_end {
			return m.dsp.read_ctrl32(offset - dsp_ctrl)
		}
		if offset >= i2s && offset < i2s_end {
			return m.jerry.read_i2s(offset - i2s)
		}
		if offset >= wavetable && offset < wavetable_end {
			return ram_long(m.wavetable, offset - wavetable)
		}
	}
	return (u32(m.io_read16(a)) << 16) | m.io_read16(a + 2)
}

// io_read16 reads a word from TOM or JERRY; `a` is word-aligned.
fn (mut m Machine) io_read16(a u32) u16 {
	if is_long_block(a) {
		value := m.io_read32(a & 0xff_fffc)
		return if a & 2 == 0 { u16(value >> 16) } else { u16(value) }
	}
	if a < jerry_base {
		offset := tom_offset(a)
		if offset < tom_registers_end {
			if offset == tom_hc {
				m.tom.hc = m.horizontal_count()
			}
			return m.tom.read16(offset)
		}
		return 0xffff
	}
	offset := a & 0xffff
	if offset < jerry_registers_end {
		return m.jerry.read16(offset)
	}
	match offset {
		joystick {
			// Bit 0 carries the cartridge EEPROM's serial data output.
			return (m.jerry.pads.read_columns() & 0xfffe) | m.eeprom.data_out()
		}
		joybuts {
			return m.jerry.pads.read_buttons()
		}
		eeprom_select {
			m.eeprom.select()
			return 0xffff
		}
		else {
			return 0xffff
		}
	}
}

// io_read8 reads a byte from TOM or JERRY.
fn (mut m Machine) io_read8(a u32) u8 {
	if a < jerry_base {
		offset := tom_offset(a)
		if offset >= gpu_ram && offset < gpu_ram_end {
			return m.gpu.read_ram8(offset)
		}
	} else {
		offset := a & 0xffff
		if offset >= dsp_ram && offset < dsp_ram_end {
			return m.dsp.read_ram8(offset - dsp_ram)
		}
	}
	value := m.io_read16(a & 0xff_fffe)
	return if a & 1 == 0 { u8(value >> 8) } else { u8(value) }
}

// io_write32 writes a long to TOM or JERRY; `a` is long-aligned.
fn (mut m Machine) io_write32(a u32, value u32) {
	if a < jerry_base {
		offset := tom_offset(a)
		if offset >= gpu_ram && offset < gpu_ram_end {
			set_ram_long(mut m.gpu.ram, offset - gpu_ram, value)
			return
		}
		if offset >= gpu_ctrl && offset < gpu_ctrl_end {
			m.gpu.write_ctrl32(offset - gpu_ctrl, value)
			m.sync()
			return
		}
		if offset >= blitter && offset < blitter_end {
			mut bus := hwtypes.Bus(m)
			m.tom.blitter.write32(offset - blitter, value, mut bus)
			return
		}
	} else {
		offset := a & 0xffff
		if offset >= dsp_ram && offset < dsp_ram_end {
			set_ram_long(mut m.dsp.ram, offset - dsp_ram, value)
			return
		}
		if offset >= dsp_ctrl && offset < dsp_ctrl_end {
			m.dsp.write_ctrl32(offset - dsp_ctrl, value)
			m.sync()
			return
		}
		if offset >= i2s && offset < i2s_end {
			m.jerry.write_i2s(offset - i2s, value)
			m.sync()
			return
		}
		if offset >= wavetable && offset < wavetable_end {
			return
		}
	}
	m.io_write16(a, u16(value >> 16))
	m.io_write16(a + 2, u16(value))
}

// io_write16 writes a word to TOM or JERRY; `a` is word-aligned.
fn (mut m Machine) io_write16(a u32, value u16) {
	if is_long_block(a) {
		m.write_long_block16(a, value)
		return
	}
	if a < jerry_base {
		offset := tom_offset(a)
		if offset < tom_registers_end {
			mut bus := hwtypes.Bus(m)
			m.tom.write16(offset, value, mut bus)
			m.sync()
		}
		return
	}
	offset := a & 0xffff
	if offset < jerry_registers_end {
		m.jerry.write16(offset, value)
		m.sync()
		return
	}
	match offset {
		joystick { m.jerry.pads.write_select(value) }
		eeprom_clock { m.eeprom.clock(value & 1 != 0) }
		eeprom_select { m.eeprom.select() }
		else {}
	}
}

// write_long_block16 delivers half of a 32-bit register.
fn (mut m Machine) write_long_block16(a u32, value u16) {
	offset := if a < jerry_base { tom_offset(a) } else { a & 0xffff }
	if a < jerry_base && offset >= blitter && offset < blitter_end {
		mut bus := hwtypes.Bus(m)
		m.tom.blitter.write16(offset - blitter, value, mut bus)
		return
	}
	if a >= jerry_base && offset >= i2s && offset < i2s_end {
		// The serial registers are 16 bits wide in the low word.
		if a & 2 != 0 {
			m.io_write32(a & 0xff_fffc, value)
		}
		return
	}
	long_addr := a & 0xff_fffc
	old := m.io_read32(long_addr)
	merged := if a & 2 == 0 {
		(old & 0x0000_ffff) | (u32(value) << 16)
	} else {
		(old & 0xffff_0000) | value
	}
	m.io_write32(long_addr, merged)
}

// io_write8 writes a byte to TOM or JERRY.
fn (mut m Machine) io_write8(a u32, value u8) {
	if a < jerry_base {
		offset := tom_offset(a)
		if offset >= gpu_ram && offset < gpu_ram_end {
			m.gpu.write_ram8(offset, value)
			return
		}
	} else {
		offset := a & 0xffff
		if offset >= dsp_ram && offset < dsp_ram_end {
			m.dsp.write_ram8(offset - dsp_ram, value)
			return
		}
	}
	word_addr := a & 0xff_fffe
	old := m.io_read16(word_addr)
	merged := if a & 1 == 0 {
		(old & 0x00ff) | (u16(value) << 8)
	} else {
		(old & 0xff00) | value
	}
	m.io_write16(word_addr, merged)
}

// is_long_block reports whether `a` lies in a block of 32-bit storage.
@[inline]
fn is_long_block(a u32) bool {
	if a < jerry_base {
		offset := tom_offset(a)
		return offset >= gpu_ctrl && offset < gpu_ram_end
			&& (offset < gpu_ctrl_end || (offset >= blitter && offset < blitter_end)
			|| offset >= gpu_ram)
	}
	offset := a & 0xffff
	return offset >= dsp_ctrl && offset < wavetable_end
		&& (offset < dsp_ctrl_end || (offset >= i2s && offset < i2s_end)
		|| offset >= dsp_ram)
}

@[direct_array_access; inline]
fn ram_long(ram []u8, offset u32) u32 {
	i := offset & u32(ram.len - 4)
	return (u32(ram[i]) << 24) | (u32(ram[i + 1]) << 16) | (u32(ram[i + 2]) << 8) | ram[i + 3]
}

@[direct_array_access; inline]
fn set_ram_long(mut ram []u8, offset u32, value u32) {
	i := offset & u32(ram.len - 4)
	ram[i] = u8(value >> 24)
	ram[i + 1] = u8(value >> 16)
	ram[i + 2] = u8(value >> 8)
	ram[i + 3] = u8(value)
}

// peek8 reads memory for a debugger or test harness. It never advances
// time, acknowledges an interrupt or clocks a device; addresses whose read
// has a side effect return zero.
pub fn (m &Machine) peek8(addr u32) u8 {
	a := addr & address_mask
	if a < ram_mirror_end {
		return m.ram[a & (ram_size - 1)]
	}
	if a < io_base {
		return m.rom_read8(a)
	}
	if a < jerry_base {
		offset := tom_offset(a)
		if offset >= gpu_ram && offset < gpu_ram_end {
			return m.gpu.read_ram8(offset)
		}
		if offset < tom_registers_end {
			value := m.tom.read16(offset & 0xfffe)
			return if a & 1 == 0 { u8(value >> 8) } else { u8(value) }
		}
		return 0
	}
	offset := a & 0xffff
	if offset >= dsp_ram && offset < dsp_ram_end {
		return m.dsp.read_ram8(offset - dsp_ram)
	}
	return 0
}

// peek32 reads a big-endian long with `peek8` semantics.
pub fn (m &Machine) peek32(addr u32) u32 {
	return (u32(m.peek8(addr)) << 24) | (u32(m.peek8(addr + 1)) << 16) | (u32(m.peek8(addr + 2)) << 8) | m.peek8(
		addr + 3)
}
