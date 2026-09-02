#!/bin/bash
#
# Corpus render sweep for the Winamp Modern (`.wal`) engine.
#
# A change to loading, initialization, script startup, hit testing or drawing reaches every skin, so
# the proof that it broke none of them is a before/after capture across the whole installed corpus.
# `WINAMP_MODERN_WAL` takes a directory and loops it inside one invocation (B72), which is what makes
# this a couple of minutes rather than the ~25 of a shell loop over the archives.
#
#   scripts/wal_render_sweep.sh capture <outdir>       one pass: raw log, invariant lines, PNGs
#   scripts/wal_render_sweep.sh compare <base> <curr>  invariants diff + per-image maxdelta report
#
# See skills/winamp-modern-skin-guide/reference/harness.md § "The corpus render sweep".
#
# Two rules this script exists to enforce, both already paid for:
#
#   * A sweep is a build — freeze the tree. Editing anything under Sources/ or Tests/ mid-run
#     invalidates the pass, and a binary that will not compile writes an *empty* capture, which
#     diffs as "everything changed". `capture` refuses a dirty tree without --allow-dirty and fails
#     loudly on a short capture.
#   * Redirect the run to a file and grep the file. Piping the sweep straight into `grep` drops
#     lines: the test binary's stdout and the runner's interleave under a pipe and whole blocks go
#     missing with no error, which reads exactly like a dropped container and is not one.
#   * Keep stdout and stderr in *separate* files. `> raw.txt 2>&1` is not enough: the test runner's
#     own banners reach fd 2 through a second file offset, so they overwrite stdout mid-line and the
#     dump lines they land on are lost outright. Measured 2026-09-02 — BLAKK.wal lost 25 invariant
#     lines that way while every one of its PNGs stayed byte-identical, which is precisely the shape
#     of a dropped container. The same pass with the streams split captured all 2031 lines with no
#     collisions at all. `capture` checks for the residue and refuses to hand on a colliding pass.
#
# Never capture the baseline with `git stash` — it relinks .build under the user's running app. Use
# a worktree:
#
#   git worktree add ../nullplayer-base HEAD
#   cp -R .build/arm64-apple-macosx/debug/*.framework \
#         .build/arm64-apple-macosx/debug/*.dylib ../nullplayer-base/.build/arm64-apple-macosx/debug/
#   (cd ../nullplayer-base && scripts/wal_render_sweep.sh capture /tmp/sweep/base)

set -u -o pipefail

readonly CORPUS_DEFAULT="$HOME/Library/Application Support/NullPlayer/WinampModernSkins"
# A skin emits ~30 invariant lines. The check is against a short or empty capture — a build failure
# writes an empty one, and an empty capture diffs as "everything changed" — so this is a floor per
# archive rather than a total, and single-skin runs are checked as strictly as a corpus pass.
readonly MINIMUM_INVARIANT_LINES_PER_SKIN=10

# The lines worth diffing: the container list, the surface catalog, the window menu, every layout's
# canvas size and node count, every hosted holder's frame, and the resolved/missing bitmap counts.
readonly INVARIANT_PATTERN='^(SKIN |RENDER-DUMP (containers|catalog|skin windows|arrangement)|RENDER-DUMP [^ ]+/[^ ]+:|HOLDERS|VIS holder|VIDEO holder|PLAYLIST holder|BITMAPS)'

usage() {
    cat >&2 <<'USAGE'
usage:
  wal_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir>]
  wal_render_sweep.sh compare <base-outdir> <curr-outdir>
USAGE
    exit 2
}

capture() {
    local out="" corpus="$CORPUS_DEFAULT" allow_dirty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --allow-dirty) allow_dirty=1; shift ;;
            --corpus) corpus="${2:-}"; shift 2 ;;
            -*) echo "unknown option: $1" >&2; usage ;;
            *) [ -n "$out" ] && usage; out="$1"; shift ;;
        esac
    done
    [ -n "$out" ] || usage

    if [ ! -d "$corpus" ]; then
        echo "wal_render_sweep: no corpus at $corpus" >&2
        exit 1
    fi
    local archives
    archives=$(find "$corpus" -maxdepth 1 -name '*.wal' | wc -l | tr -d ' ')
    if [ "$archives" -eq 0 ]; then
        echo "wal_render_sweep: no .wal archives in $corpus" >&2
        exit 1
    fi

    # A sweep is a build. An edit landing mid-run invalidates the pass, and the pair of passes is
    # what is being compared, so an uncommitted difference between them is exactly the thing this
    # guard is for.
    if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "wal_render_sweep: working tree is dirty; commit, stash-free-worktree, or pass --allow-dirty" >&2
        git status --short >&2
        exit 1
    fi

    mkdir -p "$out/png"
    echo "wal_render_sweep: capturing $archives skins -> $out"
    # Redirect, do not pipe. See the note at the top.
    WINAMP_MODERN_WAL="$corpus" \
    WINAMP_MODERN_RENDER_DUMP="$out/png" \
    WINAMP_MODERN_RENDER_BITMAPS=1 \
        swift test --filter WinampModernRenderDumpTests > "$out/raw.txt" 2> "$out/stderr.txt"
    local status=$?

    grep -E "$INVARIANT_PATTERN" "$out/raw.txt" > "$out/invariants.txt"
    local lines
    lines=$(wc -l < "$out/invariants.txt" | tr -d ' ')
    echo "wal_render_sweep: $lines invariant lines, $(find "$out/png" -name '*.png' | wc -l | tr -d ' ') images"

    local floor=$((archives * MINIMUM_INVARIANT_LINES_PER_SKIN))
    if [ "$lines" -lt "$floor" ]; then
        echo "wal_render_sweep: SHORT CAPTURE ($lines < $floor for $archives skins) — the run failed; see $out/raw.txt" >&2
        tail -30 "$out/stderr.txt" "$out/raw.txt" >&2
        exit 1
    fi
    # A record prefix appearing anywhere but the start of a line is one write landing inside
    # another. The lines it lands on are gone, not merely mangled, so the capture cannot be diffed —
    # say so here rather than let it read as a regression in whichever skin it hit.
    local collisions
    collisions=$(grep -cE '.+(SKIN |RENDER-DUMP |BITMAPS |HOLDERS |FINDING \[|Test Case)' "$out/raw.txt" 2>/dev/null || true)
    if [ "${collisions:-0}" -gt 0 ]; then
        echo "wal_render_sweep: $collisions COLLIDED LINES — interleaved writes ate part of this capture; re-run it" >&2
        grep -nE '.+(SKIN |RENDER-DUMP |BITMAPS |HOLDERS |FINDING \[|Test Case)' "$out/raw.txt" | head -5 >&2
        exit 1
    fi
    if [ $status -ne 0 ]; then
        echo "wal_render_sweep: swift test exited $status; capture kept, read $out/raw.txt before trusting it" >&2
    fi
    # A skin that fails to load prints SKIN <file> FAILED and the sweep carries on, which is right —
    # one broken archive must not abandon the other 68 — but it should never pass unremarked.
    if grep -q ' FAILED ' "$out/invariants.txt"; then
        echo "wal_render_sweep: skins that failed to load:" >&2
        grep ' FAILED ' "$out/invariants.txt" >&2
    fi
}

