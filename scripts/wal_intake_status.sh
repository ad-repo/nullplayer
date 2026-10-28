#!/bin/bash
# Where an intake stands (skills/skin-intake). Reads docs/winamp-modern/intakes/intake-<n>.tsv,
# prints the corpus tiers, the batch's count per stage and the next session's work, and fails when the ledger disagrees with
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

# Stage order; the batch's lowest stage decides the next session's work (skills/skin-intake).
stages="admitted headless live accepted promoted"

# The return guard: a commit that changes exactly one ledger row is a session spent on that skin.
# A skin at the budget is never picked again; it goes to the user's round with its open rows.
budget=2
spent=$'\t'"$(git rev-list origin/main..HEAD -- "$ledger" 2>/dev/null | while read -r c; do
    rows=$(git show --format= "$c" -- "$ledger" | grep '^+[^+]' | cut -f1 | sed 's/^+//')
    if [ "$(printf '%s\n' "$rows" | wc -l)" -eq 1 ]; then echo "$rows"; fi
done | sort | uniq -c | awk -v b="$budget" '$1 >= b { sub(/^ *[0-9]+ /, ""); print }' | tr '\n' '\t')"
# Tab-separated, not spaces: corpus filenames carry spaces, and the ledger's tab-split $1 never holds a tab.

awk -F'\t' -v stages="$stages" -v corpus="$WAL_CORPUS_ROOT" -v n="$n" -v spent="$spent" -v budget="$budget" '
BEGIN { k = split(stages, s, " "); for (i = 1; i <= k; i++) rank[s[i]] = i }
FNR == 1 { next }
FILENAME ~ /corpus-manifest/ { tier[$1] = $3; sha[$1] = $2; tiers[$3]++; next }
{
    if (!($3 in rank)) { print "bad stage \"" $3 "\" for " $1; bad++; next }
    count[$3]++; total++
    if ($3 == "headless" && index(spent, "\t" $1 "\t")) over = over " " $1
    else if ($3 == "headless") { if ($6 ~ /^headless clean/) clean++; else if (first == "") { first = $1; first_note = $6 } }
    if (!($1 in tier)) { print "not in manifest: " $1; bad++; next }
    if (sha[$1] != $2) { print "sha256 differs from manifest: " $1; bad++ }
    want = $3 == "promoted" ? "gold" : "silver"
    if (tier[$1] != want) { print $1 ": stage " $3 " but manifest tier " tier[$1]; bad++ }
    # getline, not system(): the crawl named the archive, and a quote in that name would be shell.
    path = corpus "/" want "/" $1
    if ((getline line < path) < 0) { print "not in " want "/: " $1; bad++ } else close(path)
    if (low == 0 || rank[$3] < low) low = rank[$3]
}
END {
    print "corpus: gold " tiers["gold"] + 0 ", silver " tiers["silver"] + 0 ", bronze " tiers["bronze"] + 0 \
          ", quarantine " tiers["quarantine"] + 0
    line = "batch " n ": " total " skins —"
    for (i = 1; i <= k; i++) line = line " " s[i] " " count[s[i]] + 0
    print line
    stage = s[low]
    if (stage == "admitted") print "next: the headless pass over the whole batch"
    else if (stage == "headless" && first != "") print "next: " first " — note: " first_note
    else if (stage == "headless") print "next: one live smoke session over the " clean " headless-clean skins"
    else if (stage == "live") print "next: hand the " count["live"] " live skins to the user for their UI round"
    else if (stage == "accepted") print "next: promote the batch, then review and PR"
    else print "next: once the PR is merged, close: rm -rf WinampModernCorpus/runs, then admit batch " n + 1
    if (stage == "headless" && first != "" && clean) print "      then one live smoke session over the " clean " headless-clean skins"
    if (over != "") print "budget spent (" budget " single-skin sessions), hand to the user'"'"'s round as they are, open rows in the note:" over
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
