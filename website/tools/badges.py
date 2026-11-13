# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Draw the 88x31 badges for website/badges.html into website/img/wall/.

    uv run website/tools/badges.py

Fonts come from macOS (/System/Library/Fonts/Supplemental). Each badge is a
row in BADGES: file name, two lines of text, colours, and an animation.
"""

import colorsys
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "img" / "wall"
FONTS = Path("/System/Library/Fonts/Supplemental")
W, H = 88, 31


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


BOLD = "Tahoma Bold.ttf"
NARROW = "Arial Narrow Bold.ttf"
IMPACT = "Impact.ttf"
MONO = "Courier New Bold.ttf"
BLACK = "Arial Black.ttf"
COMIC = "Comic Sans MS Bold.ttf"
SMALL = "Tahoma.ttf"

# file, line 1, line 2, background, colour 1, colour 2, animation, font for line 1
BADGES = [
    ("vjag", "VJAG", "jaguar emulator", "#000000", "#ff2020", "#ffd700", "shine", IMPACT),
    ("powered", "POWERED BY", "VJAG", "#5d0000", "#ffffff", "#ffd700", "blink", BOLD),
    ("vjagtest", "$ vjag_test", "run --frames 900", "#000000", "#33ff33", "#33ff33", "cursor", MONO),
    ("jagkit", "JAGKIT", "68000 asm in V", "#1b2a4a", "#8fb4e8", "#ffffff", "none", IMPACT),
    ("jaggame", "JAGGAME", "zero assembly", "#2a1b4a", "#ff66ff", "#ffffff", "shine", IMPACT),
    ("ghostgrid", "GHOSTGRID", "stay out of the cone", "#071a1a", "#33e0d0", "#ffb000", "scan", IMPACT),
    ("maw", "MAW", "follow the green lane", "#200030", "#ff40ff", "#40ff40", "cycle", IMPACT),
    ("wirewing", "WIREWING", "where did you learn", "#000000", "#30d050", "#ffd060", "none", MONO),
    ("hero", "JAGUAR HERO", "five lanes", "#30001a", "#ff4090", "#ffd700", "blink", IMPACT),
    ("omega", "OMEGA", "OVERDRIVE 180 BPM", "#000000", "#ff3030", "#ff9900", "shake", IMPACT),
    ("roboplay", "ROBOPLAY", "the robot got an S", "#202020", "#c0c0c0", "#33ff33", "none", BOLD),
    ("vectors", "317,500", "68000 tests pass", "#002000", "#33ff33", "#ffffff", "count", BLACK),
    ("directboot", "DIRECT BOOT", "no boot rom", "#303030", "#ffd700", "#ffffff", "none", BOLD),
    ("noroms", "NO ROMS", "bring your own", "#000000", "#ff2020", "#ffffff", "blink", IMPACT),
    ("cry", "CRY COLOUR", "16 bits a pixel", "#000000", "#ffffff", "#ffffff", "rainbowtext", BLACK),
    ("tom", "TOM", "video + gpu + blitter", "#600000", "#ffd700", "#ffffff", "none", IMPACT),
    ("jerry", "JERRY", "dsp + timers + pad", "#003000", "#ffd700", "#ffffff", "none", IMPACT),
    ("m68k", "MC68000", "the general", "#c0c0c0", "#000080", "#000000", "none", BLACK),
    ("blitter", "BLITTER", "done before you ask", "#000040", "#00ffff", "#ffffff", "shake", IMPACT),
    ("objproc", "OBJECT PROC", "edits its own list", "#202000", "#ffff40", "#ffffff", "scan", NARROW),
    ("gpu", "GPU", "26.59 MHz RISC", "#000000", "#ff8000", "#ffffff", "shine", IMPACT),
    ("dsp", "DSP", "ten voices at once", "#001030", "#40a0ff", "#ffffff", "eq", IMPACT),
    ("eeprom", "EEPROM", "128 bytes of pride", "#2a2a00", "#ffd700", "#ffffff", "none", BLACK),
    ("pressfile", "a@3+1", "right@87+10", "#000000", "#33ff33", "#33ff33", "cursor", MONO),
    ("ntscpal", "NTSC + PAL", "60 Hz / 50 Hz", "#101010", "#ffffff", "#ff4040", "blink", BLACK),
    ("vlang", "V 0.5.2", "written in V", "#ffffff", "#5d87bf", "#536b8a", "none", BLACK),
    ("sdl3", "SDL3", "pixels + samples", "#173f5f", "#ffcc00", "#ffffff", "none", BLACK),
    ("just", "just run", "maw.jag", "#2b2b2b", "#66ff66", "#ffffff", "cursor", MONO),
    ("mit", "MIT", "take it, fork it", "#ffffff", "#a00000", "#000000", "none", BLACK),
    ("64bit", "64 BIT", "if you count right", "#cc0000", "#ffff00", "#ffffff", "blink", IMPACT),
    ("dothemath", "DO THE MATH", "2:47 music video", "#000000", "#ffd700", "#ff3030", "shine", IMPACT),
    ("ilovejag", "I LOVE MY", "JAGUAR", "#ff80c0", "#ffffff", "#c00000", "pulse", COMIC),
    ("jagcd", "JAGUAR CD", "not emulated (yet)", "#404040", "#c0c0c0", "#ff8080", "none", BOLD),
    ("homebrew", "HOMEBREW", "made in 2026", "#004000", "#40ff40", "#ffff40", "cycle", IMPACT),
    ("hardware", "REAL HARDWARE?", "flash cart owners", "#400000", "#ffffff", "#ffd700", "blink", NARROW),
    ("tempest", "TEMPEST 2000", "fan club", "#000000", "#ff00ff", "#00ffff", "cycle", NARROW),
    ("avp", "ALIEN VS", "PREDATOR fan", "#001800", "#80ff80", "#ffffff", "scan", IMPACT),
    ("ironsoldier", "IRON SOLDIER", "stomp club", "#303030", "#ff9030", "#ffffff", "shake", NARROW),
    ("cybermorph", "CYBERMORPH", "pack-in pilot", "#002040", "#00ffff", "#ffffff", "none", NARROW),
    ("keypad", "1 2 3 4 5 6", "7 8 9 * 0 #", "#111111", "#ff3030", "#ff3030", "none", MONO),
    ("controller", "17 BUTTONS", "on one pad", "#000000", "#ffffff", "#ff4040", "blink", BLACK),
    ("oddmachine", "THE ODD", "MACHINE", "#4a004a", "#ffd700", "#ff80ff", "pulse", IMPACT),
    ("y1993", "EST. 1993", "emulated 2026", "#202020", "#ffd700", "#c0c0c0", "none", BLACK),
    ("scanlines", "SCANLINES", "ON", "#000000", "#ffffff", "#33ff33", "scanlines", BLACK),
    ("webring", "JAG WEBRING", "<< prev  next >>", "#000060", "#ffff00", "#ffffff", "blink", BOLD),
    ("construction", "UNDER", "CONSTRUCTION", "#ffcc00", "#000000", "#000000", "stripes", IMPACT),
    ("getvjag", "GET VJAG", "NOW!!!", "#c00000", "#ffffff", "#ffff00", "pulse", IMPACT),
    ("crosscheck", "CROSSCHECK", "vs virtual jaguar", "#1a1a1a", "#40ff40", "#c0c0c0", "none", NARROW),
    ("bigpemu", "BIGPEMU", "respect", "#000000", "#ff4040", "#ffffff", "shine", IMPACT),
    ("cartridge", "CART EDITION", ".j64 ready", "#2a2a2a", "#e0e0e0", "#ffd700", "none", NARROW),
]


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def fit(text: str, name: str, start: int, width: int) -> ImageFont.FreeTypeFont:
    size = start
    while size > 6:
        f = font(name, size)
        if f.getlength(text) <= width:
            return f
        size -= 1
    return font(name, 6)


def bevel(d: ImageDraw.ImageDraw) -> None:
    d.line([(0, 0), (W - 1, 0)], fill=(255, 255, 255))
    d.line([(0, 0), (0, H - 1)], fill=(255, 255, 255))
    d.line([(0, H - 1), (W - 1, H - 1)], fill=(0, 0, 0))
    d.line([(W - 1, 0), (W - 1, H - 1)], fill=(0, 0, 0))


def frame(spec, t: int, n: int) -> Image.Image:
    name, l1, l2, bg, c1, c2, anim, f1name = spec
    back = rgb(bg)
    if anim == "cycle":
        r, g, b = colorsys.hsv_to_rgb(t / n, 0.8, 0.45)
        back = (int(r * 255), int(g * 255), int(b * 255))
    im = Image.new("RGB", (W, H), back)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    if anim == "stripes":
        for k in range(-4, 14):
            x = k * 10 + (t * 2) % 10
            d.polygon([(x, 0), (x + 5, 0), (x - 5, H), (x - 10, H)], fill=(0, 0, 0))
        d.rectangle([4, 4, W - 5, H - 5], fill=rgb(bg))
    if anim == "scanlines":
        for y in range(0, H, 2):
            d.line([(0, y), (W, y)], fill=(25, 25, 25))
    if anim == "eq":
        for i in range(10):
            hgt = int(4 + 8 * abs(math.sin(t * 0.9 + i * 1.7)))
            d.rectangle([4 + i * 8, H - 3 - hgt, 9 + i * 8, H - 3], fill=(20, 60, 120))
    f1 = fit(l1, f1name, 15, W - 8)
    f2 = fit(l2, SMALL if f1name != MONO else MONO, 10, W - 6)
    col1, col2 = rgb(c1), rgb(c2)
    if anim == "blink" and t % 2:
        col1, col2 = col2, col1
    if anim == "rainbowtext":
        r, g, b = colorsys.hsv_to_rgb(t / n, 1, 1)
        col1 = (int(r * 255), int(g * 255), int(b * 255))
    dx = dy = 0
    if anim == "shake":
        dx, dy = [(0, 0), (1, -1), (-1, 1), (1, 1)][t % 4]
    text1 = l1
    if anim == "count":
        text1 = f"{int(317500 * min(1, (t + 1) / (n - 2))):,}"
    if anim == "cursor" and t % 2 == 0:
        text1 = l1 + "_"
    scale1 = f1
    if anim == "pulse":
        scale1 = fit(l1, f1name, 15 - (t % 2) * 2, W - 8)
    y1 = 3 if l2 else 8
    w1 = scale1.getlength(text1 if anim != "cursor" else l1 + "_")
    d.text(((W - w1) / 2 + dx, y1 + dy), text1, font=scale1, fill=col1)
    if l2:
        w2 = f2.getlength(l2)
        d.text(((W - w2) / 2, 18), l2, font=f2, fill=col2)
    if anim == "shine":
        x = t * 14 - 20
        overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.polygon([(x, 0), (x + 8, 0), (x - 4, H), (x - 12, H)], fill=(255, 255, 255, 120))
        im = Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB")
        d = ImageDraw.Draw(im)
    if anim == "scan":
        y = (t * 4) % H
        d.line([(1, y), (W - 2, y)], fill=col2)
    bevel(d)
    return im


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    frames_for = {"none": 1, "blink": 2, "cursor": 2, "shake": 4, "pulse": 2, "count": 10}
    for spec in BADGES:
        anim = spec[6]
        n = frames_for.get(anim, 8)
        frames = [frame(spec, t, n) for t in range(n)]
        path = OUT / f"{spec[0]}.gif"
        delay = {"blink": 500, "cursor": 450, "shake": 70, "pulse": 300, "count": 120, "shine": 90}.get(anim, 110)
        if anim == "count":
            durations = [delay] * (n - 1) + [2500]
        elif anim == "shine":
            durations = [delay] * (n - 1) + [1500]
        else:
            durations = delay
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
    print(f"{len(BADGES)} badges in {OUT}")


if __name__ == "__main__":
    main()
