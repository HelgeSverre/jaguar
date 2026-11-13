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
| `fn fix_raw(f f64) i64` | fix_raw is the raw 16.16 value nearest to a float: `fix_raw(1.5)` is 98304. |
| `fn fix_value(raw i64) f64` | fix_value turns a raw `fix` into a float, for tests and messages. |

## Expressions

`jaggame/lang_expr.v`

| Declaration | |
|---|---|
| `enum Op` | Op is an operation of an expression. |
| `fn (o Op) name() string` | name is the operation as it is written in the builder. |
| `struct Expr` | Expr is a value of the language: a literal, a variable, an element, a field, or an operation on other expressions. A variable handle is an Expr too, so it can be used wherever a value can, and as a destination. Expressions are only descriptions; their types are checked when the program is built. |
| `type Val = Expr \| int \| i64 \| f64 \| bool \| u16` | Val is what builder methods take: an expression or a V literal. An `int` (or a `u16`, which is what `cry` returns, or an `i64`, for large `u32` values) takes the type of the other side, an `f64` is a `fix`. |
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
| `type NativeFn = fn (mut it Interpreter) !` | NativeFn is what the interpreter runs in place of the machine code of a `native` statement: it must do to the interpreter's variables what the code does to the machine's. |
| `fn (mut c Code) native(emit AsmFn, run NativeFn)` | native is an `asm` statement that the interpreter can run too: the machine runs `emit`'s code, the interpreter calls `run`. It is how the runtime has hot routines in 68000 code and the same behaviour in tests; a test of the two together (`Image.differences`) keeps them equal. |
| `fn (mut c Code) native_ret(emit AsmFn, run NativeFn)` | native_ret is `native` for a function that has a result: the code leaves the result in `d0` as a compiled `ret` does, and the function returns from there (so the function needs nothing after it); the interpreter's `run` leaves the result in `Interpreter.result`. |
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
| `fn (mut it Interpreter) set_value(name string, raw i64) !` | set_value changes a global variable, as a test feeds the program an input (the pad, say). The raw value is cut to the variable's type. |
| `fn (it &Interpreter) field(name string, index int, field string) !i64` | field is the raw value of a field of an element of an array of records. |
| `fn (mut it Interpreter) set_element(name string, index int, raw i64) !` | set_element changes an element of a global array, as a test feeds the program an input or moves something by hand. The raw value is cut to the element's type. |
| `fn (mut it Interpreter) set_field(name string, index int, field string, raw i64) !` | set_field changes a field of an element of an array of records, as `set_element` does. |
| `fn (it &Interpreter) array(name string) ![]i64` | array is a copy of the raw values of a global array or table, for a test that looks at all of it at once. |

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
| `fn (img &Image) field_address(name string, index int, field string) !u32` | field_address is the address in memory of a field of an element of an array of records, for a test that sets one by hand. |
| `fn (img &Image) address_of_element(name string, index int) !(u32, int)` | address_of_element is the address in memory of an element of a global variable or array, and its size in bytes, for a test that sets one by hand (the bytes are big-endian). |
| `fn (img &Image) field_size(name string, field string) !int` | field_size is the size in bytes of a field of an array of records. |

## The runtime: games

`jaggame/rt_game.v`

| Declaration | |
|---|---|
| `const logical_width = 320` | logical_width is the width of the screen a game draws on, in pixels. |
| `const logical_height = 240` | logical_height is the height of the screen a game draws on, in lines. |
| `struct Config` | Config is what a game decides before it declares anything. |
| `enum Region` | Region is the television standard a game runs on. |
| `struct Game` | Game is a Program with a runtime around it. Declare the game's own variables and functions on `p`; the runtime's are listed on the struct. |
| `fn new_game(config Config) &Game` | new_game starts a game with the runtime's variables declared. |
| `fn cry(r int, g int, b int) u16` | cry is the CRY colour nearest to an RGB colour, each part 0..255, for art, palettes, text and the background. |
| `fn (mut g Game) define_init() &Code` | define_init returns the block that collects the statements of the function that runs once, before the first frame. |
| `fn (mut g Game) define_update() &Code` | define_update returns the block that collects the statements of the function that runs once every frame, in the vertical interrupt. |
| `fn (g &Game) seconds(s Val) Expr` | seconds is a number of frames: the right one for the television standard the game finds itself on, decided when it starts. Use it for durations: `seconds(1.5)` is 90 on NTSC and 75 on PAL. The result is a `u16`. |
| `fn (g &Game) whole_seconds(frames Val) Expr` | whole_seconds is a whole number of frames as seconds, rounded down, for showing elapsed time. |

