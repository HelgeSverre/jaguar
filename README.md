# vjag

An Atari Jaguar emulator written in [V](https://vlang.io).

<p align="center">
  <img src="docs/screenshots/hero.png" width="720" alt="vjag playing Tempest 2000 inside its console shell">
</p>

![V 0.5.2](https://img.shields.io/badge/V-0.5.2-5d87bf)
![SDL 3](https://img.shields.io/badge/SDL-3-173f5f)
![macOS arm64](https://img.shields.io/badge/macOS-arm64-lightgrey)
![68000 vectors](https://img.shields.io/badge/68000%20test%20vectors-317%2C500%20passing-brightgreen)
![timing profile](https://img.shields.io/badge/timing-functional__v1-orange)
![MIT licence](https://img.shields.io/badge/licence-MIT-blue)

The Jaguar is an odd machine: a Motorola 68000 that mostly gets out of the way, two custom RISC processors (one for graphics, one for sound), a display-list chip that rewrites its own list while it draws, and a blitter with more mode bits than documentation. vjag emulates all of it in about 14,000 lines of V, with no C emulation cores underneath. SDL3 only puts the picture in a window and the samples in the speakers.

<p>
  <img src="docs/screenshots/landscape.png" width="49%" alt="A wireframe landscape rendered through the blitter">
  <img src="docs/screenshots/fractal.png" width="49%" alt="A Mandelbrot set computed on the emulated GPU">
</p>
<p>
  <img src="docs/screenshots/colour-space.png" width="49%" alt="The Jaguar's CRY colour space">
  <img src="docs/screenshots/nebula.png" width="49%" alt="A 16-bit CRY photograph shown by the object processor">
</p>

The four above are public-domain homebrew. No commercial ROMs or boot ROM images come with this project; bring your own, or start with the [game that is built from source here](#write-your-own).

## Where it stands

It boots and plays a lot. A sweep over a private collection of 139 cartridge dumps and homebrew programs gives:

| Result after 15 seconds of emulated time | Images |
| --- | ---: |
| Animated picture | 118 |
| Static picture | 4 |
| Blank screen | 11 |
| 68000 ended up outside any program | 5 |
| Refused by the loader | 1 |

Most of the blank ones are tools that draw nothing by design, or dumps that are damaged. The crashes are real bugs.

"Animated" means pixels moved, not that the game is right. From looking at the pictures: 3D titles render their worlds, 2D titles scroll and animate, menus respond to the pad, and music plays. Known problems include one racing game that crashes its sound driver after about 13 seconds, a few demos that fall over on scaled sprites, and whatever nobody has played far enough to find.

Things that are honestly not done yet:

- **Boot ROM.** Everything starts by direct boot: the cartridge runs with the video timing the boot ROM would have left behind. Loading a real boot ROM is not wired up.
- **Blitter timing.** A blit finishes the instant it is started. Results are exact pixel for pixel in the tested modes, but software can never catch the blitter busy.
- **Cycle accuracy.** The 68000 counts cycles correctly; the RISC processors use rough per-instruction costs. The profile is called `functional_v1` so nobody mistakes it for more.
- **Save states, input recording, Jaguar CD.** Cartridge EEPROM saves work and persist between runs.
- **Wavetable ROM.** The eight waveforms in JERRY are generated, not dumped, so software that plays them sounds close but not identical.

## Run it

You need V 0.5.2, SDL3 and [just](https://github.com/casey/just). On macOS:

```sh
brew install vlang sdl3 just
just run path/to/game.j64
```

`just` on its own lists every recipe. The ones you will use:

```sh
just run game.j64        # optimized build, then play
just dev game.j64        # debug build with runtime checks
just test                # all unit tests
just install             # copy vjag and vjag_test to ~/.local/bin
just benchmark game.j64  # how fast it runs flat out
```

`just run` with no image opens an empty window; drop an image on it to start. Drop another one at any time to switch games. Saves land in your data directory, keyed by the content of the image, so renaming a file keeps its save.

### The shell

By default the window is not a window. It is a borderless, see-through cutout shaped like a console, in the spirit of the media-player skins of twenty years ago:

- The five red buttons are power, reset, pause, mute and fullscreen. Hover over one and the readout names it.
- The twelve keys are the controller's keypad, laid out 1-9, `*`, 0, `#`. Click and hold works.
- The strip shows what is loaded and scrolls when the title is too long for it.
- The eyes flare with the sound.
- Drag it anywhere by the body. `[` and `]` change its size.

Not your thing? `F2` swaps it for an ordinary resizable window and back, and remembers the choice. So does `shell = false` in `vjag/config.toml` under your configuration directory (`~/Library/Application Support` on macOS), and `--no-shell` turns it off for one run. Fullscreen always shows the bare picture.

<p>
  <img src="docs/screenshots/shell.png" width="49%" alt="The console shell with no image loaded">
</p>

### Controls

| Jaguar | Keyboard | Gamepad |
| --- | --- | --- |
| D-pad | Arrow keys | D-pad |
| C, B, A | Z, X, C | West, South, East |
| Pause | Enter | Start |
| Option | Tab | Back or North |
| Keypad 0-9 | 0-9 | |
| Keypad `*` and `#` | `-` and `=` | Left and right shoulder |

| Emulator | Key |
| --- | --- |
| Pause emulation | P |
| Reset | F5 |
| Fullscreen | F11 |
| Mute | M |
| Status overlay | F1 |
| Screenshot | F12 |
| Console shell on/off | F2 |
| Shell smaller / larger | `[` / `]` |
| Fast-forward (hold) | `` ` `` |
| Quit | Esc |

### Images it understands

Raw cartridges, Jaguar Server executables (`JAGR` types 2 and 3), DRI/Alcyon ABS, COFF, and headerless binaries. The loader looks at the bytes, never at the file extension. For headerless binaries it scores a short list of load addresses by how many absolute jumps land inside the image; when it guesses, it says so, and you can override it:

```sh
vjag demo.bin --format raw --load-address 0x4000 --entry 0x4000
vjag inspect demo.bin        # show what the loader would do, without running
```

## The headless tools

`vjag_test` is the same emulator without a window. It links without SDL, so it should build wherever V does; so far only macOS has been tried.

```sh
vjag_test run game.j64 --frames 600 --screenshot shot.png --wav sound.wav
vjag_test compat roms/ --frames 900 --report-json out/compat.json --screenshots out/shots
vjag_test bench game.j64 --frames 1200
vjag_test trace game.j64 --cpu dsp --tail 80
```

`trace` is the one that earns its keep. It single-steps the machine, keeps the last instructions of one processor in a ring, and stops when something interesting happens: the DSP wanders out of its RAM, the 68000 jumps into the vector table, a memory location changes. Then it prints the ring as a disassembly. Most of the bugs fixed so far were found this way.

```sh
vjag_test trace game.j64 --cpu m68k --stop-range 0x0:0x400   # who jumped into the vectors?
vjag_test trace game.j64 --cpu m68k --watch 0x4912           # who overwrote this?
vjag_test run game.j64 --frames 300 --dump                   # processors, video registers, display list
vjag_test run game.j64 --watch-io 0xf1a100:0xf1a120          # every write to the DSP control registers
vjag_test run game.j64 --frames 900 --press b@600 --press left@700+30 --screenshot shot.png   # scripted pad input
```

## Write your own

`jagkit` is a small V module for making Jaguar programs without an assembler: you write V, and V emits the image.

- **Two assemblers.** One for the 68000, one for the GPU and DSP. An instruction is a method call, a label is a string, a register can have a name that means something, and V itself is the macro language.
- **Display lists.** Describe the bitmaps; the list comes out laid out, linked and guarded for NTSC or PAL.
- **The dull parts.** The hardware register map, nearest-colour matching into CRY, and a `.jag` writer.

```v
mut gpu := jagkit.new_risc(jagkit.gpu_ram)
pixel := jagkit.Reg.r0
gpu.label('next')
gpu.loadw(texture, pixel)      // fetch a texel
gpu.storew(pixel, target)      // put it on screen
gpu.subq(1, left)
gpu.jr(.ne, 'next')
gpu.addqt(2, target)           // delay slot
```

`demos/maw` is a whole game built this way, and `demos/maw.jag` is its output, so there is something to run out of the box:

```sh
just run demos/maw.jag   # play it
just demo                # rebuild the image from the V source first
```

<p>
  <img src="docs/screenshots/maw-title.png" width="49%" alt="The title screen of MAW: a logo and a scroller over a textured tunnel">
  <img src="docs/screenshots/maw-play.png" width="49%" alt="MAW in play: a ship at the bottom of the tunnel, a red gate ahead and a green lane through it">
</p>

MAW is a tunnel flyer. Left and right turn the world; follow the green lane through each red gate. The GPU draws the tunnel from a lookup table with depth fog, a gate is a few rings of the wall texture painted over, the DSP is a three-voice synthesizer and the 68000 runs the rules and the tune. Its test plays the game: it boots the image in the emulator, reads the game's variables through the assembler's symbol table and steers.

It has only ever run in this emulator. Real hardware has not seen it.

## How it is put together

```
hwtypes/   the bus interface and a few shared types; depends on nothing
m68k/      Motorola 68000
risc/      the GPU and DSP: one instruction format, two opcode maps
tom/       video timing, object processor, blitter, CRY colour
jerry/     timers, serial audio, controller matrix, wavetable
cart/      cartridge EEPROM
loader/    image detection and validated load plans
machine/   memory map, scheduler, interrupt wiring
debug/     disassemblers and read-only inspection
cli/       headless commands
host/sdl/  window, audio stream, input
cmd/       vjag (desktop) and vjag_test (headless)
jagkit/    assemblers and helpers for writing Jaguar programs in V
demos/     MAW, a game written with jagkit
```

Processors and devices only know the `Bus` interface from `hwtypes`. `machine` owns them all and is the bus. Nothing below `cli` touches a file, a clock or SDL, and the core does not allocate while it runs: a ten-second benchmark allocates about 12 KB in total.

All three processors share one timeline counted in ticks of the 26.59 MHz master clock. The scheduler runs each processor for at most 64 ticks, or up to the next device event, before the others catch up, so a mailbox written by the 68000 is seen by the DSP a few microseconds later, not a frame later.

On an M2 Max a simple homebrew program runs at about fourteen times real speed, and a commercial game that keeps both RISC processors busy at about four times.

## Tests

```sh
just fetch-tests   # once: downloads the 68000 corpus (MIT) into data/tests
just test
```

- **68000:** every case of [SingleStepTests/m68000](https://github.com/SingleStepTests/m68000) matches on registers, memory, cycle count and bus order. 317,500 of 317,500, no exclusions. Without the corpus the test says it was skipped.
- **Devices:** the object processor, blitter, RISC cores, EEPROM, controller matrix and timers have unit tests that check exact memory and register results.
- **Whole machine:** small hand-assembled programs boot through the real loader, run on the 68000, hand work to the GPU and publish a result word.
- **Loader:** synthetic fixtures for every format and every way a file can be truncated or lie about itself.

## Credits

Built from the Atari Jaguar Technical and Software Reference manuals and the original hardware errata. The CRY colour tables are hardware data, tabulated in MAME's Jaguar driver (BSD-3-Clause). The 68000 corpus is the work of the SingleStepTests project. Virtual Jaguar and BigPEmu showed what was possible.

The shell artwork was generated with an OpenAI image model, using Evan Amos's photographs of the console and controller on Wikimedia Commons as reference. `scripts/build-shell.py` turns the raw image into `host/sdl/shell.png`.

## Licence

MIT. See [LICENSE](LICENSE).
