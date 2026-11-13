# The headless runner

`vjag_test` is the emulator without a window: it runs an image for a number of frames and reports. `vjag` accepts the same commands, so `vjag run …` works too.

```sh
just release                 # builds bin/vjag and bin/vjag_test
./bin/vjag_test <command> <image or directory> [options]
```

## Commands

| Command | Does |
|---|---|
| `inspect <image>` | describes how the image would be loaded: format, load address, entry point |
| `run <image>` | runs for `--frames` frames, then produces what the options ask for |
| `compat <directory>` | boots every image in a directory and writes a triage report |
| `bench <image>` | measures emulation speed with nothing holding it back |
| `trace <image>` | single-steps, keeps the last instructions of one processor, and prints them when a stop condition is met |

## Options for every command

| Option | Meaning |
|---|---|
| `--region ntsc\|pal` | television standard; default `ntsc` |
| `--format <kind>` | force the image kind: `cart`, `jagserver`, `abs`, `coff`, `rom`, `raw` |
| `--load-address <addr>` | load address for a raw image |
| `--entry <addr>` | entry point override |
| `--frames <n>` | frames to run |

Addresses are written with `0x` for hexadecimal; a bare number is decimal.

## `run`

| Option | Meaning |
|---|---|
| `--screenshot <png>` | save the last frame |
| `--wav <file>` | save the sound |
| `--video <ppm>` | save every frame as one stream of binary PPM images |
| `--video-from <n>` | first frame saved by `--video`; the `--wav` starts there too, so the two stay in step |
| `--press <button@frame[+n]>` | hold a pad button from a frame, for `n` frames (6 if left out); repeatable |
| `--eeprom-in <file>` | load a 128-byte EEPROM image before the first frame |
| `--eeprom-out <file>` | write the 128-byte EEPROM image after the last frame |
| `--dump` | print the processors, the video registers and the display list at the end |
| `--peek <addr[:len]>` | print memory at the end; repeatable |
| `--list <addr[:count]>` | disassemble 68000 code at the end; repeatable |
| `--watch-io <lo:hi>` | log every write to hardware registers in the range |

Buttons for `--press`: `up`, `down`, `left`, `right`, `a`, `b`, `c`, `option`, `pause`, `0` to `9`, `star`, `hash`.

```sh
# Start a game at frame 30, hold right for a second, look at the result.
vjag_test run demos/wirewing.jag --frames 200 --press b@30 --press right@60+60 --screenshot shot.png

# A film with sound: frames and audio from frame 120 on, joined with ffmpeg.
vjag_test run demos/maw.jag --frames 720 --video out/maw.ppm --video-from 120 --wav out/maw.wav
ffmpeg -framerate 60 -f image2pipe -c:v ppm -i out/maw.ppm -i out/maw.wav -pix_fmt yuv420p out/maw.mp4

# What is in the program's variables?
vjag_test run demos/hello.jag --frames 60 --peek 0x4000:64 --list 0x4000:20
```

## `trace`

| Option | Meaning |
|---|---|
| `--cpu m68k\|gpu\|dsp` | processor to follow; default `dsp` |
| `--tail <n>` | instructions to print; default 64 |
| `--stop-pc <addr>` | stop when the processor reaches an address |
| `--stop-range <lo:hi>` | stop when its program counter enters a range |
| `--watch <addr[:mask]>` | stop when the long at an address changes |
| `--skip <n>` | instructions to run before the stop conditions apply |

```sh
vjag_test trace game.j64 --cpu m68k --stop-range 0x0:0x400   # who jumped into the vectors?
vjag_test trace game.j64 --cpu m68k --watch 0x4912           # who overwrote this?
```

## `compat`

| Option | Meaning |
|---|---|
| `--report-json <file>` | write the report |
| `--screenshots <dir>` | save pictures of every image as it runs |
| `--jobs <n>` | parallel workers; default all cores |

Each image gets a verdict: `animated`, `static_picture`, `blank`, `crashed` or `load_error`. Comparing two reports is how a change to the emulator is checked against a collection of images: `just compat` writes `out/compat.json`.

## A second opinion

`scripts/crosscheck/run.sh` runs images in another emulator, the Virtual Jaguar libretro core, and leaves a picture from each emulator side by side in `out/crosscheck`. It fetches and builds the core on first use and needs git, make and a C compiler.

```sh
sh scripts/crosscheck/run.sh                  # the demos, 120 frames
sh scripts/crosscheck/run.sh 600 game.jag     # one image, 600 frames
```

It has found one bug in each direction so far: a table the GPU read from an unaligned address in a demo, and the emulator letting it.

`run.sh` runs the images plainly. For a game that needs input or a save, use its two parts directly; `run.sh` leaves the frontend at `out/crosscheck/front`, and `compare.v` needs only `v`.

| `front` option | Meaning |
|---|---|
| `--holds-file <file>` | pad holds, whitespace separated, in the form of `--press`: `up@120+36 a@130+5` (6 frames if the length is left out); no limit on the number |
| `--hold <run>` | one such run on the command line; repeatable |
| `--eeprom-in <file>` | 128 bytes put into the core's save RAM before the first frame |
| `--eeprom-out <file>` | the 128 bytes of save RAM after the last frame |
| `--shot <n>:<bmp>` | the picture after `n` frames, as `--frames n --screenshot` would give it; repeatable |
| `--pal` | PAL console (the core option `virtualjaguar_pal`) |
| `--var key=value` | any other core option |

The buttons are those of `--press`, except `7`, `8`, `9`, `star` and `hash`: the core reaches them only through a keypad device, and `front` refuses them. The EEPROM files are the same 128 big-endian bytes as the core's save RAM and as vjag's save file, so one file goes to both sides; `vjag_test run` takes `--eeprom-in` and `--eeprom-out` for that. The core exposes the EEPROM for every cartridge image, `.jag` and `.j64` alike (it needs no particular extension). A `.j64` of the same game starts one frame later in the core than in vjag: compare the core at frame n with vjag at n+1. Its chip starts out zeroed, vjag's erased to `0xffff`; a game that checks a record, as ghostgrid does, sees no good record either way.

`compare.v` takes pixel (x, y) of vjag's picture against (x+dx, y+dy) of the other, over the area both cover, and tells how many pixels it compared, how many differ by more than the tolerance in any channel, and the largest difference. The offset between the two pictures is (16, 3) and the colours agree to within 2 or so.

```sh
# Ghostgrid: pass the title, load a saved best time, look at the mission select.
echo 'a@5+3' > out/holds.txt
cc -I out/crosscheck/core/libretro-common/include -o out/crosscheck/front scripts/crosscheck/front.c
out/crosscheck/front out/crosscheck/core/virtualjaguar_libretro.dylib demos/ghostgrid.jag 120 \
    out/pick-other.bmp out/crosscheck/scratch --holds-file out/holds.txt --eeprom-in save.eep --eeprom-out after.eep
vjag_test run demos/ghostgrid.jag --frames 120 --press a@5+3 --eeprom-in save.eep --screenshot out/pick-vjag.png
v run scripts/crosscheck/compare.v out/pick-other.bmp out/pick-vjag.png --offset 16,3 --tolerance 2
# compared 77025 pixels, 0 differ by more than 2, max channel difference 1
```