## The runtime: sprites and animations

`jaggame/rt_sprites.v`

| Declaration | |
|---|---|
| `struct Art` | Art is a picture the sprites can show. |
| `fn (mut g Game) art_cry(name string, width int, height int, frames int, pixels []u16) Art` | art_cry declares a picture of 16-bit CRY pixels (see `cry`). The pixels are `frames` pictures of `width` by `height`, one after the other, a line after a line. The width must be a multiple of 4, so that a line fills whole 64-bit phrases. The pixel value 0 is transparent. |
| `fn (mut g Game) art_pal(name string, width int, height int, frames int, pixels []u8) Art` | art_pal declares a picture of 8-bit pixels that index the game's palette (see `palette`). The width must be a multiple of 8. The pixel value 0 is transparent. |
| `fn (mut g Game) palette(colours []u16)` | palette sets the colours that 8-bit pictures use: entry n is the colour of pixel value n. At most 256 minus two for every text layer are allowed (the text keeps the top of the colour table). |
| `struct Sprite` | Sprite is a handle on one element of the sprite pool. Its fields are expressions, usable as values and as destinations. |
| `fn (mut g Game) sprite(index int) Sprite` | sprite is element `index` of the pool. A number that is not in the pool is a build error. |
| `fn (g &Game) sprite_at(index Val) Sprite` | sprite_at is the element of the pool that an expression selects: use it in a loop, `game.sprite_at(i)`. The interpreter stops on an index outside the pool; the machine does not check. |
| `fn (s Sprite) put(mut c Code, art string, x Val, y Val, layer int)` | put shows a sprite: it sets the picture, the position and the layer, frame 0, full size, and makes it visible. |
| `fn (s Sprite) hide(mut c Code)` | hide stops drawing a sprite. |
| `struct Step` | Step is one step of an animation: which frame to show, and for how long. |
| `fn (mut g Game) sequence(name string, steps []Step)` | sequence declares a named animation: the frames to show one after the other, each for its time. A time is in seconds, so that the animation runs at the same speed on both television standards; it is rounded to whole frames, at least 1. |
| `fn (s Sprite) play(mut c Code, name string, repeat bool)` | play starts a named animation on the sprite: it shows the first step now and the runtime moves on every frame. With `repeat` it starts again after the last step; without, the sprite stays on the last frame and `playing` becomes false. |
| `fn (s Sprite) stop(mut c Code)` | stop ends the animation of a sprite; it keeps the frame it shows. |

## Assets: PNG import

`jaggame/assets_png.v`

| Declaration | |
|---|---|
| `fn (mut g Game) png_cry(name string, path string, cell_w int, cell_h int) Art` | png_cry reads a PNG as art of 16-bit CRY pixels, cut into frames by a grid of `cell_w` by `cell_h` pixels. The frames are numbered across and then down. The cell width must be a multiple of 4. |
| `fn (mut g Game) png_pal(name string, path string, cell_w int, cell_h int) Art` | png_pal reads a PNG as art of 8-bit pixels that index the game's palette, cut into frames by a grid like `png_cry`. The cell width must be a multiple of 8. If the game declared its palette (`palette`), every colour in the picture must be in it; if not, the colours of the picture are added to a palette that grows with each picture, in the order they are found (entry 0 is the transparent colour). |

## Assets: drawing pictures for a game

`jaggame/assets_canvas.v`

| Declaration | |
|---|---|
| `struct Canvas` | Canvas is a picture to draw on and save as a PNG: for the small programs that make a game's art (see demos/ghostgrid/art) and for tests that need a file to import. A pixel is red, green, blue and alpha, 0..255; an alpha of 0 is transparent. |
| `fn new_canvas(width int, height int) Canvas` | new_canvas makes a transparent picture. |
| `fn (mut c Canvas) put(x int, y int, r int, g int, b int, a int)` | put sets one pixel; a place outside the canvas is ignored. |
| `fn (mut c Canvas) fill(x int, y int, w int, h int, r int, g int, b int)` | fill paints an opaque rectangle. |
| `fn (c Canvas) save(path string) !` | save writes the canvas as a PNG file, making the directory if it is missing. |

