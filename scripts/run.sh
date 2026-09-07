#!/bin/sh
# Build the app bundle and launch it. Extra environment (MONSTER_AUTOPLAY=...) passes through.
#
#   scripts/run.sh [debug|release]
set -eu
cd "$(dirname "$0")/.."
scripts/build-app.sh "${1:-release}"
# One LaunchServices record per machine keeps the Services item pointing at this bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$PWD/build/MonsterDeleter.app"
pkill -x MonsterDeleter 2>/dev/null || true
exec build/MonsterDeleter.app/Contents/MacOS/MonsterDeleter
