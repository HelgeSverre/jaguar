module jaggame

import jaggame.emulated
import time

// Differential fuzzing: random well-typed programs are run by the
// interpreter and, compiled, on the emulated 68000, and every variable must
// end with the same value on both sides.
//
// A batch is one program: input globals holding edge values of every type,
// a few helper functions with parameters, and several hundred cases. An
// expression case is a function that returns one random expression, stored
// in a global by `main`; a statement case is a function with locals, an
// array and an array of records of its own and a random sequence of
// statements, loops and calls. `main` fills the input arrays, then runs the
// cases in order. The seed is fixed, so a failure reproduces; the failing
// case is printed as the builder calls that make it.

const fuzz_seed = u64(0x6a61_6767_616d_6531)
const fuzz_batches = 40
const fuzz_cases_per_batch = 520

struct Rng {
mut:
	state u64
}

// next is xorshift64*: small, and the same on every machine.
fn (mut r Rng) next() u64 {
	r.state ^= r.state >> 12
	r.state ^= r.state << 25
	r.state ^= r.state >> 27
	return r.state * 0x2545_f491_4f6c_dd1d
}

fn (mut r Rng) below(n int) int {
	return int(r.next() % u64(n))
}

fn (mut r Rng) chance(percent int) bool {
	return r.below(100) < percent
}

fn (mut r Rng) pick_type() Type {
	return all_types[r.below(all_types.len)]
}

fn (mut r Rng) pick_integer() Type {
	return integer_types[r.below(integer_types.len)]
}

const integer_types = [Type.u8, .i8, .u16, .i16, .u32, .i32]

// edge_values are the raw values every type is tried with.
fn edge_values(t Type) []i64 {
	return match t {
		.bool {
			[i64(0), 1]
		}
		.u8 {
			[i64(0), 1, 2, 127, 128, 254, 255]
		}
		.i8 {
			[i64(0), 1, -1, 2, -2, 127, -128, -127]
		}
		.u16 {
			[i64(0), 1, 2, 255, 256, 0x7fff, 0x8000, 0xfffe, 0xffff]
		}
		.i16 {
			[i64(0), 1, -1, 2, -2, 255, -256, 32767, -32768, -32767]
		}
		.u32 {
			[i64(0), 1, 2, 0xffff, 0x10000, 0x7fff_ffff, 0x8000_0000, 0xffff_fffe, 0xffff_ffff]
		}
		.i32 {
			[i64(0), 1, -1, 2, -2, 0xffff, -65536, 0x7fff_ffff, -i64(0x8000_0000), -0x7fff_ffff]
		}
		.fix {
			[i64(0), 65536, -65536, 32768, -32768, 1, -1, 0x7fff_ffff, -i64(0x8000_0000), 0x3_4000,
				-0x64_8000]
		}
		.void {
			[]i64{}
		}
	}
}

fn (mut r Rng) raw_value(t Type) i64 {
	if r.chance(60) {
		edges := edge_values(t)
		return edges[r.below(edges.len)]
	}
	if r.chance(50) {
		return t.wrap(i64(r.below(41)) - 20)
	}
	return t.wrap(i64(r.next()))
}

// literal is a V literal of type t, as a builder method takes it.
fn (mut r Rng) literal(t Type) Val {
	if t == .bool {
		return Val(r.chance(50))
	}
	if t == .fix {
		if r.chance(40) {
			return Val(r.below(201) - 100)
		}
		return Val(fix_value(r.raw_value(.fix)))
	}
	return Val(r.raw_value(t))
}

fn value_name(t Type, raw i64) string {
	if t == .fix {
		return 'fix_${raw:x}'.replace('-', 'm')
	}
	return '${t}_${raw}'.replace('-', 'm')
}

struct Typed {
	e Expr
	t Type
}

struct Helper {
	f   Func
	ret Type
}

