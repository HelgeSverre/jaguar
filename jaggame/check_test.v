module jaggame

// The type checker: every rule of the language accepts what it should and
// refuses what it should, with a message that names the problem. Problems
// are collected; each names the function and the statement.

// Fixture is a program with one function `f` and a global of every type,
// named after its type.
struct Fixture {
mut:
	p       &Program
	c       &Code
	globals []Expr
}

fn fixture() Fixture {
	mut p := new_program()
	mut globals := []Expr{}
	for t in all_types {
		globals << p.global('g_${t}', t)
	}
	f := p.func('f', [], .void)
	c := p.define(f)
	return Fixture{p, c, globals}
}

// g is the global of a type.
fn (x &Fixture) g(t Type) Expr {
	return x.globals[all_types.index(t)]
}

fn accepted(p &Program) {
	p.check() or { assert false, 'refused:\n${err.msg()}' }
}

fn refused(p &Program, phrases ...string) {
	p.check() or {
		for phrase in phrases {
			assert err.msg().contains(phrase), 'expected `${phrase}` in:\n${err.msg()}'
		}
		return
	}
	assert false, 'accepted, but expected: ${phrases}'
}

fn test_the_narrower_side_widens_when_both_have_the_same_signedness() {
	mut x := fixture()
	x.c.set(x.g(.u16), x.g(.u16).add(x.g(.u8)))
	x.c.set(x.g(.i32), x.g(.i8).mul(x.g(.i16)))
	x.c.set(x.g(.bool), x.g(.u32).lt(x.g(.u8)))
	accepted(x.p)
}

fn test_mixing_signed_and_unsigned_is_refused() {
	mut x := fixture()
	x.c.set(x.g(.u16), x.g(.u16).add(x.g(.i16)))
	refused(x.p,
		'function `f`: set(g_u16, g_u16.add(g_i16)): add mixes u16 and i16: one is signed and the other is not; convert one side with as_')
	mut y := fixture()
	y.c.set(y.g(.bool), y.g(.u8).lt(y.g(.i8)))
	refused(y.p, 'lt mixes u8 and i8')
	mut z := fixture()
	z.c.set(z.g(.u16), z.g(.u16).add(z.g(.i16).as_(.u16)))
	accepted(z.p)
}

fn test_an_integer_literal_takes_the_other_sides_type_and_must_fit() {
	mut x := fixture()
	x.c.set(x.g(.u8), x.g(.u8).add(255))
	x.c.set(x.g(.i8), x.g(.i8).sub(-128))
	x.c.set(x.g(.u32), x.g(.u32).and(i64(0xffff_ffff)))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.u8), y.g(.u8).add(256))
	y.c.set(y.g(.i8), y.g(.i8).add(-129))
	y.c.set(y.g(.u16), y.g(.u16).add(-1))
	refused(y.p, '256 does not fit u8 (0..255)', '-129 does not fit i8 (-128..127)',
		'-1 does not fit u16 (0..65535)')
}

fn test_a_float_literal_is_a_fix() {
	mut x := fixture()
	x.c.set(x.g(.fix), x.g(.u8).add(1.5))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.u8), y.g(.u8).add(1.5))
	refused(y.p, 'a fix cannot be stored in a u8; convert it with as_(.u8), which rounds down')
	mut z := fixture()
	z.c.set(z.g(.bool), z.g(.bool).eq(1.5))
	refused(z.p, 'set(g_bool, g_bool.eq(1.5)): the number 1.5 is a fix, not a bool')
}

fn test_fix_with_an_integer_converts_the_integer() {
	mut x := fixture()
	x.c.set(x.g(.fix), x.g(.fix).add(x.g(.i16)).mul(x.g(.u32)).div(x.g(.fix)))
	x.c.set(x.g(.fix), x.g(.fix).add(3))
	x.c.set(x.g(.fix), x.g(.u8))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.fix), y.g(.fix).add(40000))
	refused(y.p, '40000 does not fit fix (-32768..32767)')
}

fn test_shift_counts() {
	mut x := fixture()
	x.c.set(x.g(.u32), x.g(.u32).shl(31).shr(x.g(.i8)))
	x.c.set(x.g(.fix), x.g(.fix).shr(1))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.u32), y.g(.u32).shl(32))
	y.c.set(y.g(.u32), y.g(.u32).shr(-1))
	y.c.set(y.g(.u32), y.g(.u32).shl(y.g(.fix)))
	y.c.set(y.g(.bool), y.g(.bool).shl(1))
	refused(y.p, 'the shift count 32 must be 0..31', 'the shift count -1 must be 0..31',
		'a shift count must be an integer, not fix', 'shl needs an integer or a fix, not bool')
}

