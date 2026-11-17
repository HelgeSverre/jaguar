# Cross-emulator investigation — 17 November 2026

The deeper pass fixed Music Demo’s invisible text and Hover Strike’s missing terrain. Both were emulator defects. The [subsequent I-War investigation](iwar-investigation.md) corrects this report’s earlier polygon-failure diagnosis: Phoenix and Virtual Jaguar reproduce the same mission-transition and tank-destruction effects. Fight for Life reaches gameplay. PAULA remains inconclusive, with different failures in the tested emulators.

## Reference and image identity

I ran the local images in Virtual Jaguar libretro 3.12.0, commit `8543bbffaf021971726852bf39de52791db412f7`. Its source checkout is clean. The tested production library has SHA-256 `ebb76ec9d8356bc1851c844537b7f9aac0a80f26444aa8f6ed44b23a07eef3ad`. A separate diagnostic library relinks the same object files with internal symbols exposed; it does not change processor or device implementations.

For this initial comparison, BigPEmu was checked against its author's [published compatibility table](https://www.richwhitehouse.com/jaguar/index.php?content=compat), not run locally. A later local launch did not yield a validated gameplay capture; see the I-War follow-up. These local files exactly match its published 64-bit FNV-1a hashes and are listed as Excellent:

| Local image | Matching published hash |
|---|---|
| Fight For Your Life (1996) | `C56B6F168A80E5EE` |
| Hover Strike (1995) | `67C944EE0406FAD9` |
| I-War (1995) | `99A14C375429A786` |
| Kasumi Ninja (1994), without `[a1]` | `392906008D83777E` |

The alternate images do not inherit those compatibility claims. [Image identities](../out/cross-emulator-20261117/image-identities.json) record file sizes, SHA-256, CRC32 and FNV-1a. No ROM was changed or replaced.

## Results and causes

| Title / image | Cross-check | Conclusion |
|---|---|---|
| **Music Demo (ScatoLOGIC)** | Virtual Jaguar displays text and produces audio. Coherent blitter aliases restore the text here; the correction is now in production and has a regression test. | **Fixed emulator defect.** PATD and intensity shared storage was missing. The 900-frame library verdict improves from blank to animated. |
| **Hover Strike** | The image matches BigPEmu’s Excellent entry. A live TOM timer-counter read restores terrain here, including a 3,600-frame run. | **Missing-terrain cause fixed.** Its elapsed-time routine previously always computed zero. Remaining font bit-expansion differences are separate; full playability is not certified. |
| **I-War** | Phoenix 2.8.25 and new Virtual Jaguar sequences reproduce the scattered polygons at mission transition and at zero energy. Movement, shooting and datapod collection work here. | **Earlier visual-failure diagnosis withdrawn.** The sampled “holes” were game animations compared at different gameplay states. Separate captured blitter discrepancies remain valid fixes; this does not certify the whole game. See the [follow-up](iwar-investigation.md). |
| **Fight for Life, normal image** | Both emulators exceed their initial audit time limits while the generic script remains in the menus. A direction-and-button script reaches character selection and then an actual fight in both. | **Menu host-performance bottleneck addressed.** The menu repeatedly copies a full background through the generic blitter. A guarded RAM-copy path reduces the new benchmark from 121.59 to 11.13 ms/frame, retaining the screenshot and guest state. The original timeout was not a demonstrated hang. See the [performance investigation](fight-for-life-performance.md); full playability remains unverified. |
| **Fight for Life `[a1]`** | Both emulators reach its menus, then exceed the generic-script time limit. Virtual Jaguar's independent matrix records HLE boot success but real-BIOS rejection for this alternate image. | **Separate performance and image-authentication questions.** Do not label it a crash from the timeout, or apply the normal image's BigPEmu hash result to it. The new gameplay script was tested on the normal image. |
| **PAULA Preview Demo 2** | Virtual Jaguar stays silent through 3,600 frames. Diagnostic sampling finds the CPU polling DSP control at `$008EAE..$008EB2`, the DSP stopped at `$F1B12C`, and its control register retaining interrupt latch bit `$80`. Its TOM timer remains disabled. Here initialization proceeds further, then the GPU timer interrupt uses `r31=0` and returns outside local RAM. | **Unresolved shared compatibility / initialization issue.** Virtual Jaguar's “boots and runs” label does not establish functioning audio. It stalls before the timer path that fails here. There is no evidence yet that justifies declaring the image damaged, inventing an initial GPU stack, or changing the hardware's IMASK semantics. |
| **Kasumi Ninja `[a1]`** | Reproduced the failure in Virtual Jaguar; its independent matrix identifies the same `$80B780` fault and BIOS rejection. The ordinary local Kasumi image matches BigPEmu's working hash. | **Unusable alternate image.** Invalid startup code, rather than the title generally being unsupported. |
| **Fight for Life `[a2]`** | Reproduced failure in Virtual Jaguar; its matrix identifies invalid startup at `$8020AC` and BIOS rejection. | **Unusable alternate image.** This is the 2 MiB variant, not the normal 4 MiB image that reaches gameplay. |
| **Assassin Part 1 for BJL** | Both fail, but their automatic loaders choose different addresses. The local image also has invalid startup instructions / hardware addresses compared with its working sibling. | **Suspect image / format.** Cross-emulator failure alone is insufficient because the load environments differ. Establish the original BJL encoding and load address before assigning all blame to damaged bytes. |
| **BadCode4 Metal `[a1]`** | Both fail. Virtual Jaguar's matrix records the `$004A4C` exception. Our automatic `$5000` placement and explicit `$4000` placement both fail; the latter jumps into `$FFFF` where the working sibling has executable code. | **Unresolved image/layout problem.** There is no verified original load/link address, so this is not a proven emulation defect or a proven damaged dump. |