struct Fuzzer {
mut:
	p        &Program
	r        Rng
	inputs   [][]Typed // by type
	arrays   []Expr    // a read-write input array of four elements per type
	tables   []Expr    // a table of four elements per type
	rec      Record
	recs     Expr // four input records with a field of every type
	helpers  []Helper
	callable int     // helpers below this index may be called
	scope    []Typed // locals and parameters that may be read and set
	loops    int     // how deeply loops are nested here
	serial   int
	// what each case is, for the report
	expr_cases []Func
	stmt_cases []Func
	order      []Func
	main       Func
	results    []int // the variables expression cases store into
}

fn new_fuzzer(seed u64) Fuzzer {
	mut p := new_program()
	mut fields := []Field{}
	for t in all_types {
		fields << Field{'f_${t}', t}
	}
	rec := p.record('Sample', fields)
	recs := p.array_of('samples', rec, 4)
	mut inputs := [][]Typed{}
	for _ in 0 .. all_types.len + 1 {
		inputs << []Typed{}
	}
	return Fuzzer{
		p:      p
		r:      Rng{seed | 1}
		rec:    rec
		recs:   recs
		inputs: inputs
	}
}

fn (mut f Fuzzer) declare_inputs() {
	for t in all_types {
		for raw in edge_values(t) {
			f.inputs[int(t)] << Typed{f.p.global(value_name(t, raw), t, input_val(t, raw)), t}
		}
		for k in 0 .. 3 {
			raw := t.wrap(i64(f.r.next()))
			f.inputs[int(t)] << Typed{f.p.global('${t}_r${k}', t, input_val(t, raw)), t}
		}
	}
	for t in all_types {
		f.arrays << f.p.array('array_${t}', t, 4)
		mut values := []Val{}
		for _ in 0 .. 4 {
			values << input_val(t, f.r.raw_value(t))
		}
		f.tables << f.p.table('table_${t}', t, values)
	}
}

fn input_val(t Type, raw i64) Val {
	return match t {
		.bool { Val(raw != 0) }
		.fix { Val(fix_value(raw)) }
		else { Val(raw) }
	}
}

fn (f &Fuzzer) array_of_type(t Type) Expr {
	return f.arrays[all_types.index(t)]
}

fn (f &Fuzzer) table_of_type(t Type) Expr {
	return f.tables[all_types.index(t)]
}

// fill_inputs is the start of main: the input arrays and records get
// values, which also tests stores of every type.
fn (mut f Fuzzer) fill_inputs(mut c Code) {
	for t in all_types {
		for i in 0 .. 4 {
			c.set(f.array_of_type(t).at(i), f.literal(t))
			c.set(f.recs.at(i).field('f_${t}'), f.literal(t))
		}
	}
}

fn (mut f Fuzzer) literal(t Type) Val {
	return f.r.literal(t)
}

// narrower is a type whose values widen to t without as_.
fn (mut f Fuzzer) narrower(t Type) Type {
	mut options := []Type{}
	for s in integer_types {
		if assignable(s, t) {
			options << s
		}
	}
	if options.len == 0 {
		return t
	}
	return options[f.r.below(options.len)]
}

// index is an index into an array of `len` elements, len a power of two.
fn (mut f Fuzzer) index(len int, depth int) Val {
	if f.r.chance(40) || depth <= 0 {
		return Val(f.r.below(len))
	}
	return Val(f.gen(f.r.pick_integer(), depth - 1).and(len - 1))
}

fn (mut f Fuzzer) leaf(t Type, depth int) Expr {
	mut locals := f.scope.filter(it.t == t)
	n := f.r.below(100)
	if n < 30 && locals.len > 0 {
		return locals[f.r.below(locals.len)].e
	}
	if n < 55 {
		inputs := f.inputs[int(t)]
		return inputs[f.r.below(inputs.len)].e
	}
	if n < 70 {
		return lit(f.literal(t)).as_(t)
	}
	if n < 80 {
		return f.array_of_type(t).at(f.index(4, depth))
	}
	if n < 90 {
		return f.table_of_type(t).at(f.index(4, depth))
	}
	return f.recs.at(f.index(4, depth)).field('f_${t}')
}

