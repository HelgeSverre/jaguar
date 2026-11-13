module jagkit

fn test_a_movei_in_a_delay_slot_is_reported() {
	mut r := new_risc(gpu_ram)
	r.label('top')
	r.jr(.always, 'top')
	r.movei(1, .r0)
	message := if _ := r.assemble() { '' } else { err.msg() }
	assert message.contains('movei at 0xf03002 is in the delay slot of a jump')
}

fn test_a_jump_in_a_delay_slot_is_reported() {
	mut r := new_risc(gpu_ram)
	r.label('top')
	r.jump(.always, .r1)
	r.jr(.ne, 'top')
	r.nop()
	message := if _ := r.assemble() { '' } else { err.msg() }
	assert message.contains('jr at 0xf03002 is in the delay slot of a jump')
}

fn test_ordinary_delay_slots_are_accepted() {
	mut r := new_risc(gpu_ram)
	r.label('top')
	r.subq(1, .r0)
	r.jr(.ne, 'top')
	r.addqt(4, .r1)
	r.movei(5, .r2) // after the slot, not in it
	r.jump(.always, .r3)
	r.nop()
	r.assemble()!
}

fn test_a_program_too_large_for_its_ram_is_reported() {
	mut gpu := new_risc(gpu_ram)
	for _ in 0 .. gpu_ram_size / 2 + 1 {
		gpu.nop()
	}
	message := if _ := gpu.assemble() { '' } else { err.msg() }
	assert message.contains('2 bytes past the end of its RAM at 0xf04000')

	mut full := new_risc(dsp_ram)
	for _ in 0 .. dsp_ram_size / 2 {
		full.nop()
	}
	full.assemble()!

	// A program assembled for main memory has no such limit.
	mut elsewhere := new_risc(0x10000)
	for _ in 0 .. 5000 {
		elsewhere.nop()
	}
	elsewhere.assemble()!
}

fn test_regions_that_fit_are_accepted() {
	check_regions([
		Region{'image', 0x4000, 0x1000},
		Region{'list', 0x5000, 64},
		Region{'buffer', 0x1f0000, 0x10000},
	])!
}

fn test_overlapping_regions_are_reported() {
	message := if _ := check_regions([
		Region{'image', 0x4000, 0x7d000},
		Region{'list', 0x80000, 64},
		Region{'buffer', 0x1f8000, 0x10000},
		Region{'empty', 0x100, 0},
	])
	{
		''
	} else {
		err.msg()
	}
	assert message.contains('`image` (0x004000..0x081000) and `list` (0x080000..0x080040) overlap')
	assert message.contains('`buffer` ends at 0x208000, past the end of memory')
	assert message.contains('`empty` has no size')
}

fn test_printing_a_character_the_font_lacks_is_reported() {
	mut m := new_m68k(0x4000)
	m.text_routines(TextScreen{ address: 0x80000 })
	m.print_at(0, 0, 'FINE')
	m.print_at(0, 1, 'lower')
	message := if _ := m.assemble() { '' } else { err.msg() }
	assert message.contains('the font has no `l` (in "lower")')
	assert !message.contains('FINE')
}

fn test_a_text_screen_describes_its_own_bitmap() {
	screen := TextScreen{
		address: 0x80000
		rows:    2
	}
	assert screen.bytes() == 640
	bitmap := screen.bitmap(16, 40, 17)
	assert bitmap.width == 320 && bitmap.height == 16 && bitmap.palette == 16
	object_list(0x90000, ntsc, [bitmap])!
}
