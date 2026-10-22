#!/bin/bash
#
# Corpus render sweep for the Winamp Modern (`.wal`) engine.
#
# A change to loading, initialization, script startup, hit testing or drawing reaches every skin, so
# the proof that it broke none of them is a before/after capture across the whole corpus (gold+silver,
# scripts/lib/wal_corpus.sh).
# `WINAMP_MODERN_WAL` takes a directory and loops it inside one invocation (B72), which is what makes
# this a couple of minutes rather than the ~25 of a shell loop over the archives.
#
#   scripts/wal_render_sweep.sh capture <outdir>       one pass: raw log, invariant lines, PNGs
#       --touching <feature,…> --index <features.tsv>  only the skins (every tier) the index says use them
#       --shards K                                      K test processes after one build; pass the core count
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
#   * **Read each skin's own log, never the shared stdout.** On stdout, interleaved writes ate whole
#     blocks of the log at random in about half of all passes (measured 2026-09-02: one pass lost 25
#     of BLAKK.wal's invariant lines, another 3 of Itemskin.wal's, PNGs byte-identical). Since B166
#     the harness writes every skin's lines to `png/<skin>.log`, which nothing else writes to, and
#     `invariants.txt` is built from those files. `raw.txt` is kept for reading, not for diffing.

# Never capture the baseline with `git stash` — it relinks .build under the user's running app. Use
# a worktree:
#
#   scripts/baseline_worktree.sh ../nullplayer-base HEAD
#   (cd ../nullplayer-base && scripts/wal_render_sweep.sh capture /tmp/sweep/base)
#
# Add --allow-dirty only when baseline_worktree.sh says its framework links dirty the tree; it is
# safe there only.

set -u -o pipefail

# Pin the native build system where offered: the default on Swift 6.4 cannot build the test
# target (no VLCKit), which would leave an empty capture. See scripts/lib/swiftpm.sh.
source "$(dirname "$0")/lib/swiftpm.sh"
source "$(dirname "$0")/lib/wal_corpus.sh"
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
  wal_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir[:dir…]>]   (default gold:silver)
                              [--touching <feature,…> --index <features.tsv>]  (default corpus: every tier)
                              [--shards <K>]
  wal_render_sweep.sh compare <base-outdir> <curr-outdir>
USAGE
    exit 2
}

