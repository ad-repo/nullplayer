#!/bin/bash
# window-interaction-matrix.sh <skin> <out.tsv> [app args…]
#
# Opens, stretches and closes every Windows-menu window of one skin, then the main window, through
# real menu presses, drags and clicks on the debug build. Per window:
#   open             Windows-menu toggle; a new on-screen window, menu checked
#   close            at the opened size
#   reopen, stretch  drags br, bottom, right, left, top by 40 pt; each records resize/move/none. A
#                    window that does not stretch is a result, not a failure
#   close-stretched  the close again, at the stretched size
# The main window is stretched and closed last (in Classic that quits the app).
#
# A close click-searches the top-right corner, outermost first and down to 40 pt (a stretched
# window can letterbox its art and move the close button down). It is CLOSED only when the window
# is off screen, its Windows-menu item is unchecked and Accessibility does not report it minimized.
# A miss that shades, resizes or minimizes the window is logged as `<step>-miss` and undone.
# NOT-CLOSED saves `noclose-<skin>-<window>-<step>.png` beside <out.tsv>; it is not by itself a
# defect: Original/Metal with Hide Title Bars on (`-hideTitleBars NO` shows them for one run) and
# some gloss-framed `.wmz`/`.wal` windows have no close target.
#
# App args go to the launched app. TAG=<label> is appended to the skin column. The repo is the
# checkout this script lives in, so a worktree's copy measures that worktree's build.
# Rows: skin  window  step  result  detail. Stdout: one MATRIX line per skin.
set -u
[ $# -ge 2 ] || { sed -n '2,24p' "$0"; exit 2; }
SKIN=$1; OUT=$2; shift 2; APPARGS=("$@")
TAG=${TAG:-}
R=$(cd "$(dirname "$0")/../../.." && pwd)
WH=$R/skills/app-control/scripts/winhelper; MENU=$R/skills/app-control/scripts/menu.applescript
[ -x "$WH" ] || { echo "winhelper missing: run skills/app-control/scripts/build.sh"; exit 1; }
mkdir -p "$(dirname "$OUT")"; SHOTS=$(cd "$(dirname "$OUT")" && pwd)
[ -s "$OUT" ] || printf 'skin\twindow\tstep\tresult\tdetail\n' > "$OUT"
"$R/skills/app-control/scripts/launch.sh" "$SKIN" --no-play ${APPARGS[@]+-- "${APPARGS[@]}"} >/dev/null 2>&1 </dev/null \
  || { echo "MATRIX $SKIN$TAG: LAUNCH FAIL"; exit 1; }
PID=$(pgrep -x NullPlayer | head -1)
SAFE=${SKIN//[^A-Za-z0-9]/_}$TAG

emit() { printf '%s\t%s\t%s\t%s\t%s\n' "$SKIN$TAG" "$1" "$2" "$3" "${4:-}" >> "$OUT"; }
alive() { kill -0 "$PID" 2>/dev/null; }
ids() { "$WH" windows --pid "$PID" </dev/null 2>/dev/null | awk '{print $1}' | sort; }
row() { "$WH" windows --pid "$PID" </dev/null 2>/dev/null | awk -F'\t' -v id="$1" '$1==id{print $3, $4, $5, $6}'; }
title() { "$WH" windows --pid "$PID" </dev/null 2>/dev/null | awk -F'\t' -v id="$1" '$1==id{print $8}'; }
raise() { "$WH" move 100 100 >/dev/null 2>&1 </dev/null; "$WH" raise "$PID" >/dev/null 2>&1 </dev/null; }
closeaux() { osascript "$MENU" closeaux "$PID" >/dev/null 2>&1 </dev/null; sleep 1; }
checked() { osascript "$MENU" windowitems "$PID" 2>/dev/null </dev/null | awk -F'|' -v n="$1" '$2==n{print $4}'; }
ax() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to $1" 2>/dev/null </dev/null; }
minimized() { ax "get value of attribute \"AXMinimized\" of (every window whose name is \"$1\")" | grep -q true; }
unminimize() { ax "set value of attribute \"AXMinimized\" of (every window whose name is \"$1\") to false" >/dev/null; sleep 1; }

# open <menu index> <name>: toggles the item on, parks the new window at 200,200, echoes its id
open() {
  local before new; before=$(ids)
  osascript "$MENU" toggle "$PID" "$1" "$2" >/dev/null 2>&1 </dev/null; sleep 1.5
  new=$(comm -13 <(echo "$before") <(ids) | head -1)
  [ -n "$new" ] && { "$WH" park "$PID" "$(title "$new")" 200 200 >/dev/null 2>&1 </dev/null; sleep 0.5; }
  echo "$new"
}

# stretch <id> <name>
stretch() {
  local id=$1 name=$2 X Y W H X2 Y2 W2 H2 PX PY DX DY V
  for STEP in br bottom right left top; do
    raise; read -r X Y W H < <(row "$id"); [ -n "${X:-}" ] || { emit "$name" "drag-$STEP" LOST; return; }
    case $STEP in
      br)     PX=$((X+W-3)); PY=$((Y+H-3)); DX=40;  DY=40 ;;
      bottom) PX=$((X+W/2)); PY=$((Y+H-3)); DX=0;   DY=40 ;;
      right)  PX=$((X+W-2)); PY=$((Y+H/2)); DX=40;  DY=0 ;;
      left)   PX=$((X+3));   PY=$((Y+H/2)); DX=-40; DY=0 ;;
      top)    PX=$((X+W/2)); PY=$((Y+1));   DX=0;   DY=-40 ;;
    esac
    "$WH" drag $PX $PY $((PX+DX/2)) $((PY+DY/2)) $((PX+DX)) $((PY+DY)) >/dev/null 2>&1 </dev/null; sleep 0.6
    read -r X2 Y2 W2 H2 < <(row "$id")
    if [ -z "${X2:-}" ]; then V=GONE
    elif [ "$W2 $H2" != "$W $H" ]; then V=resize
    elif [ "$X2 $Y2" != "$X $Y" ]; then V=move
    else V=none; fi
    emit "$name" "drag-$STEP" "$V" "$X $Y $W $H -> ${X2:-} ${Y2:-} ${W2:-} ${H2:-}"
    [ "$V" = GONE ] && return
  done
}

