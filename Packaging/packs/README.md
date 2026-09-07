# Built-in packs

Every folder here with a `pack.json` is copied by `scripts/build-app.sh` into
`Contents/Resources/packs/` of the app bundle before the bundle is signed, and shows up in the
menu as a built-in pack (`docs/adr/0003-character-packs.md` has the format). This file and
anything without a `pack.json` are left out.

`kaiju/`, `cat/` and `ufo/` contain artwork generated for this project and cut into sheets by
`scripts/pack-sheet.sh`. [Media provenance and authoring constraints](../../docs/artwork.md)
document the models, sounds, icon composition and sheet preparation. `ShippedPackTests` keeps
every built-in pack loadable. Upstream MonsterDeleter artwork is not included in these packs.
