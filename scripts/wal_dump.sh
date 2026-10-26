#!/bin/bash
# One `.wal` skin's headless render dump in one call: find the archive by name, run
# WinampModernRenderDumpTests into a fresh directory, log to a file, and print a short verdict.
#
#   scripts/wal_dump.sh <skin|path> [--out <dir>] [--grep <ERE>] [--skip-build]
#   WINAMP_MODERN_RENDER_CLICK='main/normal@91,188' WINAMP_MODERN_CALL_TRACE=1 scripts/wal_dump.sh Abducted --grep 'CLICK at'
#
# Probe variables (harness.md § *Debugging a skin*) are passed through from the caller's environment.
# The output directory is emptied first, because PNGs from an earlier run would read as this run's.
# Prints `DUMP PASS|FAIL`, the log, the PNG count, and at most 60 log lines matching --grep. The full
# log stays in <dir>/dump.log; read it there rather than re-running.
#
# Why: intake #3 ran this by hand about 160 times, each one rebuilding the same path lookup, env
# line, redirect and `tail`. A test that skipped (no archive found) passed the hand recipe silently.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"
source scripts/lib/wal_corpus.sh
source scripts/lib/swiftpm.sh

SKIN="" OUT="" GREP="" SKIP=()
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --grep) GREP="$2"; shift 2 ;;
        --skip-build) SKIP=(--skip-build); shift ;;
        -*) echo "wal_dump: unknown option $1" >&2; exit 2 ;;
        *) SKIN="$1"; shift ;;
    esac
done
[ -n "$SKIN" ] || { echo "usage: wal_dump.sh <skin|path> [--out <dir>] [--grep <ERE>] [--skip-build]" >&2; exit 2; }
WAL=$(wal_resolve_skin "$SKIN") || exit 2
NAME=$(basename "$WAL"); NAME=$(printf '%s' "${NAME%.*}" | tr -c 'A-Za-z0-9._-' '_')
OUT="${OUT:-$TMP/wal-dump/$NAME}"
rm -rf "$OUT" && mkdir -p "$OUT"

WINAMP_MODERN_WAL="$WAL" WINAMP_MODERN_RENDER_DUMP="$OUT" \
    swift test ${SKIP[@]+"${SKIP[@]}"} ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} \
    --filter WinampModernRenderDumpTests > "$OUT/dump.log" 2>&1
STATUS=$?

VERDICT=PASS
[ $STATUS -eq 0 ] || VERDICT="FAIL (swift test exited $STATUS)"
grep -q "testRendersEachContainerToPNG\]' skipped" "$OUT/dump.log" && VERDICT="FAIL (test skipped: $(grep -m1 -o 'Set WINAMP[^.]*\|No .wal archives[^.]*' "$OUT/dump.log"))"
echo "DUMP $VERDICT  $WAL"
echo "log: $OUT/dump.log  pngs: $(find "$OUT" -name '*.png' | wc -l | tr -d ' ')  dir: $OUT"
[ "$VERDICT" = PASS ] || { grep -E 'error:|failed' "$OUT/dump.log" | head -10; exit 1; }
if [ -n "$GREP" ]; then
    MATCHES=$(grep -E "$GREP" "$OUT/dump.log" | cut -c1-240)
    N=$(grep -c . <<<"$MATCHES")
    [ "$N" -gt 0 ] || { echo "no log line matches $GREP"; exit 0; }
    head -60 <<<"$MATCHES"
    [ "$N" -le 60 ] || echo "… $((N - 60)) more in $OUT/dump.log"
fi
