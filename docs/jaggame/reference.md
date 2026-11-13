# jaggame reference

Every public name in `jaggame`, with the comment from its source. This file is generated: see `jaggame/reference_test.v`. The guide is [`guide.md`](guide.md); the design is [`design.md`](design.md).

## Types

`jaggame/lang_types.v`

| Declaration | |
|---|---|
| `enum Type` | Type is the type of a value in the language. `void` is only the result of a function that returns nothing. |
| `const all_types = [Type.bool, .u8, .i8, .u16, .i16, .u32, .i32, .fix]` | all_types lists every type a variable can have. |
| `const fix_one = 65536` | fix_one is 1.0 in the 16.16 fixed-point format of `fix`. |
| `fn (t Type) size() int` | size is the number of bytes a value of the type takes in memory. |
| `fn (t Type) is_integer() bool` | is_integer is true for the eight- to 32-bit integer types. |
| `fn (t Type) is_number() bool` | is_number is true for the integers and `fix`. |
| `fn (t Type) is_signed() bool` | is_signed is true for the signed integers and `fix`. |
| `fn (t Type) smallest() i64` | smallest is the smallest raw value of the type. |
| `fn (t Type) largest() i64` | largest is the largest raw value of the type. |
| `fn (t Type) wrap(v i64) i64` | wrap reduces a raw value to the type's width, the way the 68000 does: the bits above the width are dropped and a signed type is sign-extended. |
| `fn fix_value(raw i64) f64` | fix_value turns a raw `fix` into a float, for tests and messages. |

## Expressions

`jaggame/lang_expr.v`

| Declaration | |
|---|---|
| `enum Op` | Op is an operation of an expression. |
| `fn (o Op) name() string` | name is the operation as it is written in the builder. |
| `struct Expr` | Expr is a value of the language: a literal, a variable, an element, a field, or an operation on other expressions. A variable handle is an Expr too, so it can be used wherever a value can, and as a destination. Expressions are only descriptions; their types are checked when the program is built. |
| `type Val = Expr \| int \| i64 \| f64 \| bool` | Val is what builder methods take: an expression or a V literal. An `int` (or an `i64`, for large `u32` values) takes the type of the other side, an `f64` is a `fix`. |
| `fn lit(v Val) Expr` | lit turns a literal into an expression. Its type comes from where it is used; `lit(5).as_(.u8)` is a `u8` constant. |
| `fn (a Expr) add(b Val) Expr` | add is a + b. |
| `fn (a Expr) sub(b Val) Expr` | sub is a - b. |
| `fn (a Expr) mul(b Val) Expr` | mul is a * b. For `fix` the product keeps 16.16. |
| `fn (a Expr) div(b Val) Expr` | div is a / b, rounded toward zero; dividing by zero gives 0. |
| `fn (a Expr) mod(b Val) Expr` | mod is the remainder of a / b, with the sign of a; by zero it is 0. |
| `fn (a Expr) and(b Val) Expr` | and keeps the bits set in both. |
| `fn (a Expr) or_(b Val) Expr` | or_ keeps the bits set in either (`or` is a V keyword). |
| `fn (a Expr) xor(b Val) Expr` | xor keeps the bits set in one but not both. |
| `fn (a Expr) shl(count Val) Expr` | shl shifts left by 0..31 bits. |
| `fn (a Expr) shr(count Val) Expr` | shr shifts right by 0..31 bits: arithmetically for signed types and `fix`, filling with zeroes for unsigned ones. |
| `fn (a Expr) min(b Val) Expr` | min is the smaller of a and b. |
| `fn (a Expr) max(b Val) Expr` | max is the larger of a and b. |
| `fn (a Expr) eq(b Val) Expr` | eq is true when a equals b. |
| `fn (a Expr) ne(b Val) Expr` | ne is true when a differs from b. |
| `fn (a Expr) lt(b Val) Expr` | lt is true when a < b. |
| `fn (a Expr) le(b Val) Expr` | le is true when a <= b. |
| `fn (a Expr) gt(b Val) Expr` | gt is true when a > b. |
| `fn (a Expr) ge(b Val) Expr` | ge is true when a >= b. |
| `fn (a Expr) both(b Val) Expr` | both is true when a and b are; b is not evaluated when a is false. |
| `fn (a Expr) either(b Val) Expr` | either is true when a or b is; b is not evaluated when a is true. |
| `fn (a Expr) neg() Expr` | neg is -a, for signed types and `fix`. |
| `fn (a Expr) not() Expr` | not flips every bit of an integer. |
| `fn (a Expr) invert() Expr` | invert is the boolean not. |
| `fn (a Expr) abs() Expr` | abs is the magnitude of a signed value or a `fix`; the smallest value stays as it is. |
| `fn (a Expr) as_(t Type) Expr` | as_ converts to another type. Integers are cut to the new width or extended; a `fix` becomes an integer by rounding down (-0.5 becomes -1); anything becomes a `bool` by comparing it with zero. |
| `fn (a Expr) at(index Val) Expr` | at is an element of an array, a table or an array of records. The index is not checked at run time; a literal index is checked at build time. |
| `fn (a Expr) field(name string) Expr` | field is a field of a record element: `guards.at(i).field('x')`. |
| `fn (a Expr) + (b Expr) Expr` | + is add. |
| `fn (a Expr) - (b Expr) Expr` | - is sub. |
| `fn (a Expr) * (b Expr) Expr` | * is mul. |
| `fn (a Expr) / (b Expr) Expr` | / is div. |
| `fn (a Expr) % (b Expr) Expr` | % is mod. |

