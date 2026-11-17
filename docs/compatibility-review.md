# Compatibility review

This review covers the 139 local images in `data/roms`, including commercial games, alternate dumps, development utilities and demos. The comparison baseline is commit `d327cd5`. A successful boot or changing screenshot does not establish that a game is playable throughout.

The [17 November cross-emulator investigation](cross-emulator-investigation.md) refines these findings with identical-image Virtual Jaguar runs, BigPEmu hash checks and captured blitter replay. Normal Fight for Life reaches gameplay; its earlier timeout was not a demonstrated hang. The deeper pass also fixes Music Demo’s text and Hover Strike’s missing terrain. The [I-War follow-up](iwar-investigation.md) adds Phoenix and MAME tests and corrects the earlier polygon-failure classification: the sampled effects also occur in Phoenix and Virtual Jaguar during mission transitions and tank destruction.

## Initial library comparison results

All 139 images were attempted on both builds for 3,600 frames, with the same button script and a 90-second limit per process. There were no new crash, halt, timeout or load-error classifications. Both Ladybug variants changed from crashed to animated. Deliberate exits explain the apparent animation losses in Gorf, the Jaguar Server examples and SlamRacer Intro.

| Automated verdict | Original | Modified |
|---|---:|---:|
| Animated | 104 | 105 |
| Static picture | 15 | 16 |
| Blank | 15 | 15 |
| Crashed | 2 | 0 |
| Timed out | 2 | 2 |
| Load error | 1 | 1 |
| Total | 139 | 139 |

The [complete CSV](../out/review-20261116/results.csv) includes each image's SHA-256 and both verdicts; [audit.json](../out/review-20261116/audit.json) retains the counters and details. These local artifacts are ignored by Git. The defect table below qualifies the automated results: the remaining bad dumps, rendering failures and long-run slowdown mean **not all games work**.

## Corrections

| Problem | Correction and regression coverage |
|---|---|
| A failed EEPROM save was followed by reset, image replacement or quit, discarding unsaved progress. | Keep the session and display the failure; retry when storage becomes writable. The desktop test forces the temporary save path to be a directory and checks reset, switch, quit and successful recovery. |
| Programming either JERRY timer also restarted the other timer and serial audio clock. | Reschedule only the corresponding clock. Tests repeatedly program timer 1 while timer 2 and audio must continue. |
| `trace` never returned after a 68000 double fault. | Stop on `cpu_halted`, including while skipping instructions or tracing an inactive coprocessor. Reject invalid trace budgets. |
| PNG palette overflow silently made opaque pixels transparent. | Reject the asset build with its name and path when the automatic palette exceeds 256 entries. |
| Uploaded demos ended in `ILLEGAL` with no development monitor installed. | Provide an exception handler that parks the 68000 while devices continue. Preserve image-owned vectors, code and BSS, and leave cartridges alone. Tests verify the real exception stack and continued device activity. |
| Disabled TOM interrupts incorrectly set pending latches. | Apply the hardware enable gate before the pending latch. Tests cover a STOP object during a video interrupt handler's polling loop. |
| A processor's own FLAGS write selected the next register bank immediately. | Preserve the old bank for the instruction already in flight. Tests cover both processors, scheduler slices, pending interrupts and a FLAGS write in a branch delay slot. |
| The compatibility checker labelled execution through mirrored RAM as a crash. | Accept the populated RAM alias while continuing to reject vector-table addresses, odd addresses and the unpopulated DRAM bank. |

## Hardware behaviour preserved

The FLAGS delay is intentional emulation of a hardware pipeline effect. In ScatoLOGIC Music Demo, `STORE FLAGS; MOVEI stack,r31` initializes the **old** bank's interrupt stack. An immediate bank switch leaves that stack at zero, and the first interrupt returns the DSP to address zero. The original failure is recorded in `out/review-20261116/music-dsp-full.txt`; the corrected trace stays in DSP RAM. Atari documents the FLAGS hazard on pages 59 and 109 of the [Technical Reference revision 8](https://www.hillsoftware.com/files/atari/jaguar/jag_v8.pdf). The comments deliberately explain why the delay must remain. This is an instruction-level approximation, not a complete pipeline timing model.

