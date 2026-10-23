#!/bin/bash
# Where an intake stands (skills/skin-intake). Reads docs/winamp-modern/intakes/intake-<n>.tsv,
# prints the count per stage and the next skin to work, and fails when the ledger disagrees with
# the manifest or the corpus on disk — so a session or a loop can trust it without re-deriving.
#
#   scripts/wal_intake_status.sh [n]      # default: the highest-numbered intake
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/wal_corpus.sh

dir=docs/winamp-modern/intakes
n=${1:-$(ls "$dir" | sed -n 's/^intake-\([0-9]*\)\.tsv$/\1/p' | sort -n | tail -1)}
ledger="$dir/intake-$n.tsv"
[ -f "$ledger" ] || { echo "no ledger at $ledger" >&2; exit 1; }

# Stage order; the next skin is the first row of the least-advanced stage short of `accepted`.
stages="admitted headless live accepted promoted"

awk -F'\t' -v stages="$stages" -v corpus="$WAL_CORPUS_ROOT" -v n="$n" '
BEGIN { k = split(stages, s, " "); for (i = 1; i <= k; i++) rank[s[i]] = i }
FNR == 1 { next }
FILENAME ~ /corpus-manifest/ { tier[$1] = $3; sha[$1] = $2; next }
{
    if (!($3 in rank)) { print "bad stage \"" $3 "\" for " $1; bad++; next }
    count[$3]++; total++
    if (!($1 in tier)) { print "not in manifest: " $1; bad++; next }
    if (sha[$1] != $2) { print "sha256 differs from manifest: " $1; bad++ }
    want = $3 == "promoted" ? "gold" : "silver"
    if (tier[$1] != want) { print $1 ": stage " $3 " but manifest tier " tier[$1]; bad++ }
    if (system("test -f \"" corpus "/" want "/" $1 "\"")) { print "not in " want "/: " $1; bad++ }
    if (rank[$3] < rank["accepted"] && (next_rank == 0 || rank[$3] < next_rank)) { next_rank = rank[$3]; next_file = $1; next_note = $6 }
}
END {
    line = "intake " n ": " total " skins —"
    for (i = 1; i <= k; i++) line = line " " s[i] " " count[s[i]] + 0
    print line
    if (next_file == "") print "next: none — promote the accepted rows, then PR"
    else if (s[next_rank] == "admitted") print "next: the batch headless pass (lifecycle step 3) over the " count["admitted"] " admitted skins"
    else if (s[next_rank] == "live") print "next: the user'"'"'s UI round (lifecycle step 5) over the " count["live"] " live skins"
    else print "next: " next_file " (" s[next_rank] ") — note: " next_note
    if (bad) { print bad " ledger problem(s)"; exit 1 }
}' docs/winamp-modern/corpus-manifest.tsv "$ledger"

# What this tree can take from the run store (harness.md § "The run store") over gold+silver, so a
# session knows before it starts whether its baseline is free.
key=$(wal_run_key "$(wal_corpus_archives "$WAL_CORPUS_DEFAULT")")
stored=""
for kind in render interaction motion; do
    [ -n "$key" ] && [ -f "$WAL_RUNS_ROOT/$kind/$key/.complete" ] && stored="$stored $kind"
done
echo "run store for this tree, gold+silver:${stored:- nothing}"