## Assets: tile sets, legends and rooms

`jaggame/assets_map.v`

| Declaration | |
|---|---|
| `const flag_solid = 1` | flag_solid is a tile flag: the tile blocks movement (`move_and_slide`, `solid_at`). A tile has the flags the legend gives it; the game reads them with `flags_at`. |
| `const flag_cover = 2` | flag_cover is a tile flag: a place to hide behind. |
| `const flag_exit = 4` | flag_exit is a tile flag: the tile leads out of the room. |
| `const flag_item = 8` | flag_item is a tile flag: something to pick up. |
| `const flag_user1 = 16` | flag_user1 is a tile flag the game may use as it likes. |
| `const flag_user2 = 32` | flag_user2 is a tile flag the game may use as it likes. |
| `const flag_user3 = 64` | flag_user3 is a tile flag the game may use as it likes. |
| `const flag_user4 = 128` | flag_user4 is a tile flag the game may use as it likes. |
| `const tile_size = 16` | tile_size is the width and the height of a tile in pixels. |
| `const tile_none = 255` | tile_none is what `tile_at` returns outside the room; it is solid. |
| `struct Point` | Point is a position in a room, in tiles. |
| `struct Room` | Room is a handle on a room: `index` is the number to give `load_room`. |
| `fn (mut g Game) tileset(path string) Tileset` | tileset reads the PNG as the game's tile set: tiles of 16x16 pixels, cut across and then down and numbered from 0. A game has one tile set, which shares the game's palette with the other 8-bit art. At most 255 tiles (255 is `tile_none`). |
| `struct Tileset` | Tileset is a handle on the tile set. |
| `fn (mut g Game) legend_tile(ch rune, tile int, flags int)` | legend_tile says that the character `ch` in a room is tile `tile` of the tile set, with `flags` (the `flag_` constants, added together). A tile's flags are a property of the tile: two characters that show one tile must give it the same flags. |
| `fn (mut g Game) legend_marker(ch rune, name string, tile int, flags int)` | legend_marker says that the character `ch` in a room is a place called `name`: the game asks for its position (`marker_x`, `marker_y`) and the picture shows tile `tile` there, with `flags` as for `legend_tile`. Several characters may share a name; the places of a name are numbered in reading order, rows from the top. |
| `fn (mut g Game) room(name string, text string) Room` | room declares a room from a text of rows, one character a tile (a leading and a trailing line break are ignored). Rooms are numbered from 0 in the order they are declared. Rows must be of equal length, the room from 1x1 to 64x64 tiles and 4096 tiles at most. |
| `fn (mut g Game) markers_of(room Room, name string) []Point` | markers_of are the places of a marker name in a room, in tiles, in reading order. Rooms are read when the game is built, or by this call. |
| `fn (mut g Game) room_size(room Room) (int, int)` | room_size is the width and height of a room in tiles. |

## The runtime: the tile layer, rooms and the camera

`jaggame/rt_tiles.v`

