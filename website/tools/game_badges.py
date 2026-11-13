"""Original pixel scenes inspired by Jaguar games; no game assets or logos.

Regenerate with: uv run --project website/tools website/tools/game_badges.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "img" / "wall"
# File, original caption, inspiration. Captions deliberately avoid game logos.
GAMES = [
    ("podpilot", "POD PILOT", "Cybermorph"),
    ("websurfer", "WEB SURFER", "Tempest 2000"),
    ("citystomper", "CITY STOMPER", "Iron Soldier"),
    ("motiontracker", "SIGNAL LOST", "Alien vs Predator"),
    ("redplanet", "RED ALERT", "Doom"),
    ("mazerunner", "MAZE RUNNER", "Wolfenstein 3D"),
    ("skyislands", "SKY ISLANDS", "Rayman"),
    ("powderrun", "POWDER RUN", "Val d'Isère Skiing and Snowboarding"),
    ("apexchaser", "APEX CHASER", "Super Burnout"),
    ("junglefang", "JUNGLE FANG", "Primal Rage"),
]
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Tahoma Bold.ttf", 8)


def scene(index: int, t: int) -> Image.Image:
    im = Image.new("RGB", (88, 31), "#080b20")
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    bob = round(math.sin(t * math.pi / 4))
    if index == 0:
        d.rectangle((1, 1, 86, 21), fill="#19385c")
        d.polygon(
            [
                (1, 18),
                (14, 5),
                (29, 18),
                (46, 8),
                (64, 19),
                (77, 7),
                (87, 17),
                (87, 23),
                (1, 23),
            ],
            fill="#336747",
        )
        d.polygon([(1, 22), (28, 14), (51, 23)], fill="#599449")
        for x in (12, 69):
            d.ellipse((x, 16 + bob, x + 3, 20 + bob), fill="#ffdc51")
        d.polygon(
            [
                (33, 14 + bob),
                (45, 8 + bob),
                (57, 14 + bob),
                (46, 13 + bob),
                (42, 17 + bob),
            ],
            fill="#a4e0da",
        )
        d.line([(35, 14 + bob), (45, 11 + bob), (52, 14 + bob)], fill="#37aab0")
        d.point((43, 16 + bob), fill="#ff9947")
    elif index == 1:
        for r in (1, 2, 4, 7, 11):
            points = [
                (
                    44 + round(4 * r * math.cos(a * math.pi / 4)),
                    11 + round(r * math.sin(a * math.pi / 4)),
                )
                for a in range(8)
            ]
            d.line(points + [points[0]], fill="#7137ac")
        for a in range(8):
            d.line(
                (
                    44,
                    11,
                    44 + round(44 * math.cos(a * math.pi / 4)),
                    11 + round(11 * math.sin(a * math.pi / 4)),
                ),
                fill="#28cdec",
            )
        x = 47 + t * 4
        d.line((x, 13, x + 3, 11, x + 5, 14), fill="#ff475c", width=2)
        d.polygon([(37, 21), (41, 17), (45, 21), (49, 17), (53, 21)], fill="#fff568")
    elif index == 2:
        d.rectangle((1, 1, 86, 22), fill="#402d49")
        for x, h in ((3, 11), (17, 17), (31, 8), (62, 14), (76, 19)):
            d.rectangle((x, h, x + 9, 23), fill="#182538")
            for y in range(h + 2, 22, 4):
                d.line((x + 2, y, x + 6, y), fill="#e3b64f")
        d.rectangle((42, 3 + bob, 51, 7 + bob), fill="#aeb7ae")
        d.line((44, 5 + bob, 49, 5 + bob), fill="#fa6547")
        d.polygon(
            [(40, 8), (53, 8), (56, 15), (50, 17), (42, 16), (37, 12)], fill="#727f82"
        )
        d.line((42, 16, 40 - bob, 22), fill="#c2ccc3", width=4)
        d.line((50, 16, 54 + bob, 22), fill="#9daaa8", width=4)
        d.line((54, 10, 63, 12), fill="#ccd5c9", width=3)
        if t % 4 < 2:
            d.polygon([(64, 9), (71, 12), (64, 15)], fill="#ffb347")
    elif index in (3, 4, 5):
        palettes = [
            ("#28564e", "#071b1b", "#69f7a3"),
            ("#944a35", "#301a23", "#ffad57"),
            ("#647a8f", "#232e46", "#ffe298"),
        ]
        wall, dark, light = palettes[index - 3]
        d.rectangle((1, 1, 86, 22), fill=dark)
        for k in range(4):
            x, y = 2 + k * 9, 1 + k * 2
            d.line([(x, 22), (x, y), (87 - x, y), (87 - x, 22)], fill=wall, width=2)
            d.line((x, y, 36, 9), fill=wall)
            d.line((87 - x, y, 51, 9), fill=wall)
        d.rectangle((36, 9, 51, 20), fill="#06090e")
        if index == 3:
            d.arc((5, 8, 29, 32), 180, 360, fill=light)
            d.line((17, 20, 12 + t * 2, 10), fill=light)
            d.point((23, 14), fill=light)
            d.line((42, 12, 44, 12), fill="#ffb646")
        elif index == 4:
            d.polygon([(38, 22), (40, 16), (47, 16), (50, 22)], fill="#9ea7af")
            d.rectangle((42, 14, 46, 20), fill="#555c64")
            if t % 4 == 0:
                d.polygon([(39, 14), (42, 10), (44, 12), (47, 9), (49, 14)], fill=light)
        else:
            for x in (7, 70):
                d.line((x, 10, x, 17), fill="#b4a080", width=2)
                d.ellipse((x - 2, 6 + t % 2, x + 2, 10), fill=light)
            d.rectangle((40, 19, 47, 22), fill="#b5aaa0")
    elif index == 6:
        d.rectangle((1, 1, 86, 22), fill="#467ac2")
        for x in (7, 37, 67):
            d.ellipse((x, 4, x + 14, 8), fill="#bce8e8")
        for x, y in ((1, 18), (34, 14), (67, 19)):
            d.ellipse((x, y, x + 21, y + 7), fill="#8a5170")
            d.line((x + 2, y, x + 19, y), fill="#a9e76a", width=3)
        d.ellipse((43, 5 + bob, 48, 10 + bob), fill="#ffe271")
        d.line((45, 11 + bob, 44, 13 + bob), fill="#fff2c3", width=2)
        for x in (25, 58):
            d.point((x, 11 + bob), fill="#ffdd6b")
    elif index == 7:
        d.rectangle((1, 1, 86, 22), fill="#86c9dc")
        d.polygon([(1, 18), (22, 3), (36, 17), (53, 1), (86, 21)], fill="#d9e7ed")
        d.polygon([(1, 22), (39, 9), (87, 22)], fill="#fff4e8")
        for x, y in ((18, 9), (66, 15)):
            d.polygon([(x, y - 4), (x - 4, y + 4), (x + 4, y + 4)], fill="#24635a")
        d.ellipse((43, 9 + bob, 46, 12 + bob), fill="#ffdb9f")
        d.line((44, 13 + bob, 47, 17), fill="#e14364", width=3)
        d.line((46, 17, 42, 21), fill="#20375e", width=2)
        d.line((39, 21, 48, 20), fill="#e9544c")
        d.line((49, 20, 55, 18), fill="#e9544c")
    elif index == 8:
        d.rectangle((1, 1, 86, 22), fill="#dc8263")
        d.ellipse((62, 3, 72, 13), fill="#ffe68f")
        d.polygon(
            [(1, 17), (12, 8), (28, 17), (48, 9), (64, 17), (85, 8), (87, 22)],
            fill="#565072",
        )
        d.polygon([(39, 11), (49, 11), (78, 23), (8, 23)], fill="#3c4252")
        for y in (13 + t % 3, 19 + t % 3):
            d.line((44, y, 43, y + 2), fill="#fff0c2")
        d.ellipse((39, 17, 42, 23), fill="#090f22")
        d.ellipse((46, 17, 49, 23), fill="#090f22")
        d.polygon([(39, 19), (41, 14 + bob), (47, 14 + bob), (50, 19)], fill="#e43456")
        d.ellipse((42, 10 + bob, 46, 14 + bob), fill="#fff3d7")
    else:
        d.rectangle((1, 1, 86, 22), fill="#263c42")
        d.ellipse((60, 2, 72, 14), fill="#d5cfa0")
        for x in (6, 24, 77):
            d.line((x, 1, x + 4, 23), fill="#18282d", width=4)
            d.polygon([(x - 6, 1), (x + 13, 2), (x + 6, 7)], fill="#467554")
        d.rectangle((1, 21, 86, 23), fill="#86754b")
        d.polygon(
            [
                (25, 18),
                (36, 13 + bob),
                (43, 13 + bob),
                (47, 7 + bob),
                (56, 7 + bob),
                (59, 11 + bob),
                (51, 12 + bob),
                (47, 18),
                (35, 19),
            ],
            fill="#a1bb67",
        )
        d.line((36, 18, 33 - bob, 22), fill="#a1bb67", width=3)
        d.line((44, 17, 48 + bob, 22), fill="#a1bb67", width=3)
        d.point((54, 8 + bob), fill="#fff3ae")
    # A small footer leaves most of the button to the actual illustration.
    d.rectangle((1, 22, 86, 29), fill="#070b13")
    caption = GAMES[index][1]
    d.text(
        ((88 - d.textlength(caption, font=FONT)) // 2, 22),
        caption,
        font=FONT,
        fill="#f6edcb",
        anchor="lt",
    )
    d.rectangle((0, 0, 87, 30), outline="#87949e")
    d.line((1, 29, 86, 29), fill="#26313e")
    return im


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (name, _, _) in enumerate(GAMES):
        frames = [scene(i, t) for t in range(8)]
        frames[0].save(
            OUT / f"{name}.gif",
            save_all=True,
            append_images=frames[1:],
            duration=140,
            loop=0,
            optimize=True,
        )
    print(f"Drew {len(GAMES)} original illustrated badges")


if __name__ == "__main__":
    main()
