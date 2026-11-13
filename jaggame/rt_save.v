module jaggame

import jagkit { imm, lbl }

// Save data: a small record that survives the power being switched off.
//
// What is real. A Jaguar cartridge can carry a serial EEPROM (a 93C46 type
// part: 64 words of 16 bits, 128 bytes), wired to three addresses in JERRY's
// range: $F14000 (bit 0 reads the chip's data out), $F14800 (a word write
// sends a bit to the chip's data in; a read is the clock strobe) and $F15000
// (an access is the chip select). The chip is on the cartridge board, not
// in the console. A `.jag` image is loaded into RAM by a tool (a Jaguar
// Server, a flash cartridge) and runs on whatever cartridge board it was
// loaded through, so it has an EEPROM only if that board has one; a game
// that must keep its record writes it as a cartridge image (`Image.cartridge`)
// for a board that has one. The emulator has the chip always, saves its
// contents next to the image's hash and gives it back on the next start.
//
// What this does. `game.save(version, fields)` declares a record of 16-bit
// fields, held in ordinary variables (`save.field(name)`). `store` writes it,
// `load` reads it and `busy` says an operation is going on: one word of the
// EEPROM is moved a frame, so that the slow part of a write (up to 10
// milliseconds a word on a real chip) never keeps a frame from being ready.
// The record in the EEPROM is a header word (a mark and the version), the
// fields, and a checksum; `load` accepts it only if all three are right. A
// chip that is missing, blank, written by another version or damaged gives
// "none": `loaded` stays false, the fields keep their values and the game
// goes on. A `store` that does not read back as written (no chip, a chip that
// does not take writes) sets `failed`.

const save_mark = 0x4700
const save_seed = 0x5a5a
const eeprom_words_total = 64

// Save is a handle on the game's saved record.
pub struct Save {
pub:
	version int
	fields  []string
	values  []Expr // u16: the fields, in order
	words   Expr   // u16 array: the record as it is in the EEPROM
	op      Expr   // u8: 0 nothing is going on, 1 reading, 2 writing
	at      Expr   // u8: the word the operation is on
	loaded  Expr   // bool: the last `load` found a good record
	failed  Expr   // bool: the last `store` did not read back as written
	game    &Game
}

// SaveInfo is what the build keeps of a save record.
struct SaveInfo {
	save   Save
	eeprom Expr // u16 array: the interpreter's chip
	read   Func
	write  Func
	tick   Func
}

// save declares the game's record: `fields` are the names of 16-bit
// values, up to 16, kept in `Save.field(name)`; `version` (0..255) goes into
// the record, and a record of another version is not read: change it when
// the fields change. A game has one record. The variables start at 0.
pub fn (mut g Game) save(version int, fields []string) Save {
	if g.save_info.len > 0 {
		g.problem('save: a game has one saved record')
		return g.save_info[0].save
	}
	if version < 0 || version > 255 || fields.len < 1 || fields.len > 16 {
		g.problem('save: the version must be 0..255 and the record 1..16 fields, not ${fields.len}')
	}
	mut p := g.p
	mut values := []Expr{}
	for name in fields {
		values << p.u16('save_${name}')
	}
	total := fields.len + 2
	s := Save{
		version: version
		fields:  fields
		values:  values
		words:   p.array_u16('rt_save_words', total)
		op:      p.u8('rt_save_op')
		at:      p.u8('rt_save_at')
		loaded:  p.bool('rt_save_loaded')
		failed:  p.bool('rt_save_failed')
		game:    unsafe { g }
	}
	eeprom := p.array_u16('rt_eeprom', eeprom_words_total)
	p.u8('rt_ee_present', 1)
	g.save_info << SaveInfo{
		save:   s
		eeprom: eeprom
		read:   p.func('rt_ee_read', [Param{'word', .u32}], .u16)
		write:  p.func('rt_ee_write', [Param{'word', .u32}, Param{'value', .u32}], .bool)
		tick:   p.func('rt_save_tick', [], .void)
	}
	return s
}

// field is the variable of a field of the record (a `u16`).
pub fn (s Save) field(name string) Expr {
	at := s.fields.index(name)
	if at < 0 {
		mut g := s.game
		g.problem('save: there is no field `${name}`; the fields are: ${s.fields.join(', ')}')
		return invalid('no save field ${name}')
	}
	return s.values[at]
}

