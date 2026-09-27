#!/bin/bash
# User-level regression test: a window left OPEN across skin switches through every UI mode never
# keeps the previous skin's size. Usage:
#
#   skills/app-control/scripts/skin-mode-switch-test.sh "<Windows menu item>"
#
# Pick windows by how their size is decided, not all of them:
#   "Spectrum Analyzer"  centre stack, `.wmz` border, classic resetToDefaultFrame — stands in for
#                        Cava, Flow, Audio Analyzer, PeppyMeter, Waveform
#   "Visualizations"     side window, no reset, its own last-frame cache — stands in for Library
#   "Sonos Rooms"        its own show path, width once taken from the player
#
# The chain enters every mode from another mode and switches skin within every mode:
#   Ice → anemone → Classic → Classic' → Original → Original' → Metal → Metal' → .wal → .wal' →
#   .wmz (anemone) → Ice
# Before every switch the window is resized by +38x28, so a leak is visible. After every switch:
#   open      the window is still open
#   no-leak   its size is not the size it had just before the switch
#   own       back in Ice or anemone it has the size it was given there
#   classic   in Classic it has the classic default for that window
# One row per switch, then `SWITCH-TEST PASS|FAIL (<n>)` and a matching exit status. About 3-4
# minutes; it drives the menus and two-point drags on the window, and saves and restores the debug
# `NullPlayer` defaults domain.
cd "$(dirname "$0")/../../.." || exit 1
WH=skills/app-control/scripts/winhelper
MA=skills/app-control/scripts/menu.applescript
ITEM=${1:?usage: skin-mode-switch-test.sh \"<Windows menu item>\" [--expected <census windows.tsv>...]}
shift
# Optional: `window-census.sh` windows.tsv files for the chain's skins. A switch into another mode must
# then land on that skin's fresh-launch size — the size a first open in that mode gives.
EXPECTED=()
while [ $# -gt 0 ]; do case "$1" in --expected) EXPECTED+=("$2"); shift 2 ;; *) shift ;; esac; done
fresh_size() {  # fresh_size <menu skin name>
  [ ${#EXPECTED[@]} -gt 0 ] || return 0
  awk -F'\t' -v s="$1" -v i="$ITEM" 'FNR>1 && $6=="opened" && $5==i { n=$2; sub(/^[a-z]+:/, "", n); if (n==s) print $11"x"$12 }' "${EXPECTED[@]}" | head -1
}
LOG=/tmp/np-switch-test.log
BASE=$(mktemp -t np-switch-test-defaults).plist
PID=""; ROW=""; FAILS=0; CUR_SKIN=""; CUR_SUB=""
OWN=""   # lines of <skin>|<size>: the size each skin was last left at (bash 3.2 has no maps)
own_get() { echo "$OWN" | awk -F'|' -v s="$1" '$1==s{v=$2} END{print v}'; }

skills/app-control/scripts/build.sh >/dev/null || { echo "SWITCH-TEST FAIL: winhelper did not build"; exit 1; }
quit_debug() {
  [ -n "$PID" ] || return 0
  kill "$PID" 2>/dev/null
  for _ in $(seq 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$PID" 2>/dev/null
}
restore_defaults() { defaults delete NullPlayer 2>/dev/null; defaults import NullPlayer "$BASE"; rm -f "$BASE"; }
defaults export NullPlayer "$BASE" || { echo "SWITCH-TEST FAIL: could not save the NullPlayer defaults"; exit 1; }
trap 'quit_debug; restore_defaults' EXIT
die() { echo "ABORT: $*" >&2; echo "SWITCH-TEST FAIL (aborted)"; exit 1; }

item_field() { osascript $MA windowitems "$PID" | awk -F'|' -v n="$ITEM" -v f="$1" '$2==n{print $f}'; }
is_main() { [[ "$1" == "NullPlayer" || "$1" == "NullPlayer — "* ]]; }
title_re() {
  case "$ITEM" in
    "Spectrum Analyzer") echo '^(NullPlayer Analyzer|Spectrum Analyzer)$' ;;
    *) echo "^$ITEM\$" ;;
  esac
}
# The window's row: by title where the mode gives it one, else the only window that is not the player.
find_window() {
  local rows others
  RESIZED=${RESIZED:-0}
  rows=$($WH windows --pid "$PID" | awk -F'\t' '$2==0')
  ROW=$(echo "$rows" | awk -F'\t' -v re="$(title_re)" '$8 ~ re' | head -1)
  [ -n "$ROW" ] && return 0
  others=$(echo "$rows" | while IFS=$'\t' read -r id l x y w h a t; do is_main "$t" || printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$l" "$x" "$y" "$w" "$h" "$a" "$t"; done)
  [ "$(echo "$others" | grep -c .)" = "1" ] && ROW=$others && return 0
  ROW=""; return 1
}
size_of() { echo "$ROW" | awk -F'\t' '{print $5"x"$6}'; }
open_menus() { $WH windows --pid "$PID" | awk -F'\t' '$2!=0' | grep -c .; }

ensure_open() {
  if [ "$(item_field 4)" != "1" ]; then
    osascript $MA toggle "$PID" "$(item_field 1)" "$ITEM" >/dev/null || die "toggle $ITEM"
    sleep 5
  fi
  find_window || die "cannot find the $ITEM window"
}

resize() {
  local X Y W H
  find_window || die "cannot find the $ITEM window to resize"
  read -r _ _ X Y W H _ <<<"$ROW"
  local was; was=$(size_of)
  [ -n "$X" ] && [ -n "$W" ] && [ -n "$H" ] || die "empty geometry"
  RESIZED=0
  $WH raise "$PID" >/dev/null || die "raise"
  # A refused press (the corner is covered or off screen) posts nothing; the switch still runs and
  # the row says the window was not resized, which weakens that row's leak check.
  $WH click $((X + W / 2)) $((Y + H / 2)) >/dev/null 2>&1 || return 0
  sleep 0.4
  $WH drag $((X + W - 2)) $((Y + H - 2)) $((X + W + 20)) $((Y + H + 15)) $((X + W + 38)) $((Y + H + 28)) \
    >/dev/null 2>&1 || return 0
  sleep 1.5
  find_window || die "window lost after resize"
  # Counted only when the size moved: a skin frame whose corner is not a drag handle takes the drag
  # and stays put, and its unchanged size is not a leak.
  [ "$(size_of)" != "$was" ] && RESIZED=1
}

# The classic default for this window: width of the classic main window, height per window.
classic_default() {
  local main_w main_h
  main_w=$($WH windows --pid "$PID" | awk -F'\t' '$2==0 && $8=="NullPlayer"{print $5; exit}')
  main_h=$($WH windows --pid "$PID" | awk -F'\t' '$2==0 && $8=="NullPlayer"{print $6; exit}')
  case "$ITEM" in
    "Spectrum Analyzer") echo "${main_w}x${main_h}" ;;
    "Sonos Rooms") echo "${main_w}x$(( 270 * main_h / 145 ))" ;;
    "Visualizations") echo "550x$(( 4 * main_h ))" ;;
  esac
}

row() { printf '%-34s %-10s %-10s %s\n' "$1" "$2" "$3" "$4"; }
verdict() {  # verdict <label> <before> <after> <target skin> <mode> <expect: change|keep>
  local label=$1 before=$2 after=$3 skin=$4 mode=$5 expect=$6 notes="" bad=0
  [ -n "$after" ] || { notes="CLOSED"; bad=1; }
  # Within Classic, and within Original/Metal (one family in the code), an open window has always
  # kept the user's stretch across a skin change; nothing there is saved or carried from hosted
  # chrome, and changing it would change Classic/Original behaviour. So those switches expect it kept.
  if [ "$bad" = 0 ] && [ "$expect" = keep ]; then
    if [ "$after" = "$before" ]; then notes="kept (in-family, as before)"
    else notes="expected kept $before"; bad=1; fi
    [ "$(open_menus)" = 0 ] || { notes="$notes; MENU LEFT OPEN"; bad=1; }
    [ "$bad" = 0 ] && notes="PASS  $notes" || { notes="FAIL  $notes"; FAILS=$((FAILS + 1)); }
    row "$label" "$before" "$after" "$notes"; return
  fi
  if [ "$bad" = 0 ] && [ "$after" = "$before" ]; then
    [ "$RESIZED" = 1 ] && { notes="LEAK (kept previous size)"; bad=1; } || notes="not resized; unchanged"
  fi
  if [ "$bad" = 0 ] && [ -n "$(own_get "$skin")" ] && [ "$mode" = wmz ]; then
    if [ "$after" = "$(own_get "$skin")" ]; then notes="own size restored"
    else notes="expected own $(own_get "$skin")"; bad=1; fi
  fi
  local fresh; fresh=$(fresh_size "$skin")
  if [ "$bad" = 0 ] && [ -n "$fresh" ] && [ "$kind" = mode ] && [ "$mode" != wmz ]; then
    if [ "$after" = "$fresh" ]; then notes="$notes fresh-launch size"
    else notes="expected fresh-launch $fresh"; bad=1; fi
  fi
  if [ "$bad" = 0 ] && [ "$mode" = classic ]; then
    local want; want=$(classic_default)
    if [ "$after" = "$want" ]; then notes="classic default"
    else notes="expected classic default $want"; bad=1; fi
  fi
  [ "$(open_menus)" = 0 ] || { notes="$notes; MENU LEFT OPEN"; bad=1; }
  [ "$bad" = 0 ] && notes="PASS  $notes" || { notes="FAIL  $notes"; FAILS=$((FAILS + 1)); }
  row "$label" "$before" "$after" "$notes"
}

# One switch: resize first, then switch, then judge.
switch() {  # switch <label> <mode> <expect> <kind: skin|mode> <submenu> [<skin>]
  local label=$1 mode=$2 expect=$3 kind=$4 sub=$5 skin=$6 before after
  resize; before=$(size_of); OWN="$OWN
$CUR_SKIN|$before"
  if [ "$kind" = mode ]; then
    osascript $MA mode "$PID" "$sub" >/dev/null || die "Skins > $sub > Switch to"
    sleep 10
    skin=$(osascript $MA current "$PID" "$sub")
  else
    osascript $MA skin "$PID" "$sub" "$skin" >/dev/null || die "Skins > $sub > $skin"
    sleep 8
  fi
  CUR_SKIN=${skin:-?$sub}; CUR_SUB=$sub
  if find_window; then after=$(size_of); else after=""; fi
  local shown=$label; [ "$RESIZED" = 1 ] || shown="$label (not resized)"
  verdict "$shown → $CUR_SKIN" "$before" "$after" "$CUR_SKIN" "$mode" "$expect"
  [ -n "$after" ] || { ensure_open; }
}
# The other of a mode's two skins, whichever one a mode switch landed on.
other() { [ "$CUR_SKIN" = "$1" ] && echo "$2" || echo "$1"; }

echo "== $ITEM"
skills/app-control/scripts/launch.sh Ice.wmz --log "$LOG" | tail -1 | grep -q PASS || die "launch Ice"
PID=$(pgrep -f '\.build/.*/debug/NullPlayer' | head -1); [ -n "$PID" ] || die "no debug pid"
for k in $(defaults read NullPlayer | grep -o '"hostedInteriorSize3[^"]*"' | tr -d '"'); do defaults delete NullPlayer "$k"; done
osascript $MA closeaux "$PID" >/dev/null
CUR_SKIN=Ice; CUR_SUB="Media Player"
ensure_open
row "switch" "before" "after" "result"
switch ".wmz Ice (in place)"   wmz      change skin "Media Player" anemone
switch ".wmz → Classic"        classic  change mode "Classic"
switch "Classic (in place)"    classic  keep   skin "Classic" "$(other aquamp 'base-2.91 (1)')"
switch "Classic → Original"    original change mode "Original"
switch "Original (in place)"   original keep   skin "Original" "$(other NeonWave ArcticMinimal)"
switch "Original → Metal"      metal    keep   mode "Original-Metal"
switch "Metal (in place)"      metal    keep   skin "Original-Metal" "$(other 'Brushed Steel' Gunmetal)"
switch "Metal → .wal"          wal      change mode "Modern"
switch ".wal (in place)"       wal      change skin "Modern" "$(other Firefox 2222-cPro__Bento)"
switch ".wal → .wmz"           wmz      change mode "Media Player"
switch ".wmz (in place)"       wmz      change skin "Media Player" "$(other Ice anemone)"
echo
if [ "$FAILS" = 0 ]; then echo "SWITCH-TEST PASS"; exit 0; fi
echo "SWITCH-TEST FAIL ($FAILS)"; exit 1
