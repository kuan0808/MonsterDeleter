#!/usr/bin/env python3
"""Clear the thin parts a render hangs under a character-pack prop.

    pack-strands.py <sheet.png> [<sheet.png> ...] [--columns C] [--rows R] [--wide W]

A generated prop keeps growing parts the design does not have - a robot vacuum's
side brushes are the case this exists for - and at the size the show draws a
sheet they read as stray legs or whiskers rather than as part of the object.
They cannot be matted away: they are opaque paint inside the silhouette, so
`backdrop-matte.py` is right to keep them and no guard here sees them.

This exists for the Cat pack's robot vacuum and is applied to
`Packaging/packs/cat/rescuer.png` and `fly.png` only. It runs after
`pack-sheet.sh` and overwrites the sheet in place. In every frame it finds the
prop's body - the lowest row that is at least `--wide` pixels across - and
clears the alpha of anything painted below it that is thinner than five pixels.
A drive wheel survives; a hair does not.

That rule is the vacuum's, not a general one, so this is opt-in per sheet rather
than a routine step: on art it was not written for it erases legitimate paint,
measured at 716 px off `packs/kaiju/rescuer.png` and 363 px off its `walk.png`.
It clears a strand's core, the paint at alpha 64 and above, and leaves its soft
fringe deliberately: under a rim that fringe is mixed with the prop's own
antialiasing, so reaching it means eating the rim's edge with it.
Only alpha is written, so no colour is resampled and nothing is smeared, and it
is idempotent: a second run over the same sheet clears nothing.

Needs numpy and Pillow for python3, which the matte already needs.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

THIN = 5  # a part this many pixels thick anywhere is structure, not a strand


def components(mask):
    """Every 8-connected component of `mask`, as boolean arrays."""
    seen = np.zeros_like(mask)
    height, width = mask.shape
    for start in zip(*np.nonzero(mask & ~seen)):
        if seen[start]:
            continue
        part = np.zeros_like(mask)
        stack = [start]
        seen[start] = part[start] = True
        while stack:
            y, x = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = part[ny, nx] = True
                        stack.append((ny, nx))
        yield part


def is_thick(part, size=THIN):
    """Whether `part` holds a solid `size` by `size` block, which a wheel does and a hair does not."""
    filled = part.astype(np.int32)
    box = filled.cumsum(axis=0).cumsum(axis=1)
    box = np.pad(box, ((1, 0), (1, 0)))
    total = box[size:, size:] - box[:-size, size:] - box[size:, :-size] + box[:-size, :-size]
    return bool((total == size * size).any())


def strip(path, columns=5, rows=3, wide=50):
    """Clear the strands from every frame of the sheet at `path`. Returns pixels cleared."""
    sheet = np.array(Image.open(path).convert("RGBA"))
    height, width, _ = sheet.shape
    cell_width, cell_height = width // columns, height // rows
    cleared = 0
    for index in range(columns * rows):
        row, column = divmod(index, columns)
        cell = sheet[row * cell_height : (row + 1) * cell_height, column * cell_width : (column + 1) * cell_width]
        painted = cell[..., 3] >= 64
        body = np.nonzero(painted.sum(axis=1) >= wide)[0]
        if body.size == 0:
            continue
        below = painted.copy()
        below[: body.max() + 1] = False
        for part in components(below):
            if not is_thick(part):
                cell[..., 3][part] = 0
                cleared += int(part.sum())
    if cleared:
        Image.fromarray(sheet).save(path)
    return cleared


def main(argv):
    options = {"columns": 5, "rows": 3, "wide": 50}
    sheets = []
    while argv:
        argument = argv.pop(0)
        if argument.startswith("--"):
            options[argument[2:]] = int(argv.pop(0))
        else:
            sheets.append(argument)
    if not sheets:
        print(__doc__.splitlines()[2].strip(), file=sys.stderr)
        return 2
    for sheet in sheets:
        print(f"pack-strands: {Path(sheet).name}, {strip(sheet, **options)} pixels cleared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
