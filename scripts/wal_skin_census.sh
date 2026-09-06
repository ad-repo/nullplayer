#!/bin/bash
#
# Structural census of the installed Winamp Modern (`.wal`) corpus.
#
# One TSV row per **archive**: what the skin declared, where each surface ended up, how much artwork
# resolved, which NullPlayer-owned windows wear its frame, and the git rev it was all measured at.
# This is the headless 80% of a skin report. It is deliberately *not* a grade — see the rating note
# below, and `.claude/skills/wal-skin-report/SKILL.md` for the letter, which stays human.
#
#   scripts/wal_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--skip-hosted]
#
# Output: <outdir>/census.tsv, plus the raw logs it was derived from (render.txt, hosted.txt) and
# damaged.txt.
#
# See skills/winamp-modern-skin-guide/reference/harness.md and scripts/wal_render_sweep.sh, whose
# rules this script inherits wholesale:
#
#   * **A census is a build — freeze the tree.** Editing anything under Sources/ or Tests/ mid-run
#     invalidates the pass, and a binary that will not compile writes an *empty* capture. Refuses a
#     dirty tree without --allow-dirty. Never run it while the user may be building: SwiftPM lock
#     contention stalls both.
#   * **Redirect, do not pipe.** Piping the run into a filter drops whole blocks with no error.
#   * **Interleaved writes eat blocks of the log at random, in about half of all passes.** That is
#     measured, it is not a dropped container, and re-running does not cure it. A census that
#     inherited the sweep but not this rule would emit *silently missing columns*. So `damaged` is a
#     first-class column: a skin whose log came back damaged gets a row carrying its identity and
#     nothing else, and is named for a re-run alone (`--corpus` a directory holding just that
#     archive). No skin ships to a published document from a damaged log.
#
# **Enumeration rule.** `*.[wW][aA][lL]`, `-type f`. A plain `*.wal` silently drops
# `Defix Hi-END 200.WAL` — one of the six skins that already carries a letter — and a bare `*` picks
# up the `ClassicProEngine` directory, which is a shared engine tree and not an archive. The script
# **prints the count it measured and never asserts a fixed one**: the corpus moves (four skins landed
# overnight on 2026-09-05), so a document quoting a frozen number goes wrong in a way that looks
# right. The sha256 is emitted per row, so archives that are byte-identical under two filenames are
# visible as duplicates downstream instead of being counted twice.

set -u -o pipefail

readonly CORPUS_DEFAULT="$HOME/Library/Application Support/NullPlayer/WinampModernSkins"
# A skin emits ~30 invariant lines; this is the floor per archive that catches a short or empty
# capture, which is what a build failure writes.
readonly MINIMUM_INVARIANT_LINES_PER_SKIN=10
readonly INVARIANT_PATTERN='^(SKIN |RENDER-DUMP (containers|catalog|skin windows|arrangement)|RENDER-DUMP [^ ]+/[^ ]+:|HOLDERS|VIS holder|VIDEO holder|PLAYLIST holder|BITMAPS)'

usage() {
    cat >&2 <<'USAGE'
usage:
  wal_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--skip-hosted] [--parse-only]
USAGE
    exit 2
}

out="" corpus="$CORPUS_DEFAULT" allow_dirty=0 skip_hosted=0 parse_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --skip-hosted) skip_hosted=1; shift ;;
        --parse-only) parse_only=1; shift ;;
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -n "$out" ] && usage; out="$1"; shift ;;
    esac
done
[ -n "$out" ] || usage

if [ ! -d "$corpus" ]; then
    echo "wal_skin_census: no corpus at $corpus" >&2
    exit 1
fi

# The enumeration rule, applied. Counted here so the number in the header is the number that was
# measured, not one this script believes.
archives=$(find "$corpus" -maxdepth 1 -type f -name '*.[wW][aA][lL]' | wc -l | tr -d ' ')
if [ "$archives" -eq 0 ]; then
    echo "wal_skin_census: no .wal archives in $corpus" >&2
    exit 1
fi

if [ "$allow_dirty" -eq 0 ] && [ "$parse_only" -eq 0 ] \
   && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "wal_skin_census: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
    git status --short >&2
    exit 1
fi

rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
measured=$(date +%Y-%m-%d)
mkdir -p "$out"

echo "wal_skin_census: $archives archives in $corpus -> $out (rev $rev)"

