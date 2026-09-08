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
# Output: <outdir>/census.tsv, <outdir>/starved.tsv (every view ranked by how much of it failed to
# resolve — see W70), <outdir>/appkit.tsv (every hosted view ranked by how much of the window an
# AppKit overlay painted outside any widget frame — see W71), plus the raw logs it was derived from (render.txt, render.stderr.txt),
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
readonly INVARIANT_PATTERN='^(HARNESS |SKIN |LOAD |COMPAT |UNKNOWN |FINDING \[|SCRIPTS |RENDER-DUMP |BITMAPS |APPKIT )'

# ---- exclusions ---------------------------------------------------------------------------------
# A blacklisted archive is dropped before anything measures it, by linking the corpus into a farm of
# the archives that are in scope and sweeping that. Filtering afterwards would still let an excluded
# skin's diagnostics into the logs the backlog is ranked from, which is the whole point of excluding
# it. The list and its reasons are scripts/wmp_corpus_exclusions.txt.
exclusion_farm() {  # <corpus> <farmdir> <tool-name> -> prints the measured count on stdout
    local src="$1" farm="$2" tool="$3" name dropped=0 kept=0
    local list; list="$(dirname "$0")/wmp_corpus_exclusions.txt"
    rm -rf "$farm"; mkdir -p "$farm"
    while IFS= read -r archive; do
        name=$(basename "$archive")
        if [ -f "$list" ] && grep -v '^[[:space:]]*#' "$list" | grep -qxF "$name"; then
            dropped=$((dropped + 1))
            echo "$tool: excluded $name (scripts/wmp_corpus_exclusions.txt)" >&2
            continue
        fi
        # Hard link, not a symlink: the harness enumerates with `isRegularFile`, which a symlink
        # is not, and the sweep then reports an empty corpus instead of an excluded one. Copy only
        # if the farm lands on another volume.
        ln "$archive" "$farm/$name" 2>/dev/null || cp "$archive" "$farm/$name"
        kept=$((kept + 1))
    done < <(find "$src" -maxdepth 1 -type f -name '*.[wW][mM][zZ]')
    [ "$dropped" -gt 0 ] && echo "$tool: $dropped archive(s) excluded; measuring $kept" >&2
    echo "$kept"
}

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

# Everything downstream — the sweep, the sha256 rows, the denominator — sees the farm, not the
# installed directory, so an excluded skin cannot reach a column.
source_corpus="$corpus"
archives=$(exclusion_farm "$corpus" "$out/corpus" wmp_skin_census)
corpus="$out/corpus"
if [ "$archives" -eq 0 ]; then
    echo "wmp_skin_census: every archive in $source_corpus is excluded" >&2
    exit 1
fi

echo "wmp_skin_census: $archives archives in $source_corpus -> $out (rev $rev)"

if [ "$parse_only" -eq 0 ]; then
    # Redirect, do not pipe. Every probe is on: the census is the one pass that pays for the whole
    # corpus, and a column it did not ask for is a column nobody has.
    WMP_SKIN="$corpus" \
    WMP_RENDER_DUMP="$out/png" \
    WMP_RENDER_BITMAPS=1 \
    WMP_RENDER_SCRIPTS=1 \
    WMP_CALL_TRACE=1 \
    WMP_RENDER_APPKIT=1 \
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
# W71. `outside` is the number that ranks: an overlay painting inside its own widget frame is the
# hosting working, and one painting anywhere else is the W43 class — an AppKit surface over the
# artwork, which no dumped PNG can see because the renderer draws the scene and these are NSViews
# hosted over it.
APPKIT = re.compile(r"^APPKIT (\S+): (\S+)@(\d+)x differing=(\d+)/(\d+) \S+ hosted=(\d+)/(\d+) "
                    r"outside=(\d+) \(\S+\) max-delta=(\d+) blit=(\d+) \(\S+\) blit-max-delta=(\d+)")

