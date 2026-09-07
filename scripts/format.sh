#!/bin/sh
# Format Swift sources in place with the Xcode toolchain formatter (config: .swift-format).
set -eu
cd "$(dirname "$0")/.."
dirs=""
for d in Sources Tests; do [ -d "$d" ] && dirs="$dirs $d"; done
[ -n "$dirs" ] || { echo "format: no Sources or Tests directory yet, nothing to do"; exit 0; }
# shellcheck disable=SC2086
exec xcrun swift-format format --in-place --recursive $dirs
