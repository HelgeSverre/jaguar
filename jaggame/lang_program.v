module jaggame

enum VarKind {
	scalar
	array   // read-write elements
	table   // read-only elements
	records // an array of records
}

enum VarRole {
	global
	param
	local
	hidden // a counter the compiler adds, for `repeat`
}

// Var is one variable, array or table of a program.
struct Var {
	name   string // as the program wrote it
	label  string // the assembler label of its storage
	kind   VarKind
	role   VarRole
	typ    Type // of the variable, or of each element; void for records
	len    int = 1
	record int = -1
	owner  int = -1 // the function of a parameter or local
	init   []i64 // raw initial values, one per element; empty means zeroes
}

fn (v Var) describe() string {
	return match v.kind {
		.scalar { '`${v.name}`' }
		.array { 'array `${v.name}`' }
		.table { 'table `${v.name}`' }
		.records { 'array of records `${v.name}`' }
	}
}

// Field is one field of a record.
pub struct Field {
pub:
	name string
	typ  Type
}

struct RecordInfo {
	name    string
	fields  []Field
	offsets []int
	size    int // a power of two, so that indexing is a shift
	shift   int
}

fn (r RecordInfo) field_index(name string) int {
	for i, f in r.fields {
		if f.name == name {
			return i
		}
	}
	return -1
}

// Record is a record type made by `Program.record`.
pub struct Record {
pub:
	id   int
	name string
}

// Param is one parameter of a function.
pub struct Param {
pub:
	name string
	typ  Type
}

// Func is a function made by `Program.func`. Its parameters, locals and
// result live at fixed addresses, so a function cannot call itself, even
// through others.
pub struct Func {
pub:
	id         int
	name       string
	params     []Param
	ret        Type
	param_vars []int
}

// arg is a parameter of the function, as an expression.
pub fn (f Func) arg(name string) Expr {
	for i, p in f.params {
		if p.name == name {
			return Expr{&Node{
				kind: .variable
				var:  f.param_vars[i]
			}}
		}
	}
	return invalid('`${f.name}` has no parameter `${name}`')
}

// call is a call of the function, as an expression.
pub fn (f Func) call(args ...Val) Expr {
	return Expr{&Node{
		kind: .call
		func: f.id
		args: args.map(lit(it))
	}}
}

struct FuncInfo {
	name       string
	params     []Param
	param_vars []int
	ret        Type
}

// Program collects the variables, tables, records and functions of a game.
// Mistakes in declarations are collected and reported together, with the
// type errors, when the program is built.
@[heap]
pub struct Program {
mut:
	vars     []Var
	records  []RecordInfo
	funcs    []FuncInfo
	bodies   map[int]&Code
	asms     []AsmFn
	natives  map[int]NativeFn
	problems []string
	names    map[string]bool
	machines []&Machine
}

// new_program starts an empty program.
pub fn new_program() &Program {
	return &Program{}
}

fn valid_name(name string) bool {
	if name == '' || name[0].is_digit() {
		return false
	}
	for c in name {
		if !(c.is_letter() || c.is_digit() || c == `_`) {
			return false
		}
	}
	return true
}

// claim reserves a name in the program's one namespace of globals, arrays,
// tables and functions.
fn (mut p Program) claim(name string, what string) bool {
	if !valid_name(name) {
		p.problems << '${what} `${name}`: a name is letters, digits and _, not starting with a digit'
		return false
	}
	if name in p.names {
		p.problems << '${what} `${name}`: the name is already used'
		return false
	}
	p.names[name] = true
	return true
}

fn (mut p Program) add_var(v Var) Expr {
	p.vars << v
	return Expr{&Node{
		kind: .variable
		var:  p.vars.len - 1
	}}
}

// constant turns a V value into the raw value of a type, or says why not.
fn constant(t Type, v Val) !i64 {
	match v {
		int {
			return int_constant(t, v)
		}
		u16 {
			return int_constant(t, v)
		}
		i64 {
			return int_constant(t, v)
		}
		f64 {
			if t != .fix {
				return error('the number ${v} is a fix, not a ${t}')
			}
			if !fix_fits(v) {
				return error('${v} does not fit fix (${t.range()})')
			}
			return fix_raw(v)
		}
		bool {
			if t != .bool {
				return error('${v} is a bool, not a ${t}')
			}
			return if v { 1 } else { 0 }
		}
		Expr {
			return error('an initial value must be a V literal')
		}
	}
}