# ---------------------------------------------------------------- the render sweep
# `--parse-only` re-derives the TSV from the logs a previous run kept in <outdir>, without paying
# the sweep again. It is how a parsing or rating change is checked against a capture that is already
# known-good, and it never touches the tree or the build.
if [ "$parse_only" -eq 0 ]; then
    # Redirect, do not pipe. RENDER_BITMAPS is what produces the resolved/missing artwork columns.
    WINAMP_MODERN_WAL="$corpus" \
    WINAMP_MODERN_RENDER_DUMP="$out/png" \
    WINAMP_MODERN_RENDER_BITMAPS=1 \
        swift test --filter WinampModernRenderDumpTests > "$out/render.txt" 2> "$out/render.stderr.txt"
    render_status=$?

    grep -E "$INVARIANT_PATTERN" "$out/render.txt" > "$out/invariants.txt"
    lines=$(wc -l < "$out/invariants.txt" | tr -d ' ')
    floor=$((archives * MINIMUM_INVARIANT_LINES_PER_SKIN))
    if [ "$lines" -lt "$floor" ]; then
        echo "wal_skin_census: SHORT CAPTURE ($lines < $floor for $archives skins) — the run failed; see $out/render.txt" >&2
        tail -30 "$out/render.stderr.txt" "$out/render.txt" >&2
        exit 1
    fi
    [ $render_status -ne 0 ] && echo "wal_skin_census: render sweep exited $render_status; read $out/render.txt before trusting it" >&2

    # ------------------------------------------------------------ the hosted-window pass
    # The B110/B140 surface: which NullPlayer-owned windows wear the skin's own frame and which fall
    # back to the standalone classic window.
    if [ "$skip_hosted" -eq 0 ]; then
        WINAMP_MODERN_DRAG_HOSTED="$corpus" \
            swift test --filter WinampModernDragProbe/testHostedWindowDragCoverage \
            > "$out/hosted.txt" 2> "$out/hosted.stderr.txt"
        hosted_status=$?
        [ $hosted_status -ne 0 ] && echo "wal_skin_census: hosted pass exited $hosted_status; read $out/hosted.txt" >&2
    else
        : > "$out/hosted.txt"
    fi
elif [ ! -f "$out/render.txt" ]; then
    echo "wal_skin_census: --parse-only needs a previous capture at $out (missing render.txt)" >&2
    exit 1
fi

# ---------------------------------------------------------------- the TSV
python3 - "$corpus" "$out" "$rev" "$measured" <<'PYCENSUS'
import hashlib, os, re, sys, zipfile

corpus, out, rev, measured = sys.argv[1:5]

# The enumeration rule again, in the language that actually reads the directory. `*.wal` would drop
# `Defix Hi-END 200.WAL`; a bare listing would pick up the ClassicProEngine directory.
files = sorted((name for name in os.listdir(corpus)
                if name.lower().endswith(".wal")
                and os.path.isfile(os.path.join(corpus, name))),
               key=str.lower)

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

def has_screenshot(path):
    """The author's own marketing shot, if the archive ships one — the reference image the vision
    triage compares our render against."""
    try:
        with zipfile.ZipFile(path) as archive:
            return any(os.path.basename(name).lower() == "screenshot.png" for name in archive.namelist())
    except Exception:
        return False

digests, screenshots = {}, {}
for name in files:
    full = os.path.join(corpus, name)
    digests[name] = sha256(full)
    screenshots[name] = has_screenshot(full)

# An archive byte-identical to one already seen is the *same skin* under a second filename. It keeps
# its own row (a row is per file) and names the file it duplicates, so anything counting skins rather
# than files can drop it without re-hashing.
first_seen, duplicate_of = {}, {}
for name in files:
    digest = digests[name]
    if digest in first_seen:
        duplicate_of[name] = first_seen[digest]
    else:
        first_seen[digest] = name

# ---- damaged-log detection, identical in rule to wal_render_sweep.sh -------------------------
DAMAGE = re.compile(r"(SKIN |RENDER-DUMP |BITMAPS |HOLDERS |FINDING \[|Test Case)")

def read(path):
    if not os.path.exists(path):
        return []
    return open(path, errors="replace").read().splitlines()

render = read(os.path.join(out, "render.txt"))

blocks, damaged, current = {}, set(), None
for line in render:
    if line.startswith("SKIN ") and " FAILED " not in line:
        current = line[len("SKIN "):].strip()
        blocks.setdefault(current, [])
    if current is None:
        continue
    blocks[current].append(line)
    hit = DAMAGE.search(line, 1)
    if hit and not line.startswith(" "):
        damaged.add(current)

