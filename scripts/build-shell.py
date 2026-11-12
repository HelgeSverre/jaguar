# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Turn raw shell artwork into host/sdl/shell.png.

    uv run scripts/build-shell.py raw.png host/sdl/shell.png

The raw artwork has a transparent background and a flat magenta screen. This
cuts the screen out, trims the transparent margin and prints where the screen
and the round red buttons ended up, for the layout constants in
host/sdl/shell.v. The readout strip, keypad and eyes are black on black and
have to be measured by hand.
"""

import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

source, target = sys.argv[1], sys.argv[2]
image = np.array(Image.open(source).convert("RGBA")).astype(np.int32)
r, g, b, a = (image[..., i] for i in range(4))
height, width = a.shape

# The screen is the magenta or see-through region around the image centre.
magenta = (r > 120) & (b > 120) & (g < 0.6 * np.minimum(r, b))
labels, _ = ndi.label(magenta | (a < 200))
window = magenta[
    height // 2 - 150 : height // 2 + 150, width // 2 - 300 : width // 2 + 300
]
ys, xs = np.nonzero(window)
seed = labels[height // 2 - 150 + ys[0], width // 2 - 300 + xs[0]]
if seed == labels[0, 0]:
    sys.exit("the screen is connected to the background")
screen = ndi.binary_fill_holes(labels == seed)
# Widen the hole past the pink fringe where magenta blends into the bezel.
screen = ndi.binary_dilation(screen, iterations=7)
sy, sx = np.nonzero(screen)
top, bottom, left, right = sy.min(), sy.max(), sx.min(), sx.max()

# Buttons are saturated red, round, and below the screen.
red = (r > 170) & (g < 90) & (b < 90) & (a > 250)
red[:bottom, :] = False
blobs, _ = ndi.label(ndi.binary_closing(red, iterations=3))
buttons = []
for box in ndi.find_objects(blobs):
    h, w = box[0].stop - box[0].start, box[1].stop - box[1].start
    if 40 < w < 140 and 0.8 < w / h < 1.25:
        buttons.append((box[1].start + w // 2, box[0].start + h // 2, max(w, h) // 2))
buttons.sort()

# Cut the hole and soften its edge over two pixels.
alpha = a.astype(np.float64)
alpha[screen] = 0
distance = ndi.distance_transform_edt(~screen)
rim = (distance > 0) & (distance <= 2)
alpha[rim] *= distance[rim] / 2.0
image[..., 3] = alpha.astype(np.int32)

visible_y, visible_x = np.nonzero(image[..., 3] > 8)
y0, y1, x0, x1 = (
    visible_y.min(),
    visible_y.max() + 1,
    visible_x.min(),
    visible_x.max() + 1,
)
Image.fromarray(image[y0:y1, x0:x1].astype(np.uint8), "RGBA").save(
    target, optimize=True
)

print(f"size    {x1 - x0}x{y1 - y0}")
print(f"screen  x={left - x0} y={top - y0} w={right - left + 1} h={bottom - top + 1}")
for x, y, radius in buttons:
    print(f"button  cx={x - x0} cy={y - y0} r={radius}")
