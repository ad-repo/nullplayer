#!/usr/bin/env python3
"""Contact sheets for Audion face text: Panic's screenshot of each face beside NullPlayer's render.

    audion_font_sheet.py <cache> <corpus> <out> --before <capture> [--after <capture>] [--per-page N]

<cache> is scripts/audion_panic_originals.sh's (with map.tsv and txtr.tsv from audion_txtr.py);
<capture> is a scripts/audion_render_sweep.sh capture, whose `playing` PNGs and `PROBE … label:`
lines give the render and its text boxes. Each row: the face as Panic's JPG shows it (found by
cross-correlating base.png), before, after, then both text boxes from each at 3x nearest-neighbour.
Pages go to <out>/<cohort>-<n>.png, cohorts in review order; <out>/index.tsv lists every row.
The sheets are the evidence for text work: the oracle draws missing fonts as Helvetica too. Never
committed. Documented in skills/audion-face-guide/reference/harness.md.
"""

import argparse
import collections
import csv
import json
import os
import re
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ISSUE_642 = ['Mint 1.2 xp', 'Display', 'FX', 'B Box', 'Glass', 'Vintage Totem', 'YAG']
SUBSTITUTED = {'chicago', 'charcoal', 'techno', 'gadget', 'sand', 'capitals', 'silkscreen', 'textile', 'kidprint',
               'sf digital readout medium', 'mini', 'mini tight', '04b-03', '04b-08', '04b-09', '04b-11',
               '04b-20', '04b-24', '04bit-10', '04bit-16', 'orchis 5', 'orchis 6', 'redensek', 'bitbit',
               'bitsumishi', 'squarodynamic 08', 'hooge 05_53', 'freecemini', 'lilliput steps',
               'ikkio_square'}  # AudionFaceFontSubstitutes' keys
BITMAP_STRIKES = {'geneva': {9, 10, 12, 14, 18, 20, 24}, 'monaco': {9, 10, 12, 14}}
SCALE, CROP_MAX, THUMB = 3, 260, (340, 170)
SHIPPED = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Sources', 'NullPlayer', 'Resources',
                       'Fonts', 'AudionFaces')  # AudionFaceOriginalFonts' families
FONT = ImageFont.load_default()


def installed_fonts(names):
    """The names NSFont resolves on this Mac, asked once through JXA."""
    script = ('ObjC.import("AppKit"); JSON.stringify(%s.filter(n => !$.NSFont.fontWithNameSize(n, 12).isNil()))'
              % json.dumps(sorted(names)))
    out = subprocess.run(['osascript', '-l', 'JavaScript', '-e', script], capture_output=True, text=True, check=True)
    return set(json.loads(out.stdout))


def boxes(capture):
    """{face: {role: (x, y, w, h)}} from a capture's playing-state label PROBE lines."""
    found, face = collections.defaultdict(dict), None
    with open(os.path.join(capture, 'raw.txt'), errors='replace') as raw:
        for line in raw:
            if line.startswith('FACE ') and ' FAILED ' not in line:
                face = line[5:].rstrip('\n')
            match = re.match(r'PROBE playing label:(\w+) (-?\d+),(-?\d+) (\d+)x(\d+)', line)
            if match and face:
                found[face][match[1]] = tuple(int(v) for v in match.groups()[1:])
    return found


def locate(jpg, base):
    """(x, y, score) of base inside jpg by masked normalised cross-correlation on grey, or None.
    Only base's opaque pixels count (its transparent ones show the desktop in a screenshot), and
    base is first cut to their bounding box, so x and y may be negative."""
    alpha = np.asarray(base.getchannel('A')) > 128
    if not alpha.any():
        return None
    rows, cols = np.nonzero(alpha.any(1))[0], np.nonzero(alpha.any(0))[0]
    top, left = rows[0], cols[0]
    mask = alpha[top:rows[-1] + 1, left:cols[-1] + 1].astype(np.float64)
    template = np.asarray(base.convert('L'), dtype=np.float64)[top:rows[-1] + 1, left:cols[-1] + 1] * mask
    image = np.asarray(jpg.convert('L'), dtype=np.float64)
    # A screenshot cropped tighter than the face's shadow: pad it by edge replication.
    pad_y, pad_x = max(0, template.shape[0] - image.shape[0]), max(0, template.shape[1] - image.shape[1])
    image = np.pad(image, ((pad_y, pad_y), (pad_x, pad_x)), mode='edge')
    (H, W), (h, w) = image.shape, template.shape
    shape = (H + h, W + w)
    def correlate(a, kernel):
        out = np.fft.irfft2(np.fft.rfft2(a, shape) * np.conj(np.fft.rfft2(kernel, shape)), shape)
        return out[:H - h + 1, :W - w + 1]
    n = mask.sum()
    sum_i, sum_i2 = correlate(image, mask), correlate(image ** 2, mask)
    numerator = correlate(image, template) - sum_i * template.sum() / n
    spread_t = np.sqrt(max((template ** 2).sum() - template.sum() ** 2 / n, 1e-9))
    ncc = numerator / (np.sqrt(np.maximum(sum_i2 - sum_i ** 2 / n, 1e-9)) * spread_t)
    y, x = np.unravel_index(np.argmax(ncc), ncc.shape)
    return int(x - left - pad_x), int(y - top - pad_y), float(ncc[y, x])


