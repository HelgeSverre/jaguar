# Fight for Life menu performance

The slowdown comes from repeatedly copying the menu background through the general blitter implementation. It is a host execution bottleneck, and is much worse in the menu than in the sampled fight.

## Reproduction and cause

The normal `Fight For Your Life (1996).jag` image reaches the mode-selection menu with the existing A/B/C audit script. Measuring frames 300–360 gives approximately 249 blits and 4.88 million processed pixels per video field. The sampled fight at frames 1,200–1,260 processes about 57,000 pixels per field instead.

A native CPU sample attributes about 96% of main-thread samples to the blitter command path. The dominant command is `01800609`: a plain 16-bit source copy with destination reads enabled. It copies a 320×240 background from `$182FE8` into pitch-3 phrase storage. Despite doing a simple copy, the old path evaluates the general address generation, data selection, comparisons, depth and shading conditions for every pixel, with individual bus dispatches.

Disassembly confirms a repeating redraw/input loop at `$81CA64..$81CEA2`. It issues the background command at `$81CAE0`, polls blitter completion at `$81CAEA`, draws the selection overlays, updates the object-list data address through `$81A74E`, reads controllers through `$81A45A`, and loops. These calls do not wait for a new video field. Our `functional_v1` model completes each blit synchronously, so its busy polls return immediately and many backgrounds are copied within one field. This explains both the unusually large workload and why waiting longer eventually reaches gameplay.

The diagnostic artifacts are under `out/fight-perf-20261117/`: [benchmark source](../out/fight-perf-20261117/bench.v), [CPU sample](../out/fight-perf-20261117/menu-sample.txt), [captured commands](../out/fight-perf-20261117/commands.log), [drawing routine](../out/fight-perf-20261117/menu-loop-code.txt), [loop tail](../out/fight-perf-20261117/menu-wait-code.txt), and [controller routine](../out/fight-perf-20261117/menu-input-code.txt). The command capture stops at the diagnostic watcher's 4,096-write limit; the benchmark pixel/blit totals cover every command.

## Correction

The blitter can now request a forward row of 16-bit RAM copies through an optional bus capability. The machine validates both complete address ranges before accessing memory, then copies the pixels directly while preserving phrase pitch and word-by-word overlap ordering. Register writeback, pixel counts and address-generator stepping are unchanged.

The optimized path only accepts plain source copies with positive unit X steps and no masking, clipping, comparisons, shading or depth operations. Non-RAM addresses, bank-boundary crossings and unsupported modes use the original implementation. RAM aliases are resolved before copying. A refused request does not partially modify memory.

This is a general host optimization, with no title/hash detection, skipped draws or altered guest clocks. It retains the existing instantaneous-blitter timing approximation and does not remove any hardware quirk. More accurate busy/bus timing remains separate work.

## Measurements

Adjacent unprofiled runs of the same 60-frame section:

| Section | Before | After |
|---|---:|---:|
| Mode-selection menu | 121.59 ms/frame | 11.13 ms/frame |
| Actual fight | 5.15 ms/frame | 4.58 ms/frame |

The menu measurement improves from roughly 8 to 90 host frames/second. Host load varied during the investigation, so this is a measured pair, not a guaranteed speedup on every machine. Process user CPU time for the complete menu harness, including boot/warmup, drops from 8.36 to 1.71 seconds. [Before](../out/fight-perf-20261117/menu-before-clean.log), [after](../out/fight-perf-20261117/menu-after-clean.log), [before CPU time](../out/fight-perf-20261117/menu-before-clean-time.log), [after CPU time](../out/fight-perf-20261117/menu-after-clean-time.log).

Both benchmark sections retain byte-identical screenshots, identical full main-RAM hashes, processor PCs, master ticks, blit counts and pixel counts. Tests compare the optimized console bus against a scalar RAM bus across 26 cases, including the actual background dimensions, all phrase pitches, partial phrases, overlapping copies, aliases, address wrapping and fallback modes. Separate tests verify that rejected rows leave memory untouched. The seven focused optimized test files pass; the new copy tests also pass in a debug build.

The 900-frame sweep of all 139 local images preserves every recorded result field except elapsed host time. All 828 captured PNG files are byte-identical to the preceding baseline. A separate 1,800-frame Fight for Life run with the gameplay script produces identical PNG, WAV and diagnostic dump files before and after the change. [Verification](../out/fight-perf-20261117/regression-verification.json), [sweep](../out/fight-perf-20261117/sweep.json), [gameplay commands](../out/fight-perf-20261117/gameplay-runs.json), [focused tests](../out/fight-perf-20261117/focused-tests.log).

These checks validate the optimization against the previous behavior. They do not establish full-game compatibility or cycle-accurate hardware timing.
