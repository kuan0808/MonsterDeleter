#!/bin/sh
# Print the codesign timestamp flag for a signing identity:
#
#   scripts/lib/signing.sh <identity>
#
# A secure timestamp needs a real Developer ID certificate and Apple's timestamp authority, so
# only a "Developer ID Application: ..." identity gets --timestamp. Ad hoc ("-") cannot carry one
# at all, and a personal-team "Apple Development: ..." build never needs one, so both get
# --timestamp=none and keep working offline.
set -eu

case "${1:?usage: signing.sh <identity>}" in
  "Developer ID Application:"*) echo "--timestamp" ;;
  *) echo "--timestamp=none" ;;
esac
