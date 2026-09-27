#!/bin/bash
# Window census: launch each skin, open every Windows-menu window on its own from the same
# baseline, and record where it opens and how big it is. Usage:
#
#   skills/app-control/scripts/window-census.sh <skin>… | --all <families> [--shots] [--out <dir>] [--no-play]
#   skills/app-control/scripts/window-census.sh --list <families>     # print the skin list, run nothing
#
# <skin> is anything launch.sh takes. <families> is a comma list of classic, wal, wmz, original,
# metal, or `all`: every installed skin of those families, classic/wal/wmz as `name.ext` (the
# extension pins the family, so a name found in two families never fails as ambiguous). Geometry is top-left global points (`winhelper windows`).
# Each item is toggled on, measured, and toggled off again before the next, so every row is
# independent of the order. Output in <dir> (default /tmp/np-window-census/<timestamp>/):
#   windows.tsv  one row per window (baseline windows, then each item's), size in points
#   skins.tsv    one row per skin: main window size, the largest window opened, status counts
#   meta.tsv     key/value: screens, scale, UI size
#   report.md    the same, for reading; with --shots, shots/<skin>/<item>.png zipped into shots.zip
# All TSVs are plain: one header row, no comments, one value per column. Pointing --out at an
# existing census appends to it and skips skins already in skins.tsv, so a long corpus run resumes.
#
# Isolation: the app persists window sizes in its defaults domain, so without protection each skin
# would open with whatever the previous skin left behind. The debug domain (`NullPlayer`) is saved
# once to <dir>/defaults-baseline.plist and put back exactly — delete, then import, because
# `defaults import` alone merges — before every skin and again on exit. A resumed census reuses the
# same baseline file, so its rows stay comparable. Only the debug build is ever quit to do this.
# Stdout is one CENSUS line per skin and a final REPORT line; exit 1 if any skin failed to launch.
# Status vocabulary and the placement rule: app-control SKILL.md § Window census.
set -uo pipefail
cd "$(dirname "$0")/../../.."
HERE=skills/app-control/scripts
WH=$HERE/winhelper
MENU=$HERE/menu.applescript

SUPPORT="$HOME/Library/Application Support/NullPlayer"
# Every installed skin of one family, one launch.sh argument per line.
enumerate() {
  case "$1" in
    classic) find "$SUPPORT/Skins" -maxdepth 1 -type f \( -iname '*.wsz' -o -iname '*.whsz' \) ;;
    wal)     find "$SUPPORT/WinampModernSkins" -maxdepth 1 -type f -iname '*.wal' ;;
    wmz)     find "$SUPPORT/WMPSkins" -maxdepth 1 -type f -iname '*.wmz' ;;
  esac | while IFS= read -r f; do basename "$f"; done | sort -f
  case "$1" in
    original)  # bundled + user folders holding a skin.json; selected by folder name
      for d in Sources/NullPlayer/Resources/Skins/*/ "$SUPPORT/ModernSkins"/*/; do
        [ -f "$d/skin.json" ] && echo "modern:$(basename "$d")"
      done | sort -uf ;;
    metal)     # code-defined finishes (ModernSkinLoader.builtInMetalSkinNames) + user folders
      { grep -o 'builtInMetalSkinNames = \[[^]]*\]' Sources/NullPlayer/ModernSkin/ModernSkinLoader.swift \
          | grep -o '"[^"]*"' | tr -d '"'
        for d in "$SUPPORT/MetalSkins"/*/; do [ -f "$d/skin.json" ] && basename "$d"; done
      } | sed 's/^/metal:/' ;;
  esac
}
families() {
  local f; for f in $(tr ',' ' ' <<<"$1"); do
    case "$f" in
      all) enumerate classic; enumerate original; enumerate metal; enumerate wal; enumerate wmz ;;
      classic|original|metal|wal|wmz) enumerate "$f" ;;
      *) echo "window-census.sh: unknown family '$f' (classic, original, metal, wal, wmz, all)" >&2; exit 2 ;;
    esac
  done
}

SKINS=(); SHOTS=0; OUT=""; LAUNCH_OPTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all) while IFS= read -r k; do [ -n "$k" ] && SKINS+=("$k"); done < <(families "$2"); shift 2 ;;
    --list) families "$2"; exit 0 ;;
    --shots) SHOTS=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --no-play) LAUNCH_OPTS+=(--no-play); shift ;;
    -*) echo "window-census.sh: unknown option $1" >&2; exit 2 ;;
    *) SKINS+=("$1"); shift ;;
  esac
done
[ ${#SKINS[@]} -gt 0 ] || { echo "usage: window-census.sh <skin>… | --all <families> [--shots] [--out <dir>] [--no-play]" >&2; exit 2; }
OUT="${OUT:-/tmp/np-window-census/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT/logs"
"$HERE/build.sh" >/dev/null || { echo "CENSUS FAIL: winhelper did not build"; exit 1; }

# Quit the debug build (never the installed app) and wait, so nothing writes the domain mid-restore.
quit_debug() {
  local p
  for p in $(pgrep -f '\.build/.*/debug/NullPlayer'); do kill "$p" 2>/dev/null; done
  for _ in $(seq 40); do pgrep -f '\.build/.*/debug/NullPlayer' >/dev/null || return 0; sleep 0.25; done
  pkill -9 -f '\.build/.*/debug/NullPlayer' 2>/dev/null; sleep 0.5
}
BASE_DEFAULTS="$OUT/defaults-baseline.plist"
restore_defaults() {
  defaults delete NullPlayer 2>/dev/null
  defaults import NullPlayer "$BASE_DEFAULTS"
}
quit_debug
if [ ! -f "$BASE_DEFAULTS" ]; then
  defaults export NullPlayer "$BASE_DEFAULTS" || { echo "CENSUS FAIL: could not save the NullPlayer defaults"; exit 1; }
