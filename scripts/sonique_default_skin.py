#!/usr/bin/env python3
"""Draw NullPlayer's default Sonique skin (S11) and write it as an .sgf.

    python3 -I scripts/sonique_default_skin.py [<layout.sgf>] [<out.sgf>]

The artwork is NullPlayer's own, drawn here. The layout is Sonique's default: every /rgn/ entry is
copied from <layout.sgf>, the corpus skin whose frames match the oracle's default outlines exactly
(`sonique.sgf`, see skills/sonique-skin-guide/reference/harness.md § *The default skin*). Lit states
sit at misc.txt's default [misc locations], so the skin writes no [misc locations] of its own, and
it writes no [sonique colors]: the default skin's colours are misc.txt's.

Needs Pillow and NumPy. Pure black is transparent in a Sonique picture, so nothing here is drawn
darker than DARKEST.
"""
import io, os, struct, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LAYOUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Library/Application Support/NullPlayer/SoniqueSkins/sonique.sgf')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    HERE, '..', 'Sources', 'NullPlayer', 'Resources', 'Skins', 'NullPlayer-Sonique.sgf')
FONT = ImageFont.truetype(os.path.join(HERE, '..', 'Sources', 'NullPlayer', 'Resources', 'Fonts',
                                       'DepartureMono-Regular.otf'), 11)

# The palette: NullPlayer's flat graphite with navy screens (NullPlayer-Silver, NullPlayer-Black).
DARKEST = (14, 15, 18)
BODY_TOP, BODY_BOTTOM = (50, 54, 62), (30, 32, 37)
EDGE_LIGHT, EDGE_DARK = (92, 97, 108), (18, 19, 23)
SCREEN, SCREEN_RIM = (18, 20, 34), (54, 58, 74)
KEY, KEY_LIGHT, KEY_DARK = (64, 68, 78), (104, 110, 122), (36, 38, 44)
GLYPH = (214, 218, 225)
LABEL = (150, 156, 168)
ACCENT = (255, 138, 31)
LIT = {'cyan': (0, 210, 230), 'green': (90, 220, 90), 'orange': ACCENT, 'red': (230, 70, 60),
       'trans': (120, 160, 220)}


# --- the layout ---------------------------------------------------------------------------------

def entries(path):
    d = open(path, 'rb').read()
    n = struct.unpack_from('<I', d, 0x68)[0]
    out = {}
    for i in range(n):
        e = 0x70 + i * 0x64
        name = d[e:e + 0x54].split(b'\0')[0].decode('latin-1').lower()
        off, size = struct.unpack_from('<II', d, e + 0x54)
        out[name] = d[off:off + size]
    return out


LAYOUT_ENTRIES = entries(LAYOUT)
REGIONS = {k: v for k, v in LAYOUT_ENTRIES.items() if k.startswith('/rgn/') and not k.endswith('logohref')}


def rects(name):
    p = REGIONS[name]
    n = struct.unpack_from('<H', p, 0)[0]
    return [struct.unpack_from('<4H', p, 10 + 8 * i) for i in range(n)]


def bounds(name):
    return struct.unpack_from('<4H', REGIONS[name], 2)


def mask(name, size, dx=0, dy=0):
    """The region as a 1-bit-deep L image of `size`, moved by dx, dy."""
    m = np.zeros((size[1], size[0]), np.uint8)
    for l, t, r, b in rects(name):
        m[max(0, t + dy):max(0, b + dy), max(0, l + dx):max(0, r + dx)] = 255
    return Image.fromarray(m)


# --- drawing ------------------------------------------------------------------------------------

def gradient(size, top, bottom):
    h = size[1]
    col = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top)[None, None, :] * (1 - col) + np.array(bottom)[None, None, :] * col
    return Image.fromarray(np.repeat(arr, size[0], axis=1).astype(np.uint8), 'RGB')


def bevel(img, m, light=EDGE_LIGHT, dark=EDGE_DARK, width=1):
    """A 1 px light edge up and left, dark down and right, inside mask `m`."""
    a = np.array(m) > 0
    up = np.zeros_like(a); up[width:, width:] = a[:-width, :-width]
    down = np.zeros_like(a); down[:-width, :-width] = a[width:, width:]
    px = np.array(img)
    px[a & ~up] = light
    px[a & ~down] = dark
    return Image.fromarray(px)