COLUMNS = ["file", "sha256", "duplicate_of", "damaged", "load", "reject_codes",
           "encoding", "entries", "views", "nodes", "scripts", "script_runtime",
           "findings_error", "findings_warning", "finding_codes",
           "layouts", "layout_nodes", "commands", "hits", "widgets", "unresolved",
           "starved_views", "blind_views", "silent_views", "worst_view", "worst_ratio",
           "appkit_outside_px", "appkit_max_delta", "appkit_worst_view", "appkit_blit_px",
           "bitmaps_resolved", "bitmaps_missing", "missing_bitmaps",
           "unknown_tags", "unknown_members", "top_unknown_members",
           "traced_calls", "unrecognised_calls", "inert_calls",
           "measured_rev", "measured_at"]

def cell(value):
    return str(value).replace("\t", " ").replace("\n", " ")

# ---- W70: rank a view by how much of it failed to resolve ---------------------------------------
# `unresolved` sat in every capture since the sweep existed and nothing looked at it, so ALXMorph —
# 15 nodes, 15 unresolved, five hit targets, a whole player's worth of controls missing — was
# invisible until a human opened it. **The rule has to be a ratio, not a count.** The reporter's own
# control proves why: corona, the skin they called working, carries 8 unresolved on `vPlayer` against
# 66 nodes, and `unresolved > 0` is true of most views in the corpus. Against 66, 8 is noise; against
# 15, 15 is the whole view.
#
# `nodes` in the RENDER-DUMP line is `resolvedNodeCount`, so the denominator here is nodes+unresolved
# — every node the view declared — rather than `nodes`, which would divide by zero exactly where the
# defect is worst (Alienware Invader: 2 resolved, 18 unresolved).
#
# A ranked list is not a picture. A promoted view is a view worth dumping and looking at, never a
# defect on its own: `hits == 0` is correct for a view that is pure artwork.
class WMPView:
    __slots__ = ("skin", "view", "nodes", "commands", "hits", "widgets", "unresolved")

    def __init__(self, skin, view, nodes, commands, hits, widgets, unresolved):
        self.skin, self.view = skin, view
        self.nodes, self.commands = nodes, commands
        self.hits, self.widgets, self.unresolved = hits, widgets, unresolved

    @property
    def declared(self):
        return self.nodes + self.unresolved

    @property
    def ratio(self):
        return self.unresolved / self.declared if self.declared else 0.0

    # Half the nodes the view declared never got a frame. At that point the view is not degraded,
    # it is starved: what draws is a shell.
    @property
    def starved(self):
        return self.declared > 0 and self.ratio >= 0.5

    @property
    def blind(self):
        return self.hits == 0

    @property
    def silent(self):
        return self.commands == 0

class WMPHostedView:
    __slots__ = ("skin", "view", "outside", "max_delta", "differing", "total", "hosted",
                 "blit", "blit_delta")

    def __init__(self, skin, view, outside, max_delta, differing, total, hosted, blit, blit_delta):
        self.skin, self.view = skin, view
        self.outside, self.max_delta = outside, max_delta
        self.differing, self.total, self.hosted = differing, total, hosted
        self.blit, self.blit_delta = blit, blit_delta

rows = []
all_views = []
all_hosted = []
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
    views_measured = []
    appkit = []

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
            views_measured.append(WMPView(name, match.group(1), int(match.group(4)),
                                          int(match.group(5)), int(match.group(6)),
                                          int(match.group(7)), int(match.group(8))))
        elif (match := APPKIT.match(line)):
            appkit.append(WMPHostedView(name, match.group(1), int(match.group(8)),
                                        int(match.group(9)), int(match.group(4)),
                                        int(match.group(5)), int(match.group(6)),
                                        int(match.group(10)), int(match.group(11))))
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

    starved = [view for view in views_measured if view.starved]
    worst = max(views_measured, key=lambda view: (view.ratio, view.unresolved), default=None)
    all_views.extend(views_measured)
    row.update(starved_views=len(starved),
               blind_views=sum(1 for view in views_measured if view.blind),
               silent_views=sum(1 for view in views_measured if view.silent),
               worst_view=("%s:%d/%d" % (worst.view, worst.unresolved, worst.nodes)) if worst else "-",
               worst_ratio=("%.2f" % worst.ratio) if worst else "-")
    all_hosted.extend(appkit)
    worst_hosted = max(appkit, key=lambda view: (view.outside, view.max_delta), default=None)
    row.update(appkit_outside_px=sum(view.outside for view in appkit),
               appkit_max_delta=max((view.max_delta for view in appkit), default=0),
               appkit_worst_view=(worst_hosted.view if worst_hosted and worst_hosted.outside else "-"),
               appkit_blit_px=sum(view.blit for view in appkit))
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

