#!/bin/sh
# Notarize and staple a Developer ID build. The release candidate workflow requires it; it
# only runs when NOTARY_PROFILE names a notarytool keychain profile, which needs a paid Apple
# Developer Program membership and a "Developer ID Application" certificate. Without it the
# script explains and exits 0 unless NOTARY_REQUIRED=1 requests a fail-closed public build.
#
#   CODESIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<profile> scripts/notarize.sh
#
# One-time setup: xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
# (it asks for an app-specific password). The steps after the build are the whole public
# distribution story: submit the zip, staple the ticket to the app, zip it again.
#
# The build runs with PACKAGE_DMG=0, whatever the environment says: a DMG made here would hold
# the app from before the ticket was stapled. PACKAGE_DMG=1 makes the DMG after stapling,
# then signs, notarizes and staples that outer container too.
set -eu
cd "$(dirname "$0")/.."

make_dmg="${PACKAGE_DMG:-0}"
export PACKAGE_DMG=0

if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "notarize: NOTARY_PROFILE is not set; nothing to do (see the comment at the top of this script)"
  exit "${NOTARY_REQUIRED:-0}"
fi
case "${CODESIGN_IDENTITY:-}" in
  "Developer ID Application:"*) ;;
  *) echo "notarize: CODESIGN_IDENTITY must be a 'Developer ID Application: ...' identity" >&2; exit 1 ;;
esac

scripts/package.sh release

app="build/MonsterDeleter.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip="build/MonsterDeleter-$version.zip"

set -- --keychain-profile "$NOTARY_PROFILE" --wait
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then set -- "$@" --keychain "$NOTARY_KEYCHAIN"; fi
xcrun notarytool submit "$zip" "$@"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose=2 "$app"
echo "notarized and stapled $zip"

if [ "$make_dmg" = 1 ]; then
  PACKAGE_DMG=1 scripts/package.sh --prebuilt-app
  dmg="build/MonsterDeleter-$version.dmg"
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" "$@"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
  echo "notarized and stapled $dmg"
fi