| Declaration | |
|---|---|
| `fn (mut g Game) load_room(mut c Code, room Room)` | load_room starts loading a room (see `room`). The tile layer and the sprites are not drawn until it is done, `loading` is true meanwhile, and the game's update goes on running: leave the room alone while `loading`. The room's size (`room_width`, `room_height`) and its markers are right at once; `tile_at` and the tiles are not until the room is loaded. |
| `fn (mut g Game) load_room_number(mut c Code, number Val)` | load_room_number is `load_room` for a room number that is not known when the game is built: an expression, from 0. A number past the last room loads the last one. |
| `fn (mut g Game) set_tile(mut c Code, column Val, row Val, tile Val)` | set_tile puts a tile at a column and a row of the room (in tiles) and redraws it. Up to 64 changes can be drawn in one frame; more are counted in `rt_tile_lost` and not drawn. A place outside the room is ignored. |
| `fn (mut g Game) set_cell(mut c Code, cell Val, tile Val)` | set_cell is `set_tile` for a cell number: the tile at `cell` (row * room width + column) of the loaded room becomes `tile`, drawn this frame like `set_tile`. A cell outside the room is ignored. |
| `fn (mut g Game) tile_at(x Val, y Val) Expr` | tile_at is the tile number at a world position in pixels, as a `u8` expression: `tile_none` (255) outside the room. The position is an `i32` or narrower; turn a `fix` into pixels with `as_(.i32)`. |
| `fn (mut g Game) flags_at(x Val, y Val) Expr` | flags_at is the flags of the tile at a world position (the `flag_` constants, added together), as a `u8` expression; outside the room it is `flag_solid`. |
| `fn (mut g Game) solid_at(x Val, y Val) Expr` | solid_at is true when the tile at a world position blocks movement. |
| `fn (mut g Game) marker_count(name string) Expr` | marker_count is how many places of the marker `name` the loaded room has, a `u8` expression. |
| `fn (mut g Game) marker_x(name string, k Val) Expr` | marker_x is the column, in tiles, of place number `k` (from 0) of the marker `name` in the loaded room, an `i16` expression; -1 if there is no such place. Multiply by 16 for pixels. |
| `fn (mut g Game) marker_y(name string, k Val) Expr` | marker_y is the row of a marker's place, like `marker_x`. |
| `fn (mut g Game) camera_follow(mut c Code, x Val, y Val)` | camera_follow moves the camera so that the world position (x, y) is in the middle of the screen, as far as the room allows: the camera stops at the edges of the room, and a room smaller than the screen is centred. The position is in pixels, an `i32` or narrower. |

## The runtime: collision

`jaggame/rt_collide.v`

| Declaration | |
|---|---|
| `struct Hitbox` | Hitbox is the part of a sprite that collides: a rectangle of `w` by `h` pixels whose top left corner is `ox`, `oy` pixels from the sprite's position. A hitbox smaller than the picture lets the corners pass walls. |
| `struct Rect` | Rect is a rectangle in the world, for `overlap`. |
| `fn (s Sprite) rect(b Hitbox) Rect` | rect is the world rectangle of a sprite's hitbox. The sprite's position is an `i16`, so the other rectangle's numbers must be one too. |
| `fn overlap(a Rect, b Rect) Expr` | overlap is true when two rectangles share at least one pixel. All their numbers must be of one type (integers; a `fix` position needs `as_`). |
| `const max_step = 16` | max_step is the most a box moves along one axis in one `move_and_slide`: one tile. A larger step is cut to it; a faster mover calls again. |
| `fn (mut g Game) move_and_slide(mut c Code, x Expr, y Expr, box Hitbox, dx Val, dy Val)` | move_and_slide moves the box of a mover, whose position is `x` and `y` (`fix` variables, in world pixels), by `dx` and `dy` (`fix` values) against the solid tiles: first along x, then along y, each stopping flush against a wall. Moving diagonally into a wall therefore slides along it. Afterwards `blocked_x` and `blocked_y` say which way a wall stopped it.  A step along one axis is at most `max_step` (16) pixels, one tile, so that only one new column or row of tiles can be entered and nothing is tunnelled through; a larger step is cut to that. The box must not start inside a wall. Outside the room counts as solid. The edge of the box is the whole pixel the position is in: the position's fraction is kept while the box is free and dropped when a wall stops it. |
| `fn (mut g Game) blocked_x() Expr` | blocked_x is true when the last `move_and_slide` was stopped by a wall along x. |
| `fn (mut g Game) blocked_y() Expr` | blocked_y is true when the last `move_and_slide` was stopped by a wall along y. |

## The runtime: text

`jaggame/rt_text.v`

| Declaration | |
|---|---|
| `struct TextConfig` | TextConfig places a text layer. |
| `struct TextLayer` | TextLayer is a handle on a text layer. |
| `fn (mut g Game) text_layer(name string, config TextConfig) TextLayer` | text_layer declares a layer of text. Layers are drawn over all sprites, in the order they are declared. |
| `fn (t TextLayer) print(mut c Code, col Val, row Val, text string)` | print writes a string constant at a column and a row of the layer. The font has capitals, digits and punctuation; anything else, and a string that does not fit the row, is a build error. Columns and rows may be expressions; the machine does not check those. |
| `fn (t TextLayer) number(mut c Code, col Val, row Val, value Val, width int)` | number writes an unsigned number at a column and a row, right-aligned in `width` cells (1 to 10). A number with more digits shows its low digits. The value may be any unsigned integer expression. |
| `fn (t TextLayer) clear(mut c Code)` | clear blanks the whole layer. |

