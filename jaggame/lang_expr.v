module jaggame

// Op is an operation of an expression.
pub enum Op {
	add
	sub
	mul
	div
	mod
	and_
	or_
	xor
	shl
	shr
	min
	max
	eq
	ne
	lt
	le
	gt
	ge
	both
	either
	neg
	not_
	invert
	abs
}

// name is the operation as it is written in the builder.
pub fn (o Op) name() string {
	return match o {
		.and_ { 'and' }
		.or_ { 'or_' }
		.not_ { 'not' }
		else { o.str() }
	}
}

fn (o Op) is_compare() bool {
	return o in [.eq, .ne, .lt, .le, .gt, .ge]
}

enum NodeKind {
	int_literal
	float_literal
	bool_literal
	variable
	element
	field
	unary
	binary
	convert
	call
	invalid
}

@[heap]
struct Node {
	kind        NodeKind
	op          Op
	args        []Expr
	int_value   i64
	float_value f64
	var         int = -1
	func        int = -1
	name        string // the field name, or what is wrong with an invalid node
	typ         Type   // the target of a conversion
}

// Expr is a value of the language: a literal, a variable, an element, a
// field, or an operation on other expressions. A variable handle is an
// Expr too, so it can be used wherever a value can, and as a destination.
// Expressions are only descriptions; their types are checked when the
// program is built.
pub struct Expr {
	node &Node
}

// Val is what builder methods take: an expression or a V literal. An `int`
// takes the type of the other side, an `f64` is a `fix`.
pub type Val = Expr | int | f64 | bool

// lit turns a literal into an expression. Its type comes from where it is
// used; `lit(5).as_(.u8)` is a `u8` constant.
pub fn lit(v Val) Expr {
	return match v {
		Expr {
			v
		}
		int {
			Expr{&Node{
				kind:      .int_literal
				int_value: v
			}}
		}
		f64 {
			Expr{&Node{
				kind:        .float_literal
				float_value: v
			}}
		}
		bool {
			Expr{&Node{
				kind:      .bool_literal
				int_value: if v { 1 } else { 0 }
			}}
		}
	}
}

fn binary(op Op, a Expr, b Val) Expr {
	return Expr{&Node{
		kind: .binary
		op:   op
		args: [a, lit(b)]
	}}
}

fn unary(op Op, a Expr) Expr {
	return Expr{&Node{
		kind: .unary
		op:   op
		args: [a]
	}}
}

fn invalid(message string) Expr {
	return Expr{&Node{
		kind: .invalid
		name: message
	}}
}

// add is a + b.
pub fn (a Expr) add(b Val) Expr {
	return binary(.add, a, b)
}

// sub is a - b.
pub fn (a Expr) sub(b Val) Expr {
	return binary(.sub, a, b)
}

// mul is a * b. For `fix` the product keeps 16.16.
pub fn (a Expr) mul(b Val) Expr {
	return binary(.mul, a, b)
}

// div is a / b, rounded toward zero; dividing by zero gives 0.
pub fn (a Expr) div(b Val) Expr {
	return binary(.div, a, b)
}

// mod is the remainder of a / b, with the sign of a; by zero it is 0.
pub fn (a Expr) mod(b Val) Expr {
	return binary(.mod, a, b)
}

// and keeps the bits set in both.
pub fn (a Expr) and(b Val) Expr {
	return binary(.and_, a, b)
}

// or_ keeps the bits set in either (`or` is a V keyword).
pub fn (a Expr) or_(b Val) Expr {
	return binary(.or_, a, b)
}

// xor keeps the bits set in one but not both.
pub fn (a Expr) xor(b Val) Expr {
	return binary(.xor, a, b)
}

// shl shifts left by 0..31 bits.
pub fn (a Expr) shl(count Val) Expr {
	return binary(.shl, a, count)
}

// shr shifts right by 0..31 bits: arithmetically for signed types and
// `fix`, filling with zeroes for unsigned ones.
pub fn (a Expr) shr(count Val) Expr {
	return binary(.shr, a, count)
}

// min is the smaller of a and b.
pub fn (a Expr) min(b Val) Expr {
	return binary(.min, a, b)
}

// max is the larger of a and b.
pub fn (a Expr) max(b Val) Expr {
	return binary(.max, a, b)
}

// eq is true when a equals b.
pub fn (a Expr) eq(b Val) Expr {
	return binary(.eq, a, b)
}

// ne is true when a differs from b.
pub fn (a Expr) ne(b Val) Expr {
	return binary(.ne, a, b)
}

// lt is true when a < b.
pub fn (a Expr) lt(b Val) Expr {
	return binary(.lt, a, b)
}

// le is true when a <= b.
pub fn (a Expr) le(b Val) Expr {
	return binary(.le, a, b)
}

// gt is true when a > b.
pub fn (a Expr) gt(b Val) Expr {
	return binary(.gt, a, b)
}

// ge is true when a >= b.
pub fn (a Expr) ge(b Val) Expr {
	return binary(.ge, a, b)
}

// both is true when a and b are; b is not evaluated when a is false.
pub fn (a Expr) both(b Val) Expr {
	return binary(.both, a, b)
}

// either is true when a or b is; b is not evaluated when a is true.
pub fn (a Expr) either(b Val) Expr {
	return binary(.either, a, b)
}

// neg is -a, for signed types and `fix`.
pub fn (a Expr) neg() Expr {
	return unary(.neg, a)
}

// not flips every bit of an integer.
pub fn (a Expr) not() Expr {
	return unary(.not_, a)
}

// invert is the boolean not.
pub fn (a Expr) invert() Expr {
	return unary(.invert, a)
}

// abs is the magnitude of a signed value or a `fix`; the smallest value
// stays as it is.
pub fn (a Expr) abs() Expr {
	return unary(.abs, a)
}

// as_ converts to another type. Integers are cut to the new width or
// extended; a `fix` becomes an integer by rounding down (-0.5 becomes -1);
// anything becomes a `bool` by comparing it with zero.
pub fn (a Expr) as_(t Type) Expr {
	return Expr{&Node{
		kind: .convert
		args: [a]
		typ:  t
	}}
}

// at is an element of an array, a table or an array of records. The index
// is not checked at run time; a literal index is checked at build time.
pub fn (a Expr) at(index Val) Expr {
	return Expr{&Node{
		kind: .element
		args: [a, lit(index)]
	}}
}

// field is a field of a record element: `guards.at(i).field('x')`.
pub fn (a Expr) field(name string) Expr {
	return Expr{&Node{
		kind: .field
		args: [a]
		name: name
	}}
}

// The operators that V lets a struct overload with a result of the same
// type. Comparisons cannot be overloaded this way: V requires `<` and `==`
// to return a V `bool`.

// + is add.
pub fn (a Expr) + (b Expr) Expr {
	return a.add(b)
}

// - is sub.
pub fn (a Expr) - (b Expr) Expr {
	return a.sub(b)
}

// * is mul.
pub fn (a Expr) * (b Expr) Expr {
	return a.mul(b)
}

// / is div.
pub fn (a Expr) / (b Expr) Expr {
	return a.div(b)
}

// % is mod.
pub fn (a Expr) % (b Expr) Expr {
	return a.mod(b)
}
