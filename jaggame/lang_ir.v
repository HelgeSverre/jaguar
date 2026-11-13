module jaggame

// The typed IR. Type checking turns the program's expressions and
// statements into these: every literal has its type, every implicit
// conversion is explicit, and `for_`, `repeat`, `inc` and the like are
// reduced to `set` and one kind of loop. The interpreter and the code
// generator both work from this form, so they agree on what a program
// means.

enum TKind {
	constant
	load
	unary
	binary  // arithmetic, bits, shifts, min and max: the result has the operands' type
	compare // the operands have one type, the result is bool
	logic   // both and either
	convert
	call
}

// TExpr is a typed expression. Operands of a binary operation have the
// operation's type, except the count of a shift, which is any integer.
struct TExpr {
	kind  TKind
	typ   Type
	op    Op
	value i64 // a constant's raw value
	place TPlace
	func  int = -1
	args  []TExpr
}

// TPlace is a scalar in memory: a variable, an element or a field.
struct TPlace {
	var    int
	typ    Type
	field  int = -1
	offset int     // of the field in its record
	shift  int     // log2 of the element or record size
	index  []TExpr // empty for a variable, else the index
}

enum TStmtKind {
	set
	branch // conditions with a body each, then the else body
	loop   // the condition, the body and the step that `continue_` goes on with
	eval   // a call whose result is thrown away
	ret
	break_
	continue_
	asm
}

// TStmt is a typed statement.
struct TStmt {
	kind    TStmtKind
	place   TPlace
	exprs   []TExpr   // set: value; branch: conditions; loop: condition; eval: call; ret: value
	bodies  [][]TStmt // branch: one per condition, then the else (possibly empty); loop: body, step
	asm     int
	returns bool
}

// LFunc is a checked function.
struct LFunc {
	id      int
	name    string
	ret     Type
	params  []int
	locals  []int // set to 0 on entry, hidden counters included
	body    []TStmt
	defined bool
}

// Lowered is a checked program, ready for the interpreter or the code
// generator.
struct Lowered {
	vars    []Var
	records []RecordInfo
	funcs   []LFunc
	asms    []AsmFn
	natives map[int]NativeFn
}

fn (l &Lowered) stride(v Var) int {
	if v.kind == .records {
		return l.records[v.record].size
	}
	return v.typ.size()
}

// slots is how many values the interpreter keeps for a variable.
fn (l &Lowered) slots(v Var) int {
	if v.kind == .records {
		return v.len * l.records[v.record].fields.len
	}
	return v.len
}

fn (l &Lowered) func_named(name string) int {
	for f in l.funcs {
		if f.name == name {
			return f.id
		}
	}
	return -1
}

fn (l &Lowered) var_named(name string) int {
	for i, v in l.vars {
		if v.role == .global && v.name == name {
			return i
		}
	}
	return -1
}
