#!/bin/bash
#
# Corpus render sweep for the Audion face engine.
#
#   scripts/audion_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir>]
#   scripts/audion_render_sweep.sh compare <base-outdir> <curr-outdir>
#
# `capture` renders every face in the oracle's canonical states (stopped, playing) through the
# harness, so the same capture feeds scripts/audion_oracle_compare.py, which reads the text boxes
# from its PROBE lines in raw.txt. `compare` diffs two captures:
# the invariant lines, then every image through scripts/png_diff.py. A diff between two captures is
# unclassified until the oracle has classified it. The flags are documented only in
# skills/audion-face-guide/reference/harness.md.
#
# Rules inherited from the `.wmz` sweep rather than re-earned: freeze the tree (a dirty tree is
# refused), redirect the run to files (never pipe a long `swift test`), stderr in its own file, and
# an INCOMPLETE marker that only a finished capture removes. Never capture a baseline with
# `git stash`; use scripts/baseline_worktree.sh.

set -u -o pipefail
source "$(dirname "$0")/lib/swiftpm.sh"
source "$(dirname "$0")/lib/audion_corpus.sh"

readonly INVARIANT_PATTERN='^(HARNESS |FACE |LOAD |FINDING |ELEMENTS |RENDER-DUMP |PNG )'

usage() {
    echo "usage: audion_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir>]" >&2
    echo "       audion_render_sweep.sh compare <base-outdir> <curr-outdir>" >&2
    exit 2
}

capture() {
    local out="" corpus="$AUDION_CORPUS_DEFAULT" allow_dirty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --allow-dirty) allow_dirty=1; shift ;;
            --corpus) corpus="${2:-}"; shift 2 ;;
            -*) usage ;;
            *) [ -n "$out" ] && usage; out="$1"; shift ;;
        esac
    done
    [ -n "$out" ] || usage
    [ -d "$corpus" ] || { echo "audion_render_sweep: no corpus at $corpus" >&2; exit 1; }
    audion_require_clean_tree audion_render_sweep "$allow_dirty"

    rm -rf "$out/png"; mkdir -p "$out/png"
    echo "audion_render_sweep capture started $(date '+%F %T') — not finished" > "$out/INCOMPLETE"
    local faces; faces=$(audion_face_list "$corpus" "$out/faces.txt" audion_render_sweep)
    [ "$faces" -gt 0 ] || { echo "audion_render_sweep: no faces in $corpus" >&2; exit 1; }
    echo "audion_render_sweep: capturing $faces faces -> $out"
    AUDION_FACE="$out/faces.txt" AUDION_RENDER_DUMP="$out/png" AUDION_RENDER_STATE=stopped,playing AUDION_RENDER_PROBE=1 \
        swift test ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} --filter AudionFaceRenderDumpTests/testSweepsFaceOrCorpus \
        > "$out/raw.txt" 2> "$out/stderr.txt"
    local status=$?

    grep -E "$INVARIANT_PATTERN" "$out/raw.txt" > "$out/invariants.txt"
    # Every face prints exactly one `FACE <name>` line before anything else about it, so a count
    # short of the list is a lost block or a run that died, never a quiet face.
    local reported; reported=$(grep -c '^FACE ' "$out/invariants.txt" | tr -d ' ')
    reported=$((reported - $(grep -c '^FACE .* FAILED ' "$out/invariants.txt")))
    echo "audion_render_sweep: $(wc -l < "$out/invariants.txt" | tr -d ' ') invariant lines, $reported faces reported, $(find "$out/png" -name '*.png' | wc -l | tr -d ' ') images"
    if [ "$reported" -ne "$faces" ]; then
        echo "audion_render_sweep: SHORT CAPTURE ($reported of $faces faces) — see $out/raw.txt and $out/stderr.txt" >&2
        tail -20 "$out/stderr.txt" >&2
        exit 1
    fi
    [ $status -eq 0 ] || echo "audion_render_sweep: swift test exited $status; read $out/raw.txt before trusting it" >&2
    if grep -q '^FACE .* FAILED ' "$out/invariants.txt"; then
        echo "audion_render_sweep: faces that failed to load:" >&2
        grep '^FACE .* FAILED ' "$out/invariants.txt" >&2
    fi
    rm -f "$out/INCOMPLETE"
    echo "audion_render_sweep: done — $out"
}

compare() {
    [ $# -eq 2 ] || usage
    local dir
    for dir in "$1" "$2"; do
        [ -f "$dir/invariants.txt" ] || { echo "audion_render_sweep: no capture at $dir" >&2; exit 1; }
        [ -f "$dir/INCOMPLETE" ] && { echo "audion_render_sweep: $dir is an unfinished capture" >&2; exit 1; }
    done
    echo "=== invariants ==="
    # The HARNESS line names the capture's own list file, which differs between any two captures.
    if diff <(sed -E 's/^(HARNESS .* from ).*/\1<list>/' "$1/invariants.txt") \
            <(sed -E 's/^(HARNESS .* from ).*/\1<list>/' "$2/invariants.txt") > "$2/invariants.diff"; then
        echo "identical ($(wc -l < "$2/invariants.txt" | tr -d ' ') lines)"
    else
        echo "DIFFER — $(grep -c '^[<>]' "$2/invariants.diff") changed lines; $2/invariants.diff"
        head -40 "$2/invariants.diff"
    fi
    echo
    echo "=== images ==="
    python3 "$(dirname "$0")/png_diff.py" "$1/png" "$2/png" --summary --top 25
}

[ $# -ge 1 ] || usage
command="$1"; shift
case "$command" in
    capture) capture "$@" ;;
    compare) compare "$@" ;;
    *) usage ;;
esac
