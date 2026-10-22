#!/bin/bash
#
# S3 motion sweep of the Winamp Modern (`.wal`) corpus (corpus-runner-plan.md §3 S3, §7 step 4).
# Does what a skin declares as moving actually move, at rest?
#
#   scripts/wal_motion_sweep.sh <outdir> [--corpus <dir[:dir…]>] [--shards K] [--allow-dirty]
#
# Output: <outdir>/motion.tsv, one row per (skin, container, opening layout), and a summary on
# stdout. Columns and their reading are in
# skills/winamp-modern-skin-guide/reference/harness.md § "The motion sweep".
#
# Every skin costs ~4 s of wall time (the ladder ends at t = 4 s), so pass --shards = cores.
# A run is a build, like wal_render_sweep.sh: it refuses a dirty tree without --allow-dirty, and
# fails if any archive is missing its rows.

set -u -o pipefail

source "$(dirname "$0")/lib/swiftpm.sh"
source "$(dirname "$0")/lib/wal_corpus.sh"

usage() {
    echo "usage: wal_motion_sweep.sh <outdir> [--corpus <dir[:dir…]>] [--shards K] [--allow-dirty]" >&2
    exit 2
}

out="" corpus="$WAL_CORPUS_DEFAULT" allow_dirty=0 shards=1
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --corpus) corpus="${2:-}"; shift 2 ;;
        --shards) shards="${2:-}"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -n "$out" ] && usage; out="$1"; shift ;;
    esac
done
[ -n "$out" ] || usage
[[ "$shards" =~ ^[1-9][0-9]*$ ]] || { echo "wal_motion_sweep: --shards takes a positive count" >&2; usage; }

list=$(wal_corpus_archives "$corpus") || exit 1
archives=$(printf '%s' "$list" | grep -c .)
[ "$archives" -gt 0 ] || { echo "wal_motion_sweep: no .wal archives in $corpus" >&2; exit 1; }

wal_require_clean_tree wal_motion_sweep "$allow_dirty" || exit 1

mkdir -p "$out"
out=$(cd "$out" && pwd)
rm -f "$out"/motion-*.tsv "$out"/raw-*.txt
[ "$shards" -gt "$archives" ] && shards=$archives
echo "wal_motion_sweep: $archives archives in $shards shard(s) -> $out (rev $(git rev-parse --short HEAD 2>/dev/null || echo unknown))"
wal_build_tests wal_motion_sweep "$out" || exit 1

run_shard() {
    WINAMP_MODERN_MOTION_SWEEP="$2" \
    WINAMP_MODERN_MOTION_SWEEP_OUT="$out/motion-$1.tsv" \
        xcrun xctest -XCTest NullPlayerAppTests.WinampModernMotionSweepTests "$3" > "$out/raw-$1.txt" 2>&1
}
status=0
wal_run_shards "$shards" "$list" run_shard || status=$?
[ "$status" -eq 0 ] || echo "wal_motion_sweep: a shard exited $status; read $out/raw-*.txt before trusting the result" >&2

python3 -I - "$out" "$list" <<'PYMOTION'
import glob, os, sys

out, archives = sys.argv[1], {os.path.basename(p) for p in sys.argv[2].splitlines() if p}
COLUMNS = ["skin", "container", "layout", "open", "frames", "verdict", "animatedlayers", "autoplay",
           "timer", "suspect", "moved", "anim", "still"]
rows = []
for path in sorted(glob.glob(os.path.join(out, "motion-*.tsv"))):
    rows += [line.rstrip("\n").split("\t") for line in open(path, errors="replace") if line.strip()]
missing = sorted(archives - {row[0] for row in rows}, key=str.lower)
if missing:
    sys.exit(f"wal_motion_sweep: {len(missing)} archives have no rows (a shard crashed?): " + ", ".join(missing[:10]))
rows.sort(key=lambda row: (row[0].lower(), row[0], row[1].lower(), row[2]))
with open(os.path.join(out, "motion.tsv"), "w") as handle:
    handle.write("\t".join(COLUMNS) + "\n")
    handle.writelines("\t".join(row) + "\n" for row in rows)