capture() {
    local out="" corpus="" allow_dirty=0 touching="" index="" shards=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --allow-dirty) allow_dirty=1; shift ;;
            --corpus) corpus="${2:-}"; shift 2 ;;
            --touching) touching="${2:-}"; shift 2 ;;
            --index) index="${2:-}"; shift 2 ;;
            --shards) shards="${2:-}"; shift 2 ;;
            -*) echo "unknown option: $1" >&2; usage ;;
            *) [ -n "$out" ] && usage; out="$1"; shift ;;
        esac
    done
    [ -n "$out" ] || usage
    [[ "$shards" =~ ^[1-9][0-9]*$ ]] || { echo "wal_render_sweep: --shards takes a positive count" >&2; usage; }
    # An impact-selected sweep reaches every tier; the pre-merge gate is gold+silver (§8).
    [ -n "$corpus" ] || corpus=$([ -n "$touching" ] && echo "$WAL_CORPUS_ALL" || echo "$WAL_CORPUS_DEFAULT")

    local list
    list=$(wal_corpus_archives "$corpus") || exit 1
    if [ -n "$touching" ]; then
        [ -f "$index" ] || { echo "wal_render_sweep: --touching needs --index <features.tsv> (wal_feature_index.sh)" >&2; exit 2; }
        list=$(select_touching "$index" "$touching" "$list") || exit 1
    fi
    local archives
    archives=$(printf '%s' "$list" | grep -c .)
    if [ "$archives" -eq 0 ]; then
        echo "wal_render_sweep: no .wal archives in $corpus" >&2
        exit 1
    fi

    # The pair of passes is what is being compared, so an uncommitted difference between them is
    # exactly the thing this guard is for.
    wal_require_clean_tree wal_render_sweep "$allow_dirty" || exit 1

    mkdir -p "$out/png"
    rm -f "$out"/png/*.log "$out"/raw-*.txt "$out"/stderr-*.txt
    [ "$shards" -gt "$archives" ] && shards=$archives
    echo "wal_render_sweep: capturing $archives skins in $shards shard(s) -> $out"
    wal_build_tests wal_render_sweep "$out" || exit 1

    local status=0
    wal_run_shards "$shards" "$list" render_shard || status=$?
    cat "$out"/raw-*.txt > "$out/raw.txt"
    cat "$out"/stderr-*.txt > "$out/stderr.txt"

    # One log per skin (B166), concatenated in a fixed order so two captures line up.
    cat "$out"/png/*.log 2>/dev/null | grep -E "$INVARIANT_PATTERN" > "$out/invariants.txt"
    local lines
    lines=$(wc -l < "$out/invariants.txt" | tr -d ' ')
    echo "wal_render_sweep: $lines invariant lines, $(find "$out/png" -name '*.png' | wc -l | tr -d ' ') images"

    local floor=$((archives * MINIMUM_INVARIANT_LINES_PER_SKIN))
    if [ "$lines" -lt "$floor" ]; then
        echo "wal_render_sweep: SHORT CAPTURE ($lines < $floor for $archives skins) — the run failed; see $out/raw.txt" >&2
        tail -30 "$out/stderr.txt" "$out/raw.txt" >&2
        exit 1
    fi
    local logs
    logs=$(find "$out/png" -maxdepth 1 -name '*.log' | wc -l | tr -d ' ')
    if [ "$logs" -ne "$archives" ]; then
        echo "wal_render_sweep: $logs skin logs for $archives archives — a skin is missing its log; see $out/stderr.txt" >&2
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

# render_shard <shard> <archives:…> <bundle>: one shard of `capture` (whose `$out` it writes to), for
# wal_run_shards. Redirect, do not pipe — see the note at the top.
render_shard() {
    WINAMP_MODERN_WAL="$2" \
    WINAMP_MODERN_RENDER_DUMP="$out/png" \
    WINAMP_MODERN_RENDER_BITMAPS=1 \
        xcrun xctest -XCTest NullPlayerAppTests.WinampModernRenderDumpTests "$3" \
        > "$out/raw-$1.txt" 2> "$out/stderr-$1.txt"
}

# select_touching <features.tsv> <feature,…> <archive list>: the archives whose index rows name any of
# the features — the `feature` column, case-insensitive, any kind (`Wasabi:Frame` is the xml-tag).
# A matching skin the corpus does not hold means the index is stale, which fails rather than
# quietly sweeping fewer skins than the change reaches.
select_touching() {
    python3 - "$@" <<'PYTOUCHING'
import os, sys
index, features, archives = sys.argv[1], sys.argv[2], sys.argv[3].splitlines()
wanted = {f.strip().lower() for f in features.split(",") if f.strip()}
with open(index, errors="replace") as handle:
    next(handle)
    skins = {row[0] for row in (line.rstrip("\n").split("\t") for line in handle) if row[3].lower() in wanted}
by_name = {os.path.basename(path): path for path in archives}
missing = sorted(skins - by_name.keys())
if missing:
    sys.exit("wal_render_sweep: the index names skins the corpus lacks (stale index?): " + ", ".join(missing))
print("wal_render_sweep: %d skins touch %s" % (len(skins), ",".join(sorted(wanted))), file=sys.stderr)
print("\n".join(by_name[skin] for skin in sorted(skins)))
PYTOUCHING
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
    python3 - "$base/invariants.txt" "$curr/invariants.txt" <<'PYINVARIANTS'
import difflib, sys

def read(path):
    return open(path, errors="replace").read().splitlines()

base, curr = read(sys.argv[1]), read(sys.argv[2])
real = []
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, base, curr, autojunk=False).get_opcodes():
    if tag == "equal":
        continue
    real += ["- " + line for line in base[i1:i2]]
    real += ["+ " + line for line in curr[j1:j2]]

summary = "%d base lines, %d curr lines" % (len(base), len(curr))
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
            # `alpha_only=False` is load-bearing, not tidiness. Pillow 9.5 made `getbbox()` on an
            # image *with* an alpha channel look at the alpha alone, and every dump here is RGBA —
            # so a difference that changed only colour reported a bbox of `None` and the pair was
            # counted **identical**. Measured 2026-09-03: BLAKK's boombox moved a 191x10 volume bar
            # and the sweep called all 590 images clean. A comparison that cannot see a repaint is
            # not a regression proof, and it had been silently passing changes for as long as the
            # dumps have carried alpha.
            try:
                bbox = delta.getbbox(alpha_only=False)
            except TypeError:                                     # Pillow < 9.5 has no such flag
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
