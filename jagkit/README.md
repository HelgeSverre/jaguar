# jagkit

A V module for writing Atari Jaguar programs in V: you call it from an ordinary V program, and a `.jag` image comes out.

| File | What it gives you |
|---|---|
| `m68k.v` | a 68000 assembler: instructions as methods, labels as strings |
| `risc.v` | the same for the GPU and the DSP |
| `objects.v` | display lists from a list of `Bitmap` descriptions |
| `hardware.v` | register addresses and NTSC/PAL display timing |
| `image.v` | the `.jag` writer, big-endian helpers, RGB to CRY |
| `font.v` | an 8x8 font |
| `synth.v` | a three-voice DSP synthesizer |

- **Guide:** [`docs/jagkit.md`](../docs/jagkit.md) walks through a complete program and covers the display list, the pad, sound, the GPU and testing.
- **Smallest example:** [`demos/hello`](../demos/hello/main.v). Run `just demo hello`.
- **Reference:** `v doc jagkit`, or the comments in the files above.
- **Larger examples:** `demos/wirewing`, `demos/maw`, `demos/hero`.

`image.v` uses the emulator's `tom` module for colour conversion, so the kit is used from inside this repository.

Programs built with it have only run in this emulator, never on real hardware.
