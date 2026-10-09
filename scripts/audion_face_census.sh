#!/bin/bash
#
# Structural census of the installed Audion face corpus.
#
#   scripts/audion_face_census.sh <outdir> [--corpus <dir>] [--allow-dirty]
#
# One census.tsv row per face: the harness's DIGEST of its files, whether it loaded and the fatal code if
# not, its size and mask, its warnings by code, which elements survived, and what each of the six
# files FaceKit ignores holds (window.png, drag.png, inactive.png, active-alpha.png, about.png,
# icon.png). Prints the measured count and the tallies; it never asserts a fixed count, because the
# corpus moves. scripts/audion_corpus_baseline.py re-records the load ratchet from census.tsv.
# The numbers and what they settled are in skills/audion-face-guide/reference/harness.md.

set -u -o pipefail
source "$(dirname "$0")/lib/swiftpm.sh"
source "$(dirname "$0")/lib/audion_corpus.sh"

out="" corpus="$AUDION_CORPUS_DEFAULT" allow_dirty=0
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "usage: audion_face_census.sh <outdir> [--corpus <dir>] [--allow-dirty]" >&2; exit 2 ;;
        *) out="$1"; shift ;;
    esac
done
[ -n "$out" ] || { echo "usage: audion_face_census.sh <outdir> [--corpus <dir>] [--allow-dirty]" >&2; exit 2; }
[ -d "$corpus" ] || { echo "audion_face_census: no corpus at $corpus" >&2; exit 1; }
audion_require_clean_tree audion_face_census "$allow_dirty"

mkdir -p "$out"
echo "audion_face_census started $(date '+%F %T') — not finished" > "$out/INCOMPLETE"
faces=$(audion_face_list "$corpus" "$out/faces.txt" audion_face_census)
[ "$faces" -gt 0 ] || { echo "audion_face_census: no faces in $corpus" >&2; exit 1; }
echo "audion_face_census: measuring $faces faces"
AUDION_FACE="$out/faces.txt" \
    swift test ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} --filter AudionFaceRenderDumpTests/testSweepsFaceOrCorpus \
    > "$out/raw.txt" 2> "$out/stderr.txt"

python3 - "$out" "$(git rev-parse --short HEAD)" <<'PY' || exit 1
import collections, os, re, sys
import numpy as np
from PIL import Image

out, rev = sys.argv[1], sys.argv[2]
folders = [line.rstrip("\n") for line in open(os.path.join(out, "faces.txt"), encoding="utf-8")]

