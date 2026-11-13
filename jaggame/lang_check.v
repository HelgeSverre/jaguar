module jaggame

// The type checker. It walks every function body, applies the rules of
// docs/jaggame/design.md and produces the typed IR of lang_ir.v. Problems
// are collected, each naming the function and the statement, and reported
// together.

struct Checker {
	p &Program
mut:
	vars     []Var
	problems []string
	func     int
	where    string
	calls    map[int][]int
	called   map[int]bool
	hidden   int
}

// check applies every rule of the language to the program and reports
// all the problems it finds together.
pub fn (p &Program) check() ! {
	p.lower()!
}

fn (p &Program) lower() !&Lowered {
	mut k := Checker{
		p:    p
		vars: p.vars.clone()
	}
	mut funcs := []LFunc{}
	for id in 0 .. p.funcs.len {
		funcs << k.function(id)
	}
	k.recursion()
	for id in 0 .. p.funcs.len {
		if id in k.called && id !in p.bodies {
			k.problems << 'function `${p.funcs[id].name}` is called but never defined'
		}
	}
	mut all := p.problems.clone()
	all << k.problems
	if all.len > 0 {
		return error('jaggame program:\n  ' + all.join('\n  '))
	}
	return &Lowered{
		vars:    k.vars
		records: p.records.clone()
		funcs:   funcs
		asms:    p.asms.clone()
	}
}

fn (mut k Checker) fail(message string) {
	k.problems << 'function `${k.p.funcs[k.func].name}`: ${k.where}: ${message}'
}

fn (mut k Checker) function(id int) LFunc {
	f := k.p.funcs[id]
	k.func = id
	code := k.p.bodies[id] or {
		return LFunc{
			id:     id
			name:   f.name
			ret:    f.ret
			params: f.param_vars
		}
	}
	open := code.open_blocks()
	if open.len > 0 {
		k.problems << 'function `${f.name}`: ${open.join(', ')} not closed with end()'
	}
	body := k.block(code.statements())
	if f.ret != .void && !always_returns(body) {
		k.problems << 'function `${f.name}` returns ${f.ret} but can reach its end without ret'
	}
	mut locals := []int{}
	for i, v in k.vars {
		if v.owner == id && v.role in [.local, .hidden] {
			locals << i
		}
	}
	return LFunc{
		id:      id
		name:    f.name
		ret:     f.ret
		params:  f.param_vars
		locals:  locals
		body:    body
		defined: true
	}
}

fn always_returns(body []TStmt) bool {
	for s in body {
		if s.kind == .ret {
			return true
		}
		if s.kind == .branch && s.bodies.all(always_returns(it)) {
			return true
		}
	}
	return false
}

fn (mut k Checker) recursion() {
	mut state := map[int]int{}
	mut path := []int{}
	for id in 0 .. k.p.funcs.len {
		k.visit(id, mut state, mut path)
	}
}

// visit walks the call graph depth first; finding a function that is
// still being visited means a cycle.
fn (mut k Checker) visit(id int, mut state map[int]int, mut path []int) {
	s := state[id] or { 0 }
	if s == 2 {
		return
	}
	if s == 1 {
		start := path.index(id)
		mut names := path[start..].map('`${k.p.funcs[it].name}`')
		names << '`${k.p.funcs[id].name}`'
		k.problems << 'recursion is not allowed (parameters and locals have fixed addresses): ${names.join(' calls ')}'
		return
	}
	state[id] = 1
	path << id
	for callee in k.calls[id] or { []int{} } {
		k.visit(callee, mut state, mut path)
	}
	path.pop()
	state[id] = 2
}

fn (mut k Checker) block(stmts []Stmt) []TStmt {
	mut out := []TStmt{}
	for s in stmts {
		k.stmt(s, mut out)
	}
	return out
}

fn (mut k Checker) stmt(s Stmt, mut out []TStmt) {
	k.where = k.p.show_stmt(s)
	match s.kind {
		.set {
			place := k.place(s.exprs[0], true) or { return }
			value := k.assign(s.exprs[1], place.typ) or { return }
			out << TStmt{
				kind:  .set
				place: place
				exprs: [value]
			}
		}
		.if_ {
			k.branch(s, mut out)
		}
		.loop {
			match s.loop {
				.while_ { k.while_loop(s, mut out) }
				.for_ { k.for_loop(s, mut out) }
				.repeat { k.repeat_loop(s, mut out) }
			}
		}
		.call {
			e := k.call(s.exprs[0].node, true) or { return }
			out << TStmt{
				kind:  .eval
				exprs: [e]
			}
		}
		.ret {
			k.ret(s, mut out)
		}
		.break_ {
			out << TStmt{
				kind: .break_
			}
		}
		.continue_ {
			out << TStmt{
				kind: .continue_
			}
		}
		.asm {
			out << TStmt{
				kind: .asm
				asm:  s.asm
			}
		}
	}
}