with open(os.path.join(out, "damaged.txt"), "w") as handle:
    for name in sorted(damaged):
        handle.write(name + "\n")

# ---- the hosted pass ---------------------------------------------------------------------------
# The probe prints the archive's basename *without* its extension for a measured or fallback window
# and *with* it for a failure, and a name may contain spaces, so the field cannot be split on
# whitespace. Match the longest known basename that the line starts with instead.
stems = sorted(((os.path.splitext(name)[0], name) for name in files),
               key=lambda pair: -len(pair[0]))

def owner(rest):
    for stem, name in stems:
        if rest.startswith(stem):
            return name, rest[len(stem):].strip()
    return None, rest

hosted = {name: {"frame": [], "fallback": [], "failed": []} for name in files}
for line in read(os.path.join(out, "hosted.txt")):
    if not line.startswith("HOSTED "):
        continue
    name, rest = owner(line[len("HOSTED "):])
    if name is None:
        continue
    fields = rest.split()
    if not fields:
        continue
    window = fields[0]
    if "classic fallback" in rest:
        hosted[name]["fallback"].append(window)
    elif "FAILED" in rest or "no instantiator" in rest:
        hosted[name]["failed"].append(window if window != "no" else "-")
    elif "drag=" in rest:
        hosted[name]["frame"].append(window)

# ---- per-skin parse ------------------------------------------------------------------------------
LAYOUT = re.compile(r"^RENDER-DUMP (\S+)/(\S+): (\d+)x(\d+), (\d+) nodes")
BITMAPS = re.compile(r"^BITMAPS (\S+)/(\S+): resolved=(\d+) missing=(.*)$")
FINDING = re.compile(r"^FINDING \[(\w+)\] (\S+) ×(\d+) (.*?) @(.*)$")
ARRANGE = re.compile(r"^RENDER-DUMP arrangement=(\S+) embedded=(\[.*?\]) declared=(\[.*?\]) "
                     r"synthesized=(\[.*?\]) fallback=(\[.*?\])$")

def brackets(text):
    """`["a", "b"]` -> `a,b`; `[]` -> `-`. The dump prints Swift array literals."""
    inner = text.strip()[1:-1].strip()
    if not inner:
        return "-"
    return ",".join(part.strip().strip('"') for part in inner.split(",") if part.strip())

def rating(row):
    """The coarse release rating.

    **It is deliberately not the compatibility level.** That level counts diagnostics, not
    correctness — Itemskin reads `unsupported` while drawing correctly, and a skin can read `full`
    and be visibly wrong — so publishing it to users would tell them a working skin is unsupported.

    It is deliberately not built from the finding or missing-bitmap counts either, and that is
    measured, not cautious. Across the corpus on 2026-09-06, 57 of 79 archives referenced at least
    one bitmap that did not resolve and 23 carried an error-severity finding, and neither tracks what
    the skin looks like: cPro Insomnis carries a hand-graded **B** with 15 unresolved ids, Big Bento
    Modern is one of the best-drawing skins in the corpus with 20, and most of the shortfall is
    Wasabi base ids (`wasabi.frame.basetexture`, `component.basetexture`) that nothing visible draws.
    A rating built on those columns would have called 58 of 79 skins broken. They stay in the TSV as
    internal diagnostics; they do not decide the rating.

    The names are chosen to say what was measured rather than to pass judgement. An earlier pass
    called the tiers complete/partial/needs-work, which was wrong in a way a user would feel: the
    bottom tier is mostly skins that predate Winamp's media library and so declare no library window
    at all — Nullsoft's own Winamp3 base skin among them — and "needs work" reads as a defect in the
    skin rather than a surface it never had.

    What is left are the three signals that do describe something a user can see — the archive
    loaded, every surface the skin declares found a home rather than being left with none, and the
    NullPlayer-owned windows wear the skin's own frame instead of the classic standalone window
    (B110/B140). Even so this says only that the pieces are present and placed. It says nothing about
    whether the skin *looks* right; only a live pass and a letter say that."""
    if row["load"] != "ok":
        return "does-not-load"
    if row["dropped_containers"] > 0 or row["surface_fallback"] != "-":
        return "partly-skinned"
    if row["hosted_classic_fallback"] > 0:
        return "player-skinned"
    return "fully-skinned"