fi
trap 'quit_debug; restore_defaults' EXIT

WIN="$OUT/windows.tsv"; SKN="$OUT/skins.tsv"; META="$OUT/meta.tsv"; MD="$OUT/report.md"
TMP="$OUT/.work"; mkdir -p "$TMP"
RUN=$(basename "$OUT")
SCREENS=$("$WH" screens)
[ -f "$WIN" ] || printf 'run\tskin\tfamily\trole\titem\tstatus\tenabled\twin_id\tx\ty\tw\th\ttitle\treachable\toverlap_main\tresidue\tshot\tnotes\n' >"$WIN"
[ -f "$SKN" ] || printf 'run\tskin\tfamily\tlaunch_ok\tmain_w\tmain_h\tmax_w\tmax_h\tmax_item\titems\topened\tno_window\tother\tunreachable\tresidue\terror\n' >"$SKN"
if [ ! -f "$META" ]; then
  {
    printf 'key\tvalue\n'
    printf 'run\t%s\n' "$RUN"
    printf 'started\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'coordinates\ttop-left global points (winhelper windows)\n'
    i=0; while IFS=$'\t' read -r sx sy sw sh sc; do
      printf 'screen%d_visible_frame\t%s %s %s %s\nscreen%d_scale\t%s\n' $i "$sx" "$sy" "$sw" "$sh" $i "$sc"; i=$((i + 1))
    done <<<"$SCREENS"
    printf 'defaults_baseline\t%s (restored before every skin)\n' "$BASE_DEFAULTS"
    printf 'ui_size\t100%% (launch.sh disables restoration; UI Size is not persisted otherwise)\n'
  } >"$META"
fi
SCREEN_RECTS=$(awk -F'\t' '{printf "%s %s %s %s;", $1, $2, $3, $4}' <<<"$SCREENS")

listing() { "$WH" windows --pid "$PID"; }

# Poll until two listings 250 ms apart agree on everything but alpha (a .wmz pane fades in, so
# alpha would never settle), capped at 4 s. Leaves the final listing in $1 and every window id
# seen along the way in $1.seen, so a window that flashes up and vanishes is still known.
wait_stable() {
  local out=$1 prev cur i
  sleep 0.5                      # the menu closes and the action lands before the first read
  prev=$(listing); printf '%s\n' "$prev" | cut -f1 >"$out.seen"
  for i in $(seq 14); do
    sleep 0.25
    cur=$(listing); printf '%s\n' "$cur" | cut -f1 >>"$out.seen"
    [ "$(cut -f1-6,8 <<<"$cur")" = "$(cut -f1-6,8 <<<"$prev")" ] && break
    prev=$cur
  done
  printf '%s\n' "$cur" | sed '/^$/d' >"$out"
}

