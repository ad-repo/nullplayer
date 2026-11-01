#!/bin/bash
# Drive a ClassicPro skin's SUI tabs (cPro-Bento by default) from both sides — the tab strip and the Windows menu — and check after
# every step that the two agree (B350). Prints one row per step and a VIOLATION line for each broken
# rule; exits 1 if any rule broke. Usage:
#
#   skills/app-control/scripts/bento_tabs.sh [--skin <name>] [--no-launch] [--keep] [step ...]
#
#   step  click:<tab label>   click that tab in the strip     click:"Media Library"
#         menu:<item>         choose that Windows-menu item   menu:"Library Browser"
#         rclick:<tab label>  open that tab's right-click menu, read it, dismiss it
#         reset               Skins → Modern → Restore Default Tabs (reloads the skin)
#         relaunch            quit with ⌘Q and launch again (not with --no-launch)
#   With no steps, runs the default sequence below.
#   --skin       the skin to launch: 2222-cPro__Bento (engine one, the default) or
#                cpro2_dark_aluminum_final_by_victhor_d6necra (engine two)
#   --no-launch  drive the debug build already running (it must have WINAMP_MODERN_TAB_TRACE=1)
#   --keep       leave the app running afterwards (it is quit by default)
#
# State comes from two places, never from a screenshot: the app's `TABS` trace line (strip, active
# tab, pages on screen) and the Windows menu's own tick marks, read through Accessibility.
#
# The rules every step must leave true — mechanical, whichever route got there:
#   R1 the active tab's page is the page on screen, and a page on screen has its tab active
#   R2 a menu item is ticked exactly when its tab is in the strip
#   R3 `click:X` leaves X active
#   R4 `menu:X` on an unticked item leaves X's tab in the strip, active
#   R5 `menu:X` on a ticked item leaves X's tab out of the strip
#   R6 `click:X` changes which tabs are in the strip not at all
#   R7 `relaunch` brings back exactly the tabs that were in the strip
#   R8 `rclick:X` offers no Auto Close Tab, and changes nothing
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WH="$HERE/winhelper"
LOG="${BENTO_TABS_LOG:-${TMPDIR:-/tmp}/bento_tabs.log}"
SETTLE="${BENTO_TABS_SETTLE:-1.2}"

LAUNCH=1; KEEP=0; STEPS=(); SKIN="2222-cPro__Bento"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-launch) LAUNCH=0 ;;
    --keep) KEEP=1 ;;
    --skin) SKIN="$2"; shift ;;
    *) STEPS+=("$1") ;;
  esac
  shift
done
# The tabs that differ by skin: engine two names the browser tab Web Reader; the widget tabs are the
# skin's own (W1 is closed and reopened, W2 closed).
case "$SKIN" in
  *dark_aluminum*) WEB="Web Reader"; W1="Now Playing"; W2="Now Playing" ;;
  *) WEB="Browser"; W1="BrowserPro"; W2="Now Playing" ;;
esac
if [ ${#STEPS[@]} -eq 0 ]; then
  STEPS=(reset
         "click:Playlist" "click:Media Library" "click:$WEB" "click:$W2" "click:Video"
         "menu:Library Browser" "menu:Library Browser"           # close an inactive tab, reopen it
         "menu:Library Browser" "click:Video"                    # close the active tab, then click
         "menu:Playlist Editor" "menu:Playlist Editor"
         "menu:$WEB" "menu:$WEB" "menu:Library Browser"
         "menu:$W2" "menu:$W1" "menu:$W1"
         "click:$WEB" "click:Playlist" "click:$WEB"             # clicks keep every tab in the strip
         "rclick:Playlist" "rclick:$WEB" "click:Playlist"       # the tab menu cannot close a tab
         "menu:Video" "menu:Visualization" relaunch "click:$WEB"
         "menu:Video" "menu:Visualization" relaunch
         reset)
fi

# Windows-menu item → tab label. Media Library and Playlist are NullPlayer's own Library Browser and
# Playlist Editor items; every other tab has an item named after it.
tab_for_menu() {
  case "$1" in
    "Library Browser") echo "Media Library" ;; "Playlist Editor") echo "Playlist" ;; *) echo "$1" ;;
  esac
}
# Tab label → the page `CentroSUI.m` shows for it.
page_for_tab() {
  case "$1" in
    "Media Library") echo library ;; "Playlist") echo playlist ;; "Video") echo video ;;
    "Visualization") echo visualization ;; "$WEB") echo browser ;; *) echo widget ;;
  esac
}
MENU_ITEMS=("Library Browser" "Playlist Editor" "Video" "Visualization" "$WEB" "$W1")
[ "$W2" = "$W1" ] || MENU_ITEMS+=("$W2")

