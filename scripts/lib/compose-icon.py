#!/usr/bin/env python3
"""Compose the app icon master from the committed source artwork.

    python3 scripts/lib/compose-icon.py <source.png> <out-1024.png>

The source is the generated character on a transparent background
(`Packaging/Icon/AppIcon-source.png`). This places it on the macOS icon grid: a 1024 canvas whose
artwork lives inside an 824 squircle with a 100 pt margin all round, which is what Apple's template
gives every Big Sur and later app icon, so MonsterDeleter sits at the same size as its neighbours in
the Dock and in Finder. The gradient behind it is the one the artwork was lit against, so the
character reads as standing in the tile rather than pasted on it.

Only Pillow is needed. Everything is drawn at 4x and resampled, so the squircle and the shadow have
no stair steps at 16 pt.
"""

import sys

from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
GRID = 824  # Apple's icon grid: the rounded square inside the 1024 canvas
MARGIN = (CANVAS - GRID) // 2
SUPERSAMPLE = 4
# The squircle's exponent: 5 is visibly rounder than a rounded rectangle's corner and matches
# Apple's continuous curvature closely enough that no one can tell them apart at 512.
SQUIRCLE_EXPONENT = 5.0
TOP_COLOUR = (142, 207, 174)
BOTTOM_COLOUR = (245, 231, 214)
# How much of the grid's height the character fills, and how far its feet sit above the bottom.
CHARACTER_HEIGHT = 0.86
FOOT_MARGIN = 0.05


def squircle_mask(size: int) -> Image.Image:
    """A superellipse the size of the grid, antialiased by drawing it big and shrinking it."""
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    pixels = mask.load()
    radius = big / 2
    for y in range(big):
        dy = abs((y + 0.5 - radius) / radius) ** SQUIRCLE_EXPONENT
        if dy >= 1:
            continue
        # |x/r|^n + |y/r|^n = 1, solved for x: every row is one horizontal run.
        half = radius * (1 - dy) ** (1 / SQUIRCLE_EXPONENT)
        for x in range(max(0, int(radius - half)), min(big, int(radius + half) + 1)):
            pixels[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def gradient(size: int) -> Image.Image:
    image = Image.new("RGB", (1, size))
    for y in range(size):
        blend = y / (size - 1)
        image.putpixel(
            (0, y),
            tuple(round(top + (bottom - top) * blend) for top, bottom in zip(TOP_COLOUR, BOTTOM_COLOUR)),
        )
    return image.resize((size, size))


def compose(source_path: str, out_path: str) -> None:
    source = Image.open(source_path).convert("RGBA")
    box = source.split()[3].getbbox()
    if box is None:
        raise SystemExit(f"{source_path} is empty")
    character = source.crop(box)

    tile = gradient(GRID).convert("RGBA")

    height = round(GRID * CHARACTER_HEIGHT)
    width = round(character.width * height / character.height)
    character = character.resize((width, height), Image.LANCZOS)
    left = (GRID - width) // 2
    top = GRID - round(GRID * FOOT_MARGIN) - height

    # A soft contact shadow under the feet, so the character stands on the tile.
    shadow = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [left + width * 0.10, top + height - GRID * 0.055, left + width * 0.90, top + height + GRID * 0.035],
        fill=(60, 80, 70, 90),
    )
    tile.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(GRID * 0.018)))
    tile.alpha_composite(character, (left, top))
    tile.putalpha(squircle_mask(GRID))

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.alpha_composite(tile, (MARGIN, MARGIN))
    icon.save(out_path)
    print(f"composed {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    compose(sys.argv[1], sys.argv[2])
