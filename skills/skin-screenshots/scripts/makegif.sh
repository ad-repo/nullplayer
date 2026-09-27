#!/bin/bash
# makegif.sh [--seconds 30 | --delay CS] [--size 500] [--order random|system] [--in DIR] [--out FILE]
#            [--feature FILE:N]...
# Per-frame delay is integer centisecs with the remainder spread over the first frames,
# so the cycle is EXACTLY the requested length rather than drifting with frame count.
# --delay fixes the per-frame delay instead, and the cycle becomes frames x delay.
# --feature makes FILE appear N times in total: one copy at a random spot in each of N equal
# slices of the sequence, so the repeats are spread out rather than bunched.
set -u
SEC=30; DELAY=""; SIZE=500; ORDER=random; IN="$HOME/Documents/shots"; DEST=""; FEATURES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SEC="$2"; shift 2;; --size) SIZE="$2"; shift 2;;
    --order) ORDER="$2"; shift 2;; --in) IN="$2"; shift 2;;
    --out) DEST="$2"; shift 2;; --delay) DELAY="$2"; shift 2;;
    --feature) FEATURES+=("$2"); shift 2;; *) echo "unknown arg $1"; exit 2;;
  esac
done
[ -z "$DEST" ] && DEST="$IN/nullplayer-skins.gif"
cd "$IN" || exit 1
if [ "$ORDER" = "system" ]; then
  list=$(for p in classic original original-metal modern wmp; do ls ${p}_*.png 2>/dev/null | sort; done)
else
  list=$(ls *.png 2>/dev/null | sort -R)
fi
for feat in ${FEATURES[@]+"${FEATURES[@]}"}; do
  ff="${feat%:*}"; times="${feat##*:}"
  [ -f "$ff" ] || { echo "feature frame not found: $ff"; exit 1; }
  list=$(echo "$list" | grep -vxF "$ff" | awk -v f="$ff" -v k="$times" -v seed="$RANDOM" '
    { a[NR]=$0 } END { srand(seed)
      for (j=0; j<k; j++) { lo=int(NR*j/k)+1; hi=int(NR*(j+1)/k); at[lo+int(rand()*(hi-lo+1))]=1 }
      for (r=1; r<=NR; r++) { if (r in at) print f; print a[r] } }')
done
n=$(echo "$list" | grep -c .)
[ "$n" -eq 0 ] && { echo "no frames in $IN"; exit 1; }
if [ -n "$DELAY" ]; then total=$(( DELAY * n )); else total=$(( SEC * 100 )); fi
base=$(( total / n )); rem=$(( total - base * n ))
args=(); i=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  d=$base; [ $i -lt $rem ] && d=$((base+1))
  args+=( -delay "$d" "$f" ); i=$((i+1))
done <<< "$list"
echo "frames=$n  delay=${base}cs (+1cs on first $rem)  cycle=$(awk -v t=$total 'BEGIN{printf "%.2f", t/100}')s  size=${SIZE}px  order=$ORDER"
magick "${args[@]}" -loop 0 -resize ${SIZE}x${SIZE} -layers OptimizePlus -colors 256 "$DEST"
actual=$(magick identify -format '%T\n' "$DEST" | awk '{s+=$1} END{printf "%.2f", s/100}')
echo "wrote $DEST  ($(du -h "$DEST" | cut -f1), verified ${actual}s)"
