#!/bin/bash
# One centred shot of the MAIN window per skin, for every skin system.
#
#   capture.sh [--list FILE] [--frame 800] [--out DIR] [--settle 2] [--only REGEX]
#
# Writes <out>/<label>_<YYYY-MM-DD_HHMMSS>.png plus a manifest TSV recording every
# decision, so a run can be audited and re-run for just the rows that went wrong.
set -u
cd "$(dirname "$0")"
LIST=""; FRAME=800; OUT="$HOME/Documents/shots"; SETTLE=2; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST="$2"; shift 2;; --frame) FRAME="$2"; shift 2;;
    --out) OUT="$2"; shift 2;; --settle) SETTLE="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;; *) echo "unknown arg $1"; exit 2;;
  esac
done
./build.sh >/dev/null
RAW="$(pwd)/.raw"; mkdir -p "$OUT" "$RAW"
STAMP=$(date +"%Y%m%d_%H%M%S"); MAN="$OUT/manifest_$STAMP.tsv"
printf 'label\tsystem\titem\tstatus\twindow_pt\tart_pt\tframing\tfile\n' > "$MAN"
if [ -z "$LIST" ]; then LIST="$(mktemp)"; ./enumerate_skins.sh > "$LIST"; fi

mw() { ./winhelper windows | awk -F'\t' '$2==0 && $7>0' | sort -t$'\t' -k8,8 | awk -F'\t' '
  { if ($8 ~ /^NullPlayer/ && !b) b=$1"\t"$3"\t"$4"\t"$5"\t"$6; if (!a) a=$1"\t"$3"\t"$4"\t"$5"\t"$6 } END{print (b?b:a)}'; }
geom() { ./winhelper windows | awk -F'\t' '$2==0 && $7>0' | sort -t$'\t' -k8,8 | head -1 | cut -f5,6; }
rec() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" "${6:-}" "${7:-}" "${8:-}" >> "$MAN"; }

cursys=""
while IFS=$'\t' read -r sys sub item label; do
  [ -z "${label:-}" ] && continue
  [ -n "$ONLY" ] && { echo "$label" | grep -Eq "$ONLY" || continue; }
  printf '%s ... ' "$label"
  pgrep -x NullPlayer >/dev/null || { echo "APP-DEAD"; rec "$label" "$sys" "$item" app-dead; break; }

  # Switching SYSTEM needs the submenu's "Switch to ..." item; a skin name alone won't do it.
  if [ "$sys" != "$cursys" ]; then
    osascript menu.applescript mode "$sub" >/dev/null 2>&1; sleep 4; cursys="$sys"
  fi

  before=$(geom)
  ok=""; for t in 1 2 3; do osascript menu.applescript skin "$sub" "$item" >/dev/null 2>&1 && { ok=1; break; }; sleep 2; done
  [ -z "$ok" ] && { echo "MENU-FAIL"; rec "$label" "$sys" "$item" menu-fail; continue; }

  # Wait for the window to CHANGE (proves the new skin took), then for it to settle.
  # Waiting only for "stable" photographs the PREVIOUS skin, because a heavy .wal leaves
  # the old window up unchanged for seconds while it loads.
  for i in $(seq 1 40); do sleep 0.25; [ "$(geom)" != "$before" ] && break; done
  prev=""; st=0
  for i in $(seq 1 40); do sleep 0.25; c=$(geom); [ "$c" = "$prev" ] && st=$((st+1)) || st=0; prev="$c"; [ $st -ge 2 ] && break; done
  sleep "$SETTLE"

  [ "$(./winhelper windows | awk -F'\t' '$2==0 && $7>0' | wc -l | tr -d ' ')" -gt 1 ] && \
    { osascript menu.applescript closeaux >/dev/null 2>&1; sleep 1; }

  IFS=$'\t' read -r id x y w h < <(mw)
  [ -z "${id:-}" ] && { echo "NO-WINDOW"; rec "$label" "$sys" "$item" no-window; continue; }

  raw="$RAW/$label.png"; rm -f "$raw"
  screencapture -o -x -l "$id" "$raw" 2>/dev/null
  [ -s "$raw" ] || { echo "CAPTURE-FAIL"; rec "$label" "$sys" "$item" capture-fail "${w}x${h}"; continue; }

  read -r status art framing file < <(./reframe.sh "$raw" "$w" "$h" "$FRAME" "$OUT" "$label")
  echo "$status ${w}x${h}pt art=$art $framing"
  rec "$label" "$sys" "$item" "$status" "${w}x${h}" "$art" "$framing" "$file"
done < "$LIST"
echo "DONE  manifest: $MAN"
