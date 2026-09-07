# Media provenance and artwork

The Kaiju, Cat and UFO character packs and both icons were generated for MonsterDeleter.
No artwork from the original [531149627/MonsterDeleter](https://github.com/531149627/MonsterDeleter)
is included. The app implementation is independent; that project's desktop toy and show are
credited as inspiration in the [README](../README.md#credits--inspiration).

## Generation sources and license scope

| Shipped material | Generation and preparation |
| --- | --- |
| Six PNG sheets in each of `Packaging/packs/kaiju/`, `cat/` and `ufo/` | Nano Banana character designs and seed stills through KIE; Seedance motion clips; local sheet cutting and backdrop matting. |
| `bgm.wav`, `voice.wav`, `explosion.wav` in each pack (nine sounds total) | Suno V5 through KIE's `suno:sounds`; converted to mono 44.1 kHz, 16-bit WAV. These are generated sounds, not CC0 recordings. |
| `Packaging/Icon/AppIcon-source.png` | Nano Banana Pro through KIE, using the project's Kaiju as reference; Recraft background removal. |
| `Packaging/Icon/MenuBarIcon-source.png` | Nano Banana through KIE, generated as a monochrome glyph. |
| App icon master and menu bar templates | Local composition from the committed generated sources. |
| `docs/images/*-kick.png` | Unmodified app-rendered checkpoint captures of the three generated characters, with no desktop content. |

Original source, scripts and documentation are [MIT licensed](../LICENSE). Generated media in
`Packaging/packs/`, `Packaging/Icon/` and its copies or depictions in `docs/images/` is outside
that grant. KIE [advertises commercial use](https://kie.ai/suno-api); outputs remain subject to
applicable provider terms, including [KIE's terms](https://kie.ai/terms-of-use). This repository
does not grant a separate MIT sublicense for those outputs. The procedural placeholder and its
self-test references are produced by the app's original source code.

## Recompose the icons

```sh
scripts/make-icon.sh --render
```

This uses Pillow and the two committed source images. `scripts/lib/compose-icon.py` makes the
1024 px master with an 824 px artwork region. `scripts/lib/compose-menu-bar-icon.py` makes the
18 pt and 36 px menu bar templates. The app icon is colored artwork; the menu bar icon is a
silhouette with holes that AppKit tints. Neither is derived from the other. Normal app builds
use the committed master and macOS `sips`/`iconutil`, without generating new artwork.

## Sheet preparation

The [pack format](adr/0003-character-packs.md) specifies the manifest. `scripts/pack-sheet.sh`
accepts a motion clip, time window, crop, grid, inset and fade parameters; its header documents
all arguments. It uses ffmpeg, Python, NumPy and Pillow. `scripts/lib/backdrop-matte.py` measures
the backdrop per frame; [ADR-0006](adr/0006-pack-art-on-a-magenta-backdrop.md) explains why.
Work in the ignored `.pack-work/` directory. Model generation is not deterministic; the shipped
sheets are the canonical build inputs, and the original motion clips are not required to build.

- Generate against flat magenta, a color no character wears. Avoid broad near-black surfaces
  facing the backdrop: spill on them can become unwanted partial transparency. This is not a
  ban on near-black outlines or detail. Avoid thin dangling props that look like stray legs.
- Settle the rescuer's framing first. Both figures must share one frame, fixing the scale the
  other sheets need. State the figure's fraction of frame height and foot position in seed
  prompts. A later crop can enlarge a small figure but cannot restore paint clipped by the model.
- Crop width controls scale when that axis binds. Crop height shifts the foot line within the
  padded cell. Keep the kick and rescue handover consistent; `ShippedPackTests.rescueHandover`
  checks the shipped pairs.
- Cat's `rescuer.png` and `fly.png` also use `scripts/pack-strands.py` to clear thin remnants below
  the vacuum. Re-cutting alone regrows those remnants. This alpha-only pass is specific to that
  prop and may erase legitimate paint on another character.
- Scaling the sheet can bleed edge paint into an adjacent cell. Frames next to an empty tail
  must leave that shared edge clear or fade out. `--inset F` and `explosionHeight / F` retain
  on-screen size when an inset is needed. Mid-bloom frames may touch their cell edges.
- On a 15-frame kick sheet, `kickImpactFrame` must leave time for the explosion checkpoint
  4.5 frame slots later. The shipped maximum is 10. The manifest alone does not enforce this.
- A pack's tint colors the ask paper, so it must remain light enough for the fixed dark ink.
  `ShippedPackTests` enforces 4.5:1 contrast and checks sheet slicing, transparency, timing,
  sound files and the empty explosion tail. Do not weaken those gates to accept new artwork.
