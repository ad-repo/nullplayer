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
# With no bronze left in the ranking it adopts the skins already in silver instead (the B167 seed set,
# skins held back from an earlier batch): they stay where they are and only join the skin menu.
# Refuses while the newest ledger has a skin short of `promoted`: one batch is open at a time.

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
    "$count" "$(git rev-parse --short HEAD)" "$(date +%F)" "$dir/intake-$last.tsv" <<'PY'
import os, shutil, sys

ranking, manifest, root, skins, ledger, count, rev, today, previous = sys.argv[1:10]
if not count.isdigit() or not 1 <= int(count) <= 200:
    sys.exit(f"wal_intake_pick: count must be 1-200, got {count}")
if os.path.exists(previous):
    open_rows = [line.split("\t")[0] for line in open(previous).read().splitlines()[1:]
                 if line.split("\t")[2] != "promoted"]
    if open_rows:
        sys.exit(f"wal_intake_pick: {previous} is still open ({len(open_rows)} not promoted)")
rows = [line.split("\t") for line in open(manifest).read().splitlines()]
at = {fields[0]: i for i, fields in enumerate(rows)}
order = [line.split("\t")[1] for line in open(ranking).read().splitlines()[1:]]
picks = [name for name in order if name in at and rows[at[name]][2] == "bronze"][:int(count)]
if os.path.exists(ledger):
    sys.exit(f"wal_intake_pick: {ledger} exists")


def write_ledger(names):
    with open(ledger, "w") as handle:
        handle.write("file\tsha256\tstage\tupdated\trows\tnote\n")
        for name in names:
            handle.write(f"{name}\t{rows[at[name]][1]}\tadmitted\t{today}\t-\t-\n")


if not picks:
    # Already in silver/ and already tiered: they only join the skin menu.
    picks = sorted(fields[0] for fields in rows[1:] if fields[2] == "silver")[:int(count)]
    if not picks:
        sys.exit("wal_intake_pick: no bronze or silver left; crawl with wal_intake.sh")
    for name in picks:
        if not os.path.exists(os.path.join(root, "silver", name)):
            sys.exit(f"wal_intake_pick: {os.path.join(root, 'silver', name)} is missing; nothing copied")
    os.makedirs(skins, exist_ok=True)
    for name in picks:
        shutil.copy2(os.path.join(root, "silver", name), os.path.join(skins, name))
    write_ledger(picks)
    print(f"wal_intake_pick: adopted {len(picks)} from silver into {ledger}: {', '.join(picks)}")
    sys.exit(0)
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
write_ledger(picks)
with open(manifest, "w") as handle:
    handle.write("".join("\t".join(fields) + "\n" for fields in rows))
print(f"wal_intake_pick: admitted {len(picks)} into {ledger}: {', '.join(picks)}")
PY
