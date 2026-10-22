#!/bin/bash
#
# Reach of one feature across the Winamp Modern (`.wal`) corpus, per tier (B171, corpus-runner-plan.md §8):
#
#   scripts/wal_reach.sh <kind> <feature-regex> [--index <features.tsv>]
#   -> gold a/A, silver n/N, bronze m/M, quarantine q/Q (manifest <rev>)
#
# A skin counts when any of its index rows has that kind and a feature matching the regex (awk ERE,
# case-insensitive). Tier is joined from docs/winamp-modern/corpus-manifest.tsv by sha256, so the
# manifest rev names the denominator. A skin is its content: an archive the manifest lists twice
# (the four byte-identical re-adds of gold skins in silver) counts once, in its best tier. A tier the index covers only in part, or an indexed skin the
# manifest lacks, is a stale index and fails rather than printing a wrong denominator; a tier the
# index does not cover at all (a gold+silver index) is left out of the line.

set -u -o pipefail

source "$(dirname "$0")/lib/wal_corpus.sh"

usage() {
    echo "usage: wal_reach.sh <kind> <feature-regex> [--index <features.tsv>]" >&2
    exit 2
}

index="$WAL_CORPUS_ROOT/index/features.tsv" args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --index) index="${2:-}"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) args+=("$1"); shift ;;
    esac
done
[ ${#args[@]} -eq 2 ] || usage
[ -f "$index" ] || { echo "wal_reach: no index at $index (scripts/wal_feature_index.sh <dir> --corpus all tiers)" >&2; exit 1; }

manifest="$(dirname "$0")/../docs/winamp-modern/corpus-manifest.tsv"
rev=$(git log -1 --format=%h -- "$manifest")
[ -z "$(git status --porcelain -- "$manifest")" ] || rev="$rev+dirty"

awk -F'\t' -v kind="${args[0]}" -v re="${args[1]}" -v rev="$rev" '
    BEGIN { rank["gold"] = 1; rank["silver"] = 2; rank["bronze"] = 3; rank["quarantine"] = 4 }
    NR == FNR { if (FNR > 1 && (!($2 in tier) || rank[$3] < rank[tier[$2]])) tier[$2] = $3; next }
    FNR == 1 { next }
    !($2 in tier) { stale[$1]; next }
    { indexed[$2] }
    $3 == kind && tolower($4) ~ tolower(re) { hit[$2] }
    END {
        for (s in stale) { print "wal_reach: indexed skin not in the manifest (stale index?): " s > "/dev/stderr"; bad = 1 }
        for (sha in tier) total[tier[sha]]++
        for (sha in indexed) covered[tier[sha]]++
        for (sha in hit) hits[tier[sha]]++
        split("gold silver bronze quarantine", order, " ")
        for (i = 1; i <= 4; i++) {
            t = order[i]
            if (!(t in covered)) continue
            if (covered[t] != total[t]) { printf "wal_reach: index covers %d of %d %s skins (stale index?)\n", covered[t], total[t], t > "/dev/stderr"; bad = 1 }
            line = line (line == "" ? "" : ", ") sprintf("%s %d/%d", t, hits[t], total[t])
        }
        if (bad) exit 1
        print line " (manifest " rev ")"
    }' "$manifest" "$index"
