#!/usr/bin/env python3
"""The three W256 populations, read out of the archives rather than grepped.

    python3 scripts/wmp_slider_drag_census.py [--corpus <dir>]

`grep` calls a cp1252 `.wms` binary — about half the corpus carries a 0xA9 copyright sign in its
first line — and exits 0 having printed nothing, so every number here is taken by decoding the
archive entry. See `skills/wmp-skin-guide/reference/harness/corpus.md` § *A corpus number taken with `grep`
is not a corpus number*.

Prints, over the installed corpus minus `scripts/wmp_corpus_exclusions.txt`:

  A   elements that author a handler and no `id`, and the `value_onchange` subset of them — the
      population whose handlers used to run with no bound `value` and no element scope
  B   sliders that paint a thumb and no track, whose hit region used to be the knob
  C   archives whose `<EQUALIZERSETTINGS>` is named something other than `eq`
"""
import argparse
import os
import re
import zipfile

TAG = re.compile(rb"<\s*([A-Za-z][\w]*)((?:[^>\"']|\"[^\"]*\"|'[^']*')*)>", re.S)
ATTR = re.compile(rb"([A-Za-z_][\w:.-]*)\s*=\s*(\"[^\"]*\"|'[^']*')", re.S)
# `<CUSTOMSLIDER>` is excluded from B: its `positionImage` is the authority on its region (W150),
# which is a better answer than the frame rather than a worse one.
THUMB_SLIDERS = {b"slider", b"volumeslider", b"seekslider", b"balanceslider", b"progressbar"}
TRACK_ART = (b"image", b"backgroundimage", b"positionimage")


def definitions(archive):
    for entry in archive.namelist():
        if entry.lower().endswith(".wms"):
            try:
                yield archive.read(entry)
            except Exception:
                continue


def elements(data):
    for match in TAG.finditer(data):
        attrs = {k.lower(): v[1:-1] for k, v in ATTR.findall(match.group(2))}
        yield match.group(1).lower(), attrs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", default=os.path.expanduser(
        "~/Library/Application Support/NullPlayer/WMPSkins"))
    args = parser.parse_args()

    excluded = set()
    path = os.path.join(os.path.dirname(__file__), "wmp_corpus_exclusions.txt")
    if os.path.exists(path):
        excluded = {line.strip() for line in open(path)
                    if line.strip() and not line.startswith("#")}

    scanned = 0
    totals = {"a": [0, 0], "a_value": [0, 0], "b": [0, 0]}
    named_equalizers = {}
    for name in sorted(os.listdir(args.corpus)):
        if not name.lower().endswith(".wmz") or name in excluded:
            continue
        try:
            archive = zipfile.ZipFile(os.path.join(args.corpus, name))
        except Exception:
            continue
        scanned += 1
        counts = {"a": 0, "a_value": 0, "b": 0}
        equalizers = set()
        for data in definitions(archive):
            for tag, attrs in elements(data):
                handlers = [k for k, v in attrs.items()
                            if (k.startswith(b"on") or k.endswith(b"_onchange")) and v.strip()]
                if handlers and not attrs.get(b"id", b"").strip():
                    counts["a"] += 1
                    if b"value_onchange" in handlers:
                        counts["a_value"] += 1
                if tag in THUMB_SLIDERS and b"thumbimage" in attrs \
                        and not any(attrs.get(k, b"").strip() for k in TRACK_ART):
                    counts["b"] += 1
                if tag == b"equalizersettings":
                    authored = attrs.get(b"id", b"").decode("latin-1")
                    if authored and authored.lower() != "eq":
                        equalizers.add(authored)
        for key, count in counts.items():
            if count:
                totals[key][0] += count
                totals[key][1] += 1
        if equalizers:
            named_equalizers[name] = sorted(equalizers)

    print(f"archives scanned: {scanned}")
    print(f"A  a handler and no id:            {totals['a'][0]} nodes / {totals['a'][1]} archives")
    print(f"A' of those, value_onchange:       {totals['a_value'][0]} nodes / "
          f"{totals['a_value'][1]} archives")
    print(f"B  a thumb and no track:           {totals['b'][0]} sliders / {totals['b'][1]} archives")
    print(f"C  <EQUALIZERSETTINGS> not 'eq':   {len(named_equalizers)} archives")
    for name, ids in named_equalizers.items():
        print(f"     {name} -> {', '.join(ids)}")


if __name__ == "__main__":
    main()
