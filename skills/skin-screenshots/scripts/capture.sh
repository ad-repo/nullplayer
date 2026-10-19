#!/bin/bash
# One centred shot of the MAIN window per skin, for every skin system.
#
#   capture.sh [--list FILE] [--frame 800] [--out DIR] [--settle SECONDS] [--only REGEX] [--allow-extra REGEX] [--log FILE]
#
# Writes <out>/<label>_<YYYY-MM-DD_HHMMSS>.png (white frame, for the GIF), the raw transparent
# window shot to <out>/raw/<label>.png (the site source), and a manifest TSV recording every
# decision, so a run can be audited and re-run for just the rows that went wrong.
#
# The main window is matched by its EXACT title for the family (see main_title); a row is shot
# only when exactly one such window exists and no other NullPlayer window is on screen.
# --settle overrides the per-family settle; ../settle.tsv (skin<TAB>seconds) overrides both.
# --allow-extra REGEX shoots the matching labels despite other windows on screen, recording
#   `extra-ignored` in the framing column; use it only after looking at the shot, since
#   `screencapture -l` of a docked group returns the whole group as one image.
# --log is the app's log, used to confirm a .wal has rendered (default $NULLPLAYER_LOG, /tmp/np.log).
set -u
cd "$(dirname "$0")"
LIST=""; FRAME=800; OUT="$HOME/Documents/shots"; SETTLE=""; ONLY=""; ALLOW=""; LOG="${NULLPLAYER_LOG:-/tmp/np.log}"
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST="$2"; shift 2;; --frame) FRAME="$2"; shift 2;;
    --out) OUT="$2"; shift 2;; --settle) SETTLE="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;; --log) LOG="$2"; shift 2;; --allow-extra) ALLOW="$2"; shift 2;; *) echo "unknown arg $1"; exit 2;;
  esac
done
../../app-control/scripts/build.sh >/dev/null
# The tools live in `app-control`; this sweep is one of their callers.
WH=../../app-control/scripts/winhelper
MENU=../../app-control/scripts/menu.applescript
# menu.applescript addresses the app by unix id, never by name — see `app-control` Rule zero.
PID="${NULLPLAYER_PID:-$(pgrep -x NullPlayer | head -1)}"
if [ -z "$PID" ]; then echo "FAIL  NullPlayer is not running"; exit 1; fi
if [ "$(pgrep -x NullPlayer | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "FAIL  more than one NullPlayer is running; set NULLPLAYER_PID to the debug build you launched"; exit 1
fi
export NULLPLAYER_PID="$PID"

SETTLE_TSV="$(pwd)/../settle.tsv"
RAW="$OUT/raw"; mkdir -p "$OUT" "$RAW"
STAMP=$(date +"%Y%m%d_%H%M%S"); MAN="$OUT/manifest_$STAMP.tsv"
printf 'label\tsystem\titem\tstatus\twindow_pt\tart_pt\tframing\tfile\ttitle\twindow_id\tshadows\n' > "$MAN"
if [ -z "$LIST" ]; then LIST="$(mktemp)"; ./enumerate_skins.sh > "$LIST"; fi

# The main window's exact title per family (window.title = ... in each *MainWindowController).
# A prefix match is wrong: "NullPlayer Analyzer", "NullPlayer Art" and the WMP view windows
# ("NullPlayer — <view>") all start with it and sort ahead of the real one.
main_title() { case "$1" in
  modern) echo "NullPlayer — Winamp Modern";; wmp) echo "NullPlayer — Windows Media Player";;
  audion) echo "NullPlayer — Audion Faces";; *) echo "NullPlayer";; esac; }
# Time for animations after the skin is confirmed loaded.
family_settle() { case "$1" in modern) echo 15;; wmp) echo 15;; *) echo 0.5;; esac; }
settle_for() { # $1 system $2 item
  local o; o=$(awk -F'\t' -v k="$2" '$1==k{print $2; exit}' "$SETTLE_TSV" 2>/dev/null)
  if [ -n "$o" ]; then echo "$o"; elif [ -n "$SETTLE" ]; then echo "$SETTLE"; else family_settle "$1"; fi; }
# This process's on-screen layer-0 windows (shadow windows are already filtered out):
#   id <TAB> layer <TAB> x <TAB> y <TAB> w <TAB> h <TAB> alpha <TAB> title
wins() { "$WH" windows --pid "$PID" | awk -F'\t' '$2==0 && $7>0'; }
wal_count() { grep -c 'WinampModern surfaces \[' "$LOG" 2>/dev/null || echo 0; }
# Window Shadows (default on). Read live from the app's defaults: the sweep's own menu driving
# once switched it off mid-run, which left shadowless shots that looked fine.
shadows() { local v; v=$(defaults read NullPlayer skinWindowShadows 2>/dev/null); [ "$v" = 0 ] && echo off || echo on; }
rec() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" "${6:-}" "${7:-}" "${8:-}" "${9:-}" "${10:-}" "$(shadows)" >> "$MAN"; }
[ -r "$LOG" ] || echo "note  no app log at $LOG: .wal render is confirmed by the family settle alone"