def fill(img, m, colour_or_image):
    src = colour_or_image if isinstance(colour_or_image, Image.Image) else Image.new('RGB', img.size, colour_or_image)
    img.paste(src, (0, 0), m)


def chassis(size, m):
    img = Image.new('RGB', size, DARKEST)
    fill(img, m, gradient(size, BODY_TOP, BODY_BOTTOM))
    return bevel(img, m)


def screen(img, m):
    fill(img, m, SCREEN)
    rim = np.array(m) > 0
    inner = np.array(m.filter(ImageFilter.MinFilter(3))) > 0
    px = np.array(img); px[rim & ~inner] = SCREEN_RIM
    return Image.fromarray(px)


def key(img, m, lit=None):
    """A button filling its region: a flat key with a bevel, or lit in a colour."""
    b = m.getbbox()
    if not b:
        return img
    base = gradient(img.size, KEY_LIGHT if lit is None else tuple(min(255, c + 40) for c in lit),
                    KEY if lit is None else lit)
    region = Image.new('L', img.size, 0); region.paste(m, (0, 0))
    fill(img, region, base.crop((0, 0) + img.size) if base.size == img.size else base)
    return bevel(img, region, light=KEY_LIGHT if lit is None else tuple(min(255, c + 70) for c in lit), dark=KEY_DARK)


def glyph(draw, kind, box, colour=GLYPH):
    l, t, r, b = box
    cx, cy = (l + r) / 2, (t + b) / 2
    s = min(r - l, b - t) * 0.28
    if kind == 'play':
        draw.polygon([(cx - s * 0.8, cy - s), (cx - s * 0.8, cy + s), (cx + s, cy)], fill=colour)
    elif kind == 'stop':
        draw.rectangle([cx - s * 0.8, cy - s * 0.8, cx + s * 0.8, cy + s * 0.8], fill=colour)
    elif kind == 'pause':
        draw.rectangle([cx - s * 0.8, cy - s, cx - s * 0.25, cy + s], fill=colour)
        draw.rectangle([cx + s * 0.25, cy - s, cx + s * 0.8, cy + s], fill=colour)
    elif kind == 'prev':
        draw.rectangle([cx - s, cy - s, cx - s * 0.6, cy + s], fill=colour)
        draw.polygon([(cx + s, cy - s), (cx + s, cy + s), (cx - s * 0.5, cy)], fill=colour)
    elif kind == 'next':
        draw.rectangle([cx + s * 0.6, cy - s, cx + s, cy + s], fill=colour)
        draw.polygon([(cx - s, cy - s), (cx - s, cy + s), (cx + s * 0.5, cy)], fill=colour)
    elif kind == 'up':
        draw.polygon([(cx - s * 1.6, cy + s * 0.7), (cx + s * 1.6, cy + s * 0.7), (cx, cy - s * 0.9)], fill=colour)
    elif kind == 'down':
        draw.polygon([(cx - s * 1.6, cy - s * 0.7), (cx + s * 1.6, cy - s * 0.7), (cx, cy + s * 0.9)], fill=colour)


def label(draw, text, xy, colour=LABEL, anchor='la'):
    draw.text(xy, text, font=FONT, fill=colour, anchor=anchor)


# --- the pictures -------------------------------------------------------------------------------

PILL_LABEL = {'eject': 'open', 'repeat': 'loop', 'shuffle': 'mix'}


