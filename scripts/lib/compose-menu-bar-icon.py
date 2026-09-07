#!/usr/bin/env python3
"""Compose the menu bar template image from the committed source glyph.

    python3 scripts/lib/compose-menu-bar-icon.py <glyph.png> <out.png>

The menu bar wants a different animal from the app icon: a single-weight silhouette that macOS
tints itself, so it is right in a light bar, a dark bar and a bar tinted by the wallpaper. This
takes the black-on-white source glyph (`Packaging/Icon/MenuBarIcon-source.png`), turns its darkness
into alpha, trims it, and writes an 18 pt image with its 2x companion beside it. The file name ends
in "Template", which is how AppKit is told to tint it rather than draw it as art.

Nothing about the shape is invented here: the source glyph is the artwork, and this only measures,
trims and scales it.
"""

import sys

from PIL import Image

POINTS = 18
# The glyph's own height inside the 18 pt square, leaving the breathing room the menu bar expects.
GLYPH_POINTS = 15


def compose(source_path: str, out_path: str) -> None:
    source = Image.open(source_path).convert("L")
    # Black is the shape, white is the paper: darkness becomes coverage.
    alpha = Image.eval(source, lambda level: 255 - level)
    box = alpha.getbbox()
    if box is None:
        raise SystemExit(f"{source_path} is blank")
    alpha = alpha.crop(box)

    for scale, suffix in ((1, ""), (2, "@2x")):
        side = POINTS * scale
        height = GLYPH_POINTS * scale
        width = round(alpha.width * height / alpha.height)
        resized = alpha.resize((width, height), Image.LANCZOS)
        canvas = Image.new("L", (side, side), 0)
        canvas.paste(resized, ((side - width) // 2, (side - height) // 2))
        template = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        template.putalpha(canvas)
        path = out_path.replace(".png", f"{suffix}.png")
        template.save(path)
        print(f"composed {path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    compose(sys.argv[1], sys.argv[2])
