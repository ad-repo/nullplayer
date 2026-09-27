#!/bin/bash
#
# Make (or refresh) a baseline worktree that builds and runs the test probe, for a before/after
# sweep (`wmp_render_sweep.sh`, `wmp_skin_census.sh`, `wal_render_sweep.sh`, `wal_skin_census.sh`).
#
#   scripts/baseline_worktree.sh [<dir>] [<rev>]      # defaults: ../nullplayer-base  HEAD
#
# then:
#
#   (cd <dir> && scripts/wmp_render_sweep.sh capture <outdir>)   # the script says if --allow-dirty is needed
#
# Why a script: the manual route has three traps, each of which fails as something other than itself.
#
#   * `Frameworks/` is only partly tracked (libaubio/, libkeyfinder/, libprojectm-4/, libaubio.5.dylib
#     are in git), so a fresh worktree has no VLCKit and fails with `no such module 'VLCKit'`.
#   * Linking the whole directory lands the link *inside* the tracked one as `Frameworks/Frameworks`
#     (the same error), or, replacing it, deletes tracked files so `capture` refuses the tree. So
#     this links each untracked **entry**, never the directory.
#   * Once it compiles, the test bundle dies in dlopen: its rpath resolves beside itself, so the
#     frameworks SwiftPM copied into `.build/<triple>/{debug,Frameworks}` must be there too.
#
# If it prints that the capture needs `--allow-dirty`, that is safe for this worktree only: what
# makes it dirty is these framework links, and it lists them.
# The check at the end — `git status -- Sources Tests scripts` clean — is what proves the baseline
# really is <rev>. Never capture a baseline with `git stash`; it relinks .build under a running app.

set -eu -o pipefail

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
dir="${1:-$repo/../nullplayer-base}"
rev="${2:-HEAD}"
sha="$(git -C "$repo" rev-parse --verify "$rev^{commit}")"

if [ -e "$dir" ]; then
    common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
    if [ -z "$(common "$dir")" ] || [ "$(common "$dir")" != "$(common "$repo")" ]; then
        echo "baseline_worktree: $dir exists and is not a worktree of $repo" >&2; exit 1
    fi
    if [ -n "$(git -C "$dir" status --porcelain -- Sources Tests scripts Package.swift)" ]; then
        echo "baseline_worktree: $dir has edits under Sources/Tests/scripts; refusing to move it" >&2; exit 1
    fi
    git -C "$dir" checkout --quiet --detach "$sha"
else
    git -C "$repo" worktree add --quiet --detach "$dir" "$sha"
fi
dir="$(cd "$dir" && pwd -P)"

if [ -L "$dir/Frameworks" ]; then
    echo "baseline_worktree: $dir/Frameworks is a symlink; remove it and restore the tracked directory" >&2; exit 1
fi
mkdir -p "$dir/Frameworks"

# Every entry of the working repo's Frameworks/ that git does not carry.
tracked="$(git -C "$repo" ls-files Frameworks | cut -d/ -f2 | sort -u)"
linked=0
for entry in "$repo"/Frameworks/*; do
    name="$(basename "$entry")"
    grep -qxF "$name" <<<"$tracked" && continue
    ln -sfn "$entry" "$dir/Frameworks/$name"; linked=$((linked + 1))
done

# What SwiftPM copied beside the test bundle. ogg/vorbis are real directories there; the rest are
# links — resolve either way and link the real thing.
built=0
for sub in debug Frameworks; do
    src="$repo/.build/arm64-apple-macosx/$sub"
    [ -d "$src" ] || continue
    mkdir -p "$dir/.build/arm64-apple-macosx/$sub"
    for f in "$src"/*.framework "$src"/*.dylib; do
        [ -e "$f" ] || continue
        target="$(readlink "$f" || echo "$f")"
        ln -sfn "$target" "$dir/.build/arm64-apple-macosx/$sub/$(basename "$f")"; built=$((built + 1))
    done
done
[ "$built" -gt 0 ] || echo "baseline_worktree: warning — $repo/.build has no frameworks to mirror; build the working repo once first" >&2

if [ -n "$(git -C "$dir" status --porcelain -- Sources Tests scripts Package.swift)" ]; then
    echo "baseline_worktree: $dir is not clean under Sources/Tests/scripts after linking — not a baseline" >&2; exit 1
fi
echo "baseline_worktree: $dir at ${sha:0:8} ($linked framework entries, $built build products linked)"
# Whether the capture needs --allow-dirty depends on this clone's ignore rules: `.gitignore`'s
# `Frameworks/VLCKit.framework/` matches a directory, not the symlink put here, so the link shows as
# untracked unless `.git/info/exclude` covers it. Say which, rather than always passing the flag.
if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    echo "next: (cd \"$dir\" && scripts/wmp_render_sweep.sh capture <outdir> --allow-dirty)   # dirty only by:"
    git -C "$dir" status --porcelain | sed 's/^/        /'
else
    echo "next: (cd \"$dir\" && scripts/wmp_render_sweep.sh capture <outdir>)   # tree is clean"
fi
