# jaggame: design

`jaggame` is a V module on top of `jagkit` for writing Jaguar games without writing assembly. A game is a V program that *describes* itself (variables, logic, sprites, maps, scenes, sound) to a builder; the builder compiles the logic to 68000 code, links it with a fixed runtime and writes a `.jag`.

This document is the contract the implementation slices work from. When V 0.5.2 or the hardware forces a deviation, change this document in the same commit and say why.

## Goals

- Game code never names a register or an instruction.
- Everything is checked at build time: types, sizes, memory layout, assets.
- Compiled, not interpreted: logic becomes 68000 code.
- Testable twice: the same logic runs in a V interpreter (fast, no emulator) and compiled in the emulator, and the two must agree.
- One real game, GHOSTGRID, uses every feature. A feature the demo does not use does not ship.
- Documentation lands with each slice: `docs/jaggame/guide.md` (chapters), and reference generated from source comments like `docs/jagkit-reference.md`.

Out of scope: compiling ordinary V source; 3D.

## Layers

| Layer | Directory | What it is |
|---|---|---|
| Language | `jaggame/lang_*.v` | typed variables, expressions, statements, functions, state machines; IR; type checker |
| Interpreter | `jaggame/interp.v` | evaluates the IR in V; the reference semantics |
| Code generator | `jaggame/codegen_*.v` | IR to 68000 through `jagkit.M68k`; helper routines (32-bit multiply, divide, fixed point) |
| Runtime | `jaggame/rt_*.v` | frame loop, NTSC/PAL, display list, sprites, tilemap, camera, pad, text, sound, save data, GPU effects |
| Assets | `jaggame/assets_*.v` | PNG import, palettes, tile sets, maps, fonts |
| Game | `demos/ghostgrid/` | the demo |

The runtime may be written with `jagkit` directly or in the language itself, whichever is clearer per routine.

## The language

### Types

| Type | Size | Notes |
|---|---|---|
| `u8`, `i8` | 1 byte | |
| `u16`, `i16` | 2 | the natural size on the 68000 |
| `u32`, `i32` | 4 | |
| `fix` | 4 | signed 16.16 fixed point |
| `bool` | 1 | 0 or 1 |

Rules:

- A binary operation needs both sides of the same signedness; the narrower side widens to the wider. Mixing signed and unsigned is a build error; `.as_(type)` converts explicitly.
- An integer literal takes the type of the other side and must fit it. A float literal is a `fix`.
- `fix` with an integer: the integer is converted. `fix * fix` and `fix / fix` keep 16.16.
- Arithmetic wraps at the type's width. Division by zero yields 0 (defined, the same in the interpreter and on the machine).
- Comparisons and logic yield `bool`. `and`/`or` short-circuit.
- Shifts take a count of 0..31; a larger count is a build error for literals and is masked to 5 bits for values.

### Values and expressions

A variable handle and an expression are the same V type, `Expr`, so a variable can be used wherever a value can. Builder methods take `Val = Expr | int | f64 | bool`, so literals need no wrapping.

```v
mut p := jaggame.new_program()
score := p.u16('score')              // a global, initial value 0
lives := p.u8('lives', 3)
speed := p.fix('speed', 1.5)
sines := p.table_i16('sines', values)   // read-only data
bag   := p.array_u8('bag', 16)          // read-write array

score.add(10)            // an expression: score + 10
score.lt(lives)          // build error: u16 against u8 is fine (widens); u16 against i16 is not
bag.at(3)                // an element; usable as a value and as a destination
sines.at(angle.and(255))
```

Expression methods: `add sub mul div mod neg`, `and or xor not shl shr`, `eq ne lt le gt ge`, `both(…)`/`either(…)` (short-circuit logic), `invert()` (boolean not), `as_(type)`, `min max abs`, `at(index)`, `field(name)`. Where V 0.5.2 allows operator overloading between two `Expr` values (`+ - * / % < ==`), provide it as well.

### Records and arrays of records