## The runtime: the pad

`jaggame/rt_pad.v`

| Declaration | |
|---|---|
| `enum Button` | Button is one button of the Jaguar's controller. The order is the order of the bits in `pad`: the matrix of four rows of four lines, then the fire buttons, then Pause. |
| `fn button_mask(b Button) u32` | button_mask is the bit (or bits) of `pad` and `pad_pressed` that belong to a button. A test that feeds the interpreter builds the pad it wants from these. |
| `fn (g &Game) held(b Button) Expr` | held is true while a button is down, as a `bool` expression. |
| `fn (g &Game) pressed(b Button) Expr` | pressed is true for the one frame in which a button went down. |

## The runtime: timers

`jaggame/rt_time.v`

| Declaration | |
|---|---|
| `struct Timer` | Timer is a handle on a timer. |
| `fn (mut g Game) timer(name string) Timer` | timer declares a timer, stopped. |
| `fn (t Timer) start(mut c Code, frames Val)` | start counts `frames` down to 0 (use `seconds` for the number). When it gets there the timer stops and `fired` is true for one frame. Starting a running timer starts it over. |
| `fn (t Timer) stopwatch(mut c Code)` | stopwatch counts the frames since now in `elapsed`, until it is stopped. |
| `fn (t Timer) stop(mut c Code)` | stop stops the timer; `left` and `elapsed` keep their values. |

## The runtime: scenes

`jaggame/rt_scenes.v`

| Declaration | |
|---|---|
| `struct Scenes` | Scenes is the handle on the game's scenes, made by `Game.scenes`. |
| `fn (mut g Game) scenes() &Scenes` | scenes starts the game's scenes, or returns them if they were started. |
| `fn (mut s Scenes) scene(name string) &Code` | scene declares a scene and returns the block to write its update in: it runs once a frame while the scene is the current one. Inside it, `time_in_state()` is the frames the scene has been going. |
| `fn (mut s Scenes) on_enter(name string) &Code` | on_enter declares the block that runs when the scene begins, before its first frame (and before its setup, if it has one). |
| `fn (mut s Scenes) on_leave(name string) &Code` | on_leave declares the block that runs when the scene ends, before the next scene's `on_enter`. |
| `fn (mut s Scenes) setup(name string, steps int) &Code` | setup declares a scene's setup: a block that runs once a frame for `steps` frames after the scene begins, with `step` (0, 1, ...) saying which. The scene's update starts when the last step is done. A step that has to wait for something calls `wait`, which makes the same step run again next frame. |
| `fn (mut s Scenes) start(name string)` | start says which scene the game begins in, after its `init` has run. |
| `fn (mut s Scenes) go(mut c Code, name string)` | go leaves the current scene for another one: its `on_leave` runs, then `on_enter` of the new one, at once; the new scene's update (or its setup) begins next frame. The statements after it in the block still run, so follow it with `ret_void()` to stop. |
| `fn (s &Scenes) wait(mut c Code)` | wait makes the setup step that is running run again next frame instead of moving on. |
| `fn (s &Scenes) current() Expr` | current is the number of the current scene, in the order they were declared (a `u8` expression). |
| `fn (s &Scenes) time() Expr` | time is the frames the current scene has been going, counting from 0 in its first frame (a `u16` expression); it does not count while a setup runs. |
| `fn (mut s Scenes) in_scene(name string) Expr` | in_scene is true while the named scene is the current one. Declare the scene first. |
| `fn (s &Scenes) settled() Expr` | settled is true when no setup is running: the update of the current scene is the thing that runs. |

## The runtime: menus

`jaggame/rt_menu.v`

