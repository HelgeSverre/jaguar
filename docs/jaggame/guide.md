# Writing Jaguar games with jaggame

`jaggame` is a V module for writing Atari Jaguar programs without writing assembly. A program *describes* its variables and logic to a builder; the builder checks the description, compiles it to 68000 code and writes a `.jag` image. The same description also runs in an interpreter written in V, and the two must agree.

This guide grows with the module. Chapter 1, the language, is all that exists so far: there is no runtime yet (no video, sprites, pad or sound), so the programs here compute values that tests read back. [`design.md`](design.md) is the plan and the contract; [`reference.md`](reference.md) lists every public name with its comment.

Every V block in this guide is quoted from a test in [`jaggame/tests`](../../jaggame/tests), and every text block is output that a test produces: `jaggame/tests/guide_test.v` fails if one of them drifts.

## Contents

- [Chapter 1: the language](#chapter-1-the-language)
  - [A first program](#a-first-program)
  - [Running it twice](#running-it-twice)
  - [Types](#types)
  - [Expressions](#expressions)
  - [Variables, tables, arrays and records](#variables-tables-arrays-and-records)
  - [Statements](#statements)
  - [Functions](#functions)
  - [What the operations do](#what-the-operations-do)
  - [Mistakes are reported together](#mistakes-are-reported-together)
  - [Four complete programs](#four-complete-programs)
  - [How it is compiled](#how-it-is-compiled)
  - [How it is tested](#how-it-is-tested)
  - [V traps](#v-traps)

## Chapter 1: the language

### A first program

<!-- guide:first -->
```v
mut p := jaggame.new_program()
score := p.u16('score')
lives := p.u8('lives', 3)

bonus := p.func('bonus', [jaggame.Param{'level', .u16}], .u16)
mut c := p.define(bonus)
c.ret(bonus.arg('level').mul(100).add(50))

main := p.func('main', [], .void)
c = p.define(main)
level := c.local_u8('level')

c.for_(level, 1, 4)
c.add_to(score, bonus.call(level))
c.end()
c.dec(lives)
```

Read it as a program, not as V: `score` is a 16-bit variable of the Jaguar program, `bonus` a function of the Jaguar program, and `c.for_(level, 1, 4)` a loop that the 68000 will run. The V code runs once, at build time, and records what was asked for. Two consequences:

- **V is the macro language.** A V function that adds statements to a `Code` is a macro; a V `for` loop repeats statements in the program; a V value computed at build time (a sine table, a constant) goes into the program as data. The sine walk below builds its table with V's `math.sin`.
- **Nothing is checked until the program is built.** Writing `score.add(lives)` builds a description. The type rules are applied by `p.check()`, `p.interpreter()` or `p.plain_image(...)`, which report every problem together.

`p.define(f)` returns the `Code` that collects the body of `f`. Blocks are opened by `if_`, `while_`, `for_` and `repeat` and closed by `end()`. A function may be declared with `p.func` long before it is defined, so functions can call each other in any order.

### Running it twice

<!-- guide:run -->
```v
mut it := p.interpreter()!
it.run('main')!
assert it.value('score')! == 750
assert it.value('lives')! == 2

img := p.plain_image(main)!
mut runner := emulated.new()
runner.run(img.bytes, img.done, 60)!
assert img.value(runner.ram(), 'score')! == 750
assert img.differences(it, runner.ram()) == []
```

- `p.interpreter()` checks the program and returns an `Interpreter`. `run` calls a function by name. `value`, `element` and `field` read variables. Values are *raw*: a `fix` comes back as its 32-bit pattern (`jaggame.fix_value` turns it into a float, `jaggame.fix_raw` goes the other way).
- `p.plain_image(main)` compiles the program into an image that calls `main` once, sets a `done` byte and waits. It sets up nothing else. `img.bytes` is the `.jag` file; `os.write_file_array(path, img.bytes)` saves it.
- `jaggame.emulated` boots an image in the emulator and runs frames until `done` is set. It is a separate module so that a game build does not link the emulator.
- `img.differences(it, ram)` compares every variable, parameter and local of the two runs and lists the ones that differ.

`p.listing(main)` prints a function back as builder calls, which is how the fuzzer shows a failing case:

```text
// fn main()
level := c.local('level', .u8)
c.for_(level, 1, 4)
	c.set(score, score.add(bonus.call(level)))
c.end()
c.set(lives, lives.sub(1))
```

### Types

| Type | Size | Values |
|---|---|---|
| `bool` | 1 byte | 0 or 1 |
| `u8`, `i8` | 1 | 0..255, -128..127 |
| `u16`, `i16` | 2 | 0..65535, -32768..32767; the natural size on the 68000 |
| `u32`, `i32` | 4 | 0..4294967295, -2147483648..2147483647 |
| `fix` | 4 | signed 16.16 fixed point: -32768.0 up to just under 32768.0, in steps of 1/65536 |

The rules:

- **Both sides of an operation have the same signedness.** The narrower side widens to the wider: `u16` with `u8` is a `u16`. `u16` with `i16` is refused; convert one side with `as_`.
- **A `fix` with an integer converts the integer** (both signed and unsigned ones): `speed.mul(lives)` is `speed * 3.0`.
- **An integer literal takes the type of the other side and must fit it.** `x.add(300)` is refused when `x` is a `u8`. A float literal is a `fix`, so `x.add(1.5)` is a `fix` even when `x` is an integer. Literals larger than an `int` need `i64(...)`: `x.and(i64(0xffff_0000))`.
- **Comparisons and `both`/`either` yield `bool`.** Arithmetic on a `bool` is refused; so is a number used as a condition.
- **`set` widens but does not narrow:** a `u8` can be stored in a `u32` or a `fix`, a `u32` in a `u8` only with `as_(.u8)`.

### Expressions

<!-- guide:expressions -->
```v
mut p := jaggame.new_program()
score := p.u16('score')
lives := p.u8('lives', 3)
speed := p.fix('speed', 1.5)
bag := p.array_u8('bag', 16)
sines := p.table_i16('sines', [0, 3212, 6393, 9512])

a := score.add(10) // u16
b := score.lt(lives) // bool: the u8 widens to u16
d := speed.mul(lives) // fix: lives becomes 3.0
e := bag.at(3).add(1) // u8: 255 + 1 wraps to 0
f := sines.at(score.and(3)).as_(.i32).mul(2) // i32
g := score + lives.as_(.u16) // operators work between two Exprs
```

A variable, an element and an operation are all `jaggame.Expr`, so a variable can be used wherever a value can. The methods take a `jaggame.Val`: an `Expr`, an `int`, an `i64`, an `f64` or a `bool`.

| Methods | |
|---|---|
| `add sub mul div mod` | arithmetic; `mul` and `div` of `fix` keep 16.16 |
| `and or_ xor not shl shr` | bits of integers (`or` is a V keyword); `shl`/`shr` also shift a `fix` |
| `eq ne lt le gt ge` | comparisons |
| `both either invert` | `bool` logic; `both` and `either` do not evaluate their right side when the left decides |
| `neg abs` | signed types and `fix` |
| `min max` | |
| `as_(.type)` | conversion |
| `at(index)`, `field(name)` | an element, a field of a record element |
| `+ - * / %` | the same as `add sub mul div mod`, between two `Expr` values |

V lets a struct overload `<` and `==` only with a V `bool` result, so comparisons have no operators. A literal on its own has no type: `jaggame.lit(5).as_(.u8)` is a `u8` constant.

### Variables, tables, arrays and records

| Declaration | |
|---|---|
| `p.u8('name')`, `p.i16('name', -1)`, `p.fix('speed', 1.5)`, `p.bool('flag', true)` … | a global, 0 unless given a value; `p.global(name, type, value)` is the general form |
| `p.table_i16('sines', values)`, `p.table_fix(name, []f64)`, `p.table(name, type, []Val)` | read-only data |
| `p.array_u8('bag', 16)`, `p.array(name, type, length)` | read-write, all 0 |
| `p.record('Guard', fields)`, `p.array_of('guards', guard, 8)` | records, all fields 0 |
| `c.local_u16('i')`, `c.local(name, type)` | a local of the function being defined |

A record's fields are laid out in order, each aligned to its size, and the record's size is rounded up to a power of two so that indexing is a shift: `u8, u32, i16, bool` puts the fields at 0, 4, 8 and 10 in a 16-byte record. `guards.at(i).field('x')` is a field; `guards.at(i)` on its own is not a value.

An index is any integer expression. A literal index is checked at build time; an index computed at run time is not checked by the compiled code. The interpreter does check it and stops with an error, so a test in the interpreter finds an index out of range.

### Statements

<!-- guide:statements -->
```v
mut p := jaggame.new_program()
x := p.i16('x')
alert := p.bool('alert')
steps := p.u16('steps')
walk := p.func('walk', [jaggame.Param{'far', .i16}], .void)
mut c := p.define(walk)
i := c.local_u8('i')

c.if_(walk.arg('far').gt(100))
c.set(alert, true)
c.else_if(walk.arg('far').gt(50))
c.inc(steps)
c.else_()
c.ret_void()
c.end()

c.for_(i, 0, 8) // i is 0..7
c.if_(x.ge(walk.arg('far')))
c.break_()
c.end()
c.add_to(x, 10)
c.end()

c.while_(x.gt(0).both(alert))
c.sub_from(x, 3)
c.end()

c.repeat(3)
c.inc(steps)
c.end()
```

`v fmt` keeps the statements flat; the blocks are in the calls, not in the indentation.

| Statement | Meaning |
|---|---|
| `set(dst, value)` | store; `dst` is a variable, an element or a field |
| `inc(dst)`, `dec(dst)`, `add_to(dst, v)`, `sub_from(dst, v)` | `set(dst, dst.add(1))` and so on; for a `fix`, 1 is 1.0 |
| `if_(cond)`, `else_if(cond)`, `else_()`, `end()` | |
| `while_(cond)` … `end()` | |
| `for_(v, from, to)` … `end()` | `v` from `from` while `v < to`, adding 1; like C, `to` is evaluated before every step |
| `repeat(n)` … `end()` | `n` times; `n` is evaluated once, and a negative `n` runs no times |
| `break_()`, `continue_()` | leave the innermost loop, or go on with its next step (in a `for_`, the increment) |
| `call(f, args…)` | a call as a statement; a result is thrown away |
| `ret(value)`, `ret_void()` | |
| `asm(fn (mut m jagkit.M68k) { … })` | 68000 code in place of a statement, for the runtime; the interpreter cannot run it |

### Functions

<!-- guide:records -->
```v
clamp := p.func('clamp', [jaggame.Param{'v', .fix}, jaggame.Param{'lo', .fix},
	jaggame.Param{'hi', .fix}], .fix)
mut c := p.define(clamp)
c.ret(clamp.arg('v').max(clamp.arg('lo')).min(clamp.arg('hi')))
```

`clamp.arg('v')` is a parameter as an expression; `clamp.call(x, 0, 100)` is a call. Arguments convert to the parameters' types by the rules of `set`.

- **Parameters, locals and the result have fixed addresses**, not a stack frame: fast on a 68000, and the reason a function cannot call itself, directly or through others. The checker follows the call graph and refuses recursion.
- **Locals are set to 0 every time the function is called.**
- **A function that returns a value must not be able to reach its end**: the last statement must be a `ret`, or an `if_` with an `else_` whose every branch ends that way.
- **The arguments of a call are all evaluated before any is stored**, so `f.call(x, f.call(y, z))` works.

### What the operations do

The interpreter defines what every operation means, and the compiled code must do the same. These cases are worked out by hand and run both ways in `jaggame/tests/semantics_test.v`:

<!-- guide:semantics -->
```v
cases := [
	Case{'u8 wraps', .u8, u8_200.add(100), 44},
	Case{'u16 wraps below 0', .u16, u16_zero.sub(1), 65535},
	Case{'i16 wraps', .i16, i16_max.add(1), -32768},
	Case{'division rounds toward zero', .i8, i8_m7.div(2), -3},
	Case{'remainder has the sign of the dividend', .i8, i8_m7.mod(2), -1},
	Case{'-128 / -1 wraps', .i8, i8_min.div(-1), -128},
	Case{'smallest i32 / -1 wraps', .i32, i32_min.div(i32_m1), -2147483648},
	Case{'division by zero is 0', .u32, u32_five.div(0), 0},
	Case{'remainder by zero is 0', .i32, i32_m5.mod(0), 0},
	Case{'fix division by zero is 0', .fix, one.div(0), 0},
	Case{'unsigned division', .u32, u32_max.div(2), 0x7fff_ffff},
	Case{'shr fills unsigned with 0', .u8, u8_0x81.shr(1), 0x40},
	Case{'shr keeps the sign', .i8, i8_min.shr(1), -64},
	Case{'shl into the sign bit', .i8, i8_one.shl(7), -128},
	Case{'shl out of the type', .u8, u8_one.shl(8), 0},
	Case{'a shift count is masked to 5 bits', .u32, u32_five.shl(u32_33), 10},
	Case{'shr of -1', .i32, i32_m1.shr(31), -1},
	Case{'fix product', .fix, speed.mul(2.25), jaggame.fix_raw(3.375)},
	Case{'fix product rounds down', .fix, tiny.mul(half), 0},
	Case{'a negative one too', .fix, tiny.neg().mul(half), -1},
	Case{'fix quotient rounds toward zero', .fix, one.div(three), 21845},
	Case{'a negative one too', .fix, one.neg().div(three), -21845},
	Case{'fix remainder', .fix, f_m75.mod(2), jaggame.fix_raw(-1.5)},
	Case{'fix with an integer', .fix, speed.add(u8_two), jaggame.fix_raw(3.5)},
	Case{'fix to integer rounds down', .i16, half.neg().as_(.i16), -1},
	Case{'fix to u8', .u8, speed.add(1.25).as_(.u8), 2},
	Case{'narrowing cuts', .u8, i16_300.as_(.u8), 44},
	Case{'i8 to u16', .u16, i8_m1.as_(.u16), 65535},
	Case{'u8 to i8', .i8, u8_255.as_(.i8), -1},
	Case{'integer to fix wraps', .fix, u16_40000.as_(.fix), -1673527296},
	Case{'bool to fix', .fix, t.as_(.fix), jaggame.fix_one},
	Case{'to bool compares with 0', .bool, half.as_(.bool), 1},
	Case{'abs of the smallest', .i16, i16_min.abs(), -32768},
	Case{'neg of the smallest', .i8, i8_min.neg(), -128},
	Case{'unsigned max', .u16, u16_max.max(1), 0xffff},
	Case{'signed min', .i16, i16_m1.min(1), -1},
	Case{'unsigned compare', .bool, u32_top.gt(1), 1},
	Case{'signed compare', .bool, i32_m1.lt(1), 1},
	Case{'either skips its right side', .bool, t.either(bump.call()), 1},
	Case{'both skips its right side', .bool, t.invert().both(bump.call()), 0},
	Case{'both runs its right side', .bool, t.both(bump.call()), 1},
]
```

In words:

- **Arithmetic wraps** at the type's width, as the 68000 does.
- **Division rounds toward zero**, and the remainder has the sign of the dividend, as in C and V. **Dividing by zero gives 0**, and so does the remainder.
- **A shift count is 0..31.** A literal outside that is refused; a computed count is masked to five bits. `shr` is arithmetic for signed types and `fix`, logical for unsigned ones.
- **`fix * fix` rounds down** (toward minus infinity): it is the signed 64-bit product shifted right 16 bits, cut to 32. **`fix / fix` rounds toward zero.** `fix % fix` is the remainder of the raw values, which is the remainder in 16.16.
- **Conversions:** integers are cut or extended; an integer becomes a `fix` by shifting it 16 bits left, wrapping; a `fix` becomes an integer by rounding down (-0.5 becomes -1); anything becomes a `bool` by comparing with 0; a `bool` is 0 or 1 (1.0 as a `fix`).
- **Order of evaluation:** left side before right side, arguments left to right, and in `set` the destination's index before the value. It matters only when a function called in an expression changes a variable used in the same statement.

### Mistakes are reported together

<!-- guide:mistakes -->
```v
mut p := jaggame.new_program()
speed := p.fix('speed', 1.5)
x := p.i16('x')
hits := p.u8('hits')
update := p.func('update', [], .void)
mut c := p.define(update)
c.set(x, x.add(speed))

c.if_(hits)
c.set(hits, hits.add(x))
c.end()
c.set(x, 40000)
p.check() or { return err.msg() }
```

```text
jaggame program:
  function `update`: set(x, x.add(speed)): `x.add(speed)`: a fix cannot be stored in an i16; convert it with as_(.i16), which rounds down
  function `update`: if_(hits): a condition must be a bool, not u8; compare it, e.g. `hits.ne(0)`
  function `update`: set(hits, hits.add(x)): add mixes u8 and i16: one is signed and the other is not; convert one side with as_
  function `update`: set(x, 40000): 40000 does not fit i16 (-32768..32767)
```

Each problem names the function and the statement, written back as builder calls. Declarations are checked too (a name used twice, an initial value that does not fit, a table value out of range), as are blocks left open, `break_` outside a loop, calls with the wrong arguments, a function that is called but never defined, and recursion. `jaggame/check_test.v` tries every rule both ways.

### Four complete programs

Each is in `jaggame/tests/programs_test.v`, run by the interpreter and on the emulated 68000, compared variable by variable, and checked against the same computation written in plain V.

**An insertion sort.** `both` is what keeps `data.at(j.sub(1))` from being read when `j` is 0: the interpreter would stop on the index 65535.

<!-- guide:sort -->
```v
mut p := jaggame.new_program()
input := p.table_i16('input', values)
data := p.array_i16('data', 32)
sort := p.func('sort', [], .void)
mut c := p.define(sort)
i := c.local_u16('i')
j := c.local_u16('j')
key := c.local_i16('key')

c.for_(i, 0, 32)
c.set(data.at(i), input.at(i))
c.end()

c.for_(i, 1, 32)
c.set(key, data.at(i))
c.set(j, i)

// both() does not look at data.at(j - 1) once j is 0.
c.while_(j.gt(0).both(data.at(j.sub(1)).gt(key)))
c.set(data.at(j), data.at(j.sub(1)))
c.dec(j)
c.end()
c.set(data.at(j), key)
c.end() // for each element
```

**The primes below 2000**, by sieving:

<!-- guide:primes -->
```v
mut p := jaggame.new_program()
composite := p.array('composite', .bool, limit)
primes := p.array_u16('primes', 400)
count := p.u16('count')
sieve := p.func('sieve', [], .void)
mut c := p.define(sieve)
n := c.local_u16('n')
multiple := c.local_u32('multiple')

c.for_(n, 2, limit)
c.if_(composite.at(n).invert())
c.set(primes.at(count), n)
c.inc(count)
// n * n would wrap as a u16: square it as a u32.
c.set(multiple, n)
c.set(multiple, multiple.mul(n))

c.while_(multiple.lt(limit))
c.set(composite.at(multiple), true)
c.add_to(multiple, n)
c.end() // for each multiple of n
c.end() // if n is prime
c.end() // for each n
```

**A walk along a sine table.** The table is computed in V at build time. The angle is a `u16` whose high byte indexes the table, so adding to it wraps around the circle for free.

<!-- guide:sine -->
```v
mut p := jaggame.new_program()
sines := p.table_fix('sines', sine_table())
path := p.array_fix('path', 64)
angle := p.u16('angle') // 256 steps to a turn in the high byte
x := p.fix('x')
speed := p.fix('speed', 2.5)
walk := p.func('walk', [], .void)
mut c := p.define(walk)
step := c.local_u8('step')

c.for_(step, 0, 64)
c.add_to(angle, 1000) // wraps around at 65536
c.add_to(x, sines.at(angle.shr(8)).mul(speed))
c.set(path.at(step), x)
c.end()
```

**Records, and functions that call functions.** Eight guards walk back and forth for 150 steps; then `find` asks `distance` about each of them.

<!-- guide:records -->
```v
// step moves guard i right until x is 100, then left until it is 0.
step := p.func('step', [jaggame.Param{'i', .u8}], .void)
c = p.define(step)
g := guards.at(step.arg('i'))

c.if_(g.field('state').eq(0))
c.set(g.field('x'), clamp.call(g.field('x').add(1.5), 0, 100))

c.if_(g.field('x').eq(100))
c.set(g.field('state'), 1)
c.end()
c.else_()
c.set(g.field('x'), clamp.call(g.field('x').sub(0.75), 0, 100))

c.if_(g.field('x').eq(0))
c.set(g.field('state'), 0)
c.end()
c.end() // moving right or left
c.inc(g.field('timer'))
```

`g` is a V variable holding an expression, used six times: V is the macro language. `find` and `main` are in the test.

### How it is compiled

The checker turns the program into a typed form (every literal typed, every widening explicit, `for_`, `repeat`, `inc` and the like reduced to `set` and one kind of loop). The interpreter and the code generator both work from that form, which is why they agree on what a program means.

The code generator is meant to be obviously right, not fast:

- **Every expression leaves its value in `d0` as a whole long**, sign- or zero-extended from its type. Operations work on longs and cut the result back to the type, which is exactly how the interpreter wraps.
- **The left operand of an operation waits on the stack** while the right one is evaluated. There is no register allocation and no optimisation.
- **Nothing lives in a register from one statement to the next.** Globals, parameters and locals have fixed addresses in a data area after the code: longs, then words, then bytes, then arrays, tables and records.
- **Helper routines** do what the 68000 has no instruction for: `jaggame.mul32` (a 32 × 32 product from three `mulu`), `jaggame.divu32` and `jaggame.divs32` (shift-and-subtract division with the remainder), `jaggame.fix_mul` (bits 16..47 of the signed 64-bit product, from four `mulu`) and `jaggame.fix_div` (a 64 by 32 bit division). Each is emitted only when used. Narrow multiplications use `mulu` directly.
- **Registers:** compiled code uses `d0`..`d5` and `a0`; `a5`, `a6` and `d7` are never touched, for the runtime. `jaggame/registers_test.v` sets them in an `asm` statement, runs code that uses every helper, and checks them.

`p.emit(mut m)` compiles a program into a `jagkit.M68k` that may hold other code; `plain_image` is built on it. The labels are the names: function `bonus` starts at the label `bonus`, global `score` is at `score`, a parameter or local is `bonus.level`. To call a compiled function from assembly, store the arguments at the parameters' labels and `jsr` to it; the result comes back in `d0`, and `d0`..`d5`, `a0`..`a4` may have changed.

### How it is tested

| Test | What it proves |
|---|---|
| `jaggame/check_test.v` | every rule of the language accepts and refuses what it should, with a message that names the problem |
| `jaggame/fuzz_test.v` | 20,800 random well-typed cases agree between the interpreter and the 68000 |
| `jaggame/tests/semantics_test.v` | the table above, worked out by hand, on both sides |
| `jaggame/tests/programs_test.v` | the four programs, on both sides and against plain V |
| `jaggame/registers_test.v` | compiled code leaves `a5`, `a6` and `d7` alone |
| `jaggame/tests/guide_test.v` | this guide quotes only tested code |

The fuzzer builds 40 programs from a fixed seed. Each has globals holding the edge values of every type (0, ±1, the smallest and largest, and their neighbours), a few helper functions with parameters, and 520 cases: half are a function returning one random expression, half a function with locals, an array and records of its own and a random run of statements, loops, early returns and calls. Every variable is compared after the run, and a coverage check proves that every operation, conversion, load and store of every type was generated. In about five seconds it runs every case and some 3,000 divisions by zero.

When the two sides disagree, the test prints the first case, in the order the program runs them, whose variables differ, written back as builder calls with the values on both sides. The seed is fixed, so the failure reproduces; copy the case into a test of its own when you fix it.

### V traps

Found with V 0.5.2 while writing this slice, in addition to [the ones in the jagkit guide](../jagkit.md#v-traps):

| Trap | Workaround |
|---|---|
| With `-prod`, before every call statement V copies the pointers of each value-typed local and parameter in scope that holds pointers, walking it deeply, so that the garbage collector keeps them. A recursive walk over a tree held by value becomes quadratic | in hot code, hold trees and arrays of structs by reference (`&TExpr`, `&[]TStmt`), and keep large values such as the interpreter on the heap. This made the interpreter 6.5 times faster |
| `<` and `==` can only be overloaded with a V `bool` result | comparisons are methods only |
| `or` is a keyword | the method is `or_`, like `if_` and `for_` |
| `for s in list` where `list` is a `&[]T` gives `&T` elements, and `&list[i]` is refused outside `unsafe` | loop with `for s in list` and pass `s` on as it is |
| `-0x8000_0000` is positive: the literal is an `int` before it is negated | write `-i64(0x8000_0000)` |
| An `int` is 32 bits, so `0xffff_ffff` does not fit an `int` parameter | `Val` accepts `i64` too; `p.u32` and `table_u32` take `i64` |