// busy is true while a `load` or a `store` is going on (a `bool`).
pub fn (s Save) busy() Expr {
	return s.op.ne(0)
}

// load starts reading the record. When `busy` is false again, `loaded` says
// whether there was a good record, and if there was, the fields hold it.
pub fn (s Save) load(mut c Code) {
	c.set(s.op, 1)
	c.set(s.at, 0)
	c.set(s.loaded, false)
}

// store starts writing the fields as the record. When `busy` is false
// again, `failed` says whether the chip took it. A store that is asked for
// while another operation is going on is ignored.
pub fn (s Save) store(mut c Code) {
	total := s.fields.len + 2
	c.if_(s.op.eq(0))
	c.set(s.words.at(0), save_mark + s.version)
	mut sum := lit(save_seed + save_mark + s.version).as_(.u16)
	for k, value in s.values {
		c.set(s.words.at(1 + k), value)
		sum = sum.add(value)
	}
	c.set(s.words.at(total - 1), sum)
	c.set(s.op, 2)
	c.set(s.at, 0)
	c.set(s.failed, false)
	c.end() // idle
}

// define_save writes `rt_save_tick`, which moves one word of the record a
// frame, and the two routines that reach the chip.
fn (mut g Game) define_save() {
	info := g.save_info[0]
	s := info.save
	total := s.fields.len + 2
	mut p := g.p
	read := info.read
	write := info.write
	mut c := p.define(read)
	c.native_ret(fn [read] (mut m jagkit.M68k) {
		emit_ee_read(mut m, read)
	}, fn [read] (mut it Interpreter) ! {
		run_ee_read(mut it, read)!
	})
	c = p.define(write)
	c.native_ret(fn [write] (mut m jagkit.M68k) {
		emit_ee_write(mut m, write)
	}, fn [write] (mut it Interpreter) ! {
		run_ee_write(mut it, write)!
	})

	c = p.define(info.tick)
	i := c.local_u8('i')
	sum := c.local_u16('sum')
	c.if_(s.op.eq(1))
	c.set(s.words.at(s.at), info.read.call(s.at))
	c.inc(s.at)

	c.if_(s.at.ge(total))
	c.set(s.op, 0)
	c.set(sum, save_seed)
	c.for_(i, 0, total - 1)
	c.set(sum, sum.add(s.words.at(i)))
	c.end() // each word but the checksum

	c.if_(s.words.at(0).eq(save_mark + s.version).both(s.words.at(total - 1).eq(sum)))
	for k, value in s.values {
		c.set(value, s.words.at(1 + k))
	}
	c.set(s.loaded, true)
	c.end() // a good record
	c.end() // the last word was read
	c.else_if(s.op.eq(2))

	c.if_(info.write.call(s.at, s.words.at(s.at)).invert())
	c.set(s.failed, true)
	c.set(s.op, 0)
	c.else_()
	c.inc(s.at)

	c.if_(s.at.ge(total))
	c.set(s.op, 0)
	c.end() // the last word was written
	c.end() // taken or not
	c.end() // reading or writing
}

