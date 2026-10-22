#!/bin/bash
#
# Rate and admit crawled Winamp Modern (`.wal`) candidates (B169, corpus-runner-plan.md §8).
#
#   scripts/wal_intake.sh <candidates> <outdir> [--admit] [--allow-dirty]
#
# Runs the census over the candidates (health) and the feature index over them and over gold+silver
# (value), then writes <outdir>/intake.tsv: every candidate's health, value, rank and the features
# it added. Two scores, never blended:
#
#   health  the census rating plus the count of distinct MAKI calls the runtime does not implement
#   value   maki-* and xml-* features the corpus does not already exercise (family/load do not count)
#
# Rank is greedy set cover on value, from the gold+silver feature union, ties to the lowest sha256,
# so intake.tsv is a pure function of (candidate sha256s, corpus sha256s, git rev). Tier:
#
#   quarantine  did not load in the census or the index (a skin the census never reached stops the run)
#   silver      the first SILVER_BUDGET of the greedy order whose gain is ≥ SILVER_MIN_GAIN
#   bronze      the rest
#
# Without --admit nothing moves. With it, every candidate is moved into
# WinampModernCorpus/<tier>/ and appended to docs/winamp-modern/corpus-manifest.tsv, taking its
# source URL and internal name from the crawler's <candidates>/manifest.tsv.

set -u -o pipefail

source "$(dirname "$0")/lib/wal_corpus.sh"
# Agreed 2026-10-19; re-open from intake.tsv's gain curve and the sweep time the batch added (§8).
readonly SILVER_BUDGET=25 SILVER_MIN_GAIN=3

usage() {
    echo "usage: wal_intake.sh <candidates> <outdir> [--admit] [--allow-dirty]" >&2
    exit 2
}

candidates="" out="" admit=0 dirty=()
while [ $# -gt 0 ]; do
    case "$1" in
        --admit) admit=1; shift ;;
        --allow-dirty) dirty=(--allow-dirty); shift ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) if [ -z "$candidates" ]; then candidates="$1"; elif [ -z "$out" ]; then out="$1"; else usage; fi; shift ;;
    esac
done
[ -n "$out" ] || usage
candidates=$(cd "$candidates" && pwd) || exit 1
mkdir -p "$out"
out=$(cd "$out" && pwd)
scripts=$(cd "$(dirname "$0")" && pwd)

"$scripts/wal_skin_census.sh" "$out/census" --corpus "$candidates" ${dirty[@]+"${dirty[@]}"} \
    && [ -s "$out/census/census.tsv" ] || { echo "wal_intake: census failed" >&2; exit 1; }
"$scripts/wal_feature_index.sh" "$out/index" --corpus "$candidates" ${dirty[@]+"${dirty[@]}"} \
    && [ -s "$out/index/features.tsv" ] || { echo "wal_intake: candidate index failed" >&2; exit 1; }
"$scripts/wal_feature_index.sh" "$out/corpus-index" ${dirty[@]+"${dirty[@]}"} \
    && [ -s "$out/corpus-index/features.tsv" ] || { echo "wal_intake: corpus index failed" >&2; exit 1; }

python3 -I - "$candidates" "$out" "$admit" "$WAL_CORPUS_ROOT" "$(git rev-parse --short HEAD)" \
    "$SILVER_BUDGET" "$SILVER_MIN_GAIN" "$(git rev-parse --show-toplevel)/docs/winamp-modern/corpus-manifest.tsv" <<'PYINTAKE'
import csv, os, shutil, sys

candidates, out, admit, root, rev, budget, min_gain, manifest = sys.argv[1:9]
admit, budget, min_gain = admit == "1", int(budget), int(min_gain)

def rows(path):
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t", quoting=csv.QUOTE_NONE))

census = {row["file"]: row for row in rows(os.path.join(out, "census", "census.tsv"))}
features, unimplemented, index_load = {}, {}, {}
for row in rows(os.path.join(out, "index", "features.tsv")):
    skin, kind = row["skin"], row["kind"]
    features.setdefault(skin, set())
    if kind == "load":
        index_load[skin] = row["feature"]
    elif kind.startswith(("maki-", "xml-")):
        features[skin].add(f"{kind}:{row['feature']}")
        if kind == "maki-call" and row["implemented"] == "no":
            unimplemented.setdefault(skin, set()).add(row["feature"])
