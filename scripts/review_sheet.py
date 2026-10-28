#!/usr/bin/env python3
"""One sheet per skin for the visual review: the author's reference beside every window we drew.

  scripts/review_sheet.py <out.png> <render.png>... [--ref screenshot.png] [--scale F]

Every render is composited over magenta. An image viewer shows alpha 0 as white or black, so a
missing background on a light or dark skin reads as intended art — that is how intake #3's
see-through panes reached the user. Magenta inside a body is a hole; the reference (drawn as is)
says whether the author meant it.

Per render it prints the transparent share and the *enclosed* holes — transparent pixels not
connected to the canvas edge. A shaped window's cut-outs touch the edge; a body's missing fill
usually does not. `HOLES` marks a render worth opening first, never a verdict either way: a fully
see-through window has no enclosed hole at all, which is why the transparent share is printed too.

--scale divides the renders (2 for Retina window-census shots) so everything sits at 1x beside a
1x reference.
"""
import argparse
from PIL import Image, ImageDraw

MAGENTA = (255, 0, 255, 255)
PAD = 12
HOLE_FLAG = 64  # px; below this an enclosed hole is antialiasing


def holes(img):
    """(transparent px, enclosed px, enclosed bbox) for alpha <= 8."""
    alpha = img.getchannel('A')
    mask = alpha.point(lambda a: 255 if a <= 8 else 0)
    framed = Image.new('L', (img.width + 2, img.height + 2), 255)
    framed.paste(mask, (1, 1))
    ImageDraw.floodfill(framed, (0, 0), 128)  # reach every edge-connected transparent pixel
    enclosed = framed.point(lambda v: 255 if v == 255 else 0).crop((1, 1, img.width + 1, img.height + 1))
    return mask.histogram()[255], enclosed.histogram()[255], enclosed.getbbox()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('renders', nargs='+')
    ap.add_argument('--ref', action='append', default=[])
    ap.add_argument('--scale', type=float, default=1.0)
    a = ap.parse_args()

    tiles = []
    for path in a.ref:
        tiles.append(Image.open(path).convert('RGBA'))
        print('%s  reference' % path)
    for path in a.renders:
        img = Image.open(path).convert('RGBA')
        if a.scale != 1:
            img = img.resize((round(img.width / a.scale), round(img.height / a.scale)), Image.LANCZOS)
        clear, enclosed, box = holes(img)
        total = img.width * img.height
        flag = '  HOLES' if enclosed >= HOLE_FLAG else ''
        print('%s  %dx%d  transparent=%.0f%%  enclosed=%d px%s%s' % (
            path, img.width, img.height, 100 * clear / total, enclosed,
            ' bbox=%s' % (box,) if enclosed else '', flag))
        backed = Image.new('RGBA', img.size, MAGENTA)
        tiles.append(Image.alpha_composite(backed, img))

    w = max(t.width for t in tiles) + 2 * PAD
    h = sum(t.height for t in tiles) + PAD * (len(tiles) + 1)
    sheet = Image.new('RGBA', (w, h), (40, 40, 40, 255))
    y = PAD
    for t in tiles:
        sheet.paste(t, (PAD, y), t)
        y += t.height + PAD
    sheet.save(a.out)
    print('sheet: %s' % a.out)


if __name__ == '__main__':
    main()