## Programs: variables, tables, records and functions

`jaggame/lang_program.v`

| Declaration | |
|---|---|
| `struct Field` | Field is one field of a record. |
| `struct Record` | Record is a record type made by `Program.record`. |
| `struct Param` | Param is one parameter of a function. |
| `struct Func` | Func is a function made by `Program.func`. Its parameters, locals and result live at fixed addresses, so a function cannot call itself, even through others. |
| `fn (f Func) arg(name string) Expr` | arg is a parameter of the function, as an expression. |
| `fn (f Func) call(args ...Val) Expr` | call is a call of the function, as an expression. |
| `struct Program` | Program collects the variables, tables, records and functions of a game. Mistakes in declarations are collected and reported together, with the type errors, when the program is built. |
| `fn new_program() &Program` | new_program starts an empty program. |
| `fn (mut p Program) global(name string, t Type, init ...Val) Expr` | global declares a variable that lives as long as the program. Its initial value is 0 unless one is given. |
| `fn (mut p Program) bool(name string, init ...bool) Expr` | bool declares a `bool` global. |
| `fn (mut p Program) u8(name string, init ...int) Expr` | u8 declares a `u8` global. |
| `fn (mut p Program) i8(name string, init ...int) Expr` | i8 declares an `i8` global. |
| `fn (mut p Program) u16(name string, init ...int) Expr` | u16 declares a `u16` global. |
| `fn (mut p Program) i16(name string, init ...int) Expr` | i16 declares an `i16` global. |
| `fn (mut p Program) u32(name string, init ...i64) Expr` | u32 declares a `u32` global. |
| `fn (mut p Program) i32(name string, init ...i64) Expr` | i32 declares an `i32` global. |
| `fn (mut p Program) fix(name string, init ...f64) Expr` | fix declares a `fix` global. |
| `fn (mut p Program) array(name string, t Type, len int) Expr` | array declares a read-write array of `len` elements, all 0. |
| `fn (mut p Program) array_u8(name string, len int) Expr` | array_u8 declares an array of `u8`. |
| `fn (mut p Program) array_i8(name string, len int) Expr` | array_i8 declares an array of `i8`. |
| `fn (mut p Program) array_u16(name string, len int) Expr` | array_u16 declares an array of `u16`. |
| `fn (mut p Program) array_i16(name string, len int) Expr` | array_i16 declares an array of `i16`. |
| `fn (mut p Program) array_u32(name string, len int) Expr` | array_u32 declares an array of `u32`. |
| `fn (mut p Program) array_i32(name string, len int) Expr` | array_i32 declares an array of `i32`. |
| `fn (mut p Program) array_fix(name string, len int) Expr` | array_fix declares an array of `fix`. |
| `fn (mut p Program) table(name string, t Type, values []Val) Expr` | table declares read-only data. Every value must fit the type. |
| `fn (mut p Program) table_u8(name string, values []int) Expr` | table_u8 declares a table of `u8`. |
| `fn (mut p Program) table_i8(name string, values []int) Expr` | table_i8 declares a table of `i8`. |
| `fn (mut p Program) table_u16(name string, values []int) Expr` | table_u16 declares a table of `u16`. |
| `fn (mut p Program) table_i16(name string, values []int) Expr` | table_i16 declares a table of `i16`. |
| `fn (mut p Program) table_u32(name string, values []i64) Expr` | table_u32 declares a table of `u32`. |
| `fn (mut p Program) table_i32(name string, values []i64) Expr` | table_i32 declares a table of `i32`. |
| `fn (mut p Program) table_fix(name string, values []f64) Expr` | table_fix declares a table of `fix`. |
| `fn (mut p Program) record(name string, fields []Field) Record` | record declares a record type. Each field is aligned to its size and the record's size is rounded up to a power of two. |
| `fn (mut p Program) array_of(name string, r Record, len int) Expr` | array_of declares an array of `len` records, all fields 0. |
| `fn (mut p Program) func(name string, params []Param, ret Type) Func` | func declares a function. Its body is given later with `define`, so functions can call each other in any order. |
| `fn (mut p Program) define(f Func) &Code` | define starts the body of a function and returns the block to add its statements to. |

