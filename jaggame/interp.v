module jaggame

// The interpreter runs the typed IR in V. It is the reference semantics:
// the code generator must produce the same values for every program.
//
// Every value is kept as an i64 holding the value the type means: a `u32`
// is 0..4294967295, an `i8` is -128..127, a `fix` is its raw 32-bit
// pattern read as signed, a `bool` is 0 or 1.

// Interpreter runs a checked program. Its variables start with their
// initial values and keep them from one call to the next.
pub struct Interpreter {
	low Lowered
mut:
	memory [][]i64
	steps  i64
	result i64 // set by ret
pub mut:
	// step_limit stops a program that runs too long: each statement and each
	// turn of a loop is a step.
	step_limit i64 = 50_000_000
}

enum Flow {
	normal
	broke
	continued
	returned
}

// interpreter checks the program and prepares to run it.
pub fn (p &Program) interpreter() !Interpreter {
	low := p.lower()!
	mut memory := [][]i64{}
	for v in low.vars {
		mut values := []i64{len: low.slots(v)}
		for i, x in v.init {
			values[i] = x
		}
		memory << values
	}
	return Interpreter{
		low:    low
		memory: memory
	}
}

// run calls a function by name with raw argument values and returns its
// raw result (0 for a function that returns nothing).
pub fn (mut it Interpreter) run(name string, args ...i64) !i64 {
	id := it.low.func_named(name)
	if id < 0 {
		return error('there is no function `${name}`')
	}
	f := it.low.funcs[id]
	if args.len != f.params.len {
		return error('`${name}` takes ${f.params.len} arguments, not ${args.len}')
	}
	mut wrapped := []i64{}
	for i, a in args {
		wrapped << it.low.vars[f.params[i]].typ.wrap(a)
	}
	return it.call(id, wrapped)
}

// value is the raw value of a global variable.
pub fn (it &Interpreter) value(name string) !i64 {
	return it.element(name, 0)
}

// element is the raw value of an element of a global array or table.
pub fn (it &Interpreter) element(name string, index int) !i64 {
	var := it.low.var_named(name)
	if var < 0 || it.low.vars[var].kind == .records {
		return error('there is no global variable, array or table `${name}`')
	}
	if index < 0 || index >= it.low.vars[var].len {
		return error('`${name}` has no element ${index}')
	}
	return it.memory[var][index]
}

// field is the raw value of a field of an element of an array of records.
pub fn (it &Interpreter) field(name string, index int, field string) !i64 {
	var := it.low.var_named(name)
	if var < 0 || it.low.vars[var].kind != .records {
		return error('there is no array of records `${name}`')
	}
	r := it.low.records[it.low.vars[var].record]
	f := r.field_index(field)
	if f < 0 || index < 0 || index >= it.low.vars[var].len {
		return error('`${name}` has no element ${index} with a field `${field}`')
	}
	return it.memory[var][index * r.fields.len + f]
}

fn (mut it Interpreter) call(id int, args []i64) !i64 {
	f := it.low.funcs[id]
	if !f.defined {
		return error('`${f.name}` is not defined')
	}
	for i, v in f.params {
		it.memory[v][0] = args[i]
	}
	for v in f.locals {
		it.memory[v][0] = 0
	}
	it.result = 0
	it.block(f.body)!
	result := it.result
	it.result = 0
	return result
}

fn (mut it Interpreter) step() ! {
	it.steps++
	if it.steps > it.step_limit {
		return error('the program ran for more than ${it.step_limit} steps: an endless loop?')
	}
}

fn (mut it Interpreter) block(stmts []TStmt) !Flow {
	for s in stmts {
		it.step()!
		flow := it.stmt(s)!
		if flow != .normal {
			return flow
		}
	}
	return .normal
}

fn (mut it Interpreter) stmt(s TStmt) !Flow {
	match s.kind {
		.set {
			// The destination's index is evaluated before the value.
			slot := it.slot(s.place)!
			value := it.eval(s.exprs[0])!
			it.memory[s.place.var][slot] = value
		}
		.branch {
			for i, cond in s.exprs {
				if it.eval(cond)! != 0 {
					return it.block(s.bodies[i])
				}
			}
			return it.block(s.bodies[s.bodies.len - 1])
		}
		.loop {
			for {
				it.step()!
				if it.eval(s.exprs[0])! == 0 {
					break
				}
				flow := it.block(s.bodies[0])!
				if flow == .broke {
					break
				}
				if flow == .returned {
					return flow
				}
				it.block(s.bodies[1])!
			}
		}
		.eval {
			it.eval(s.exprs[0])!
		}
		.ret {
			if s.exprs.len > 0 {
				it.result = it.eval(s.exprs[0])!
			}
			return .returned
		}
		.break_ {
			return .broke
		}
		.continue_ {
			return .continued
		}
		.asm {
			return error('the interpreter cannot run an asm statement')
		}
	}

	return .normal
}

