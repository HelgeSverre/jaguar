module jaggame

import jaggame.emulated
import jerry

// Save data: a record written to the EEPROM and read back by a fresh
// machine, damaged records and records of another version taken for none,
// a board without the chip, and the same as a cartridge image.

// save_game keeps a record of two fields. The pad: A sets them to 1234 and 7
// and stores them, B loads, C clears the fields (so that a load shows).
fn save_game(version int) &Game {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	save := g.save(version, ['best', 'seen'])
	mut c := g.define_update()
	c.if_(g.pressed(.a))
	c.set(save.field('best'), 1234)
	c.set(save.field('seen'), 7)
	save.store(mut c)
	c.end()
	c.if_(g.pressed(.b))
	save.load(mut c)
	c.end()
	c.if_(g.pressed(.c))
	c.set(save.field('best'), 0)
	c.set(save.field('seen'), 0)
	c.end()
	return g
}

// built is the image of the game.
fn built(version int) Image {
	mut g := save_game(version)
	return g.build() or { panic(err) }
}

fn tap(mut p emulated.Player, button jerry.Button) {
	p.press(button)
	p.frames(2)
	p.release(button)
	p.frames(1)
}

fn settle_save(img Image, p &emulated.Player) ! {
	assert img.value(p.m.ram, 'rt_save_op')! == 0, 'the operation is over'
}

fn field_of(img Image, p &emulated.Player, name string) int {
	return int(img.value(p.m.ram, 'save_${name}') or { panic(err) })
}

// the checksum of the record [mark+version, best, seen]
fn checksum(version int, best int, seen int) int {
	return (0x5a5a + 0x4700 + version + best + seen) & 0xffff
}

fn test_a_record_is_written_and_read_back_by_a_fresh_machine() {
	img := built(1)
	mut p := emulated.boot(img.bytes, false)!
	p.frames(5)
	tap(mut p, .b)
	p.frames(8)
	settle_save(img, p)!
	assert img.value(p.m.ram, 'rt_save_loaded')! == 0, 'a blank chip has no record'
	tap(mut p, .a)
	p.frames(8)
	settle_save(img, p)!
	assert img.value(p.m.ram, 'rt_save_failed')! == 0
	assert [int(p.m.eeprom.words[0]), int(p.m.eeprom.words[1]), int(p.m.eeprom.words[2]),
		int(p.m.eeprom.words[3])] == [0x4701, 1234, 7, checksum(1, 1234, 7)]
	assert p.m.eeprom.write_enabled == false, 'the writes are disabled again'

	// A new machine, started with the chip's contents.
	mut q := emulated.boot(img.bytes, true)!
	q.m.eeprom.load_bytes(p.m.eeprom.to_bytes())!
	q.frames(5)
	assert field_of(img, q, 'best') == 0
	tap(mut q, .b)
	q.frames(8)
	assert img.value(q.m.ram, 'rt_save_loaded')! == 1
	assert field_of(img, q, 'best') == 1234 && field_of(img, q, 'seen') == 7
}

fn test_a_damaged_or_foreign_record_is_none() {
	img := built(1)
	mut p := emulated.boot(img.bytes, false)!
	p.frames(5)
	tap(mut p, .a)
	p.frames(8)
	good := p.m.eeprom.to_bytes()

	// each word of the record, damaged in turn
	for word in 0 .. 4 {
		mut bad := good.clone()
		bad[word * 2 + 1] ^= 0x10
		mut q := emulated.boot(img.bytes, false)!
		q.m.eeprom.load_bytes(bad)!
		q.frames(5)
		tap(mut q, .b)
		q.frames(8)
		assert img.value(q.m.ram, 'rt_save_loaded')! == 0, 'word ${word} damaged'
		assert field_of(img, q, 'best') == 0, 'and the fields are not touched'
	}

	// the same record read by a game of another version
	other := built(2)
	mut r := emulated.boot(other.bytes, false)!
	r.m.eeprom.load_bytes(good)!
	r.frames(5)
	tap(mut r, .b)
	r.frames(8)
	assert other.value(r.m.ram, 'rt_save_loaded')! == 0
	// and a chip that was never written
	mut blank := emulated.boot(img.bytes, false)!
	blank.frames(5)
	tap(mut blank, .b)
	blank.frames(8)
	assert img.value(blank.m.ram, 'rt_save_loaded')! == 0
}

