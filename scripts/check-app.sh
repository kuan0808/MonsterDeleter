#!/bin/sh
# Inspect the actual signed artifact, including both Mach-O deployment targets.
set -eu
app="${1:-build/MonsterDeleter.app}"
binary="$app/Contents/MacOS/MonsterDeleter"
[ -x "$binary" ] || { echo "missing executable: $binary" >&2; exit 1; }
[ "$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")" = 15.0 ] ||
  { echo "bundle must require macOS 15.0" >&2; exit 1; }
architectures="$(lipo -archs "$binary")"
[ "$(printf '%s\n' "$architectures" | tr ' ' '\n' | sort | tr '\n' ' ')" = 'arm64 x86_64 ' ] ||
  { echo "expected arm64 + x86_64, found: $architectures" >&2; exit 1; }
for architecture in arm64 x86_64; do
  xcrun vtool -arch "$architecture" -show-build "$binary" |
    awk '/platform / { platform=$2 } /minos / { minimum=$2; count++ }
      END { exit !(count == 1 && platform == "MACOS" && minimum == "15.0") }' ||
      { echo "$architecture must deploy to macOS 15.0" >&2; exit 1; }
done
codesign --verify --deep --strict --verbose=2 "$app"
echo "artifact passed: arm64 + x86_64, macOS 15.0, valid signature"
shasum -a 256 "$binary"
