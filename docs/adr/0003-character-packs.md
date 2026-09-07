# Character packs are folders with a forgiving pack.json, sliced once into a per-pack cache

Phase 4 makes the characters, sounds and ask texts swappable while the choreography stays fixed. A pack is a folder: `pack.json` plus the sheets and sounds it names. The
manifest is decoded leniently on purpose, packs are hand-written by users and a typo must not
kill the show: every field is optional, unknown fields are ignored, a malformed value falls back
to the built-in default with a logged warning, and only a file that is not a JSON object rejects
the pack. A file the manifest declares must exist; a role it leaves out, or names no `file` for,
uses the default-named file when the folder has one and the built-in placeholder otherwise, so a
`pack.json` alone is a valid re-skin and an entry may carry only a grid or a volume. A grid the
manifest declares for a sheet the folder does not ship is dropped: the substituted placeholder
sheet is sliced with its own 5 x 3 grid, and the point range or impact frame that no longer fits
it falls back to the default for that grid. Sheets are scaled once so every frame is twice its
displayed height and kept as PNGs under
`~/Library/Application Support/MonsterDeleter/cache/<origin>/<pack>/`, keyed by the sheet file's
modification date, grid and frame height in the file name, so the show never decodes an original
sheet (the upstream explosion is 7200 x 5760).

## Considered options

- Strict `Codable` for `pack.json`: one missing comma or a wrong type would refuse the whole
  pack with a decoding error no pack author can read. Kept for encoding only; `PackManifest` is
  the single decoding path.
- Caching one PNG per frame: 90 files per pack, and `SheetSlicer` already cuts a scaled sheet in
  O(1) with `CGImage.cropping`. One scaled sheet per role instead.
- A Swift zip reader for installing packs: our own parser for a format the OS already unpacks.
  `PackArchive` lists entries with the system `unzip`, refuses any that would escape the pack
  folder before extracting into a scratch folder, validates there, and only then moves the
  folder into the user packs directory. What may be unpacked is capped at 1000 files and
  512 MB: the listing is checked first, and because a zip may understate its sizes the scratch
  folder is measured again once `unzip` has run, before anything is validated or moved.

## Consequences

- Pack identity is `<origin>/<folder name>` (`builtIn/kaiju`, `user/Placeholder-Blue`),
  so a user pack can never shadow a built-in one and the choice persists as a string in
  `UserDefaults`.
- A running show is dressed in the pack chosen at summon time; the swap button during the ask
  changes the frames, sounds, bubble and buttons and leaves the machine and its timing alone.
  The `ShowStage` keeps the choreography it was created with for the same reason: durations
  follow the show, while frame indices follow the pack on screen, so the held point frame after
  a swap is the new pack's own last point frame, clamped to its sheet.
- Built-in folder packs live in `Contents/Resources/packs/`; the generated placeholder needs no
  folder and no cache, and is not a pack anyone can choose
  (`docs/adr/0007-no-placeholder-fallback.md`). `Packaging/packs/kaiju/` is the first folder pack
  shipped that way.
- The tint is a colour for the bubble and buttons only; recolouring sprites would need the
  artwork's cooperation and belongs to the pack's own sheets.
