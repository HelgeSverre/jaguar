# jaggame

A V module for writing Atari Jaguar games without writing assembly. A program *describes* itself (variables, logic, sprites, rooms, scenes, sound) to a builder; the builder checks it, compiles the logic to 68000 code, links it with a fixed runtime and writes a `.jag` image, and a `.j64` cartridge image for a board with the save chip. The same description also runs in an interpreter written in V, and the two must agree.

- **A small typed language.** `u8` to `u32`, `fix` (16.16), `bool`, arrays, tables, records, functions, state machines. Types, sizes and memory are checked when the image is built; every mistake comes out together, with its place.
- **A runtime.** A frame loop for NTSC and PAL, sprites, text layers, timers, tile rooms bigger than the screen with a camera and collision, line of sight and hearing, scenes with a fade between them, menus, a six-voice synthesizer with effects and music, a saved record in the cartridge's EEPROM, and a GPU-drawn backdrop.
- **Assets.** PNG files to sprites, tile sets and palettes; rooms as text with a legend.
- **Tested twice.** A differential fuzzer runs random programs in the interpreter and on the emulated 68000; a robot plays [GHOSTGRID](../demos/ghostgrid/main.v), a game with ten missions that uses every feature, through the pad.

A game that moves a ball and counts its steps (it builds and runs; `v run` it, then `just run ball.jag`):

```v
mut g := jaggame.new_game(jaggame.Config{ sprites: 1, layers: 1 })
g.art_cry('ball', 16, 16, 1, []u16{len: 256, init: jaggame.cry(255, 160, 40)})
ball := g.sprite(0)
hud := g.text_layer('hud', jaggame.TextConfig{ columns: 16, rows: 1, x: 8, y: 8 })
steps := g.p.u16('steps')

mut init := g.define_init()
ball.put(mut init, 'ball', 152, 112, 0)
hud.print(mut init, 0, 0, 'STEPS')

mut c := g.define_update()
c.if_(g.held(.left))
c.sub_from(ball.x, 2)
c.inc(steps)
c.end()
c.if_(g.held(.right))
c.add_to(ball.x, 2)
c.inc(steps)
c.end()
hud.number(mut c, 6, 0, steps, 5)
os.write_file_array('ball.jag', g.build()!.bytes)!
```

| Read | For |
|---|---|
| [`docs/jaggame/guide.md`](../docs/jaggame/guide.md) | the guide, six chapters: the language, the runtime, rooms and collision, guards and cones, scenes and sound and saves, missions as data and how GHOSTGRID is put together |
| [`docs/jaggame/reference.md`](../docs/jaggame/reference.md) | every public name, generated from the source comments (`just reference`) |
| [`docs/jaggame/design.md`](../docs/jaggame/design.md) | the plan and the contract, a record of each slice, the feature checklist and what is not verified |
| [`demos/hello2`](../demos/hello2/main.v), [`demos/ghostgrid`](../demos/ghostgrid/main.v) | a small game and a large one |

```sh
v -prod test jaggame/ demos/hello2/ demos/ghostgrid/    # all of it, about four minutes
```
