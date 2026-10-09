#!/usr/bin/env python3
"""Re-record `Tests/NullPlayerAppTests/Fixtures/AudionFace/corpus-baseline.tsv` from a census run.

    scripts/audion_face_census.sh <out>
    scripts/audion_corpus_baseline.py <out>

The baseline is the ratchet `AudionFaceCorpusLoadTests` enforces: a face recorded `ok` that later
fails to load is a regression. Re-record only after improving the loader, never to turn a red
suite green. Rows the census could not measure (`not-run`, or no digest) are skipped.
"""
import csv, os, sys

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                    "Tests/NullPlayerAppTests/Fixtures/AudionFace/corpus-baseline.tsv")
HEADER = """\
# Load outcome per installed Audion face, keyed by the census sha256 — the ratchet for
# AudionFaceCorpusLoadTests. A face recorded `ok` that later fails is a REGRESSION and fails the
# suite. One recorded `failed` that later loads is progress: re-record. A face absent from here is
# unranked and never fails the build.
# Regenerate: scripts/audion_face_census.sh <out>, then scripts/audion_corpus_baseline.py <out>
#
# sha256\tload\tcode\tface (the name is a comment; sha256 is the key)
"""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: audion_corpus_baseline.py <census outdir>")
    census = os.path.join(sys.argv[1], "census.tsv")
    if not os.path.exists(census):
        sys.exit("no census.tsv in %s — run scripts/audion_face_census.sh first" % sys.argv[1])
    rows = [(r["sha256"], r["load"], r["code"], r["face"])
            for r in csv.DictReader(open(census, encoding="utf-8"), delimiter="\t")
            if r["load"] in ("ok", "failed") and r["sha256"] != "-"]
    rows.sort(key=lambda row: row[3].lower())
    with open(DEST, "w", encoding="utf-8") as out:
        out.write(HEADER)
        for row in rows:
            out.write("\t".join(row) + "\n")
    print("audion_corpus_baseline: %d rows -> %s" % (len(rows), os.path.normpath(DEST)))


if __name__ == "__main__":
    main()