fn test_comparisons_and_logic_yield_bool() {
	mut x := fixture()
	x.c.set(x.g(.bool), x.g(.u8).lt(3).both(x.g(.fix).ge(0.5)).either(x.g(.bool).invert()))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.u8), y.g(.u8).lt(3))
	y.c.set(y.g(.bool), y.g(.u8).both(y.g(.bool)))
	y.c.set(y.g(.bool), y.g(.bool).lt(y.g(.bool)))
	refused(y.p, 'a bool cannot be stored in a u8; convert it with as_(.u8)',
		'both needs bools, not u8; compare `g_u8` first', 'lt needs numbers, not bool')
}

fn test_a_condition_must_be_a_bool() {
	mut x := fixture()
	x.c.if_(x.g(.u8))
	x.c.end()
	x.c.while_(x.g(.fix))
	x.c.end()
	refused(x.p, 'if_(g_u8): a condition must be a bool, not u8; compare it, e.g. `g_u8.ne(0)`',
		'while_(g_fix): a condition must be a bool, not fix')
}

fn test_operations_need_the_right_kind_of_type() {
	mut x := fixture()
	x.c.set(x.g(.bool), x.g(.bool).add(x.g(.bool)))
	x.c.set(x.g(.fix), x.g(.fix).and(1))
	x.c.set(x.g(.bool), x.g(.bool).xor(true))
	x.c.set(x.g(.u8), x.g(.u8).neg())
	x.c.set(x.g(.u16), x.g(.u16).abs())
	x.c.set(x.g(.fix), x.g(.fix).not())
	x.c.set(x.g(.bool), x.g(.bool).not())
	x.c.set(x.g(.u8), x.g(.u8).invert())
	refused(x.p, 'add needs numbers, not bool', 'and works on the bits of integers, not fix',
		'xor works on the bits of integers, not bool; for bools use both or either',
		'neg needs a signed type or fix, not u8', 'abs needs a signed type or fix, not u16',
		'not needs an integer, not fix', 'not needs an integer, not bool; for a bool use invert()',
		'invert needs a bool, not u8; for the bits of an integer use not()')
}

fn test_set_widens_but_does_not_narrow() {
	mut x := fixture()
	x.c.set(x.g(.u32), x.g(.u8))
	x.c.set(x.g(.i16), x.g(.i8))
	x.c.set(x.g(.fix), x.g(.i32))
	x.c.set(x.g(.u8), x.g(.u16).as_(.u8))
	x.c.set(x.g(.i16), x.g(.fix).as_(.i16))
	x.c.set(x.g(.bool), x.g(.u8).as_(.bool))
	x.c.inc(x.g(.fix))
	x.c.add_to(x.g(.u16), x.g(.u8))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.u8), y.g(.u16))
	y.c.set(y.g(.u16), y.g(.i8))
	y.c.set(y.g(.i16), y.g(.fix))
	y.c.set(y.g(.bool), y.g(.u8))
	y.c.set(y.g(.u8), y.g(.bool))
	y.c.add_to(y.g(.u8), y.g(.u16))
	y.c.inc(y.g(.bool))
	refused(y.p, 'set(g_u8, g_u16): `g_u16`: a u16 does not fit a u8; narrow it with as_(.u8)',
		'an i8 cannot be stored in a u16: one is signed and the other is not; convert it with as_(.u16)',
		'a fix cannot be stored in an i16',
		'a u8 cannot be stored in a bool; compare it instead, e.g. .ne(0)',
		'a bool cannot be stored in a u8; convert it with as_(.u8)',
		'set(g_u8, g_u8.add(g_u16)): `g_u8.add(g_u16)`: a u16 does not fit a u8',
		'set(g_bool, g_bool.add(1)): add needs numbers, not bool')
}

fn test_tables_arrays_and_indexes() {
	mut x := fixture()
	bag := x.p.array_u8('bag', 8)
	sines := x.p.table_i16('sines', [0, 1, 2, 3])
	x.c.set(bag.at(7), sines.at(x.g(.u8).and(3)).as_(.u8))
	x.c.set(bag.at(x.g(.i32)), 1)
	accepted(x.p)
	mut y := fixture()
	bag2 := y.p.array_u8('bag', 8)
	sines2 := y.p.table_i16('sines', [0, 1, 2, 3])
	y.c.set(sines2.at(0), 1)
	y.c.set(bag2.at(8), 1)
	y.c.set(bag2.at(-1), 1)
	y.c.set(bag2.at(y.g(.fix)), 1)
	y.c.set(bag2, 1)
	y.c.set(y.g(.u8), y.g(.u8).at(0))
	y.c.set(y.g(.u8), bag2.add(1))
	refused(y.p, 'table `sines` is read-only', 'index 8 is outside array `bag` (0..7)',
		'index -1 is outside array `bag` (0..7)', 'an index must be an integer, not fix',
		'array `bag` is not a single value; index it with at(…)',
		'at(…) needs an array or a table, not `g_u8`')
}

