#!/bin/bash
#
# The S4 demand index for the Winamp Modern (`.wal`) corpus (B174, corpus-runner-plan.md §3 S4):
#
#   scripts/wal_demand.sh [--index <features.tsv>] > demand.tsv
#
# Every MAKI call the runtime lacks (`maki-call`, implemented=no), one row per call: how many skins
# declare it, per tier, and up to three skins to test against (best tier first, then file name). A
# skin is its content, joined to docs/winamp-modern/corpus-manifest.tsv by sha256 the way
# wal_reach.sh does, so a re-added gold archive counts once. Class names come from
# docs/winamp-modern/maki-classes.tsv (the `extern class` lines of the `.mi` headers the corpus
# ships); a class it lacks prints as its GUID. Ordered by skins, then gold+silver, then call, so the
# output is a pure function of the index and the manifest rev on its first line.

set -u -o pipefail

source "$(dirname "$0")/lib/wal_corpus.sh"

index="$WAL_CORPUS_ROOT/index/features.tsv"
case "${1:-}" in
    --index) index="${2:-}" ;;
    "") ;;
    *) echo "usage: wal_demand.sh [--index <features.tsv>]" >&2; exit 2 ;;
esac
[ -f "$index" ] || { echo "wal_demand: no index at $index (scripts/wal_feature_index.sh <dir> --corpus all tiers)" >&2; exit 1; }

docs="$(dirname "$0")/../docs/winamp-modern"
manifest="$docs/corpus-manifest.tsv"
rev=$(git log -1 --format=%h -- "$manifest")
[ -z "$(git status --porcelain -- "$manifest")" ] || rev="$rev+dirty"

echo "# maki-call implemented=no (manifest $rev)"
printf 'call\tfeature\tskins\tgold\tsilver\tbronze\tquarantine\tsamples\n'
awk -F'\t' '
    BEGIN { rank["gold"] = 1; rank["silver"] = 2; rank["bronze"] = 3; rank["quarantine"] = 4 }
    FILENAME ~ /maki-classes/ { if (FNR > 1) name[$1] = $2; next }
    FILENAME ~ /corpus-manifest/ { if (FNR > 1 && (!($2 in tier) || rank[$3] < rank[tier[$2]])) tier[$2] = $3; next }
    FNR == 1 { next }
    !($2 in tier) { print "wal_demand: indexed skin not in the manifest (stale index?): " $1 > "/dev/stderr"; bad = 1; next }
    $3 == "maki-call" && $5 == "no" {
        if (!($2 in file) || $1 < file[$2]) file[$2] = $1
        hit[$4, $2]; calls[$4]
    }
    END {
        if (bad) exit 1
        for (k in hit) {
            split(k, p, SUBSEP); f = p[1]; t = tier[p[2]]
            n[f]++; c[f, t]++
            # the sort key orders samples by tier, then file name
            s[f] = s[f] "\n" rank[t] "\t" file[p[2]] " (" t ")"
        }
        for (f in calls) {
            split(f, g, "."); cls = (g[1] in name) ? name[g[1]] : g[1]
            m = split(substr(s[f], 2), lines, "\n"); sorted = ""
            # insertion sort: m is at most a few hundred
            for (i = 2; i <= m; i++) { v = lines[i]; for (j = i - 1; j >= 1 && lines[j] > v; j--) lines[j + 1] = lines[j]; lines[j + 1] = v }
            for (i = 1; i <= m && i <= 3; i++) { sub(/^[0-9]\t/, "", lines[i]); sorted = sorted (i > 1 ? ", " : "") lines[i] }
            # leading gold+silver column is the second sort key, cut after sorting
            printf "%d\t%s.%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\n", c[f, "gold"] + c[f, "silver"], cls, g[2], f, n[f], c[f, "gold"], c[f, "silver"], c[f, "bronze"], c[f, "quarantine"], sorted
        }
    }' "$docs/maki-classes.tsv" "$manifest" "$index" |
    LC_ALL=C sort -t$'\t' -k4,4nr -k1,1nr -k3,3 | cut -f2-