# The harness's lines, per face block.
blocks, face = {}, None
for line in open(os.path.join(out, "raw.txt"), encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("FACE "):
        name = line[5:]
        failed = re.match(r"(.*) FAILED (.*)", name)
        if failed:
            code = re.match(r"\[(AUD\d{4})\]", failed.group(2))
            blocks[failed.group(1)]["failed"] = code.group(1) if code else "untyped"
        else:
            face = name
            blocks[face] = {"failed": None, "findings": collections.Counter(), "sha256": "-"}
    elif face and line.startswith("DIGEST "):
        # `DIGEST FAILED <why>` leaves "-", which the baseline skips.
        if re.fullmatch(r"[0-9a-f]{64}", line[7:]):
            blocks[face]["sha256"] = line[7:]
    elif face and line.startswith("LOAD "):
        blocks[face].update(kv.split("=", 1) for kv in line[5:].split() if not kv.startswith("findings="))
    elif face and line.startswith("FINDING "):
        code = re.match(r"FINDING \[(AUD\d{4})\]", line)
        blocks[face]["findings"][code.group(1) if code else "untyped"] += 1
    elif face and line.startswith("ELEMENTS "):
        for kv in line[9:].split():
            key, value = kv.split("=", 1)
            blocks[face][key] = 0 if value == "-" else len(value.split(","))

def headroom(folder):
    """The locked limits' inputs, over every file (AUD0003, AUD0004, AUD0005, AUD0011). Images are
    taken over every PNG, not only those the loader decodes, so they overstate the decode."""
    row = {"index_bytes": os.path.getsize(os.path.join(folder, "index.json")), "entries": 0, "bytes": 0,
           "max_side": 0, "max_png_bytes": 0, "png_pixels": 0}
    for root, dirs, names in os.walk(folder):
        row["entries"] += len(dirs) + len(names)
        for name in names:
            path = os.path.join(root, name)
            size = os.path.getsize(path)
            row["bytes"] += size
            with open(path, "rb") as handle:
                header = handle.read(24)
            if header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR":
                width, height = int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")
                row["max_side"] = max(row["max_side"], width, height)
                row["max_png_bytes"] = max(row["max_png_bytes"], size)
                row["png_pixels"] += width * height
    return row

def rgba(folder, name):
    path = os.path.join(folder, name)
    return np.asarray(Image.open(path).convert("RGBA")) if os.path.exists(path) else None

def region(image):
    """window.png and drag.png are opaque black-on-white: the region is the dark pixels."""
    return image[..., :3].max(axis=2) < 128

def ignored(folder):
    """What each file FaceKit ignores holds, measured against base.png and base-alpha.png."""
    base, mask = rgba(folder, "base.png"), rgba(folder, "base-alpha.png")
    shape = base.shape[:2]
    shaped = mask[..., 3] > 0 if mask is not None and mask.shape[:2] == shape else None
    window, drag = rgba(folder, "window.png"), rgba(folder, "drag.png")
    inactive, active = rgba(folder, "inactive.png"), rgba(folder, "active-alpha.png")
    about, icon = rgba(folder, "about.png"), rgba(folder, "icon.png")
    row = {}
    def iou(a, b):
        return "%.3f" % ((a & b).sum() / max((a | b).sum(), 1))
    win = region(window) if window is not None and window.shape[:2] == shape else None
    row["window_vs_mask_iou"] = "-" if window is None else "size" if win is None else "nomask" if shaped is None else iou(win, shaped)
    if drag is None:
        row["drag_in_window"] = "-"
    elif drag.shape[:2] != shape or win is None:
        row["drag_in_window"] = "size"
    else:
        dr = region(drag)
        row["drag_in_window"] = "%.3f/%.3f" % ((dr & win).sum() / max(dr.sum(), 1), dr.sum() / max(win.sum(), 1))
    if inactive is None:
        row["inactive_vs_base"] = "-"
    elif inactive.shape[:2] != shape:
        row["inactive_vs_base"] = "size"
    else:
        # The share of base.png's visible pixels it repaints by more than 8 levels; inactive.png is
        # opaque everywhere, so pixels the base leaves transparent carry no meaning.
        changed = (np.abs(inactive[..., :3].astype(int) - base[..., :3].astype(int)) > 8).any(axis=2)
        row["inactive_vs_base"] = "%.3f" % changed[base[..., 3] > 0].mean()
    if active is None:
        row["active_alpha"] = "-"
    else:
        row["active_alpha"] = "nomask" if mask is None else "size" if active.shape != mask.shape \
            else "same" if (active[..., 3] == mask[..., 3]).all() else "differs"
    row["about"] = "-" if about is None else "%dx%d" % (about.shape[1], about.shape[0])
    row["icon"] = "-" if icon is None else "%dx%d" % (icon.shape[1], icon.shape[0])
    return row

columns = ["face", "sha256", "load", "code", "size", "mask", "inactiveMask", "findings", "buttons",
           "indicators", "digits", "animations", "text", "window_vs_mask_iou", "drag_in_window",
           "inactive_vs_base", "active_alpha", "about", "icon", "index_bytes", "entries", "bytes", "max_side",
           "max_png_bytes", "png_pixels", "rev"]
rows, loads, fatal, warnings = [], collections.Counter(), collections.Counter(), collections.Counter()
for folder in folders:
    name = os.path.basename(folder)
    block = blocks.get(name)
    row = {"face": name, "sha256": block["sha256"] if block else "-", "rev": rev, **headroom(folder)}
    if block is None:
        row["load"] = "not-run"
    elif block["failed"]:
        row.update(load="failed", code=block["failed"])
        fatal[block["failed"]] += 1
    else:
        row.update(load="ok", code="-", **{k: block.get(k, "-") for k in
                   ("size", "mask", "inactiveMask", "buttons", "indicators", "digits", "animations", "text")})
        row["findings"] = ",".join("%s=%d" % kv for kv in sorted(block["findings"].items())) or "-"
        warnings.update(block["findings"])
        row.update(ignored(folder))
    loads[row["load"]] += 1
    rows.append(row)

with open(os.path.join(out, "census.tsv"), "w", encoding="utf-8") as tsv:
    tsv.write("\t".join(columns) + "\n")
    for row in rows:
        tsv.write("\t".join(str(row.get(c, "-")) for c in columns) + "\n")

print("audion_face_census: %d faces — %s" % (len(rows), ", ".join("%s %d" % kv for kv in sorted(loads.items()))))
print("audion_face_census: fatal by code — %s" % (", ".join("%s %d" % kv for kv in sorted(fatal.items())) or "none"))
print("audion_face_census: warnings by code — %s" % (", ".join("%s %d" % kv for kv in sorted(warnings.items())) or "none"))
loaded = [r for r in rows if r["load"] == "ok"]
def tally(key, buckets):
    counts = collections.Counter()
    for r in loaded:
        value = r[key]
        counts["absent" if value == "-" else value if value in ("size", "nomask", "same", "differs") else buckets(value)] += 1
    print("audion_face_census: %s — %s" % (key, ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
tally("window_vs_mask_iou", lambda v: ">=0.95" if float(v) >= 0.95 else "<0.95")
tally("drag_in_window", lambda v: ("inside" if float(v.split("/")[0]) >= 0.99 else "outside")
      + (" smaller" if float(v.split("/")[1]) < 0.99 else " whole"))
tally("inactive_vs_base", lambda v: "same" if float(v) == 0 else "<5%" if float(v) < 0.05 else ">=5%")
tally("active_alpha", str)
tally("about", lambda v: "present")
tally("icon", str)
for key, limit in (("index_bytes", "AUD0003 256 KiB"), ("max_side", "AUD0004 4096 px"),
                   ("max_png_bytes", "AUD0004 8 MiB"), ("entries", "AUD0005 2,000"), ("bytes", "AUD0005 64 MiB"),
                   ("png_pixels", "AUD0011 64 Mpx")):
    top = max(rows, key=lambda r: r[key])
    print("audion_face_census: headroom %s — max %d (%r) against %s" % (key, top[key], top["face"], limit))
pixels = sorted(r["png_pixels"] for r in rows)
print("audion_face_census: median png_pixels %d" % pixels[len(pixels) // 2])
if loads["not-run"]:
    print("audion_face_census: %d face(s) have no harness block — the run died; see raw.txt and stderr.txt" % loads["not-run"])
    sys.exit(1)
PY
rm -f "$out/INCOMPLETE"
echo "audion_face_census: done — $out/census.tsv"
