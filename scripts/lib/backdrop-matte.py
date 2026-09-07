#!/usr/bin/env python3
"""Pull a colour-difference matte off frames shot against a flat magenta backdrop.

    backdrop-matte.py <frames-dir> [--lo L] [--hi H] [--fade N]

Every `*.png` in the directory is replaced by an RGBA version of itself with the backdrop gone.

A fixed-colour key cannot do this job. Generated footage lights its own backdrop: a fireball washes
the magenta from `#FF00FF` towards white, and a moving figure drags a gradient across it, so the
backdrop is a different colour in every frame and in every part of every frame. Keying one constant
colour leaves whatever drifted away from it, and being a yes-or-no test it also has nothing to say
about smoke, which is genuinely half transparent.

So the backdrop is measured instead of assumed. Magenta-ness is `(min(R, B) - G)` over the pixel's
own brightness: high on the backdrop, zero on grey smoke and white paint, negative on the fire and
on the teal and yellow the characters are painted in. Taking it as a fraction of brightness rather
than an absolute is what clears the soft shadows and the pools of light the figures cast on the
backdrop, which an absolute measure reads as half a character and leaves as smudges.

A quadratic surface fitted to the frame's outer ring gives the backdrop's own colour everywhere,
including behind the character, and one refitting pass drops the ring pixels the subject is standing
in front of.

Alpha is then how much of that magenta-ness a pixel is missing, which lands smoke at a half cover it
deserves, and the colour comes back by inverting the compositing equation the camera performed:
`foreground = (observed - (1 - alpha) * backdrop) / alpha`. That removes the magenta the backdrop
spilled onto the silhouette, so no fringe survives to be scaled later.

A last unspill pass takes the magenta the screen bounced onto the figures themselves back out, which
is what stops the rescuer's white cape and boots coming back pink. It only ever touches pixels where
`min(R, B)` sits above `G`, and that is true of nothing these characters are painted in: the teal,
the orange, the yellow and the cream all have a channel below their green. Choosing a backdrop
colour the art does not use is what makes the whole of this safe.

`--fade N` then dissolves the last N frames away. An explosion sheet has to end on an empty frame,
because the app leaves its last frame on screen until the flight begins, and a generated fireball
leaves a cloud of smoke standing there instead of clearing.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

# A pixel missing this little of the backdrop's magenta-ness is still backdrop, which is what
# clears the bright pool of light the figures cast around their own feet; one missing `HI` or more
# is solid character. Between them alpha ramps, which is what carries smoke. Smoke wants a smaller
# lift than a figure does, hence --lo.
LO, HI = 0.22, 0.88
# The outer ring the backdrop surface is fitted from, as a fraction of the shorter side.
RING = 0.06
# Ring pixels this far below the fitted surface are the subject leaning into the frame edge, and
# the surface is fitted again without them.
OUTLIER = 0.55


def _basis(ys, xs, height, width):
    """The quadratic terms of a surface over normalised image coordinates."""
    u = xs / width - 0.5
    v = ys / height - 0.5
    return np.stack([np.ones_like(u), u, v, u * u, u * v, v * v], axis=-1)


def _fit(values, ys, xs, height, width, full):
    coefficients, *_ = np.linalg.lstsq(_basis(ys, xs, height, width), values, rcond=None)
    return full @ coefficients


def magenta_of(image):
    """How magenta a pixel is, as a fraction of its own brightness, so shadows read the same."""
    return (np.minimum(image[..., 0], image[..., 2]) - image[..., 1]) / np.maximum(
        image.max(axis=-1), 8.0
    )


def backdrop(frame):
    """The backdrop's own RGB at every pixel, fitted from the frame's outer ring."""
    height, width, _ = frame.shape
    ring = max(2, int(round(min(height, width) * RING)))
    mask = np.zeros((height, width), bool)
    mask[:ring] = mask[-ring:] = True
    mask[:, :ring] = mask[:, -ring:] = True
    ys, xs = np.nonzero(mask)
    grid = np.indices((height, width))
    full = _basis(grid[0].ravel(), grid[1].ravel(), height, width)

    magenta = magenta_of(frame)
    fitted = _fit(magenta[ys, xs], ys, xs, height, width, full).reshape(height, width)
    keep = magenta[ys, xs] > fitted[ys, xs] * OUTLIER
    if keep.any() and not keep.all():
        ys, xs = ys[keep], xs[keep]

    planes = [_fit(frame[ys, xs, c], ys, xs, height, width, full).reshape(height, width) for c in range(3)]
    return np.stack(planes, axis=-1)


def matte(frame, lo=LO, hi=HI):
    """Straight (unpremultiplied) RGBA for one frame, backdrop removed and despilled."""
    ground = backdrop(frame)
    reference = np.maximum(magenta_of(ground), 0.02)
    cover = np.clip(magenta_of(frame) / reference, 0.0, None)

    alpha = np.clip((1.0 - cover - lo) / (hi - lo), 0.0, 1.0)
    solid = alpha[..., None] > 0
    colour = np.where(
        solid,
        (frame - (1.0 - alpha[..., None]) * ground) / np.maximum(alpha[..., None], 1e-3),
        0.0,
    )
    spill = np.clip(np.minimum(colour[..., 0], colour[..., 2]) - colour[..., 1], 0.0, None)
    colour[..., 0] -= spill
    colour[..., 2] -= spill
    return np.dstack([np.clip(colour, 0, 255), alpha * 255]).astype(np.uint8)


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    directory = Path(argv[0])
    lo, hi, fade = LO, HI, 0
    rest = argv[1:]
    while rest:
        flag, value, rest = rest[0], rest[1] if len(rest) > 1 else None, rest[2:]
        if flag == "--lo" and value is not None:
            lo = float(value)
        elif flag == "--hi" and value is not None:
            hi = float(value)
        elif flag == "--fade" and value is not None:
            fade = int(value)
        else:
            print(f"backdrop-matte: unknown option {flag}", file=sys.stderr)
            return 2

    frames = sorted(directory.glob("*.png"))
    if not frames:
        print(f"backdrop-matte: no frames in {directory}", file=sys.stderr)
        return 1
    for index, path in enumerate(frames):
        frame = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
        rgba = matte(frame, lo, hi)
        left = len(frames) - index
        if 0 < left <= fade:
            rgba[..., 3] = (rgba[..., 3] * ((left - 1) / fade)).astype(np.uint8)
        Image.fromarray(rgba, "RGBA").save(path)
    print(f"backdrop-matte: matted {len(frames)} frames in {directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
