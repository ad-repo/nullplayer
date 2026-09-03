#!/bin/sh

set -eu

backlog=${1:-TASKS.md}

if grep -n '^- \[x\]' "$backlog"; then
  echo "closed item still in $backlog — archive it" >&2
  exit 1
fi

# Every open item in a ranking table must carry a Reach, so the backlog can be ranked by how many
# skins a defect actually touches rather than by how bad it sounds.
#
# Scoped by *shape*, not by a pattern over the whole line. The ranking tables are
# `| Id | Item | Reach | Effort | Tier |` — five cells, so seven awk fields once the leading and
# trailing pipes are counted — and the "Awaiting manual QA" table is three cells wide and has no
# Reach column at all. Matching `^| B` across both is what made this check unrunnable: it demanded a
# Reach of rows that are not supposed to have one.
#
# It also used to require the Reach to *look* numeric (`[0-9]+ skins`, `[0-9]+ variants`, or `—`),
# which rejects the true and common answer "every `.wal` skin". The cell being non-blank is the
# thing worth enforcing mechanically; whether the answer is a good one is a review question.
#
# Both defects were masked until 2026-09-02: `set -e` plus the closed-item `grep` above meant this
# check had never run on a backlog that got past the first one.
missing=$(awk -F'|' '/^\| B/ && NF == 7 {
    reach = $4
    gsub(/[ \t]/, "", reach)
    if (reach == "") print FILENAME ":" FNR ": " $2 " has no Reach"
}' "$backlog")
if [ -n "$missing" ]; then
  printf '%s\n' "$missing" >&2
  echo "open item missing Reach in $backlog" >&2
  exit 1
fi

echo "Winamp Modern backlog hygiene: OK"