fn test_records_and_fields() {
	mut x := fixture()
	guard := x.p.record('Guard', [Field{'x', .fix}, Field{'y', .fix}])
	guards := x.p.array_of('guards', guard, 4)
	bag := x.p.array_u8('bag', 4)
	x.c.set(guards.at(1).field('x'), guards.at(x.g(.u8).and(3)).field('y').add(1))
	accepted(x.p)
	mut y := fixture()
	guard2 := y.p.record('Guard', [Field{'x', .fix}, Field{'y', .fix}])
	guards2 := y.p.array_of('guards', guard2, 4)
	bag2 := y.p.array_u8('bag', 4)
	y.c.set(guards2.at(0).field('z'), 1)
	y.c.set(y.g(.fix), guards2.at(0))
	y.c.set(y.g(.u8), bag2.at(0).field('x'))
	y.c.set(y.g(.fix), guards2.field('x'))
	refused(y.p, 'record `Guard` has no field `z`; its fields are x, y',
		'`guards.at(0)` is a whole record; take one of its fields with field(…)',
		'field(…) needs an element of an array of records, not `bag.at(0)`',
		'field(…) needs an element of an array of records, not `guards`')
	_ = bag
}

fn test_record_layout() {
	mut p := new_program()
	r := p.record('Mixed', [Field{'a', .u8}, Field{'b', .u32},
		Field{'c', .i16}, Field{'d', .bool}])
	info := p.records[r.id]
	assert info.offsets == [0, 4, 8, 10]
	assert info.size == 16
	assert info.shift == 4
	p.record('Small', [Field{'a', .u8}])
	assert p.records[1].size == 2
}

fn test_calls_are_checked() {
	mut x := fixture()
	two := x.p.func('two', [Param{'a', .u16}, Param{'b', .fix}], .u16)
	mut c2 := x.p.define(two)
	c2.ret(two.arg('a'))
	nothing := x.p.func('nothing', [], .void)
	x.p.define(nothing)
	x.c.set(x.g(.u32), two.call(x.g(.u8), 3))
	x.c.call(nothing)
	x.c.call(two, 1, 2)
	accepted(x.p)
	mut y := fixture()
	two2 := y.p.func('two', [Param{'a', .u16}, Param{'b', .fix}], .u16)
	mut d := y.p.define(two2)
	d.ret(two2.arg('a'))
	nothing2 := y.p.func('nothing', [], .void)
	y.p.define(nothing2)
	y.c.set(y.g(.u16), two2.call(1))
	y.c.set(y.g(.u16), two2.call(y.g(.i16), 0))
	y.c.set(y.g(.u16), nothing2.call())
	y.c.set(y.g(.u16), two2.arg('c'))
	refused(y.p, '`two` takes 2 arguments, not 1', 'an i16 cannot be stored in a u16',
		'`nothing` returns nothing, so it cannot be used as a value', '`two` has no parameter `c`')
}

fn test_recursion_is_refused() {
	mut p := new_program()
	a := p.func('a', [], .void)
	b := p.func('b', [], .void)
	self := p.func('self', [], .void)
	mut c := p.define(a)
	c.call(b)
	c = p.define(b)
	c.call(a)
	c = p.define(self)
	c.call(self)
	refused(p,
		'recursion is not allowed (parameters and locals have fixed addresses): `a` calls `b` calls `a`',
		'`self` calls `self`')
}

fn test_a_function_may_be_declared_before_it_is_defined() {
	mut p := new_program()
	later := p.func('later', [], .u8)
	never := p.func('never', [], .void)
	_ = never
	first := p.func('first', [], .void)
	mut c := p.define(first)
	g := p.u8('g')
	c.set(g, later.call())
	c = p.define(later)
	c.ret(7)
	accepted(p)
	mut q := new_program()
	missing := q.func('missing', [], .void)
	user := q.func('user', [], .void)
	mut d := q.define(user)
	d.call(missing)
	refused(q, 'function `missing` is called but never defined')
}

fn test_blocks_must_balance() {
	mut x := fixture()
	x.c.if_(true)
	x.c.while_(true)
	refused(x.p, 'function `f`: if_, while_ not closed with end()')
	mut y := fixture()
	y.c.end()
	y.c.else_()
	y.c.else_if(true)
	y.c.if_(true)
	y.c.else_()
	y.c.else_()
	y.c.else_if(true)
	y.c.end()
	refused(y.p, 'function `f`: end() without an open block', 'else_ without an if_',
		'else_if without an if_', 'a second else_ for the same if_', 'else_if after else_')
}

