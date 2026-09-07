#!/bin/bash
#
# Structural census of the installed Windows Media Player (`.wmz`) corpus.
#
# One TSV row per **archive**: whether it loaded at all, what the loader rejected it for, how many
# views and nodes came out, how much artwork resolved, what tags and host members it asks for that
# the engine does not implement, and the git rev it was measured at. This is the row that ranks
# `WMP_TASKS.md`, and it is the only honest source for the counts in that file — everything in there
# today is inherited hand measurement.
#
#   scripts/wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]
#
# Output: <outdir>/census.tsv, plus the raw logs it was derived from (render.txt, render.stderr.txt),
# invariants.txt, damaged.txt, and <outdir>/png/<skin>/*.png.
#
# The canonical probe reference is skills/wmp-skin-guide/reference/harness.md. This script restates
# no flag documentation; it only invokes them.
#
# Rules inherited wholesale from scripts/wal_skin_census.sh rather than re-earned:
#
#   * **A census is a build — freeze the tree.** Editing anything under Sources/ or Tests/ mid-run
#     invalidates the pass, and a binary that will not compile writes an *empty* capture that then
#     reads as "every skin regressed". Refuses a dirty tree without --allow-dirty. Never run it
#     while the user may be building: SwiftPM lock contention stalls both.
#   * **Redirect, do not pipe.** Piping a long `swift test` into a filter drops whole blocks with no
#     error. stderr gets its own file.
#   * **Interleaved writes eat blocks of the log at random.** Two writers land inside one another and
#     the lines they collide with are lost rather than mangled. `damaged` is a first-class column: a
#     skin whose block came back damaged gets a row carrying its identity and nothing else, and is
#     named for a solo re-run (`--corpus` a directory holding just that archive).
#
# **Enumeration rule.** `*.[wW][mM][zZ]`, `-type f`. The script **prints the count it measured and
# never asserts a fixed one**: the corpus moves, and a document quoting a frozen number goes wrong in
# a way that looks right. The sha256 is emitted per row so byte-identical archives under two
# filenames are visible as duplicates downstream instead of being counted twice.

set -u -o pipefail

readonly CORPUS_DEFAULT="$HOME/Library/Application Support/NullPlayer/WMPSkins"
# A loading skin emits at least SKIN + LOAD + COMPAT + one RENDER-DUMP. A *rejected* skin emits only
# SKIN + SKIN…FAILED, and 10 of 14 archives are rejected today, so the floor cannot assume a load.
readonly MINIMUM_INVARIANT_LINES_PER_SKIN=2
readonly INVARIANT_PATTERN='^(HARNESS |SKIN |LOAD |COMPAT |UNKNOWN |FINDING \[|SCRIPTS |RENDER-DUMP |BITMAPS )'

usage() {
    cat >&2 <<'USAGE'
usage:
  wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]
USAGE
    exit 2
}

out="" corpus="$CORPUS_DEFAULT" allow_dirty=0 parse_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --parse-only) parse_only=1; shift ;;
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -n "$out" ] && usage; out="$1"; shift ;;
    esac
done
[ -n "$out" ] || usage

if [ ! -d "$corpus" ]; then
    echo "wmp_skin_census: no corpus at $corpus" >&2
    exit 1
fi

archives=$(find "$corpus" -maxdepth 1 -type f -name '*.[wW][mM][zZ]' | wc -l | tr -d ' ')
if [ "$archives" -eq 0 ]; then
    echo "wmp_skin_census: no .wmz archives in $corpus" >&2
    exit 1
fi

if [ "$allow_dirty" -eq 0 ] && [ "$parse_only" -eq 0 ] \
   && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "wmp_skin_census: working tree is dirty; commit, use a worktree, or pass --allow-dirty" >&2
    git status --short >&2
    exit 1
fi

rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
measured=$(date +%Y-%m-%d)
mkdir -p "$out"

echo "wmp_skin_census: $archives archives in $corpus -> $out (rev $rev)"

if [ "$parse_only" -eq 0 ]; then
    # Redirect, do not pipe. Every probe is on: the census is the one pass that pays for the whole
    # corpus, and a column it did not ask for is a column nobody has.
    WMP_SKIN="$corpus" \
    WMP_RENDER_DUMP="$out/png" \
    WMP_RENDER_BITMAPS=1 \
    WMP_RENDER_SCRIPTS=1 \
    WMP_CALL_TRACE=1 \
        swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus \
        > "$out/render.txt" 2> "$out/render.stderr.txt"
    render_status=$?

    grep -E "$INVARIANT_PATTERN" "$out/render.txt" > "$out/invariants.txt"
    lines=$(wc -l < "$out/invariants.txt" | tr -d ' ')
    floor=$((archives * MINIMUM_INVARIANT_LINES_PER_SKIN))
    if [ "$lines" -lt "$floor" ]; then
        echo "wmp_skin_census: SHORT CAPTURE ($lines < $floor for $archives skins) — the run failed; see $out/render.txt" >&2
        tail -30 "$out/render.stderr.txt" "$out/render.txt" >&2
        exit 1
    fi
    [ $render_status -ne 0 ] && echo "wmp_skin_census: sweep exited $render_status; read $out/render.txt before trusting it" >&2
