#!/bin/bash
# Drive a ClassicPro skin's SUI tabs from both sides — the tab strip and the Windows menu — and check
# after every step that the two agree (B350). Any ClassicPro skin, either engine: the tabs are read
# from the app, never listed here. Prints one row per step and a VIOLATION line for each broken rule.
# Usage:
#
#   skills/app-control/scripts/bento_tabs.sh [--skin <name|path>] [--no-launch] [--keep] [step ...]
#   skills/app-control/scripts/bento_tabs.sh --all [--from <n>] [--count <n>]
#   skills/app-control/scripts/bento_tabs.sh --list
#
#   step  click:<tab>         click that tab in the strip     click:"Media Library"
#         menu:<item>         choose that Windows-menu item   menu:"Library Browser"
#         rclick:<tab>        open that tab's right-click menu, read it, dismiss it
#         reset               Skins → Modern → Restore Default Tabs (reloads the skin)
#         relaunch            quit with ⌘Q and launch again (not with --no-launch)
#   With no steps, runs a sequence built from the skin's own tabs (see `default_steps`).
#   --skin       a name `launch.sh` resolves, or a path (default 2222-cPro__Bento, engine one;
#                cpro2_dark_aluminum_final_by_victhor_d6necra is engine two)
#   --no-launch  drive the debug build already running (it must have WINAMP_MODERN_TAB_TRACE=1)
#   --keep       leave the app running afterwards (it is quit by default)
#   --all        every skin in the corpus (gold, silver, bronze) and the installed skins that loads
#                the ClassicPro engine, one name per line: PASS, FAIL with its violations, or SKIP (the
#                skin runs no tab strip). `--from`/`--count` take a slice of that list (1-based).
#   --list       print that list, one path per line, and exit
#
# Exits 0 on a pass, 1 on any violation, 3 when the skin runs no tab strip (SKIP).
#
# State comes from two places, never from a screenshot: the app's `TABS` trace line (strip, closed
# tabs, active tab, pages on screen) and the Windows menu's own tick marks, read through Accessibility.
#
# The rules every step must leave true — mechanical, whichever route got there:
#   R1 the active tab's page is the page on screen, and a page on screen has its tab active
#   R2 a menu item is ticked exactly when its tab is in the strip — the engine's strip, which on a
#      narrow skin (Insomnis) scrolls, so a tab in it can be past its end and not drawn
#   R3 `click:X` leaves X active
#   R4 `menu:X` on an unticked item leaves X's tab in the strip, active
#   R5 `menu:X` on a ticked item leaves X's tab out of the strip
#   R6 `click:X` changes which tabs are in the strip not at all
#   R7 `relaunch` brings back exactly the tabs that were in the strip
#   R8 `rclick:X` offers no Auto Close Tab, and changes nothing
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WH="$HERE/winhelper"
LOG="${BENTO_TABS_LOG:-${TMPDIR:-/tmp}/bento_tabs.log}"
SETTLE="${BENTO_TABS_SETTLE:-1.2}"
SUPPORT="$HOME/Library/Application Support/NullPlayer"

LAUNCH=1; KEEP=0; ALL=0; FROM=1; COUNT=100000; STEPS=(); SKIN="2222-cPro__Bento"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-launch) LAUNCH=0 ;;
    --keep) KEEP=1 ;;
    --skin) SKIN="$2"; shift ;;
    --all) ALL=1 ;;
    --list) ALL=2 ;;
    --from) FROM="$2"; shift ;;
    --count) COUNT="$2"; shift ;;
    *) STEPS+=("$1") ;;
  esac
  shift
done

# The skins that load the ClassicPro engine (its `load.xml` include), one path per name: gold first.
engine_skins() {
  local d f
  for d in "$SUPPORT/WinampModernCorpus/gold" "$SUPPORT/WinampModernCorpus/silver" \
           "$SUPPORT/WinampModernCorpus/bronze" "$SUPPORT/WinampModernSkins"; do
    find "$d" -maxdepth 1 -iname "*.wal" -print0 2>/dev/null
  done | while IFS= read -r -d '' f; do
    unzip -p "$f" 2>/dev/null | /usr/bin/grep -aqi 'classicpro[/\\]engine' && printf '%s\n' "$f"
  done | awk -F/ '!seen[$NF]++'
}
[ $ALL -eq 2 ] && { engine_skins; exit 0; }

