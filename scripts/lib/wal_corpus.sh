#!/bin/bash
# The Winamp Modern (`.wal`) test corpus (B167). Source this file; every corpus script defaults to
# WAL_CORPUS_DEFAULT and takes `--corpus` as a `:`-separated list of directories.
#
# The corpus lives outside the app's own skin folder: `WinampModernSkins/` is the importer's install
# folder, so anything there is in the user's skin menu. Tier is recorded in the committed
# docs/winamp-modern/corpus-manifest.tsv; see docs/winamp-modern/corpus-runner-plan.md §8.
WAL_CORPUS_ROOT="$HOME/Library/Application Support/NullPlayer/WinampModernCorpus"
WAL_CORPUS_DEFAULT="$WAL_CORPUS_ROOT/gold:$WAL_CORPUS_ROOT/silver"
WAL_CORPUS_ALL="$WAL_CORPUS_DEFAULT:$WAL_CORPUS_ROOT/bronze:$WAL_CORPUS_ROOT/quarantine"

# wal_corpus_archives <dir[:dir…]>: every archive, one path per line; fails on a missing directory.
# `*.[wW][aA][lL]`, `-type f`: a plain `*.wal` drops `Defix Hi-END 200.WAL`.
wal_corpus_archives() {
    local dirs dir
    IFS=: read -ra dirs <<<"$1"
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || { echo "no corpus directory at $dir" >&2; return 1; }
    done
    find "${dirs[@]}" -maxdepth 1 -type f -name '*.[wW][aA][lL]'
}

# wal_resolve_skin <name|path>: one archive path. A name is matched without its extension, ignoring
# case, across every tier, then the user's WinampModernSkins/ (where an admitted skin has a second
# copy); it fails on none or on several.
wal_resolve_skin() {
    [ -f "$1" ] && { echo "$1"; return 0; }
    local name="${1%.[wW][aA][lL]}" dirs found
    IFS=: read -ra dirs <<<"$WAL_CORPUS_ALL"
    found=$(find "${dirs[@]}" -maxdepth 1 -type f -iname "$name.wal" 2>/dev/null)
    [ -n "$found" ] || found=$(find "$(dirname "$WAL_CORPUS_ROOT")/WinampModernSkins" -maxdepth 1 -type f \
                                   -iname "$name.wal" 2>/dev/null)
    case $(grep -c . <<<"$found") in
        1) echo "$found" ;;
        0) echo "no skin named $1 in the corpus or WinampModernSkins/" >&2; return 1 ;;
        *) echo "several skins named $1; pass a path:" >&2; echo "$found" >&2; return 1 ;;
    esac
}

# wal_require_clean_tree <script> <allow_dirty>: a sweep is a build, and an edit landing mid-run
# invalidates the pass — so refuse a dirty tree unless allow_dirty is 1.
wal_require_clean_tree() {
    [ "$2" -eq 1 ] || [ -z "$(git status --porcelain 2>/dev/null)" ] && return 0
    echo "$1: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
    git status --short >&2
    return 1
}

# The run store (harness.md § "The run store"). A sweep's output is a function of the code it ran,
# the archives it read and the probe variables set, so a finished run is kept once under
# WAL_RUNS_ROOT/<kind>/<key> and handed to any later run with the same key instead of re-running.
WAL_RUNS_ROOT="$WAL_CORPUS_ROOT/runs"

# wal_code_key [rev]: one hash of Sources/, Tests/, the sweep scripts and their library (they select
# what is stored) and the Package files — at <rev>, or in the working tree when no rev is given
# (edits and untracked files included, through a throwaway index), so an uncommitted run and the
# commit that later holds the same code share a key.
wal_code_key() {
    local tree index
    if [ -n "${1:-}" ]; then
        tree=$(git rev-parse --verify -q "$1^{tree}") || { echo "no commit $1" >&2; return 1; }
    else
        index=$(mktemp)
        cp "$(git rev-parse --git-path index)" "$index"
        tree=$(GIT_INDEX_FILE="$index" git add -A :/ && GIT_INDEX_FILE="$index" git write-tree)
        rm -f "$index"
    fi
    git rev-parse "$tree:Sources" "$tree:Tests" "$tree:scripts/lib" "$tree:scripts/wal_render_sweep.sh" \
        "$tree:scripts/wal_interaction_sweep.sh" "$tree:scripts/wal_motion_sweep.sh" \
        "$tree:Package.swift" "$tree:Package.resolved" | shasum | cut -c1-16
}

