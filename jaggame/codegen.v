module jaggame

import jagkit { imm, lbl }

// The code generator turns the typed IR into 68000 code through
// jagkit.M68k. The scheme is chosen to be obviously right rather than
// fast:
//
// - Every expression leaves its value in d0 as a whole long, sign- or
//   zero-extended from its type. Operations work on longs and cut the
//   result back to the type, which is how the interpreter wraps.
// - The left operand of a binary operation waits on the stack while the
//   right one is evaluated; then the left is in d0 and the right in d1.
// - Nothing lives in a register from one statement to the next. Variables,
//   parameters and locals have fixed addresses in a data area after the
//   code.
// - d0..d5 and a0 are used; a5, a6 and d7 are left to the runtime.
// - Multiplication of longs, division, modulo and the fixed-point
//   operations call helper routines (codegen_helpers.v), which are emitted
//   only when used.

const d0 = jagkit.d0
const d1 = jagkit.d1
const d2 = jagkit.d2
const d3 = jagkit.d3
const d4 = jagkit.d4
const d5 = jagkit.d5
const a0 = jagkit.a0
const sp = jagkit.sp

struct LoopLabels {
	cont string
	exit string
}

struct Gen {
	low &Lowered
mut:
	m     &jagkit.M68k
	exit  string
	loops []LoopLabels
	needs map[string]bool
}

// emit compiles every defined function of the program into `m`, followed
// by the helper routines they use and the program's data. A function's
// code starts at a label with the function's name and a variable's
// storage at a label with its name; parameters and locals are
// `function.name`. A function is called with `jsr`; its parameters are
// stored at their labels first, and its result comes back in d0. It may
// change d0..d5 and a0..a4.
pub fn (p &Program) emit(mut m jagkit.M68k) ! {
	p.emit_lowered(mut m)!
}

fn (p &Program) emit_lowered(mut m jagkit.M68k) !&Lowered {
	low := p.lower()!
	mut g := Gen{
		low: low
		m:   m
	}
	for f in low.funcs {
		if f.defined {
			g.function(f)
		}
	}
	g.helpers()
	g.data()
	return low
}

fn (mut g Gen) function(f LFunc) {
	g.m.label(f.name)
	for v in f.locals {
		var := g.low.vars[v]
		g.m.clr(size_of(var.typ), lbl(var.label))
	}
	g.exit = 'jaggame.exit.${f.name}'
	g.block(f.body)
	g.m.label(g.exit)
	g.m.rts()
}

fn size_of(t Type) jagkit.Size {
	return match t.size() {
		1 { jagkit.Size.b }
		2 { .w }
		else { .l }
	}
}

fn (mut g Gen) block(stmts []TStmt) {
	for s in stmts {
		g.stmt(s)
	}
}

fn (mut g Gen) stmt(s TStmt) {
	match s.kind {
		.set {
			g.set(s.place, s.exprs[0])
		}
		.branch {
			end := g.m.unique('jaggame.end')
			for i, cond in s.exprs {
				next := g.m.unique('jaggame.next')
				g.expr(cond)
				g.m.tst(.l, d0)
				g.m.b(.eq, next)
				g.block(s.bodies[i])
				g.m.bra(end)
				g.m.label(next)
			}
			g.block(s.bodies[s.bodies.len - 1])
			g.m.label(end)
		}
		.loop {
			top := g.m.unique('jaggame.loop')
			labels := LoopLabels{
				cont: g.m.unique('jaggame.continue')
				exit: g.m.unique('jaggame.break')
			}
			g.m.label(top)
			g.expr(s.exprs[0])
			g.m.tst(.l, d0)
			g.m.b(.eq, labels.exit)
			g.loops << labels
			g.block(s.bodies[0])
			g.m.label(labels.cont)
			g.block(s.bodies[1])
			g.loops.pop()
			g.m.bra(top)
			g.m.label(labels.exit)
		}
		.eval {
			g.expr(s.exprs[0])
		}
		.ret {
			if s.exprs.len > 0 {
				g.expr(s.exprs[0])
			}
			g.m.bra(g.exit)
		}
		.break_ {
			g.m.bra(g.loops[g.loops.len - 1].exit)
		}
		.continue_ {
			g.m.bra(g.loops[g.loops.len - 1].cont)
		}
		.asm {
			emit := g.low.asms[s.asm]
			emit(mut g.m)
		}
	}
}

fn (mut g Gen) push() {
	g.m.move(.l, d0, jagkit.dec(sp))
}

fn (mut g Gen) pop(r jagkit.Ea) {
	g.m.move(.l, jagkit.inc(sp), r)
}