```v
guard := p.record('Guard', [
	jaggame.Field{'x', .fix}, jaggame.Field{'y', .fix},
	jaggame.Field{'state', .u8}, jaggame.Field{'timer', .u16},
])
guards := p.array_of('guards', guard, 8)
g := guards.at(i)        // i is an expression
g.field('x')             // value and destination
```

Layout is array-of-structures with fields aligned to their size; the record size is rounded up to a power of two so indexing is a shift.

### Statements

Statements are added to a `Code` block. Blocks are opened and closed explicitly; an unbalanced block is a build error naming the function. Closure sugar (`c.when(cond, fn …)`) may be added on top where it reads better, but the explicit form is the primitive because V closures need capture lists.

```v
fn (mut game Ghostgrid) move_player(mut c jaggame.Code) {
	c.if_(game.pad.held(.left))
	c.set(game.px, game.px.sub(game.speed))
	c.else_()
	c.inc(game.idle)
	c.end()

	i := c.local_u16('i')
	c.for_(i, 0, 8)                  // i from 0 to 7
	c.if_(guards.at(i).field('state').eq(alert))
	c.break_()
	c.end()
	c.end()
}
```

| Statement | Meaning |
|---|---|
| `set(dst, value)` | assignment; `value` converts to `dst`'s type by the widening rules, narrowing needs `as_` |
| `inc(dst)`, `dec(dst)`, `add_to(dst, v)`, `sub_from(dst, v)` | shorthand |
| `if_(cond)`, `else_if(cond)`, `else_()`, `end()` | |
| `while_(cond)`, `for_(var, from, to)`, `repeat(n)`, `break_()`, `continue_()`, `end()` | |
| `call(func, args…)` | a call as a statement |
| `ret(value)` / `ret_void()` | |
| `local_<type>(name)` | a local variable |
| `asm(fn (mut m jagkit.M68k))` | escape hatch for the runtime; games should not need it |

### Functions

```v
clamp := p.func('clamp', [jaggame.Param{'v', .i16}, jaggame.Param{'hi', .i16}], .i16)
// clamp.arg('v') is an Expr; clamp.body is a Code
p.define(clamp, fn [clamp] (mut c jaggame.Code) { … })
value := clamp.call(x, 100)      // an Expr
```

- Parameters, locals and the result live at fixed addresses (no stack frames): fast on a 68000, and a recursive call is a build error (the call graph is checked).
- A function may be declared before it is defined; an undefined function that is called is a build error.

### State machines

First-class, because guards, scenes and missions are all state machines.

```v
m := p.machine('guard_ai', guards)            // one state variable per record, or a single global one
m.state('patrol', fn (mut c jaggame.Code, self jaggame.Expr) { … c.go('suspicious') … })
m.state('suspicious', …)
m.on_enter('alert', …)
m.run(c, guards.at(i))                        // dispatch through a jump table
```

`go` to an unknown state is a build error. Each state has an implicit `time_in_state` counter (frames).

## Code generation

Correctness first, speed second.

- Globals, locals, parameters: static addresses in a data area after the code, laid out by size (longs, words, bytes), longs and words even-aligned.
- Expressions: a simple scheme, for example evaluate into `d0` with temporaries pushed on the stack, or a small register stack `d0..d5` that spills. No optimiser beyond constant folding and using quick/immediate forms.
- Registers `a5`/`a6`/`d7` are reserved for the runtime; everything else is free inside a statement and nothing lives in a register across statements.
- Helper routines emitted only when used: 32×32 multiply, 32/32 divide and modulo (signed and unsigned), fixed-point multiply and divide.
- Every accepted program must assemble without `jagkit` reporting a problem; a jagkit problem is a compiler bug.

## Testing strategy

| Level | What it proves |
|---|---|
| Type checker unit tests | every rule above accepts and refuses what it should, with a useful message |
| Differential fuzzing | random well-typed expression trees and statement sequences: interpreter result == compiled result on the emulated 68000, for every type, including edge values (0, ±1, min, max) |
| Program tests | small complete programs (sort, primes, fixed-point sine walk, a state machine) checked both ways |
| Runtime tests | boot in the emulator, drive the pad, read variables by name (as the existing demos do), NTSC and PAL |
| Game tests | a robot completes missions; an idle player is caught; saves survive a restart |
| Second emulator | `just crosscheck` on every image |

