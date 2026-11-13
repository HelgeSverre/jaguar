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
| Code generator | `jaggame/codegen*.v`, `jaggame/image.v` | IR to 68000 through `jagkit.M68k`; helper routines (32-bit multiply, divide, fixed point); a plain image for tests |
| Test harness | `jaggame/emulated/` | boots an image in the emulator for tests; a separate module so that a game build does not link the emulator, and free of `jaggame` so that `jaggame`'s own tests can import it |
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
- An integer literal takes the type of the other side and must fit it. A float literal is a `fix`, so an integer side next to one converts to `fix`.
- `fix` with an integer: the integer is converted. `fix * fix` and `fix / fix` keep 16.16.
- Arithmetic wraps at the type's width. Division by zero yields 0 (defined, the same in the interpreter and on the machine).
- Comparisons and logic yield `bool`. `both`/`either` short-circuit.
- Shifts take a count of 0..31; a larger count is a build error for literals and is masked to 5 bits for values.

Decided in slice 1, where the rules above left a choice (the interpreter defines them; `jaggame/tests/semantics_test.v` checks each one by hand on both sides):

- Division rounds toward zero; the remainder has the sign of the dividend (as in C and V); a remainder by zero is 0 too.
- `fix * fix` rounds toward minus infinity (the 64-bit product shifted right 16); `fix / fix` rounds toward zero; `fix % fix` is the remainder of the raw values.
- `as_`: integers are cut or extended; integer to `fix` shifts left 16 and wraps; `fix` to integer rounds down (-0.5 becomes -1), because that is one `swap` on the 68000; anything to `bool` compares with 0.
- `shr` is arithmetic for signed types and `fix`, logical for unsigned ones. The count may be of any integer type; its signedness does not have to match.
- `and`, `or_`, `xor`, `not` take integers only (not `fix`, not `bool`); `neg` and `abs` take signed types and `fix`; arithmetic and ordering refuse `bool`.
- Evaluation is left to right; in `set`, the destination's index is evaluated before the value.
- `set` widens within one signedness and from any integer to `fix`, and nothing else.

### Values and expressions

A variable handle and an expression are the same V type, `Expr`, so a variable can be used wherever a value can. Builder methods take `Val = Expr | int | i64 | f64 | bool`, so literals need no wrapping. (`i64` because a V `int` is 32 bits and cannot hold `0xffff_ffff`; for the same reason `p.u32`, `p.i32`, `table_u32` and `table_i32` take `i64`.)

```v
mut p := jaggame.new_program()
score := p.u16('score')              // a global, initial value 0
lives := p.u8('lives', 3)
speed := p.fix('speed', 1.5)
sines := p.table_i16('sines', values)   // read-only data
bag   := p.array_u8('bag', 16)          // read-write array

score.add(10)            // an expression: score + 10
score.lt(lives)          // a bool: u16 against u8 is fine (widens); u16 against i16 is a build error
bag.at(3)                // an element; usable as a value and as a destination
sines.at(angle.and(255))
```

Expression methods: `add sub mul div mod neg`, `and or_ xor not shl shr`, `eq ne lt le gt ge`, `both(…)`/`either(…)` (short-circuit logic), `invert()` (boolean not), `as_(type)`, `min max abs`, `at(index)`, `field(name)`. `or` is a V keyword, hence `or_`. The operators `+ - * / %` work between two `Expr` values; `<` and `==` do not, because V 0.5.2 only lets them be overloaded with a V `bool` result. A bare literal has no type until it meets one: `jaggame.lit(5).as_(.u8)` is a typed constant.

An index computed at run time is not checked by the compiled code (a literal one is checked at build time). The interpreter checks every index and stops with an error, so a test run in the interpreter finds one out of range.

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
| `local_<type>(name)` | a local variable, set to 0 each time the function is called |
| `asm(fn (mut m jagkit.M68k))` | escape hatch for the runtime; games should not need it; the interpreter cannot run it |

`for_(v, from, to)` evaluates `to` before every step, as C does; `repeat(n)` evaluates `n` once into a hidden counter, and a negative `n` runs no times. `break_`/`continue_` outside a loop and `else_`/`else_if` without an `if_` are build errors, reported with the unbalanced blocks.

### Functions

```v
clamp := p.func('clamp', [jaggame.Param{'v', .i16}, jaggame.Param{'hi', .i16}], .i16)
// clamp.arg('v') is an Expr
mut c := p.define(clamp)         // the Code of the body
c.ret(clamp.arg('v').min(clamp.arg('hi')))
value := clamp.call(x, 100)      // an Expr
```

- Parameters and locals live at fixed addresses (no stack frames): fast on a 68000, and a recursive call is a build error (the call graph is checked).
- The result comes back in `d0`, not at a fixed address: the caller uses it at once, and a fixed result slot would only add a store and a load.
- A function may be declared before it is defined; an undefined function that is called is a build error.
- A function with a result must not be able to reach its end: its last statement is a `ret`, or an `if_` with an `else_` whose every branch ends that way.
- Arguments are all evaluated onto the stack before any is stored in a parameter, so an argument may call the same function.