by_skin = {}
for row in rows:
    by_skin.setdefault(row[0], []).append(dict(zip(COLUMNS, row)))
failed = [s for s, r in by_skin.items() if r[0]["verdict"] == "failed"]
counts = {}
for row in rows:
    counts[row[5]] = counts.get(row[5], 0) + 1
# The plan's suspect rule (corpus-runner-plan.md §3 S3): the skin declares an animatedlayer, an
# autoplay or a script Timer, and its pixels are byte-identical across the ladder in every window.
still = sorted((s for s, r in by_skin.items() if s not in failed
                and all(x["verdict"] == "static" for x in r)
                and (r[0]["timer"] == "yes" or any(x["animatedlayers"] != "0" or x["autoplay"] != "0" for x in r))),
               key=str.lower)
# The S4 impact score for motion (§3 S4): still animated layers / animated layers, per skin.
with open(os.path.join(out, "impact.tsv"), "w") as handle:
    handle.write("skin\tanimated\tstill\tsuspect\n")
    for skin in sorted(by_skin, key=str.lower):
        if skin in failed:
            continue
        animated = sum(int(x["animatedlayers"]) for x in by_skin[skin])
        handle.write(f"{skin}\t{animated}\t{sum(int(x['still']) for x in by_skin[skin])}\t{int(skin in still)}\n")
layouts = [r for r in rows if r[9] == "1"]
causes = {}
for row in rows:
    for item in row[11].split(","):
        if "=" in item:
            cause = item.rsplit("=", 1)[1]
            causes[cause] = causes.get(cause, 0) + 1
# The S4 motion-dead ranking (§3 S4): one row per plan cause (§3 S3), counted over suspect skins.
# priority = skins × severity × visibility ÷ cost. Motion-dead is 4th of 5 on the ladder: weight 2.
# Visibility 3 when the cause sits in an open window at rest, else 2. Cost 1: the plan tunes it by
# hand afterwards, and nothing measured here estimates it. `hidden` is never drawn at all, which is
# coverage (§7 step 5b), not motion.
CAUSES = {"never-played": "never played", "not-repainted": "played but not repainted",
          "stuck": "played but drawn at one frame", "one-frame": "played but drawn at one frame"}
ranked = {}
for skin in still:
    for x in by_skin[skin]:
        for item in x["anim"].split(","):
            cause = item.rsplit("=", 1)[-1] if "=" in item else None
            if cause in CAUSES:
                entry = ranked.setdefault(CAUSES[cause], {"skins": set(), "open": set()})
                entry["skins"].add(skin)
                if x["open"] == "1":
                    entry["open"].add(skin)
timer_only = [s for s in still if all(x["animatedlayers"] == "0" for x in by_skin[s])]
ranked["Timer declared, no animated layer, nothing moved"] = {"skins": set(timer_only),
    "open": {s for s in timer_only if any(x["open"] == "1" for x in by_skin[s])}}
with open(os.path.join(out, "ranking.tsv"), "w") as handle:
    handle.write("priority\tcause\tskins\tseverity\tvisibility\tcost\tsamples\n")
    lines = []
    for cause, entry in ranked.items():
        visibility = 3 if entry["open"] else 2
        skins = len(entry["skins"])
        lines.append((skins * 2 * visibility, cause, skins, visibility,
                      ", ".join(sorted(entry["skins"], key=str.lower)[:3])))
    for priority, cause, skins, visibility, samples in sorted(lines, key=lambda l: (-l[0], l[1])):
        handle.write(f"{priority}\t{cause}\t{skins}\t2\t{visibility}\t1\t{samples}\n")

print(f"wal_motion_sweep: {len(rows)} layouts over {len(by_skin)} skins -> {out}/motion.tsv; "
      + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
print("  animatedlayers: " + (", ".join(f"{k} {v}" for k, v in sorted(causes.items())) or "none"))
print(f"  suspect layouts (animatedlayer declared, static): {len(layouts)}")
print(f"  suspect skins (animatedlayer, autoplay or Timer declared, nothing moved): {len(still)} -> {out}/impact.tsv")
for skin in still:
    print("    " + skin)
PYMOTION