## Statements

`jaggame/lang_code.v`

| Declaration | |
|---|---|
| `type AsmFn = fn (mut m jagkit.M68k)` | AsmFn emits 68000 code in place of a statement: the escape hatch for the runtime. It may change d0..d6 and a0..a4. |
| `struct Code` | Code is the body of a function under construction. Blocks are opened by `if_`, `while_`, `for_` and `repeat` and closed by `end`. |
| `fn (mut c Code) set(dst Expr, value Val)` | set stores a value. The value converts to the destination's type by the widening rules; narrowing needs `as_`. |
| `fn (mut c Code) inc(dst Expr)` | inc adds 1 (1.0 for a `fix`). |
| `fn (mut c Code) dec(dst Expr)` | dec subtracts 1 (1.0 for a `fix`). |
| `fn (mut c Code) add_to(dst Expr, value Val)` | add_to adds a value to a destination. |
| `fn (mut c Code) sub_from(dst Expr, value Val)` | sub_from subtracts a value from a destination. |
| `fn (mut c Code) if_(cond Val)` | if_ opens a block that runs when the condition is true. |
| `fn (mut c Code) else_if(cond Val)` | else_if adds a branch to the innermost `if_`. |
| `fn (mut c Code) else_()` | else_ adds the branch that runs when no condition of the innermost `if_` was true. |
| `fn (mut c Code) while_(cond Val)` | while_ opens a loop that runs while the condition is true. |
| `fn (mut c Code) for_(v Expr, from Val, to Val)` | for_ opens a loop with `v` going from `from` up to `to - 1`. Like C's `for`, `to` is evaluated before every step. |
| `fn (mut c Code) repeat(count Val)` | repeat opens a loop that runs `count` times; the count is evaluated once, and a negative one runs no times. |
| `fn (mut c Code) end()` | end closes the innermost block. |
| `fn (mut c Code) break_()` | break_ leaves the innermost loop. |
| `fn (mut c Code) continue_()` | continue_ goes on with the next step of the innermost loop. |
| `fn (mut c Code) call(f Func, args ...Val)` | call calls a function as a statement; a result is thrown away. |
| `fn (mut c Code) ret(value Val)` | ret returns a value from the function. |
| `fn (mut c Code) ret_void()` | ret_void returns from a function that has no result. |
| `fn (mut c Code) asm(emit AsmFn)` | asm emits 68000 code in place of a statement. The interpreter cannot run it; games should not need it. |
| `fn (mut c Code) local(name string, t Type) Expr` | local declares a variable of the function. It is set to 0 each time the function is called. |
| `fn (mut c Code) local_bool(name string) Expr` | local_bool declares a `bool` local. |
| `fn (mut c Code) local_u8(name string) Expr` | local_u8 declares a `u8` local. |
| `fn (mut c Code) local_i8(name string) Expr` | local_i8 declares an `i8` local. |
| `fn (mut c Code) local_u16(name string) Expr` | local_u16 declares a `u16` local. |
| `fn (mut c Code) local_i16(name string) Expr` | local_i16 declares an `i16` local. |
| `fn (mut c Code) local_u32(name string) Expr` | local_u32 declares a `u32` local. |
| `fn (mut c Code) local_i32(name string) Expr` | local_i32 declares an `i32` local. |
| `fn (mut c Code) local_fix(name string) Expr` | local_fix declares a `fix` local. |