// set stores a value. As in the interpreter, the destination's index is
// evaluated first.
fn (mut g Gen) set(place TPlace, value TExpr) {
	if place.index.len == 0 {
		g.expr(value)
		g.m.move(size_of(place.typ), d0, lbl(g.low.vars[place.var].label))
		return
	}
	g.index(place)
	g.push()
	g.expr(value)
	g.pop(d1)
	g.m.lea(lbl(g.low.vars[place.var].label), a0)
	g.m.add(.l, d1, a0)
	g.m.move(size_of(place.typ), d0, g.field_ea(place))
}

// index leaves the byte offset of an element in d0.
fn (mut g Gen) index(place TPlace) {
	g.expr(place.index[0])
	mut left := place.shift
	for left > 0 {
		n := if left > 8 { 8 } else { left }
		g.m.lsl(.l, imm(n), d0)
		left -= n
	}
}

fn (g &Gen) field_ea(place TPlace) jagkit.Ea {
	if place.offset == 0 {
		return jagkit.ind(a0)
	}
	return jagkit.at(place.offset, a0)
}

// place_ea is the operand that reaches a place, computing an element's
// address into a0 first.
fn (mut g Gen) place_ea(place TPlace) jagkit.Ea {
	if place.index.len == 0 {
		return lbl(g.low.vars[place.var].label)
	}
	g.index(place)
	g.m.lea(lbl(g.low.vars[place.var].label), a0)
	g.m.add(.l, d0, a0)
	return g.field_ea(place)
}

fn (mut g Gen) load(place TPlace) {
	ea := g.place_ea(place)
	t := place.typ
	match t {
		.bool, .u8 {
			g.m.moveq(0, d0)
			g.m.move(.b, ea, d0)
		}
		.i8 {
			g.m.move(.b, ea, d0)
			g.m.ext(.w, d0)
			g.m.ext(.l, d0)
		}
		.u16 {
			g.m.moveq(0, d0)
			g.m.move(.w, ea, d0)
		}
		.i16 {
			g.m.move(.w, ea, d0)
			g.m.ext(.l, d0)
		}
		else {
			g.m.move(.l, ea, d0)
		}
	}
}

// normalize cuts d0 to a type and extends it back to a long.
fn (mut g Gen) normalize(t Type) {
	match t {
		.u8 {
			g.m.and(.l, imm(0xff), d0)
		}
		.i8 {
			g.m.ext(.w, d0)
			g.m.ext(.l, d0)
		}
		.u16 {
			g.m.and(.l, imm(0xffff), d0)
		}
		.i16 {
			g.m.ext(.l, d0)
		}
		else {}
	}
}

fn (mut g Gen) constant(value i64) {
	if value >= -128 && value <= 127 {
		g.m.moveq(int(value), d0)
	} else {
		g.m.move(.l, imm(value), d0)
	}
}

fn (mut g Gen) expr(e TExpr) {
	match e.kind {
		.constant {
			g.constant(e.value)
		}
		.load {
			g.load(e.place)
		}
		.unary {
			g.expr(e.args[0])
			g.unary(e.op)
			g.normalize(e.typ)
		}
		.binary {
			g.operands(e)
			g.binary(e.op, e.typ)
			g.normalize(e.typ)
		}
		.compare {
			g.operands(e)
			g.compare(e.op, e.args[0].typ)
		}
		.logic {
			end := g.m.unique('jaggame.logic')
			g.expr(e.args[0])
			g.m.tst(.l, d0)
			g.m.b(if e.op == .both { jagkit.Cc.eq } else { jagkit.Cc.ne }, end)
			g.expr(e.args[1])
			g.m.label(end)
		}
		.convert {
			g.expr(e.args[0])
			g.convert(e.args[0].typ, e.typ)
		}
		.call {
			g.call(e)
		}
	}
}

// operands leaves the left operand in d0 and the right one in d1.
fn (mut g Gen) operands(e TExpr) {
	g.expr(e.args[0])
	g.push()
	g.expr(e.args[1])
	g.m.move(.l, d0, d1)
	g.pop(d0)
}

fn (mut g Gen) unary(op Op) {
	match op {
		.neg {
			g.m.neg(.l, d0)
		}
		.not_ {
			g.m.not(.l, d0)
		}
		.invert {
			g.m.eor(.l, imm(1), d0)
		}
		else {
			done := g.m.unique('jaggame.abs')
			g.m.tst(.l, d0)
			g.m.b(.pl, done)
			g.m.neg(.l, d0)
			g.m.label(done)
		}
	}
}

fn (mut g Gen) helper(name string) {
	g.needs[name] = true
	g.m.jsr(lbl('jaggame.${name}'))
}