def thumb(image):
    image = image.convert('RGBA')
    image.thumbnail(THUMB, Image.NEAREST if image.width <= THUMB[0] and image.height <= THUMB[1] else Image.LANCZOS)
    return image


def crop(image, rect, offset=(0, 0)):
    if image is None or rect is None:
        return None
    x, y, w, h = rect
    x, y = x + offset[0], y + offset[1]
    w = min(w, CROP_MAX)
    part = image.convert('RGBA').crop((x, y, x + w, y + h))
    return part.resize((part.width * SCALE, part.height * SCALE), Image.NEAREST)


def describe(face, lines, index):
    out = [face]
    for role in ('artist', 'album'):
        t = lines.get(role)
        authored = 'no Txtr' if not t or t['id'] == '-' else \
            f"Txtr {t['id']}: {t['name'] or '(none)'!r} {t['size']} style {t['style']} just {t['just']} #{t['rgb']}"
        out.append(f"{role}: {authored}")
        out.append(f"  index: {index.get(f'{role}DisplayFontName')!r} {index.get(f'{role}FontSize')} "
                   f"justify {index.get(f'{role}Justify')}")
    return out


def row_image(face, lines, index, jpg, base, before, after, rects_before, rects_after):
    located = locate(jpg, base) if jpg is not None else None
    offset = located[:2] if located and located[2] > 0.5 else None
    shown = jpg.crop((offset[0], offset[1], offset[0] + base.width, offset[1] + base.height)) if offset else jpg
    text = describe(face, lines, index) + [
        'jpg: ' + ('none' if jpg is None else f'at {offset} ncc {located[2]:.2f}' if offset
                   else f'not located ({located[2]:.2f})' if located else 'no opaque pixels')]
    tiles = [('Panic JPG', shown), ('before', before), ('after', after)]
    crops = []
    for role in ('artist', 'album'):
        rect = rects_before.get(role) or rects_after.get(role)
        crops.append([(f'{role} JPG', crop(jpg, rect, offset) if offset else None),
                      (f'{role} before', crop(before, rects_before.get(role))),
                      (f'{role} after', crop(after, rects_after.get(role)))])
    crop_w = max([c.width for column in crops for _, c in column if c] + [120])
    crop_h = [max([c.height for _, c in column if c] + [12]) for column in zip(*crops)]
    head_h = max(THUMB[1], 12 * len(text)) + 16
    width = 300 + 3 * (THUMB[0] + 10)
    width = max(width, 2 * (crop_w + 90))
    height = head_h + sum(h + 6 for h in crop_h) + 10
    canvas = Image.new('RGBA', (width, height), (236, 236, 236, 255))
    draw = ImageDraw.Draw(canvas)
    for i, line in enumerate(text):
        draw.text((6, 6 + 12 * i), line, fill=(0, 0, 0, 255), font=FONT)
    for i, (label, tile) in enumerate(tiles):
        x = 300 + i * (THUMB[0] + 10)
        draw.text((x, 2), label, fill=(80, 80, 80, 255), font=FONT)
        if tile is not None:
            small = thumb(tile)
            canvas.alpha_composite(small, (x, 14))
    y = head_h
    for r, h in enumerate(crop_h):
        for c, column in enumerate(crops):
            label, image = column[r]
            x = 6 + c * (crop_w + 90)
            draw.text((x, y), label, fill=(80, 80, 80, 255), font=FONT)
            if image is not None:
                canvas.alpha_composite(image, (x + 84, y))
        y += h + 6
    draw.line((0, height - 1, width, height - 1), fill=(120, 120, 120, 255))
    return canvas