fn (mut k Checker) branch(s Stmt, mut out []TStmt) {
	mut conds := []TExpr{}
	mut bodies := [][]TStmt{}
	for i, cond in s.exprs {
		k.where = if i == 0 { 'if_(${k.p.show(cond)})' } else { 'else_if(${k.p.show(cond)})' }
		if c := k.condition(cond) {
			conds << c
		}
		bodies << k.block(s.bodies[i])
	}
	bodies << if s.has_else { k.block(s.bodies[s.bodies.len - 1]) } else { []TStmt{} }
	if conds.len == s.exprs.len {
		out << TStmt{
			kind:   .branch
			exprs:  conds
			bodies: bodies
		}
	}
}

fn (mut k Checker) while_loop(s Stmt, mut out []TStmt) {
	cond := k.condition(s.exprs[0])
	body := k.block(s.bodies[0])
	if c := cond {
		out << TStmt{
			kind:   .loop
			exprs:  [c]
			bodies: [body, []TStmt{}]
		}
	}
}

// for_loop is `v = from; while v < to { body; v += 1 }`, with `continue_`
// going on with the increment.
fn (mut k Checker) for_loop(s Stmt, mut out []TStmt) {
	v := s.exprs[0]
	if v.node.kind != .variable {
		k.fail('the loop variable must be a variable, not `${k.p.show(v)}`')
		return
	}
	place := k.place(v, true) or { return }
	if !place.typ.is_number() {
		k.fail('the loop variable must be a number, not ${place.typ}')
		return
	}
	from := k.assign(s.exprs[1], place.typ)
	cond := k.condition(v.lt(s.exprs[2]))
	step := k.assign(v.add(1), place.typ)
	body := k.block(s.bodies[0])
	f := from or { return }
	c := cond or { return }
	st := step or { return }
	out << TStmt{
		kind:  .set
		place: place
		exprs: [f]
	}
	out << TStmt{
		kind:   .loop
		exprs:  [c]
		bodies: [body, [
			TStmt{
				kind:  .set
				place: place
				exprs: [st]
			},
		]]
	}
}

// repeat_loop is `n = count; while n > 0 { n -= 1; body }` with a hidden
// counter of the count's type.
fn (mut k Checker) repeat_loop(s Stmt, mut out []TStmt) {
	cn := s.exprs[0]
	mut count := TExpr{}
	if is_literal(cn) {
		count = k.literal(cn.node, .u32) or {
			k.fail('repeat needs a count of 0 or more')
			return
		}
	} else {
		count = k.expr(cn, .void) or { return }
		if !count.typ.is_integer() {
			k.fail('repeat needs an integer count, not ${count.typ}')
			return
		}
	}
	t := count.typ
	k.hidden++
	k.vars << Var{
		name:  'repeat.${k.hidden}'
		label: '${k.p.funcs[k.func].name}.repeat.${k.hidden}'
		kind:  .scalar
		role:  .hidden
		typ:   t
		owner: k.func
	}
	counter := TPlace{
		var: k.vars.len - 1
		typ: t
	}
	load := TExpr{
		kind:  .load
		typ:   t
		place: counter
	}
	zero := TExpr{
		kind: .constant
		typ:  t
	}
	one := TExpr{
		kind:  .constant
		typ:   t
		value: 1
	}
	mut body := [
		TStmt{
			kind:  .set
			place: counter
			exprs: [
				TExpr{
					kind: .binary
					op:   .sub
					typ:  t
					args: [load, one]
				},
			]
		},
	]
	body << k.block(s.bodies[0])
	out << TStmt{
		kind:  .set
		place: counter
		exprs: [count]
	}
	out << TStmt{
		kind:   .loop
		exprs:  [
			TExpr{
				kind: .compare
				op:   .gt
				typ:  .bool
				args: [load, zero]
			},
		]
		bodies: [body, []TStmt{}]
	}
}

