module jaggame

import jagkit { imm, lbl }

// Helper routines for what the 68000 has no instruction for. Each takes
// its operands in d0 and d1 and leaves the result in d0 (and a remainder
// in d1); each may change d2..d5. They are emitted once, after the
// functions, and only when a function uses them.

fn (mut g Gen) helpers() {
	for name in ['mul32', 'divu32', 'divs32', 'fix_mul', 'fix_div'] {
		if name == 'divu32' && 'divs32' in g.needs {
			g.needs['divu32'] = true
		}
		if name in g.needs {
			g.m.label('jaggame.${name}')
			match name {
				'mul32' { g.mul32() }
				'divu32' { g.divu32() }
				'divs32' { g.divs32() }
				'fix_mul' { g.fix_mul() }
				else { g.fix_div() }
			}
		}
	}
}

// mul32 is d0 * d1, cut to 32 bits, signed or not:
// al*bl + ((ah*bl + al*bh) << 16).
fn (mut g Gen) mul32() {
	mut m := g.m
	m.move(.l, d0, d2)
	m.move(.l, d1, d3)
	m.swap(d2) // ah
	m.mulu(d1, d2) // ah * bl
	m.swap(d3) // bh
	m.mulu(d0, d3) // al * bh
	m.add(.w, d3, d2) // only the low word survives the shift
	m.swap(d2)
	m.clr(.w, d2)
	m.mulu(d1, d0) // al * bl
	m.add(.l, d2, d0)
	m.rts()
}

// divu32 divides d0 by d1, unsigned: quotient in d0, remainder in d1, both
// 0 when d1 is 0. It shifts the dividend through the remainder one bit at
// a time and subtracts the divisor where it fits (restoring division).
fn (mut g Gen) divu32() {
	mut m := g.m
	m.tst(.l, d1)
	m.b(.ne, 'jaggame.divu32.go')
	m.moveq(0, d0)
	m.rts()
	m.label('jaggame.divu32.go')
	m.moveq(0, d2) // remainder
	m.moveq(31, d3)
	m.label('jaggame.divu32.bit')
	m.add(.l, d0, d0) // the next dividend bit goes to X
	m.roxl(.l, imm(1), d2)
	m.b(.cs, 'jaggame.divu32.fits') // the remainder overflowed: it is surely >= the divisor
	m.cmp(.l, d1, d2)
	m.b(.cs, 'jaggame.divu32.next')
	m.label('jaggame.divu32.fits')
	m.sub(.l, d1, d2)
	m.add(.l, imm(1), d0) // the quotient bit
	m.label('jaggame.divu32.next')
	m.dbra(d3, 'jaggame.divu32.bit')
	m.move(.l, d2, d1)
	m.rts()
}

// divs32 divides d0 by d1, signed, rounding toward zero: the quotient has
// the sign of the operands, the remainder the sign of the dividend.
// d4 bit 0: negate the quotient; bit 1: negate the remainder.
fn (mut g Gen) divs32() {
	mut m := g.m
	m.moveq(0, d4)
	m.tst(.l, d0)
	m.b(.pl, 'jaggame.divs32.a')
	m.neg(.l, d0)
	m.moveq(3, d4)
	m.label('jaggame.divs32.a')
	m.tst(.l, d1)
	m.b(.pl, 'jaggame.divs32.b')
	m.neg(.l, d1)
	m.eor(.l, imm(1), d4)
	m.label('jaggame.divs32.b')
	m.jsr(lbl('jaggame.divu32'))
	m.btst(0, d4)
	m.b(.eq, 'jaggame.divs32.q')
	m.neg(.l, d0)
	m.label('jaggame.divs32.q')
	m.btst(1, d4)
	m.b(.eq, 'jaggame.divs32.r')
	m.neg(.l, d1)
	m.label('jaggame.divs32.r')
	m.rts()
}

// fix_mul is the 16.16 product of d0 and d1, rounded down: bits 16..47 of
// the signed 64-bit product. From the unsigned product of the halves,
//   (ah*bh << 16) + al*bh + ah*bl + (al*bl >> 16)
// and, for each negative operand, the other operand << 16 taken away.
// Carries above bit 47 do not matter.
fn (mut g Gen) fix_mul() {
	mut m := g.m
	m.move(.l, d0, d2)
	m.swap(d2) // ah
	m.move(.l, d1, d3)
	m.swap(d3) // bh
	m.move(.w, d2, d4)
	m.mulu(d3, d4) // ah * bh
	m.swap(d4)
	m.clr(.w, d4)
	m.move(.w, d0, d5)
	m.mulu(d3, d5) // al * bh
	m.add(.l, d5, d4)
	m.move(.w, d2, d5)
	m.mulu(d1, d5) // ah * bl
	m.add(.l, d5, d4)
	m.move(.w, d0, d5)
	m.mulu(d1, d5) // al * bl
	m.clr(.w, d5)
	m.swap(d5)
	m.add(.l, d5, d4)
	m.tst(.l, d0)
	m.b(.pl, 'jaggame.fix_mul.a')
	m.move(.l, d1, d5)
	m.swap(d5)
	m.clr(.w, d5)
	m.sub(.l, d5, d4)
	m.label('jaggame.fix_mul.a')
	m.tst(.l, d1)
	m.b(.pl, 'jaggame.fix_mul.b')
	m.move(.l, d0, d5)
	m.swap(d5)
	m.clr(.w, d5)
	m.sub(.l, d5, d4)
	m.label('jaggame.fix_mul.b')
	m.move(.l, d4, d0)
	m.rts()
}

// fix_div is the 16.16 quotient of d0 and d1, rounded toward zero, cut to
// 32 bits; 0 when d1 is 0. The magnitudes are divided as a 64-bit
// dividend (|a| << 16, in d5:d0) by a 32-bit divisor, the same way as
// divu32, and the low 32 bits of the quotient are kept.
fn (mut g Gen) fix_div() {
	mut m := g.m
	m.tst(.l, d1)
	m.b(.ne, 'jaggame.fix_div.go')
	m.moveq(0, d0)
	m.rts()
	m.label('jaggame.fix_div.go')
	m.moveq(0, d4)
	m.tst(.l, d0)
	m.b(.pl, 'jaggame.fix_div.a')
	m.neg(.l, d0)
	m.moveq(1, d4)
	m.label('jaggame.fix_div.a')
	m.tst(.l, d1)
	m.b(.pl, 'jaggame.fix_div.b')
	m.neg(.l, d1)
	m.eor(.l, imm(1), d4)
	m.label('jaggame.fix_div.b')
	m.move(.l, d0, d5)
	m.clr(.w, d5)
	m.swap(d5) // high long: |a| >> 16
	m.swap(d0)
	m.clr(.w, d0) // low long: |a| << 16
	m.moveq(0, d2) // remainder
	m.moveq(63, d3)
	m.label('jaggame.fix_div.bit')
	m.add(.l, d0, d0)
	m.roxl(.l, imm(1), d5)
	m.roxl(.l, imm(1), d2)
	m.b(.cs, 'jaggame.fix_div.fits')
	m.cmp(.l, d1, d2)
	m.b(.cs, 'jaggame.fix_div.next')
	m.label('jaggame.fix_div.fits')
	m.sub(.l, d1, d2)
	m.add(.l, imm(1), d0)
	m.label('jaggame.fix_div.next')
	m.dbra(d3, 'jaggame.fix_div.bit')
	m.btst(0, d4)
	m.b(.eq, 'jaggame.fix_div.done')
	m.neg(.l, d0)
	m.label('jaggame.fix_div.done')
	m.rts()
}
