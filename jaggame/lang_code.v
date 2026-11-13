module jaggame

import jagkit

// AsmFn emits 68000 code in place of a statement: the escape hatch for the
// runtime. It may change d0..d6 and a0..a4.
pub type AsmFn = fn (mut m jagkit.M68k)

enum StmtKind {
	set
	if_
	loop
	call
	ret
	break_
	continue_
	asm
}

enum LoopKind {
	while_
	for_
	repeat
}

// Stmt is one statement as the program wrote it, before type checking.
struct Stmt {
	kind     StmtKind
	loop     LoopKind
	exprs    []Expr   // set: dst, value; if_: the conditions; while_: cond; for_: var, from, to; repeat: count; call: the call; ret: the value, if any
	bodies   [][]Stmt // if_: one per condition, then the else; loops: the body
	has_else bool
	asm      int
}

enum BlockKind {
	body
	if_
	loop
}

struct Block {
	kind BlockKind
	loop LoopKind
mut:
	exprs    []Expr
	bodies   [][]Stmt
	has_else bool
}

// Code is the body of a function under construction. Blocks are opened by
// `if_`, `while_`, `for_` and `repeat` and closed by `end`.
@[heap]
pub struct Code {
mut:
	prog   &Program
	func   int
	blocks []Block
}

fn (mut c Code) problem(message string) {
	c.prog.problems << 'function `${c.prog.funcs[c.func].name}`: ${message}'
}

fn (mut c Code) add(s Stmt) {
	mut b := &c.blocks[c.blocks.len - 1]
	if b.kind == .body {
		if b.bodies.len == 0 {
			b.bodies << []Stmt{}
		}
	}
	b.bodies[b.bodies.len - 1] << s
}

fn (c &Code) in_loop() bool {
	for b in c.blocks {
		if b.kind == .loop {
			return true
		}
	}
	return false
}

// statements is the finished body, or none while a block is open.
fn (c &Code) statements() []Stmt {
	if c.blocks.len == 0 || c.blocks[0].bodies.len == 0 {
		return []Stmt{}
	}
	return c.blocks[0].bodies[0]
}

// open_blocks names the blocks that `end` has not closed.
fn (c &Code) open_blocks() []string {
	mut open := []string{}
	for b in c.blocks[1..] {
		open << match b.kind {
			.if_ { 'if_' }
			.loop { b.loop.str() }
			.body { 'body' }
		}
	}
	return open
}

// set stores a value. The value converts to the destination's type by the
// widening rules; narrowing needs `as_`.
pub fn (mut c Code) set(dst Expr, value Val) {
	c.add(Stmt{
		kind:  .set
		exprs: [dst, lit(value)]
	})
}

// inc adds 1 (1.0 for a `fix`).
pub fn (mut c Code) inc(dst Expr) {
	c.set(dst, dst.add(1))
}

// dec subtracts 1 (1.0 for a `fix`).
pub fn (mut c Code) dec(dst Expr) {
	c.set(dst, dst.sub(1))
}

// add_to adds a value to a destination.
pub fn (mut c Code) add_to(dst Expr, value Val) {
	c.set(dst, dst.add(value))
}

// sub_from subtracts a value from a destination.
pub fn (mut c Code) sub_from(dst Expr, value Val) {
	c.set(dst, dst.sub(value))
}

// if_ opens a block that runs when the condition is true.
pub fn (mut c Code) if_(cond Val) {
	c.blocks << Block{
		kind:   .if_
		exprs:  [lit(cond)]
		bodies: [[]Stmt{}]
	}
}

// else_if adds a branch to the innermost `if_`.
pub fn (mut c Code) else_if(cond Val) {
	mut b := &c.blocks[c.blocks.len - 1]
	if b.kind != .if_ {
		c.problem('else_if without an if_')
		return
	}
	if b.has_else {
		c.problem('else_if after else_')
		return
	}
	b.exprs << lit(cond)
	b.bodies << []Stmt{}
}

// else_ adds the branch that runs when no condition of the innermost `if_`
// was true.
pub fn (mut c Code) else_() {
	mut b := &c.blocks[c.blocks.len - 1]
	if b.kind != .if_ {
		c.problem('else_ without an if_')
		return
	}
	if b.has_else {
		c.problem('a second else_ for the same if_')
		return
	}
	b.has_else = true
	b.bodies << []Stmt{}
}

