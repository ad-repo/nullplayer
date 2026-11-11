#!/bin/bash
#
# Live smoke over Winamp Modern (`.wal`) skins: click every main-window control in the running debug
# build and record what each click changed, then open the Library, click its controls and press its
# own close (the two checks of an intake, skills/skin-intake § The scan):
#
#   scripts/wal_live_smoke.sh <skin>... [--out <dir>] [--timeout <seconds>]
#   -> <out>/smoke.tsv, <out>/<skin>.log, and one summary line per skin
#
# One launch per skin (skills/app-control/scripts/launch.sh, music playing) with
# WINAMP_MODERN_DEBUG_CLICK=auto (WinampModernDebugClickSweep.swift). A skin is a path or a name
# launch.sh resolves. The sweep logs `WM-SMOKE|key=value|…` rows; their keys, in the sweep's order,
# are the TSV's columns after `skin`. The last, `changed`, is the sweep's verdict: what moved
# (volume, play, position jump, track, eq, layout, windows, main, menu, modal), or `nochange`; a row
# the sweep did not click reads `-` there and says why in `note` (skip, unreachable). A window with
# see-through holes inside its outline gets one `holes` row: `backed` (a press there stays in the
# window) or `unbacked` (it would go to the app behind), named in the summary line too.
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
: >"$TSV"

for SKIN in "${SKINS[@]}"; do
    NAME=$(basename -- "${SKIN%.*}")
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
    # The sweep's row is already the TSV row: its keys, in order, are the columns after `skin`.
    HEADER=1; [ -s "$TSV" ] && HEADER=0
    grep -o 'WM-SMOKE|.*' "$LOG" | awk -F'|' -v skin="$NAME" -v header="$HEADER" 'BEGIN { OFS = "\t" }
        {
            line = skin; keys = "skin"
            for (i = 2; i <= NF; i++) { eq = index($i, "="); keys = keys OFS substr($i, 1, eq - 1); line = line OFS substr($i, eq + 1) }
            if (header) { print keys; header = 0 }
            print line
        }' >>"$TSV"
    # Columns by name from the header: `window`, `idx`, `note`, `changed`.
    awk -F'\t' -v skin="$NAME" -v status="$STATUS" '
        NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        $1 == skin {
            w = $col["window"]; v = $col["changed"]
            if ($col["idx"] == "open") { opened = $col["note"]; next }
            if ($col["idx"] == "close") { shut = v == "-" ? $col["note"] : v; next }
            if ($col["idx"] == "holes") { holes = holes "; holes in " w " " v " (" $col["note"] ")"; next }
            if (v == "-") other[w]++; else { clicked[w]++; if (v == "nochange") same[w]++ }
        } END {
            printf "%s: %s, main %d clicked, %d nochange, %d not clicked; library %s", skin, status,
                clicked["main"], same["main"], other["main"], (opened == "" ? "not reached" : opened)
            if (opened == "skin-frame") printf ", %d clicked, %d nochange, %d not clicked, close %s", clicked["library"], same["library"], other["library"], shut
            printf "%s\n", holes
        }' "$TSV"
done
pkill -x NullPlayer 2>/dev/null || true
echo "tsv: $TSV"