# The promotion. A ranked file, written every run, so a starved view cannot sit in a capture
# unread the way ALXMorph's did: the census names the worst of them on stdout where the person who
# ran it is already looking.
starved_path = os.path.join(out, "starved.tsv")
ranked = sorted((view for view in all_views if view.starved or view.blind or view.silent),
                key=lambda view: (-view.ratio, -view.unresolved, view.skin.lower(), view.view))
with open(starved_path, "w") as handle:
    handle.write("\t".join(["ratio", "skin", "view", "nodes", "unresolved", "declared",
                            "commands", "hits", "widgets", "why"]) + "\n")
    for view in ranked:
        why = ",".join(word for word, flag in
                       (("starved", view.starved), ("blind", view.blind), ("silent", view.silent))
                       if flag)
        handle.write("\t".join(str(field) for field in
                                ["%.3f" % view.ratio, view.skin, view.view, view.nodes,
                                 view.unresolved, view.declared, view.commands, view.hits,
                                 view.widgets, why]) + "\n")

# The AppKit promotion. Same rule as the starvation one: written every run, worst named on stdout.
hosted_path = os.path.join(out, "appkit.tsv")
hosted_ranked = sorted((view for view in all_hosted if view.outside or view.blit),
                       key=lambda view: (-view.outside, -view.max_delta, -view.blit))
with open(hosted_path, "w") as handle:
    handle.write("\t".join(["outside_px", "max_delta", "blit_px", "blit_delta", "skin", "view",
                            "differing_px", "total_px", "hosted_widgets"]) + "\n")
    for view in hosted_ranked:
        handle.write("\t".join(str(field) for field in
                                [view.outside, view.max_delta, view.blit, view.blit_delta,
                                 view.skin, view.view, view.differing, view.total,
                                 view.hosted]) + "\n")

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
starved_views = [view for view in all_views if view.starved]
blind_views = [view for view in all_views if view.blind]
silent_views = [view for view in all_views if view.silent]
print("wmp_skin_census: %d views measured; starved(>=50%% unresolved)=%d/%d skins, "
      "hits==0=%d/%d skins, commands==0=%d/%d skins -> %s"
      % (len(all_views),
         len(starved_views), len({view.skin for view in starved_views}),
         len(blind_views), len({view.skin for view in blind_views}),
         len(silent_views), len({view.skin for view in silent_views}),
         starved_path))
if ranked:
    print("wmp_skin_census: worst views by unresolved ratio — dump these and look at them:")
    for view in ranked[:12]:
        print("  %.2f  %-34s %-16s %2d/%2d nodes resolved, %d commands, %d hits"
              % (view.ratio, view.skin, view.view, view.nodes, view.declared,
                 view.commands, view.hits))

outside_views = [view for view in all_hosted if view.outside]
print("wmp_skin_census: %d views hosted through AppKit; %d in %d skins paint outside every widget "
      "frame -> %s"
      % (len(all_hosted), len(outside_views), len({view.skin for view in outside_views}), hosted_path))
if outside_views:
    print("wmp_skin_census: AppKit overlays painting where no widget is — the W43 class:")
    for view in sorted(outside_views, key=lambda view: -view.outside)[:12]:
        print("  %7d px  delta %3d  %-34s %s"
              % (view.outside, view.max_delta, view.skin, view.view))

if damaged:
    print("wmp_skin_census: DAMAGED LOG — no populated row for:")
    for name in sorted(damaged):
        print("  " + name)
    print("  Re-run each alone: --corpus <dir holding just that archive>")
PYCENSUS

echo "wmp_skin_census: done — $out/census.tsv"
