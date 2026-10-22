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

# wal_require_clean_tree <script> <allow_dirty>: a sweep is a build, and an edit landing mid-run
# invalidates the pass — so refuse a dirty tree unless allow_dirty is 1.
wal_require_clean_tree() {
    [ "$2" -eq 1 ] || [ -z "$(git status --porcelain 2>/dev/null)" ] && return 0
    echo "$1: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
    git status --short >&2
    return 1
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