fn test_without_the_chip_a_load_says_none_a_store_says_failed_and_the_game_goes_on() {
	img := built(1)
	mut p := emulated.boot(img.bytes, false)!
	p.m.eeprom.present = false
	p.frames(5)
	tap(mut p, .a)
	p.frames(8)
	assert img.value(p.m.ram, 'rt_save_failed')! == 1
	assert img.value(p.m.ram, 'rt_save_op')! == 0
	tap(mut p, .c)
	tap(mut p, .b)
	p.frames(8)
	assert img.value(p.m.ram, 'rt_save_loaded')! == 0
	assert field_of(img, p, 'best') == 0
	before := img.value(p.m.ram, 'frame')!
	p.frames(30)
	assert img.value(p.m.ram, 'frame')! == before + 30, 'the game goes on'
	assert img.value(p.m.ram, 'missed_frames')! == 0
}

fn test_the_interpreter_saves_and_loads_what_the_machine_does() {
	img := built(1)
	mut g := save_game(1)
	mut it := g.interpreter(.ntsc)!
	mut p := emulated.boot(img.bytes, false)!
	script := [u32(0), 0, button_mask(.a), 0, 0, 0, 0, 0, 0, 0, 0, 0, button_mask(.c),
		0, 0, button_mask(.b), 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for held in script {
		g.step(mut it, held)!
		for pair in [[button_mask(.a), 0], [button_mask(.b), 1],
			[button_mask(.c), 2]] {
			button := [jerry.Button.a, .b, .c][pair[1]]
			if held & pair[0] != 0 {
				p.press(button)
			} else {
				p.release(button)
			}
		}
		p.frames(1)
	}
	mut differences := img.differences(it, p.m.ram)
	differences = differences.filter(!it.contains('rt_eeprom'))
	assert differences.len == 0, differences.join('\n')
	assert it.value('save_best')! == 1234 && it.value('rt_save_loaded')! == 1
	// the interpreter's chip holds the record, as the machine's does
	for k in 0 .. 4 {
		assert it.element('rt_eeprom', k)! == p.m.eeprom.words[k]
	}
}

fn test_the_cartridge_image_runs_and_saves_in_the_emulator() {
	img := built(1)
	rom := img.cartridge()!
	assert rom.len & (rom.len - 1) == 0 && rom.len >= 0x20000
	assert rom[0x400..0x408] == [u8(4), 4, 4, 4, 0, 0x80, 0x20, 0]
	for pal in [false, true] {
		mut p := emulated.boot(rom, pal)!
		p.frames(10)
		assert img.value(p.m.ram, 'frame')! >= 9, 'the cartridge copied the program and it runs'
		tap(mut p, .a)
		p.frames(8)
		assert p.m.eeprom.words[1] == 1234
		tap(mut p, .c)
		tap(mut p, .b)
		p.frames(8)
		assert field_of(img, p, 'best') == 1234
	}
}

// A program of more than 256 KB, which the copy loop of the first slice could
// not hold: a table of 300,000 bytes, the last of which the game reads.
fn test_a_cartridge_of_more_than_256_kb_is_copied_whole() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	mut data := []int{len: 300000}
	data[299999] = 77
	data[131072] = 55
	table := g.p.table_u8('big', data)
	last := g.p.u8('last')
	middle := g.p.u8('middle')
	mut c := g.define_update()
	c.set(last, table.at(299999))
	c.set(middle, table.at(131072))
	img := g.build()!
	assert img.bytes.len > 300000
	rom := img.cartridge()!
	assert rom.len == 0x80000
	mut p := emulated.boot(rom, false)!
	p.frames(10)
	assert img.value(p.m.ram, 'last')! == 77 && img.value(p.m.ram, 'middle')! == 55, 'the whole program was copied'
}

fn test_save_mistakes_are_reported() {
	mut g := new_game(Config{ sprites: 1, layers: 1 })
	g.art_cry('box', 8, 8, 1, []u16{len: 64, init: 1})
	save := g.save(300, ['a'])
	g.save(1, ['b'])
	mut c := g.define_update()
	c.set(save.field('nothing'), 1)
	message := build_error(mut g)
	assert message.contains('the version must be 0..255'), message
	assert message.contains('a game has one saved record'), message
	assert message.contains('there is no field `nothing`; the fields are: a'), message
}

fn build_error(mut g Game) string {
	g.build() or { return err.msg() }
	return ''
}