| Declaration | |
|---|---|
| `struct Menu` | Menu is a handle on a menu: its variables, all valid for the frame in which `update` ran. |
| `fn (mut g Game) menu(name string, layer TextLayer, col int, row int, items []string) Menu` | menu declares a menu of `items` on a text layer, with the cursor in column `col` and the first item in row `row`; the items are written two columns to the right. An item is a string constant, as `print` takes. |
| `fn (m Menu) open(mut c Code)` | open writes the items on the layer, puts the cursor on the first and forgets the last choice. Call it when the scene that shows the menu begins. |
| `fn (m Menu) update(mut c Code)` | update reads the pad for one frame: it moves the cursor (with repeat while a direction is held: the delay before it starts and the pace after are in seconds, so they are the same on both television standards), and sets `chosen`, `backed` and `moved`. |

## The runtime: sound and music

`jaggame/rt_sound.v`

| Declaration | |
|---|---|
| `struct Sfx` | Sfx is a sound effect: a sequence of pitches on one voice. |
| `struct SfxStep` | SfxStep is one pitch of an effect and how long it lasts. |
| `struct Pattern` | Pattern is 16 rows of music: four channels written as text. |
| `struct Track` | Track is a piece of music: patterns, the order they are played in (a pattern may come again) and how fast it goes. |
| `fn (mut g Game) sfx(name string, sfx Sfx)` | sfx declares a sound effect with a name, to start with `play`. |
| `fn (mut g Game) track(name string, track Track)` | track declares a piece of music with a name, to start with `music_play`. |
| `fn (mut g Game) play(mut c Code, name string)` | play starts a sound effect. It takes the effect voice it belongs on if that is free or playing something of lower or equal priority; otherwise nothing happens. |
| `fn (mut g Game) music_play(mut c Code, name string)` | music_play starts a track, unless it is the one playing: calling it every frame is fine. Another track that was playing is cut off at once. |
| `fn (mut g Game) music_stop(mut c Code)` | music_stop stops the music; the notes that sound fade out. |
| `fn (mut g Game) music_is(name string) Expr` | music_is is true while the named track is playing. Declare the track first. |
| `fn (mut g Game) music_rows() Expr` | music_rows is the number of rows the sequencer has played since the game started (a `u16` expression): a clock that runs at the track's tempo. |

## The runtime: save data

`jaggame/rt_save.v`

| Declaration | |
|---|---|
| `struct Save` | Save is a handle on the game's saved record. |
| `fn (mut g Game) save(version int, fields []string) Save` | save declares the game's record: `fields` are the names of 16-bit values, up to 16, kept in `Save.field(name)`; `version` (0..255) goes into the record, and a record of another version is not read: change it when the fields change. A game has one record. The variables start at 0. |
| `fn (s Save) field(name string) Expr` | field is the variable of a field of the record (a `u16`). |
| `fn (s Save) busy() Expr` | busy is true while a `load` or a `store` is going on (a `bool`). |
| `fn (s Save) load(mut c Code)` | load starts reading the record. When `busy` is false again, `loaded` says whether there was a good record, and if there was, the fields hold it. |
| `fn (s Save) store(mut c Code)` | store starts writing the fields as the record. When `busy` is false again, `failed` says whether the chip took it. A store that is asked for while another operation is going on is ignored. |

## The runtime: the backdrop

`jaggame/rt_backdrop.v`

| Declaration | |
|---|---|
| `struct Rgb` | Rgb is a colour for the backdrop, each part 0..255. |
| `struct Backdrop` | Backdrop is what the backdrop looks like: the colours of its gradient, from the top of the screen down and round again, blended. |
| `struct BackdropParams` | BackdropParams are the four numbers that say where everything is in a frame, each 0..255. |
| `fn backdrop_params(frame u32) BackdropParams` | backdrop_params is where the grid, the bar and the gradient are in a frame. |
| `fn (mut g Game) backdrop(look Backdrop)` | backdrop gives the game a backdrop. It starts hidden. |
| `fn (mut g Game) backdrop_show(mut c Code)` | backdrop_show makes the backdrop visible from the next picture on. |
| `fn (mut g Game) backdrop_hide(mut c Code)` | backdrop_hide hides the backdrop: the GPU is left alone and the picture shows what is behind it. |
| `fn (mut g Game) backdrop_shown() Expr` | backdrop_shown is true while the backdrop is visible. |

## The runtime: cartridge images

`jaggame/rt_cartridge.v`

