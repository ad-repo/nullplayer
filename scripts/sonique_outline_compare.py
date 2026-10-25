#!/usr/bin/env python3
"""Compare each mode's window outline as assembled from the skin with the one real Sonique drew.

usage: python3 -I scripts/sonique_outline_compare.py [<captures dir>] [<corpus dir>]

Reads oracle captures named <skin>__<nav|mid|small>_0.png (scripts/sonique_oracle_capture.sh, 2x,
window-only, binary alpha) and the matching <skin>.sgf. The assembled outline is the mode's
/rgn/<mode>/frame, right/bottom exclusive; navigator mode adds the closed drawer, /rgn/nav/drawer at
DRAWER_POS ([misc locations]), else MISC_DRAWER_POS ([misc values]), else 29,229. A repeated entry
name reads its last copy.

Wine hands macOS a distorted copy of the region Sonique sets (wine_shape), so the outline is compared
after the same distortion. A pixel still left over is unexplained unless it is oracle-only and pure
white: shown by macOS but outside the region Sonique set, so nothing painted it. What the numbers
settled is in skills/sonique-skin-guide/reference/format.md and harness.md.
"""
import os, re, struct, sys

import numpy as np
from PIL import Image

ORACLE = os.path.expanduser('~/Library/Application Support/NullPlayer/SoniqueOracle')
MODES = ('nav', 'mid', 'small')
WINDOW_X = 3  # the skin's x = 0 sits 3 px into the captured window, which fixes Wine's byte phase


def entries(data):
    """The .sgf entry table, names lowercased, the last of a name kept (as SoniqueSkinLoader does)."""
    out = {}
    for i in range(struct.unpack_from('<I', data, 0x68)[0]):
        at = 0x70 + i * 0x64
        name = data[at:at + 0x54].split(b'\0')[0].decode('latin1').lower()
        offset, size = struct.unpack_from('<II', data, at + 0x54)
        out[name] = data[offset:offset + size]
    return out


def ini(text):
    """(section, key) -> value; the first section of a name and the first key in it (SoniqueSkinINI)."""
    out, seen, section = {}, set(), None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('['):
            name = line[1:line.find(']')].strip().lower() if ']' in line else None
            section = name if name is not None and name not in seen else None
            seen.add(name)
        elif section and '=' in line and not line.startswith((';', '//')):
            key, value = line.split('=', 1)
            out.setdefault((section, key.strip().lower()), value.strip())
    return out


def drawer_pos(cfg):
    for section, key in (('misc locations', 'drawer_pos'), ('misc values', 'misc_drawer_pos')):
        x, y = (re.match(r'-?\d+', cfg.get((section, f'{key}_{axis}'), '')) for axis in 'xy')
        if x and y and (key == 'drawer_pos' or (int(x.group()), int(y.group())) != (0, 0)):
            return int(x.group()), int(y.group())
    return 29, 229  # MISC_DRAWER_POS 0,0 reads as unwritten (Barrels, winson99)


def paint(mask, payload, dx=0, dy=0):
    for i in range(struct.unpack_from('<H', payload)[0]):
        left, top, right, bottom = struct.unpack_from('<4H', payload, 10 + 8 * i)
        mask[max(top + dy, 0):bottom + dy, max(left + dx, 0):right + dx] = True


def outline(skin, mode):
    """The assembled outline in window columns (skin x + WINDOW_X), and whether the default drawer is missing."""
    frame = skin.get(f'/rgn/{mode}/frame')
    if frame is None:
        return None, False
    mask = np.zeros((1024, 1024), bool)
    paint(mask, frame, WINDOW_X)
    drawer = skin.get('/rgn/nav/drawer') if mode == 'nav' else None
    if drawer:
        x, y = drawer_pos(ini(skin.get('/skin.ini', b'').decode('latin1')))
        paint(mask, drawer, x + WINDOW_X, y)
    return mask, mode == 'nav' and drawer is None


def wine_shape(mask):
    """Wine's 1 bpp window shape: a run inside one byte of a row comes out as [right, end of that byte)."""
    out = np.zeros_like(mask)
    for y in np.nonzero(mask.any(axis=1))[0]:
        edges = np.diff(np.concatenate([[0], mask[y].astype(np.int8), [0]]))
        for left, right in zip(np.nonzero(edges == 1)[0], np.nonzero(edges == -1)[0]):
            if left >> 3 == (right - 1) >> 3:
                out[y, right:(left | 7) + 1] = True
            else:
                out[y, left:right] = True
    return out


def rows(mask):
    return mask[np.nonzero(mask.any(axis=1))[0].min():]


def compare(model, capture):
    """Pixel counts after aligning tops (the window's y origin varies by mode); x is fixed."""
    oracle, white = capture[..., 3] > 0, (capture[..., :3] == 255).all(axis=2)
    top = np.nonzero(oracle.any(axis=1))[0].min()
    oracle, white = oracle[top:], white[top:]
    best = None
    for shift in range(-2, 3):
        a, b = rows(model)[max(shift, 0):], oracle[max(-shift, 0):]
        h, w = max(a.shape[0], b.shape[0]), max(a.shape[1], b.shape[1])
        pa, pb, pw = (np.zeros((h, w), bool) for _ in range(3))
        pa[:a.shape[0], :a.shape[1]] = a
        pb[:b.shape[0], :b.shape[1]] = b
        pw[:b.shape[0], :b.shape[1]] = white[max(-shift, 0):]
        diff = pa ^ pb
        counts = (int(diff.sum()), int((diff & ~(pb & pw)).sum()))
        best = min(best or counts, counts)
    return best


def main():
    captures = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ORACLE, 'captures/sample-2026-10-11')
    corpus = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/Library/Application Support/NullPlayer/SoniqueSkins')
    counts = {mode: [] for mode in MODES}
    for name in sorted(os.listdir(captures)):
        skin_name, _, rest = name.rpartition('__')  # a skin name can hold `__` itself (paper_)
        mode = rest.split('_')[0]
        if mode not in MODES or not rest.endswith('_0.png'):
            continue
        skin = entries(open(os.path.join(corpus, skin_name + '.sgf'), 'rb').read())
        model, default_drawer = outline(skin, mode)
        if model is None:
            print(f'OUTLINE {skin_name} {mode} no-frame')
            continue
        capture = np.asarray(Image.open(os.path.join(captures, name)).convert('RGBA'))[::2, ::2]
        region, _ = compare(model, capture)
        wine, unexplained = compare(wine_shape(model), capture)
        tag = ' default-drawer' if default_drawer else ''
        counts[mode].append((region, wine, unexplained, default_drawer))
        print(f'OUTLINE {skin_name} {mode} region={region} wine={wine} unexplained={unexplained}{tag}')

    for mode in MODES:
        got = counts[mode]
        if got:
            print(f'SUMMARY {mode}: {len(got)} outlines, region exact {sum(r == 0 for r, *_ in got)}, '
                  f'wine exact {sum(w == 0 for _, w, *_ in got)}, explained {sum(u == 0 for _, _, u, _ in got)}, '
                  f'default drawer {sum(d for *_, d in got)}')


if __name__ == '__main__':
    main()
