#!/bin/bash
# User-level regression test for skin window-size isolation: no skin inherits another skin's (or
# another mode's) window sizes. Drives the debug build through real menu picks and one real resize
# per skin, and checks what is on screen plus what was saved. Usage:
#
#   skills/app-control/scripts/size-isolation-test.sh [<wmz A> <wmz B>]     # default: Ice anemone
#
# A and B must be installed `.wmz` skins that lend a border to NullPlayer's windows, so a size can
# be saved for them. The Classic leg uses the Skins menu's "Switch to Classic", i.e. whichever
# classic skin was last used.
#
# The sequence, and the rule each step checks:
#   1. A: open the analyser, resize it           -> saved under A, and only A
#   2. switch to B in place                      -> B's default size, nothing saved under B
#   3. back to A                                 -> A's resized size again
#   4. B again                                   -> B's default again (stable)
#   5. mode switch to Classic                    -> the Classic default (the main window's width,
#                                                   the classic height), not B's frame
#   6. resize it in Classic                      -> nothing saved anywhere
#   7. mode switch back to WMP (B)               -> B's default, not the Classic size
#   every step                                   -> no menu left open
#
# One PASS/FAIL line per check, then `SIZE-ISOLATION PASS` or `SIZE-ISOLATION FAIL (<n>)`, and the
# exit status to match. It takes the machine for about two minutes (menu picks, two drags) and quits
# any running debug build. The debug `NullPlayer` defaults domain is saved at the start and put back
# on exit, so the run leaves no sizes behind; the installed app is never touched.
cd "$(dirname "$0")/../../.." || exit 1
WH=skills/app-control/scripts/winhelper
MA=skills/app-control/scripts/menu.applescript
A=${1:-Ice}; B=${2:-anemone}
LOG=/tmp/np-size-isolation.log
BASE=$(mktemp -t np-size-isolation-defaults).plist
PID=""; ANA=""; ROW=""; FAILS=0

skills/app-control/scripts/build.sh >/dev/null || { echo "SIZE-ISOLATION FAIL: winhelper did not build"; exit 1; }

