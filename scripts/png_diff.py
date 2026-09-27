#!/usr/bin/env python3
"""Compare two PNGs, or two trees of them, and say which way each one changed.

  scripts/png_diff.py <a.png> <b.png>
  scripts/png_diff.py <base-dir> <curr-dir> [--summary] [--top N]

Every differing pair gets a class, so a large diff is read by its short list rather than one image
at a time:

  lsb        maxdelta <= 1 — rounding, not a change (a human still reads the number)
  recolour   the alpha band is identical — same silhouette, different colour
  moved      same drawn-pixel count, alpha changed — content moved or reshaped
  gained     more drawn pixels (alpha > 8) than before
  lost       fewer drawn pixels than before — the list worth opening first
  size       the canvas changed size

Why a script: an ad-hoc Pillow comparison is wrong in a way that says "identical". Since Pillow 9.5
`getbbox()` on an RGBA image — including a *difference* image — considers the alpha band alone, so a
colour-only change reports no bbox (the Phase 5 sweep: 3 changed where there were 198). This splits
the bands and never asks alpha alone. Sorting by drawn-pixel direction is what turned that sweep's
198 changed images into a one-skin list of lost or gained content.
"""
import argparse, os, sys
from collections import Counter, defaultdict
from PIL import Image, ImageChops

CLASS_ORDER = ['lost', 'gained', 'size', 'moved', 'recolour', 'lsb']


def drawn(alpha):
    return sum(alpha.histogram()[9:])


def compare(pa, pb):
    """None if identical, else a dict describing the change."""
    with Image.open(pa) as ia, Image.open(pb) as ib:
        ia, ib = ia.convert('RGBA'), ib.convert('RGBA')
        if ia.size != ib.size:
            return {'class': 'size', 'detail': '%s -> %s' % (ia.size, ib.size)}
        bands = ImageChops.difference(ia, ib).split()
        boxes = [b.getbbox() for b in bands]          # per band: never alpha alone
        if not any(boxes):
            return None
        maxdelta = max(b.getextrema()[1] for b in bands)
        mask = bands[0]
        for b in bands[1:]:
            mask = ImageChops.lighter(mask, b)
        changed = sum(mask.histogram()[1:])
        xs = [b for b in boxes if b]
        bbox = (min(b[0] for b in xs), min(b[1] for b in xs), max(b[2] for b in xs), max(b[3] for b in xs))
        da, db = drawn(ia.getchannel('A')), drawn(ib.getchannel('A'))
        if maxdelta <= 1: cls = 'lsb'
        elif boxes[3] is None: cls = 'recolour'
        elif db > da: cls = 'gained'
        elif db < da: cls = 'lost'
        else: cls = 'moved'
        return {'class': cls, 'maxdelta': maxdelta, 'changed': changed, 'bbox': bbox,
                'drawn': (da, db),
                'detail': 'maxdelta=%d over %d px, bbox=%s, drawn %d -> %d (%+d)'
                          % (maxdelta, changed, bbox, da, db, db - da)}


def index(root):
    found = {}
    for dirpath, _, names in os.walk(root):
        for name in names:
            if name.lower().endswith('.png'):
                full = os.path.join(dirpath, name)
                found[os.path.relpath(full, root)] = full
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('a'); ap.add_argument('b')
    ap.add_argument('--summary', action='store_true',
                    help='tree mode: counts per class and per skin, and only the lost/gained/size rows')
    ap.add_argument('--top', type=int, default=0, help='with --summary: cap each listed class at N rows')
    args = ap.parse_args()

    if os.path.isfile(args.a) and os.path.isfile(args.b):
        r = compare(args.a, args.b)
        print('identical' if r is None else '%s  %s' % (r['class'].upper(), r['detail']))
        sys.exit(0 if r is None else 1)

    a, b = index(args.a), index(args.b)
    only_a, only_b = sorted(set(a) - set(b)), sorted(set(b) - set(a))
    rows, unreadable, identical = [], [], 0
    for name in sorted(set(a) & set(b)):
        try:
            r = compare(a[name], b[name])
        except Exception as exc:
            unreadable.append((name, str(exc))); continue
        if r is None: identical += 1
        else: rows.append((name, r))

    by_class = defaultdict(list)
    for name, r in rows: by_class[r['class']].append((name, r))
    print('%d identical, %d differing, %d only in base, %d only in curr, %d unreadable'
          % (identical, len(rows), len(only_a), len(only_b), len(unreadable)))
    print('by class: ' + ', '.join('%s %d' % (c, len(by_class[c])) for c in CLASS_ORDER if by_class[c]))
    if args.summary:
        skins = Counter(name.split(os.sep)[0] for name, _ in rows)
        print('by skin (%d skins): ' % len(skins)
              + ', '.join('%s %d' % kv for kv in sorted(skins.items(), key=lambda kv: (-kv[1], kv[0]))[:20])
              + (' …' if len(skins) > 20 else ''))
    listed = ['lost', 'gained', 'size'] if args.summary else CLASS_ORDER
    for c in listed:
        items = sorted(by_class[c], key=lambda nr: -abs(nr[1].get('drawn', (0, 0))[1] - nr[1].get('drawn', (0, 0))[0]))
        if args.summary and args.top: items = items[:args.top]
        for name, r in items:
            print('  %-8s %s  %s' % (c.upper(), name, r['detail']))
    for name in only_a: print('  ONLY-BASE %s' % name)
    for name in only_b: print('  ONLY-CURR %s' % name)
    for name, why in unreadable: print('  UNREADABLE %s  %s' % (name, why))
    sys.exit(0 if not rows and not only_a and not only_b and not unreadable else 1)


if __name__ == '__main__':
    main()