// operand is the right side of an operation of type t: a value of t, of a
// type that widens to it, or a V literal.
fn (mut f Fuzzer) operand(t Type, depth int) Val {
	n := f.r.below(100)
	if n < 25 {
		return f.literal(t)
	}
	if n < 45 {
		return Val(f.gen(f.narrower(t), depth))
	}
	return Val(f.gen(t, depth))
}

// gen is a random expression of exactly type t.
fn (mut f Fuzzer) gen(t Type, depth int) Expr {
	if depth <= 0 || f.r.chance(15) {
		return f.leaf(t, depth)
	}
	if t == .bool {
		return f.gen_bool(depth)
	}
	d := depth - 1
	for {
		match f.r.below(14) {
			0 {
				ops := [Op.add, .sub, .mul, .div, .mod]
				return binary(ops[f.r.below(ops.len)], f.gen(t, d), f.operand(t, d))
			}
			1 {
				// The narrower side on the left, for a change.
				ops := [Op.add, .sub, .mul, .div, .mod, .min, .max]
				return binary(ops[f.r.below(ops.len)], f.gen(f.narrower(t), d), f.gen(t, d))
			}
			2 {
				ops := [Op.div, .mod, .mul, .add, .sub, .min, .max]
				op := ops[f.r.below(ops.len)]
				if f.r.chance(50) {
					// A bare literal on the left takes the type of the right.
					return binary(op, lit(f.literal(t)), f.gen(t, d))
				}
				if t == .fix && f.r.chance(50) {
					// A float literal makes an integer side fix.
					return binary(op, f.gen(f.r.pick_integer(), d), fix_value(f.r.raw_value(.fix)))
				}
				return binary(op, f.gen(t, d), f.operand(t, d))
			}
			3 {
				if t.is_integer() {
					ops := [Op.and_, .or_, .xor]
					return binary(ops[f.r.below(ops.len)], f.gen(t, d), f.operand(t, d))
				}
			}
			4 {
				count := if f.r.chance(50) {
					Val(f.r.below(32))
				} else {
					Val(f.gen(f.r.pick_integer(), d))
				}
				return binary(if f.r.chance(50) { Op.shl } else { Op.shr }, f.gen(t, d), count)
			}
			5 {
				if t.is_signed() {
					return if f.r.chance(50) { f.gen(t, d).neg() } else { f.gen(t, d).abs() }
				}
			}
			6 {
				if t.is_integer() {
					return f.gen(t, d).not()
				}
			}
			7, 8 {
				return f.gen(f.r.pick_type(), d).as_(t)
			}
			9 {
				return binary(if f.r.chance(50) { Op.min } else { Op.max }, f.gen(t, d), f.operand(t,
					d))
			}
			10 {
				if e := f.helper_call(t, d) {
					return e
				}
			}
			11 {
				return f.leaf(t, depth)
			}
			else {
				ops := [Op.add, .sub]
				return binary(ops[f.r.below(ops.len)], f.gen(t, d), f.operand(t, d))
			}
		}
	}
	return f.leaf(t, depth)
}

fn (mut f Fuzzer) gen_bool(depth int) Expr {
	d := depth - 1
	match f.r.below(6) {
		0, 1 {
			s := f.r.pick_type()
			mut ops := [Op.eq, .ne]
			if s != .bool {
				ops << [Op.lt, .le, .gt, .ge]
			}
			return binary(ops[f.r.below(ops.len)], f.gen(s, d), f.operand(s, d))
		}
		2 {
			second := if f.r.chance(25) { f.literal(.bool) } else { Val(f.gen(.bool, d)) }
			return binary(if f.r.chance(50) { Op.both } else { Op.either }, f.gen(.bool, d), second)
		}
		3 {
			return f.gen(.bool, d).invert()
		}
		4 {
			return f.gen(f.r.pick_type(), d).as_(.bool)
		}
		else {
			if e := f.helper_call(.bool, d) {
				return e
			}
			return f.leaf(.bool, depth)
		}
	}
}

