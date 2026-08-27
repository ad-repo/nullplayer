#!/bin/sh

set -eu

backlog=${1:-TASKS.md}

if grep -n '^- \[x\]' "$backlog"; then
  echo "closed item still in $backlog — archive it" >&2
  exit 1
fi

missing=$(grep -n '^| B' "$backlog" | grep -vE '\|[^|]*([0-9]+[^|]*skins?|[0-9]+ variants|—)[^|]*\|' || true)
if [ -n "$missing" ]; then
  printf '%s\n' "$missing" >&2
  echo "open item missing Reach in $backlog" >&2
  exit 1
fi

echo "Winamp Modern backlog hygiene: OK"