fn int_constant(t Type, v i64) !i64 {
	if t == .fix {
		if v < -32768 || v > 32767 {
			return error('${v} does not fit fix (${t.range()})')
		}
		return v * fix_one
	}
	if !t.is_integer() {
		return error('the integer ${v} cannot be a ${t}')
	}
	if !t.fits(v) {
		return error('${v} does not fit ${t} (${t.range()})')
	}
	return v
}

// global declares a variable that lives as long as the program. Its
// initial value is 0 unless one is given.
pub fn (mut p Program) global(name string, t Type, init ...Val) Expr {
	mut values := []i64{}
	if t == .void {
		p.problems << 'global `${name}`: a variable cannot be void'
	} else if init.len > 1 {
		p.problems << 'global `${name}`: one initial value at most'
	} else if init.len == 1 {
		values << constant(t, init[0]) or {
			p.problems << 'global `${name}`: ${err.msg()}'
			i64(0)
		}
	}
	p.claim(name, 'global')
	return p.add_var(Var{
		name:  name
		label: name
		kind:  .scalar
		role:  .global
		typ:   t
		init:  values
	})
}

// bool declares a `bool` global.
pub fn (mut p Program) bool(name string, init ...bool) Expr {
	return p.global(name, .bool, ...init.map(Val(it)))
}

// u8 declares a `u8` global.
pub fn (mut p Program) u8(name string, init ...int) Expr {
	return p.global(name, .u8, ...init.map(Val(it)))
}

// i8 declares an `i8` global.
pub fn (mut p Program) i8(name string, init ...int) Expr {
	return p.global(name, .i8, ...init.map(Val(it)))
}

// u16 declares a `u16` global.
pub fn (mut p Program) u16(name string, init ...int) Expr {
	return p.global(name, .u16, ...init.map(Val(it)))
}

// i16 declares an `i16` global.
pub fn (mut p Program) i16(name string, init ...int) Expr {
	return p.global(name, .i16, ...init.map(Val(it)))
}

// u32 declares a `u32` global.
pub fn (mut p Program) u32(name string, init ...i64) Expr {
	return p.global(name, .u32, ...init.map(Val(it)))
}

// i32 declares an `i32` global.
pub fn (mut p Program) i32(name string, init ...i64) Expr {
	return p.global(name, .i32, ...init.map(Val(it)))
}

// fix declares a `fix` global.
pub fn (mut p Program) fix(name string, init ...f64) Expr {
	return p.global(name, .fix, ...init.map(Val(it)))
}

// array declares a read-write array of `len` elements, all 0.
pub fn (mut p Program) array(name string, t Type, len int) Expr {
	if t == .void {
		p.problems << 'array `${name}`: the elements cannot be void'
	}
	if len < 1 {
		p.problems << 'array `${name}`: the length ${len} must be at least 1'
	}
	p.claim(name, 'array')
	return p.add_var(Var{
		name:  name
		label: name
		kind:  .array
		role:  .global
		typ:   t
		len:   if len < 1 { 1 } else { len }
	})
}

// array_u8 declares an array of `u8`.
pub fn (mut p Program) array_u8(name string, len int) Expr {
	return p.array(name, .u8, len)
}

// array_i8 declares an array of `i8`.
pub fn (mut p Program) array_i8(name string, len int) Expr {
	return p.array(name, .i8, len)
}

// array_u16 declares an array of `u16`.
pub fn (mut p Program) array_u16(name string, len int) Expr {
	return p.array(name, .u16, len)
}

// array_i16 declares an array of `i16`.
pub fn (mut p Program) array_i16(name string, len int) Expr {
	return p.array(name, .i16, len)
}

// array_u32 declares an array of `u32`.
pub fn (mut p Program) array_u32(name string, len int) Expr {
	return p.array(name, .u32, len)
}

// array_i32 declares an array of `i32`.
pub fn (mut p Program) array_i32(name string, len int) Expr {
	return p.array(name, .i32, len)
}

// array_fix declares an array of `fix`.
pub fn (mut p Program) array_fix(name string, len int) Expr {
	return p.array(name, .fix, len)
}

// table declares read-only data. Every value must fit the type.
pub fn (mut p Program) table(name string, t Type, values []Val) Expr {
	mut raw := []i64{}
	for v in values {
		raw << constant(t, v) or {
			p.problems << 'table `${name}`: ${err.msg()}'
			i64(0)
		}
	}
	if values.len == 0 {
		p.problems << 'table `${name}`: a table needs at least one value'
		raw << 0
	}
	p.claim(name, 'table')
	return p.add_var(Var{
		name:  name
		label: name
		kind:  .table
		role:  .global
		typ:   t
		len:   raw.len
		init:  raw
	})
}