| Declaration | |
|---|---|
| `fn (img &Image) cartridge() ![]u8` | cartridge builds the cartridge image of a game image: the length is the next power of two of at least 128 KB. |

## The runtime: building a game

`jaggame/rt_build.v`

| Declaration | |
|---|---|
| `fn (mut g Game) build() !Image` | build checks the game, compiles it with the runtime and returns the image. The game can be built once. Every mistake in the description of the game (and every type error in its code) is reported together. |

## The runtime: running a game in the interpreter

`jaggame/rt_interp.v`

| Declaration | |
|---|---|
| `fn (mut g Game) interpreter(region Region) !&Interpreter` | interpreter checks the game and starts it in the interpreter, as if on a machine of the given standard: the runtime has set up its variables and the game's `init` has run. Add all the game's code before calling it; after it, the game can no longer be built. |
| `fn (g &Game) step(mut it Interpreter, held u32) !` | step runs one frame of the game in the interpreter with a pad: the buttons held this frame, built from `button_mask`. |

## Running images in the emulator (module jaggame.emulated)

`jaggame/emulated/emulated.v`

| Declaration | |
|---|---|
| `struct Runner` | Runner boots images, one after another, in one emulated machine. |
| `fn new() Runner` | new makes a runner with an NTSC machine. |
| `fn (mut r Runner) run(image []u8, done u32, max_frames int) !int` | run boots an image and runs frames until the byte at `done` is not 0. It returns the number of frames that took, or an error after `max_frames`. |
| `fn (r &Runner) ram() []u8` | ram is the machine's main memory. |

## Driving a machine in a test (module jaggame.emulated)

`jaggame/emulated/player.v`

| Declaration | |
|---|---|
| `struct Player` | Player is an emulated machine that a test drives: it boots an image on either television standard, runs frames, holds buttons and looks at the memory, the picture and the sound. |
| `fn boot(image []u8, pal bool) !Player` | boot loads an image into a fresh machine of a television standard. |
| `fn (mut p Player) frames(count int)` | frames runs a number of frames. A frame of the emulator ends in the middle of the frame interrupt of a game that does real work, so after each one the machine runs on until the processor is idle again (`settle`): a test then sees the state the interrupt left behind. |
| `fn (mut p Player) settle()` | settle runs the machine on, for at most a frame, until the 68000 has stopped to wait for the next interrupt. |
| `fn (mut p Player) press(button jerry.Button)` | press holds a button of the first pad until `release`. |
| `fn (mut p Player) release(button jerry.Button)` | release lets go of a button of the first pad. |
| `fn (mut p Player) hold(button jerry.Button, count int)` | hold holds a button for a number of frames, lets go and runs one more. |
| `fn (mut p Player) busy_cycles(count int) int` | busy_cycles runs a number of frames and returns how many cycles of the 68000 a frame used on average: the time it was not stopped, counted in steps of 100 cycles. |
| `fn (p &Player) peek8(address u32) int` | peek8 reads a byte of main memory. |
| `fn (p &Player) peek16(address u32) int` | peek16 reads a big-endian word. |
| `fn (p &Player) peek32(address u32) u32` | peek32 reads a big-endian long. |
| `struct Picture` | Picture is a frame of the emulator: 0x00RRGGBB pixels. |
| `fn (p &Player) picture() Picture` | picture is the last completed frame. |
| `fn (pic &Picture) at(x int, y int) u32` | at is the pixel at a column and a row, or 0 outside the picture. |
| `struct Box` | Box is the smallest rectangle around some pixels, and how many there are. |
| `fn (pic &Picture) bounds(x0 int, y0 int, x1 int, y1 int, wanted fn (pixel u32) bool) Box` | bounds finds the pixels of a picture that `wanted` accepts, inside a rectangle (right and bottom are not included). |
| `fn (mut p Player) loudest() int` | loudest drains the sound made so far and returns the peak sample. |
| `fn (mut p Player) audio() []i16` | audio drains the sound made since the last call and returns it as stereo samples, left then right for each frame of sound. |
| `struct Object` | Object is one object of a display list as the object processor reads it. |
| `fn (p &Player) list_objects(base u32) []Object` | list_objects follows a display list from its first slot, after the 32-byte header at `base`, through its links and branches, and returns the bitmap objects it finds, as they stand in memory now. |
