#!/usr/bin/env python3
"""Re-record `Tests/NullPlayerAppTests/Fixtures/WMPSkin/corpus-baseline.tsv` from a census run.

    scripts/wmp_skin_census.sh /tmp/wmp/census
    scripts/wmp_corpus_baseline.py /tmp/wmp/census

The baseline is the ratchet `WMPCorpusLoadTests` enforces: an archive recorded `ok` that later
fails is a regression. Re-record only when you have *improved* the loader — never to make a red
suite go green, which is the whole failure this file exists to prevent.

Rows whose census block was `damaged` or `not-run` are skipped: an interleaved log is not evidence
about a skin, and recording a guess as a baseline is worse than having no row at all.
"""
import csv, os, sys
from collections import Counter

CORPUS = os.path.expanduser("~/Library/Application Support/NullPlayer/WMPSkins")
DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                    "Tests/NullPlayerAppTests/Fixtures/WMPSkin/corpus-baseline.tsv")
HEADER = """\
# Load outcome per installed `.wmz`, keyed by sha256 — the ratchet for WMPCorpusLoadTests.
# An archive recorded `ok` that later fails is a REGRESSION and fails the suite.
# An archive recorded `failed` that later loads is progress: the suite passes and asks
# you to re-record this file. An archive absent from here is unranked and never fails
# the build — a corpus is personal and grows, and a newly downloaded broken skin is a
# backlog item, not a broken build.
# Regenerate: scripts/wmp_skin_census.sh <out>, then scripts/wmp_corpus_baseline.py <out>
#
# sha256\tload\treject_codes\tfile (name is a comment; sha256 is the key)
"""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: wmp_corpus_baseline.py <census outdir>")
    census = os.path.join(sys.argv[1], "census.tsv")
    if not os.path.exists(census):
        sys.exit("no census.tsv in %s — run scripts/wmp_skin_census.sh first" % sys.argv[1])

    rows = []
    skipped = Counter()
    for row in csv.DictReader(open(census), delimiter="\t"):
        if row["load"] not in ("ok", "failed"):
            skipped[row["load"]] += 1
            continue
        # An archive the census saw but that is no longer installed keeps no row.
        if not os.path.exists(os.path.join(CORPUS, row["file"])):
            skipped["uninstalled"] += 1
            continue
        rows.append((row["sha256"], row["load"],
                     row["reject_codes"] if row["load"] == "failed" else "-", row["file"]))
    rows.sort(key=lambda item: item[3].lower())

    with open(DEST, "w") as handle:
        handle.write(HEADER)
        for row in rows:
            handle.write("\t".join(row) + "\n")

    tally = Counter(row[1] for row in rows)
    print("wmp_corpus_baseline: %d rows -> %s" % (len(rows), os.path.normpath(DEST)))
    print("wmp_corpus_baseline: " + ", ".join("%s=%d" % kv for kv in sorted(tally.items())))
    if skipped:
        print("wmp_corpus_baseline: skipped " + ", ".join("%s=%d" % kv for kv in sorted(skipped.items()))
              + " (no row recorded — re-run those alone with --corpus)")


if __name__ == "__main__":
    main()
