#!/bin/bash
# Live CLI casting checks against a real Chromecast and DLNA TV on the LAN: the #645–#647 fixes.
# One PASS/FAIL line per check; exits 0 only if every check passed. Usage:
#
#   skills/cast-testing/scripts/cast-test.sh [--chromecast <name>] [--dlna <name>] [--sonos <room>]
#
# Defaults to the first Chromecast and the first DLNA TV discovered. Sonos runs only when a room is
# named: it plays a 5 s tone in that room. Uses the already-built debug
# binary (build it first: `swift build --build-system native`); never builds, never kills the app.
# Puts video on both TVs: a corrupt file the Chromecast rejects, a 10 s clip on each.
set -uo pipefail
cd "$(dirname "$0")/../../.."

BIN=.build/$(uname -m)-apple-macosx/debug/NullPlayer
OUT=tmp/cast-test
CC_NAME=""; DLNA_NAME=""; SONOS_ROOM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --chromecast) CC_NAME="$2"; shift 2 ;;
    --dlna) DLNA_NAME="$2"; shift 2 ;;
    --sonos) SONOS_ROOM="$2"; shift 2 ;;
    *) echo "cast-test.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }

# run <log> <alarm-seconds> <stdin-script> <cli args...>; sets RC (142 = hung until the alarm).
run() {
  local log="$1" secs="$2" input="$3"; shift 3
  (eval "$input") | perl -e "alarm $secs; exec @ARGV" "$BIN" --cli --no-art --volume 0 "$@" >"$log" 2>&1
  RC=${PIPESTATUS[1]}
  tr '\r' '\n' <"$log" >"$log.txt"
}

# --- preflight -------------------------------------------------------------------------------
[ -x "$BIN" ] || { echo "FAIL  preflight: $BIN missing — swift build --build-system native"; exit 1; }
if lsof -nP -iTCP:8765 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "FAIL  preflight: port 8765 is held (another NullPlayer is casting); stop it and retry"; exit 1
fi
mkdir -p "$OUT"
VIDEO=$(scripts/testdata.sh path video-short)
AUDIO=$(scripts/testdata.sh path audio-short)
[ -f "$VIDEO" ] && [ -f "$AUDIO" ] || { echo "FAIL  preflight: scripts/testdata.sh ensure"; exit 1; }
python3 -c "open('$OUT/corrupt.mp4','wb').write(b'NullPlayer cast-test corrupt media\n'*6000)"
printf 'not video\n' >"$OUT/sample.mpg"

# --- #647: discovery lists the friendly name and the stable id -------------------------------
perl -e 'alarm 30; exec @ARGV' "$BIN" --cli --list-devices --json </dev/null >"$OUT/devices.json" 2>/dev/null
DEVICES_PY=$(cat <<'EOF'
import json, re, shlex, sys
rows = json.load(open(sys.argv[1]))
want_cc, want_dlna = sys.argv[2], sys.argv[3]
keys = {"name", "type", "id", "supportsVideo", "address", "port"}
assert all(keys <= r.keys() for r in rows), "row missing a field"
cc = [r for r in rows if r["type"] == "chromecast" and (not want_cc or r["name"] == want_cc)]
dl = [r for r in rows if r["type"] == "dlnaTV" and (not want_dlna or r["name"] == want_dlna)]
cc, dl = (cc[0] if cc else None), (dl[0] if dl else None)
if cc:
    # The service instance name ends in a 32-hex suffix; the TXT `fn` does not.
    assert not re.search(r"-[0-9a-f]{32}$", cc["name"]), "name is the service instance name"
    assert re.fullmatch(r"chromecast:[0-9a-f]{32}", cc["id"]), "id is not chromecast:<TXT id>"
print("CC_ID=" + shlex.quote(cc["id"] if cc else "-"))
print("CC_NAME=" + shlex.quote(cc["name"] if cc else "-"))
print("DLNA_NAME=" + shlex.quote(dl["name"] if dl else "-"))
EOF
)
if python3 -c "$DEVICES_PY" "$OUT/devices.json" "$CC_NAME" "$DLNA_NAME" >"$OUT/devices.env"; then
  . "$OUT/devices.env"
  pass "list-devices: every row has name/type/id/supportsVideo/address/port"