fn (mut g Gen) binary(op Op, t Type) {
	match op {
		.add {
			g.m.add(.l, d1, d0)
		}
		.sub {
			g.m.sub(.l, d1, d0)
		}
		.and_ {
			g.m.and(.l, d1, d0)
		}
		.or_ {
			g.m.orr(.l, d1, d0)
		}
		.xor {
			g.m.eor(.l, d1, d0)
		}
		.mul {
			if t == .fix {
				g.helper('fix_mul')
			} else if t.size() <= 2 {
				// The low word of a 16 x 16 product is all a narrow type keeps.
				g.m.mulu(d1, d0)
			} else {
				g.helper('mul32')
			}
		}
		.div, .mod {
			if op == .div && t == .fix {
				g.helper('fix_div')
			} else if t.is_signed() {
				g.helper('divs32')
			} else {
				g.helper('divu32')
			}
			if op == .mod {
				g.m.move(.l, d1, d0)
			}
		}
		.shl, .shr {
			// The 68000 takes a register count modulo 64; the language masks it to
			// five bits.
			g.m.moveq(31, d2)
			g.m.and(.l, d2, d1)
			if op == .shl {
				g.m.lsl(.l, d1, d0)
			} else if t.is_signed() {
				g.m.asr(.l, d1, d0)
			} else {
				g.m.lsr(.l, d1, d0)
			}
		}
		.min, .max {
			keep := g.m.unique('jaggame.keep')
			g.m.cmp(.l, d1, d0)
			// Keep d0 when it is already the smaller (or the larger) one.
			mut cc := jagkit.Cc.cc
			if op == .min {
				cc = if t.is_signed() { jagkit.Cc.le } else { jagkit.Cc.ls }
			} else if t.is_signed() {
				cc = .ge
			}
			g.m.b(cc, keep)
			g.m.move(.l, d1, d0)
			g.m.label(keep)
		}
		else {}
	}
}

// compare sets d0 to 1 when `d0 op d1` holds, else to 0.
fn (mut g Gen) compare(op Op, t Type) {
	signed := t.is_signed()
	cc := match op {
		.eq {
			jagkit.Cc.eq
		}
		.ne {
			jagkit.Cc.ne
		}
		.lt {
			if signed { jagkit.Cc.lt } else { jagkit.Cc.cs }
		}
		.le {
			if signed { jagkit.Cc.le } else { jagkit.Cc.ls }
		}
		.gt {
			if signed { jagkit.Cc.gt } else { jagkit.Cc.hi }
		}
		else {
			if signed { jagkit.Cc.ge } else { jagkit.Cc.cc }
		}
	}

	yes := g.m.unique('jaggame.true')
	end := g.m.unique('jaggame.compared')
	g.m.cmp(.l, d1, d0)
	g.m.b(cc, yes)
	g.m.moveq(0, d0)
	g.m.bra(end)
	g.m.label(yes)
	g.m.moveq(1, d0)
	g.m.label(end)
}

fn (mut g Gen) convert(from Type, to Type) {
	if to == .bool {
		zero := g.m.unique('jaggame.zero')
		g.m.tst(.l, d0)
		g.m.b(.eq, zero)
		g.m.moveq(1, d0)
		g.m.label(zero)
		return
	}
	if from == .fix {
		if to != .fix {
			// The integer part, rounded down, is the high word.
			g.m.swap(d0)
			g.m.ext(.l, d0)
			g.normalize(to)
		}
		return
	}
	if to == .fix {
		g.m.swap(d0)
		g.m.clr(.w, d0)
		return
	}
	g.normalize(to)
}

// call evaluates the arguments onto the stack, then stores them in the
// parameters: an argument that calls the same function cannot overwrite a
// parameter already stored.
fn (mut g Gen) call(e TExpr) {
	f := g.low.funcs[e.func]
	for a in e.args {
		g.expr(a)
		g.push()
	}
	for i := e.args.len - 1; i >= 0; i-- {
		param := g.low.vars[f.params[i]]
		g.pop(d0)
		g.m.move(size_of(param.typ), d0, lbl(param.label))
	}
	g.m.jsr(lbl(f.name))
}

// data emits the variables: longs, then words, then bytes, then arrays,
// tables and records, each aligned to its element.
fn (mut g Gen) data() {
	g.m.align(4)
	for size in [4, 2, 1] {
		for v in g.low.vars {
			if v.kind == .scalar && v.typ.size() == size {
				g.m.label(v.label)
				g.value(v.typ, if v.init.len > 0 { v.init[0] } else { i64(0) })
			}
		}
	}
	for v in g.low.vars {
		if v.kind == .scalar {
			continue
		}
		g.m.align(4)
		g.m.label(v.label)
		if v.kind == .records {
			g.m.bytes([]u8{len: v.len * g.low.stride(v)})
			continue
		}
		for i in 0 .. v.len {
			g.value(v.typ, if i < v.init.len { v.init[i] } else { i64(0) })
		}
	}
	g.m.align(2)
}

fn (mut g Gen) value(t Type, raw i64) {
	match t.size() {
		1 { g.m.byte(int(raw)) }
		2 { g.m.word(int(raw)) }
		else { g.m.long(u32(raw)) }
	}
}
