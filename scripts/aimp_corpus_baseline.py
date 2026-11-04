#!/usr/bin/env python3
"""Re-record `Tests/NullPlayerAppTests/Fixtures/AIMPSkin/corpus-baseline.tsv` from a census run.

    scripts/aimp_skin_census.sh /tmp/aimp/census
    scripts/aimp_corpus_baseline.py /tmp/aimp/census

The baseline is the ratchet `AIMPCorpusLoadTests` enforces: a skin recorded `ok` that later fails,
or whose scripts that run fall below the recorded count, is a regression. Re-record only when you
have *improved* the engine, never to make a red suite green, which is the failure this file exists
to prevent.
"""
import csv
import os
import sys

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                    "Tests/NullPlayerAppTests/Fixtures/AIMPSkin/corpus-baseline.tsv")
HEADER = """\
# Load outcome and script coverage per installed AIMP skin, keyed by sha256: the ratchet for
# AIMPCorpusLoadTests. A skin recorded `ok` that later fails, or runs fewer of its scripts, is a
# REGRESSION and fails the suite. A skin recorded `failed` that later loads is progress: the suite
# passes and asks you to re-record. A skin absent from here is unranked and never fails the build:
# a corpus is personal and grows.
# Regenerate: scripts/aimp_skin_census.sh <out>, then scripts/aimp_corpus_baseline.py <out>
#
# sha256\toutcome\tcodes\tscripts_ran\tscripts\tfile (the name is a comment; sha256 is the key)
"""


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    census = os.path.join(sys.argv[1], "census.tsv")
    with open(census, newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if not rows:
        sys.exit(f"{census} has no rows")
    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    with open(DEST, "w") as out:
        out.write(HEADER)
        for row in sorted(rows, key=lambda r: r["file"].lower()):
            out.write("\t".join([row["sha256"], row["outcome"], row["codes"], row["scripts_ran"],
                                 row["scripts"], row["file"]]) + "\n")
    ok = sum(1 for r in rows if r["outcome"] == "ok")
    print(f"recorded {len(rows)} skin(s), {ok} ok -> {os.path.normpath(DEST)}")


if __name__ == "__main__":
    main()
