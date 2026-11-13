module jagkit

// The code shown in README.md and docs/jagkit.md that is not taken from a
// demo is kept here, so that it is known to assemble.

fn test_the_68000_example_assembles() {
	mut m := new_m68k(0x4000)
	m.label('ball_x')
	m.word(0)
	m.move(.w, lbl('ball_x'), d0)
	m.add(.w, imm(2), d0)
	m.cmp(.w, imm(288), d0) // flags of d0 - 288
	m.b(.hi, 'skip') // branch if d0 > 288, unsigned
	m.move(.w, d0, lbl('ball_x'))
	m.label('skip')
	m.assemble()!
}

fn test_the_risc_examples_assemble() {
	mut g := new_risc(gpu_ram)
	target := Reg.r0
	left := Reg.r1
	zero := Reg.r2
	g.label('clear')
	g.store(zero, target) // write a long
	g.subq(1, left)
	g.jr(.ne, 'clear')
	g.addqt(4, target) // delay slot: runs before the jump takes effect

	// The one in README.md.
	texture := Reg.r3
	pixel := Reg.r4
	g.label('next')
	g.loadw(texture, pixel) // fetch a texel
	g.storew(pixel, target) // put it on screen
	g.subq(1, left)
	g.jr(.ne, 'next')
	g.addqt(2, target) // delay slot
	g.assemble()!
}

fn test_the_variable_printing_example_assembles() {
	mut m := new_m68k(0x4000)
	m.text_routines(TextScreen{ address: 0x81000 })
	m.label('score')
	m.word(0)
	m.move(.w, lbl('score'), d0)
	m.bsr('number')
	m.moveq(30, d0) // column
	m.moveq(0, d1) // row
	m.bsr('print')
	m.rts()
	m.assemble()!
}