# wal_run_key <archive list> [rev]: the store key for a run over those archives. Prints nothing when a
# WINAMP_MODERN_* variable is set: a probe or A/B switch changes the output and the key cannot name it.
wal_run_key() {
    env | grep -q '^WINAMP_MODERN_' && return 0
    local code archives
    code=$(wal_code_key "${2:-}") || return 1
    # Name and content: the output is filed under each archive's name, so the same bytes renamed are
    # a different run.
    archives=$(printf '%s\n' "$1" | while IFS= read -r path; do
                   printf '%s %s\n' "$(shasum -a 256 "$path" | cut -d' ' -f1)" "${path##*/}"
               done | sort | shasum | cut -c1-16)
    echo "$code-$archives"
}

# wal_store_fetch <kind> <key> <outdir>: copy a stored run into <outdir> (an APFS clone, so instant).
# Fails when none is stored.
wal_store_fetch() {
    local stored="$WAL_RUNS_ROOT/$1/$2"
    [ -n "$2" ] && [ -f "$stored/.complete" ] || return 1
    # Into an empty directory, or one already holding this run: copied over another capture, the
    # result is a mix of both. An exit, not a return: `return 1` means "none stored", and the caller
    # would then run the sweep into that same directory.
    if [ -n "$(ls -A "$3" 2>/dev/null)" ] && [ "$(cat "$3/key" 2>/dev/null)" != "$2" ]; then
        echo "$1: $3 holds another run; give an empty or new directory to serve the stored one ($2)" >&2
        exit 1
    fi
    mkdir -p "$3"
    cp -cR "$stored/." "$3/" 2>/dev/null || cp -R "$stored/." "$3/"
    echo "$1: from the run store ($2) -> $3"
}

# wal_store_put <kind> <key> <outdir> <archive list>: keep a finished run. Skipped when the code
# changed while it ran — that run is void anyway.
wal_store_put() {
    [ -n "$2" ] || return 0
    if [ "$(wal_run_key "$4")" != "$2" ]; then
        echo "$1: the code changed during the run; not stored, and the run is not to be trusted" >&2
        return 0
    fi
    echo "$2" > "$3/key"
    local stored="$WAL_RUNS_ROOT/$1/$2" staging="$WAL_RUNS_ROOT/$1/.staging-$$"
    mkdir -p "$WAL_RUNS_ROOT/$1" && rm -rf "$staging"
    { cp -cR "$3" "$staging" 2>/dev/null || cp -R "$3" "$staging"; } && touch "$staging/.complete" \
        && rm -rf "$stored" && mv "$staging" "$stored" && echo "$1: stored as $2"
}

# wal_store_serve <kind> <key> <outdir> <fresh> <rev>: the shared front half of every sweep. Serves a
# stored run and returns 0 (the caller exits); returns 1 to run. A --rev request that is not stored
# fails, since this tree is not that commit: capture it in a worktree (baseline_worktree.sh).
wal_store_serve() {
    [ "$4" -eq 0 ] && wal_store_fetch "$1" "$2" "$3" && return 0
    [ -z "$5" ] && return 1
    echo "$1: nothing stored for $5${2:+ ($2)}; capture it in a worktree (scripts/baseline_worktree.sh), which stores it" >&2
    exit 1
}

# wal_build_tests <script> <outdir>: build the test bundle once, log to <outdir>/build.txt. Needs
# lib/swiftpm.sh.
wal_build_tests() {
    swift build --build-tests ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} > "$2/build.txt" 2>&1 && return 0
    echo "$1: build failed; see $2/build.txt" >&2
    tail -30 "$2/build.txt" >&2
    return 1
}

# wal_run_shards <shards> <archive list> <fn>: run `fn <shard> <archives:…> <bundle>` once per
# shard, in parallel, and return the last non-zero exit. Shard i takes every K-th archive of the
# sha256 order (B170), so the split depends on content alone, never on file names or tier. Each path
# is followed by a `:` so a shard of one skin is still a list, which the harness treats as a sweep.
# `fn` runs the built bundle with `xctest`, not `swift test --skip-build`: SwiftPM holds a lock on
# .build for the whole run, which queued K `swift test`s one behind another (measured 2026-10-19:
# K=1/2/4 took 90/89/94 s). Redirect `fn`'s output to a file; never pipe it.
wal_run_shards() {
    local shards="$1" list="$2" fn="$3" bundle ordered shard status=0 pids=()
    bundle="$(swiftpm_bin_path debug 2>/dev/null)/NullPlayerPackageTests.xctest"
    ordered=$(printf '%s\n' "$list" | while IFS= read -r path; do
                  printf '%s\t%s\n' "$(shasum -a 256 "$path" | cut -d' ' -f1)" "$path"
              done | sort)
    for ((shard = 0; shard < shards; shard++)); do
        "$fn" "$shard" \
            "$(printf '%s\n' "$ordered" | awk -F'\t' -v k="$shards" -v i="$shard" '(NR - 1) % k == i { printf "%s:", $2 }')" \
            "$bundle" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || status=$?; done
    return "$status"
}
