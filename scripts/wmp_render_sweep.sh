#!/bin/bash
#
# Corpus render sweep for the Windows Media Player (`.wmz`) engine.
#
# A change to loading, XML parsing, text decoding, script startup, layout or drawing reaches every
# skin, so the proof that it broke none of them is a before/after capture across the whole installed
# corpus. `WMP_SKIN` takes a directory and loops it inside one invocation, which is what makes this
# one test-binary startup rather than fourteen.
#
#   scripts/wmp_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir>]
#   scripts/wmp_render_sweep.sh compare <base-outdir> <curr-outdir>
#
# Run `capture` before an engine-wide change and `compare` after. Every engine change from Phase 2
# onward is expected to pass through this. See skills/wmp-skin-guide/reference/harness.md for the
# probe flags; this script documents none of them.
#
# Rules this script exists to enforce, all already paid for by the `.wal` subsystem:
#
#   * **A sweep is a build — freeze the tree.** An edit landing mid-run invalidates the pass, and a
#     binary that will not compile writes an *empty* capture, which diffs as "everything changed".
#     `capture` refuses a dirty tree without --allow-dirty and fails loudly on a short capture.
#   * **Redirect the run to a file and grep the file.** Piping a long `swift test` into a filter
#     drops lines silently; stderr gets its own file.
#   * **Interleaved writes eat whole blocks of the log, at random.** Two writers land inside one
#     another and the dump lines they collide with are lost outright, not merely mangled — which
#     reads exactly like a skin that stopped drawing and is not one. `capture` names the damaged
#     skins in damaged.txt; `compare` leaves them out of the invariants diff and says so. Their PNGs
#     are unaffected and are still compared.
#   * **Compare pixels, not alpha.** Pillow 9.5 made `getbbox()` on an RGBA image consider the alpha
#     channel alone, and every dump here carries alpha — so a change that moved a visible control but
#     left alpha untouched came back "identical" across 590 images. `alpha_only=False` is load-
#     bearing, not tidiness.
#
# Never capture the baseline with `git stash` — it relinks .build under the user's running app. Use
# a worktree:
#
#   git worktree add ../nullplayer-base HEAD
#   (cd ../nullplayer-base && scripts/wmp_render_sweep.sh capture /tmp/wmp-sweep/base)

set -u -o pipefail

readonly CORPUS_DEFAULT="$HOME/Library/Application Support/NullPlayer/WMPSkins"
# A rejected archive emits only SKIN + SKIN…FAILED, and 10 of 14 are rejected today, so the floor
# per archive cannot assume a load. It exists to catch an empty or truncated capture.
readonly MINIMUM_INVARIANT_LINES_PER_SKIN=2

# The lines worth diffing: the archive frame, what loaded and how, the finding tally, the
# unimplemented surface, and every view's canvas size, node/command/hit counts and artwork tally.
# PROBE/EXPR/CALL lines are deliberately out: they are for isolating one defect, not for regression.
readonly INVARIANT_PATTERN='^(HARNESS |SKIN |LOAD |COMPAT |UNKNOWN |FINDING \[|SCRIPTS |SCRIPT |RENDER-DUMP |BITMAPS |PNG )'