if [ $ALL -eq 1 ]; then
  pass=0; fail=0; skip=0; out_file="$LOG.skin"
  while IFS= read -r skin; do
    # A skin that has not finished in BENTO_TABS_SKIN_LIMIT seconds (default 600) is stopped: one
    # stuck skin must not hold up the rest.
    "$0" --skin "$skin" < /dev/null > "$out_file" 2>&1 & child=$!
    ( sleep "${BENTO_TABS_SKIN_LIMIT:-600}"; kill "$child"; pkill -x NullPlayer ) 2>/dev/null & dog=$!
    wait "$child"; status=$?
    kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
    out=$(cat "$out_file")
    name=$(basename "$skin" .wal)
    case $status in
      0) pass=$((pass + 1)); echo "PASS  $name" ;;
      3) skip=$((skip + 1)); echo "SKIP  $name" ;;
      143) fail=$((fail + 1)); echo "FAIL  $name: timed out after ${BENTO_TABS_SKIN_LIMIT:-600}s" ;;
      *) fail=$((fail + 1)); echo "FAIL  $name"
         printf '%s\n' "$out" | /usr/bin/grep -E "VIOLATION|FAIL|unknown" | sed 's/^ *//' \
           | sort | uniq -c | sort -rn | sed 's/^/    /' ;;
    esac
  done < <(engine_skins | tail -n "+$FROM" | head -n "$COUNT")
  echo "BENTO TABS --all: $pass pass, $fail fail, $skip skip"
  [ $fail -eq 0 ]; exit
fi

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
# Every Windows-menu item as `title<TAB>mark`. Two bulk reads (0.2 s), not one per item (5 s). Retried:
# the menu is rebuilt as windows change, and a read that lands mid-rebuild errors.
read_menu() {
  local i
  for i in 1 2 3 4 5; do
    MENU=$(ax 'set m to menu 1 of menu bar item "Windows" of menu bar 1
      set ts to title of every menu item of m
      set ks to value of attribute "AXMenuItemMarkChar" of every menu item of m
      set out to ""
      repeat with i from 1 to count of ts
        set k to item i of ks
        if k is missing value then set k to ""
        set out to out & item i of ts & tab & k & linefeed
      end repeat
      return out')
    [ -n "$MENU" ] && return; sleep 0.2
  done
}
# Whether the item is ticked, in the last `read_menu` — the last item of that title, as `item` picks.
tick() {
  [ "$(printf '%s\n' "$MENU" | awk -F'\t' -v t="$1" '$1 == t { m = $2 } END { print m }')" = "✓" ]
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

# The last TABS line, parsed into STRIP (labels, `*` on the active one), CENTRES, CLOSED, PAGES,
# CANVAS_W. Returns 1 when there is none: the skin runs no tab strip.
read_state() {
  local line; line=$(/usr/bin/grep -a "WinampModern TABS" "$LOG" | tail -1)
  [ -n "$line" ] || return 1
  line=${line#*TABS }
  local strip=${line#strip=[}; strip=${strip%%]*}
  local closed=${line#*closed=[}; closed=${closed%%]*}
  PAGES=${line#*pages=[}; PAGES=${PAGES%%]*}
  CANVAS_W=${line##*canvas=}; CANVAS_W=${CANVAS_W%x*}
  STRIP=(); CENTRES=(); CLOSED=(); ACTIVE=""
  local IFS='|' tab
  for tab in $strip; do
    local label=${tab%@*}
    if [[ "$label" == *"*" ]]; then label=${label%\*}; ACTIVE=$label; fi
    STRIP+=("$label"); CENTRES+=("${tab##*@}")
  done
  for tab in $closed; do CLOSED+=("$tab"); done
}
sorted_strip() { printf '%s\n' "${STRIP[@]}" | sort | paste -sd'|' -; }
in_strip() { local t; for t in "${STRIP[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
page_shown() { [[ ",$PAGES," == *",$1,"* ]]; }

# Tab ↔ Windows-menu item. Media Library and Playlist are NullPlayer's own Library Browser and
# Playlist Editor items; every other tab has an item named after it.
menu_for_tab() {
  case "$1" in "Media Library") echo "Library Browser" ;; "Playlist") echo "Playlist Editor" ;; *) echo "$1" ;; esac
}
tab_for_menu() {
  case "$1" in "Library Browser") echo "Media Library" ;; "Playlist Editor") echo "Playlist" ;; *) echo "$1" ;; esac
}
# Tab → the page `CentroSUI.m` shows for it. Engine two names its browser tab Web Reader.
page_for_tab() {
  case "$1" in
    "Media Library") echo library ;; "Playlist") echo playlist ;; "Video") echo video ;;
    "Visualization") echo visualization ;; "Browser"|"Web Reader") echo browser ;; *) echo widget ;;
  esac
}