quit_debug() {
  [ -n "$PID" ] || return 0
  kill "$PID" 2>/dev/null
  for _ in $(seq 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$PID" 2>/dev/null
}
restore_defaults() { defaults delete NullPlayer 2>/dev/null; defaults import NullPlayer "$BASE"; rm -f "$BASE"; }
defaults export NullPlayer "$BASE" || { echo "SIZE-ISOLATION FAIL: could not save the NullPlayer defaults"; exit 1; }
trap 'quit_debug; restore_defaults' EXIT

# An abort is not a result: something the test relies on did not happen, so nothing after it counts.
die() { echo "ABORT: $*" >&2; echo "SIZE-ISOLATION FAIL (aborted)"; exit 1; }
check() {  # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "PASS  $1: $2"
  else echo "FAIL  $1: got $2, expected $3"; FAILS=$((FAILS + 1)); fi
}
check_differs() {  # check_differs <label> <actual> <must-not-equal>
  if [ "$2" != "$3" ]; then echo "PASS  $1: $2 (not $3)"
  else echo "FAIL  $1: got $2, which is the size it must not inherit"; FAILS=$((FAILS + 1)); fi
}

skinkey() { local lower; lower=$(echo "$1" | tr '[:upper:]' '[:lower:]'); echo "${#1}:$lower"; }
stored() {  # the interior saved for the analyser under a `.wmz` skin, as WxH, or "none"
  defaults read NullPlayer "hostedInteriorSize3.$(skinkey "$1").SpectrumWindow" 2>/dev/null \
    | tr -d ' ;\n' | sed -E 's/.*h=([0-9.]+).*w=([0-9.]+).*/\2x\1/; s/^\{\}$//' | grep . || echo none
}
all_keys() { defaults read NullPlayer 2>/dev/null | grep -o '"hostedInteriorSize3[^"]*"' | sort | tr '\n' ' '; }
open_menus() { $WH windows --pid "$PID" | awk -F'\t' '$2!=0' | grep -c .; }
check_no_menu() { check "$1: menus left open" "$(open_menus)" 0; }

spectrum_item() { osascript $MA windowitems "$PID" | awk -F'|' -v f="$1" '$2=="Spectrum Analyzer"{print $f}'; }
size_of() { echo "$ROW" | awk -F'\t' '{print $5"x"$6}'; }
main_row() { $WH windows --pid "$PID" | awk -F'\t' '$2==0 && ($8=="NullPlayer" || $8 ~ /^NullPlayer — /)' | head -1; }

# The analyser's row, opening it if the menu says it is closed. It is found as the one non-main
# window — every other window is closed — so no per-mode title is assumed.
analyser() {
  local others
  if [ "$(spectrum_item 4)" != "1" ]; then
    osascript $MA toggle "$PID" "$(spectrum_item 1)" "Spectrum Analyzer" >/dev/null || die "Spectrum Analyzer toggle"
    sleep 5
  fi
  [ "$(spectrum_item 4)" = "1" ] || die "the Spectrum Analyzer did not open"
  others=$($WH windows --pid "$PID" | awk -F'\t' '$2==0 && $8!="NullPlayer" && $8 !~ /^NullPlayer — /')
  [ "$(echo "$others" | grep -c .)" = "1" ] || die "expected exactly one window besides the player, got: $(echo "$others" | cut -f1,5,6 | tr '\n' ' ')"
  ROW=$others; ANA=$(echo "$ROW" | cut -f1)
}

# Drag the analyser's bottom-right corner out by 40x30. The press is refused by winhelper unless it
# lands on NullPlayer, and the geometry is checked here first, so an empty lookup cannot post anything.
resize_analyser() {
  local X Y W H
  read -r _ _ X Y W H _ <<<"$ROW"
  [ -n "$X" ] && [ -n "$W" ] && [ -n "$H" ] || die "empty analyser geometry"
  $WH raise "$PID" >/dev/null || die "could not raise the app"
  $WH click $((X + W / 2)) $((Y + H / 2)) || die "activation click refused"
  sleep 0.5
  $WH drag $((X + W - 2)) $((Y + H - 2)) $((X + W + 20)) $((Y + H + 15)) $((X + W + 38)) $((Y + H + 28)) \
    || die "resize drag refused"
  sleep 2
  analyser
}

switch_skin() { osascript $MA skin "$PID" "Media Player" "$1" >/dev/null || die "Skins > Media Player > $1"; sleep 8; }
switch_mode() { osascript $MA mode "$PID" "$1" >/dev/null || die "Skins > $1 > Switch to"; sleep 10; }

echo "== launch $A"
skills/app-control/scripts/launch.sh "$A.wmz" --log "$LOG" | tail -1 | grep -q PASS || die "launch $A"
PID=$(pgrep -f '\.build/.*/debug/NullPlayer' | head -1); [ -n "$PID" ] || die "no debug pid"
# Start from nothing saved for either skin, so every expectation below is this run's own.
defaults delete NullPlayer "hostedInteriorSize3.$(skinkey "$A").SpectrumWindow" 2>/dev/null
defaults delete NullPlayer "hostedInteriorSize3.$(skinkey "$B").SpectrumWindow" 2>/dev/null
osascript $MA closeaux "$PID" >/dev/null
analyser; A_DEFAULT=$(size_of)
echo "      $A default: $A_DEFAULT"
resize_analyser; A_RESIZED=$(size_of)
check_differs "$A resize took" "$A_RESIZED" "$A_DEFAULT"
[ "$(stored "$A")" != none ] && check "$A resize saved under $A" saved saved || check "$A resize saved under $A" none saved
check "$A resize saved nothing under $B" "$(stored "$B")" none
check_no_menu "$A"

echo "== switch to $B in place"
switch_skin "$B"; analyser; B_DEFAULT=$(size_of)
check_differs "$B does not inherit $A's size" "$B_DEFAULT" "$A_RESIZED"
check "the switch saved nothing under $B" "$(stored "$B")" none
check_no_menu "$B"

echo "== back to $A"
switch_skin "$A"; analyser
check "$A restores its own size" "$(size_of)" "$A_RESIZED"
check_no_menu "$A again"

echo "== $B again"
switch_skin "$B"; analyser
check "$B's default is stable" "$(size_of)" "$B_DEFAULT"

echo "== mode switch to Classic"
KEYS_BEFORE=$(all_keys)
switch_mode "Classic"; analyser
MAIN_W=$(main_row | cut -f5)
[ -n "$MAIN_W" ] || die "no Classic main window"
# The Classic default: the classic main window's width (275 x scale) by the classic analyser height,
# which is the main window's own height at every UI size.
check "Classic opens at the Classic default" "$(size_of)" "${MAIN_W}x$(main_row | cut -f6)"
CLASSIC_DEFAULT=$(size_of)
resize_analyser; CLASSIC_RESIZED=$(size_of)
check_differs "Classic resize took" "$CLASSIC_RESIZED" "$CLASSIC_DEFAULT"
check "Classic saved nothing" "$(all_keys)" "$KEYS_BEFORE"
check_no_menu "Classic"

echo "== mode switch back to WMP ($B)"
switch_mode "Media Player"; analyser
check "$B does not inherit the Classic size" "$(size_of)" "$B_DEFAULT"
check_no_menu "WMP"

echo
if [ "$FAILS" = 0 ]; then echo "SIZE-ISOLATION PASS"; exit 0; fi
echo "SIZE-ISOLATION FAIL ($FAILS)"; exit 1