covered = {f"{row['kind']}:{row['feature']}" for row in rows(os.path.join(out, "corpus-index", "features.tsv"))
           if row["kind"].startswith(("maki-", "xml-"))}

missing = sorted(set(census) ^ set(index_load))
if missing:
    sys.exit(f"wal_intake: census and index disagree on the candidate set: {', '.join(missing[:10])}")

# A skin the render pass never reached means the pass crashed or was cut short, not a verdict on it.
not_run = sorted(name for name, row in census.items() if row["load"] == "not-run")
if not_run:
    sys.exit(f"wal_intake: the census never reached {len(not_run)} skins, from {not_run[0]}; "
             "move a crashing skin to quarantine by hand and re-run")

quarantined = {name for name, row in census.items()
               if row["load"] != "ok" or index_load[name] != "ok"}

# Greedy set cover. ponytail: recomputes every gain per pick, O(n²·f); ~1 s at 900 candidates.
order, pool = [], sorted(set(census) - quarantined, key=lambda name: census[name]["sha256"])
while pool:
    best = max(pool, key=lambda name: len(features[name] - covered))  # first max = lowest sha256
    added = sorted(features[best] - covered)
    order.append((best, added))
    covered |= features[best]
    pool.remove(best)

tier, rank, gain = {}, {}, {}
for position, (name, added) in enumerate(order, 1):
    rank[name], gain[name] = position, added
    tier[name] = "silver" if position <= budget and len(added) >= min_gain else "bronze"
for name in quarantined:
    tier[name], rank[name], gain[name] = "quarantine", "-", []

ordered = [name for name, _ in order] + sorted(quarantined, key=lambda name: census[name]["sha256"])
with open(os.path.join(out, "intake.tsv"), "w") as handle:
    handle.write("rank\tfile\tsha256\ttier\tload\trating\tunimplemented\tfeatures\tgain\tadded\n")
    for name in ordered:
        row = census[name]
        load = row["load"] if row["load"] != "ok" else index_load[name]
        handle.write("\t".join(str(v) for v in (
            rank[name], name, row["sha256"], tier[name], load, row["rating"],
            len(unimplemented.get(name, ())), len(features[name]), len(gain[name]),
            ",".join(gain[name][:40]).replace("\t", " ") or "-")) + "\n")

tally = {t: sum(1 for v in tier.values() if v == t) for t in ("silver", "bronze", "quarantine")}
curve = [len(added) for _, added in order[:60]]
print(f"wal_intake: {len(census)} candidates -> {out}/intake.tsv; " + ", ".join(f"{k}={v}" for k, v in tally.items()))
print(f"wal_intake: gain curve (first 60) {' '.join(map(str, curve))}")

if not admit:
    sys.exit(0)

crawl = {}
for line in open(os.path.join(candidates, "manifest.tsv"), errors="replace"):
    fields = line.rstrip("\n").split("\t")
    if len(fields) >= 3:
        crawl[fields[0]] = (fields[2] or "-", fields[1].replace("\t", " ") or "-")
existing = {line.split("\t", 1)[0] for line in open(manifest)}
clash = [name for name in ordered if name in existing]
if clash:
    sys.exit(f"wal_intake: already in the manifest, nothing moved: {', '.join(clash[:10])}")
with open(manifest, "a") as handle:
    for name in ordered:
        os.makedirs(os.path.join(root, tier[name]), exist_ok=True)
        destination = os.path.join(root, tier[name], name)
        if os.path.exists(destination):
            sys.exit(f"wal_intake: {destination} exists; stopped part-way, see the manifest tail")
        shutil.move(os.path.join(candidates, name), destination)
        url, internal = crawl.get(name, ("-", "-"))
        handle.write("\t".join((name, census[name]["sha256"], tier[name], url, internal, rev)) + "\n")
print(f"wal_intake: admitted {len(ordered)} into {root} and {manifest}")
PYINTAKE