elif [ ! -f "$out/render.txt" ]; then
    echo "wmp_skin_census: --parse-only needs a previous capture at $out (missing render.txt)" >&2
    exit 1
fi

python3 - "$corpus" "$out" "$rev" "$measured" <<'PYCENSUS'
import hashlib, os, re, sys

corpus, out, rev, measured = sys.argv[1:5]

files = sorted((name for name in os.listdir(corpus)
                if name.lower().endswith(".wmz")
                and os.path.isfile(os.path.join(corpus, name))),
               key=str.lower)

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

digests = {name: sha256(os.path.join(corpus, name)) for name in files}

first_seen, duplicate_of = {}, {}
for name in files:
    digest = digests[name]
    if digest in first_seen:
        duplicate_of[name] = first_seen[digest]
    else:
        first_seen[digest] = name

# ---- damaged-log detection ----------------------------------------------------------------------
# A record prefix appearing anywhere but the start of a line is one write landing inside another, and
# the lines it lands on are lost rather than mangled. A populated row derived from such a block would
# carry silently wrong columns, so the row carries identity and the flag and nothing else.
DAMAGE = re.compile(r"(SKIN |LOAD |COMPAT |RENDER-DUMP |BITMAPS |SCRIPTS |FINDING \[|Test Case)")

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

# A splice is only the *visible* half of a lost write, and the invisible half is the common one:
# of the three losses in the 180-archive run at rev 171cf89a, the scan above saw one. The other two
# blocks simply stopped, because the splice consumed the record prefix that would have betrayed it.
# `views=` is the block's own declaration of how many views must report (a view that fails still
# emits `RENDER-DUMP <view> FAILED`), so a short block is arithmetic rather than inference. A
# rejected archive carries no LOAD line and is not a block with rows missing.
#
# Count **distinct view ids**, not RENDER-DUMP lines. A view that lays out and then fails to
# rasterize emits both lines — the stats dump, then the FAILED one — so `Nautical` reported 2 dumps
# against `views=1` and was called a damaged log when nothing had been lost. Reading a live defect
# (its `vol_slider.bmp` is W33) as a lost log block is the exact failure this check exists to catch,
# pointed the wrong way.
for name, lines in blocks.items():
    loads = [line for line in lines if line.startswith("LOAD ")]
    if len(loads) > 1:
        damaged.add(name)
        continue
    if not loads:
        continue
    declared = re.search(r"\bviews=(\d+)", loads[0])
    reported = {m.group(1) for m in
                (re.match(r"RENDER-DUMP (\S+?):? (?:FAILED|\d)", line) for line in lines) if m}
    if declared and int(declared.group(1)) != len(reported):
        damaged.add(name)

with open(os.path.join(out, "damaged.txt"), "w") as handle:
    for name in sorted(damaged):
        handle.write(name + "\n")

# ---- per-skin parse ------------------------------------------------------------------------------
LOAD = re.compile(r"^LOAD definition=(\S+) encoding=(\S+) entries=(\d+) bytes=(\d+) views=(\d+) "
                  r"nodes=(\d+) scripts=(\d+) resources=(\d+) loadms=([\d.]+)")
COMPAT = re.compile(r"^COMPAT unknown-tags=(\d+) unknown-members=(\d+) "
                    r"resources-missing=(\d+) resources-unsupported=(\d+)")
FINDING = re.compile(r"^FINDING \[(\w+)\] (WMP\d+) ×(\d+) ")
DUMP = re.compile(r"^RENDER-DUMP (\S+): (\S+)x(\S+), (\d+) nodes, (\d+) commands, "
                  r"(\d+) hits, (\d+) widgets, (\d+) unresolved")
BITMAPS = re.compile(r"^BITMAPS (\S+): resolved=(\d+) missing=(.*)$")
SCRIPTS = re.compile(r"^SCRIPTS programs=(\d+)(?: bytes=(\d+))? runtime=(\S+)")
UNKNOWN_TAG = re.compile(r"^UNKNOWN tag (\S+) ×(\d+)")
UNKNOWN_MEMBER = re.compile(r"^UNKNOWN member (\S+) ×(\d+)")
CALLS = re.compile(r"^CALLS \S+ (\S+) ×(\d+) (ok|INERT|UNRECOGNISED)")

COLUMNS = ["file", "sha256", "duplicate_of", "damaged", "load", "reject_codes",
           "encoding", "entries", "views", "nodes", "scripts", "script_runtime",
           "findings_error", "findings_warning", "finding_codes",
           "layouts", "layout_nodes", "commands", "hits", "widgets", "unresolved",
           "bitmaps_resolved", "bitmaps_missing", "missing_bitmaps",
           "unknown_tags", "unknown_members", "top_unknown_members",
           "traced_calls", "unrecognised_calls", "inert_calls",
           "measured_rev", "measured_at"]

