#!/bin/bash
# Prints the running debug build's playback snapshot: engine and player state, the measured
# output level, audio-graph recovery, output routing and the cast session. Exits 0 with the
# snapshot, or 1 with one line saying why there is none. Usage:
#
#   skills/app-control/scripts/playback-snapshot.sh [<pid>]
#
# With no pid it picks the one running debug build and refuses to guess between several. Only
# debug builds answer (the handler is #if DEBUG). The trigger is SIGINFO, whose default action is
# ignore, so a release or older build is never killed — it just times out. The app also logs
# each line with a `SNAPSHOT` prefix.
set -euo pipefail

PID="${1:-}"
if [ -z "$PID" ]; then
  PIDS=$(pgrep -f '\.build/.*/debug/NullPlayer' || true)
  COUNT=$(printf '%s\n' "$PIDS" | grep -c . || true)
  if [ "$COUNT" -ne 1 ]; then
    echo "playback-snapshot: FAIL — expected one running debug build, found $COUNT${PIDS:+ ($(echo $PIDS))}; pass a pid" >&2
    exit 1
  fi
  PID="$PIDS"
fi
kill -0 "$PID" 2>/dev/null || { echo "playback-snapshot: FAIL — no process $PID" >&2; exit 1; }

# The app writes to NSTemporaryDirectory(), which is the per-user temp dir whatever TMPDIR says.
FILE="$(getconf DARWIN_USER_TEMP_DIR)nullplayer-snapshot-$PID.txt"
rm -f "$FILE"
kill -INFO "$PID"
for _ in $(seq 1 30); do
  if [ -s "$FILE" ]; then cat "$FILE"; exit 0; fi
  sleep 0.1
done
echo "playback-snapshot: FAIL — pid $PID wrote nothing in 3s (release or pre-snapshot build, main thread blocked, or a sandboxed shell: its kill reports success but the signal is dropped — run unsandboxed)" >&2
exit 1
