#!/usr/bin/env python3
"""Compare NullPlayer's face renders with the FaceKit oracle's, face by face.

    scripts/audion_facekit_reference.sh <oracle-out>
    scripts/audion_render_sweep.sh capture <sweep-out>
    scripts/audion_oracle_compare.py <oracle-out> <sweep-out>

Each face gets the worst verdict of its states:

  identical   every pixel equal
  rounding    no premultiplied channel off by more than 1: compositing arithmetic. Core Animation
              composites FaceKit's layers in 16-bit backing stores and NullPlayer in 8 bits; compared
              un-premultiplied, a 1-level difference at alpha 8 reads as 32 levels
  text-only   every pixel past rounding lies inside a text box the sweep drew (its `PROBE … label:`
              lines, so the loader stays the only reader of index.json): font rasterisation
  geometry    a pixel differs outside the text boxes — a defect, unless it is a listed departure
  missing     one side has no image (the oracle died, or the sweep did not render that face)

Writes <sweep-out>/oracle-compare.tsv (face, verdict, per-state pixel counts) and prints the tally
and every geometry face. See skills/audion-face-guide/reference/harness.md § *The oracle*.
"""
import argparse, os, re, sys
import numpy as np
from PIL import Image

STATES = ["stopped", "playing"]
ORDER = ["identical", "rounding", "text-only", "geometry", "missing"]
ROUNDING = 1


def label_boxes(raw):
    """Each face's label boxes from the sweep's PROBE lines, as (x, y, width, height), top-left."""
    boxes, face = {}, None
    probe = re.compile(r"PROBE \S+ label:\w+ (-?\d+),(-?\d+) (\d+)x(\d+)")
    for line in open(raw, encoding="utf-8", errors="replace"):
        if line.startswith("FACE ") and " FAILED " not in line:
            face = line[5:].rstrip("\n")
            boxes[face] = set()
        elif face and (match := probe.match(line)):
            boxes[face].add(tuple(map(int, match.groups())))
    return boxes


def text_mask(boxes, shape):
    mask = np.zeros(shape, dtype=bool)
    for x, y, width, height in boxes:
        mask[max(y, 0):max(y + height, 0), max(x, 0):max(x + width, 0)] = True
    return mask


def compare(oracle_png, ours_png, boxes):
    """(verdict, pixels past rounding, of which outside the text boxes)."""
    if not (os.path.exists(oracle_png) and os.path.exists(ours_png)):
        return "missing", 0, 0
    a, b = premultiplied(oracle_png), premultiplied(ours_png)
    if a.shape != b.shape:
        return "geometry", -1, -1
    if (a == b).all():
        return "identical", 0, 0
    differs = (np.abs(a - b) > ROUNDING).any(axis=2)
    total = int(differs.sum())
    outside = int((differs & ~text_mask(boxes, differs.shape)).sum())
    return ("rounding" if total == 0 else "text-only" if outside == 0 else "geometry"), total, outside


def premultiplied(path):
    rgba = np.asarray(Image.open(path).convert("RGBA"), dtype=np.int32)
    rgba[..., :3] = (rgba[..., :3] * rgba[..., 3:4] + 127) // 255
    return rgba


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("oracle")
    parser.add_argument("sweep")
    args = parser.parse_args()
    raw = os.path.join(args.sweep, "raw.txt")
    # A capture without PROBE lines would read every text difference as geometry.
    if not os.path.exists(raw) or not any(line.startswith("PROBE ") for line in open(raw, encoding="utf-8", errors="replace")):
        sys.exit("audion_oracle_compare: %s has no PROBE lines; recapture with scripts/audion_render_sweep.sh" % raw)
    boxes = label_boxes(raw)

    oracle_root, sweep_root = os.path.join(args.oracle, "png"), os.path.join(args.sweep, "png")
    faces = sorted(set(os.listdir(oracle_root)) | set(os.listdir(sweep_root)))
    rows, tally = [], {verdict: 0 for verdict in ORDER}
    for face in faces:
        results = [compare(os.path.join(oracle_root, face, state + ".png"),
                           os.path.join(sweep_root, face, state + ".png"),
                           boxes.get(face, ())) for state in STATES]
        verdict = max((r[0] for r in results), key=ORDER.index)
        tally[verdict] += 1
        rows.append([face, verdict] + ["%d/%d" % (r[1], r[2]) for r in results])

    with open(os.path.join(args.sweep, "oracle-compare.tsv"), "w") as out:
        out.write("face\tverdict\t" + "\t".join("%s_past_rounding/outside_text" % s for s in STATES) + "\n")
        for row in rows:
            out.write("\t".join(row) + "\n")

    same = tally["identical"] + tally["rounding"] + tally["text-only"]
    print("audion_oracle_compare: %d faces — %s" % (len(faces), ", ".join("%s %d" % (v, tally[v]) for v in ORDER)))
    print("audion_oracle_compare: geometry-identical %d/%d (%.1f%%)" % (same, len(faces), 100.0 * same / max(len(faces), 1)))
    for row in rows:
        if row[1] in ("geometry", "missing"):
            print("  %s  %r  %s" % (row[1].upper(), row[0], "  ".join(row[2:])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