fn (mut f Fuzzer) helper_call(t Type, depth int) ?Expr {
	mut options := []Helper{}
	for h in f.helpers[..f.callable] {
		if h.ret == t {
			options << h
		}
	}
	if options.len == 0 {
		return none
	}
	h := options[f.r.below(options.len)]
	mut args := []Val{}
	for param in h.f.params {
		args << f.operand(param.typ, depth)
	}
	return h.f.call(...args)
}

// value is something that can be stored in a t.
fn (mut f Fuzzer) value(t Type, depth int) Val {
	return f.operand(t, depth)
}

fn (mut f Fuzzer) target() ?Typed {
	if f.scope.len == 0 {
		return none
	}
	return f.scope[f.r.below(f.scope.len)]
}

// statements adds `n` random statements; `depth` limits nesting.
fn (mut f Fuzzer) statements(mut c Code, n int, depth int, own Expr, own_type Type, own_records Expr) {
	for _ in 0 .. n {
		f.statement(mut c, depth, own, own_type, own_records)
	}
}

fn (mut f Fuzzer) statement(mut c Code, depth int, own Expr, own_type Type, own_records Expr) {
	ed := 1 + f.r.below(3)
	match f.r.below(16) {
		0, 1, 2 {
			if x := f.target() {
				c.set(x.e, f.value(x.t, ed))
				return
			}
		}
		3 {
			c.set(own.at(f.index(4, ed)), f.value(own_type, ed))
			return
		}
		4 {
			t := f.r.pick_type()
			c.set(own_records.at(f.index(2, ed)).field('f_${t}'), f.value(t, ed))
			return
		}
		5 {
			if x := f.target() {
				if x.t.is_number() {
					match f.r.below(4) {
						0 { c.inc(x.e) }
						1 { c.dec(x.e) }
						2 { c.add_to(x.e, f.operand(x.t, 1)) }
						else { c.sub_from(x.e, f.operand(x.t, 1)) }
					}

					return
				}
			}
		}
		6, 7 {
			if depth > 0 {
				c.if_(f.gen(.bool, ed))
				f.statements(mut c, 1 + f.r.below(3), depth - 1, own, own_type, own_records)
				if f.r.chance(30) {
					c.else_if(f.gen(.bool, ed))
					f.statements(mut c, 1 + f.r.below(2), depth - 1, own, own_type, own_records)
				}
				if f.r.chance(50) {
					c.else_()
					f.statements(mut c, 1 + f.r.below(2), depth - 1, own, own_type, own_records)
				}
				c.end()
				return
			}
		}
		8 {
			if depth > 0 {
				t := if f.r.chance(15) { Type.fix } else { f.r.pick_integer() }
				f.serial++
				v := c.local('i${f.serial}', t)
				to := if t == .fix { f.gen(t, 1).min(5) } else { f.gen(t, 1).and(7) }
				c.for_(v, f.r.below(3), to)
				f.loop_body(mut c, depth, own, own_type, own_records)
				return
			}
		}
		9 {
			if depth > 0 {
				f.serial++
				w := c.local('w${f.serial}', .u8)
				c.set(w, 0)
				c.while_(w.lt(f.gen(.u8, 1).and(7)))
				c.inc(w)
				f.loop_body(mut c, depth, own, own_type, own_records)
				return
			}
		}
		10 {
			if depth > 0 {
				t := f.r.pick_integer()
				mut count := f.gen(t, 1).and(3)
				if t.is_signed() {
					count = count.sub(1) // -1 runs no times
				}
				c.repeat(count)
				f.loop_body(mut c, depth, own, own_type, own_records)
				return
			}
		}
		11 {
			if f.loops > 0 {
				c.if_(f.gen(.bool, 1))
				if f.r.chance(50) {
					c.break_()
				} else {
					c.continue_()
				}
				c.end()
				return
			}
		}
		12 {
			if f.callable > 0 {
				h := f.helpers[f.r.below(f.callable)]
				mut args := []Val{}
				for param in h.f.params {
					args << f.operand(param.typ, ed)
				}
				c.call(h.f, ...args)
				return
			}
		}
		13 {
			if f.r.chance(20) {
				ret := c.prog.funcs[c.func].ret
				c.if_(f.gen(.bool, 1))
				if ret == .void {
					c.ret_void()
				} else {
					c.ret(f.value(ret, 2))
				}
				c.end()
				return
			}
		}
		else {}
	}

	if x := f.target() {
		c.set(x.e, f.value(x.t, ed))
	}
}

