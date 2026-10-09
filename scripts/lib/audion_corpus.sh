#!/bin/bash
# Shared by the Audion corpus scripts. Source it, then call:
#
#   audion_require_clean_tree <tool> <allow-dirty 0|1>
#   audion_face_list <corpus> <list-file> <tool>   -> prints the measured face count
#
# A sweep or census is a build: an edit landing mid-run invalidates it, and a binary that does not
# compile writes an empty capture. So both refuse a dirty tree unless told otherwise.

readonly AUDION_CORPUS_DEFAULT="${AUDION_CORPUS_PATH:-$HOME/Library/Application Support/NullPlayer/AudionFaces}"

audion_require_clean_tree() {
    if [ "$2" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "$1: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
        git status --short >&2
        exit 1
    fi
}

# Every folder under <corpus> holding index.json, minus scripts/audion_corpus_exclusions.txt, one
# path per line: the AUDION_FACE list file the harness reads. Prints the count it wrote.
audion_face_list() {
    local corpus="$1" list="$2" tool="$3" kept=0 dropped=0 face
    local exclusions; exclusions="$(dirname "${BASH_SOURCE[0]}")/../audion_corpus_exclusions.txt"
    : > "$list"
    while IFS= read -r -d '' index; do
        face=$(dirname "$index")
        if grep -v '^[[:space:]]*#' "$exclusions" | grep -qxF -- "$(basename "$face")"; then
            dropped=$((dropped + 1))
            echo "$tool: excluded '$(basename "$face")' (scripts/audion_corpus_exclusions.txt)" >&2
            continue
        fi
        printf '%s\n' "$face" >> "$list"
        kept=$((kept + 1))
    done < <(find "$corpus" -name index.json -type f -print0 | sort -z)
    [ "$dropped" -gt 0 ] && echo "$tool: $dropped face(s) excluded; measuring $kept" >&2
    echo "$kept"
}