# new/gone/changed rows between two listings, matched by window id (as `winhelper clickdiff`).
diff_listings() {
  awk -F'\t' -v OFS='\t' '
    FILENAME == ARGV[1] { b[$1] = $0; next }
    { seen[$1] = 1
      if (!($1 in b)) { print "new", $1, $3, $4, $5, $6, $7, $8; next }
      split(b[$1], o, "\t"); d = ""
      if (o[3] != $3 || o[4] != $4) d = d "moved " o[3] "," o[4] "->" $3 "," $4 " "
      if (o[5] != $5 || o[6] != $6) d = d "resized " o[5] "x" o[6] "->" $5 "x" $6 " "
      if (o[8] != $8) d = d "renamed "
      if (d != "") print "changed", $1, d, $8 }
    END { for (k in b) if (!(k in seen)) { split(b[k], o, "\t"); print "gone", o[1], o[3], o[4], o[5], o[6], o[7], o[8] } }
  ' "$1" "$2"
}

# Geometry of a listing without ids or alpha: ids may be reissued when a window is re-created.
shape() { cut -f3-6,8 "$1" | sort; }

# WindowPlacement.isReachable over visibleFrames, in top-left space: the window's top-left corner
# lies in a screen, left/top edges inclusive, right/bottom exclusive. Prints reachable (1/0) and
# the overlap with main in pt², tab-separated.
placement() {  # x y w h  mainx mainy mainw mainh
  awk -v s="$SCREEN_RECTS" -v x="$1" -v y="$2" -v w="$3" -v h="$4" \
      -v mx="$5" -v my="$6" -v mw="$7" -v mh="$8" 'BEGIN {
    r = 0; n = split(s, a, ";")
    for (i = 1; i <= n; i++) { if (split(a[i], f, " ") < 4) continue
      if (x >= f[1] && x < f[1] + f[3] && y >= f[2] && y < f[2] + f[4]) r = 1 }
    ow = (x + w < mx + mw ? x + w : mx + mw) - (x > mx ? x : mx)
    oh = (y + h < my + mh ? y + h : my + mh) - (y > my ? y : my)
    o = (mx == "" || ow <= 0 || oh <= 0) ? 0 : ow * oh
    printf "%d\t%d", r, o }'
}

# One windows.tsv row. A window-less item (no-window, skin-view, …) gets one row with the geometry
# columns empty; an item that opens several windows gets one row each, largest first.
emit() {  # role item status enabled win_id x y w h title residue shot notes
  local place=$'\t'
  [ -n "$5" ] && place=$(placement "$6" "$7" "$8" "$9" "$MX" "$MY" "$MW" "$MH")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$RUN" "$SKIN" "$FAMILY" "$1" \
    "$(clean "$2")" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$(clean "${10}")" "$place" "${11}" "${12}" "$(clean "${13}")" >>"$WIN"
}

count() { tr ' ' '\n' <<<"$STATUSES" | grep -cx "$1"; }
clean() { printf '%s' "$1" | tr '\t\n' '  '; }
FAILED=0

