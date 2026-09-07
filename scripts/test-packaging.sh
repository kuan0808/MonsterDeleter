#!/bin/sh
# Regression checks at the signed-artifact and self-test command boundaries.
set -eu
cd "$(dirname "$0")/.."
scripts/check-app.sh
fixture="$(mktemp -d "build/packaging-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
reject() {
  if "$@"; then
    echo "FAIL: accepted invalid artifact: $*" >&2
    exit 1
  fi
}
reject scripts/check-app.sh "$fixture/missing.app"
set +e
scripts/self-test.sh --prebuilt-app "$fixture/missing.app" > "$fixture/missing.log" 2>&1
code=$?
set -e
[ "$code" -eq 1 ] || { cat "$fixture/missing.log"; exit 1; }
# A real, correctly signed but thin executable must fail the universal gate.
cp -R build/MonsterDeleter.app "$fixture/thin.app"
binary="$fixture/thin.app/Contents/MacOS/MonsterDeleter"
lipo "$binary" -thin arm64 -output "$fixture/arm64"
mv "$fixture/arm64" "$binary"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements Packaging/MonsterDeleter.entitlements "$fixture/thin.app"
reject scripts/check-app.sh "$fixture/thin.app"
echo "packaging regression checks passed"
