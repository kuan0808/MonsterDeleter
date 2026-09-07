#!/bin/sh
# The self-test: build the bundle (or use --prebuilt-app), then play two shows on scratch files
# at a fixed point and judge them, exit non-zero on any miss.
#
#   scripts/self-test.sh [--update-references] [debug|release | --prebuilt-app /path/to/MonsterDeleter.app]
#
# Show 1 confirms: a file and a folder, every phase in order within its window, both in the
# Trash, six checkpoint captures compared with Tests/Fixtures/ShowReferences/ (2% of pixels
# may differ). Show 2 presses Esc: the show ends cancelled and both items stay put. Both shows
# always play the placeholder pack. --update-references writes show 1's captures over the
# committed references instead of comparing; commit them with the change that moved them.
#
# The app judges its own show (AutoplaySelfTest) and prints "self-test passed" or one "FAIL:"
# line per problem; this script adds the checks the app cannot make on itself: the exit status
# and, from outside the process, the scratch items gone or still there. Logs and captures land
# under build/self-test/.
set -eu
cd "$(dirname "$0")/.."

update=0
configuration=release
prebuilt=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --update-references) update=1 ;;
    --prebuilt-app)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--prebuilt-app needs an app path" >&2; exit 64; }
      prebuilt="$2"
      shift
      ;;
    debug|release) configuration="$1" ;;
    *) echo "usage: scripts/self-test.sh [--update-references] [debug|release | --prebuilt-app /path/to/MonsterDeleter.app]" >&2; exit 64 ;;
  esac
  shift
done

if [ -n "$prebuilt" ]; then
  app="$prebuilt/Contents/MacOS/MonsterDeleter"
else
  scripts/build-app.sh "$configuration"
  app="build/MonsterDeleter.app/Contents/MacOS/MonsterDeleter"
fi
[ -x "$app" ] || { echo "missing executable: $app" >&2; exit 1; }
out="build/self-test"
reference="Tests/Fixtures/ShowReferences"
rm -rf "$out"
mkdir -p "$out"
{
  sw_vers
  uname -m
  file "$app"
  shasum -a 256 "$app"
} | tee "$out/artifact.log"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/monster-self-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
status=0

# One show: $1 name, $2 answer (confirm|esc), $3 snapshot folder, $4 reference folder.
play() {
  name="$1"
  file="$scratch/$name-file.txt"
  folder="$scratch/$name-folder"
  printf 'Feed me to the monster.\n' > "$file"
  mkdir -p "$folder"
  printf 'inside\n' > "$folder/inside.txt"
  echo "== show $name ($2)"
  set +e
  # Empty MONSTER_AUTOPLAY_PACK reads as absent, so the show is the placeholder whatever a
  # maintainer left exported after capturing a pack's evidence: the references are its captures.
  MONSTER_AUTOPLAY="$file:$folder" MONSTER_AUTOPLAY_POINT=700,400 MONSTER_AUTOPLAY_ANSWER="$2" \
    MONSTER_AUTOPLAY_PACK='' MONSTER_AUTOPLAY_SNAPSHOTS="$3" MONSTER_AUTOPLAY_REFERENCE="$4" \
    "$app" > "$out/$name.log" 2>&1
  code=$?
  set -e
  cat "$out/$name.log"
  if [ "$code" -ne 0 ]; then
    echo "FAIL: show $name exited with status $code"
    status=1
  fi
  case "$2" in
    confirm)
      for item in "$file" "$folder"; do
        if [ -e "$item" ]; then echo "FAIL: $item is still there"; status=1; fi
      done
      ;;
    esc)
      for item in "$file" "$folder"; do
        if [ ! -e "$item" ]; then echo "FAIL: $item is gone after a cancelled show"; status=1; fi
      done
      ;;
  esac
}

if [ "$update" -eq 1 ]; then
  mkdir -p "$reference"
  play confirm confirm "$reference" ""
  echo "wrote references to $reference"
else
  play confirm confirm "$out/snapshots" "$reference"
fi
play esc esc "" ""

if [ "$status" -eq 0 ]; then
  echo "self-test: both shows passed"
else
  echo "self-test: failed (logs under $out)"
fi
exit "$status"
