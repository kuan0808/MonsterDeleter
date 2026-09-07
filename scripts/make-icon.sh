#!/bin/sh
# Build the app icon. Without arguments, turns the committed master
# Packaging/Icon/AppIcon-1024.png into build/AppIcon.icns through sips and iconutil (what
# scripts/build-app.sh runs). With --render, first recomposes the master and the menu bar template
# from the committed source artwork, so both icons stay reproducible from what is in the repo.
#
# The two icons are different animals and are composed by their own scripts: the app icon is
# artwork on the Apple grid, the menu bar one a single-weight template macOS tints itself
# (docs/artwork.md). Both need Pillow for python3.
#
#   scripts/make-icon.sh [--render]
set -eu
cd "$(dirname "$0")/.."

master="Packaging/Icon/AppIcon-1024.png"
iconset="build/AppIcon.iconset"
icns="build/AppIcon.icns"

if [ "${1:-}" = "--render" ]; then
  python3 scripts/lib/compose-icon.py Packaging/Icon/AppIcon-source.png "$master"
  python3 scripts/lib/compose-menu-bar-icon.py \
    Packaging/Icon/MenuBarIcon-source.png Packaging/Icon/MenuBarIconTemplate.png
fi

rm -rf "$iconset"
mkdir -p "$iconset"
# The iconset pairs each point size with its 2x image; iconutil rejects a set with a size missing.
for points in 16 32 128 256 512; do
  pixels=$((points * 2))
  sips -z "$points" "$points" "$master" --out "$iconset/icon_${points}x${points}.png" > /dev/null
  sips -z "$pixels" "$pixels" "$master" --out "$iconset/icon_${points}x${points}@2x.png" > /dev/null
done
iconutil --convert icns --output "$icns" "$iconset"
rm -rf "$iconset"
echo "built $icns"
