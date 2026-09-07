#!/bin/sh
# Cut a motion clip into one character-pack sprite sheet.
#
#   scripts/pack-sheet.sh <clip> <sheet.png> [options]
#
# A pack sheet is a grid of equal cells read left to right and top to bottom (five by three by
# default, so fifteen frames). This takes the clip a motion was generated as, lifts the frames the
# sheet needs out of a chosen window of it, pulls the flat backdrop off them and tiles the result.
#
# The backdrop comes off with a colour-difference matte (scripts/lib/backdrop-matte.py) rather than
# a matting model, because pack art is generated against a flat magenta ground that appears nowhere
# on the characters. It is not keyed against one fixed colour: generated footage lights its own
# backdrop, so a fireball washes the magenta towards white and a flight drags a gradient across it.
# The matte measures the backdrop in every frame instead, which also gives smoke the half cover it
# deserves rather than a yes-or-no answer.
#
# Every frame is scaled by the same factor and padded to the cell with its feet on the bottom edge,
# never cropped to what it contains. Fitting each frame to its own contents would resize the
# character from frame to frame and the animation would pump.
#
# The scale runs in premultiplied alpha. Scaling a straight matte would average the colour of
# pixels the matte had already made transparent into their opaque neighbours and put a halo back
# around the silhouette.
#
# The extracted frames are kept beside the sheet so the window can be checked before shipping: a
# sheet is only right when the pose the manifest names by index really sits at that index, which is
# what --start and --duration are for (the manifest's kickImpactFrame and pointFrames; a pack may
# move kickImpactFrame to where its own art lands instead of forcing the window).
#
#   --start S        seconds into the clip the sheet's first frame comes from (default 0)
#   --duration D     seconds of clip the sheet spans (default: to the end)
#   --cell WxH       cell size in pixels (default 288x512, the 9:16 character cell at 2x)
#   --grid CxR       columns by rows (default 5x3)
#   --crop W:H:X:Y   crop each source frame before matting, for scenery the shot grew (ffmpeg order)
#   --lo N           how much of the backdrop's magenta a pixel may lose and still go (default 0.22)
#   --hi N           magenta-ness at or over this fraction of the backdrop's is gone (default 0.88)
#   --fade N         dissolve the last N frames away, so an explosion ends on an empty cell
#   --inset F        draw each frame at F of the cell, centred, leaving a margin all round. The
#                    slicing cache rescales a whole sheet, so a bloom that reaches its cell's edge
#                    bleeds a little alpha into the neighbouring cell, and the explosion's last
#                    cell has to stay empty. Without it a frame is padded with its feet on the
#                    bottom edge, which is what a character sheet wants.
#   --hflip          mirror every frame, for art generated facing the wrong way
#   --frames DIR     where to keep the extracted frames (default <sheet.png without .png>-frames)
#
# Needs ffmpeg on the PATH, and numpy and Pillow for python3, which the matte imports.
set -eu
cd "$(dirname "$0")/.."

[ $# -ge 2 ] || { sed -n '2,4p' "$0" | cut -c3-; exit 2; }
clip="$1"
sheet="$2"
shift 2

start=0
duration=""
cell="288x512"
grid="5x3"
crop=""
lo=""
hi=""
fade=""
inset=""
hflip=""
frames=""

while [ $# -gt 0 ]; do
  case "$1" in
    --start) start="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --cell) cell="$2"; shift 2 ;;
    --grid) grid="$2"; shift 2 ;;
    --crop) crop="crop=$2,"; shift 2 ;;
    --lo) lo="$2"; shift 2 ;;
    --hi) hi="$2"; shift 2 ;;
    --fade) fade="$2"; shift 2 ;;
    --inset) inset="$2"; shift 2 ;;
    --hflip) hflip="hflip,"; shift ;;
    --frames) frames="$2"; shift 2 ;;
    *) echo "pack-sheet: unknown option $1" >&2; exit 2 ;;
  esac
done

[ -f "$clip" ] || { echo "pack-sheet: no clip at $clip" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "pack-sheet: ffmpeg is not installed" >&2; exit 1; }
python3 -c 'import numpy, PIL' 2>/dev/null || {
  echo "pack-sheet: the matte needs numpy and Pillow (python3 -m pip install numpy pillow)" >&2; exit 1; }

width="${cell%x*}"
height="${cell#*x}"
columns="${grid%x*}"
rows="${grid#*x}"
count=$((columns * rows))
[ -n "$frames" ] || frames="${sheet%.png}-frames"

# The window defaults to the whole clip, so a clip generated at the sheet's own length needs no
# --duration. ffprobe reports a float; the frame rate below is a float too, so no rounding is lost.
if [ -z "$duration" ]; then
  total="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$clip")"
  duration="$(awk -v t="$total" -v s="$start" 'BEGIN { printf "%.6f", t - s }')"
fi
rate="$(awk -v n="$count" -v d="$duration" 'BEGIN { printf "%.6f", n / d }')"

# The inset shrinks what a frame is drawn at and centres it in the cell; without one a frame fills
# the cell and is padded with its feet on the bottom edge.
if [ -n "$inset" ]; then
  fit="$(awk -v w="$width" -v f="$inset" 'BEGIN { printf "%d", w * f }')"
  fit="$fit:$(awk -v h="$height" -v f="$inset" 'BEGIN { printf "%d", h * f }')"
  pad="(ow-iw)/2:(oh-ih)/2"
else
  fit="${width}:${height}"
  pad="(ow-iw)/2:oh-ih"
fi

# Zero-padded to the width of the frame count, so the matte's sorted glob and ffmpeg's numeric
# tiling agree on the order past frame 99.
pattern="frame-%0${#count}d.png"

rm -rf "$frames"
mkdir -p "$frames" "$(dirname "$sheet")"

# -ss before -i seeks, so the window starts on a keyframe-accurate decode of the requested second.
ffmpeg -v error -y -ss "$start" -t "$duration" -i "$clip" \
  -vf "${crop}${hflip}fps=${rate}" -frames:v "$count" "$frames/$pattern"

extracted="$(find "$frames" -name 'frame-*.png' | wc -l | tr -d ' ')"
[ "$extracted" -eq "$count" ] || {
  echo "pack-sheet: got $extracted frames, need $count; the window runs past the end of the clip" >&2
  exit 1
}

python3 scripts/lib/backdrop-matte.py "$frames" ${lo:+--lo "$lo"} ${hi:+--hi "$hi"} ${fade:+--fade "$fade"}

ffmpeg -v error -y -framerate 1 -start_number 1 -i "$frames/$pattern" \
  -vf "format=rgba,premultiply=inplace=1,scale=${fit}:force_original_aspect_ratio=decrease,unpremultiply=inplace=1,pad=${width}:${height}:${pad}:color=#00000000,tile=${columns}x${rows}:color=#00000000" \
  -frames:v 1 "$sheet"

echo "pack-sheet: $sheet ($((width * columns))x$((height * rows)), $count frames from ${start}s+${duration}s of $clip)"
echo "pack-sheet: frames kept in $frames/ - check the pose indices before shipping"