TOM's enable-before-latch behaviour is visible directly in the original [MISC.NET chip design](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/MISC.NET): `Vip/Gip/Oip/Tip/Dip` feed the interrupt latches through the enable gates. Music Demo loops forever polling a disabled OP interrupt if that gate is omitted. The JERRY timer separation follows pages 85–86 and 91 of Atari's manual.

Ladybug and DEMO1C deliberately use `ILLEGAL` to return to the upload monitor. Their instruction streams and Virtual Jaguar's [direct-upload initialization](https://github.com/libretro/virtualjaguar-libretro/blob/master/src/core/jaguar.c) corroborate the convention. The correction supplies the missing environment; it does not suppress the CPU exception or modify the images.

No physical-console tests were performed. Uncertain hardware behaviour, including DSP external longword alignment, was not changed merely to match another emulator.

## Failures and cases requiring interpretation

| Image or family | Evidence and interpretation |
|---|---|
| Kasumi Ninja `[a1]` | Startup calls `$80B780`, which contains invalid opcode `$468E`. The other local Kasumi image boots. Virtual Jaguar reports the same fault address and BIOS rejection. This alternate image is unusable; changing CPU semantics would conceal the problem. |
| Fight For Your Life `[a2]` | Startup reaches invalid opcode `$713C` at `$8020AC`. The image is 2 MiB, versus 4 MiB for the other variants. Virtual Jaguar reports the same fault address and BIOS rejection. Size alone is not the diagnosis; the invalid startup code is decisive. |
| Assassin Part 1 for BJL | Its startup differs from the working same-size image in opcodes and hardware addresses, including `$F0xxxx` becoming `$95xxxx`. Both emulators fail, but automatic loading differs between them. The follow-up classifies this as a suspect image/format requiring the original BJL encoding and load address, rather than treating cross-emulator failure as proof of damage. |
| BadCode4 Metal `[a1]` | A startup call targets `$4A4C`; at a forced `$4000` base its destination begins with `$FFFF`, whereas the working sibling has executable code there. Forced `$4000` and the heuristic `$5000` placement both fail. Virtual Jaguar also faults at `$4A4C`. This is an unresolved image/layout problem: the original link/load address is needed to distinguish a damaged image from an unusual upload convention. |
| Fight For Your Life, normal and `[a1]` | The original menu timeouts did not establish a hang. The normal image reaches a fight in both emulators. The [performance follow-up](fight-for-life-performance.md) identifies repeated background copies and adds a general RAM-copy optimization, reducing the measured normal-image menu cost from 121.59 to 11.13 ms/frame with matching guest state. Complete playability and the alternate image's authentication question remain separate. |
| Hover Strike | **Missing terrain fixed in the deeper pass.** Its elapsed-time routine read constant TOM timer reload values and computed zero. Live counter readback restores terrain through 3,600 frames. Font-mask differences remain. |
| I-War | **Earlier polygon-failure classification withdrawn.** Phoenix and Virtual Jaguar reproduce the scattered scene-transition polygons and tank destruction at zero energy. Controlled runs here exercise movement, shooting, datapod collection, death and respawn. Full-game compatibility and precise timing remain unverified; see the [follow-up](iwar-investigation.md). |
| ScatoLOGIC Music Demo | **Text fixed in the deeper pass.** The initial interrupt/stack fixes restored execution and audio; coherent blitter PATD/intensity aliases now restore visible text. The 139-image comparison improves this title from blank to animated. |
| PAULA Preview Demo 2 | GPU interrupt entry occurs here with `r31 == 0`; the return-address store goes outside populated memory and the handler returns to zero. Virtual Jaguar also fails to produce audio, but stalls earlier in a CPU/DSP control-register handshake before enabling the timer. Its boot-success classification is not evidence that this demo functions. The image versus boot-environment attribution remains unresolved; do not invent a power-on stack value. |
| Drumpad | Silent with the generic A/B/C script, but keypad presses produce nonzero audio (peak 32768). Its black screen is not sufficient evidence of failure. |
| Drumpad2 | Blank video, but the button script produces nonzero audio. Classify it as an audio program, not a video boot failure. |
| PlaySFX | Installs a STOP-only object list, so blank video is expected. Keypad presses produce nonzero audio (peak 16256). |
| JAGOS update | Polls the development-server interface at `$E1FD00`/`$E1FE00`. That interface is not emulated. It is not a standalone game. |
| KEYB update | Loader explicitly rejects JAGR variant 10. Its protocol has not been implemented; it is not an ordinary type-2/type-3 executable. |
| Jaguar Server 50HZ and 60HZ | Small timing-setup utilities. They finish in the monitor loop through RAM's `$201000` alias. Blank output is not evidence of a failed game. |
| Jaguar Server 27OBJ, SCALE and SCALE3 | The generic buttons exit the examples. The 27OBJ trace restores the prior interrupt registers, writes `VMODE=$04C0` to disable video and executes `RTS`. Its final blank screen is deliberate; the original build's subsequent garbage execution is not a successful animation. |
| Gorf 2000 | The generic input script triggers an intentional `ILLEGAL` at `$0049BE`, immediately after a button-bit test. The modified build parks in the monitor with the scene intact; the original continues into invalid execution and is misleadingly labelled animated. Use a title-specific script that does not trigger its debugger-exit control. |
| SlamRacer Intro | The scripted sequence finishes the intro and returns through `RTS` at `$0101BA`; the processor then reaches the monitor through the RAM mirror. Its static end state is not evidence that the monitor broke active gameplay. |
| Chroma-Luma Mouse, JDC Example, Mandelbrot, PAULA Preview | A static result alone is inconclusive: these are a mouse-oriented tool, static demonstrations or an audio preview. The generic A/B/C script does not exercise every intended control. |

