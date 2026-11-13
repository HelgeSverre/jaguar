module jaggame

// Printing expressions and statements the way the builder writes them, for
// messages and for the fuzzer's failing cases.

// show writes an expression as builder calls: `score.add(10)`.
pub fn (p &Program) show(e Expr) string {
	n := e.node
	return match n.kind {
		.int_literal {
			n.int_value.str()
		}
		.float_literal {
			show_float(n.float_value)
		}
		.bool_literal {
			if n.int_value != 0 {
				'true'
			} else {
				'false'
			}
		}
		.variable {
			if n.var >= 0 && n.var < p.vars.len {
				p.vars[n.var].name
			} else {
				'?'
			}
		}
		.element {
			'${p.receiver(n.args[0])}.at(${p.show(n.args[1])})'
		}
		.field {
			"${p.receiver(n.args[0])}.field('${n.name}')"
		}
		.unary {
			'${p.receiver(n.args[0])}.${n.op.name()}()'
		}
		.binary {
			'${p.receiver(n.args[0])}.${n.op.name()}(${p.show(n.args[1])})'
		}
		.convert {
			'${p.receiver(n.args[0])}.as_(.${n.typ})'
		}
		.call {
			'${p.funcs[n.func].name}.call(${n.args.map(p.show(it)).join(', ')})'
		}
		.invalid {
			'<${n.name}>'
		}
	}
}

fn show_float(f f64) string {
	s := f.str()
	return if s.contains('.') || s.contains('e') { s } else { s + '.0' }
}

// receiver writes the left side of a method call; a bare literal needs
// `lit(…)` there.
fn (p &Program) receiver(e Expr) string {
	if is_literal(e) {
		return 'lit(${p.show(e)})'
	}
	return p.show(e)
}

// show_stmt writes the head of a statement: `set(x, y)`, `if_(c)`.
fn (p &Program) show_stmt(s Stmt) string {
	return match s.kind {
		.set {
			'set(${p.show(s.exprs[0])}, ${p.show(s.exprs[1])})'
		}
		.if_ {
			'if_(${p.show(s.exprs[0])})'
		}
		.loop {
			match s.loop {
				.while_ { 'while_(${p.show(s.exprs[0])})' }
				.for_ { 'for_(${s.exprs.map(p.show(it)).join(', ')})' }
				.repeat { 'repeat(${p.show(s.exprs[0])})' }
			}
		}
		.call {
			'call(${p.show(s.exprs[0])})'
		}
		.ret {
			if s.exprs.len == 0 {
				'ret_void()'
			} else {
				'ret(${p.show(s.exprs[0])})'
			}
		}
		.break_ {
			'break_()'
		}
		.continue_ {
			'continue_()'
		}
		.asm {
			'asm(…)'
		}
	}
}

// listing writes a function's body as the builder calls that made it.
pub fn (p &Program) listing(f Func) string {
	code := p.bodies[f.id] or { return '// `${f.name}` is not defined' }
	params := f.params.map('${it.name} ${it.typ}').join(', ')
	ret := if f.ret == .void { '' } else { ' ${f.ret}' }
	mut lines := ['// fn ${f.name}(${params})${ret}']
	for v in p.vars {
		if v.owner == f.id && v.role == .local {
			lines << "${v.name} := c.local('${v.name}', .${v.typ})"
		}
	}
	p.list_block(code.statements(), 0, mut lines)
	return lines.join('\n')
}

fn (p &Program) list_block(stmts []Stmt, depth int, mut lines []string) {
	indent := '\t'.repeat(depth)
	for s in stmts {
		match s.kind {
			.if_ {
				for i, cond in s.exprs {
					head := if i == 0 { 'if_' } else { 'else_if' }
					lines << '${indent}c.${head}(${p.show(cond)})'
					p.list_block(s.bodies[i], depth + 1, mut lines)
				}
				if s.has_else {
					lines << '${indent}c.else_()'
					p.list_block(s.bodies[s.bodies.len - 1], depth + 1, mut lines)
				}
				lines << '${indent}c.end()'
			}
			.loop {
				lines << '${indent}c.${p.show_stmt(s)}'
				p.list_block(s.bodies[0], depth + 1, mut lines)
				lines << '${indent}c.end()'
			}
			.call {
				call := s.exprs[0].node
				mut args := [p.funcs[call.func].name]
				args << call.args.map(p.show(it))
				lines << '${indent}c.call(${args.join(', ')})'
			}
			else {
				lines << '${indent}c.${p.show_stmt(s)}'
			}
		}
	}
}
