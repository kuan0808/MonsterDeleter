# Sign every build with the Hardened Runtime, keep assembly and signing apart, and package without Xcode

Phase 7 needs a personal build that installs on the developer's Mac and a path to public
distribution that adds nothing but a certificate and a notarization step. `scripts/build-app.sh`
assembles the bundle first (executable, `Packaging/Info.plist`, `AppIcon.icns` built from the
committed 1024 px master, every built-in pack folder from `Packaging/packs/`) and then signs it in
one `codesign` call: the identity from `CODESIGN_IDENTITY` (ad hoc by default), the Hardened
Runtime on every build, the same entitlements and identifier every time, a secure timestamp only
for a Developer ID identity (`scripts/lib/signing.sh` classifies it), so an ad hoc or
personal-team build never has to reach Apple's timestamp authority to sign.
`scripts/package.sh` reads the version from `Info.plist` and wraps the signed app as a zip (and a
DMG on request); `scripts/notarize.sh` submits that zip, staples and re-zips, and does nothing
until `NOTARY_PROFILE` is set. ADR-0001 deferred an Xcode project to "the distribution phase";
this ADR closes that door instead: the whole pipeline is a handful of shell scripts, CI runs the
assembling, signing and packaging ones on every push, and Xcode's archive and export flow would
only duplicate them.

## Considered options

- Hardened Runtime only for Developer ID builds: the personal build would then run with a
  different set of runtime restrictions than the one shipped, and a library-validation or
  entitlement problem would surface only at notarization time. Applying it always costs nothing
  here (no plugins, no JIT, no injected libraries) and keeps one build behaviour.
- Committing `AppIcon.icns`: a binary that drifts from its source. Committing the master PNG
  and the drawing script keeps the icon reproducible, and `sips` plus `iconutil` take a second.
- Copying built-in packs during signing, or signing the packs separately: resources are sealed
  by the bundle's own signature, so the only rule that matters is "assemble everything, then sign
  once"; a pack added after signing breaks the seal.
- An Xcode project for archive, export and notarization: adds a generated artefact to keep in
  sync with `Package.swift`, and its export options plist would just re-encode the identity and
  the entitlements the scripts already carry.

## Consequences

- An ad hoc build is rejected by `spctl --assess` by design; Gatekeeper only trusts Developer
  ID, and a locally built app has no quarantine flag, so it launches without a prompt anyway.
  `scripts/check-app.sh` verifies the resulting bundle.
- Public distribution is `CODESIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=...
  scripts/notarize.sh` and nothing else in this repo changes.
- The version lives in `Packaging/Info.plist` only; bump `CFBundleShortVersionString` and
  `CFBundleVersion` there and every artifact name follows.
- `AppBundleTests` checks the packaging inputs always and the assembled bundle when it exists,
  so CI builds the bundle before `swift test`.