def load(path):
    try:
        return Image.open(path).convert('RGBA') if path and os.path.isfile(path) else None
    except OSError:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('cache')
    parser.add_argument('corpus')
    parser.add_argument('out')
    parser.add_argument('--before', required=True)
    parser.add_argument('--after')
    parser.add_argument('--per-page', type=int, default=12)
    parser.add_argument('--cohort', action='append', help='only these cohorts')
    args = parser.parse_args()

    jpg_of = {}
    with open(os.path.join(args.cache, 'map.tsv')) as file:
        for row in csv.DictReader(file, delimiter='\t'):
            if row['face'] and row['jpg']:
                jpg_of.setdefault(row['face'], os.path.join(args.cache, 'download', row['jpg'] + '.jpg'))
    lines = collections.defaultdict(dict)
    with open(os.path.join(args.cache, 'txtr.tsv')) as file:
        for row in csv.DictReader(file, delimiter='\t'):
            lines[row['face']].setdefault(row['role'], row)
    indexes = {}
    for face in os.listdir(args.corpus):
        path = os.path.join(args.corpus, face, 'index.json')
        if os.path.isfile(path):
            with open(path, 'rb') as file:
                indexes[face] = json.load(file)
    names = {index.get(f'{role}DisplayFontName') for index in indexes.values() for role in ('artist', 'album')}
    names |= {t['name'] for face in lines.values() for t in face.values() if t['id'] != '-'}
    names.discard(None)
    names.discard('')
    resolved = installed_fonts(names)
    shipped = {name.strip().lower() for name in os.listdir(SHIPPED)} if os.path.isdir(SHIPPED) else set()

    cohorts = collections.OrderedDict((name, []) for name in [
        'issue-642', 'dropped', 'txtr-128-only', 'no-txtr', 'right', 'centred', 'bitmap-strike',
        'original-font', 'substitute', 'unresolved'])
    for face in sorted(indexes, key=str.casefold):
        index, line = indexes[face], lines.get(face, {})
        ids = {t['id'] for t in line.values()}
        if face in ISSUE_642:
            cohorts['issue-642'].append(face)
        if any(t['id'] in ('200', '201') and index.get(f'{role}DisplayFontName') is None and (t['name'] or t['size'] != '0')
               for role, t in line.items()):
            cohorts['dropped'].append(face)
        if ids == {'128'}:
            cohorts['txtr-128-only'].append(face)
        if line and ids == {'-'}:
            cohorts['no-txtr'].append(face)
        if any(t['just'] == '-1' for t in line.values()):
            cohorts['right'].append(face)
        if any(t['just'] == '1' and t['id'] != '128' for t in line.values()):
            cohorts['centred'].append(face)
        fonts = [(index.get(f'{role}DisplayFontName'), index.get(f'{role}FontSize')) for role in ('artist', 'album')]
        if any(n and n.strip().lower() in BITMAP_STRIKES and s in BITMAP_STRIKES[n.strip().lower()] for n, s in fonts):
            cohorts['bitmap-strike'].append(face)
        if any(n and n.strip().lower() in shipped and n not in resolved for n, _ in fonts):
            cohorts['original-font'].append(face)
        if any(n and n.strip().lower() in SUBSTITUTED and n not in resolved for n, _ in fonts):
            cohorts['substitute'].append(face)
        if any(n and n not in resolved and n.strip().lower() not in SUBSTITUTED for n, _ in fonts):
            cohorts['unresolved'].append(face)

    rects_before, rects_after = boxes(args.before), boxes(args.after) if args.after else {}
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, 'index.tsv'), 'w') as listing:
        listing.write('cohort\tpage\tface\n')
        for cohort, faces in cohorts.items():
            if args.cohort and cohort not in args.cohort:
                continue
            for page_number, start in enumerate(range(0, len(faces), args.per_page), 1):
                rows = []
                for face in faces[start:start + args.per_page]:
                    base = load(os.path.join(args.corpus, face, 'base.png'))
                    if base is None:
                        continue
                    rows.append(row_image(
                        face, lines.get(face, {}), indexes[face], load(jpg_of.get(face)), base,
                        load(os.path.join(args.before, 'png', face, 'playing.png')),
                        load(os.path.join(args.after, 'png', face, 'playing.png')) if args.after else None,
                        rects_before.get(face, {}), rects_after.get(face, {})))
                    listing.write(f'{cohort}\t{page_number}\t{face}\n')
                if not rows:
                    continue
                page = Image.new('RGBA', (max(r.width for r in rows), sum(r.height for r in rows)), (236, 236, 236, 255))
                y = 0
                for r in rows:
                    page.alpha_composite(r, (0, y))
                    y += r.height
                page.convert('RGB').save(os.path.join(args.out, f'{cohort}-{page_number}.png'))
            print(f'audion_font_sheet: {cohort}: {len(faces)} faces, {-(-len(faces) // args.per_page)} page(s)')


if __name__ == '__main__':
    main()