## Checking

`jaggame/lang_check.v`

| Declaration | |
|---|---|
| `fn (p &Program) check() !` | check applies every rule of the language to the program and reports all the problems it finds together. |

## Printing

`jaggame/lang_print.v`

| Declaration | |
|---|---|
| `fn (p &Program) show(e Expr) string` | show writes an expression as builder calls: `score.add(10)`. |
| `fn (p &Program) listing(f Func) string` | listing writes a function's body as the builder calls that made it. |

## The interpreter

`jaggame/interp.v`

| Declaration | |
|---|---|
| `struct Interpreter` | Interpreter runs a checked program. Its variables start with their initial values and keep them from one call to the next. |
| `fn (p &Program) interpreter() !&Interpreter` | interpreter checks the program and prepares to run it. |
| `fn (mut it Interpreter) run(name string, args ...i64) !i64` | run calls a function by name with raw argument values and returns its raw result (0 for a function that returns nothing). |
| `fn (it &Interpreter) value(name string) !i64` | value is the raw value of a global variable. |
| `fn (it &Interpreter) element(name string, index int) !i64` | element is the raw value of an element of a global array or table. |
| `fn (it &Interpreter) field(name string, index int, field string) !i64` | field is the raw value of a field of an element of an array of records. |

## The code generator

`jaggame/codegen.v`

| Declaration | |
|---|---|
| `fn (p &Program) emit(mut m jagkit.M68k) !` | emit compiles every defined function of the program into `m`, followed by the helper routines they use and the program's data. A function's code starts at a label with the function's name and a variable's storage at a label with its name; parameters and locals are `function.name`. A function is called with `jsr`; its parameters are stored at their labels first, and its result comes back in d0. It may change d0..d5 and a0..a4. |

## Plain images

`jaggame/image.v`

| Declaration | |
|---|---|
| `const load_address = u32(0x4000)` | load_address is where a plain image is loaded; the stack grows down from it. |
| `struct Image` | Image is a compiled program ready for the emulator, with its symbols and what is needed to read its variables back. |
| `fn (p &Program) plain_image(entry Func) !Image` | plain_image compiles a program into an image that calls `entry` once, sets the byte at `done` to 1 and then waits forever. It sets up nothing else: no video, no interrupts. It is what tests and plain computations run. |
| `fn (img &Image) differences(it &Interpreter, ram []u8) []string` | differences compares every variable, parameter and local of a program that has run in an interpreter with the same program run as this image, and lists those that differ. Both must have started from the beginning and done the same work. |
| `fn (img &Image) value(ram []u8, name string) !i64` | value is the raw value of a global variable, read from the machine's memory. |
| `fn (img &Image) element(ram []u8, name string, index int) !i64` | element is the raw value of an element of a global array or table. |
| `fn (img &Image) field(ram []u8, name string, index int, field string) !i64` | field is the raw value of a field of an element of an array of records. |

## Running images in the emulator (module jaggame.emulated)

`jaggame/emulated/emulated.v`

| Declaration | |
|---|---|
| `struct Runner` | Runner boots images, one after another, in one emulated machine. |
| `fn new() Runner` | new makes a runner with an NTSC machine. |
| `fn (mut r Runner) run(image []u8, done u32, max_frames int) !int` | run boots an image and runs frames until the byte at `done` is not 0. It returns the number of frames that took, or an error after `max_frames`. |
| `fn (r &Runner) ram() []u8` | ram is the machine's main memory. |