The independent image observations are consistent with Virtual Jaguar's [boot matrix](https://github.com/libretro/virtualjaguar-libretro/blob/master/docs/cart-boot-matrix.md). Agreement with another emulator is supporting evidence, not proof of correct hardware behaviour.

For the audio tools, the control check holds keypad `1` at frame 200, `2` at 400 and `3` at 600, each for 120 frames, in a 900-frame run. Nonzero samples establish a response, not musical fidelity. Checkered Flag's scripted run also retained a valid DSP PC and nonzero audio in each 900-frame interval through frame 3600; this does not clear every possible gameplay sequence.

## Reproducing the checks

The local evidence is under `out/review-20261116/`: baseline and modified executables, JSON results, sampled screenshots, CPU traces, audio probes and test logs. ROM images were not modified.

```sh
v -prod -o out/review-20261116/review-vjag_test cmd/vjag_test/main.v
out/review-20261116/review-vjag_test compat data/roms \
  --frames 900 --jobs 4 --report-json out/review-20261116/short.json
```

The longer audit uses one process per image, 3,600 frames, six screenshot samples and the same deterministic A/B/C script on both builds. Each image has a 90-second host-time limit so that a runaway cannot prevent later images from being tested. `bounded-audit.rb` records completed results incrementally in `audit.json`. Timeouts are reported explicitly and are not counted as successes. Full-level gameplay, every controller accessory, PAL operation and every save path require additional title-specific testing.

For the initial correction set, the debug suite passed all 74 test files (`VJOBS=4 v test .`). The optimized suite passed 73/73 test files; the subsequently added compatibility-classifier test and expanded RISC tests also passed separately with `-prod`. The desktop build completed a ten-frame SDL dummy-driver smoke run with a captured Ladybug image. Formatting and `v vet .` passed; vet retains existing notices and documentation warnings outside these changes.
