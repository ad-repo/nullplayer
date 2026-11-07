#!/bin/bash
# Live checks of the visualization cast (`skills/visualization-cast`) against a real Chromecast and
# DLNA TV on the LAN: every behaviour that skill records as measured. One PASS/FAIL line per check;
# exits 0 only if every check passed. Usage:
#
#   skills/cast-testing/scripts/viscast-test.sh [--chromecast <name>] [--dlna <name>] [--skin <skin>]
#
# Defaults to the first Chromecast and the first DLNA TV discovered, on `modern:NeonWave` (any
# `launch.sh` skin works; run a Classic one too, the two Visualizations windows are separate hosts).
# It (re)launches the debug build through `launch.sh` (which kills a running one), plays its default
# music, opens Visualizations and drives the right-click menu. About 6 minutes; puts the
# visualization on both TVs. The cast settings are saved first and put back at the end.
set -uo pipefail
cd "$(dirname "$0")/../../.."

OUT=tmp/viscast-test
CC=""; DLNA=""; SKIN="modern:NeonWave"
while [ $# -gt 0 ]; do
  case "$1" in
    --chromecast) CC="$2"; shift 2 ;;
    --dlna) DLNA="$2"; shift 2 ;;
    --skin) SKIN="$2"; shift 2 ;;
    *) echo "viscast-test.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { if [ "$1" = 0 ]; then pass "$2"; else fail "$2${3:+ — $3}"; fi; }

for tool in ffmpeg ffprobe python3 curl; do
  command -v $tool >/dev/null || { echo "FAIL  preflight: $tool not found"; exit 1; }
