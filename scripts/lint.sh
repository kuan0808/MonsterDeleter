#!/bin/sh
# Lint Swift sources with the Xcode toolchain formatter (config: .swift-format). Non-zero exit on any finding.
set -eu
cd "$(dirname "$0")/.."
dirs=""
for d in Sources Tests; do [ -d "$d" ] && dirs="$dirs $d"; done
[ -n "$dirs" ] || { echo "lint: no Sources or Tests directory yet, nothing to do"; exit 0; }
# shellcheck disable=SC2086
exec xcrun swift-format lint --strict --recursive $dirs
