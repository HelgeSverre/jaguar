// Cartridge hardware beyond the ROM itself.
module cart

// eeprom_words is the capacity of the standard cartridge EEPROM: a 93C46
// serial device organised as 64 words of 16 bits (128 bytes).
pub const eeprom_words = 64

enum Phase {
	idle    // waiting for the start bit
	command // collecting two opcode bits and six address bits
	read_out
	write_in
	write_all_in
}

// Eeprom models the serial protocol and contents of the save memory.
pub struct Eeprom {
pub mut:
	words         [eeprom_words]u16
	dirty         bool // contents differ from the last persisted image
	write_enabled bool
mut:
	phase    Phase
	shift    u32
	bits     u32
	address  u32
	data_out u8 = 1
}

// new_eeprom returns an erased device, as shipped.
pub fn new_eeprom() Eeprom {
	mut e := Eeprom{}
	for i in 0 .. eeprom_words {
		e.words[i] = 0xffff
	}
	return e
}

// select models chip select being cycled: any command in flight is dropped.
pub fn (mut e Eeprom) select() {
	e.phase = .idle
	e.bits = 0
	e.shift = 0
}

// data_out returns the level of the serial data output.
pub fn (e &Eeprom) data_out() u8 {
	return e.data_out
}

// clock shifts one bit in on the rising serial clock and updates the output.
pub fn (mut e Eeprom) clock(data_in bool) {
	bit := if data_in { u32(1) } else { u32(0) }
	match e.phase {
		.idle {
			if data_in {
				e.phase = .command
				e.shift = 0
				e.bits = 0
			}
		}
		.command {
			e.shift = (e.shift << 1) | bit
			e.bits++
			if e.bits == 8 {
				e.begin_command(e.shift >> 6, e.shift & 0x3f)
			}
		}
		.read_out {
			e.data_out = u8((e.shift >> 15) & 1)
			e.shift <<= 1
			e.bits++
			if e.bits == 16 {
				// Sequential read: the next word follows without a new command.
				e.address = (e.address + 1) % eeprom_words
				e.shift = e.words[e.address]
				e.bits = 0
			}
		}
		.write_in, .write_all_in {
			e.shift = (e.shift << 1) | bit
			e.bits++
			if e.bits == 16 {
				e.finish_write(u16(e.shift))
			}
		}
	}
}

fn (mut e Eeprom) begin_command(opcode u32, address u32) {
	e.address = address
	e.bits = 0
	e.shift = 0
	match opcode {
		2 {
			// READ: a dummy zero precedes the sixteen data bits.
			e.shift = e.words[address]
			e.data_out = 0
			e.phase = .read_out
		}
		1 {
			e.phase = .write_in
		}
		3 {
			e.store(address, 0xffff)
			e.complete()
		}
		else {
			match address >> 4 {
				3 {
					e.write_enabled = true
					e.complete()
				}
				0 {
					e.write_enabled = false
					e.complete()
				}
				2 {
					for i in u32(0) .. eeprom_words {
						e.store(i, 0xffff)
					}
					e.complete()
				}
				else {
					e.phase = .write_all_in
				}
			}
		}
	}
}

fn (mut e Eeprom) finish_write(value u16) {
	if e.phase == .write_all_in {
		for i in u32(0) .. eeprom_words {
			e.store(i, value)
		}
	} else {
		e.store(e.address, value)
	}
	e.complete()
}

// complete ends a command; the output reads "ready".
fn (mut e Eeprom) complete() {
	e.phase = .idle
	e.data_out = 1
}

// store writes one word if writes are enabled.
fn (mut e Eeprom) store(address u32, value u16) {
	if !e.write_enabled {
		return
	}
	if e.words[address] != value {
		e.words[address] = value
		e.dirty = true
	}
}

// to_bytes serialises the contents as 128 big-endian bytes.
pub fn (e &Eeprom) to_bytes() []u8 {
	mut bytes := []u8{len: eeprom_words * 2}
	for i in 0 .. eeprom_words {
		bytes[i * 2] = u8(e.words[i] >> 8)
		bytes[i * 2 + 1] = u8(e.words[i])
	}
	return bytes
}

// load_bytes replaces the contents from a persisted image.
pub fn (mut e Eeprom) load_bytes(bytes []u8) ! {
	if bytes.len != eeprom_words * 2 {
		return error('EEPROM image must be ${eeprom_words * 2} bytes, got ${bytes.len}')
	}
	for i in 0 .. eeprom_words {
		e.words[i] = (u16(bytes[i * 2]) << 8) | bytes[i * 2 + 1]
	}
	e.dirty = false
}