fn (mut k Checker) ret(s Stmt, mut out []TStmt) {
	f := k.p.funcs[k.func]
	if s.exprs.len == 0 {
		if f.ret != .void {
			k.fail('`${f.name}` returns ${f.ret}, so ret needs a value')
			return
		}
		out << TStmt{
			kind: .ret
		}
		return
	}
	if f.ret == .void {
		k.fail('`${f.name}` returns nothing; use ret_void()')
		return
	}
	value := k.assign(s.exprs[0], f.ret) or { return }
	out << TStmt{
		kind:  .ret
		exprs: [value]
	}
}

fn is_literal(e Expr) bool {
	return e.node.kind in [.int_literal, .float_literal, .bool_literal]
}

fn literal_val(n &Node) Val {
	return match n.kind {
		.float_literal { Val(n.float_value) }
		.bool_literal { Val(n.int_value != 0) }
		else { Val(n.int_value) }
	}
}

fn (mut k Checker) literal(n &Node, t Type) ?TExpr {
	value := constant(t, literal_val(n)) or {
		k.fail(err.msg())
		return none
	}
	return TExpr{
		kind:  .constant
		typ:   t
		value: value
	}
}

// assignable is true when a value of type `from` can be stored in `to`
// without `as_`.
fn assignable(from Type, to Type) bool {
	if from == to {
		return true
	}
	if from.is_integer() && to.is_integer() {
		return from.is_signed() == to.is_signed() && from.size() <= to.size()
	}
	return from.is_integer() && to == .fix
}

// a_type is a type with its article: "a u8", "an i16".
fn a_type(t Type) string {
	return if t.str().starts_with('i') { 'an ${t}' } else { 'a ${t}' }
}

fn store_problem(from Type, to Type) string {
	if to == .bool {
		return '${a_type(from)} cannot be stored in a bool; compare it instead, e.g. .ne(0)'
	}
	if from == .bool {
		return 'a bool cannot be stored in ${a_type(to)}; convert it with as_(.${to})'
	}
	if from == .fix {
		return 'a fix cannot be stored in ${a_type(to)}; convert it with as_(.${to}), which rounds down'
	}
	if from.is_signed() != to.is_signed() {
		return '${a_type(from)} cannot be stored in ${a_type(to)}: one is signed and the other is not; convert it with as_(.${to})'
	}
	return '${a_type(from)} does not fit ${a_type(to)}; narrow it with as_(.${to})'
}

// assign checks a value that is stored in, or passed as, a `to`.
fn (mut k Checker) assign(e Expr, to Type) ?TExpr {
	if is_literal(e) {
		return k.literal(e.node, to)
	}
	v := k.expr(e, to)?
	if v.typ == to {
		return v
	}
	if assignable(v.typ, to) {
		return widen(v, to)
	}
	k.fail('`${k.p.show(e)}`: ${store_problem(v.typ, to)}')
	return none
}

fn (mut k Checker) condition(e Expr) ?TExpr {
	if is_literal(e) {
		return k.literal(e.node, .bool)
	}
	v := k.expr(e, .bool)?
	if v.typ != .bool {
		k.fail('a condition must be a bool, not ${v.typ}; compare it, e.g. `${k.p.show(e)}.ne(0)`')
		return none
	}
	return v
}

fn widen(e TExpr, t Type) TExpr {
	if e.typ == t {
		return e
	}
	return TExpr{
		kind: .convert
		typ:  t
		args: [e]
	}
}

// expr checks an expression. `want` is the type a literal takes when
// nothing else decides it, or void.
fn (mut k Checker) expr(e Expr, want Type) ?TExpr {
	n := e.node
	match n.kind {
		.int_literal, .float_literal, .bool_literal {
			if want == .void {
				k.fail('cannot tell the type of the literal `${k.p.show(e)}`; give it one, e.g. lit(${k.p.show(e)}).as_(.u16)')
				return none
			}
			return k.literal(n, want)
		}
		.variable, .element, .field {
			place := k.place(e, false)?
			return TExpr{
				kind:  .load
				typ:   place.typ
				place: place
			}
		}
		.unary {
			return k.unary(n, want)
		}
		.binary {
			return k.binary(n, want)
		}
		.convert {
			return k.convert(n)
		}
		.call {
			return k.call(n, false)
		}
		.invalid {
			k.fail(n.name)
			return none
		}
	}
}

fn (mut k Checker) visible(v Var) bool {
	if v.role in [.param, .local] && v.owner != k.func {
		what := if v.role == .param { 'a parameter' } else { 'a local' }
		k.fail('`${v.name}` is ${what} of `${k.p.funcs[v.owner].name}`, not of this function')
		return false
	}
	return true
}