# close_search <id> <name> <menu name, or - for the main window> <step>
close_search() {
  local id=$1 name=$2 mname=$3 step=$4 t X Y W H X2 Y2 W2 H2 DX DY c
  t=$(title "$id")
  for DY in 6 10 14 20 26 32 40; do for DX in 6 9 12 16 20 26; do
    raise; read -r X Y W H < <(row "$id"); [ -n "${X:-}" ] || break 2
    "$WH" click $((X+W-DX)) $((Y+DY)) >/dev/null 2>&1 </dev/null; sleep 1
    alive || { emit "$name" "$step" CLOSED "app quit at -$DX,+$DY"; return; }
    read -r X2 Y2 W2 H2 < <(row "$id")
    if [ -z "${X2:-}" ]; then
      if minimized "$t"; then
        emit "$name" "$step-miss" minimized "at -$DX,+$DY (undone)"; unminimize "$t"; continue
      fi
      c=n/a; [ "$mname" = - ] || c=$(checked "$mname")
      if [ "$c" = 1 ]; then
        emit "$name" "$step" HIDDEN-BUT-CHECKED "off screen at -$DX,+$DY but menu still checked"; return
      fi
      emit "$name" "$step" CLOSED "at -$DX,+$DY; off screen, not minimized, menu checked=$c"; return
    fi
    if [ "$W2 $H2" != "$W $H" ]; then  # shade or maximize: the same click toggles it back
      emit "$name" "$step-miss" "size $W $H -> $W2 $H2" "at -$DX,+$DY (undone)"
      "$WH" click $((X2+W2-DX)) $((Y2+DY)) >/dev/null 2>&1 </dev/null; sleep 1
    fi
  done; done
  "$WH" capture "$id" "$SHOTS/noclose-$SAFE-${name// /_}-$step.png" --pid "$PID" >/dev/null 2>&1 </dev/null
  emit "$name" "$step" NOT-CLOSED "no corner point closed it; see noclose-$SAFE-${name// /_}-$step.png"
}

raise; closeaux
while IFS='|' read -r IDX NAME EN _; do
  [ "$EN" = 1 ] || continue
  alive || { emit "$NAME" open APP-EXITED; break; }
  NEW=$(open "$IDX" "$NAME")
  [ -n "$NEW" ] || { emit "$NAME" open NO-WINDOW "menu checked=$(checked "$NAME")"; closeaux; continue; }
  emit "$NAME" open OPENED "$(row "$NEW"); menu checked=$(checked "$NAME")"
  close_search "$NEW" "$NAME" "$NAME" close
  alive || break
  closeaux
  NEW=$(open "$IDX" "$NAME")
  [ -n "$NEW" ] || { emit "$NAME" reopen NO-WINDOW "menu checked=$(checked "$NAME")"; closeaux; continue; }
  emit "$NAME" reopen OPENED "$(row "$NEW")"
  stretch "$NEW" "$NAME"
  [ -n "$(row "$NEW")" ] && close_search "$NEW" "$NAME" "$NAME" close-stretched
  alive && closeaux
done < <(osascript "$MENU" windowitems "$PID" 2>/dev/null </dev/null)

if alive; then
  MAIN=$("$WH" windows --pid "$PID" </dev/null | awk -F'\t' 'NR==1{print $1}')
  if [ -n "$MAIN" ]; then
    "$WH" park "$PID" "$(title "$MAIN")" 200 200 >/dev/null 2>&1 </dev/null; sleep 0.5
    emit Main open OPENED "$(row "$MAIN")"
    stretch "$MAIN" Main
    [ -n "$(row "$MAIN")" ] && alive && close_search "$MAIN" Main - close-stretched
  fi
fi
alive && kill "$PID"

awk -F'\t' -v s="$SKIN$TAG" '$1==s && $3 ~ /^close(-stretched)?$/ { n[$4]++ }
  END { printf "MATRIX %s: %d closed, %d not-closed, %d hidden-but-checked\n", s, n["CLOSED"], n["NOT-CLOSED"], n["HIDDEN-BUT-CHECKED"] }' "$OUT"