The harness for differential tests: compile to an image whose entry runs the code and then sets a `done` flag; run the machine until the flag; read result variables through the symbol table. Reuse one machine across many cases where possible, the emulator boot is the slow part.

## Runtime (slices 2 to 5)

- **Loop:** `init`, then once a frame in the vertical interrupt: read pad, run the scene's `update`, build the display list, sound tick. A missed frame is counted in a variable tests can read.
- **Video:** NTSC and PAL profiles chosen at start-up; a logical 320×240 screen centred in the display window. A `frames_per_second` constant and frame-rate-independent timers (`seconds(1.5)` compiles to the right frame count for either standard, chosen at run time).
- **Sprites:** up to N live objects with x, y, frame, visible, flip, scale, layer; the runtime builds the display list from them every frame, sorted by layer. Animation: named sequences with per-frame durations.
- **Tilemap and camera:** tile sets and maps from assets; rooms larger than the screen; camera follows a target with clamping. Approach to decide in slice 3 and verify in both emulators (a pre-rendered room bitmap scrolled by the object's data pointer and position is the expected one).
- **Collision:** tile flags (solid, hides, exit, item) queried by position; box against box between sprites; a `move_and_slide(x, y, dx, dy, box)` helper.
- **Line of sight and cones:** `can_see(from, facing, to, range, half_angle)` stepping through tiles; sine and arctangent tables.
- **Text:** fixed font, `print`, numbers, a HUD layer; briefings with word wrap done at build time.
- **Sound:** effects by name with priority; a pattern sequencer for music with at least four voices and the ability to switch pattern sets on a game event (calm, alert). Tempo independent of the television standard.
- **Scenes:** named scenes with `enter`, `update`, `leave`; `go_scene`; transitions (fade through the colour table).
- **Save data:** a small key-value block with a checksum. Investigate what storage a `.jag` loaded this way has in the emulator and on hardware (cartridge EEPROM), implement what is real, and say plainly what is not.
- **GPU effects:** pluggable background modules with a parameter block (the existing plasma is the model): an animated grid backdrop and a full-screen pulse.
- **Assets:** PNG to 16-bit CRY or to a palette and 8-bit indices, sprite sheets cut by grid, tile sets, maps from text. All checked at build time (phrase widths, palette sizes, missing files).

## The demo: GHOSTGRID

An original top-down stealth trainer. Simulated training rooms: glowing grid floors, block walls, simple geometric figures. No characters, names, levels, music or visual design from any existing game.

- **Player:** walk, run (louder, guards hear it), press against cover, knock on a wall to draw a guard.
- **Guards:** patrol routes; a visible vision cone blocked by walls; states patrol → suspicious → alert → search → return. Cameras that sweep.
- **Missions:** about ten, of four kinds: reach the exit, collect every chip, never be seen, beat the clock. A rank per mission from time and times seen.
- **Scenes:** title, mission select (with best rank and time), briefing, play, pause, results.
- **Uses:** every runtime feature above.

## Slices and gates

Each slice ends with the suite green, a guide chapter, and commits on `main` (never pushed by an agent).

| # | Slice | Gate |
|---|---|---|
| 1 | Language core: types, expressions, statements, functions, tables, arrays, records; interpreter; code generator; helpers | `v -prod test jaggame/` passes, including differential fuzzing of at least 20,000 random cases across all types, and four program tests |
| 2 | Runtime core: loop, video profiles, sprites, pad, text, timers; `demos/hello2` (hello rewritten with no assembly) | its test passes on NTSC and PAL; runs in the second emulator |
| 3 | Assets, tilemap, camera, collision; a player walking a scrolling room | robot walks a route, cannot pass walls, camera clamps |
| 4 | State machines, arrays of actors, line of sight; one complete mission with guards | robot completes it unseen; idle-in-view player is caught |
| 5 | Scenes, sound and music, save data, GPU backdrop | menu flow test; music switches on alert; save survives restart |
| 6 | GHOSTGRID complete: all missions, ranks, PAL, cross-check, final docs | every mission completed by a robot; full suite green |