usage() {
    cat >&2 <<'USAGE'
usage:
  wmp_render_sweep.sh capture <outdir> [--allow-dirty] [--corpus <dir>]
  wmp_render_sweep.sh compare <base-outdir> <curr-outdir>
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
        echo "wmp_render_sweep: no corpus at $corpus" >&2
        exit 1
    fi
    # Enumeration rule: `-type f`, case-insensitive extension, and the count printed rather than
    # asserted — the corpus moves.
    local archives
    archives=$(find "$corpus" -maxdepth 1 -type f -name '*.[wW][mM][zZ]' | wc -l | tr -d ' ')
    if [ "$archives" -eq 0 ]; then
        echo "wmp_render_sweep: no .wmz archives in $corpus" >&2
        exit 1
    fi

    if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "wmp_render_sweep: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
        git status --short >&2
        exit 1
    fi

    mkdir -p "$out/png"
    echo "wmp_render_sweep: capturing $archives skins -> $out"
    # Redirect, do not pipe. See the note at the top.
    WMP_SKIN="$corpus" \
    WMP_RENDER_DUMP="$out/png" \
    WMP_RENDER_BITMAPS=1 \
    WMP_RENDER_SCRIPTS=1 \
        swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus \
        > "$out/raw.txt" 2> "$out/stderr.txt"
    local status=$?

    grep -E "$INVARIANT_PATTERN" "$out/raw.txt" > "$out/invariants.txt"
    local lines
    lines=$(wc -l < "$out/invariants.txt" | tr -d ' ')
    echo "wmp_render_sweep: $lines invariant lines, $(find "$out/png" -name '*.png' | wc -l | tr -d ' ') images"

    local floor=$((archives * MINIMUM_INVARIANT_LINES_PER_SKIN))
    if [ "$lines" -lt "$floor" ]; then
        echo "wmp_render_sweep: SHORT CAPTURE ($lines < $floor for $archives skins) — the run failed; see $out/raw.txt" >&2
        tail -30 "$out/stderr.txt" "$out/raw.txt" >&2
        exit 1
    fi

    python3 - "$out/raw.txt" > "$out/damaged.txt" <<'PYDAMAGED'
import re, sys

PREFIX = re.compile(r"(SKIN |LOAD |COMPAT |RENDER-DUMP |BITMAPS |SCRIPTS |FINDING \[|Test Case)")
skin, damaged = "<before any skin>", []
blocks = {}
for line in open(sys.argv[1], errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("SKIN "):
        skin = line[len("SKIN "):].strip().split(" FAILED ")[0]
        blocks.setdefault(skin, [])
    if skin in blocks:
        blocks[skin].append(line)
    hit = PREFIX.search(line, 1)
    if hit and not line.startswith(" "):
        damaged.append(skin)

# A splice is only the *visible* half of a lost write. Two of the three losses in the 180-archive
# run left no spliced prefix at all — one block simply stopped, and the prefix-scan above saw
# nothing. `views=` is the block's own declaration of how many RENDER-DUMP lines must follow it
# (a view that fails still emits `RENDER-DUMP <view> FAILED`), so a short block is arithmetic, not
# inference. Rejected archives carry no LOAD line and are not blocks with missing rows.
for name, lines in blocks.items():
    loads = [line for line in lines if line.startswith("LOAD ")]
    if len(loads) > 1:
        damaged.append(name)
        continue
    if not loads:
        continue
    declared = re.search(r"\bviews=(\d+)", loads[0])
    dumps = sum(1 for line in lines if line.startswith("RENDER-DUMP "))
    if declared and int(declared.group(1)) != dumps:
        damaged.append(name)

for name in dict.fromkeys(damaged):
    print(name)
PYDAMAGED
    if [ -s "$out/damaged.txt" ]; then
        echo "wmp_render_sweep: interleaved writes damaged the log for:" >&2
        sed 's/^/  /' "$out/damaged.txt" >&2
        echo '  Their PNGs are unaffected and still compare; compare leaves their lines out.' >&2
        echo "  To check those lines, run each alone: --corpus <dir holding just that .wmz>" >&2
    fi
    if [ $status -ne 0 ]; then
        echo "wmp_render_sweep: swift test exited $status; capture kept, read $out/raw.txt before trusting it" >&2
    fi
    # A skin that fails to load prints SKIN <file> FAILED and the sweep carries on, which is right,
    # but it should never pass unremarked — 10 of 14 do today and driving that to 0 is Phase 2.
    if grep -q ' FAILED ' "$out/invariants.txt"; then
        echo "wmp_render_sweep: skins that failed to load:" >&2
        grep ' FAILED ' "$out/invariants.txt" >&2
    fi
}

compare() {
    [ $# -eq 2 ] || usage
    local base="$1" curr="$2"
    for dir in "$base" "$curr"; do
        if [ ! -f "$dir/invariants.txt" ]; then
            echo "wmp_render_sweep: no capture at $dir (missing invariants.txt)" >&2
            exit 1
        fi
    done

    echo "=== invariants ==="
    cat "$base/damaged.txt" "$curr/damaged.txt" 2>/dev/null | sort -u > /tmp/wmp_sweep_damaged.txt
    python3 - "$base/invariants.txt" "$curr/invariants.txt" /tmp/wmp_sweep_damaged.txt <<'PYINVARIANTS'
import difflib, os, sys

# XCTest's own banner shares the runner's stdout with the dump and can land inside a line, so a line
# it collides with differs between two runs of one unchanged binary. Set those aside and count them.
BANNER = "Test Case '-["

def read(path):
    return open(path, errors="replace").read().splitlines()

damaged = set(read(sys.argv[3])) if os.path.exists(sys.argv[3]) else set()

def usable(lines):
    """Drop the blocks of skins whose log came back damaged — their lines are missing, not changed,
    and diffing them reports a regression that is not there."""
    kept, skipping = [], False
    for line in lines:
        if line.startswith("SKIN "):
            skipping = line[len("SKIN "):].strip().split(" FAILED ")[0] in damaged
        if not skipping:
            kept.append(line)
    return kept

base = usable(read(sys.argv[1]))
curr = usable(read(sys.argv[2]))

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
if damaged:
    summary += ", %d skin(s) not compared" % len(damaged)
if not real:
    print("identical (" + summary + ")")
else:
    print("DIFFER — %d changed lines (%s)" % (len(real), summary))
    for line in real[:80]:
        print("  " + line)
    if len(real) > 80:
        print("  … %d more" % (len(real) - 80))
PYINVARIANTS
    if [ -s /tmp/wmp_sweep_damaged.txt ]; then
        echo "NOT COMPARED — interleaved writes damaged these skins' log lines; run each alone:"
        sed 's/^/  /' /tmp/wmp_sweep_damaged.txt
    fi

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
            delta = ImageChops.difference(ia, ib)
            # Load-bearing: without alpha_only=False a colour-only change reports bbox None and the
            # pair is counted identical. See the note at the top of this file.
            try:
                bbox = delta.getbbox(alpha_only=False)
            except TypeError:                                     # Pillow < 9.5 has no such flag
                bbox = delta.getbbox()
            if bbox is None:
                identical += 1
            else:
                # A maxdelta of 1 is an LSB rounding difference, not a regression. This reports the
                # number; a human reads it.
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
