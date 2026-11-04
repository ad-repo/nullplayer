#!/bin/bash
#
# Load census of the AIMP skin corpus (`.acs`, `.acs3`, `.acs4`, `.acs5`).
#
# One TSV row per skin: sha256, whether it loaded, the diagnostic code it was rejected with, how many
# of its scripts the interpreter runs, its format and file name. This is the row that ranks
# `tasks/AIMP_TASKS.md`, and what `scripts/aimp_corpus_baseline.py` records as the ratchet
# `AIMPCorpusLoadTests` enforces.
#
#   scripts/aimp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty]
#
# Output: <outdir>/census.tsv, and the run's log in <outdir>/test.log.
#
# The canonical reference is skills/aimp-skin-guide/reference/harness.md; this script restates no
# flag documentation. It follows scripts/wmp_skin_census.sh:
#
#   * A census is a build: it refuses a dirty tree without --allow-dirty, since an edit mid-run
#     measures something nobody committed.
#   * Redirect, do not pipe: the test's output goes to a file.
#   * The script prints the count it measured and never asserts a fixed one.

set -u -o pipefail
cd "$(dirname "$0")/.."

out="" corpus="" allow_dirty=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --corpus) corpus="$2"; shift 2 ;;
        --allow-dirty) allow_dirty=1; shift ;;
        -*) echo "unknown option $1" >&2; exit 2 ;;
        *) out="$1"; shift ;;
    esac
done
[[ -n "$out" ]] || { sed -n '3,13p' "$0" >&2; exit 2; }
if [[ $allow_dirty -eq 0 && -n "$(git status --porcelain -- Sources Tests)" ]]; then
    echo "Sources/ or Tests/ has uncommitted changes; commit them or pass --allow-dirty." >&2
    exit 1
fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
source scripts/lib/swiftpm.sh

env ${corpus:+AIMP_CORPUS_PATH="$corpus"} AIMP_CENSUS_OUT="$out/census.tsv" \
    swift test ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} \
    --filter 'AIMPCorpusLoadTests/testNoSkinThatUsedToLoadStoppedLoading' > "$out/test.log" 2>&1
status=$?

if [[ ! -s "$out/census.tsv" ]]; then
    echo "No census written (swift test exit $status); see $out/test.log" >&2
    exit 1
fi
rows=$(( $(wc -l < "$out/census.tsv") - 1 ))
loaded=$(awk -F'\t' 'NR > 1 && $2 == "ok"' "$out/census.tsv" | wc -l | tr -d ' ')
echo "census: $rows skin(s), $loaded loaded -> $out/census.tsv (test exit $status, rev $(git rev-parse --short HEAD))"