done
mkdir -p "$OUT"; rm -f "$OUT"/*
LOG="$OUT/app.log"
WH=skills/app-control/scripts/winhelper
D=NullPlayer   # the debug build's defaults domain
URL=http://127.0.0.1:8765/viscast

# --- the cast settings: known values for the run, the user's back afterwards -----------------
OLD_RES=$(defaults read $D visualizationCast.resolution 2>/dev/null || echo "")
OLD_FPS=$(defaults read $D visualizationCast.frameRate 2>/dev/null || echo "")
restore() {
  if [ -n "$OLD_RES" ]; then defaults write $D visualizationCast.resolution "$OLD_RES"; else defaults delete $D visualizationCast.resolution 2>/dev/null; fi
  if [ -n "$OLD_FPS" ]; then defaults write $D visualizationCast.frameRate -int "$OLD_FPS"; else defaults delete $D visualizationCast.frameRate 2>/dev/null; fi
}
trap restore EXIT
defaults write $D visualizationCast.resolution 1080p
defaults write $D visualizationCast.frameRate -int 30

# --- launch, discover, open Visualizations ---------------------------------------------------
NULLPLAYER_UPNP_LOG=1 skills/app-control/scripts/launch.sh "$SKIN" --log "$LOG" | tail -1 | grep -q PASS \
  || { echo "FAIL  preflight: launch.sh $SKIN"; exit 1; }
PID=$(pgrep -x NullPlayer | head -1)
for _ in $(seq 30); do
  grep -q "ChromecastManager: Added device" "$LOG" && grep -q "Added TVs device" "$LOG" && break; sleep 1
done
[ -n "$CC" ] || CC=$(grep -o "ChromecastManager: Added device: .* at " "$LOG" | head -1 | sed 's/.*Added device: //; s/ at $//')
[ -n "$DLNA" ] || DLNA=$(grep -o "Added TVs device: .* (" "$LOG" | head -1 | sed 's/.*Added TVs device: //; s/ ($//')
echo "INFO  Chromecast: ${CC:-none}   DLNA TV: ${DLNA:-none}   skin: $SKIN"
for i in $(seq 1 20); do
  osascript skills/app-control/scripts/menu.applescript toggle "$PID" "$i" Visualizations >/dev/null 2>&1 && break
done
sleep 2
read -r WID _ WX WY WW WHEIGHT _ < <($WH windows --pid "$PID" | grep Visualizations)
[ -n "${WID:-}" ] || { echo "FAIL  preflight: no Visualizations window"; exit 1; }

# menu <item> [<sub> [<subsub>]] — right-click the window and click down the context menu by titles.
# items <item> <sub> — "title=enabled" for each entry of that submenu (the menu is then cancelled).
MENU_AS='on run argv
  set {pid, mode, a, b, c} to argv
  tell application "System Events" to tell (first process whose unix id is (pid as integer))
    try
      click (first UI element of (first UI element of window "Visualizations" whose role is "AXMenu") whose title is a)
      if b is "" then return "ok"
      delay 0.4
      click (first UI element of UI element 1 of (first UI element of (first UI element of window "Visualizations" whose role is "AXMenu") whose title is a) whose title is b)
      if mode is "items" then
        delay 0.4
        set out to ""
        repeat with i in (UI elements of UI element 1 of (first UI element of UI element 1 of (first UI element of (first UI element of window "Visualizations" whose role is "AXMenu") whose title is a) whose title is b))
          set out to out & (title of i) & "=" & (enabled of i) & " "
        end repeat
        key code 53
        key code 53
        key code 53
        return out
      end if
      if c is "" then return "ok"
      delay 0.4
      click (first UI element of UI element 1 of (first UI element of UI element 1 of (first UI element of (first UI element of window "Visualizations" whose role is "AXMenu") whose title is a) whose title is b) whose title is c)
      return "ok"
    on error e
      key code 53
      key code 53
      key code 53
      return "FAILED: " & e
    end try
  end tell
end run'
open_menu() {
  $WH raise "$PID" >/dev/null; $WH rclick $((WX + WW / 2)) $((WY + WHEIGHT / 2)) >/dev/null
  for _ in $(seq 10); do $WH windows --pid "$PID" | grep -q "^[0-9]*	101" && break; sleep 0.3; done
}
menu() { open_menu; osascript -e "$MENU_AS" "$PID" click "$1" "${2:-}" "${3:-}"; }
items() { open_menu; osascript -e "$MENU_AS" "$PID" items "$1" "$2" ""; }

mark() { grep -c "" "$LOG"; }
# wait_log <from-line> <regex> <seconds>
wait_log() { for _ in $(seq "$3"); do tail -n +"$(($1 + 1))" "$LOG" | grep -qE "$2" && return 0; sleep 1; done; return 1; }

# settled <from-line> — after the LOAD logged past <from-line>: PLAYING within 15 s, and no BUFFERING
# from 15 s on (the window is the 35 s the caller waited).
settled() {
  tail -n +"$(($1 + 1))" "$LOG" | python3 -I -c '
import re, sys
def t(s): h, m, x = s.split(":"); return int(h) * 3600 + int(m) * 60 + float(x)
load, states = None, []
for line in sys.stdin:
    m = re.match(r"\S+ (\S+) .*Loading media", line)
    if m and load is None: load = t(m.group(1)); continue
    m = re.match(r"\S+ (\S+) .*MEDIA_STATUS - .*state: (PLAYING|BUFFERING)", line)
    if m and load is not None: states.append((t(m.group(1)) - load, m.group(2)))
first = next((s for s, st in states if st == "PLAYING"), None)
late = [s for s, st in states if st == "BUFFERING" and s > 15]
spells = sum(1 for i, (s, st) in enumerate(states) if st == "BUFFERING" and (i == 0 or states[i - 1][1] != st))
print(f"first PLAYING {first if first is None else round(first, 1)} s, {spells} buffering spells, {len(late)} BUFFERING after 15 s")
sys.exit(0 if first is not None and first < 15 and not late else 1)'
}

# probe <file> <width> <height> <fps> — stream shape, colour, continuity, PCR, silence.
probe() {
  python3 -I - "$@" <<'EOF'
import json, subprocess, sys
f, w, h, fps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", f], capture_output=True).stdout)
v = next(s for s in info["streams"] if s["codec_type"] == "video")
a = next(s for s in info["streams"] if s["codec_type"] == "audio")
bad = []
if (v["codec_name"], v["width"], v["height"], v["r_frame_rate"]) != ("h264", w, h, f"{fps}/1"):
    bad.append(f'video {v["codec_name"]} {v["width"]}x{v["height"]} {v["r_frame_rate"]}')
if v.get("color_space") != "bt709" or v.get("color_primaries") != "bt709": bad.append("video not tagged BT.709")
if (a["codec_name"], a["sample_rate"], a["channels"]) != ("aac", "48000", 2): bad.append(f'audio {a["codec_name"]} {a["sample_rate"]} {a["channels"]}')
for sel, limit in (("v", 1.5 / fps), ("a", 0.03)):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", sel, "-show_entries", "packet=pts_time", "-of", "csv=p=0", f], capture_output=True, text=True).stdout
    pts = [float(x.strip(",")) for x in out.split() if x.strip(",")]
    step = max(b - a for a, b in zip(pts, pts[1:]))
    if step > limit: bad.append(f"{sel} timestamps jump {step:.3f} s")
d = open(f, "rb").read()
for i in range(len(d) // 188):   # first PCR on the video PID, against the PTS in the same packet
    p = d[i * 188:(i + 1) * 188]
    if ((p[1] & 0x1F) << 8 | p[2]) != 0x100 or not p[3] & 0x20 or not p[4] or not p[5] & 0x10 or not p[1] & 0x40: continue
    b = p[6:12]; pcr = ((b[0] << 25) | (b[1] << 17) | (b[2] << 9) | (b[3] << 1) | (b[4] >> 7)) / 90000
    o = 5 + p[4]; q = p[o + 9:o + 14]
    pts = ((((q[0] >> 1) & 7) << 30) | (q[1] << 22) | ((q[2] >> 1) << 15) | (q[3] << 7) | (q[4] >> 1)) / 90000
    if abs(pts - pcr) > 0.001: bad.append(f"PCR {pts - pcr:.3f} s behind the PTS")
    break
pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", f, "-map", "0:a", "-f", "s16le", "-ac", "1", "-ar", "48000", "-"], capture_output=True).stdout
samples = memoryview(pcm).cast("h")[2400:]   # skip 50 ms: the decoder's start-up delay decodes as zeros
run = gaps = 0
for s in samples:
    run = run + 1 if s == 0 else 0
    if run == 48: gaps += 1
if gaps: bad.append(f"{gaps} silent gaps of 1 ms or more (is music playing?)")
print("; ".join(bad) or f"{w}x{h} {fps} fps h264 BT.709, AAC 48 kHz stereo, continuous, PCR level, no gaps")
sys.exit(1 if bad else 0)
EOF
}

# window_pair <png-a> <png-b> — two captures 1 s apart; prints "<dark fraction> <changed fraction>"
# of the window's middle.
window_pair() {
  screencapture -x -o -l "$WID" "$1"; sleep 1; screencapture -x -o -l "$WID" "$2"
  python3 -I - "$1" "$2" <<'EOF'
import subprocess, sys
def gray(p):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-vf", "scale=200:200,format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
    return [r[y * 200 + x] for y in range(30, 170) for x in range(30, 170)]
a, b = gray(sys.argv[1]), gray(sys.argv[2])
print(f"{sum(v < 24 for v in a) / len(a):.2f} {sum(abs(x - y) > 8 for x, y in zip(a, b)) / len(a):.3f}")
EOF
}

# frame_fills <file> — the rightmost tenth of a few frames is not empty (a half-drawn engine leaves it black).
frame_fills() {
  for n in 30 60 90; do
    ffmpeg -v error -y -i "$1" -vf "select=eq(n\,$n),crop=iw/10:ih:iw*9/10:0,scale=40:-1,format=gray" -frames:v 1 -f rawvideo "$OUT/strip.raw" 2>/dev/null
    python3 -I -c "import sys; sys.exit(0 if max(open('$OUT/strip.raw','rb').read() or b'\0') > 40 else 1)" && return 0
  done
  return 1
}

if [ -n "$CC" ]; then
  # --- Chromecast: the EVENT playlist starts it 6 s back, so it plays after one buffering ---------
  m=$(mark); menu "Cast Visualization" "$CC" >/dev/null
  if wait_log "$m" "VisualizationCast: casting to" 30; then
    sleep 35; r=$(settled "$m"); check $? "Chromecast '$CC' 1080p30 settles: $r"
    pl=$(curl -s -m 3 "$URL/live.m3u8")
    echo "$pl" | grep -q "^#EXT-X-PLAYLIST-TYPE:EVENT" && echo "$pl" | grep -q "^#EXT-X-START:TIME-OFFSET=-6.0" \
      && echo "$pl" | grep -q "^#EXT-X-MEDIA-SEQUENCE:0" && ! echo "$pl" | grep "^#EXTINF" | grep -vq "^#EXTINF:1.000,"
    check $? "playlist is EVENT, starts 6 s back, lists every 1 s segment from 0"
    curl -s -m 10 "$URL/live.ts" -o "$OUT/cc1080.ts"; r=$(probe "$OUT/cc1080.ts" 1920 1080 30); check $? "stream: $r"
    read -r dark changed < <(window_pair "$OUT/win-cast-a.png" "$OUT/win-cast-b.png")
    python3 -I -c "import sys; sys.exit(0 if $dark > 0.85 and $changed < 0.01 else 1)"
    check $? "window is dark and still under the note while casting (dark $dark, changed $changed)"
    menu "Visualization Engine" "AVS" >/dev/null; sleep 4; menu "Visualization Engine" "ProjectM" >/dev/null; sleep 5
    curl -s -m 5 "$URL/live.ts" -o "$OUT/switch.ts"; frame_fills "$OUT/switch.ts"
    check $? "after AVS → ProjectM mid-cast the picture fills the frame (right edge drawn)"
    m=$(mark); menu "Cast Visualization" "Frame Rate" "60 fps" >/dev/null
    if wait_log "$m" "starting to .*frameRate: 60" 10 && wait_log "$m" "VisualizationCast: casting to" 30; then
      sleep 35; r=$(settled "$m"); check $? "switch to 60 fps restarts (no hang) and settles: $r"
      curl -s -m 6 "$URL/live.ts" -o "$OUT/cc60.ts"; r=$(probe "$OUT/cc60.ts" 1920 1080 60); check $? "60 fps stream: $r"
    else
      fail "switch to 60 fps did not restart the cast (hang? see $LOG)"
    fi
    menu "Cast Visualization" "Frame Rate" "30 fps" >/dev/null; sleep 10
    m=$(mark); menu "Cast Visualization" "Stop Casting Visualization" >/dev/null
    wait_log "$m" "VisualizationCast: stopped" 10; sleep 3
    read -r dark changed < <(window_pair "$OUT/win-stop-a.png" "$OUT/win-stop-b.png")
    python3 -I -c "import sys; sys.exit(0 if $changed > 0.01 else 1)"
    check $? "after Stop the window draws the visualization again (changed $changed)"
  else
    fail "Chromecast '$CC': the cast never started (see $LOG)"
  fi
fi

if [ -n "$DLNA" ]; then
  # --- DLNA: an endless live.ts, HEAD answered chunked; 4K at 30 fps only ------------------------
  m=$(mark); menu "Cast Visualization" "$DLNA" >/dev/null
  if wait_log "$m" "VisualizationCast: casting to" 30; then
    tail -n +"$((m + 1))" "$LOG" | grep -q "HEAD live.ts from" && tail -n +"$((m + 1))" "$LOG" | grep -q "GET live.ts from"
    check $? "DLNA '$DLNA' plays: the TV HEADs and GETs live.ts"
    hdr=$(curl -s -m 3 -I -H "getcontentFeatures.dlna.org: 1" "$URL/live.ts" | tr -d '\r')
    echo "$hdr" | grep -qi "^transfer-encoding: chunked" && ! echo "$hdr" | grep -qi "^content-length: 0" \
      && echo "$hdr" | grep -q "DLNA.ORG_FLAGS=0170"
    check $? "HEAD live.ts is chunked (no Content-Length: 0) with the live DLNA flags"
    m=$(mark); menu "Cast Visualization" "Resolution" "4K" >/dev/null
    wait_log "$m" "starting to .*uhd, frameRate: 30" 10; check $? "4K starts at 30 fps"
    wait_log "$m" "VisualizationCast: casting to" 30
    r=$(items "Cast Visualization" "Frame Rate"); [ "$r" = "30 fps=true 60 fps=false " ]
    check $? "at 4K the Frame Rate menu offers only 30 fps" "$r"
    curl -s -m 6 "$URL/live.ts" -o "$OUT/dlna4k.ts"; r=$(probe "$OUT/dlna4k.ts" 3840 2160 30); check $? "4K stream: $r"
    m=$(mark); menu "Cast Visualization" "Resolution" "1080p" >/dev/null; wait_log "$m" "VisualizationCast: casting to" 30
    menu "Cast Visualization" "Stop Casting Visualization" >/dev/null
  else
    fail "DLNA '$DLNA': the cast never started (see $LOG)"
  fi
fi

[ -n "$CC$DLNA" ] || fail "no Chromecast or DLNA TV discovered"
echo "$([ $FAILS = 0 ] && echo PASS || echo FAIL)  viscast-test: $FAILS failed (logs in $OUT)"
[ $FAILS = 0 ]