The corroborating Virtual Jaguar [boot matrix at the tested revision](https://github.com/libretro/virtualjaguar-libretro/blob/8543bbffaf021971726852bf39de52791db412f7/docs/cart-boot-matrix.md) identifies images by size and CRC32. Boot classification and watchdog notes require interpretation; PAULA is a concrete example of why they are not a gameplay test.

## Blitter diagnosis

Music Demo's alias experiment is a causal check: it changes blitter register storage in an isolated copy, without changing the demo, loader, CPU, GPU or DSP. Its previously black text becomes readable and closely matches Virtual Jaguar. Atari describes these aliases on pp.76–77 of the [revision 8 Technical Reference](https://www.hillsoftware.com/files/atari/jaguar/jag_v8.pdf); Virtual Jaguar implements them in [blitter_mmio.c](https://github.com/libretro/virtualjaguar-libretro/blob/8543bbffaf021971726852bf39de52791db412f7/src/tom/blitter_mmio.c). This is missing ordinary register behaviour, not a silicon bug to preserve.

For Hover Strike and I-War, I captured RAM and all blitter registers immediately before and after real game commands, then replayed them against Virtual Jaguar with the same initial RAM and image. Hover Strike's sampled command 10,000 produced identical RAM changes in both engines; command 80,000 changed no RAM in either. I-War's command 10,000 changed the same 24 bytes in both, but five intensity bytes differed because the four computed lanes are selected in the opposite order. Its later textured command 1,000,000 produced identical RAM changes. That establishes a local shading discrepancy; it does not establish that the scattered polygons were incorrect, or rule out problems elsewhere in processor execution, scheduling or other blitter commands.

Those initial experiments were isolated. The subsequent fixes and expanded checks below supersede their production status; speculative timing, internal-memory-transfer and stack-seeding changes remain diagnostic only.

## Deeper pass: confirmed corrections

**Hover Strike’s terrain failure comes from timer readback.** The routines at `$807846` and `$807856` read `$F00050`, swap its words, and subtract successive samples. The result is stored at `$1D5C7C`. Returning the reload registers makes that elapsed interval zero. Changing only the readback to the current down-counters restores terrain. [Disassembly](../out/deep-20261117/hover-timer-code.txt), [before](../out/deep-20261117/hover-step.png), [timer-only experiment](../out/deep-20261117/hover-timer.png), [production build at frame 3,600](../out/deep-20261117/hover-final.png).

The original chip implementation resolves a documentation discrepancy: [IODEC.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/IODEC.NET) decodes PIT reads, and [MISC.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/MISC.NET) connects the live `tp` and `t` counters to them through `Dtp` and `Dt`. This supersedes the manual’s write-only label. The implementation derives readback from the existing event deadline; reads do not advance time or reschedule interrupts. It retains the scheduler’s slice resolution and existing timer-reprogramming approximation.

Other corrections now in production:

| Defect | Evidence and regression |
|---|---|
| Separate PATD/SRCD and intensity/Z storage; reversed phrase longwords | Music Demo supplies luminance through PATD. Tests exercise both alias directions, preservation of chroma, fractional source data, and four distinct phrase pixels. |
| Reversed computed lanes and advancement of only a used lane | I-War starts strips inside a phrase. All four interpolation lanes must advance at the phrase boundary, including masked lanes. A two-pixel strip crossing a boundary fails before the fix. |
| Computed depth wraps at its bounds | Positive and negative depth increments now saturate. Both boundary tests failed before the fix. |
| Unsigned luminance offset in ADDDSEL | Hover Strike’s `$FD` fade operand is -3. Tests cover subtraction, underflow, saturation and wrapping. |
| Blitter pointer reads always zero | Intentionally implement the silicon’s wrong read addresses: A1_FLAGS and A2_MASK. [BLITGPU.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/BLITGPU.NET) decodes these addresses. No dependency by the two investigated games was established; the comment does not claim one. |
| DIV uses bit 31 as the working sign | [DIVIDE.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/DIVIDE.NET) explicitly requires 33-bit arithmetic. Divisors above `$80000000` failed. Tests compare non-overflowing quotients with independent integer arithmetic, while retaining non-restored remainders and divide-by-zero behavior. |
| MMULT uses the alternate bank and discards its final address | Source bank 1 is absolute. [TOM SYSTOLIC.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/tom/SYSTOLIC.NET) and [JERRY SYSTOLIC.NET](https://github.com/Torlus/JagNetlists/blob/e13d5120cdf3f0e5b3d9e865b331a3a4f692cd38/netlists_org/jerry/SYSTOLIC.NET) advance the live ten-bit matrix address counter. Tests cover both processors, either active bank, consecutive operations, column stride and wrapping. |

The shading, saturation, signed-offset and alias rules are specified in the [Atari reference](https://www.hillsoftware.com/files/atari/jaguar/jag_v8.pdf), pp.74, 76–77 and 81–82. These fixes restore specified behavior; they do not remove silicon errata. In particular, no change was made to the documented ADDDSEL/SRCSHADE-with-Z pipeline fault based merely on visual disagreement.

### I-War replay results and corrected interpretation

At frame 1,200, correcting lane selection and phrase-wide advancement changes the sampled blit replay from 7,796 mismatches in 10,562 samples to zero. The tank still appears fragmented. Subsequent comparisons identify this as its destruction animation at ENERGY 000, not evidence of a remaining polygon defect. The earlier isolation results remain useful but must be interpreted with that correction:

- Feeding Virtual Jaguar’s resulting RAM back after 1,055,466 blits still produces the fragmented tank. This is now consistent with the observed game animation. The experiment tests output writes using our game’s inputs, not a complete replacement of blitter register semantics.
- The separately excluded 2,247 GPU-code-upload blits were replayed with identical GPU-local RAM as well as system RAM. All local-RAM results match.
- Object-processor replay matches all 246 tested lines in I-War and 249 in Hover Strike at the sampled field. This does not prove event timing or all descriptor writeback behavior.
- Sampled GPU and 68000 execution produced no demonstrated arithmetic mismatch in these game paths. Device-register reads without matching device state are not counted as instruction defects. The GPU check excludes branches, stores and accumulator-dependent instructions.
- A one-tick scheduler quantum, matrix-only correction, depth-test suppression and several register-layout experiments do not establish a fix. Nested branches were not observed in the instrumented I-War run.
- The sampled GPU polling loops at `$F03A7C` and `$F03B18`, and the CPU loop at `$70F6`, test only the blitter's idle bit. Virtual Jaguar's additional diagnostic status bits do not change those decisions. [Disassembly](../out/deep-20261117/iwar-status-code.txt).

The [Phoenix/MAME follow-up](iwar-investigation.md) withdraws the earlier categorical “confirmed emulator defect” verdict for these screenshots. No additional emulator patch was required to obtain normal gameplay, death and respawn. The above experiments are not proofs that entire subsystems are correct. [Replay harness](../out/deep-20261117/blitdiff.c), [GPU-upload results](../out/deep-20261117/iwar-local.log), [object-processor results](../out/deep-20261117/iwar-opdiff.log), [source and artifacts](../out/deep-20261117/).

Hover Strike also exposes a separate font-mask discrepancy: SRCENX/BCOMPEN byte expansion does not match the reference. Replacing those blits improves text but does not itself restore terrain. That path still needs a complete implementation and its own regression coverage.

### PAULA clarification

The no-input probe emits a brief nonzero audio burst (peak 15,120) before becoming silent; it is inaccurate to call our entire run silent. Seeding an otherwise-uninitialized GPU interrupt stack prevents the observed runaway but does not restore video or sustained sound. That seed is diagnostic, not a validated boot-state fix. Virtual Jaguar’s earlier CPU/DSP handshake stall remains a different failure. [Unmodified boot state](../out/deep-20261117/paula-noinput-0.jsonl), [seeded-stack experiment](../out/deep-20261117/paula-noinput-1.jsonl).

### Regression verification

The final 900-frame comparison covers all 139 images, using the previous review build as baseline. Baseline: 122 animated, 12 blank, four static, one load error. Final: 123 animated, 11 blank, four static, one load error. Music Demo is the only verdict change; none worsens. [Full results](../out/deep-20261117/final-sweep/audit.json), [exact runner](../out/deep-20261117/final-sweep/audit.rb).

The final 3,600-frame sweep also attempted all 139 images, retaining the 90-second per-image limit. Compared with the previous review build's 3,600-frame results, Music Demo is again the only verdict change and none worsens. Final totals: 106 animated, 16 static, 14 blank, two timeouts and one load error; no crash classifications. The Fight for Life menu timeouts and unsupported KEYB image remain separately explained above. These classifications do not certify gameplay or rendering accuracy. [Long-run results](../out/deep-20261117/long-sweep/audit.json), [runner](../out/deep-20261117/long-sweep/audit.rb), [comparison and binary hash](../out/deep-20261117/verification-summary.json), [source hashes](../out/deep-20261117/source-hashes.json).

The final focused optimized suite passes all ten test files in `risc`, `tom`, `machine` and `cli`. New regressions were run failing before their fixes. [Test result](../out/deep-20261117/final-focused-tests.log). Visual checks remain necessary: Hover Strike’s verdict was already “animated” while its terrain was absent, and I-War still passes that superficial activity test.

The final build also reaches an actual Fight for Life bout at frame 1,200 with the title-specific script. Music Demo, started with B at frame 180, displays its playing status through frame 3,600 and produces nonzero audio (peak 16,224). These are targeted smoke checks, not full playthroughs. [Fight for Life capture](../out/deep-20261117/fight-final.png), [Music Demo capture](../out/deep-20261117/music-playing.png), [audio](../out/deep-20261117/music-playing.wav).

## Inputs, captures and limits

The six-title comparison attempted 3,600 frames per image with a 180-second process limit. Both Fight for Life variants timed out; the other four completed. The initial Virtual Jaguar run used its defaults, which enable per-title visual presets for Hover Strike and I-War. Both were rerun for 1,200 frames with these explicit settings:

```text
virtualjaguar_pertitle_defaults=disabled
virtualjaguar_internal_resolution=1x
virtualjaguar_true_color=disabled
```

The generic input sequence is identical to the earlier audit. The Fight for Life gameplay script adds six separate Down presses to reach Begin Game, followed by confirmation presses through character selection. Both emulators were run to frame 1,200 with that script. Their final gameplay images differ because simulation timing differs; reaching a fight does not certify identical rendering or an entire playthrough.

Local evidence:

- [Run records and exact arguments](../out/cross-emulator-20261117/results.json)
- [Comparison runner](../out/cross-emulator-20261117/compare.rb), [generic inputs](../out/cross-emulator-20261117/buttons.press), [Fight for Life gameplay inputs](../out/cross-emulator-20261117/fight-game.press)
- [Native-rendering comparison: this emulator left, Virtual Jaguar right](../out/cross-emulator-20261117/retail-native-comparison.png)
- [Alias experiment: diagnostic build left, Virtual Jaguar right](../out/cross-emulator-20261117/alias-comparison.png)
- [Fight for Life here](../out/cross-emulator-20261117/fight-game-ours.png) and [in Virtual Jaguar](../out/cross-emulator-20261117/fight-game-other.png)
- [PAULA reference processor state](../out/cross-emulator-20261117/paula-other-timers.txt), [our timer writes](../out/cross-emulator-20261117/paula-timer-writes.txt)
- [I-War captured-command differences](../out/cross-emulator-20261117/iwar-blit-diff.txt)

These artifacts are local and ignored by Git. No physical-console tests were performed. Agreement between emulators is supporting evidence; it is not a reason to remove a documented hardware quirk.
