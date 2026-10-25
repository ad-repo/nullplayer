#!/bin/bash
# Capture real Sonique 1.96 (under Wine) drawing skins in navigator, mid and small mode.
#
# usage: sonique_oracle_capture.sh <outdir> <skin.sgf>...     skin names as they appear in the corpus dir
#
# Starts Sonique if it is not running, leaves it running (quit: sonique_oracle_capture.sh --quit).
# Writes <outdir>/<skin>__{nav,mid,small}_<n>.png, one per visible Wine window, window-only
# (never the full screen). Sonique windows appear over the user's screen while this runs.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ORACLE=${SONIQUE_ORACLE:-"$HOME/Library/Application Support/NullPlayer/SoniqueOracle"}
WINE=${SONIQUE_WINE:-"$HOME/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine"}
export WINEPREFIX="$ORACLE/prefix" WINEDEBUG=-all
WINEWINS="$ORACLE/winewins"

nap() { perl -e "select(undef,undef,undef,$1)"; }
sq() { "$WINE" 'C:\Sonique\Sonique.exe' "$@" >/dev/null 2>&1; }

[ -x "$WINE" ] || { echo "no Wine at $WINE (see reference/harness.md § The oracle)" >&2; exit 1; }
[ -d "$WINEPREFIX/drive_c/Sonique" ] || { echo "no Sonique install in $WINEPREFIX" >&2; exit 1; }
if [ "${1:-}" = --quit ]; then sq -quit; "$(dirname "$WINE")/wineserver" -k; exit 0; fi
[ $# -ge 2 ] || { echo "usage: $0 <outdir> <skin.sgf>... | --quit" >&2; exit 2; }
[ -x "$WINEWINS" ] || swiftc -O "$HERE/sonique_winewins.swift" -o "$WINEWINS" || exit 1

out=$1; shift; mkdir -p "$out"
if ! pgrep -qf 'C:\\Sonique\\Sonique.exe'; then
  (cd "$WINEPREFIX/drive_c/Sonique" && "$WINE" 'C:\Sonique\Sonique.exe' >/dev/null 2>&1 &)
  for _ in $(seq 1 60); do "$WINEWINS" | awk '$4>=200' | grep -q . && break; nap 1; done
fi

grab() {
  local n=0
  while read -r id _ _ w h _; do
    [ "$w" -ge 100 ] && [ "$h" -ge 60 ] || continue
    screencapture -x -o -l "$id" "$out/${1}_$n.png"; n=$((n + 1))
  done < <("$WINEWINS")
  echo "$n"
}

for skin in "$@"; do
  base=$(basename "${skin%.*}")
  # Small mode is captured last, so a skin with it is complete; a rerun resumes an interrupted corpus.
  [ -f "$out/${base}__small_0.png" ] && continue
  # Sonique draws its default skin for a path that does not exist, which reads as a real capture.
  [ -f "$WINEPREFIX/drive_c/Sonique/skins/$(basename "$skin")" ] || { echo "$base not in the oracle's skins folder" >&2; continue; }
  sq -loadskin "C:\\Sonique\\skins\\$(basename "$skin")"; nap 2.5
  sq -showwindow 3 1; nap 2.5; n=$(grab "${base}__nav")
  sq -showwindow 2 1; nap 2.5; m=$(grab "${base}__mid")
  sq -showwindow 1 1; nap 2.5; s=$(grab "${base}__small")
  echo "$base nav=$n mid=$m small=$s"
done
sq -showwindow 3 1
