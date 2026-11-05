#!/bin/bash
#
# Live smoke over Winamp Modern (`.wal`) skins: click every main-window control in the running debug
# build and record what each click changed:
#
#   scripts/wal_live_smoke.sh <skin>... [--out <dir>] [--timeout <seconds>]
#   -> <out>/smoke.tsv, <out>/<skin>.log, and one summary line per skin
#
# One launch per skin (skills/app-control/scripts/launch.sh, music playing) with
# WINAMP_MODERN_DEBUG_CLICK=auto (WinampModernDebugClickSweep.swift). A skin is a path or a name
# launch.sh resolves. `changed` lists what moved (volume, play, position jump, track, eq, layout,
# windows, main, menu, modal), or `nochange`; a row the sweep did not click says why in `note` (skip, unreachable).
# Why: a live pass clicked each control by hand, ~50 tool calls a skin.

set -u -o pipefail
cd "$(dirname "$0")/.."

OUT=""; TIMEOUT=300; SKINS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) SKINS+=("$1"); shift ;;
    esac
done
[ ${#SKINS[@]} -gt 0 ] || { echo "usage: wal_live_smoke.sh <skin>... [--out <dir>] [--timeout <s>]" >&2; exit 2; }
OUT="${OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
TSV="$OUT/smoke.tsv"
printf 'skin\tidx\tobject\taction\tpoint\tvolume\tplay\tposition\ttrack\teq\tlayout\twindows\tmain\tnote\tchanged\n' >"$TSV"

for SKIN in "${SKINS[@]}"; do
    NAME=$(basename "${SKIN%.*}")
    LOG="$OUT/$NAME.log"
    if ! WINAMP_MODERN_DEBUG_CLICK=auto skills/app-control/scripts/launch.sh "$SKIN" --log "$LOG" >/dev/null; then
        echo "$NAME: LAUNCH FAIL (see $LOG.build)"; continue
    fi
    for _ in $(seq "$TIMEOUT"); do
        grep -q "WM-SMOKE done" "$LOG" && break
        pgrep -x NullPlayer >/dev/null || break
        sleep 1
    done
    STATUS=done; grep -q "WM-SMOKE done" "$LOG" || STATUS="INCOMPLETE (timeout or app exit)"
    # Position drifts ~1.2 s per click while playing; only a jump outside that counts.
    grep -o 'WM-SMOKE|.*' "$LOG" | awk -F'|' -v skin="$NAME" 'BEGIN { OFS = "\t" }
        function moved(f) { split(f, p, ">"); return p[1] != p[2] }
        {
            changed = ""
            if ($6 == "-") changed = "-"
            else {
                if (moved($6)) changed = changed ",volume"
                if (moved($7)) changed = changed ",play"
                split($8, t, ">"); d = t[2] - t[1]; if (d < -0.5 || d > 2.5) changed = changed ",position"
                if (moved($9)) changed = changed ",track"
                if (moved($10)) changed = changed ",eq"
                if (moved($11)) changed = changed ",layout"
                if ($12 != "-") changed = changed ",windows"
                if (moved($13)) changed = changed ",main"
                if ($14 ~ /menu/) changed = changed ",menu"
                if ($14 ~ /modal/) changed = changed ",modal"
                changed = changed == "" ? "nochange" : substr(changed, 2)
            }
            print skin, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, changed
        }' >>"$TSV"
    awk -F'\t' -v skin="$NAME" -v status="$STATUS" '$1 == skin {
            if ($15 == "-") other++; else { clicked++; if ($15 == "nochange") same++ }
        } END { printf "%s: %s, %d clicked, %d nochange, %d not clicked\n", skin, status, clicked, same, other }' "$TSV"
done
pkill -x NullPlayer 2>/dev/null || true
echo "tsv: $TSV"
