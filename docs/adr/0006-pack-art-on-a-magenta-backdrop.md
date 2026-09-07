# Pack art is generated on a magenta backdrop and matted by measuring it

A pack needs six sheets of transparent frames, and the art is generated. To avoid a separate model call for each frame
every time a window is re-cut, every character is designed to use no magenta and every clip is generated against a flat
`#FF00FF` backdrop, which `scripts/lib/backdrop-matte.py` pulls off for nothing. That choice binds
future packs: a pack whose art wants magenta in it has to pick another backdrop colour and change
the one expression that measures it.

## Why it is measured per frame rather than keyed

The obvious implementation, `ffmpeg`'s `colorkey` against `#FF00FF`, was written first and does not
work on generated footage, because the footage lights its own backdrop. Measured at the frame
corners, the Kaiju explosion clip's backdrop drifts from a magenta-ness of 0.83 to between 0.19 and
0.60 over four seconds and varies threefold across a single frame; a fixed key leaves behind
everything that drifted away from it. So the matte fits the backdrop's own colour per frame from the
frame's outer ring and derives alpha from how much of that a pixel is missing.

Three consequences of that shape are worth keeping, each of which fixed a defect visible in a cut
sheet (see [artwork constraints](../artwork.md#sheet-preparation)):

- Magenta-ness is a fraction of the pixel's own brightness, never an absolute, so shadows and pools
  of light the figures cast on the backdrop go with it instead of reading as half a character. That
  divisor binds the art as well as the backdrop colour does: a broad near-black surface facing the
  screen picks up spill it has almost no brightness to divide by, so it lands mid-ramp at any matte
  threshold and the desktop shows through the middle of a solid prop.
  `ShippedPackTests.cornersAreTransparent` catches the enclosed form of it, and the rest is a rule
  the art has to keep.
- Alpha is continuous rather than a yes-or-no test, which is the only way an explosion's smoke gets
  the partial cover it physically has.
- A final unspill pass removes the magenta the backdrop bounced onto the figures. It is safe only
  because no character wears magenta, which is the same constraint the backdrop choice already
  imposes.