fn test_break_and_continue_need_a_loop() {
	mut x := fixture()
	x.c.repeat(3)
	x.c.if_(true)
	x.c.break_()
	x.c.end()
	x.c.continue_()
	x.c.end()
	accepted(x.p)
	mut y := fixture()
	y.c.break_()
	y.c.if_(true)
	y.c.continue_()
	y.c.end()
	refused(y.p, 'break_ outside a loop', 'continue_ outside a loop')
}

fn test_returns_are_checked() {
	mut p := new_program()
	sign := p.func('sign', [Param{'v', .i16}], .i8)
	mut c := p.define(sign)
	c.if_(sign.arg('v').lt(0))
	c.ret(-1)
	c.else_()
	c.ret(1)
	c.end()
	accepted(p)
	mut q := new_program()
	maybe := q.func('maybe', [Param{'v', .i16}], .i8)
	mut d := q.define(maybe)
	d.if_(maybe.arg('v').lt(0))
	d.ret(-1)
	d.end()
	plain := q.func('plain', [], .void)
	d = q.define(plain)
	d.ret(1)
	valued := q.func('valued', [], .u8)
	d = q.define(valued)
	d.ret_void()
	refused(q, 'function `maybe` returns i8 but can reach its end without ret',
		'`plain` returns nothing; use ret_void()', '`valued` returns u8, so ret needs a value')
}

fn test_names_are_checked() {
	mut p := new_program()
	p.u8('score')
	p.u16('score')
	p.u8('2fast')
	p.u8('dotted.name')
	f := p.func('f', [Param{'a', .u8}, Param{'a', .u8}], .void)
	mut c := p.define(f)
	c.local_u8('x')
	c.local_u8('x')
	p.define(f)
	refused(p, 'global `score`: the name is already used',
		'global `2fast`: a name is letters, digits and _, not starting with a digit',
		'global `dotted.name`', 'function `f`: parameter `a` appears twice',
		'local `x`: the name is already used in this function', 'function `f` is defined twice')
}

fn test_a_local_belongs_to_its_function() {
	mut p := new_program()
	g := p.func('g', [Param{'a', .u8}], .void)
	mut c := p.define(g)
	x := c.local_u8('x')
	f := p.func('f', [], .void)
	mut d := p.define(f)
	d.set(x, 1)
	d.set(p.u8('h'), g.arg('a'))
	refused(p, '`x` is a local of `g`, not of this function',
		'`a` is a parameter of `g`, not of this function')
}

fn test_initial_values_must_fit() {
	mut p := new_program()
	p.u8('a', 300)
	p.fix('b', 40000.0)
	p.i16('c', -32769)
	p.table_u8('t', [1, 256])
	p.global('d', .bool, Val(3))
	refused(p, 'global `a`: 300 does not fit u8 (0..255)', 'global `b`: 40000.0 does not fit fix',
		'global `c`: -32769 does not fit i16', 'table `t`: 256 does not fit u8',
		'global `d`: the integer 3 cannot be a bool')
}

fn test_literals_need_a_type_from_somewhere() {
	mut x := fixture()
	x.c.set(x.g(.u8), lit(1).add(2))
	x.c.set(x.g(.bool), lit(5).as_(.u8).lt(6))
	accepted(x.p)
	mut y := fixture()
	y.c.set(y.g(.bool), lit(1).lt(2))
	y.c.set(y.g(.u8), lit(300).as_(.u8))
	refused(y.p, 'both sides of lt are literals; give one a type, e.g. lit(1).as_(.u16)',
		'300 does not fit u8')
}

fn test_loops_are_checked() {
	mut x := fixture()
	x.c.for_(x.g(.i16), -3, x.g(.i8))
	x.c.end()
	x.c.repeat(x.g(.u8))
	x.c.end()
	accepted(x.p)
	mut y := fixture()
	bag := y.p.array_u8('bag', 4)
	y.c.for_(bag.at(0), 0, 4)
	y.c.end()
	y.c.for_(y.g(.bool), 0, 4)
	y.c.end()
	y.c.for_(y.g(.u8), 0, 256)
	y.c.end()
	y.c.repeat(y.g(.fix))
	y.c.end()
	y.c.repeat(-1)
	y.c.end()
	refused(y.p, 'the loop variable must be a variable, not `bag.at(0)`',
		'the loop variable must be a number, not bool', 'for_(g_u8, 0, 256): 256 does not fit u8',
		'repeat needs an integer count, not fix', 'repeat(-1): repeat needs a count of 0 or more')
}

fn test_every_problem_is_reported_at_once() {
	mut x := fixture()
	x.c.set(x.g(.u8), x.g(.u16))
	x.c.set(x.g(.u8), x.g(.i8))
	x.c.break_()
	x.p.u8('g_u8')
	x.p.check() or {
		assert err.msg().starts_with('jaggame program:')
		assert err.msg().count('\n') == 4
		return
	}
	assert false
}
