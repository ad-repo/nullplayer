#!/bin/bash
# makegif.sh [--seconds 30] [--size 500] [--order random|system] [--in DIR] [--out FILE]
# Per-frame delay is integer centisecs with the remainder spread over the first frames,
# so the cycle is EXACTLY the requested length rather than drifting with frame count.
set -u
SEC=30; SIZE=500; ORDER=random; IN="$HOME/Documents/shots"; DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SEC="$2"; shift 2;; --size) SIZE="$2"; shift 2;;
    --order) ORDER="$2"; shift 2;; --in) IN="$2"; shift 2;;
    --out) DEST="$2"; shift 2;; *) echo "unknown arg $1"; exit 2;;
  esac
done
[ -z "$DEST" ] && DEST="$IN/nullplayer-skins.gif"
cd "$IN" || exit 1
if [ "$ORDER" = "system" ]; then
  list=$(for p in classic original original-metal modern; do ls ${p}_*.png 2>/dev/null | sort; done)
else
  list=$(ls *.png 2>/dev/null | sort -R)
fi
n=$(echo "$list" | grep -c .)
[ "$n" -eq 0 ] && { echo "no frames in $IN"; exit 1; }
total=$(( SEC * 100 )); base=$(( total / n )); rem=$(( total - base * n ))
args=(); i=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  d=$base; [ $i -lt $rem ] && d=$((base+1))
  args+=( -delay "$d" "$f" ); i=$((i+1))
done <<< "$list"
echo "frames=$n  delay=${base}cs (+1cs on first $rem)  cycle=${SEC}.00s  size=${SIZE}px  order=$ORDER"
magick "${args[@]}" -loop 0 -resize ${SIZE}x${SIZE} -layers OptimizePlus -colors 256 "$DEST"
actual=$(magick identify -format '%T\n' "$DEST" | awk '{s+=$1} END{printf "%.2f", s/100}')
echo "wrote $DEST  ($(du -h "$DEST" | cut -f1), verified ${actual}s)"