Changed in slice 1: `p.define(f)` returns the `Code` instead of taking a closure. V closures must list what they capture (`fn [clamp, score, lives] (…)`), which grows with every function; the explicit form is the one the statements already use, and a closure form can still be added on top.

### State machines

First-class, because guards, scenes and missions are all state machines.

```v
mut m := p.machine('guard_ai', guards.records)   // one state for each record; p.machine_global(name) for a single one
mut c := m.state('patrol')                       // returns the Code of the body, as p.define does
c.if_(c.time_in_state().gt(120))
c.to('suspicious')                               // the transition
…
c = m.on_enter('alert')                          // optional
m.run(mut update, i)                             // one frame of record i
```

An unknown state in `to`, a machine with no states and a state declared twice are build errors; each state has the implicit `time_in_state` counter (frames).

Decided in slice 4 (guide chapter 4 shows it working; `jaggame/machine_test.v`, the differential fuzzer and the `guide_test.v` examples check it):

- **The statement is `c.to(name)`.** `go` is a V keyword. `c.me()` is the index of the record, `c.time_in_state()` the frames in the state, `m.start(c, index, state)` a transition from outside the machine's bodies (a spawn), `m.state_of`, `m.time_of` and `m.in_state` expressions.
- **A machine is written out in the language**, not compiled by a new statement: `m_state`, `m_time` and `m_fresh` arrays (a hidden *array* next to the records, not a hidden field of them: a record's layout is fixed when it is declared, before the machine is), a function for each state and each `on_enter`, one transition function `m_to_<state>` for each state that is gone to, and `m_run`, which dispatches and counts the frame. The interpreter and the machine therefore cannot disagree about it, and no code generator work was needed. The functions are written when the program is checked (`finish_machines`), which is why a state can be named before it is declared.
- **Dispatch is an if chain**, not a jump table: with five states a table is not faster, and a table would have needed a native routine and a twin. Revisit it for a machine with many states.
- **The first frame in a state sees `time_in_state` 0**: a transition sets the time to 0 and marks the record fresh, `run` does not count the frame it was entered in. The body that made the transition goes on running after `to`; follow it with `ret_void()`. `on_enter` runs at the transition, before the new state's first frame, and sees time 0.
- **Fuzzing:** the differential fuzzer makes state machines (2 to 5 states over 2 or 3 records, random bodies that read `me()` and `time_in_state()`, random transitions on time and on conditions, some followed by a return and some not, some to the state itself, `on_enter` bodies and `start`s): about 2,000 of the 20,800 programs. It still fails on a planted bug in the new code generator paths.

### Actors

`game.actors(name, extra_fields, count, first_sprite)` is an array of records with the fields `x`, `y` (`fix`), `face` (`u8`, an angle) and `live`, plus the game's, tied to sprites `first_sprite + i`: `spawn(x, y)` (a call: clears the record, sets position, shows the sprite, gives the number or 65535), `remove`, `each(c, i)` (a loop over the live ones, one `end()`), `show`. It is records plus sprites plus, if the game wants one, a machine over `actors.records`.

## Code generation

Correctness first, speed second.

- Globals, locals, parameters: static addresses in a data area after the code, laid out by size (longs, words, bytes), then arrays, tables and records, each long-aligned.
- Labels are the names: function `f` at `f`, global `score` at `score`, a parameter or local `f.x`. The compiler's own labels start with `jaggame.`, which no name can.
- Expressions: every value is evaluated into `d0` as a whole long, sign- or zero-extended from its type; the left operand of a binary operation waits on the stack. Operations work on longs and cut the result back to the type, which is how the interpreter wraps. No optimiser at all in slice 1, not even constant folding; quick and immediate forms only where jagkit chooses them. Slice 4 added three cheap and safe improvements (below), no more.
- Registers `a5`/`a6`/`d7` are reserved for the runtime; compiled code uses `d0`..`d5` and `a0`, and nothing lives in a register across statements. A compiled function is called with `jsr` after its arguments are stored at its parameters' labels; it may change `d0`..`d5` and `a0`..`a4`.
- Helper routines emitted only when used: `jaggame.mul32` (from three `mulu`), `jaggame.divu32` and `jaggame.divs32` (shift-and-subtract, quotient and remainder), `jaggame.fix_mul` (bits 16..47 of the signed 64-bit product, from four `mulu`) and `jaggame.fix_div` (a 64 by 32 bit division). The 68000's `divu`/`divs` divide 32 by 16 bits and trap on zero, so they are not used; narrow multiplications use `mulu`, whose low word is all an 8- or 16-bit result keeps.
- Every accepted program must assemble without `jagkit` reporting a problem; a jagkit problem is a compiler bug, and `plain_image` reports it as one.

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

As built in slice 1: `p.plain_image(main)` is that image, `jaggame.emulated.Runner` boots it (one machine, reused), and `img.differences(it, ram)` compares every variable with an interpreter that ran the same function. The fuzzer (`jaggame/fuzz_test.v`) puts 520 cases in each of 40 programs and runs 20,800 in about five seconds with `-prod`; a coverage check makes sure every operation, conversion, load and store of every type was generated.

## Runtime (slices 2 to 5)

- **Loop:** `init`, then once a frame in the vertical interrupt: read pad, run the scene's `update`, build the display list, sound tick. A missed frame is counted in a variable tests can read.
- **Video:** NTSC and PAL profiles chosen at start-up; a logical 320×240 screen centred in the display window. A `frames_per_second` constant and frame-rate-independent timers (`seconds(1.5)` compiles to the right frame count for either standard, chosen at run time).
- **Sprites:** up to N live objects with x, y, frame, visible, flip, scale, layer; the runtime builds the display list from them every frame, sorted by layer. Animation: named sequences with per-frame durations.
- **Tilemap and camera:** tile sets and maps from assets; rooms larger than the screen; camera follows a target with clamping. Approach to decide in slice 3 and verify in both emulators (a pre-rendered room bitmap scrolled by the object's data pointer and position is the expected one).
- **Collision:** tile flags (solid, hides, exit, item) queried by position; box against box between sprites; a `move_and_slide(x, y, dx, dy, box)` helper.
- **Line of sight and cones:** `can_see(from, facing, to, range, half_angle)` stepping through tiles; sine and arctangent tables. Built in slice 4, see below.
- **Text:** fixed font, `print`, numbers, a HUD layer; briefings with word wrap done at build time.
- **Sound:** effects by name with priority; a pattern sequencer for music with at least four voices and the ability to switch pattern sets on a game event (calm, alert). Tempo independent of the television standard.
- **Scenes:** named scenes with `enter`, `update`, `leave`; `go_scene`; transitions (fade through the colour table).
- **Save data:** a small key-value block with a checksum. Investigate what storage a `.jag` loaded this way has in the emulator and on hardware (cartridge EEPROM), implement what is real, and say plainly what is not.
- **GPU effects:** pluggable background modules with a parameter block (the existing plasma is the model): an animated grid backdrop and a full-screen pulse.
- **Assets:** PNG to 16-bit CRY or to a palette and 8-bit indices, sprite sheets cut by grid, tile sets, maps from text. All checked at build time (phrase widths, palette sizes, missing files).

Decided in slice 2, where the list above left a choice or was wrong (`docs/jaggame/guide.md`, chapter 2, shows each one working; `jaggame/rt_*_test.v` and `demos/hello2/hello2_test.v` check them):

- **A game** is a `Game`: a `Program` (`game.p`) plus the runtime. `new_game(Config{sprites, layers, background})`, then `define_init()` and `define_update()`, which return a `Code` as `p.define` does (a closure form is still possible on top), then `build()`, which returns an `Image` (the `.jag` bytes and the symbol table). A game builds once. Everything the author can see of the runtime is a variable of the program: `frame` (`u32`), `missed_frames` (`u16`), `fps` (`u8`, a variable, not the design's `frames_per_second` constant, because the standard is decided at run time), `pad` and `pad_pressed` (`u32`), and the array of records `sprites`. Names starting `rt_` and labels starting `rt.` belong to the runtime.
- **Everything the interpreter can run is language.** `rt_init` and `rt_frame` (count the frame, move the timers, call update, move the animations, fade the beep) are written in the language, as are text printing and number formatting; only the pad read, the drawing of text rows, the display list and the sound registers are 68000 code (`rt_game.v`, `rt_start.v`, `rt_list.v`, `rt_pad.v`). `game.interpreter(region)` starts the interpreter as if on a machine of that standard and `game.step(it, pad)` runs one frame with a pad; `Interpreter.set_value` (new) lets a test set any variable.
- **Game code runs only in the interrupt.** Start-up calls `rt_init` before interrupts are enabled; afterwards compiled code runs only from the handler, which cannot nest (the 68000 raises its mask, an interrupt that arrives meanwhile waits). Slice 1's "static locals are not reentrant" limit is therefore never reached; the guide says so.
- **The picture is one frame behind the work** (deviation: the list above had the handler build the list for the picture that follows). Frame N's handler points the object processor at the list built by frame N-1's handler, then runs the game and builds a new list into the other of two buffers, because the object processor uses a list up as it draws it and a game's update may take most of a frame. A button shows in the picture two frames after it is pressed; `Player.frames` settles the machine after each frame in tests, because an emulated frame ends in the middle of the handler.
- **`missed_frames`** is the number of handlers that found another video interrupt waiting when they finished (the hardware has one latch, so a handler that takes ten frames counts once).
- **Sprites:** the pool is `Config.sprites` records with `x`, `y` (`i16`, logical pixels), `art`, `frame`, `layer`, `visible`, `flip`, `scale` (`fix`) and the animation's `seq`, `step`, `wait`, `loops`. The builder takes the visible sprites layer by layer, in pool order within a layer (a layer above the last is drawn with the last). Flip is the object processor's reflect flag, so it is in. Clipping: a sprite wholly off the screen is skipped; the top and the bottom are cut by showing fewer lines, exactly for a sprite at full size and in whole source lines for a scaled one (the object processor cannot start an object above the display); the left and the right are left to the object processor, whose line buffer clips (the overhang falls in the display window's border, a few pixels of which the emulator shows). Hiding such sprites was the alternative; cutting is what a game wants. Scale is the 3.5 fixed point of the hardware (1/32 to just under 8).
- **Art:** `art_cry(name, w, h, frames, []u16)` and `art_pal(name, w, h, frames, []u8)` from V arrays (PNG import is slice 3); a game has one palette for its 8-bit pictures, which may not use the top two colours of each text layer. Pixel 0 is transparent. A picture's frame may be at most 65,535 bytes.
- **Animation:** `sequence(name, [Step{frame, seconds}])`, played by name with `sprite.play(c, name, repeat)`. Durations are in seconds and become frames per standard when the game starts (a table for each).
- **Text:** a layer is a program-owned array of glyph cells (`<name>_cells`) and a mark per row (`<name>_dirty`); `print` (string constants only), `number` (unsigned, right-aligned, 1 to 10 cells), `clear` and the `<name>_colour` variable, all ordinary code; the machine draws marked rows each frame. Layers sit over the sprites, in declaration order, and use colour table entries from the top (`255 - 2n`). Printing a string held in a variable and word wrap are not in this slice.
- **Time:** `seconds(x)` is an expression, `fps` times `x` rounded to a whole frame; `whole_seconds(frames)` is its inverse; `timer(name)` gives four variables (`left`, `elapsed`, `running`, `fired`) that the runtime moves before update, with `start`, `stopwatch` and `stop`.
- **Pad:** `pad` is the controller matrix read as it is (the four directions and the twelve keypad keys in the order of `Button`, then A, B, C, Option, Pause); `held` and `pressed` are expressions. The keypad costs nothing extra, so it is in.
- **Beep:** `game.beep` was provisional and is gone: slice 5 replaced it with `sfx` and `play` (see the slice 5 record); hello2 plays an effect.
- **`Val` takes a `u16`** (what `cry` returns), so that a colour can be passed to `set` without a cast.
- **Memory:** the image loads at 0x4000 as before; the two display lists start at 0x80000 and the text pictures follow them, all checked with `jagkit.check_regions`.
- **Test support:** `jaggame.emulated.Player` (boot on either standard, frames, hold, picture, list decoding, sound, cycles) and `Image.field_address`.
- **Cost:** about 1,300 68000 cycles for each visible sprite and 45 for each place in the pool for each layer; compiled text is the slow part (about 17,000 cycles for a number that changes every frame). hello2 used 66,000 of the 221,000 cycles of an NTSC frame (19,400 after slice 3 made numbers cheaper).

Decided in slice 3 (`docs/jaggame/guide.md`, chapter 3, shows each one working; `jaggame/assets_test.v`, `rt_tiles_test.v`, `rt_collide_test.v`, `rt_number_test.v` and `demos/ghostgrid/ghostgrid_test.v` check them):

- **`native` statements** (new in the language, `Code.native` and `native_ret`): an `asm` statement that the interpreter can run too, because it comes with a V function that does to the interpreter's variables what the code does to the machine's. `native_ret` leaves its result in `d0` and returns from the function, so a function with a result may end in one. This is how hot runtime routines are written: the tile queries, the two line probes of `move_and_slide`, and the digits of a number. Every one has a test that runs both sides. The slice 1 rule that `asm` cannot be run by the interpreter stands for plain `asm`.
- **Assets** (`assets_png.v`, `assets_map.v`, `assets_canvas.v`): `png_cry` and `png_pal` cut a PNG by a grid; an alpha below 128 is transparent (value 0), an opaque black is never 0; the palette of 8-bit art is built by the pictures in the order the colours are met (entry 0 transparent) unless the author declared it first, in which case a colour that is not in it is an error with its place. `Canvas` (`new_canvas`, `put`, `fill`, `save`) is in the module so that art programs and tests can write PNGs. Every mistake names the file.
- **Tile sets and maps.** One tile set, 16 by 16 pixel tiles (a different size is a build error: shifts by 4 are what keeps the collision and the drawing short), at most 255 tiles; 255 is `tile_none`, what a position outside the room has. Flags belong to the tile, not the character: the legend gives `legend_tile(ch, tile, flags)` and `legend_marker(ch, name, tile, flags)` and two characters for one tile must agree. The design said flags were "solid, hides, exit, item"; they are `flag_solid`, `flag_cover`, `flag_exit`, `flag_item` and four free ones. Rooms are read when the game is built (so the legend may come after them), at most 64 by 64 tiles and 4,096 tiles, one byte a tile. Markers come back at run time as expressions for the loaded room (`marker_count`, `marker_x`, `marker_y`, in tiles, -1 when there is no such place) and at build time as `markers_of`.
- **The tile layer** is the approach the design expected, and it works as expected in both emulators: the room is drawn into a buffer at 0x100000 of one byte a pixel (the game's palette), the whole room wide, and one object shows a window of it. The object's data pointer picks the line and the phrase (8 pixels at 8 bits); the 0 to 7 pixels left over shift the object's x to the left of the logical screen, and the line buffer clips there. The object is 41 phrases wide so that the fine part always has a phrase. The first-pixel field and a "wider object with the border over it" were not needed: this emulator and Virtual Jaguar draw the same picture (see below). The layer is opaque, the first object of the list (behind every sprite and the text). The buffer is checked with `jagkit.check_regions` and is sized for the largest room.
- **The camera** is `camera_x` and `camera_y` (`i16`, ordinary variables). Sprites take world coordinates, with a `fixed` field (new) for one that stays on the screen; the builder subtracts the camera, and only in a game that has a tile set. `camera_follow(x, y)` puts a position in the middle as far as the room allows; in a room smaller than the screen the camera is negative, so that the room is centred by the same formula (it is the world position at the screen's left edge). The text is never moved.
- **Loading a room** is a statement, `load_room` (and `load_room_number`), and takes frames: the room's size and markers are right at once; the tiles are copied by the language (so the interpreter has them) and drawn by machine code, `tiles_per_frame` = 48 a frame, with `loading` true and a blank picture (no tile layer, no sprites, the text stays) until it is done. It begins one frame late, so that the list already on its way to the screen is blank before the buffer is touched. The game's update goes on running; it must leave the room alone while `loading`. Measured: 15 frames for 600 tiles, 18 for the demo's 816, about 27 for 1,200; at most 125,000 cycles in a frame, so no frame is missed. The room was not drawn with the GPU: the 68000 draws a tile in about 1,700 cycles with `movem`, which is enough at 48 tiles a frame, and a GPU program would have added a second processor to a path that has to be right in both emulators. If a later room needs to load faster, the place to look is `rt.draw_tile` (one tile) and `tiles_per_frame`.
- **Changing a tile** (`set_tile`) changes the map at once and queues the cell (64 a frame); the machine draws the queue after `update`. A change that does not fit is counted in `rt_tile_lost`. The picture is drawn in place while it may be on its way to the screen, so a tile can be seen half drawn in the one frame it changes: the price of not double buffering 300 KB.
- **Collision.** `tile_at`, `flags_at` and `solid_at` are expressions (`tile_at` and `flags_at` are functions with machine code bodies, about 400 cycles). `move_and_slide(x, y, box, dx, dy)` takes `fix` variables for the position and a `Hitbox` for the box, moves along x and then along y against solid tiles, stops flush, and sets `blocked_x()` and `blocked_y()`. The limit is 16 pixels an axis in a call (one tile; a larger step is cut to it), the box must not start inside a wall, and outside the room is solid. `overlap(Rect, Rect)` is an expression. The design's `move_and_slide(x, y, dx, dy, box)` has the box at the end of the position and step, as the rest of the language puts the thing before its numbers.
- **Cheaper numbers.** `number` is a native function (above) that uses `divu` (one division a digit for a value below 65,536, two above) and marks only a cell that changed; the machine draws a cell only if it is marked (`<name>_stale`, a byte a cell, new, next to `<name>_dirty`, a byte a row), four cells at a time when none is. `print` skips a character that is already there. A changing number of 5 cells went from 19,800 cycles a frame to 2,300 (counting), 3,100 (every digit) and 3,900 (a 32-bit value); an unchanged one from 19,700 to 1,600. hello2 went from 66,000 to 19,400.
- **Second emulator.** GHOSTGRID ran in Virtual Jaguar with the pad held to scroll: the frames while scrolling, while a room loads (blank) and in the centred second room are pixel for pixel the same as this emulator's, at one fixed offset (colours within 2). What differs between the two is the window shown: this emulator crops the middle 325 pixels, Virtual Jaguar shows all 352, including the up to 7 columns left and 8 right of the logical screen that the layer's overhang covers.
- **Memory:** the picture buffer starts at 0x100000 (up to 1 MB); the display lists and text pictures stay at 0x80000. The image must stay below 0x80000 as before (GHOSTGRID is 24 KB).
- **Not in this slice:** more than one tile set or tile layer, tile sizes other than 16 by 16, animated tiles, a parallax layer, scaled sprites in collision (a box is whole pixels), rooms that scroll while they load, saving a room's changed tiles across `load_room`.

Decided in slice 4 (`docs/jaggame/guide.md`, chapter 4, shows each one working; `jaggame/rt_sight_test.v`, `machine_test.v`, `fuzz_test.v` and `demos/ghostgrid/ghostgrid_test.v` check them):

- **Angles** are `u8`, 256 to the turn, 0 right, 64 down, 128 left, 192 up (`angle_right` and the others are constants). `game.sine`, `cosine` (-127..127, `i8`) and `direction(dx, dy)` (the arctangent: a table of 64 steps, one division, within one 256th of a turn of `atan2`) are expressions.
- **`can_see(from_x, from_y, facing, to_x, to_y, range, half_angle)`** is a `bool` expression: within `range` pixels (at most 255), within `half_angle` (0..64) of the facing (a dot product against the sine table, squares compared, no division), and no wall on the line. `can_see_crouched` is the same for a crouching target, and `line_clear` is the third test alone. **Cover:** a tile with `flag_cover` blocks sight only for a crouching target; walls block sight for everyone. There are two tables of what blocks (`rt_sight_stand`, `rt_sight_low`), built from the legend.
- **The walk is a `native` routine** (`rt_line_clear`, machine code and a V twin): the tile under every 8th pixel along the line's longer axis, not the two end tiles; positions as 16.16 numbers and the step as 128ths of a pixel from one `divu`; a line longer than 255 pixels along an axis is blocked, one with fewer than two steps is clear. A wall the line crosses for 10 pixels or more is never missed, a graze can be. It is tested against a plain V model on random rooms, machine against interpreter against model (3,640 queries), and the model against a one-pixel walk. The cone test itself stays language code (about 3,000 of the 5,400 cycles of a 15-place look): it is the part that rejects most calls early.
- **Hearing:** `game.noise(c, x, y, radius)` and `game.hears(x, y)`: a circle, walls do not stop it, heard in the frame it was made and the next (so that whoever runs before the maker hears it), a later noise replaces the one before. Who reacts is the game's: GHOSTGRID's guards react on patrol and on the way back.
- **Showing a cone: highlighted floor tiles**, not a GPU overlay. The object processor has no blending, so an overlay would be a stipple, and it would be a second layer to keep in step with the walls; tiles need nothing new, they are drawn in place (slice 3) and what is lit is then the same list that decides what sees. The cost is the tile redraw (about 1,700 cycles a tile, at most a dozen or two a move) and the walks, so the lists are worked out when the game is built: `game.view_cells(room, tile_x, tile_y, facing, range, half_angle, crouched)` returns what `can_see` says yes to from the middle of a tile to the middle of each floor tile (a test asks the machine's `can_see` about 20,410 tiles in six random rooms and the lists agree), and the game keeps one list for each tile and facing in tables (GHOSTGRID's are 12,360 cells in 4,160 lists, one for each of the room's 1,040 tiles and each of four facings, 37 KB). Detection is a look-up in the byte of the figure's tile (which guards' cones are on it); a crouching figure is only asked `can_see_crouched` when it is in a lit tile. One cone is worked out a frame. `Game.tile_cell` (the map's element) is the expression that reads a cell.
- **`set_tile` and the new `set_cell`** (a cell number instead of a column and a row) are machine code now, with V twins: a cone changes up to 30 tiles at once and the language version cost 1,000 or more cycles a change. The existing tile tests pass unchanged; a new test fills the queue past 64 and checks the map, the queue and the count of what is lost on both sides.
- **The code generator** got three cheap improvements, in `codegen.v`, with the differential fuzzer green (20,800 programs, state machines included) and shown to catch a planted bug in each: a comparison in an `if_` or a loop branches on the flags of its `cmp` instead of making a 0 or a 1 and testing it; the right operand of an operation that is a constant or a plain variable is loaded into `d1` without going through the stack; a variable set to a constant, or to itself plus or minus a constant, is one instruction on the variable, and an element is set from a constant or a variable without the stack. A loop that cleared a byte went from 415 to 250 cycles a turn. There is no constant folding and no register allocation; nothing else was done.
- **Test support:** `Image.address_of_element`, `Image.field_size`, `Interpreter.set_element`, `set_field` and `array`, for tests that put the figure somewhere by hand.
- **Memory:** the image is 95 KB (below 0x80000, as before); the tables of cones are 37 KB of it.
- **Not in this slice:** sweeping cameras (the design's "cameras that sweep"), cones at angles other than the four ways (the tables and `can_see` are general; the display lists are for four facings), a cone that changes with the crouch (the display is the view of a standing target; crouching hides you by the cover rule), pathfinding to an arbitrary tile (guards follow fields of directions to the waypoints, and walk straight, with `move_and_slide`, to a spot), sound.

Decided in slice 5 (`docs/jaggame/guide.md`, chapter 5, shows each one working; `jaggame/rt_scenes_test.v`, `rt_menu_test.v`, `rt_sound_test.v`, `rt_save_test.v`, `rt_backdrop_test.v` and `demos/ghostgrid/ghostgrid_test.v` check them):

- **Scenes** (`rt_scenes.v`) are a global state machine `scene` plus ordinary functions and variables, as machines were: `game.scenes()`, `scene`, `on_enter`, `on_leave`, `setup(name, steps)` (a step a frame, `wait` to repeat a step, the update begins after the last), `go` (immediate: leave, enter), `start`. No new language construct, so the differential fuzzer needed no new generator (it ran unchanged and passed; see the gate). Build errors: duplicate scene, `go` or start to an unknown scene, no scenes, no start scene, a leave or setup of an unknown scene. Not done: the design's fade transition (a scene change is a cut), stacked scenes (GHOSTGRID's pause is a mode of the play scene, because a scene change would load the room again).
- **Menus** (`rt_menu.v`): items on a text layer, a cursor with repeat (0.3 s, then every 0.1 s, in seconds so it is the same on both standards), `chosen`, `backed`, `moved` as variables; no callbacks (the game reads the variables). Used for the mission select (the list of missions is data), the pause menu and the result menu.
- **Sound** (`rt_sound.v`, `rt_synth.v`): a new six-voice DSP program (two squares, a triangle, a pitched noise for drums, a square and a noise for effects) in place of `jagkit.synth()`, whose three voices could not play music; its voices block is a mailbox the program writes (`rt_voice`) and the machine copies once a frame. Everything that decides the numbers is language code (`rt_sound_tick`), so the interpreter has it; only the decay of the volumes is machine code with a twin. Effects: steps of Hz and seconds, volume, decay, slide, a voice (tone or noise) and a priority; a new effect takes its voice at equal or higher priority. Music: patterns of 16 rows by four channels written as text with note names, an order, a speed in rows a second; the sequencer adds `rows/second / fps` to a fix counter and plays a row per 1.0, so the tempo is the same in seconds on NTSC and PAL (the design mentioned the double-tick of `demos/hero/pal.v`; a fractional counter makes it unnecessary). `music_play` is idempotent. Deviation from the design: the design said "at least four voices and switch pattern sets"; tracks are switched whole.
- **Save data** (`rt_save.v`, `rt_cartridge.v`, `cart/eeprom.v`, `machine/bus.v`). *What is real:* a cartridge can carry a 93C46 type serial EEPROM (64 words of 16 bits) on the cartridge board, reached through `$F14000` (data out, bit 0), `$F14800` (a word write is a data bit, a read the clock strobe) and `$F15000` (chip select). A JAGR `.jag` image is loaded into RAM by a tool and has an EEPROM only if the board it was loaded through has one. *Decision:* the game also comes out as a cartridge image (`Image.cartridge()`: the 8 KB boot area with the memory-configuration bytes and the start address, a copy loop, the program; written next to the `.jag` as `.j64`), which is what a board with the chip would run. It carries no signature a retail console checks and has not been run on hardware. *The emulator* always has the chip, persists it by image hash and restores it (`cli/saves.v`, existing). It was incomplete: it only clocked data out on a write of `$F14800`, while the standard driver (and Virtual Jaguar's core, whose `eeprom.c` was read for this) clocks by reading it. Fixed with tests: a read of the clock address strobes (`Eeprom.strobe`), a byte write of the data line no longer reads the word it merges with (which would have strobed), and `Eeprom.present = false` models a board without the chip. Not copied from the core: its leniency of enabling writes at every chip select (this chip needs EWEN, which the driver sends) and its one-time "busy" read after a write (this one is ready at once; the driver polls). *The record:* a header word (mark and version), up to 16 16-bit fields, a checksum; `load` accepts it only if all are right, otherwise "none" and the fields are not touched; `store` reads every word back and sets `failed` if one differs (so a missing chip is reported). One word a frame is moved, so the up to 10 ms a real write takes never keeps a frame from being ready. The interpreter's chip is the array `rt_eeprom` (`rt_ee_present` models a missing chip), twins for the two machine-code routines.
- **GPU backdrop** (`rt_backdrop.v`): the first object of the display list, 160 by 120 pixels of 16-bit CRY at `0x90000` shown at double size, drawn by a GPU program that sums three table look-ups and a colour (a grid, a diagonal bar, a gradient) from four numbers the 68000 writes (language code); original, not the plasma. The object is in the list only while `rt_backdrop_on`; the GPU is not told to draw otherwise. The region is declared with `check_regions` and the tile buffer is not touched. The test compares the buffer with a V model, accepting this or the last frame's numbers per pixel.
- **Scene-aware changes to the runtime:** `hide_room` (a menu has the screen to itself), `load_room` empties the tile ring; `Player.audio`, `Player.settle_cycles` for tests; `Game.menu`, `Game.save`, `Game.backdrop` and the sound declarations are described in the reference.
- **Speed (slice 4's carried-over target).** The diagnosis in slice 4 was a little off: one cone was already worked out a frame. The 175,700-cycle frame was the end-of-mission screen written in one frame (about 100,000 cycles) plus cones that turn (up to 60 tiles at 1,700 cycles). Fixes: the result screen is a four-step setup; tile redraws wait in a ring of 128 and are drawn at most 12 a frame (5 when fewer wait); the cones' cells are one table of cell numbers; the sound's envelopes are machine code. Measured with the interrupt settled after each frame (so the tail past the emulator's frame boundary counts), the frame that ends a mission left out: worst case (four chasing, running, cones moving, alert music) mean 87,100, **most 131,700 of 221,000 (59.6%) on NTSC**, 129,700 (48.9%) on PAL, calm most 101,700 (was 118,700), missed frames 0. A two-phase cone (light the new cells, put out the old next frame) was tried and dropped: it lowered the peak but delayed the cones enough that the robot could no longer find an unseen way.
- **Costs:** sound 1,700 cycles an empty game, 4,483 on average with the alert track playing, 7,100 at most (a row); backdrop about 900 cycles a frame while shown (the GPU draws a picture in part of a frame); save and load a word a frame, about 1,500 cycles each; GHOSTGRID is 113 KB (`.jag`), 128 KB (`.j64`).
- **Limits:** one backdrop, one record, up to 16 fields; patterns of 16 rows only; four melodic channels in a track and no effect on them; a sound effect has one voice; the picture can trail the map by a few frames after a big cone change; text on the shared layer is crowded on the result screen (rows of 8 pixels).
- **Second emulator:** see the final report of the slice (what `front` could and could not hold is recorded there and in the guide).
- **For slice 6:** more missions (the mission list and the save record are per mission: widen the record), the four kinds (clock, never seen, chips, exit), sweeping cameras (the cone tables are for four facings), ranks from time and times seen, restoring chips, a second room in a mission (the scene's setup already spreads work); a fade between scenes if wanted; per-mission best times in the picker; a real-hardware check of the cartridge image and a signature.

## The demo: GHOSTGRID

An original top-down stealth trainer. Simulated training rooms: glowing grid floors, block walls, simple geometric figures. No characters, names, levels, music or visual design from any existing game.

- **Player:** walk, run (louder, guards hear it), crouch behind cover, knock on a wall to draw a guard. (Built in slice 4: A runs, B crouches, C knocks on the wall the figure faces.)
- **Guards:** patrol routes; a visible vision cone blocked by walls; states patrol → suspicious → alert → search → return. Cameras that sweep (not yet). Built in slice 4: four guards in the first mission; a guard that is alert and touches the figure ends the mission (the alert does not time out: a guard that has lost the figure for 50 frames searches and returns).
- **Missions:** about ten, of four kinds: reach the exit, collect every chip, never be seen, beat the clock. A rank per mission from time and times seen.
- **Scenes:** title, mission select (with best rank and time), briefing, play, pause, results.
- **Uses:** every runtime feature above.

Slice 4 replaced the two training rooms and their chips with the first mission, a depot of 40 by 26 tiles: the chips, the annex and the room switch are no longer in the demo (`flag_item`, `set_tile` and `load_room_number` are still tested by `rt_tiles_test.v` and `rt_collide_test.v`). The mission has a clock, an alert indicator, an end screen and a restart. Slice 5 added the title, mission select, pause and result scenes, sound and music, the saved best times and the backdrop; ranks and several missions are slice 6.

## Slices and gates

Each slice ends with the suite green, a guide chapter, and commits on `main` (never pushed by an agent).

| # | Slice | Gate |
|---|---|---|
| 1 | Language core: types, expressions, statements, functions, tables, arrays, records; interpreter; code generator; helpers | `v -prod test jaggame/` passes, including differential fuzzing of at least 20,000 random cases across all types, and four program tests |
| 2 | Runtime core: loop, video profiles, sprites, pad, text, timers; `demos/hello2` (hello rewritten with no assembly). **Done** | its test passes on NTSC and PAL; runs in the second emulator |
| 3 | Assets, tilemap, camera, collision; a player walking a scrolling room. **Done** | robot walks a route, cannot pass walls, camera clamps |
| 4 | State machines, arrays of actors, line of sight; one complete mission with guards. **Done** | robot completes it unseen; idle-in-view player is caught |
| 5 | Scenes, sound and music, save data, GPU backdrop. **Done** | menu flow test; music switches on alert; save survives restart |
| 6 | GHOSTGRID complete: all missions, ranks, PAL, cross-check, final docs | every mission completed by a robot; full suite green |