compare() {
    [ $# -eq 2 ] || usage
    local base="$1" curr="$2"
    for dir in "$base" "$curr"; do
        if [ ! -f "$dir/invariants.txt" ]; then
            echo "wal_render_sweep: no capture at $dir (missing invariants.txt)" >&2
            exit 1
        fi
    done

    echo "=== invariants ==="
    # XCTest's own "Test Case … passed" banner shares the runner's stdout with the dump and lands
    # *inside* a line — the dump lines carry no trailing newline — so a line it collides with differs
    # between two runs of one unchanged binary. Verified 2026-09-02: two passes over the same build
    # differed on exactly those lines and on nothing else, with all 590 images byte-identical. Set
    # them aside and count them separately rather than making a human re-derive that every sweep.
    python3 - "$base/invariants.txt" "$curr/invariants.txt" <<'PYINVARIANTS'
import difflib, sys

BANNER = "Test Case '-["

base = open(sys.argv[1], errors="replace").read().splitlines()
curr = open(sys.argv[2], errors="replace").read().splitlines()

real, noise = [], 0
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, base, curr, autojunk=False).get_opcodes():
    if tag == "equal":
        continue
    block = base[i1:i2] + curr[j1:j2]
    if any(BANNER in line for line in block):
        noise += len(block)
        continue
    real += ["- " + line for line in base[i1:i2]]
    real += ["+ " + line for line in curr[j1:j2]]

summary = "%d base lines, %d curr lines" % (len(base), len(curr))
if noise:
    summary += ", %d set aside as XCTest banner interleaving" % noise
if not real:
    print("identical (" + summary + ")")
else:
    print("DIFFER \u2014 %d changed lines (%s)" % (len(real), summary))
    for line in real[:80]:
        print("  " + line)
    if len(real) > 80:
        print("  \u2026 %d more" % (len(real) - 80))
PYINVARIANTS

    echo
    echo "=== images ==="
    python3 - "$base/png" "$curr/png" <<'PY'
import os, sys
from PIL import Image, ImageChops

base, curr = sys.argv[1], sys.argv[2]

def index(root):
    found = {}
    for dirpath, _, names in os.walk(root):
        for name in names:
            if name.lower().endswith(".png"):
                full = os.path.join(dirpath, name)
                found[os.path.relpath(full, root)] = full
    return found

a, b = index(base), index(curr)
only_base = sorted(set(a) - set(b))
only_curr = sorted(set(b) - set(a))
shared = sorted(set(a) & set(b))

identical, differing, unreadable = 0, [], []
for name in shared:
    try:
        with Image.open(a[name]) as ia, Image.open(b[name]) as ib:
            ia, ib = ia.convert("RGBA"), ib.convert("RGBA")
            if ia.size != ib.size:
                differing.append((name, "size %s -> %s" % (ia.size, ib.size)))
                continue
            # Per-channel maximum absolute difference. A maxdelta of 1 is an LSB rounding
            # difference, not a regression — the tiling rewrite left 12 of 288 that way. This
            # reports the number; a human reads it.
            delta = ImageChops.difference(ia, ib)
            bbox = delta.getbbox()
            if bbox is None:
                identical += 1
            else:
                maxdelta = max(band.getextrema()[1] for band in delta.split())
                pixels = sum(1 for p in delta.getdata() if p[:3] != (0, 0, 0) or p[3] != 0)
                differing.append((name, "maxdelta=%d over %d px, bbox=%s" % (maxdelta, pixels, bbox)))
    except Exception as error:                                    # a truncated or absent PNG
        unreadable.append((name, str(error)))

print("%d identical, %d differing, %d only in base, %d only in curr, %d unreadable"
      % (identical, len(differing), len(only_base), len(only_curr), len(unreadable)))
for name, why in differing:
    print("  DIFF %s  %s" % (name, why))
for name in only_base:
    print("  ONLY-BASE %s" % name)
for name in only_curr:
    print("  ONLY-CURR %s" % name)
for name, why in unreadable:
    print("  UNREADABLE %s  %s" % (name, why))
PY
}

[ $# -ge 1 ] || usage
command="$1"; shift
case "$command" in
    capture) capture "$@" ;;
    compare) compare "$@" ;;
    *) usage ;;
esac