// while_ opens a loop that runs while the condition is true.
pub fn (mut c Code) while_(cond Val) {
	c.blocks << Block{
		kind:   .loop
		loop:   .while_
		exprs:  [lit(cond)]
		bodies: [[]Stmt{}]
	}
}

// for_ opens a loop with `v` going from `from` up to `to - 1`. Like C's
// `for`, `to` is evaluated before every step.
pub fn (mut c Code) for_(v Expr, from Val, to Val) {
	c.blocks << Block{
		kind:   .loop
		loop:   .for_
		exprs:  [v, lit(from), lit(to)]
		bodies: [[]Stmt{}]
	}
}

// repeat opens a loop that runs `count` times; the count is evaluated once,
// and a negative one runs no times.
pub fn (mut c Code) repeat(count Val) {
	c.blocks << Block{
		kind:   .loop
		loop:   .repeat
		exprs:  [lit(count)]
		bodies: [[]Stmt{}]
	}
}

// end closes the innermost block.
pub fn (mut c Code) end() {
	if c.blocks.len <= 1 {
		c.problem('end() without an open block')
		return
	}
	b := c.blocks.pop()
	match b.kind {
		.if_ {
			c.add(Stmt{
				kind:     .if_
				exprs:    b.exprs
				bodies:   b.bodies
				has_else: b.has_else
			})
		}
		.loop {
			c.add(Stmt{
				kind:   .loop
				loop:   b.loop
				exprs:  b.exprs
				bodies: b.bodies
			})
		}
		.body {}
	}
}

// break_ leaves the innermost loop.
pub fn (mut c Code) break_() {
	if !c.in_loop() {
		c.problem('break_ outside a loop')
	}
	c.add(Stmt{
		kind: .break_
	})
}

// continue_ goes on with the next step of the innermost loop.
pub fn (mut c Code) continue_() {
	if !c.in_loop() {
		c.problem('continue_ outside a loop')
	}
	c.add(Stmt{
		kind: .continue_
	})
}

// call calls a function as a statement; a result is thrown away.
pub fn (mut c Code) call(f Func, args ...Val) {
	c.add(Stmt{
		kind:  .call
		exprs: [f.call(...args)]
	})
}

// ret returns a value from the function.
pub fn (mut c Code) ret(value Val) {
	c.add(Stmt{
		kind:  .ret
		exprs: [lit(value)]
	})
}

// ret_void returns from a function that has no result.
pub fn (mut c Code) ret_void() {
	c.add(Stmt{
		kind: .ret
	})
}

// asm emits 68000 code in place of a statement. The interpreter cannot run
// it; games should not need it.
pub fn (mut c Code) asm(emit AsmFn) {
	c.prog.asms << emit
	c.add(Stmt{
		kind: .asm
		asm:  c.prog.asms.len - 1
	})
}

// local declares a variable of the function. It is set to 0 each time the
// function is called.
pub fn (mut c Code) local(name string, t Type) Expr {
	f := c.prog.funcs[c.func]
	if t == .void {
		c.problem('local `${name}` cannot be void')
	}
	if !valid_name(name) {
		c.problem('`${name}` is not a valid local name')
	}
	for v in c.prog.vars {
		if v.owner == c.func && v.name == name {
			c.problem('local `${name}`: the name is already used in this function')
		}
	}
	return c.prog.add_var(Var{
		name:  name
		label: '${f.name}.${name}'
		kind:  .scalar
		role:  .local
		typ:   t
		owner: c.func
	})
}

// local_bool declares a `bool` local.
pub fn (mut c Code) local_bool(name string) Expr {
	return c.local(name, .bool)
}

// local_u8 declares a `u8` local.
pub fn (mut c Code) local_u8(name string) Expr {
	return c.local(name, .u8)
}

// local_i8 declares an `i8` local.
pub fn (mut c Code) local_i8(name string) Expr {
	return c.local(name, .i8)
}

// local_u16 declares a `u16` local.
pub fn (mut c Code) local_u16(name string) Expr {
	return c.local(name, .u16)
}

// local_i16 declares an `i16` local.
pub fn (mut c Code) local_i16(name string) Expr {
	return c.local(name, .i16)
}

// local_u32 declares a `u32` local.
pub fn (mut c Code) local_u32(name string) Expr {
	return c.local(name, .u32)
}

// local_i32 declares an `i32` local.
pub fn (mut c Code) local_i32(name string) Expr {
	return c.local(name, .i32)
}

// local_fix declares a `fix` local.
pub fn (mut c Code) local_fix(name string) Expr {
	return c.local(name, .fix)
}