// loop_body fills a loop; its counter can be read inside but not set.
fn (mut f Fuzzer) loop_body(mut c Code, depth int, own Expr, own_type Type, own_records Expr) {
	f.loops++
	saved := f.scope.clone()
	f.statements(mut c, 1 + f.r.below(3), depth - 1, own, own_type, own_records)
	f.scope = saved
	f.loops--
	c.end()
}

fn (mut f Fuzzer) helper(k int) {
	mut params := []Param{}
	for j in 0 .. 1 + f.r.below(3) {
		params << Param{'p${j}', f.r.pick_type()}
	}
	ret := f.r.pick_type()
	fun := f.p.func('h${k}', params, ret)
	mut c := f.p.define(fun)
	f.callable = k
	f.scope = []Typed{}
	for p in params {
		f.scope << Typed{fun.arg(p.name), p.typ}
	}
	t := f.r.pick_type()
	f.scope << Typed{c.local('x', t), t}
	own_type := f.r.pick_type()
	own := f.p.array('ho${k}', own_type, 4)
	own_records := f.p.array_of('hq${k}', f.rec, 2)
	f.statements(mut c, 1 + f.r.below(3), 1, own, own_type, own_records)
	c.ret(f.value(ret, 2))
	f.helpers << Helper{fun, ret}
}

fn (mut f Fuzzer) expression_case(k int) Func {
	t := f.r.pick_type()
	fun := f.p.func('e${k}', [], t)
	mut c := f.p.define(fun)
	f.scope = []Typed{}
	c.ret(f.gen(t, 1 + f.r.below(5)))
	f.expr_cases << fun
	return fun
}

fn (mut f Fuzzer) statement_case(k int) Func {
	fun := f.p.func('s${k}', [], .void)
	mut c := f.p.define(fun)
	f.scope = []Typed{}
	for j in 0 .. 4 {
		t := f.r.pick_type()
		f.scope << Typed{c.local('l${j}', t), t}
	}
	own_type := f.r.pick_type()
	own := f.p.array('o${k}', own_type, 4)
	own_records := f.p.array_of('q${k}', f.rec, 2)
	f.statements(mut c, 3 + f.r.below(6), 2, own, own_type, own_records)
	f.stmt_cases << fun
	return fun
}

// batch builds one program with `cases` cases.
fn build_batch(seed u64, cases int) Fuzzer {
	mut f := new_fuzzer(seed)
	f.declare_inputs()
	for k in 0 .. 6 {
		f.helper(k)
	}
	f.callable = f.helpers.len
	main := f.p.func('main', [], .void)
	mut funcs := []Func{}
	for k in 0 .. cases {
		funcs << if f.r.chance(50) { f.expression_case(k) } else { f.statement_case(k) }
	}
	mut c := f.p.define(main)
	f.fill_inputs(mut c)
	for fun in funcs {
		if fun.ret == .void {
			c.call(fun)
		} else {
			result := f.p.global('r_${fun.name}', fun.ret)
			f.results << result.node.var
			c.set(result, fun.call())
		}
	}
	f.order = funcs
	f.main = main
	return f
}

// owner_case is the case a variable belongs to, by its name, or -1.
fn (f &Fuzzer) owner_of(low &Lowered, var int) string {
	v := low.vars[var]
	if v.owner >= 0 {
		return low.funcs[v.owner].name
	}
	if v.name.starts_with('r_') {
		return v.name[2..]
	}
	if v.name.len > 1 && v.name[0] in [`o`, `q`] && v.name[1].is_digit() {
		return 's' + v.name[1..]
	}
	if v.name.starts_with('ho') || v.name.starts_with('hq') {
		return 'h' + v.name[2..]
	}
	return 'main'
}

fn (f &Fuzzer) show_raw(t Type, raw i64) string {
	if t == .fix {
		return '${raw} (${fix_value(raw)})'
	}
	return raw.str()
}