def cell(value):
    return str(value).replace("\t", " ").replace("\n", " ")

rows = []
for name in files:
    row = dict.fromkeys(COLUMNS, "-")
    row.update(file=name, sha256=digests[name], duplicate_of=duplicate_of.get(name, "-"),
               damaged="no", load="ok", measured_rev=rev, measured_at=measured)
    lines = blocks.get(name)

    if lines is None:
        # The sweep never reached it at all — a row that says so is the honest one.
        row.update(load="not-run")
        rows.append(row)
        continue

    if name in damaged:
        row.update(damaged="yes", load="unknown")
        rows.append(row)
        continue

    failure = next((line for line in lines
                    if line.startswith("SKIN " + name + " FAILED")), None)
    if failure is not None:
        row["load"] = "failed"
        row["reject_codes"] = ";".join(sorted(set(re.findall(r"WMP\d+", failure)))) or "-"

    severities = {"error": 0, "warning": 0}
    codes, layouts, layout_nodes = [], 0, 0
    commands = hits = widgets = unresolved = 0
    resolved, missing = 0, set()
    unknown_tags, unknown_members = [], []
    traced, unrecognised, inert = 0, set(), set()

    for line in lines:
        if (match := LOAD.match(line)):
            row.update(encoding=match.group(2), entries=match.group(3), views=match.group(5),
                       nodes=match.group(6), scripts=match.group(7))
        elif (match := COMPAT.match(line)):
            row.update(unknown_tags=match.group(1), unknown_members=match.group(2))
        elif (match := SCRIPTS.match(line)):
            row["script_runtime"] = match.group(3)
        elif (match := FINDING.match(line)):
            severity = match.group(1).lower()
            severities[severity] = severities.get(severity, 0) + 1
            codes.append("%sx%s" % (match.group(2), match.group(3)))
        elif (match := DUMP.match(line)):
            layouts += 1
            layout_nodes += int(match.group(4))
            commands += int(match.group(5))
            hits += int(match.group(6))
            widgets += int(match.group(7))
            unresolved += int(match.group(8))
        elif (match := BITMAPS.match(line)):
            resolved += int(match.group(2))
            missing.update(match.group(3).split())
        elif (match := UNKNOWN_TAG.match(line)):
            unknown_tags.append((match.group(1), int(match.group(2))))
        elif (match := UNKNOWN_MEMBER.match(line)):
            unknown_members.append((match.group(1), int(match.group(2))))
        elif (match := CALLS.match(line)):
            traced += int(match.group(2))
            if match.group(3) == "UNRECOGNISED":
                unrecognised.add(match.group(1))
            elif match.group(3) == "INERT":
                # Recognised, answered, and nothing behind it. Counted apart from `ok` because a
                # stub that reads as working is the most expensive bug this engine can carry.
                inert.add(match.group(1))

    row.update(findings_error=severities.get("error", 0),
               findings_warning=severities.get("warning", 0),
               finding_codes=";".join(sorted(set(codes))) or "-",
               layouts=layouts, layout_nodes=layout_nodes, commands=commands,
               hits=hits, widgets=widgets, unresolved=unresolved,
               bitmaps_resolved=resolved, bitmaps_missing=len(missing),
               missing_bitmaps=" ".join(sorted(missing)[:8]) or "-",
               top_unknown_members=" ".join(
                   "%sx%d" % pair for pair in sorted(unknown_members, key=lambda p: -p[1])[:6]) or "-",
               traced_calls=traced,
               unrecognised_calls=" ".join(sorted(unrecognised)[:8]) or "-",
               inert_calls=" ".join(sorted(inert)[:8]) or "-")
    rows.append(row)

path = os.path.join(out, "census.tsv")
with open(path, "w") as handle:
    handle.write("\t".join(COLUMNS) + "\n")
    for row in rows:
        handle.write("\t".join(cell(row[column]) for column in COLUMNS) + "\n")

print("wmp_skin_census: %d rows -> %s" % (len(rows), path))
print("wmp_skin_census: %d archives, %d distinct skins by sha256"
      % (len(files), len(set(digests.values()))))
tally = {}
for row in rows:
    tally[row["load"]] = tally.get(row["load"], 0) + 1
print("wmp_skin_census: load " + ", ".join("%s=%s" % pair for pair in sorted(tally.items())))
codes = {}
for row in rows:
    if row["load"] != "failed" or row["reject_codes"] == "-":
        continue
    for code in row["reject_codes"].split(";"):
        codes[code] = codes.get(code, 0) + 1
if codes:
    print("wmp_skin_census: rejections by code " +
          ", ".join("%s=%d" % pair for pair in sorted(codes.items(), key=lambda p: -p[1])))
if damaged:
    print("wmp_skin_census: DAMAGED LOG — no populated row for:")
    for name in sorted(damaged):
        print("  " + name)
    print("  Re-run each alone: --corpus <dir holding just that archive>")
PYCENSUS

echo "wmp_skin_census: done — $out/census.tsv"