if [ $LAUNCH -eq 1 ]; then
  WINAMP_MODERN_TAB_TRACE=1 "$HERE/launch.sh" "$SKIN" --log "$LOG" | tail -1
  [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
fi
PID=$(pgrep -nx NullPlayer) || { echo "FAIL: no NullPlayer running"; exit 1; }

ax() {
  osascript -e 'tell application "System Events"' -e "tell (first process whose unix id is $PID)" \
    -e "$1" -e 'end tell' -e 'end tell' 2>/dev/null
}
# A Windows-menu item by title, the last of that title: the tab rows close the menu, and a skin window
# can carry a tab's name (Dark Aluminum's Web Reader window above its Web Reader tab).
item() {
  echo "last item of (menu items of menu 1 of menu bar item \"Windows\" of menu bar 1 whose title is \"$1\")"
}
# A failed read prints nothing (an unticked item reads `missing value`), so it is retried: the menu
# is rebuilt as windows change, and a read that lands mid-rebuild errors.
tick() {
  local i v
  for i in 1 2 3 4 5; do
    v=$(ax "get value of attribute \"AXMenuItemMarkChar\" of ($(item "$1"))")
    [ -n "$v" ] && break; sleep 0.2
  done
  [ "$v" = "✓" ]
}
# The open contextual menu's item titles: an AXMenu child of whichever window it opened on.
read_popup() {
  local i v
  for i in $(seq 1 10); do
    v=$(ax 'repeat with w in every window
      repeat with e in every UI element of w
        if role of e is "AXMenu" then return title of every UI element of e
      end repeat
    end repeat
    return ""')
    [ -n "$v" ] && { echo "$v"; return; }; sleep 0.2
  done
}

# The last TABS line, parsed into STRIP (labels, `*` on the active one), CENTRES, PAGES, CANVAS_W.
read_state() {
  local line; line=$(grep "WinampModern TABS" "$LOG" | tail -1)
  line=${line#*TABS }
  local strip=${line#strip=[}; strip=${strip%%]*}
  PAGES=${line#*pages=[}; PAGES=${PAGES%%]*}
  CANVAS_W=${line##*canvas=}; CANVAS_W=${CANVAS_W%x*}
  STRIP=(); CENTRES=(); ACTIVE=""
  local IFS='|'
  for tab in $strip; do
    local label=${tab%@*}
    if [[ "$label" == *"*" ]]; then label=${label%\*}; ACTIVE=$label; fi
    STRIP+=("$label"); CENTRES+=("${tab##*@}")
  done
}
is_ticked() { [[ "$TICKED" == *"|$1|"* ]]; }
sorted_strip() { printf '%s\n' "${STRIP[@]}" | sort | paste -sd'|' -; }
in_strip() { local t; for t in "${STRIP[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
page_shown() { [[ ",$PAGES," == *",$1,"* ]]; }

click_tab() {  # $1 = label, $2 = winhelper verb (click or rclick)
  read_state
  local i
  for i in "${!STRIP[@]}"; do
    [ "${STRIP[$i]}" = "$1" ] || continue
    local win; win=$("$WH" windows --pid "$PID" | grep "Winamp Modern" | head -1)
    local wx wy ww; wx=$(echo "$win" | cut -f3); wy=$(echo "$win" | cut -f4); ww=$(echo "$win" | cut -f5)
    local cx=${CENTRES[$i]%,*} cy=${CENTRES[$i]#*,}
    local x y
    x=$(echo "$wx + $cx * $ww / $CANVAS_W" | bc -l); y=$(echo "$wy + $cy * $ww / $CANVAS_W" | bc -l)
    "$WH" raise "$PID" >/dev/null 2>&1
    "$WH" "${2:-click}" "${x%.*}" "${y%.*}" >/dev/null
    return 0
  done
  echo "  (no tab '$1' in the strip to click)"; return 1
}

quit_app() {
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set frontmost to true" \
    -e 'tell application "System Events" to keystroke "q" using command down' >/dev/null 2>&1
  local i; for i in $(seq 1 50); do kill -0 "$PID" 2>/dev/null || return 0; sleep 0.2; done
}

FAILURES=0
violation() { echo "  VIOLATION $1"; FAILURES=$((FAILURES + 1)); }

check() {  # $1 = step, $2 = the tick the step's menu item had before it ran
  read_state
  local ticks="" item
  TICKED="|"
  for item in "${MENU_ITEMS[@]}"; do
    if tick "$item"; then ticks+="${item}✓ "; TICKED+="$item|"; fi
  done
  printf '%-24s strip=[%s] active=%s pages=[%s]\n%24s ticks: %s\n' "$1" "$(IFS='|'; echo "${STRIP[*]}")" \
    "${ACTIVE:-none}" "$PAGES" "" "${ticks:-none}"
  # R1
  if [ -n "$ACTIVE" ] && ! page_shown "$(page_for_tab "$ACTIVE")"; then
    violation "R1 active tab $ACTIVE but its page $(page_for_tab "$ACTIVE") is not shown"
  fi
  local p
  for p in library playlist video visualization browser; do
    page_shown "$p" || continue
    [ "$(page_for_tab "$ACTIVE")" = "$p" ] || violation "R1 page $p on screen but the active tab is ${ACTIVE:-none}"
  done
  # R2
  for item in "${MENU_ITEMS[@]}"; do
    local tab; tab=$(tab_for_menu "$item")
    if in_strip "$tab" && ! is_ticked "$item"; then violation "R2 $tab is in the strip but '$item' is unticked"; fi
    if ! in_strip "$tab" && is_ticked "$item"; then violation "R2 '$item' is ticked but $tab is not in the strip"; fi
  done
  # R3–R6
  case "$1" in
    click:*)
      [ "$ACTIVE" = "${1#click:}" ] || violation "R3 clicked ${1#click:} but the active tab is ${ACTIVE:-none}"
      [ "$(sorted_strip)" = "$3" ] || violation "R6 the click changed the strip: [$3] -> [$(sorted_strip)]" ;;
    rclick:*)
      [ -n "$POPUP" ] || violation "R8 no tab menu read for ${1#rclick:}"
      [[ "$POPUP" != *"Auto Close Tab"* ]] || violation "R8 ${1#rclick:}'s tab menu offers Auto Close Tab: [$POPUP]"
      [ "$(sorted_strip)" = "$3" ] || violation "R8 the tab menu changed the strip: [$3] -> [$(sorted_strip)]" ;;
    relaunch)
      [ "$(sorted_strip)" = "$3" ] || violation "R7 the relaunch changed the strip: [$3] -> [$(sorted_strip)]" ;;
    menu:*)
      local tab; tab=$(tab_for_menu "${1#menu:}")
      if [ "$2" = 0 ]; then
        { in_strip "$tab" && [ "$ACTIVE" = "$tab" ]; } || violation "R4 opened '${1#menu:}' but $tab is not the active tab"
      else
        ! in_strip "$tab" || violation "R5 closed '${1#menu:}' but $tab is still in the strip"
      fi ;;
  esac
}

sleep "$SETTLE"
check "start" 0 ""
for step in "${STEPS[@]}"; do
  before=0
  read_state; strip_before=$(sorted_strip)
  case "$step" in
    reset)
      ax "perform action \"AXPress\" of menu item \"Restore Default Tabs\" of menu 1 of menu item \"Modern\" of menu 1 of menu bar item \"Skins\" of menu bar 1" >/dev/null
      sleep 3 ;;
    click:*) click_tab "${step#click:}" ;;
    rclick:*)
      POPUP=""
      if click_tab "${step#rclick:}" rclick; then
        POPUP=$(read_popup)
        echo "  tab menu: [$POPUP]"
        ax 'key code 53' >/dev/null
      fi ;;
    relaunch)
      [ $LAUNCH -eq 1 ] || { echo "relaunch needs the script to own the launch"; exit 2; }
      quit_app
      WINAMP_MODERN_TAB_TRACE=1 "$HERE/launch.sh" "$SKIN" --log "$LOG" >/dev/null || { echo "FAIL: relaunch"; exit 1; }
      PID=$(pgrep -nx NullPlayer) ;;
    menu:*)
      tick "${step#menu:}" && before=1
      ax "perform action \"AXPress\" of ($(item "${step#menu:}"))" >/dev/null ;;
    *) echo "unknown step: $step"; exit 2 ;;
  esac
  sleep "$SETTLE"
  check "$step" "$before" "$strip_before"
done

[ $KEEP -eq 1 ] || quit_app
if [ $FAILURES -eq 0 ]; then echo "BENTO TABS PASS: ${#STEPS[@]} steps"; exit 0; fi
echo "BENTO TABS FAIL: $FAILURES violation(s) over ${#STEPS[@]} steps"; exit 1