// report describes the first case whose variables disagree.
fn (f &Fuzzer) report(batch int, low &Lowered, mismatches []string, culprit string) string {
	mut lines := [
		'batch ${batch} (seed ${fuzz_seed + u64(batch):x}): interpreter and 68000 disagree in `${culprit}`',
	]
	lines << mismatches
	lines << 'the case:'
	for fun in f.order {
		if fun.name == culprit {
			lines << f.p.listing(fun)
		}
	}
	for h in f.helpers {
		if h.f.name == culprit || culprit.starts_with('s') || culprit.starts_with('e') {
			lines << f.p.listing(h.f)
		}
	}
	lines << 'inputs: globals are named by type and raw value (fix in hex, m for minus); the random ones are:'
	for t in all_types {
		for x in f.inputs[int(t)] {
			v := f.p.vars[x.e.node.var]
			if v.name.contains('_r') {
				lines << '  ${v.name} = ${f.show_raw(t, v.init[0])}'
			}
		}
		table := f.p.vars[f.table_of_type(t).node.var]
		lines << '  ${table.name} = ${table.init}'
	}
	return lines.join('\n')
}

fn run_batch(mut runner emulated.Runner, batch int, mut cov Coverage) !int {
	mut f := build_batch(fuzz_seed + u64(batch), fuzz_cases_per_batch)
	mut it := f.p.interpreter() or {
		return error('batch ${batch}: the generator made a program that does not check:\n${err.msg()}')
	}
	mut interp_error := ''
	it.run('main') or { interp_error = err.msg() }
	for i in 0 .. it.low.funcs.len {
		cov.stmts(&it.low.funcs[i].body)
	}
	cov.expr_cases += f.expr_cases.len
	cov.stmt_cases += f.stmt_cases.len
	cov.zero_divisions += it.zero_divisions
	for var in f.results {
		if it.memory[var][0] != 0 {
			cov.nonzero++
		}
	}
	img := f.p.plain_image(f.main) or { return error('batch ${batch}: ${err.msg()}') }
	mut machine_error := ''
	runner.run(img.bytes, img.done, 20000) or { machine_error = err.msg() }
	ram := runner.ram()
	// Find the first case, in the order main runs them, with a variable that
	// disagrees.
	mut position := map[string]int{}
	for i, fun in f.order {
		position[fun.name] = i
	}
	mut culprit := ''
	mut best := f.order.len + 1
	mut by_owner := map[string][]string{}
	for var, v in it.low.vars {
		for slot in 0 .. it.low.slots(v) {
			want := it.memory[var][slot]
			got := img.slot_value(ram, var, slot)
			if want != got {
				owner := f.owner_of(it.low, var)
				t := if v.kind == .records {
					it.low.records[v.record].fields[slot % it.low.records[v.record].fields.len].typ
				} else {
					v.typ
				}
				by_owner[owner] << '  `${v.label}` slot ${slot}: interpreter ${f.show_raw(t, want)}, 68000 ${f.show_raw(t, got)}'
				rank := position[owner] or { f.order.len }
				if rank < best || culprit == '' {
					best = rank
					culprit = owner
				}
			}
		}
	}
	if culprit != '' || interp_error != '' || machine_error != '' {
		mut text := if culprit != '' {
			f.report(batch, it.low, by_owner[culprit], culprit)
		} else {
			'batch ${batch}'
		}
		if interp_error != '' {
			text += '\ninterpreter: ${interp_error}'
		}
		if machine_error != '' {
			text += '\n68000: ${machine_error}'
		}
		return error(text)
	}
	return f.order.len
}

// Coverage counts what the generated programs contain, so that the claim
// "every operation on every type" is checked rather than hoped for. Keys are
// numbers made by `coverage_key`; strings would make the walk slow.
struct Coverage {
mut:
	seen           map[int]int
	expr_cases     int
	stmt_cases     int
	nonzero        int // expression cases whose result is not 0
	zero_divisions i64 // divisions and remainders by zero the interpreter ran
}