cursys=""
while IFS=$'\t' read -r sys sub item label; do
  [ -z "${label:-}" ] && continue
  [ -n "$ONLY" ] && { echo "$label" | grep -Eq "$ONLY" || continue; }
  printf '%s ... ' "$label"
  pgrep -x NullPlayer >/dev/null || { echo "APP-DEAD"; rec "$label" "$sys" "$item" app-dead; break; }
  want=$(main_title "$sys")

  # Switching SYSTEM needs the submenu's "Switch to ..." item; a skin name alone won't do it.
  if [ "$sys" != "$cursys" ]; then
    timeout 30 osascript "$MENU" mode "$PID" "$sub" >/dev/null 2>&1; sleep 4; cursys="$sys"
  fi

  walbefore=$(wal_count)
  ok=""; for t in 1 2 3; do timeout 30 osascript "$MENU" skin "$PID" "$sub" "$item" >/dev/null 2>&1 && { ok=1; break; }; sleep 2; done
  [ -z "$ok" ] && { echo "MENU-FAIL"; rec "$label" "$sys" "$item" menu-fail "" "" "" "" "$want"; continue; }

  # Loaded = the menu names this skin as checked. Geometry is no signal: same-size skins never
  # change it, and a heavy .wal leaves the old window up unchanged while it loads.
  # A skin that pegs the app's main thread makes every menu call hang (211786-Cpro, 2026-10-11),
  # so each call is bounded and the whole wait is capped at 60 s.
  loaded=""; t0=$SECONDS
  while [ $((SECONDS - t0)) -lt 60 ]; do
    [ "$(timeout 30 osascript "$MENU" current "$PID" "$sub" 2>/dev/null)" = "$item" ] && { loaded=1; break; }
    sleep 0.25
  done
  [ -z "$loaded" ] && { echo "NOT-LOADED"; rec "$label" "$sys" "$item" not-loaded "" "" "" "" "$want"; continue; }
  # The menu ticks before a .wal renders; its surfaces line is the render marker.
  if [ "$sys" = modern ] && [ -r "$LOG" ]; then
    for i in $(seq 1 120); do [ "$(wal_count)" -gt "$walbefore" ] && break; sleep 0.25; done
  fi
  sleep "$(settle_for "$sys" "$item")"

  # Nothing but the main window may be on screen: screencapture -l returns a docked group as
  # one image, and a sub-window opened by the skin must not be mistaken for the main one.
  extras=$(wins | awk -F'\t' -v t="$want" '$8!=t' | wc -l | tr -d ' ')
  if [ "$extras" -gt 0 ]; then
    timeout 30 osascript "$MENU" closeaux "$PID" >/dev/null 2>&1; sleep 1
  fi
  all=$(wins)
  mains=$(printf '%s\n' "$all" | awk -F'\t' -v t="$want" '$8==t')
  nmain=$(printf '%s' "$mains" | grep -c .)
  extras=$(printf '%s\n' "$all" | awk -F'\t' -v t="$want" 'NF && $8!=t' | wc -l | tr -d ' ')
  if [ "$nmain" -eq 0 ]; then echo "NO-MAIN"; rec "$label" "$sys" "$item" no-main "" "" "" "" "$want"; continue; fi
  if [ "$nmain" -gt 1 ]; then echo "AMBIGUOUS ($nmain)"; rec "$label" "$sys" "$item" ambiguous "" "" "" "" "$want"; continue; fi
  allowed=""
  [ "$extras" -gt 0 ] && [ -n "$ALLOW" ] && echo "$label" | grep -Eq "$ALLOW" && allowed="extra-ignored"
  if [ "$extras" -gt 0 ] && [ -z "$allowed" ]; then
    names=$(printf '%s\n' "$all" | awk -F'\t' -v t="$want" 'NF && $8!=t{printf "%s|", $8}')
    echo "EXTRA-WINDOWS $names"; rec "$label" "$sys" "$item" extra-windows "" "" "$names" "" "$want"; continue
  fi
  IFS=$'\t' read -r id _ x y w h _ title <<< "$mains"

  if [ "$(shadows)" = off ]; then echo "SHADOWS-OFF"; rec "$label" "$sys" "$item" shadows-off "" "" "" "" "$title" "$id"; break; fi

  raw="$RAW/$label.png"; rm -f "$raw"
  screencapture -o -x -l "$id" "$raw" 2>/dev/null
  [ -s "$raw" ] || { echo "CAPTURE-FAIL"; rec "$label" "$sys" "$item" capture-fail "${w}x${h}" "" "" "" "$title" "$id"; continue; }

  read -r status art framing file < <(./reframe.sh "$raw" "$w" "$h" "$FRAME" "$OUT" "$label")
  [ -n "$allowed" ] && framing="$framing+$allowed"
  echo "$status ${w}x${h}pt art=$art $framing"
  rec "$label" "$sys" "$item" "$status" "${w}x${h}" "$art" "$framing" "$file" "$title" "$id"
done < "$LIST"
echo "DONE  manifest: $MAN"
