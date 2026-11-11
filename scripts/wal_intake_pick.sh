#!/bin/bash
#
# Admit the next intake batch without a crawl (skills/skin-intake § Admit):
#
#   scripts/wal_intake_pick.sh [count]     # default 25
#
# Takes the first <count> skins still bronze in the newest intakes/intake-*.ranking.tsv, in its rank
# order, moves each into WinampModernCorpus/silver/, re-tiers its manifest row (tier silver, rev
# HEAD), copies it into WinampModernSkins/ so it is in the skin menu, and writes the next ledger
# intakes/intake-<n>.tsv with every row at `admitted`. Why no crawl: by intake #6 the greedy order's
# gain was 2 or less for every remaining candidate and no crawl had quarantined a skin (plan §8).
# A new crawl of new candidates still goes through wal_intake.sh, which writes a fresh ranking.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/wal_corpus.sh

count=${1:-25}
dir=docs/winamp-modern/intakes
last=$(ls "$dir" | sed -n 's/^intake-\([0-9]*\)\.tsv$/\1/p' | sort -n | tail -1)
ranking=$(ls "$dir" | sed -n 's/^intake-\([0-9]*\)\.ranking\.tsv$/\1/p' | sort -n | tail -1)
[ -n "$ranking" ] || { echo "no ranking in $dir" >&2; exit 1; }
n=$((last + 1))

python3 -I - "$dir/intake-$ranking.ranking.tsv" docs/winamp-modern/corpus-manifest.tsv \
    "$WAL_CORPUS_ROOT" "$(dirname "$WAL_CORPUS_ROOT")/WinampModernSkins" "$dir/intake-$n.tsv" \
    "$count" "$(git rev-parse --short HEAD)" "$(date +%F)" <<'PY'
import os, shutil, sys

ranking, manifest, root, skins, ledger, count, rev, today = sys.argv[1:9]
if not count.isdigit() or not 1 <= int(count) <= 50:
    sys.exit(f"wal_intake_pick: count must be 1-50, got {count}")
rows = [line.split("\t") for line in open(manifest).read().splitlines()]
at = {fields[0]: i for i, fields in enumerate(rows)}
order = [line.split("\t")[1] for line in open(ranking).read().splitlines()[1:]]
picks = [name for name in order if name in at and rows[at[name]][2] == "bronze"][:int(count)]
if not picks:
    sys.exit("wal_intake_pick: no bronze left in the ranking; crawl with wal_intake.sh")
if os.path.exists(ledger):
    sys.exit(f"wal_intake_pick: {ledger} exists")
moves = [(os.path.join(root, "bronze", name), os.path.join(root, "silver", name), os.path.join(skins, name))
         for name in picks]
for source, destination, _ in moves:
    if not os.path.exists(source):
        sys.exit(f"wal_intake_pick: {source} is missing; nothing moved")
    if os.path.exists(destination):
        sys.exit(f"wal_intake_pick: {destination} exists; nothing moved")
os.makedirs(os.path.join(root, "silver"), exist_ok=True)
os.makedirs(skins, exist_ok=True)
done = []
try:
    for source, destination, copy in moves:
        shutil.move(source, destination)
        installed = os.path.exists(copy)
        done.append((source, destination, copy, installed))
        shutil.copy2(destination, copy)
except BaseException:
    # Put every skin already moved back, so a failure strands none of them without a ledger. A
    # skin-menu copy that was there before this run stays.
    for source, destination, copy, installed in reversed(done):
        if not installed and os.path.exists(copy):
            os.remove(copy)
        shutil.move(destination, source)
    raise
for name in picks:
    rows[at[name]][2], rows[at[name]][5] = "silver", rev
with open(ledger, "w") as handle:
    handle.write("file\tsha256\tstage\tupdated\trows\tnote\n")
    for name in picks:
        handle.write(f"{name}\t{rows[at[name]][1]}\tadmitted\t{today}\t-\t-\n")
with open(manifest, "w") as handle:
    handle.write("".join("\t".join(fields) + "\n" for fields in rows))
print(f"wal_intake_pick: admitted {len(picks)} into {ledger}: {', '.join(picks)}")
PY