fn coverage_key(group int, a int, b int) int {
	return group * 10000 + a * 100 + b
}

fn (mut cov Coverage) expr(e &TExpr) {
	match e.kind {
		.unary, .binary, .logic {
			cov.seen[coverage_key(1, int(e.op), int(e.typ))]++
		}
		.compare {
			cov.seen[coverage_key(1, int(e.op), int(e.args[0].typ))]++
		}
		.convert {
			cov.seen[coverage_key(2, int(e.args[0].typ), int(e.typ))]++
		}
		.load {
			cov.place(0, &e.place)
		}
		else {}
	}

	for i in 0 .. e.args.len {
		cov.expr(&e.args[i])
	}
	for i in 0 .. e.place.index.len {
		cov.expr(&e.place.index[i])
	}
}

// place counts a load (what 0) or a store (what 1) of a variable, an
// element or a field.
fn (mut cov Coverage) place(what int, p &TPlace) {
	kind := if p.index.len == 0 {
		0
	} else if p.field >= 0 {
		2
	} else {
		1
	}
	cov.seen[coverage_key(3, what * 3 + kind, int(p.typ))]++
}

// stmts holds everything by reference: see "V traps" in the guide.
fn (mut cov Coverage) stmts(body &[]TStmt) {
	for s in body {
		cov.seen[coverage_key(4, int(s.kind), 0)]++
		if s.kind == .set {
			cov.place(1, &s.place)
			for i in 0 .. s.place.index.len {
				cov.expr(&s.place.index[i])
			}
		}
		for i in 0 .. s.exprs.len {
			cov.expr(&s.exprs[i])
		}
		for i in 0 .. s.bodies.len {
			cov.stmts(&s.bodies[i])
		}
	}
}

// expected_coverage names every combination the fuzzer must produce.
fn expected_coverage() map[int]string {
	mut want := map[int]string{}
	for t in all_types {
		mut ops := [Op.eq, .ne]
		if t == .bool {
			ops << [Op.both, .either, .invert]
		}
		if t.is_number() {
			ops << [Op.add, .sub, .mul, .div, .mod, .min, .max, .lt, .le, .gt, .ge, .shl, .shr]
		}
		if t.is_integer() {
			ops << [Op.and_, .or_, .xor, .not_]
		}
		if t.is_signed() {
			ops << [Op.neg, .abs]
		}
		for op in ops {
			want[coverage_key(1, int(op), int(t))] = '${op.name()} ${t}'
		}
		for s in all_types {
			if s != t {
				want[coverage_key(2, int(s), int(t))] = '${s} as ${t}'
			}
		}
		for what, name in ['load variable', 'load element', 'load field', 'store variable',
			'store element', 'store field'] {
			want[coverage_key(3, what, int(t))] = '${name} ${t}'
		}
	}
	for s in [TStmtKind.set, .branch, .loop, .eval, .ret, .break_, .continue_] {
		want[coverage_key(4, int(s), 0)] = 'statement ${s}'
	}
	return want
}

fn test_the_interpreter_and_the_68000_agree_on_random_programs() {
	start := time.now()
	mut runner := emulated.new()
	mut cov := Coverage{}
	mut total := 0
	mut failures := []string{}
	for batch in 0 .. fuzz_batches {
		total += run_batch(mut runner, batch, mut cov) or {
			failures << err.msg()
			0
		}
		if failures.len >= 2 {
			break
		}
	}
	elapsed := time.since(start)
	println('fuzz: ${total} cases agree (${cov.expr_cases} expressions, ${cov.stmt_cases} statement sequences) in ${fuzz_batches} batches, ${elapsed.milliseconds()} ms')
	println('fuzz: ${cov.nonzero} expression results are not 0; ${cov.zero_divisions} divisions by zero were run')
	assert failures.len == 0, failures.join('\n\n')
	mut missing := []string{}
	for key, name in expected_coverage() {
		if key !in cov.seen {
			missing << name
		}
	}
	assert missing.len == 0, 'the fuzzer never produced: ${missing.join(', ')}'
	assert total >= 20000
}
