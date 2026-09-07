#!/bin/bash
# reframe.sh <raw.png> <win_w_pt> <win_h_pt> <frame_pt> <outdir> <label>
# Centres the VISIBLE ARTWORK on a white frame and prints:  status art_pt framing file
#
# Two rules, both learned the hard way:
#  1. Centre the artwork, not the window rect. Many .wal windows carry huge transparent
#     margins (HeadAMP: 682px of art in a 1520px window at +414), so centring the rect
#     makes the skin wander between frames.
#  2. DISTRUST a tiny trim box. Skins whose alpha is near-uniform return a degenerate
#     box (3x4, 5x2, 0x318) and cropping to it yields a sliver. Below MIN_FRACTION of
#     the window area, fall back to the whole window. Re-shooting does NOT fix these -
#     it is not a timing problem.
set -u
raw="$1"; w="$2"; h="$3"; FRAME="$4"; OUT="$5"; label="$6"
MIN_FRACTION=35   # percent of window area a trim box must cover to be believed
px=$(magick identify -format '%w' "$raw"); py=$(magick identify -format '%h' "$raw")
sc=$(( px / w )); [ "$sc" -lt 1 ] && sc=1
g=$(magick "$raw" -alpha extract -format '%@' info: 2>/dev/null)
framing="trimmed"
case "$g" in ""|0x0*) g=""; framing="full-window(no-alpha)" ;; esac
if [ -n "$g" ]; then
  cw=${g%%x*}; r=${g#*x}; ch=${r%%+*}
  if [ $(( cw * ch * 100 )) -lt $(( px * py * MIN_FRACTION )) ]; then
    g=""; framing="full-window(trim-rejected)"
  fi
fi
if [ -n "$g" ]; then cw=${g%%x*}; r=${g#*x}; ch=${r%%+*}; else cw=$px; ch=$py; fi
aw=$(( cw / sc )); ah=$(( ch / sc ))
if [ "$aw" -gt "$FRAME" ] || [ "$ah" -gt "$FRAME" ]; then
  echo "skipped-too-big ${aw}x${ah}pt $framing -"; exit 0
fi
cv=$(( FRAME * sc ))
dest="$OUT/${label}_$(date +"%Y-%m-%d_%H%M%S").png"
crop=""; [ -n "$g" ] && crop="-crop $g +repage"
magick "$raw" $crop -background white -gravity center -extent ${cv}x${cv} \
       -alpha remove -alpha off -resize ${FRAME}x${FRAME} "$dest"
echo "ok ${aw}x${ah}pt $framing $dest"