else
  fail "list-devices: see $OUT/devices.json"; CC_ID=-; DLNA_NAME=-
fi
[ "$CC_ID" != "-" ] && pass "list-devices: Chromecast '$CC_NAME' by its fn, id $CC_ID" \
  || fail "list-devices: no Chromecast discovered"
[ "$DLNA_NAME" != "-" ] || fail "list-devices: no DLNA TV discovered"

# --- #646: .mpg is video (how the CLI ends local playback: skills/cli/scripts/cli-end-test.sh) --
run "$OUT/mpg" 20 ':' --file "$OUT/sample.mpg"
[ "$RC" = 1 ] && grep -q 'requires --cast' "$OUT/mpg.txt" \
  && pass ".mpg routes to video (asks for --cast)" || fail ".mpg routing: rc=$RC, $OUT/mpg.txt"


if [ "$CC_ID" != "-" ]; then
  # --- #645: a rejected load exits 1; #647: --cast resolves by name, id, and bare id ----------
  for target in "$CC_NAME" "$CC_ID" "${CC_ID#chromecast:}"; do
    run "$OUT/reject" 60 'sleep 55' --file "$OUT/corrupt.mp4" --cast "$target"
    if [ "$RC" = 1 ] && grep -q 'could not play this video' "$OUT/reject.txt"; then
      pass "--cast '$target' resolves; the rejected video exits 1 with the receiver's error"
    else
      fail "--cast '$target' + corrupt video: rc=$RC, $OUT/reject.txt"
    fi
  done

  run "$OUT/cc-play" 60 'sleep 55' --file "$VIDEO" --cast "$CC_NAME"
  [ "$RC" = 0 ] && pass "Chromecast plays the 10 s clip and exits 0 at its end" \
    || fail "Chromecast good cast: rc=$RC, $OUT/cc-play.txt"
fi

if [ "$DLNA_NAME" != "-" ]; then
  # --- #645: the 30 s start timeout is Chromecast-only; DLNA runs until q -------------------
  # DLNA reports no status, so whether the TV plays is read from its requests: `video-short` has
  # its moov index at the end, and a renderer that will play it range-requests past byte 0.
  run "$OUT/dlna" 60 'sleep 40; printf q; sleep 15' --file "$VIDEO" --cast "$DLNA_NAME" --cast-type dlna --verbose
  if [ "$RC" = 0 ] && ! grep -q 'did not start playing' "$OUT/dlna.txt"; then
    pass "DLNA cast runs past 30 s and quits on q"
  else
    fail "DLNA cast: rc=$RC, $OUT/dlna.txt"
  fi
  grep -qE 'LocalMediaServer: Serving range [1-9][0-9]*-' "$OUT/dlna.txt" \
    && pass "DLNA TV range-requests the index (it can play the file)" \
    || fail "DLNA TV never range-requested past byte 0 (format not supported?): $OUT/dlna.txt"
fi

if [ -n "$SONOS_ROOM" ]; then
  # --- the DLNA feature headers are answered only on request; a Sonos local-file cast still plays --
  run "$OUT/sonos" 40 'sleep 15; printf q; sleep 10' --file "$AUDIO" --cast "$SONOS_ROOM" --cast-type sonos --verbose
  if [ "$RC" = 0 ] && grep -q 'Sonos poll — state=PLAYING' "$OUT/sonos.txt"; then
    pass "Sonos '$SONOS_ROOM' plays a local file and quits on q"
  else
    fail "Sonos cast: rc=$RC, $OUT/sonos.txt"
  fi
  grep -q 'answering DLNA feature request' "$OUT/sonos.txt" \
    && echo "INFO  Sonos asked for DLNA feature headers (and got them)" \
    || echo "INFO  Sonos did not ask for DLNA feature headers"
fi

echo "$([ $FAILS = 0 ] && echo PASS || echo FAIL)  cast-test: $FAILS failed (logs in $OUT)"
[ $FAILS = 0 ]