for SKIN in "${SKINS[@]}"; do
  SAFE=$(tr -c 'A-Za-z0-9._-' '_' <<<"$SKIN" | sed 's/_$//')
  if awk -F'\t' -v s="$SKIN" 'NR > 1 && $2 == s {f = 1} END {exit !f}' "$SKN"; then
    echo "CENSUS $SKIN: already in $SKN, skipped"; continue
  fi
  FAMILY=""
  quit_debug; restore_defaults
  LINE=$("$HERE/launch.sh" "$SKIN" ${LAUNCH_OPTS[@]+"${LAUNCH_OPTS[@]}"} --log "$OUT/logs/$SAFE.log")
  if [[ "$LINE" != "LAUNCH PASS:"* ]]; then
    echo "CENSUS $SKIN: launch failed — $LINE"; FAILED=1
    printf '%s\t%s\t\t0\t\t\t\t\t\t\t\t\t\t\t\t%s\n' "$RUN" "$SKIN" "$(clean "$LINE")" >>"$SKN"
    continue
  fi
  FAMILY=$(awk '{print $3}' <<<"$LINE")
  PID=$(sed -n 's/.* pid \([0-9]*\) .*/\1/p' <<<"$LINE")

  "$WH" raise "$PID" >/dev/null
  osascript "$MENU" closeaux "$PID" >/dev/null 2>&1
  wait_stable "$TMP/base"
  # Main is the largest baseline row. The baseline may hold more than main when closeaux gives up
  # (a fixed EQ, a .wmz in-view surface); main only anchors the overlaps-main figure.
  read -r MID MX MY MW MH < <(awk -F'\t' '{print $5*$6, $1, $3, $4, $5, $6}' "$TMP/base" | sort -rn | head -1 | cut -d' ' -f2-)
  ITEMS=$(osascript "$MENU" windowitems "$PID" 2>&1)

  # Baseline rows: main, plus anything closeaux could not close.
  while IFS=$'\t' read -r id _ x y w h _ t; do
    role=baseline; [ "$id" = "$MID" ] && role=main
    emit "$role" "" baseline "" "$id" "$x" "$y" "$w" "$h" "$t" "" "" ""
  done <"$TMP/base"

  STATUSES=""; UNREACH=0; RESIDUE=0; ERROR=""
  while IFS='|' read -r IDX NAME EN CK; do
    [ -n "$NAME" ] || continue
    STATUS=""; ROWS=""; SHOT=""; SIDE=""; RES=0
    if ! kill -0 "$PID" 2>/dev/null; then
      STATUS=app-exited; ERROR="app exited before $NAME"
    elif [ "$EN" = 0 ]; then
      STATUS=no-window; SIDE="disabled, not clicked"
    else
      wait_stable "$TMP/pre"
      if ! osascript "$MENU" toggle "$PID" "$IDX" "$NAME" >/dev/null 2>"$TMP/err"; then
        STATUS=menu-changed; SIDE=$(clean "$(cat "$TMP/err")")
      else
        wait_stable "$TMP/post"
        diff_listings "$TMP/pre" "$TMP/post" >"$TMP/diff"
        NEWV=$(awk -F'\t' '$1=="new" && $7>0' "$TMP/diff")
        NEW0=$(awk -F'\t' '$1=="new" && $7<=0' "$TMP/diff")
        GONE=$(awk -F'\t' '$1=="gone"' "$TMP/diff")
        CHG=$(awk -F'\t' '$1=="changed" {printf "%s%s %s(%s)", sep, $2, $3, $4; sep="; "}' "$TMP/diff")
        FLASH=$(sort -u "$TMP/post.seen" | comm -23 - <(cut -f1 "$TMP/pre" | sort -u) | comm -23 - <(cut -f1 "$TMP/post" | sort -u) | paste -sd, -)
        if [ -n "$NEWV" ] && [ -z "$GONE" ]; then
          STATUS=opened; ROWS=$NEWV
        elif [ -n "$NEWV" ] && [ -n "$GONE" ]; then
          STATUS=skin-view; SIDE="replaced $(awk -F'\t' '$1=="gone"{printf "%s ", $2}' <<<"$GONE")with $(awk -F'\t' '$1=="new"{printf "%s@%s,%s %sx%s ", $2, $3, $4, $5, $6}' <<<"$NEWV")"
        elif [ -n "$GONE" ] && [ -z "$CHG" ]; then
          STATUS=open-at-baseline; ROWS=$GONE
        elif [ -n "$CHG" ] || [ -n "$GONE" ]; then
          STATUS=skin-view
        elif [ -n "$NEW0" ] || [ -n "$FLASH" ]; then
          STATUS=transient; SIDE="flashed: ${FLASH:-$(cut -f2 <<<"$NEW0" | paste -sd, -)}"
        else
          STATUS=no-window
        fi
        [ -n "$CHG" ] && SIDE="${SIDE:+$SIDE; }changed: $CHG"
        # Largest window first, so the item's main window is its first row.
        ROWS=$(awk -F'\t' 'NF {print $5 * $6 "\t" $0}' <<<"$ROWS" | sort -t$'\t' -k1,1rn | cut -f2-)
        if [ "$SHOTS" = 1 ] && [ "$STATUS" = opened ]; then
          mkdir -p "$OUT/shots/$SAFE"
          base="shots/$SAFE/$(tr -c 'A-Za-z0-9._-' '_' <<<"$NAME" | sed 's/_$//')"; n=0
          while IFS=$'\t' read -r _ id _; do
            F="$base.png"; [ $n -gt 0 ] && F="$base-$n.png"; n=$((n + 1))
            if "$WH" capture "$id" "$OUT/$F" --pid "$PID" >/dev/null 2>&1; then SHOT="$SHOT$F "; else SHOT="${SHOT}unavailable "; fi
          done <<<"$ROWS"
        fi
        # Put it back, and prove it went back: a baseline that drifts would taint every later row.
        if osascript "$MENU" toggle "$PID" "$IDX" "$NAME" >/dev/null 2>"$TMP/err"; then
          wait_stable "$TMP/back"
          if [ "$(shape "$TMP/back")" != "$(shape "$TMP/pre")" ]; then
            if [ "$STATUS" = skin-view ]; then SIDE="${SIDE:+$SIDE; }view not restored"
            else RES=1; fi
          fi
        else
          RES=1; SIDE="${SIDE:+$SIDE; }second toggle failed: $(clean "$(cat "$TMP/err")")"
        fi
      fi
    fi
    STATUSES="$STATUSES $STATUS "; RESIDUE=$((RESIDUE + RES))
    if [ -z "$ROWS" ]; then
      emit item "$NAME" "$STATUS" "$EN" "" "" "" "" "" "" "$RES" "" "$SIDE"
    else
      set -- $SHOT
      while IFS=$'\t' read -r _ id x y w h _ t; do
        emit item "$NAME" "$STATUS" "$EN" "$id" "$x" "$y" "$w" "$h" "$t" "$RES" "${1:-}" "$SIDE"
        [ $# -gt 0 ] && shift
        [ "$(placement "$x" "$y" "$w" "$h" "" "" "" "" | cut -f1)" = 0 ] && UNREACH=$((UNREACH + 1))
      done <<<"$ROWS"
    fi
  done <<<"$ITEMS"

  # skins.tsv: main's size, and the largest window any item opened (by area), from this skin's rows.
  awk -F'\t' -v OFS='\t' -v run="$RUN" -v skin="$SKIN" -v fam="$FAMILY" \
      -v o="$(count opened)" -v nw="$(count no-window)" -v u="$UNREACH" -v r="$RESIDUE" -v err="$ERROR" '
    $1 == run && $2 == skin && $4 == "main" { mw = $11; mh = $12 }
    $1 == run && $2 == skin && $4 == "item" { if (!seen[$5]++) items++
      if ($8 != "" && $11 * $12 > best) { best = $11 * $12; bw = $11; bh = $12; bi = $5 } }
    END { print run, skin, fam, 1, mw, mh, bw, bh, bi, items, o, nw, items - o - nw, u, r, err }
  ' "$WIN" >>"$SKN"

  kill "$PID" 2>/dev/null
  for _ in $(seq 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$PID" 2>/dev/null

  S="CENSUS $SKIN: main ${MW}x${MH}, $(count opened) opened, $(count no-window) no-window, $UNREACH unreachable, $RESIDUE residue"
  for k in open-at-baseline skin-view transient menu-changed app-exited; do
    [ "$(count $k)" -gt 0 ] && S="$S, $(count $k) $k"
  done
  echo "$S"
done

rm -rf "$TMP"

# report.md is rebuilt from the TSVs every run, so an appended census reads as one report.
awk -F'\t' '
  FILENAME ~ /skins.tsv$/ { if (FNR > 1) { sk[++ns] = $2; fam[$2] = $3; ok[$2] = $4; err[$2] = $16
                              sum[$2] = $5 "x" $6 " | " ($7 == "" ? "" : $7 "x" $8 " (" $9 ")") " | " $11 " | " $12 " | " $13 " | " $14 " | " $15 }
                            next }
  FNR > 1 { rows[$2] = rows[$2] sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n",
            ($4 == "item" ? $5 : "(" $4 ")"), $6, $11, $12, $9, $10, $8, $14, $15, $16, $18) }
  END {
    print "# Window census\n\nSizes are points. Coordinates are top-left global points. Data: `windows.tsv`, `skins.tsv`, `meta.tsv`.\n"
    print "| skin | family | main | largest opened | opened | no-window | other | unreachable | residue |"
    print "|---|---|---|---|---|---|---|---|---|"
    for (i = 1; i <= ns; i++) { s = sk[i]
      if (ok[s] == 1) print "| " s " | " fam[s] " | " sum[s] " |"
      else print "| " s " | | launch failed | | | | | | |" }
    for (i = 1; i <= ns; i++) { s = sk[i]; if (ok[s] != 1) continue
      printf "\n## %s (%s)\n\n", s, fam[s]
      if (err[s] != "") printf "**%s**\n\n", err[s]
      print "| item | status | w | h | x | y | win_id | reachable | overlap_main | residue | notes |"
      print "|---|---|---|---|---|---|---|---|---|---|---|"
      printf "%s", rows[s] }
  }' "$SKN" "$WIN" >"$MD"

if [ "$SHOTS" = 1 ] && [ -d "$OUT/shots" ]; then (cd "$OUT" && rm -f shots.zip && zip -qr shots.zip shots windows.tsv skins.tsv meta.tsv); fi
echo "REPORT $MD"
exit $FAILED
