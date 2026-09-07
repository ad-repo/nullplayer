#!/bin/bash
# Reads the live Skins menu and emits the sweep list as TSV:
#   system <TAB> submenu <TAB> menu item <TAB> output label
# Enumerating the menu (rather than the skins folders) is what keeps this correct as
# skins are added or removed, and it is the only source that knows the exact item text
# the click must match.
cd "$(dirname "$0")"
EXCLUDE_FILE="${1:-../exclude.txt}"
non_skin='^(Switch to |Load |Get More |Open |Import |Reimport |Download |Engine: |Skin Colors|Skin Settings|Spectrum Analyzer$)'
emit() { # $1 system  $2 submenu
  osascript menu.applescript list "$2" 2>/dev/null | tr ',' '\n' | sed 's/^ *//; s/ *$//' |
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    [ "$item" = "missing value" ] && continue
    echo "$item" | grep -Eq "$non_skin" && continue
    label="$1_$(echo "$item" | sed 's/[^A-Za-z0-9._-]\{1,\}/-/g; s/^-//; s/-$//')"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$item" "$label"
  done
}
{ emit classic "Classic"; emit original "Original"; emit original-metal "Original-Metal"; emit modern "Modern"; } |
if [ -s "$EXCLUDE_FILE" ]; then grep -vFf "$EXCLUDE_FILE"; else cat; fi
