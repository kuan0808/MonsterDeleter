# Build the app as a SwiftPM package and assemble the bundle with a script

Status: accepted; the deferred Xcode project for distribution is superseded by ADR-0004, which
keeps the shell scripts for Developer ID packaging too.

Phase 2 needs a runnable personal build, fast `swift build` and `swift test` loops, and no
distribution yet. We build everything as one SwiftPM package (library, executable, tests) and
assemble `build/MonsterDeleter.app` with `scripts/build-app.sh` from `Packaging/Info.plist` and
`Packaging/MonsterDeleter.entitlements`, signed ad hoc or with a personal-team identity but always
with the same bundle identifier and entitlements. No Xcode project is checked in.

## Considered options

- Xcode project (or XcodeGen): gives archive, export, notarization and an app target with
  resources for free, but adds a generated artefact to keep in sync and makes `swift test`
  second-class. Deferred to the distribution phase, where Developer ID packaging needs it.
- SwiftPM executable run directly with `swift run`: no bundle, so no `Info.plist`, no
  `NSServices` entry, no `LSUIElement`, and a Dock icon. Not usable as the product.

## Consequences

- The `NSServices` declaration, `LSUIElement` and the bundle identifier live in `Packaging/`, not
  in a target's build settings; edit them there.
- Because signing is ad hoc by default, TCC grants (none are needed for the Services path) and
  LaunchServices records are keyed by the identifier and entitlements, which the script keeps
  stable across rebuilds. `scripts/run.sh` re-registers the bundle so pbs sees one app.
- Resources are generated in memory (placeholder pack); the built-in pack folders under
  `Packaging/packs/` are files, and the script copies them into `Contents/Resources`.
