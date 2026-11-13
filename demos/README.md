# Demos

Programs written with [`jagkit`](../jagkit/README.md). Each directory is a V program that writes the `.jag` file next to it, and has a test that boots that image in the emulator and uses it.

```sh
just run demos/maw.jag        # run an image that is already built
just demo maw                 # rebuild it from its V source first
v -prod test demos/maw/       # its test
```

| Demo | What it is | Size | Controls |
|---|---|---|---|
| [`hello`](hello/main.v) | the smallest complete program: text, a ball, a beep | 4 KB | arrows move; Z, X, C beep |
| [`hello2`](hello2/main.v) | `hello` again, written with [jaggame](../docs/jaggame/guide.md) and no assembly, plus a spinning coin, a scaled and a flipped sprite, and counting numbers | 13 KB | arrows move; Z, X, C beep |
| [`ghostgrid`](ghostgrid/main.v) | **first mission.** GHOSTGRID, a stealth trainer written with [jaguar](../docs/jaggame/guide.md) and no assembly: sneak through a depot bigger than the screen to the exit pad past four guards. Each guard has a state machine (patrol, suspicious, alert, search, return), a cone of amber light on the floor that walls cut and that is exactly what sees you, and ears. You walk, run (guards hear it), crouch behind cover (they cannot see you there) and knock on a wall (one comes to look). A clock, an alert indicator and an end screen with the time and the times seen. Art is made by [a small program](ghostgrid/art/make_art.v) and imported from PNG | 95 KB | arrows move; Z run, X crouch, C knock; Z or Enter after the mission plays again |
| [`plasma`](plasma/main.v) | a first GPU program: three waves, one picture a frame | 2 KB | none |
| [`wirewing`](wirewing) | a wireframe flying game | 8 KB | left and right bank, Down climbs, Up dives; Z, X, C start |
| [`maw`](maw) | a tunnel flyer | 438 KB | left and right turn the tunnel; Z, X, C start |
| [`hero`](hero) | a five-lane rhythm game | 506 KB | 1 to 5 play the lanes; Enter pauses, Tab goes back |

`hello` and `plasma` are the examples the [guide](../docs/jagkit.md) walks through. Keys are the emulator's defaults; on a pad the fire buttons are A, B and C.

All of them handle NTSC and PAL, and all run in this emulator and in Virtual Jaguar (`scripts/crosscheck/run.sh`). None has run on real hardware.

## GHOSTGRID

<p>
  <img src="../docs/screenshots/ghostgrid-guards.png" width="49%" alt="GHOSTGRID in the west hall: two guards in teal, each with an amber patch of lit floor in front of him that shows where he looks, the red and white figure at the bottom, purple cover blocks and the word CALM">
  <img src="../docs/screenshots/ghostgrid-alert.png" width="49%" alt="A guard with a red exclamation mark over his head chasing the figure, the word ALERT! in red at the top right">
</p>

GHOSTGRID is an original stealth trainer, built one slice at a time on jaggame. The first mission is done: start in the south west of the depot, reach the green pad in the north east. The red and white figure is you; the broad teal ones with the red lens are guards, the lens is on the side they look to, and the amber floor is what they see. Waiting, a place to crouch behind cover and one knock on a wall are what the way through needs (a robot that searches for an unseen way says so). [Chapter 3 of the guide](../docs/jaggame/guide.md#chapter-3-assets-rooms-and-collision) walks through the figure and the room, [chapter 4](../docs/jaggame/guide.md#chapter-4-state-machines-actors-and-guards) through the guards. Its tests: that robot plays the mission unseen on NTSC and PAL with the interpreter alongside, and a test for each rule (caught, heard, knocked, hidden, never stuck). It runs in Virtual Jaguar with the same picture, frame for frame.

## MAW

<p>
  <img src="../docs/screenshots/maw-title.png" width="49%" alt="The title screen of MAW: a logo and a scroller over a fractal tunnel">
  <img src="../docs/screenshots/maw-play.png" width="49%" alt="MAW in play: a ship in a fractal tunnel, an electric gate ahead and a green lane through it">
</p>

MAW is a tunnel flyer with a psytrance habit. Left and right turn the tunnel; follow the green lane through each gate, because the rest of the gate is live. The GPU draws the tunnel from a lookup table: a Julia set folded into a kaleidoscope for a wall, a palette that turns while you fly, fog, and a window on the table that wanders so the tunnel swerves. A gate is a few rings of the wall repainted with lightning every other frame. The DSP is a three-voice synthesizer and the 68000 runs the rules and the tune: 150 beats a minute, kick, rolling bass, acid line. Its test plays the game: it boots the image in the emulator, reads the game's variables through the assembler's symbol table and steers.

## WIREWING

<p>
  <img src="../docs/screenshots/wirewing-play.png" width="49%" alt="WIREWING in a banked turn over a green wireframe landscape">
  <img src="../docs/screenshots/wirewing-crash.png" width="49%" alt="WIREWING after a crash: WHERE DID YOU LEARN TO FLY?">
</p>

WIREWING is a wireframe flying game. Bank with left and right, pull back to climb, fly through the spinning beacons before the tank is dry. The GPU projects the corners of a rolling landscape around the eye, with perspective, bank and distance shading, and joins them with lines it draws itself, sixty pictures a second. Fly into a hill and the onboard computer has a remark ready. Its test flies it: an autopilot collects beacons, a dive ends in the ground, an empty tank ends the flight.

## Jaguar Hero

<p>
  <img src="../docs/screenshots/jaguar-hero-title.png" width="49%" alt="Jaguar Hero title screen">
  <img src="../docs/screenshots/jaguar-hero-play.png" width="49%" alt="Jaguar Hero mid-song: a 150 note streak on a neon highway">
</p>

Jaguar Hero is a five-lane rhythm game. Five original songs, from a 113 BPM synthwave anthem to a 180 BPM finale, are written as patterns in `songs.v` and played by a ten-voice DSP synthesizer with drums, bass, distorted rhythm guitar, keys, twin leads and a stereo echo. Each chart is derived from the song's lead guitar, so what you press is what you hear: miss a note and the guitar drops out. Play the lanes with keys 1 to 5 (or Left, Up, Right, B, A on a pad), pause with Enter. Its test has a robot read the chart out of memory and play the finale perfectly inside the frame budget.

| Song | Style | BPM |
|---|---|---|
| MIDNIGHT ENGINE | synthwave anthem | 113 |
| COLOSSUS | heavy half-time | 129 |
| IRON GALLOP | galloping rock | 150 |
| NEON SERAPH | neo-classical shred | 150 |
| OMEGA OVERDRIVE | frantic finale | 180 |

## PAL

Anything counted in frames runs a sixth slower at 50 Hz. The tunes are corrected: MAW plays a step every five frames instead of six, and Jaguar Hero advances the song twice on every fifth frame. Movement is not: MAW's tunnel and WIREWING's plane are a sixth slower on a PAL machine.
