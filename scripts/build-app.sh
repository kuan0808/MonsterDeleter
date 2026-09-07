#!/bin/sh
# Assemble build/MonsterDeleter.app from the SwiftPM executable and sign it.
#
#   scripts/build-app.sh [debug|release]
#
# Assembly (executable, Info.plist, both icons, built-in packs from Packaging/packs/) is one step and
# signing is another, so a public build only adds notarization (scripts/notarize.sh) after this.
#
# CODESIGN_IDENTITY selects the signing identity (default "-", ad hoc). Use a personal-team
# "Apple Development: ..." identity to keep TCC grants across rebuilds, or a "Developer ID
# Application: ..." identity for a build meant to leave this Mac. Every build gets the Hardened
# Runtime and the same entitlements and identifier, so LaunchServices sees one app and a
# Developer ID build is notarizable as is; only that identity gets a secure timestamp
# (scripts/lib/signing.sh), so an ad hoc or personal-team build signs offline. An ad hoc build
# fails `spctl --assess` by design: Gatekeeper only trusts Developer ID, and a locally built app
# carries no quarantine flag anyway.
set -eu
cd "$(dirname "$0")/.."

configuration="${1:-release}"
identity="${CODESIGN_IDENTITY:--}"
app="build/MonsterDeleter.app"
contents="$app/Contents"
resources="$contents/Resources"

swift build -c "$configuration" --arch arm64 --arch x86_64 --product MonsterDeleter
binary="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)/MonsterDeleter"

# Assemble.
rm -rf "$app"
mkdir -p "$contents/MacOS" "$resources/packs"
cp "$binary" "$contents/MacOS/MonsterDeleter"
cp Packaging/Info.plist "$contents/Info.plist"
printf 'APPL????' > "$contents/PkgInfo"
scripts/make-icon.sh
cp build/AppIcon.icns "$resources/AppIcon.icns"
# The menu bar image is a template: a name ending in "Template" is how AppKit is told to tint it.
cp Packaging/Icon/MenuBarIconTemplate.png Packaging/Icon/MenuBarIconTemplate@2x.png "$resources/"
for pack in Packaging/packs/*/; do
  [ -f "$pack/pack.json" ] || continue
  cp -R "$pack" "$resources/packs/$(basename "$pack")"
  echo "bundled built-in pack $(basename "$pack")"
done

# Sign.
timestamp="$(scripts/lib/signing.sh "$identity")"
codesign --force --sign "$identity" --options runtime "$timestamp" \
  --entitlements Packaging/MonsterDeleter.entitlements \
  --identifier io.github.kuan0808.MonsterDeleter "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "built $app ($configuration, signed with '$identity')"