// emit_save_routines writes the 68000 routines that talk to the chip the way
// the standard driver does: a chip select is an access to $F15000, a bit
// is a word write to $F14800 (the bit in bit 0), the clock for a bit of data
// out is a read of $F14800 and the data is bit 0 of $F14000.
fn (g &Game) emit_save_routines(mut m jagkit.M68k) {
	// rt.ee_select
	m.label('rt.ee_select')
	m.tst(.w, jagkit.abs(0xf15000))
	m.rts()

	// rt.ee_send: d1 holds the bits, d4 the number of them less one; the
	// most significant is sent first. d0 and d4 change.
	m.label('rt.ee_send')
	m.label('rt.ee_bit')
	m.move(.l, jagkit.d1, jagkit.d0)
	m.lsr(.l, jagkit.d4, jagkit.d0)
	m.and(.w, imm(1), jagkit.d0)
	m.move(.w, jagkit.d0, jagkit.abs(0xf14800))
	m.dbra(jagkit.d4, 'rt.ee_bit')
	m.rts()

	// rt.ee_read_word: d3 is the word, the result is in d0. d1, d2, d4 and
	// d5 change.
	m.label('rt.ee_read_word')
	m.bsr('rt.ee_select')
	m.move(.l, jagkit.d3, jagkit.d1)
	m.orr(.w, imm(0x180), jagkit.d1)
	m.moveq(8, jagkit.d4)
	m.bsr('rt.ee_send')
	m.moveq(0, jagkit.d2)
	m.moveq(15, jagkit.d5)
	m.label('rt.ee_in')
	m.tst(.w, jagkit.abs(0xf14800))
	m.move(.w, jagkit.abs(0xf14000), jagkit.d0)
	m.and(.w, imm(1), jagkit.d0)
	m.add(.w, jagkit.d2, jagkit.d2)
	m.orr(.w, jagkit.d0, jagkit.d2)
	m.dbra(jagkit.d5, 'rt.ee_in')
	m.moveq(0, jagkit.d0)
	m.move(.w, jagkit.d2, jagkit.d0)
	m.rts()

	// rt.ee_write_word: d3 is the word and a2 the value; d0 is 1 when the
	// word reads back as written. The write is enabled, started, waited for
	// (up to a few milliseconds, longer than a chip needs) and disabled again.
	m.label('rt.ee_write_word')
	m.bsr('rt.ee_select')
	m.move(.w, imm(0x130), jagkit.d1)
	m.moveq(8, jagkit.d4)
	m.bsr('rt.ee_send')
	m.bsr('rt.ee_select')
	m.move(.l, jagkit.d3, jagkit.d1)
	m.orr(.w, imm(0x140), jagkit.d1)
	m.moveq(8, jagkit.d4)
	m.bsr('rt.ee_send')
	m.move(.l, jagkit.a2, jagkit.d1)
	m.moveq(15, jagkit.d4)
	m.bsr('rt.ee_send')
	m.bsr('rt.ee_select')
	m.move(.w, imm(8000), jagkit.d5)
	m.label('rt.ee_busy')
	m.move(.w, jagkit.abs(0xf14000), jagkit.d0)
	m.btst(0, jagkit.d0)
	m.b(.ne, 'rt.ee_ready')
	m.dbra(jagkit.d5, 'rt.ee_busy')
	m.label('rt.ee_ready')
	m.bsr('rt.ee_select')
	m.move(.w, imm(0x100), jagkit.d1)
	m.moveq(8, jagkit.d4)
	m.bsr('rt.ee_send')
	m.bsr('rt.ee_read_word')
	m.move(.l, jagkit.a2, jagkit.d1)
	m.cmp(.w, jagkit.d1, jagkit.d0)
	m.b(.ne, 'rt.ee_bad')
	m.moveq(1, jagkit.d0)
	m.rts()
	m.label('rt.ee_bad')
	m.moveq(0, jagkit.d0)
	m.rts()
}

// emit_ee_read writes the body of `rt_ee_read(word)`: the word's value.
fn emit_ee_read(mut m jagkit.M68k, f Func) {
	m.move(.l, lbl('${f.name}.word'), jagkit.d3)
	m.and(.l, imm(63), jagkit.d3)
	m.bsr('rt.ee_read_word')
}

// emit_ee_write writes the body of `rt_ee_write(word, value)`: true when the
// chip kept it.
fn emit_ee_write(mut m jagkit.M68k, f Func) {
	m.move(.l, lbl('${f.name}.word'), jagkit.d3)
	m.and(.l, imm(63), jagkit.d3)
	m.move(.l, lbl('${f.name}.value'), jagkit.a2)
	m.bsr('rt.ee_write_word')
}

// run_ee_read is what the interpreter does for `rt_ee_read`: its EEPROM is
// the array `rt_eeprom` (erased is 0xffff), unless `rt_ee_present` is 0,
// which reads as erased.
fn run_ee_read(mut it Interpreter, f Func) ! {
	word := it.get_label('${f.name}.word', 0)! & 63
	it.result = if it.get_label('rt_ee_present', 0)! != 0 {
		it.get_label('rt_eeprom', int(word))!
	} else {
		i64(0xffff)
	}
}

// run_ee_write is what the interpreter does for `rt_ee_write`.
fn run_ee_write(mut it Interpreter, f Func) ! {
	word := it.get_label('${f.name}.word', 0)! & 63
	value := it.get_label('${f.name}.value', 0)! & 0xffff
	if it.get_label('rt_ee_present', 0)! == 0 {
		it.result = 0
		return
	}
	it.put_label('rt_eeprom', int(word), value)!
	it.result = 1
}