// place checks a variable, an element or a field, as something to read or
// (with `write`) to store into.
fn (mut k Checker) place(e Expr, write bool) ?TPlace {
	n := e.node
	match n.kind {
		.variable {
			v := k.vars[n.var]
			if !k.visible(v) {
				return none
			}
			if v.kind != .scalar {
				k.fail('${v.describe()} is not a single value; index it with at(…)')
				return none
			}
			return TPlace{
				var: n.var
				typ: v.typ
			}
		}
		.element {
			base := n.args[0].node
			if base.kind != .variable || k.vars[base.var].kind == .scalar {
				k.fail('at(…) needs an array or a table, not `${k.p.show(n.args[0])}`')
				return none
			}
			v := k.vars[base.var]
			if v.kind == .records {
				k.fail('`${k.p.show(e)}` is a whole record; take one of its fields with field(…)')
				return none
			}
			if write && v.kind == .table {
				k.fail('table `${v.name}` is read-only')
				return none
			}
			index := k.index(n.args[1], v)?
			return TPlace{
				var:   base.var
				typ:   v.typ
				shift: v.typ.shift()
				index: [index]
			}
		}
		.field {
			el := n.args[0].node
			if el.kind != .element || el.args[0].node.kind != .variable
				|| k.vars[el.args[0].node.var].kind != .records {
				k.fail('field(…) needs an element of an array of records, not `${k.p.show(n.args[0])}`')
				return none
			}
			var := el.args[0].node.var
			v := k.vars[var]
			r := k.p.records[v.record]
			fi := r.field_index(n.name)
			if fi < 0 {
				names := r.fields.map(it.name).join(', ')
				k.fail('record `${r.name}` has no field `${n.name}`; its fields are ${names}')
				return none
			}
			index := k.index(el.args[1], v)?
			return TPlace{
				var:    var
				typ:    r.fields[fi].typ
				field:  fi
				offset: r.offsets[fi]
				shift:  r.shift
				index:  [index]
			}
		}
		else {
			k.fail('`${k.p.show(e)}` is not a variable, an element or a field, so nothing can be stored in it')
			return none
		}
	}
}

fn (mut k Checker) index(e Expr, v Var) ?TExpr {
	n := e.node
	if n.kind == .int_literal {
		if n.int_value < 0 || n.int_value >= v.len {
			k.fail('index ${n.int_value} is outside ${v.describe()} (0..${v.len - 1})')
			return none
		}
		return TExpr{
			kind:  .constant
			typ:   .u32
			value: n.int_value
		}
	}
	t := k.expr(e, .void)?
	if !t.typ.is_integer() {
		k.fail('an index must be an integer, not ${t.typ}')
		return none
	}
	return t
}

fn (mut k Checker) unary(n &Node, want Type) ?TExpr {
	a := k.expr(n.args[0], want)?
	t := a.typ
	match n.op {
		.neg, .abs {
			if !t.is_signed() {
				k.fail('${n.op.name()} needs a signed type or fix, not ${t}')
				return none
			}
		}
		.not_ {
			if !t.is_integer() {
				hint := if t == .bool { '; for a bool use invert()' } else { '' }
				k.fail('not needs an integer, not ${t}${hint}')
				return none
			}
		}
		else {
			if t != .bool {
				k.fail('invert needs a bool, not ${t}; for the bits of an integer use not()')
				return none
			}
		}
	}

	return TExpr{
		kind: .unary
		op:   n.op
		typ:  t
		args: [a]
	}
}

// common is the type both sides of a binary operation are converted to.
fn (mut k Checker) common(op Op, x Type, y Type) ?Type {
	if x == y {
		return x
	}
	if x.is_integer() && y.is_integer() {
		if x.is_signed() != y.is_signed() {
			k.fail('${op.name()} mixes ${x} and ${y}: one is signed and the other is not; convert one side with as_')
			return none
		}
		return if x.size() >= y.size() { x } else { y }
	}
	if (x == .fix && y.is_integer()) || (y == .fix && x.is_integer()) {
		return Type.fix
	}
	k.fail('${op.name()} cannot combine ${x} and ${y}')
	return none
}

// partner is the type of an operation between a typed side and a literal:
// a float literal makes it fix.
fn partner(t Type, literal Expr) Type {
	if literal.node.kind == .float_literal && t.is_integer() {
		return .fix
	}
	return t
}