COLUMNS = ["file", "sha256", "duplicate_of", "damaged", "load", "level",
           "findings_error", "findings_warning", "findings_info", "finding_codes",
           "arrangement", "surface_embedded", "surface_declared", "surface_synthesized",
           "surface_fallback", "containers", "dropped_containers", "layouts", "nodes",
           "bitmaps_resolved", "bitmaps_missing", "missing_bitmap_ids",
           "hosted_skin_frame", "hosted_classic_fallback", "hosted_failed", "hosted_windows",
           "screenshot", "rating", "measured_rev", "measured_at"]

def cell(value):
    return str(value).replace("\t", " ").replace("\n", " ")

rows = []
for name in files:
    row = dict.fromkeys(COLUMNS, "-")
    row.update(file=name, sha256=digests[name], duplicate_of=duplicate_of.get(name, "-"),
               damaged="no", load="ok", screenshot="yes" if screenshots[name] else "no",
               measured_rev=rev, measured_at=measured)
    lines = blocks.get(name)

    if lines is None:
        # The sweep never reached it at all — a row that says so is the honest one.
        row.update(damaged="no", load="not-run", rating="unknown")
        rows.append(row)
        continue

    if name in damaged:
        # A populated row derived from a log with blocks missing would carry silently wrong columns.
        # Emit identity and the flag, nothing else, and name it for a solo re-run.
        row.update(damaged="yes", load="unknown", rating="unknown")
        rows.append(row)
        continue

    if any(line.startswith("SKIN " + name + " FAILED") for line in render):
        row["load"] = "failed"

    severities = {"error": 0, "warning": 0, "info": 0}
    codes, layouts, nodes = [], 0, 0
    resolved, missing_ids, containers, dropped = 0, set(), 0, 0

    for line in lines:
        if line.startswith("RENDER-DUMP compatibility level="):
            row["level"] = line.split("=", 1)[1].strip()
        elif (match := FINDING.match(line)):
            severity, code, count = match.group(1).lower(), match.group(2), match.group(3)
            severities[severity] = severities.get(severity, 0) + 1
            codes.append(f"{code}x{count}")
        elif (match := ARRANGE.match(line)):
            row.update(arrangement=match.group(1),
                       surface_embedded=brackets(match.group(2)),
                       surface_declared=brackets(match.group(3)),
                       surface_synthesized=brackets(match.group(4)),
                       surface_fallback=brackets(match.group(5)))
        elif line.startswith("RENDER-DUMP containers: "):
            containers = line.count("main=")
        elif line.startswith("RENDER-DUMP dropped container: "):
            dropped += 1
        elif (match := LAYOUT.match(line)):
            layouts += 1
            nodes += int(match.group(5))
        elif (match := BITMAPS.match(line)):
            resolved += int(match.group(3))
            missing_ids.update(match.group(4).split())

    row.update(findings_error=severities.get("error", 0),
               findings_warning=severities.get("warning", 0),
               findings_info=severities.get("info", 0),
               finding_codes=";".join(sorted(set(codes))) or "-",
               containers=containers, dropped_containers=dropped,
               layouts=layouts, nodes=nodes,
               bitmaps_resolved=resolved, bitmaps_missing=len(missing_ids),
               missing_bitmap_ids=" ".join(sorted(missing_ids)[:8]) or "-")

    entry = hosted[name]
    row.update(hosted_skin_frame=len(entry["frame"]),
               hosted_classic_fallback=len(entry["fallback"]),
               hosted_failed=len(entry["failed"]),
               hosted_windows=",".join(entry["frame"]) or "-")
    row["rating"] = rating(row)
    rows.append(row)

path = os.path.join(out, "census.tsv")
with open(path, "w") as handle:
    handle.write("\t".join(COLUMNS) + "\n")
    for row in rows:
        handle.write("\t".join(cell(row[column]) for column in COLUMNS) + "\n")

print(f"wal_skin_census: {len(rows)} rows -> {path}")
distinct = len(set(digests.values()))
print(f"wal_skin_census: {len(files)} archives, {distinct} distinct skins by sha256, "
      f"{sum(1 for name in files if screenshots[name])} shipping screenshot.png")
tally = {}
for row in rows:
    tally[row["rating"]] = tally.get(row["rating"], 0) + 1
print("wal_skin_census: rating " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
if damaged:
    print("wal_skin_census: DAMAGED LOG — no populated row for:")
    for name in sorted(damaged):
        print(f"  {name}")
    print("  Re-run each alone: --corpus <dir holding just that archive>")
PYCENSUS

echo "wal_skin_census: done — $out/census.tsv"
