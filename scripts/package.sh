#!/bin/sh
# Build and sign the app, then wrap it as a release artifact under build/:
# MonsterDeleter-<version>.zip always, MonsterDeleter-<version>.dmg too with PACKAGE_DMG=1.
# The version is CFBundleShortVersionString from Packaging/Info.plist, the only place it lives.
#
#   [CODESIGN_IDENTITY=...] [PACKAGE_DMG=1] scripts/package.sh [debug|release]
#   PACKAGE_DMG=1 scripts/package.sh --prebuilt-app  # wrap the already stapled build unchanged
#
# The zip is made by ditto so the signature and the resource forks survive; the same zip is what
# scripts/notarize.sh submits for a public build.
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" = --prebuilt-app ]; then
  scripts/check-app.sh build/MonsterDeleter.app
else
  scripts/build-app.sh "${1:-release}"
fi

app="build/MonsterDeleter.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip="build/MonsterDeleter-$version.zip"
dmg="build/MonsterDeleter-$version.dmg"

rm -f "$zip" "$dmg"
ditto -c -k --keepParent "$app" "$zip"
echo "packaged $zip"

if [ "${PACKAGE_DMG:-0}" = "1" ]; then
  staging="build/dmg-staging"
  rm -rf "$staging"
  mkdir -p "$staging"
  cp -R "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -quiet -volname "MonsterDeleter $version" -srcfolder "$staging" -format UDZO "$dmg"
  rm -rf "$staging"
  echo "packaged $dmg"
fi
