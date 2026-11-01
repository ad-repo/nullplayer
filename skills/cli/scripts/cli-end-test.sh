#!/bin/bash
# How the CLI ends local and streamed playback: when it exits, with which code, and what it plays
# first. No devices or servers needed; every case runs at volume 0. One PASS/FAIL line per check;
# exits 0 only if every check passed. Usage:
#
#   skills/cli/scripts/cli-end-test.sh
#
# Uses the already-built debug binary (`swift build --build-system native`); never builds. Playlists
# go in through NULLPLAYER_CLI_QUEUE (DEBUG only; see the cli skill), not the library.
set -uo pipefail
cd "$(dirname "$0")/../../.."

BIN=.build/arm64-apple-macosx/debug/NullPlayer
OUT=$PWD/tmp/cli-test
HTTP_PORT=8799
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }

# play <name> <alarm-seconds> <stdin-script> <queue entries...> [-- <cli args>]
# Sets RC (142 = still running at the alarm), ELAPSED (when the CLI itself exited) and PLAYED
# (the "Now Playing" titles in order, space-separated).
play() {
  local name="$1" secs="$2" input="$3"; shift 3
  local entries=() args=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do entries+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift && args=("$@")
  local t0; t0=$(date +%s)
  (eval "$input") | (
    NULLPLAYER_CLI_QUEUE="$(printf '%s\n' "${entries[@]}")" perl -e "alarm $secs; exec @ARGV" \
      "$BIN" --cli --no-art --volume 0 ${args[@]+"${args[@]}"} >"$OUT/$name.log" 2>&1
    echo "$? $(( $(date +%s) - t0 ))" >"$OUT/$name.rc"
  )
  read -r RC ELAPSED <"$OUT/$name.rc"
  tr '\r' '\n' <"$OUT/$name.log" >"$OUT/$name.txt"
  PLAYED=$(grep -oE 'Now Playing: Unknown Artist - [^ ]+' "$OUT/$name.txt" | sed 's/.* - //' | uniq | tr '\n' ' ')
  PLAYED="${PLAYED% }"
}
loaderr() { grep -q "Error loading '$2'" "$OUT/$1.txt"; }

# --- fixtures --------------------------------------------------------------------------------
[ -x "$BIN" ] || { echo "FAIL  preflight: $BIN missing — swift build --build-system native"; exit 1; }
mkdir -p "$OUT"
SHORT=$(scripts/testdata.sh path audio-short)             # 5 s
TEN=$PWD/tmp/testdata/gapless/01-gapless.flac              # 10 s
[ -f "$SHORT" ] && [ -f "$TEN" ] || { echo "FAIL  preflight: scripts/testdata.sh ensure"; exit 1; }
SHORT=$(cd "$(dirname "$SHORT")" && pwd)/$(basename "$SHORT")
BAD=$OUT/bad.mp3; printf 'not audio\n' >"$BAD"
[ -f "$OUT/tone5.mp3" ] || ffmpeg -v error -f lavfi -i "sine=frequency=330:duration=5" \
  -c:a libmp3lame -b:a 128k "$OUT/tone5.mp3" || { echo "FAIL  preflight: ffmpeg"; exit 1; }

# --- a queue that plays to its end exits 0 ---------------------------------------------------
play single 20 ':' "$SHORT"
[ "$RC" = 0 ] && [ "$PLAYED" = "audio-short" ] && pass "one track plays to its end, exits 0" \
  || fail "one track: rc=$RC played='$PLAYED' ($OUT/single.txt)"

# The local track change emits a passing .stopped while the next file prepares; it is not the end.
play good-good 40 ':' "$SHORT" "$TEN"
[ "$RC" = 0 ] && [ "$PLAYED" = "audio-short 01-gapless" ] \
  && pass "two tracks play through the track change, exit 0" \
  || fail "two tracks: rc=$RC played='$PLAYED' ($OUT/good-good.txt)"

play shuffle 40 ':' "$SHORT" "$TEN" -- --shuffle
case "$PLAYED" in "audio-short 01-gapless"|"01-gapless audio-short") ok=1 ;; *) ok=0 ;; esac
[ "$RC" = 0 ] && [ $ok = 1 ] && pass "--shuffle plays both tracks, exits 0" \
  || fail "--shuffle: rc=$RC played='$PLAYED' ($OUT/shuffle.txt)"

python3 -I -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$OUT" >/dev/null 2>&1 &
HTTP_PID=$!; trap 'kill $HTTP_PID 2>/dev/null' EXIT; sleep 1
play stream 30 ':' "http://127.0.0.1:$HTTP_PORT/tone5.mp3"
[ "$RC" = 0 ] && [ "$PLAYED" = "tone5" ] && pass "an http stream plays to its end, exits 0" \
  || fail "stream: rc=$RC played='$PLAYED' ($OUT/stream.txt)"

# --- load failures: skip past them; exit 1 only when nothing played --------------------------
play bad 20 ':' "$BAD"
[ "$RC" = 1 ] && loaderr bad bad && pass "an unloadable file alone exits 1 with its error" \
  || fail "bad alone: rc=$RC ($OUT/bad.txt)"

play bad-bad 20 ':' "$BAD" "$BAD"
[ "$RC" = 1 ] && loaderr bad-bad bad && pass "a queue in which nothing loads exits 1" \
  || fail "bad, bad: rc=$RC ($OUT/bad-bad.txt)"

# The skip runs inside loadTracks, so audio-short's banner prints before play()'s one for `bad`.
play bad-good 20 ':' "$BAD" "$SHORT"
[ "$RC" = 0 ] && loaderr bad-good bad && [[ " $PLAYED " == *" audio-short "* ]] \
  && pass "[bad, good] skips the bad file, plays the good one, exits 0" \
  || fail "bad, good: rc=$RC played='$PLAYED' ($OUT/bad-good.txt)"

play good-bad-good 45 ':' "$SHORT" "$BAD" "$TEN"
[ "$RC" = 0 ] && loaderr good-bad-good bad && [ "$PLAYED" = "audio-short bad 01-gapless" ] \
  && pass "[good, bad, good] plays both good files, exits 0" \
  || fail "good, bad, good: rc=$RC played='$PLAYED' ($OUT/good-bad-good.txt)"

# --- --repeat-all restarts at the end, and does not loop a queue that never plays ------------
play repeat 25 'sleep 12; printf q; sleep 3' "$SHORT" -- --repeat-all
[ "$RC" = 0 ] && [ "$ELAPSED" -ge 12 ] && pass "--repeat-all restarts a 5 s track (alive until q at 12 s)" \
  || fail "--repeat-all: rc=$RC exited at ${ELAPSED}s ($OUT/repeat.txt)"

play repeat-bad 20 ':' "$BAD" -- --repeat-all
[ "$RC" = 1 ] && pass "--repeat-all over an unloadable queue exits 1, no loop" \
  || fail "--repeat-all over bad: rc=$RC ($OUT/repeat-bad.txt)"

echo "$([ $FAILS = 0 ] && echo PASS || echo FAIL)  cli-end-test: $FAILS failed (logs in $OUT)"
[ $FAILS = 0 ]
