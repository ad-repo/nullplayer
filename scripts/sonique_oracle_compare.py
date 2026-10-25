#!/usr/bin/env python3
"""Compare the render probe's pictures with what real Sonique drew, skin by skin and mode by mode.

usage: python3 -I scripts/sonique_oracle_compare.py <captures dir> <render dir> [--record]

<captures dir> is a scripts/sonique_oracle_capture.sh run (<skin>__<mode>_0.png, 2x, window-only);
<render dir> a render probe run in the oracle's state (SONIQUE_RENDER_OUT, SONIQUE_RENDER_STATE unset).
Each render is placed on the capture where the two outlines overlap most (cross-correlation; a stray
pixel the oracle leaves beside a window cannot move it), then the best of a +-2 px search. Per skin and mode, in skin pixels:

  shape   pixels inside one outline only, after Wine's distortion of ours (wine_shape) and leaving out
          the oracle's unpainted white (harness.md § Outline comparison)
  colour  pixels inside both whose channels differ by more than TOLERANCE: what Sonique paints that
          the renderer does not, or paints differently. JPEG decoders disagree by a few levels only
  area    the oracle's outline

The verdicts are against docs/sonique/oracle-baseline.tsv, the committed ratchet: a cell above its
baseline is a REGRESSION, one below it progress to --record. Nothing about a skin but these counts is
written there, so it carries no artwork. A skin absent from it is unranked.
"""
import argparse, csv, os, sys
from multiprocessing import Pool

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sonique_outline_compare import wine_shape  # noqa: E402

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, 'docs/sonique/oracle-baseline.tsv')
MODES = ('nav', 'mid', 'small')
TOLERANCE = 48
HEADER = """\
# Render probe against the Sonique 1.96 oracle, per corpus skin and mode, in skin pixels: the
# ratchet scripts/sonique_oracle_compare.py checks. A count above its row is a REGRESSION; one below
# it is progress, re-recorded with --record. Recipe: skills/sonique-skin-guide/reference/harness.md
# § The oracle sweep.
#
# skin\tmode\tshape\tcolour\tarea
"""


def load(path):
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.int16)


def place(render, size, x, y):
    """`render` on a transparent canvas of `size` with its top-left at (x, y), cropped to the canvas."""
    out = np.zeros(size + (4,), np.int16)
    h, w = render.shape[:2]
    x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + w, size[1]), min(y + h, size[0])
    if x1 > x0 and y1 > y0:
        out[y0:y1, x0:x1] = render[y0 - y:y1 - y, x0 - x:x1 - x]
    return out


def overlap(oracle, render):
    """The (x, y) for the render's top-left that puts most of its outline on the oracle's."""
    size = (oracle.shape[0] + render.shape[0], oracle.shape[1] + render.shape[1])
    spectrum = np.fft.rfft2(oracle, size) * np.conj(np.fft.rfft2(render, size))
    y, x = np.unravel_index(np.argmax(np.fft.irfft2(spectrum, size)), size)
    return (int(x) - size[1] if x > oracle.shape[1] else int(x)), (int(y) - size[0] if y > oracle.shape[0] else int(y))


def counts(oracle, ours):
    inside_o, inside_r = oracle[..., 3] > 127, ours[..., 3] > 127
    white = (oracle[..., :3] == 255).all(axis=2)
    shaped = wine_shape(inside_r)
    shape = (shaped ^ inside_o) & ~(inside_o & ~inside_r & white)
    both = inside_o & inside_r
    colour = both & (np.abs(oracle[..., :3] - ours[..., :3]).max(axis=2) > TOLERANCE)
    return int(shape.sum()), int(colour.sum())


def compare(capture_png, render_png):
    oracle = load(capture_png)[::2, ::2]
    render = load(render_png)
    x, y = overlap(oracle[..., 3] > 127, render[..., 3] > 127)
    best = None
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            got = counts(oracle, place(render, oracle.shape[:2], x + dx, y + dy))
            best = min(best or got, got)  # the outline decides the alignment; colour breaks ties
    return best + (int((oracle[..., 3] > 127).sum()),)


def baseline():
    if not os.path.exists(BASELINE):
        return {}
    rows = csv.reader((line for line in open(BASELINE, encoding='utf-8') if not line.startswith('#')), delimiter='\t')
    return {(r[0], r[1]): tuple(map(int, r[2:5])) for r in rows if r}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('captures')
    parser.add_argument('render')
    parser.add_argument('--record', action='store_true', help='rewrite the baseline from this run')
    args = parser.parse_args()
    jobs = {}
    for name in sorted(os.listdir(args.captures)):
        skin, _, rest = name.rpartition('__')  # a skin name can hold `__` itself (paper_)
        mode = rest.split('_')[0]
        if mode not in MODES or not rest.endswith('_0.png'):
            continue
        render = os.path.join(args.render, f'{skin}__{mode}.png')
        if os.path.exists(render):
            jobs[(skin, mode)] = (os.path.join(args.captures, name), render)
        else:
            print(f'MISSING {mode} {skin}: no render')
    with Pool() as pool:
        results = dict(zip(jobs, pool.starmap(compare, jobs.values())))
    if not results:
        sys.exit(f'sonique_oracle_compare: no captures matched renders in {args.render}')

    base = baseline()
    worse, better, unranked = [], [], 0
    for key, got in sorted(results.items(), key=lambda kv: kv[0][0].lower()):
        print(f'ORACLE {key[1]} shape={got[0]} colour={got[1]} area={got[2]} {key[0]}')
        was = base.get(key)
        if was is None:
            unranked += 1
        elif got[0] > was[0] or got[1] > was[1]:
            worse.append((key, was, got))
        elif got[:2] != was[:2]:
            better.append((key, was, got))
    for mode in MODES:
        got = [v for k, v in results.items() if k[1] == mode]
        if got:
            area = sum(v[2] for v in got)
            print(f'SUMMARY {mode}: {len(got)} compared, shape exact {sum(v[0] == 0 for v in got)}, '
                  f'shape {sum(v[0] for v in got) / area:.2%}, colour {sum(v[1] for v in got) / area:.2%} of {area} px')
    for (skin, mode), was, got in worse:
        print(f'REGRESSION {mode} shape {was[0]} -> {got[0]} colour {was[1]} -> {got[1]} {skin}')
    for (skin, mode), was, got in better:
        print(f'BETTER {mode} shape {was[0]} -> {got[0]} colour {was[1]} -> {got[1]} {skin}')
    print(f'VERDICT {len(results)} compared, {len(worse)} regressions, {len(better)} better, {unranked} unranked')
    if args.record:
        with open(BASELINE, 'w', encoding='utf-8') as out:
            out.write(HEADER)
            for (skin, mode), got in sorted(results.items(), key=lambda kv: (kv[0][0].lower(), MODES.index(kv[0][1]))):
                out.write(f'{skin}\t{mode}\t{got[0]}\t{got[1]}\t{got[2]}\n')
        print(f'recorded {len(results)} rows -> {os.path.normpath(BASELINE)}')
    sys.exit(1 if worse else 0)


if __name__ == '__main__':
    main()