// table_u8 declares a table of `u8`.
pub fn (mut p Program) table_u8(name string, values []int) Expr {
	return p.table(name, .u8, values.map(Val(it)))
}

// table_i8 declares a table of `i8`.
pub fn (mut p Program) table_i8(name string, values []int) Expr {
	return p.table(name, .i8, values.map(Val(it)))
}

// table_u16 declares a table of `u16`.
pub fn (mut p Program) table_u16(name string, values []int) Expr {
	return p.table(name, .u16, values.map(Val(it)))
}

// table_i16 declares a table of `i16`.
pub fn (mut p Program) table_i16(name string, values []int) Expr {
	return p.table(name, .i16, values.map(Val(it)))
}

// table_u32 declares a table of `u32`.
pub fn (mut p Program) table_u32(name string, values []i64) Expr {
	return p.table(name, .u32, values.map(Val(it)))
}

// table_i32 declares a table of `i32`.
pub fn (mut p Program) table_i32(name string, values []i64) Expr {
	return p.table(name, .i32, values.map(Val(it)))
}

// table_fix declares a table of `fix`.
pub fn (mut p Program) table_fix(name string, values []f64) Expr {
	return p.table(name, .fix, values.map(Val(it)))
}

// record declares a record type. Each field is aligned to its size and the
// record's size is rounded up to a power of two.
pub fn (mut p Program) record(name string, fields []Field) Record {
	mut offsets := []int{}
	mut at := 0
	mut seen := map[string]bool{}
	for f in fields {
		if f.typ == .void {
			p.problems << 'record `${name}`: field `${f.name}` cannot be void'
		}
		if !valid_name(f.name) {
			p.problems << 'record `${name}`: `${f.name}` is not a valid field name'
		}
		if f.name in seen {
			p.problems << 'record `${name}`: field `${f.name}` appears twice'
		}
		seen[f.name] = true
		size := if f.typ == .void { 1 } else { f.typ.size() }
		for at % size != 0 {
			at++
		}
		offsets << at
		at += size
	}
	if fields.len == 0 {
		p.problems << 'record `${name}`: a record needs at least one field'
	}
	mut size := 2
	mut shift := 1
	for size < at {
		size *= 2
		shift++
	}
	p.records << RecordInfo{
		name:    name
		fields:  fields.clone()
		offsets: offsets
		size:    size
		shift:   shift
	}
	return Record{
		id:   p.records.len - 1
		name: name
	}
}

// array_of declares an array of `len` records, all fields 0.
pub fn (mut p Program) array_of(name string, r Record, len int) Expr {
	if len < 1 {
		p.problems << 'array `${name}`: the length ${len} must be at least 1'
	}
	p.claim(name, 'array')
	return p.add_var(Var{
		name:   name
		label:  name
		kind:   .records
		role:   .global
		typ:    .void
		len:    if len < 1 { 1 } else { len }
		record: r.id
	})
}

// func declares a function. Its body is given later with `define`, so
// functions can call each other in any order.
pub fn (mut p Program) func(name string, params []Param, ret Type) Func {
	p.claim(name, 'function')
	id := p.funcs.len
	mut vars := []int{}
	mut seen := map[string]bool{}
	for param in params {
		if param.typ == .void {
			p.problems << 'function `${name}`: parameter `${param.name}` cannot be void'
		}
		if !valid_name(param.name) {
			p.problems << 'function `${name}`: `${param.name}` is not a valid parameter name'
		}
		if param.name in seen {
			p.problems << 'function `${name}`: parameter `${param.name}` appears twice'
		}
		seen[param.name] = true
		p.vars << Var{
			name:  param.name
			label: '${name}.${param.name}'
			kind:  .scalar
			role:  .param
			typ:   param.typ
			owner: id
		}
		vars << p.vars.len - 1
	}
	p.funcs << FuncInfo{
		name:       name
		params:     params.clone()
		param_vars: vars
		ret:        ret
	}
	return Func{
		id:         id
		name:       name
		params:     params.clone()
		ret:        ret
		param_vars: vars
	}
}

// define starts the body of a function and returns the block to add its
// statements to.
pub fn (mut p Program) define(f Func) &Code {
	if f.id in p.bodies {
		p.problems << 'function `${f.name}` is defined twice'
	}
	mut c := &Code{
		prog:   p
		func:   f.id
		blocks: [Block{
			kind:   .body
			bodies: [[]Stmt{}]
		}]
	}
	p.bodies[f.id] = c
	return c
}