def transport(img, mode, lit_overrides=None):
    """The unlit buttons of a mode: keys for the transport, pill bars with a label above for
    eject/repeat/shuffle (and mid's nav button), the menu rocker, a well under each knob."""
    p = '/rgn/%s/' % mode
    draw = ImageDraw.Draw(img)
    for name, kind in (('play', 'play'), ('pause', 'pause'), ('prev', 'prev'), ('next', 'next')):
        img = key(img, mask(p + name, img.size))
        draw = ImageDraw.Draw(img)
        glyph(draw, kind, bounds(p + name))
    pills = ['eject', 'repeat', 'shuffle'] + (['eq'] if mode == 'mid' else [])
    for name in pills:
        img = key(img, mask(p + name, img.size))
        draw = ImageDraw.Draw(img)
        l, t, r, b = bounds(p + name)
        text = 'nav' if name == 'eq' else PILL_LABEL[name]
        if mode == 'nav':
            label(draw, text, ((l + r) // 2, t - 1), anchor='md')
        else:
            label(draw, text, (r + 3, (t + b) // 2 + 1), anchor='lm')
    if mode == 'nav':
        for name, kind in (('up', 'up'), ('down', 'down')):
            img = key(img, mask(p + name, img.size))
            draw = ImageDraw.Draw(img)
            glyph(draw, kind, bounds(p + name))
    for name in ['volume'] + (['shuttle'] if mode == 'mid' else []):
        l, t, r, b = bounds(p + name)
        draw.ellipse([l - 2, t - 2, r + 1, b + 1], fill=EDGE_DARK)
        label(draw, 'vol' if name == 'volume' else 'jog', ((l + r) // 2, t - 4), anchor='md')
    return img


def navigator():
    l, t, r, b = bounds('/rgn/nav/frame')
    size = (r, b)
    m = mask('/rgn/nav/frame', size)
    img = chassis(size, m)
    img = screen(img, mask('/rgn/nav/display', size))
    draw = ImageDraw.Draw(img)
    dl, dt, dr, db = bounds('/rgn/nav/display')
    label(draw, 'nullplayer', (dl + 2, dt - 8), GLYPH, anchor='ls')
    draw.rectangle([dl + 74, dt - 13, dl + 77, dt - 10], fill=ACCENT)
    label(draw, 'navigator', (dr - 2, dt - 8), LABEL, anchor='rs')
    return transport(img, 'nav')


def midsonique():
    l, t, r, b = bounds('/rgn/mid/frame')
    size = (r, b)
    m = mask('/rgn/mid/frame', size)
    img = chassis(size, m)
    for ring in ('songposring', 'listposring'):
        img = screen(img, mask('/rgn/mid/' + ring, size))
    for window in ('top', 'bottom'):
        img = screen(img, mask('/rgn/mid/' + window, size))
    draw = ImageDraw.Draw(img)
    tl, tt, tr, tb = bounds('/rgn/mid/top')
    label(draw, 'nullplayer', ((tl + tr) // 2, tt - 3), GLYPH, anchor='ms')
    return transport(img, 'mid')


def smallstate():
    """The bar twice: unlit above, lit below. Lit: the blinker caps and both progress lines."""
    w, h = 201, 24
    out = Image.new('RGB', (w, h * 2), DARKEST)
    for row, lit in ((0, False), (1, True)):
        m = mask('/rgn/small/frame', (w, h))
        img = chassis((w, h), m)
        draw = ImageDraw.Draw(img)
        # The text window Sonique writes the track and time into, between its two dotted lines.
        draw.rectangle([90, 7, 186, 17], fill=SCREEN)
        for y in (4, 19):
            for x in range(93, 184, 3):
                draw.rectangle([x, y, x + 1, y + 1], fill=(LIT['cyan'] if y == 4 else LIT['green']) if lit else KEY)
        for x0, colour in ((9, LIT['cyan']), (186, LIT['green'])):
            draw.rectangle([x0, 2, x0 + 5, h - 3], fill=colour if lit else KEY_DARK)
        label(draw, 'nullplayer', (18, 15), GLYPH, anchor='ls')
        out.paste(img, (0, row * h))
    return out


def extra():
    """Small mode's drawers: a flat panel each, with an inset strip where the marquee runs."""
    w, h = 166, 90
    img = Image.new('RGB', (w, h), DARKEST)
    for name in ('/rgn/small/extratop', '/rgn/small/extrabottom'):
        m = mask(name, (w, h))
        fill(img, m, gradient((w, h), BODY_TOP, BODY_BOTTOM))
        img = bevel(img, m)
    draw = ImageDraw.Draw(img)
    for strip_top in (26, h - 42 + 5):
        draw.rectangle([16, strip_top, w - 12, strip_top + 10], fill=SCREEN)
    return img


MISC_SIZE = (440, 200)


def misc():
    """Every lit state at misc.txt's default location, the size of its control's bounds."""
    img = Image.new('RGB', MISC_SIZE, DARKEST)

    def lit(at, control, colour, kind=None, mode='nav'):
        nonlocal img
        l, t, r, b = bounds('/rgn/%s/%s' % (mode, control))
        dx, dy = at[0] - l, at[1] - t
        m = mask('/rgn/%s/%s' % (mode, control), MISC_SIZE, dx, dy)
        img = key(img, m, lit=colour)
        if kind:
            glyph(ImageDraw.Draw(img), kind, (at[0], at[1], at[0] + r - l, at[1] + b - t), DARKEST)

    lit((0, 0), 'next', ACCENT, 'next')
    lit((0, 40), 'prev', ACCENT, 'prev')
    lit((90, 0), 'play', ACCENT, 'play')
    lit((90, 40), 'pause', ACCENT, 'pause')
    lit((130, 0), 'play', ACCENT, 'stop')                # STOPON: pressed while playing
    # STOPOFF: what the play key shows while playing, unpressed.
    l, t, r, b = bounds('/rgn/nav/play')
    img = key(img, mask('/rgn/nav/play', MISC_SIZE, 130 - l, 40 - t))
    glyph(ImageDraw.Draw(img), 'stop', (130, 40, 130 + r - l, 40 + b - t), ACCENT)
    lit((30, 0), 'eq', LIT['red'], mode='mid')            # REDON
    lit((30, 20), 'eject', LIT['orange'])                 # ORANGEON
    lit((30, 40), 'shuffle', LIT['green'])                # GREENON
    lit((60, 0), 'repeat', LIT['trans'])                  # CYANOFF, the loop transition
    lit((60, 20), 'repeat', LIT['cyan'])                  # CYANON, loop all
    lit((60, 40), 'repeat', LIT['green'])                 # GREENON2, loop one
    lit((280, 0), 'up', ACCENT, 'up')                     # BIGUP
    lit((280, 35), 'down', ACCENT, 'down')                # BIGON_DOWN
    draw = ImageDraw.Draw(img)
    for y, colour in ((0, ACCENT), (20, KEY_LIGHT)):      # SLIDERON, SLIDEROFF: the drawer's handles
        draw.rectangle([170, y, 177, y + 13], fill=colour)
    # DRAWER: the navigator's drawer, closed behind the console with only its tab showing.
    m = mask('/rgn/nav/drawer', MISC_SIZE, 0, 76)
    panel = gradient(MISC_SIZE, BODY_BOTTOM, BODY_TOP)
    fill(img, m, panel)
    img = bevel(img, m)
    draw = ImageDraw.Draw(img)
    tl, tt, tr, tb = bounds('/rgn/nav/drawertop')
    label(draw, 'audio controls', (tr - 10, 76 + (tt + tb) // 2 + 4), GLYPH, anchor='rm')
    cx = tl + 20
    draw.polygon([(cx - 5, 76 + tb - 16), (cx + 5, 76 + tb - 16), (cx, 76 + tb - 10)], fill=ACCENT)
    # The equaliser's slider tracks, at the default slider array.
    for i in range(16):
        x = 22 + i * 14
        draw.rectangle([x + 3, 76 + 20, x + 4, 76 + 20 + 43], fill=SCREEN_RIM)
    for knob, text in (('dknobamp', 'amp'), ('dknobbal', 'bal'), ('dknobpitch', 'pitch')):
        l, t, r, b = bounds('/rgn/nav/' + knob)
        label(draw, text, (l - 4, 76 + (t + b) // 2 + 1), LABEL, anchor='rm')
    return img


def knob_strip(width, height, frames, body, tick):
    """A knob turning through 270 degrees, one frame per position, left to right."""
    out = Image.new('RGB', (width * frames, height), DARKEST)
    s = 4
    for i in range(frames):
        big = Image.new('RGB', (width * s, height * s), DARKEST)
        d = ImageDraw.Draw(big)
        r = min(width, height) * s / 2 - s
        cx, cy = width * s / 2, height * s / 2
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=body, outline=EDGE_LIGHT, width=s)
        a = np.radians(-225 + 270 * i / max(1, frames - 1))
        d.line([cx + np.cos(a) * r * 0.25, cy + np.sin(a) * r * 0.25, cx + np.cos(a) * r * 0.85, cy + np.sin(a) * r * 0.85],
               fill=tick, width=int(s * 1.5))
        out.paste(big.resize((width, height), Image.LANCZOS), (i * width, 0))
    return out


def shuttle_strip():
    w, h, frames = 49, 47, 13
    out = Image.new('RGB', (w * frames, h), DARKEST)
    s = 4
    for i in range(frames):
        big = Image.new('RGB', (w * s, h * s), DARKEST)
        d = ImageDraw.Draw(big)
        cx, cy, r = w * s / 2, h * s / 2, (min(w, h) / 2 - 1) * s
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=KEY, outline=EDGE_LIGHT, width=s)
        for n in range(12):
            a = np.radians(n * 30 + (i - frames // 2) * 12)
            d.ellipse([cx + np.cos(a) * r * 0.72 - 2 * s, cy + np.sin(a) * r * 0.72 - 2 * s,
                       cx + np.cos(a) * r * 0.72 + 2 * s, cy + np.sin(a) * r * 0.72 + 2 * s], fill=KEY_DARK)
        d.ellipse([cx - r * 0.3, cy - r * 0.3, cx + r * 0.3, cy + r * 0.3], fill=KEY_LIGHT)
        out.paste(big.resize((w, h), Image.LANCZOS), (i * w, 0))
    return out


# --- the container ------------------------------------------------------------------------------

def jpeg(img):
    # Clamp: JPEG must not round any pixel to pure black, which Sonique draws transparent.
    px = np.maximum(np.array(img.convert('RGB')), 1)
    buf = io.BytesIO()
    Image.fromarray(px.astype(np.uint8)).save(buf, 'JPEG', quality=95, subsampling=0)
    data = buf.getvalue()
    decoded = np.array(Image.open(io.BytesIO(data)).convert('RGB'))
    assert not np.any(decoded.sum(axis=2) == 0), 'a pixel decodes to pure black'
    return data


def sgf(items):
    """`format.md` § *Container*: a DAF header, the entry table, then the payloads."""
    table = 0x70 + 0x64 * len(items)
    payloads, offset = [], table
    for name, data in items:
        payloads.append((name, offset, data))
        offset += len(data)
    out = bytearray(table)
    out[0:8] = b'DAF\0LIST'
    struct.pack_into('<I', out, 0x08, table)
    out[0x14:0x18] = b'sgf\0'
    struct.pack_into('<I', out, 0x64, offset)
    struct.pack_into('<I', out, 0x68, len(items))
    for i, (name, off, data) in enumerate(payloads):
        e = 0x70 + i * 0x64
        out[e:e + len(name)] = name.encode('latin-1')
        struct.pack_into('<II', out, e + 0x54, off, len(data))
    for _, _, data in payloads:
        out += data
    return bytes(out)


INI = (b'[skin]\r\nauthor=NullPlayer\r\ntitle=NullPlayer\r\nversion=105\r\n'
       b'TouchNavMode=1\r\nTouchMidMode=1\r\nTouchSmallMode=1\r\n')

items = [
    ('/skin.ini', INI),
    ('/jpeg/navigator', jpeg(navigator())),
    ('/jpeg/midsonique', jpeg(midsonique())),
    ('/jpeg/smallstate', jpeg(smallstate())),
    ('/jpeg/misc', jpeg(misc())),
    ('/jpeg/extra', jpeg(extra())),
    ('/jpeg/volumeknob', jpeg(knob_strip(18, 18, 37, KEY, ACCENT))),
    ('/jpeg/smallknob', jpeg(knob_strip(13, 13, 37, KEY_LIGHT, GLYPH))),
    ('/jpeg/shuttle', jpeg(shuttle_strip())),
] + [(name, data) for name, data in sorted(REGIONS.items())]
data = sgf(items)
open(OUT, 'wb').write(data)
print('wrote %s: %d entries, %d bytes' % (os.path.normpath(OUT), len(items), len(data)))
