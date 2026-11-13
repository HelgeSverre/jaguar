module cart

// send clocks `count` bits of `value` into the device, most significant first.
fn send(mut e Eeprom, value u32, count int) {
	for bit := count - 1; bit >= 0; bit-- {
		e.clock((value >> u32(bit)) & 1 != 0)
	}
}

// command sends a start bit, a two-bit opcode and a six-bit address.
fn command(mut e Eeprom, opcode u32, address u32) {
	e.select()
	send(mut e, 1, 1)
	send(mut e, opcode, 2)
	send(mut e, address, 6)
}

// read_word issues READ and clocks the sixteen data bits out.
fn read_word(mut e Eeprom, address u32) u16 {
	command(mut e, 2, address)
	assert e.data_out() == 0, 'a dummy zero precedes the data'
	mut value := u16(0)
	for _ in 0 .. 16 {
		e.clock(false)
		value = (value << 1) | e.data_out()
	}
	return value
}

fn write_word(mut e Eeprom, address u32, value u16) {
	command(mut e, 1, address)
	send(mut e, value, 16)
}

fn test_erased_device_reads_ones() {
	mut e := new_eeprom()
	assert read_word(mut e, 0) == 0xffff
	assert read_word(mut e, 63) == 0xffff
	assert !e.dirty
}

fn test_write_needs_write_enable() {
	mut e := new_eeprom()
	write_word(mut e, 5, 0x1234)
	assert read_word(mut e, 5) == 0xffff, 'writes are ignored until EWEN'
	command(mut e, 0, 0x30) // EWEN
	write_word(mut e, 5, 0x1234)
	assert e.data_out() == 1, 'ready after the write'
	assert read_word(mut e, 5) == 0x1234
	assert e.dirty
	command(mut e, 0, 0x00) // EWDS
	write_word(mut e, 5, 0xbeef)
	assert read_word(mut e, 5) == 0x1234
}

fn test_erase_and_bulk_commands() {
	mut e := new_eeprom()
	command(mut e, 0, 0x30) // EWEN
	command(mut e, 0, 0x10) // WRAL
	send(mut e, 0xa5a5, 16)
	assert read_word(mut e, 0) == 0xa5a5
	assert read_word(mut e, 40) == 0xa5a5
	command(mut e, 3, 40) // ERASE
	assert read_word(mut e, 40) == 0xffff
	assert read_word(mut e, 41) == 0xa5a5
	command(mut e, 0, 0x20) // ERAL
	assert read_word(mut e, 41) == 0xffff
}

fn test_sequential_read_continues_into_the_next_word() {
	mut e := new_eeprom()
	command(mut e, 0, 0x30)
	write_word(mut e, 1, 0x00ff)
	write_word(mut e, 2, 0x8001)
	assert read_word(mut e, 1) == 0x00ff
	mut next := u16(0)
	for _ in 0 .. 16 {
		e.clock(false)
		next = (next << 1) | e.data_out()
	}
	assert next == 0x8001
}

fn test_chip_select_aborts_a_command_in_flight() {
	mut e := new_eeprom()
	command(mut e, 0, 0x30)
	command(mut e, 1, 7)
	send(mut e, 0xff, 8) // half a data word
	e.select()
	assert read_word(mut e, 7) == 0xffff, 'the partial write never landed'
}

fn test_image_round_trip_and_size_check() {
	mut e := new_eeprom()
	command(mut e, 0, 0x30)
	write_word(mut e, 0, 0x1234)
	write_word(mut e, 63, 0xabcd)
	bytes := e.to_bytes()
	assert bytes.len == 128
	assert bytes[0] == 0x12 && bytes[1] == 0x34 && bytes[126] == 0xab && bytes[127] == 0xcd
	mut restored := new_eeprom()
	restored.load_bytes(bytes)!
	assert read_word(mut restored, 63) == 0xabcd
	assert !restored.dirty, 'loading an image is not a guest write'
	restored.load_bytes([]u8{len: 5}) or {
		assert err.msg().contains('128')
		return
	}
	assert false, 'a short image must be rejected'
}

// read_by_strobes issues READ and clocks the data out the Atari-standard
// way: a strobe (a read of the clock address), then a sample of the output.
fn read_by_strobes(mut e Eeprom, address u32) u16 {
	command(mut e, 2, address)
	mut value := u16(0)
	for _ in 0 .. 16 {
		e.strobe()
		value = (value << 1) | e.data_out()
	}
	return value
}

fn test_a_read_can_be_clocked_by_strobes_and_sampling_does_not_advance_it() {
	mut e := new_eeprom()
	command(mut e, 0, 0x30) // EWEN
	write_word(mut e, 9, 0x8f01)
	assert read_by_strobes(mut e, 9) == 0x8f01
	// Sampling the output again and again does not move it on.
	command(mut e, 2, 9)
	e.strobe()
	first := e.data_out()
	for _ in 0 .. 20 {
		assert e.data_out() == first
	}
	// A strobe outside a READ does nothing.
	e.select()
	e.strobe()
	assert e.data_out() == first
}

fn test_a_board_without_the_chip_stores_nothing_and_reads_ones() {
	mut e := new_eeprom()
	e.present = false
	command(mut e, 0, 0x30) // EWEN
	write_word(mut e, 5, 0x1234)
	assert read_by_strobes(mut e, 5) == 0xffff
	assert !e.dirty
}