# Wait for the strip: the trace is silent on a skin without one.
for _ in $(seq 1 25); do read_state && break; sleep 0.4; done
if ! read_state; then
  [ $LAUNCH -eq 1 ] && [ $KEEP -eq 0 ] && pkill -x NullPlayer
  echo "BENTO TABS SKIP: $(basename "$SKIN") runs no ClassicPro tab strip"; exit 3
fi
ALL_TABS=("${STRIP[@]}" ${CLOSED[@]+"${CLOSED[@]}"})
MENU_ITEMS=(); for t in "${ALL_TABS[@]}"; do MENU_ITEMS+=("$(menu_for_tab "$t")"); done
has_tab() { local t; for t in "${ALL_TABS[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }

# The default sequence, from the skin's own tabs: select every tab; close and reopen each from the
# menu, Media Library both inactive and active; clicks and the tab menu leave the strip alone; two
# closed tabs survive a relaunch, and two reopened ones do too.
default_steps() {
  local others=() t
  for t in "${ALL_TABS[@]}"; do
    [ "$t" = "Media Library" ] || [ "$t" = "Playlist" ] || others+=("$t")
  done
  STEPS=(reset)
  for t in "${ALL_TABS[@]}"; do STEPS+=("click:$t"); done
  local first=${ALL_TABS[0]} second=${ALL_TABS[1]}
  if has_tab "Media Library"; then
    local away=$first; [ "$away" = "Media Library" ] && away=$second
    STEPS+=("menu:Library Browser" "menu:Library Browser"   # close an inactive tab, reopen it
            "menu:Library Browser" "click:$away")           # close the active tab, then click
  fi
  has_tab "Playlist" && STEPS+=("menu:Playlist Editor" "menu:Playlist Editor")
  for t in ${others[@]+"${others[@]}"}; do STEPS+=("menu:$t" "menu:$t"); done
  has_tab "Media Library" && STEPS+=("menu:Library Browser")
  # Two tabs to click between, and up to two others to close across a relaunch.
  local a=$first b=$second rest=() closing=() m
  for t in "${ALL_TABS[@]}"; do [ "$t" = "$a" ] || [ "$t" = "$b" ] || rest+=("$t"); done
  STEPS+=("click:$a" "click:$b" "click:$a"                  # clicks keep every tab in the strip
          "rclick:$b" "rclick:$a" "click:$b")               # the tab menu cannot close a tab
  [ ${#rest[@]} -gt 0 ] || return 0
  local n=${#rest[@]}
  [ $n -lt 2 ] || closing+=("menu:$(menu_for_tab "${rest[$((n - 2))]}")")
  closing+=("menu:$(menu_for_tab "${rest[$((n - 1))]}")")
  STEPS+=("${closing[@]}" relaunch "click:$a" "${closing[@]}" relaunch reset)
}
if [ ${#STEPS[@]} -eq 0 ]; then
  [ ${#ALL_TABS[@]} -ge 2 ] || { echo "BENTO TABS SKIP: $(basename "$SKIN") has one tab"; exit 3; }
  default_steps
fi
echo "tabs: [$(IFS='|'; echo "${ALL_TABS[*]}")]"

click_tab() {  # $1 = label, $2 = winhelper verb (click or rclick)
  read_state
  local i
  for i in "${!STRIP[@]}"; do
    [ "${STRIP[$i]}" = "$1" ] || continue
    [ "${CENTRES[$i]}" != "-" ] || { echo "  ('$1' is past the end of the strip, which scrolls)"; return 2; }
    local win; win=$("$WH" windows --pid "$PID" | /usr/bin/grep "Winamp Modern" | head -1)
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
violation() { VIOLATIONS+=("$1"); }

# The rules are what a step must *end* in, and a skin whose own timers keep the main thread busy
# (211786-Cpro_Winamp_Modern) redraws its strip seconds after the menu has already changed. So a broken
# rule is read again, up to four more times a second apart, and only what is still broken is reported.
check() {  # $1 = step, $2 = the tick the step's menu item had before it ran, $3 = the strip before it
  local attempt
  for attempt in 1 2 3 4 5; do
    VIOLATIONS=()
    evaluate "$@"
    [ ${#VIOLATIONS[@]} -eq 0 ] && break
    sleep 1
  done
  local ticks="" item
  for item in "${MENU_ITEMS[@]}"; do tick "$item" && ticks+="${item}✓ "; done
  printf '%-24s strip=[%s] active=%s pages=[%s]\n%24s ticks: %s\n' "$1" "$(IFS='|'; echo "${STRIP[*]}")" \
    "${ACTIVE:-none}" "$PAGES" "" "${ticks:-none}"
  for item in ${VIOLATIONS[@]+"${VIOLATIONS[@]}"}; do echo "  VIOLATION $item"; done
  FAILURES=$((FAILURES + ${#VIOLATIONS[@]}))
}

evaluate() {
  read_state; read_menu
  local item
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
    if in_strip "$tab" && ! tick "$item"; then violation "R2 $tab is in the strip but '$item' is unticked"; fi
    if ! in_strip "$tab" && tick "$item"; then violation "R2 '$item' is ticked but $tab is not in the strip"; fi
  done
  # R3–R8
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
  before=0; ran=$step
  read_state; strip_before=$(sorted_strip)
  case "$step" in
    reset)
      ax "perform action \"AXPress\" of menu item \"Restore Default Tabs\" of menu 1 of menu item \"Modern\" of menu 1 of menu bar item \"Skins\" of menu bar 1" >/dev/null
      sleep 3 ;;
    # A tab past the end of a scrolling strip cannot be clicked: the step is skipped, and only the
    # rules every state must meet (R1, R2) are checked after it.
    click:*) click_tab "${step#click:}"; [ $? -ne 2 ] || ran="skipped $step" ;;
    rclick:*)
      POPUP=""
      click_tab "${step#rclick:}" rclick; status=$?
      if [ $status -eq 0 ]; then
        POPUP=$(read_popup)
        echo "  tab menu: [$POPUP]"
        ax 'key code 53' >/dev/null
      fi
      [ $status -ne 2 ] || ran="skipped $step" ;;
    relaunch)
      [ $LAUNCH -eq 1 ] || { echo "relaunch needs the script to own the launch"; exit 2; }
      quit_app
      WINAMP_MODERN_TAB_TRACE=1 "$HERE/launch.sh" "$SKIN" --log "$LOG" >/dev/null || { echo "FAIL: relaunch"; exit 1; }
      PID=$(pgrep -nx NullPlayer)
      for _ in $(seq 1 25); do read_state && break; sleep 0.4; done ;;
    menu:*)
      read_menu; tick "${step#menu:}" && before=1
      ax "perform action \"AXPress\" of ($(item "${step#menu:}"))" >/dev/null ;;
    *) echo "unknown step: $step"; exit 2 ;;
  esac
  sleep "$SETTLE"
  check "$ran" "$before" "$strip_before"
done

[ $KEEP -eq 1 ] || quit_app
if [ $FAILURES -eq 0 ]; then echo "BENTO TABS PASS: ${#STEPS[@]} steps"; exit 0; fi
echo "BENTO TABS FAIL: $FAILURES violation(s) over ${#STEPS[@]} steps"; exit 1