fn (mut k Checker) allowed(op Op, t Type) bool {
	match op {
		.eq, .ne {
			return true
		}
		.and_, .or_, .xor {
			if !t.is_integer() {
				hint := if t == .bool { '; for bools use both or either' } else { '' }
				k.fail('${op.name()} works on the bits of integers, not ${t}${hint}')
				return false
			}
		}
		else {
			if !t.is_number() {
				k.fail('${op.name()} needs numbers, not ${t}')
				return false
			}
		}
	}

	return true
}

fn (mut k Checker) binary(n &Node, want Type) ?TExpr {
	op := n.op
	an := n.args[0]
	bn := n.args[1]
	if op in [.both, .either] {
		a := k.logic_operand(op, an)?
		b := k.logic_operand(op, bn)?
		return TExpr{
			kind: .logic
			op:   op
			typ:  .bool
			args: [a, b]
		}
	}
	if op in [.shl, .shr] {
		return k.shift(n, want)
	}
	a_lit := is_literal(an)
	b_lit := is_literal(bn)
	mut ta := TExpr{}
	mut tb := TExpr{}
	if !a_lit {
		ta = k.expr(an, .void)?
	}
	if !b_lit {
		tb = k.expr(bn, .void)?
	}
	mut t := Type.void
	if !a_lit && !b_lit {
		t = k.common(op, ta.typ, tb.typ)?
	} else if !a_lit {
		t = partner(ta.typ, bn)
	} else if !b_lit {
		t = partner(tb.typ, an)
	} else if want != .void && !op.is_compare() {
		t = want
	} else {
		k.fail('both sides of ${op.name()} are literals; give one a type, e.g. lit(${k.p.show(an)}).as_(.u16)')
		return none
	}
	if !k.allowed(op, t) {
		return none
	}
	mut a := widen(ta, t)
	if a_lit {
		a = k.literal(an.node, t)?
	}
	mut b := widen(tb, t)
	if b_lit {
		b = k.literal(bn.node, t)?
	}
	if op.is_compare() {
		return TExpr{
			kind: .compare
			op:   op
			typ:  .bool
			args: [a, b]
		}
	}
	return TExpr{
		kind: .binary
		op:   op
		typ:  t
		args: [a, b]
	}
}

fn (mut k Checker) logic_operand(op Op, e Expr) ?TExpr {
	if is_literal(e) {
		return k.literal(e.node, .bool)
	}
	v := k.expr(e, .bool)?
	if v.typ != .bool {
		k.fail('${op.name()} needs bools, not ${v.typ}; compare `${k.p.show(e)}` first')
		return none
	}
	return v
}

fn (mut k Checker) shift(n &Node, want Type) ?TExpr {
	a := k.expr(n.args[0], want)?
	if !a.typ.is_number() {
		k.fail('${n.op.name()} needs an integer or a fix, not ${a.typ}')
		return none
	}
	cn := n.args[1]
	mut count := TExpr{}
	if is_literal(cn) {
		if cn.node.kind != .int_literal || cn.node.int_value < 0 || cn.node.int_value > 31 {
			k.fail('the shift count ${k.p.show(cn)} must be 0..31')
			return none
		}
		count = TExpr{
			kind:  .constant
			typ:   .u8
			value: cn.node.int_value
		}
	} else {
		count = k.expr(cn, .void)?
		if !count.typ.is_integer() {
			k.fail('a shift count must be an integer, not ${count.typ}')
			return none
		}
	}
	return TExpr{
		kind: .binary
		op:   n.op
		typ:  a.typ
		args: [a, count]
	}
}

fn (mut k Checker) convert(n &Node) ?TExpr {
	t := n.typ
	if t == .void {
		k.fail('as_(.void) is not a conversion')
		return none
	}
	an := n.args[0]
	if is_literal(an) {
		return k.literal(an.node, t)
	}
	a := k.expr(an, .void)?
	if a.typ == t {
		return a
	}
	return TExpr{
		kind: .convert
		typ:  t
		args: [a]
	}
}

fn (mut k Checker) call(n &Node, statement bool) ?TExpr {
	id := n.func
	f := k.p.funcs[id]
	k.called[id] = true
	mut list := k.calls[k.func] or { []int{} }
	list << id
	k.calls[k.func] = list
	if n.args.len != f.params.len {
		k.fail('`${f.name}` takes ${f.params.len} arguments, not ${n.args.len}')
		return none
	}
	mut args := []TExpr{}
	for i, arg in n.args {
		args << k.assign(arg, f.params[i].typ)?
	}
	if !statement && f.ret == .void {
		k.fail('`${f.name}` returns nothing, so it cannot be used as a value')
		return none
	}
	return TExpr{
		kind: .call
		typ:  f.ret
		func: id
		args: args
	}
}
