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
# launch.sh resolves. The sweep logs `WM-SMOKE|key=value|…` rows; their keys, in the sweep's order,
# are the TSV's columns between `skin` and `changed`, and every value is read by its key. `changed`
# lists what moved (volume, play, position jump, track, eq, layout, windows, main, menu, modal), or
# `nochange`; a row the sweep did not click says why in `note` (skip, unreachable).
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
    HEADER=1; [ -s "$TSV" ] && HEADER=0
    grep -o 'WM-SMOKE|.*' "$LOG" | awk -F'|' -v skin="$NAME" -v header="$HEADER" 'BEGIN { OFS = "\t" }
        function moved(f,   p) { split(f, p, ">"); return p[1] != p[2] }
        {
            n = 0; delete v
            for (i = 2; i <= NF; i++) { eq = index($i, "="); k[++n] = substr($i, 1, eq - 1); v[k[n]] = substr($i, eq + 1) }
            if (header) { line = "skin"; for (i = 1; i <= n; i++) line = line OFS k[i]; print line OFS "changed"; header = 0 }
            changed = ""
            if (v["volume"] == "-") changed = "-"
            else {
                if (moved(v["volume"])) changed = changed ",volume"
                if (moved(v["play"])) changed = changed ",play"
                split(v["position"], t, ">"); d = t[2] - t[1]; if (d < -0.5 || d > 2.5) changed = changed ",position"
                if (moved(v["track"])) changed = changed ",track"
                if (moved(v["eq"])) changed = changed ",eq"
                if (moved(v["layout"])) changed = changed ",layout"
                if (v["windows"] != "-") changed = changed ",windows"
                if (moved(v["main"])) changed = changed ",main"
                if (v["note"] ~ /menu/) changed = changed ",menu"
                if (v["note"] ~ /modal/) changed = changed ",modal"
                changed = changed == "" ? "nochange" : substr(changed, 2)
            }
            line = skin; for (i = 1; i <= n; i++) line = line OFS v[k[i]]; print line OFS changed
        }' >>"$TSV"
    awk -F'\t' -v skin="$NAME" -v status="$STATUS" '$1 == skin {
            if ($NF == "-") other++; else { clicked++; if ($NF == "nochange") same++ }
        } END { printf "%s: %s, %d clicked, %d nochange, %d not clicked\n", skin, status, clicked, same, other }' "$TSV"
done
pkill -x NullPlayer 2>/dev/null || true
echo "tsv: $TSV"
