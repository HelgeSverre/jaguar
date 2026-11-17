# I-War: additional emulator comparison — 17 November 2026

The previous claim that I-War’s scattered polygons were a confirmed emulator defect was wrong. Phoenix 2.8.25 and Virtual Jaguar reproduce the same effects: the scene assembles from polygons when entering the mission, and the tank separates into polygons when ENERGY reaches 000. Our earlier frame-1,200 comparison paired a dying tank here with an active tank in Virtual Jaguar. Equal frame numbers did not mean equal game state.

This follow-up adds actual Phoenix and MAME runs, reruns Virtual Jaguar with controlled input, and attempts BigPEmu automation. No emulator implementation or ROM bytes were changed in this follow-up. The earlier, independently tested blitter corrections remain in place; this finding does not invalidate their register/arithmetic evidence.

## Image and references

All runs use `data/roms/I-War (1995).jag`, 2,097,152 bytes:

```text
SHA-256  2a94182c49934eeda292ba1a8961dee55a861cdf4f19b304ead775bf977c4380
SHA-1    3db485aaa28a817f468739a85e3f25741c3855ad
MD5      5a66b96ede209f251b00e0e06723826c
FNV-1a64 99A14C375429A786
```

Phoenix’s author lists this exact MD5/SHA-1 as 100% compatible since 2.8.11 in the [Jaguar compatibility table](https://www.arts-union.ru/node/66). That published rating is separate from the narrower local checks below. BigPEmu’s [published table](https://www.richwhitehouse.com/jaguar/index.php?content=compat) also matches the image’s FNV hash.

Phoenix and MAME use a Jaguar boot ROM with SHA-1 `f8991b0c385f4e5002fa2a7e2f5e61e8c5213356`. MAME’s wave ROM has SHA-1 `58117e11fd6478c521fbd3fdbe157f39567552f0`. Both match MAME 0.264’s `-listroms` output. The bytes came from the existing Virtual Jaguar source checkout’s BIOS/wavetable arrays.

## Actual runs

| Emulator | Test | Observed result |
|---|---|---|
| This emulator, current working tree | Two 3,600-frame runs: idle after menu selection; then controlled movement and firing. Captures every 30 frames from frame 300. | Mission entry, intact world, movement, firing, a collected datapod and score 1,000, damage, tank destruction and respawn. Both runs complete. |
| Virtual Jaguar libretro 3.12.0, commit `8543bbffaf021971726852bf39de52791db412f7` | Same image and the same two input scripts, 3,600 frames each. Per-title defaults and true-colour rendering disabled; internal resolution 1×. | Both runs exit successfully. The idle sequence reproduces the fragmented tank at zero energy and subsequent regeneration. The moving run also collects a datapod. Timing and exact positions differ. |
| Phoenix 2.8.25, official macOS Intel build under Rosetta | Real-BIOS boot, keyboard controller, light tank, Alpha Matrix. Manual movement check plus a new captured idle lifecycle. Threaded GPU/DSP disabled; VSync enabled for the final capture run. | Solid tank in the tunnel, scene materialization, ordinary first-person gameplay, ENERGY 000 destruction, respawn, and finally GAME OVER followed by the title screen. The apparent earlier “return to title” is explained by the captured game-over sequence, not established as a reset bug. |
| MAME 0.264, Ubuntu 24.04 ARM64 package | Real BIOS; 3,600 frame callbacks with A/B/C input. Snapshots every 600 callbacks; CPU/GPU/DSP PCs logged. Sound disabled. | Reaches gameplay and completes, but severe vertical stripes affect both HUD and scene. This is a different rendering failure and makes this version unsuitable as the visual reference. No claim about audio. |
| BigPEmu 1.221, official Linux ARM64 and x64 builds | Launch under Xvfb/software OpenGL; attempt an official-API input/frame diagnostic script. | **Inconclusive.** The bundled compiler fails on runtime-object/library paths. A diagnostic workaround produces an invalid VM module rejected with `Bad magic for VM module`. No validated gameplay/frame capture was obtained. This is a harness/environment failure, not evidence that I-War fails in BigPEmu. |

Phoenix was downloaded from its [official release page](https://www.arts-union.ru/node/23); BigPEmu from its [official download page](https://www.richwhitehouse.com/jaguar/index.php?content=download). The [MAME 0.264 driver itself](https://github.com/mamedev/mame/blob/mame0264/src/mame/atari/jaguar.cpp) warns that Jaguar support is poor and many titles have playability, blitter or performance problems. That warning does not diagnose the precise cause of our MAME stripes.

## The distinguishing evidence

![Same destruction effect at zero energy in three emulators](../out/iwar-multi-20261117/destruction-comparison.png)

The comparison preserves each HUD. Left: our idle frame 1,200, ENERGY 000, two lives. Centre: Virtual Jaguar idle frame 1,020, ENERGY 000, two lives. Right: Phoenix capture 08, ENERGY 000, two lives. Images are resized for comparison; the full originals remain in the artifact directory. These are corresponding game states, not claimed pixel-identical frames.

Our idle sequence shows an intact tunnel at frame 510, its transition at 540, a black frame at 570, scene construction at 600–660, ordinary gameplay by 720, and destruction at 1,170–1,320. ENERGY is 000 during the latter; `REGENERATING` appears at 1,290 and normal gameplay returns by 1,350. Virtual Jaguar and Phoenix both show the same ordered sequence. Phoenix capture 03 independently shows the scattered polygons during scene construction; captures 08–09 show tank destruction; capture 10 shows energy restored.

The generic audit input only cycles A/B/C. The original [Atari I-War manual](https://www.digitpress.com/library/manuals/jaguar/i%20war.pdf), control page (PDF page 7), identifies these as weapon selection, firing and special shields. Movement requires the directional controls. An unattended tank taking enemy fire therefore eventually dies; a screenshot of its destruction must not be treated as missing geometry.

To separate this from a stuck renderer, the new moving run holds Up and B for 300 frames beginning at frames 700 and 1,500, turns Right at 900 for 60 frames, and Left at 1,700 for 60 frames. Our frame 1,200 has score 1,000 and DATAPODS 7, reduced from 8. The world and camera respond to movement. Virtual Jaguar’s moving run also reaches score 1,000/DATAPODS 7. These checks establish meaningful gameplay interaction, not just changing pixels.

## Evidence and reproduction

Local artifacts are under `out/iwar-multi-20261117/` and ignored by Git:

- [Run verification, ROM/input hashes and capture counts](../out/iwar-multi-20261117/verification.json). Both local and Virtual Jaguar runs produced 111 scheduled captures each. At the time of this I-War follow-up, all 223 source files recorded by the preceding investigation retained their recorded SHA-256 hashes.
- [Diagnostic V harness](../out/iwar-multi-20261117/controlled.v), [idle inputs](../out/iwar-multi-20261117/idle.press), [movement inputs](../out/iwar-multi-20261117/move.press).
- [Our idle sequence](../out/iwar-multi-20261117/ours-idle-contact.png), [Virtual Jaguar idle sequence](../out/iwar-multi-20261117/vj-idle-small.png), [movement comparison](../out/iwar-multi-20261117/move-contact.png).
- [Phoenix lifecycle](../out/iwar-multi-20261117/phoenix-replay-contact.png), [original destruction capture](../out/iwar-multi-20261117/phoenix-replay/08.png), [scene construction](../out/iwar-multi-20261117/phoenix-replay/03.png).
- [MAME input/capture harness](../out/iwar-multi-20261117/mame-audit.lua), [completed run log](../out/iwar-multi-20261117/mame-audit.log), [striped gameplay](../out/iwar-multi-20261117/mame/frame-1200.png).
- [BigPEmu failed module log](../out/iwar-multi-20261117/bigpemu/debug_log.txt).

Run the local harness from the repository root:

```sh
v -prod -o out/iwar-multi-20261117/controlled out/iwar-multi-20261117/controlled.v
out/iwar-multi-20261117/controlled idle out/iwar-multi-20261117/idle.press
out/iwar-multi-20261117/controlled move out/iwar-multi-20261117/move.press
```

The Virtual Jaguar frontend accepts the same `.press` scripts with `--holds-file`; the exact source is [front-probe.c](../out/cross-emulator-20261117/front-probe.c). Its core options are `virtualjaguar_pertitle_defaults=disabled`, `virtualjaguar_internal_resolution=1x`, and `virtualjaguar_true_color=disabled`. Phoenix input is manual and is not frame-synchronized with either harness.

## Remaining limits

This clears the specific screenshots previously labelled as polygon failures. It does not establish a full playthrough, exact timing, audio fidelity, saving, two-player operation or all tank/weapon combinations. The runs reach corresponding events at different frame numbers; that difference needs a controlled timing investigation and hardware reference before being called a particular emulator defect. No physical-console test was performed.

No silicon erratum was changed or newly asserted. These are observed game animations, so adding a hardware-quirk comment or suppressing the effects would misrepresent the evidence. Future visual checks should match mission, energy, lives and camera state before diagnosing geometry from a single frame.