// slot finds the value a place names, checking the index.
fn (mut it Interpreter) slot(place TPlace) !int {
	if place.index.len == 0 {
		return 0
	}
	index := it.eval(place.index[0])!
	v := it.low.vars[place.var]
	if index < 0 || index >= v.len {
		return error('index ${index} is outside ${v.describe()} (0..${v.len - 1})')
	}
	if place.field >= 0 {
		return int(index) * it.low.records[v.record].fields.len + place.field
	}
	return int(index)
}

fn (mut it Interpreter) eval(e TExpr) !i64 {
	match e.kind {
		.constant {
			return e.value
		}
		.load {
			slot := it.slot(e.place)!
			return it.memory[e.place.var][slot]
		}
		.unary {
			return unary_value(e.op, e.typ, it.eval(e.args[0])!)
		}
		.binary {
			a := it.eval(e.args[0])!
			b := it.eval(e.args[1])!
			return binary_value(e.op, e.typ, a, b)
		}
		.compare {
			a := it.eval(e.args[0])!
			b := it.eval(e.args[1])!
			return compare_value(e.op, a, b)
		}
		.logic {
			a := it.eval(e.args[0])!
			if (e.op == .both && a == 0) || (e.op == .either && a != 0) {
				return a
			}
			return it.eval(e.args[1])!
		}
		.convert {
			return convert_value(e.args[0].typ, e.typ, it.eval(e.args[0])!)
		}
		.call {
			mut args := []i64{}
			for a in e.args {
				args << it.eval(a)!
			}
			return it.call(e.func, args)!
		}
	}
}

fn unary_value(op Op, t Type, a i64) i64 {
	return match op {
		.neg {
			t.wrap(-a)
		}
		.not_ {
			t.wrap(~a)
		}
		.invert {
			1 - a
		}
		.abs {
			if a < 0 {
				t.wrap(-a)
			} else {
				a
			}
		}
		else {
			0
		}
	}
}

// binary_value is an arithmetic, bit, shift, min or max operation on two
// values of type t (the count of a shift has its own type).
fn binary_value(op Op, t Type, a i64, b i64) i64 {
	return match op {
		.add {
			t.wrap(a + b)
		}
		.sub {
			t.wrap(a - b)
		}
		.mul {
			if t == .fix {
				fix_mul(a, b)
			} else {
				t.wrap(i64(u64(a) * u64(b)))
			}
		}
		.div {
			if b == 0 {
				i64(0)
			} else if t == .fix {
				fix_div(a, b)
			} else {
				t.wrap(a / b)
			}
		}
		.mod {
			if b == 0 {
				i64(0)
			} else {
				t.wrap(a % b)
			}
		}
		.and_ {
			t.wrap(a & b)
		}
		.or_ {
			t.wrap(a | b)
		}
		.xor {
			t.wrap(a ^ b)
		}
		.shl {
			t.wrap(i64(u64(a) << (b & 31)))
		}
		.shr {
			// Signed values are negative here when they are negative, so >> is
			// arithmetic for them; unsigned ones are never negative.
			t.wrap(a >> (b & 31))
		}
		.min {
			if a < b {
				a
			} else {
				b
			}
		}
		.max {
			if a > b {
				a
			} else {
				b
			}
		}
		else {
			i64(0)
		}
	}
}

// fix_mul is the 16.16 product, rounded down, cut to 32 bits.
fn fix_mul(a i64, b i64) i64 {
	return Type.fix.wrap((a * b) >> 16)
}

// fix_div is the 16.16 quotient, rounded toward zero, cut to 32 bits.
fn fix_div(a i64, b i64) i64 {
	return Type.fix.wrap((a * fix_one) / b)
}

fn compare_value(op Op, a i64, b i64) i64 {
	result := match op {
		.eq { a == b }
		.ne { a != b }
		.lt { a < b }
		.le { a <= b }
		.gt { a > b }
		else { a >= b }
	}

	return if result { 1 } else { 0 }
}

fn convert_value(from Type, to Type, a i64) i64 {
	if to == .bool {
		return if a != 0 { 1 } else { 0 }
	}
	if from == .fix {
		return if to == .fix { a } else { to.wrap(a >> 16) }
	}
	if to == .fix {
		return Type.fix.wrap(a * fix_one)
	}
	return to.wrap(a)
}
