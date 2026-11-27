# holiday.py <out.mp4> <skins.txt> [audio] [audio_start_s] — five stockings hang on a fireplace mantle, one per skin
# family with its name in script on the cuff, the site's Christmas skins (nullplayer-site _data/holiday.json) poking out
# of the tops. The camera pans to a tree hung with skins from skins.txt as ornaments; a gift under it shakes, its lid
# pops off and the rest of skins.txt bursts out. Logo + url as in the other promos, "Happy Holidays".
# Media (shots list, audio, output) lives in ~/Documents/shots/promo-kit/holiday, not in the repo.
import io, math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from promo_common import HN, ICON, brand, ease, fade, paste, plate, smooth

OUT, LIST = sys.argv[1], sys.argv[2]
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
ASTART = float(sys.argv[4]) if len(sys.argv) > 4 else 0
W, H, FPS, SECS = 1920, 1080, 50, 20
T0 = float(os.environ.get("START", 0))           # render from this second on (stills for checking a beat)
N = min(int(os.environ.get("FRAMES", FPS * SECS)), int((SECS - T0) * FPS))
rng = random.Random(25)

SITE = os.path.expanduser("~/Projects/nullplayer-site")
SITE_IMG = f"{SITE}/img"
CLIP = f"{SITE}/media/skins/holiday/modern-winamp-modern-holiday-2005.mp4"   # what the laptop on the mantle plays
SCRIPT = "/System/Library/Fonts/Supplemental/SnellRoundhand.ttc"
PAN0, PAN1, SHAKE0, POP, EMIT1, SNOW, FINALE = 5.0, 7.8, 10.0, 11.3, 15.0, 15.2, 15.6
WW = 2 * W                                       # the room; the camera pans from the fireplace (left) to the tree (right)
FX, TX = W // 2, W + W // 2                      # fireplace and tree centres, world x
MANTLE, HOOK_Y, FLOOR = 455, 500, 960
G = 1500                                         # px/s², the gift's lid and skins

# the five families as the site names them, each stocking's colours, and the holiday skins in it (centre first)
STOCKINGS = [
    ("Winamp Classic", (196, 30, 42), (250, 250, 246), False,
     ["classic-snoopy-christmas", "classic-santamp", "classic-a-charlie-brown-christmas"]),
    ("Winamp Modern", (30, 120, 62), (196, 30, 42), True,
     ["modern-magic-snow-globe", "modern-merrychristmas", "modern-revival1-0f"]),
    ("Windows Media Player", (196, 30, 42), (250, 250, 246), True,
     ["wmp-grinch", "wmp-holiday-skin", "wmp-ginger-man"]),
    ("Audion Faces", (30, 120, 62), (250, 250, 246), False, ["audion-christmas", "audion-byte-me"]),
    ("Lycos Sonique", (196, 30, 42), (30, 120, 62), True,                                   # one mode each: the gallery stills are every mode side by side
     ["media/skins/holiday/sonique-x-mas-navigator.webp", "media/skins/holiday/sonique-merryxmas-navigator.webp"]),
]

brand, BRAND_XY = brand(W)

# --- the room, static, at 2x then downsampled once
SS = 2

def B(*v):
    return tuple(int(x * SS) for x in v)

bg = Image.new("RGBA", (WW * SS, H * SS))
d = ImageDraw.Draw(bg)
for y in range(0, H * SS):                                                                 # deep red wall
    k = y / (H * SS)
    d.line([(0, y), (WW * SS, y)], fill=(int(128 - 40 * k), int(26 - 8 * k), int(34 - 10 * k), 255))
for x in range(40, WW, 80):                                                                # faint gold damask diamonds
    for y in range(40, 780, 80):
        o = 40 if (y // 80) % 2 else 0
        cx = x + o
        d.polygon(B(cx, y - 9, cx + 7, y, cx, y + 9, cx - 7, y), fill=(170, 110, 60, 60))
d.rectangle(B(0, 760, WW, FLOOR), fill=(74, 40, 26, 255))                                  # wainscot
for x in range(0, WW, 200):
    d.rectangle(B(x + 16, 780, x + 184, 940), outline=(56, 28, 18, 255), width=4 * SS)
d.rectangle(B(0, 752, WW, 764), fill=(96, 56, 36, 255))
d.rectangle(B(0, FLOOR, WW, H), fill=(122, 78, 44, 255))                                   # floor
for i, y in enumerate((975, 995, 1020, 1050)):
    d.line(B(0, y, WW, y), fill=(100, 62, 34, 255), width=3 * SS)
    for x in range(int(rng.uniform(0, 300)), WW, 420):
        d.line(B(x + i * 70, y, x + i * 70, y + 26), fill=(100, 62, 34, 255), width=2 * SS)

# window between the two halves: the night outside is in the wall, snow falls on it per frame, the frame goes on top
WIN = (W - 150, 340, W + 150, 740)
night = Image.new("RGBA", ((WIN[2] - WIN[0]) * SS, (WIN[3] - WIN[1]) * SS))
nd = ImageDraw.Draw(night)
for y in range(night.height):
    k = y / night.height
    nd.line([(0, y), (night.width, y)], fill=(int(18 + 30 * k), int(26 + 36 * k), int(64 + 50 * k), 255))
nd.ellipse(B(-120, 300, 360, 560), fill=(236, 242, 250, 255))                               # snowy hill
for x, s_ in ((70, 1.0), (220, 0.7)):                                                       # pines outside
    nd.polygon(B(x, 350 - 120 * s_, x - 40 * s_, 360, x + 40 * s_, 360), fill=(20, 54, 44, 255))
bg.paste(night, B(WIN[0], WIN[1]))
winframe = Image.new("RGBA", (WIN[2] - WIN[0] + 80, WIN[3] - WIN[1] + 80))                  # 40 px margin all round
wd = ImageDraw.Draw(winframe)
fw, fh = winframe.size
wd.rectangle((24, 24, fw - 24, fh - 24), outline=(240, 236, 226, 255), width=16)
wd.line((fw / 2, 40, fw / 2, fh - 40), fill=(240, 236, 226, 255), width=10)
wd.line((40, fh / 2, fw - 40, fh / 2), fill=(240, 236, 226, 255), width=10)
wd.rectangle((6, fh - 30, fw - 6, fh - 10), fill=(250, 248, 240, 255))                      # sill
WINC = ((WIN[0] + WIN[2]) / 2, (WIN[1] + WIN[3]) / 2)

# fireplace: brick surround, firebox (flames per frame), hearth, mantle with garland, candles and hooks
BRICK, MORTAR = (150, 70, 52, 255), (110, 56, 44, 255)
d.rectangle(B(FX - 540, 510, FX + 540, FLOOR), fill=MORTAR)
for r, y in enumerate(range(510, FLOOR, 36)):
    for x in range(FX - 540 - (r % 2) * 50, FX + 540, 100):
        sh = rng.randint(-14, 14)
        d.rectangle(B(max(x + 4, FX - 540), y + 4, min(x + 96, FX + 540), y + 32), fill=(150 + sh, 70 + sh // 2, 52 + sh // 3, 255))
FBOX = (FX - 180, 680, FX + 180, FLOOR)                                                    # arch-topped opening
d.rectangle(B(FBOX[0] - 16, 740, FBOX[2] + 16, FLOOR), fill=(70, 34, 26, 255))
d.ellipse(B(FBOX[0] - 16, FBOX[1] - 16, FBOX[2] + 16, 816), fill=(70, 34, 26, 255))
d.rectangle(B(FBOX[0], 740, FBOX[2], FLOOR), fill=(22, 14, 12, 255))
d.ellipse(B(FBOX[0], FBOX[1], FBOX[2], 800), fill=(22, 14, 12, 255))
d.rectangle(B(FX - 580, FLOOR - 10, FX + 580, FLOOR + 34), fill=(120, 118, 114, 255))      # hearth
d.rectangle(B(FX - 580, FLOOR + 30, FX + 580, FLOOR + 40), fill=(90, 88, 84, 255))
ML = 790                                                                                   # mantle half-width
d.rectangle(B(FX - ML, MANTLE, FX + ML, MANTLE + 38), fill=(92, 52, 30, 255))            # mantle shelf
d.rectangle(B(FX - ML, MANTLE, FX + ML, MANTLE + 8), fill=(120, 72, 42, 255))
d.rectangle(B(FX - ML + 50, MANTLE + 38, FX + ML - 50, MANTLE + 56), fill=(76, 42, 24, 255))
GARLAND = [(x, MANTLE + 40 + 18 * abs(math.sin(math.pi * (x - FX + ML) / 220))) for x in range(FX - ML, FX + ML + 1, 14)]
for x, y in GARLAND:
    for _ in range(3):
        r = rng.uniform(12, 18)
        gx, gy = x + rng.uniform(-6, 6), y + rng.uniform(-8, 6)
        d.ellipse(B(gx - r, gy - r, gx + r, gy + r), fill=(rng.randint(24, 44), rng.randint(84, 116), rng.randint(46, 64), 255))
for x in (FX - 370, FX + 370):                                                             # bows on the garland
    d.polygon(B(x, MANTLE + 50, x - 34, MANTLE + 30, x - 34, MANTLE + 70), fill=(196, 30, 42, 255))
    d.polygon(B(x, MANTLE + 50, x + 34, MANTLE + 30, x + 34, MANTLE + 70), fill=(196, 30, 42, 255))
    d.ellipse(B(x - 10, MANTLE + 40, x + 10, MANTLE + 60), fill=(160, 20, 30, 255))
CANDLES = [(FX + 722, 80), (FX + 766, 120)]                 # x, height
for x, h in CANDLES:
    d.rectangle(B(x - 16, MANTLE - h, x + 16, MANTLE), fill=(248, 240, 222, 255))
    d.ellipse(B(x - 16, MANTLE - h - 6, x + 16, MANTLE - h + 6), fill=(255, 250, 236, 255))
    d.line(B(x, MANTLE - h - 4, x, MANTLE - h - 14), fill=(40, 30, 20, 255), width=2 * SS)
LAP_W, LAP_H = 270, 170                                                                     # screen, outer
LAP_SCREEN = (FX - LAP_W / 2 + 10, MANTLE - 12 - LAP_H + 10, FX + LAP_W / 2 - 10, MANTLE - 12 - 14)
d.rounded_rectangle(B(FX - LAP_W / 2, MANTLE - 12 - LAP_H, FX + LAP_W / 2, MANTLE - 10), 12 * SS, fill=(28, 28, 32, 255), outline=(150, 152, 158, 255), width=2 * SS)
sx0, sy0, sx1, sy1 = LAP_SCREEN
desk = Image.new("RGBA", B(sx1 - sx0, sy1 - sy0))                                          # wallpaper: dusk hills
dd = ImageDraw.Draw(desk)
for y in range(desk.height):
    k = y / desk.height
    dd.line([(0, y), (desk.width, y)], fill=(int(40 + 180 * k), int(50 + 60 * k), int(130 - 40 * k), 255))
dd.ellipse(B(-80, sy1 - sy0 - 60, sx1 - sx0 + 80, sy1 - sy0 + 120), fill=(240, 130, 90, 255))
dd.ellipse(B(-40, sy1 - sy0 - 30, sx1 - sx0 + 140, sy1 - sy0 + 160), fill=(200, 80, 110, 255))
bg.alpha_composite(desk, B(sx0, sy0))
d.rectangle(B(sx0, sy0, sx1, sy0 + 7), fill=(236, 236, 240, 255))                           # menu bar
d.rounded_rectangle(B(FX - 70, sy1 - 20, FX + 70, sy1 - 4), 5 * SS, fill=(236, 236, 240, 170))   # dock
icon = Image.open(ICON).convert("RGBA").resize((12 * SS, 12 * SS), Image.LANCZOS)
for i, c in enumerate([(90, 160, 250), (250, 200, 60), None, (120, 220, 140), (236, 72, 140), (190, 130, 250)]):
    x = FX - 54 + i * 21
    if c is None:
        bg.alpha_composite(icon, B(x - 6, sy1 - 18))
    else:
        d.rounded_rectangle(B(x - 6, sy1 - 18, x + 6, sy1 - 6), 3 * SS, fill=c + (255,))
d.polygon(B(FX - LAP_W / 2 - 24, MANTLE - 12, FX + LAP_W / 2 + 24, MANTLE - 12, FX + LAP_W / 2 + 34, MANTLE, FX - LAP_W / 2 - 34, MANTLE), fill=(196, 198, 204, 255))
d.rectangle(B(FX - 30, MANTLE - 12, FX + 30, MANTLE - 8), fill=(160, 162, 168, 255))         # thumb notch
HOOKS = [FX - 700, FX - 480, FX - 260, FX + 260, FX + 540]                                # the laptop sits between
for x in HOOKS:
    d.rectangle(B(x - 5, MANTLE + 30, x + 5, HOOK_Y + 4), fill=(212, 170, 70, 255))
    d.ellipse(B(x - 8, HOOK_Y - 4, x + 8, HOOK_Y + 8), fill=(212, 170, 70, 255))

# the tree, tiers drawn bottom first so each upper tier overlaps the one below
TREE_TOP = 330

def tree_hw(y):
    return max(0, (y - TREE_TOP) / (FLOOR - TREE_TOP) * 470)

d.rectangle(B(TX - 34, 880, TX + 34, FLOOR + 6), fill=(92, 56, 30, 255))
for k in reversed(range(4)):
    ap, base, hw = TREE_TOP + 4 + k * 125, TREE_TOP + 250 + k * 125, 190 + k * 95
    for col, inset in (((18, 78, 44, 255), 0), ((26, 104, 56, 255), 10)):
        d.polygon(B(TX, ap + inset, TX - hw + inset, base - inset / 2, TX + hw - inset, base - inset / 2), fill=col)
        for x in range(int(TX - hw + inset), int(TX + hw - inset) + 1, 36):
            d.ellipse(B(x - 22, base - 24 - inset / 2, x + 22, base + 16 - inset / 2), fill=col)
    d.polygon(B(TX, ap + 30, TX + hw * 0.1, base - 30, TX + hw - 30, base - 10), fill=(22, 90, 50, 255))   # shade side

# the gifts round the hero gift (static), drawn on the floor in front of the tree
def gift(dr, f, x, bottom, w, h, box, ribbon, bow=True):
    dr.rectangle(f(x - w / 2, bottom - h, x + w / 2, bottom), fill=box)
    dr.rectangle(f(x - w / 2, bottom - h, x + w / 2, bottom - h + h * 0.08), fill=tuple(int(c * 0.82) for c in box[:3]) + (255,))
    dr.rectangle(f(x - w * 0.07, bottom - h, x + w * 0.07, bottom), fill=ribbon)
    if bow:
        for s in (-1, 1):
            dr.ellipse(f(x + s * w * 0.05 - w * 0.13, bottom - h - h * 0.24, x + s * w * 0.05 + w * 0.13, bottom - h + 4), outline=ribbon, width=int(10 * SS))

# the services NullPlayer works with (the site's logos), each a square box with its logo on the face
def logo(name):
    path = f"{SITE_IMG}/logos/{name}"
    data = subprocess.run(["rsvg-convert", "-w", "600", path], capture_output=True, check=True).stdout if name.endswith(".svg") else open(path, "rb").read()
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    return im.crop(im.getchannel("A").getbbox())

def logo_gift(name, x, bottom, s, rib):
    """Draws onto the gift layer (over the tree's lights and ornaments); returns the lid's top, for stacking."""
    d, bg = gd2, gifts
    side = s * 0.16
    d.polygon(B(x + s / 2, bottom - s, x + s / 2 + side, bottom - s - side * 0.6, x + s / 2 + side, bottom - side * 0.6, x + s / 2, bottom),
              fill=(206, 202, 194, 255))                                                    # right side
    d.rectangle(B(x - s / 2, bottom - s, x + s / 2, bottom), fill=(250, 248, 242, 255), outline=(190, 186, 178, 255), width=2 * SS)
    im = logo(name)
    k = min(s * 0.72 / im.width, s * 0.6 / im.height) * SS
    im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    bg.alpha_composite(im, (int(x * SS - im.width / 2), int((bottom - s * 0.44) * SS - im.height / 2)))
    lid, top, cx = s * 0.17, bottom - s - s * 0.17, x + s * 0.08                           # white lid, ribbon over it
    dark = tuple(int(c * 0.72) for c in rib) + (255,)
    d.polygon(B(x - s / 2 - 6, top, x + s / 2 + 6, top, x + s / 2 + 6 + side, top - side * 0.6, x - s / 2 - 6 + side, top - side * 0.6),
              fill=(226, 222, 214, 255))
    d.rectangle(B(x - s / 2 - 6, top, x + s / 2 + 6, bottom - s + 4), fill=(244, 242, 236, 255), outline=(190, 186, 178, 255), width=2 * SS)
    d.rectangle(B(x - s * 0.07, top, x + s * 0.07, bottom - s + 4), fill=rib + (255,))     # band down the lid's front
    d.polygon(B(cx - s * 0.07, top - side * 0.6, cx + s * 0.07, top - side * 0.6, x + s * 0.07, top, x - s * 0.07, top), fill=dark)
    ky = top - side * 0.3                                                                   # the bow's knot
    for sg in (-1, 1):
        d.polygon(B(cx, ky, cx + sg * s * 0.2, ky + s * 0.2, cx + sg * s * 0.13, ky + s * 0.2, cx + sg * s * 0.17, ky + s * 0.25,
                    cx + sg * s * 0.07, ky + s * 0.22), fill=dark)                          # notched tail
        pts = [(cx + sg * (s * 0.2 + s * 0.2 * math.cos(a)) * 0.98, ky - s * 0.07 + s * 0.11 * math.sin(a) - s * 0.06 * math.cos(a))
               for a in [math.pi * i / 16 for i in range(33)]]
        loop = [(cx, ky)] + [(cx + (px - cx) * min(1, abs(i - 16) / 6 + 0.35), py) for i, (px, py) in enumerate(pts)]
        d.polygon([B(*q) for q in loop], fill=rib + (255,))
        d.ellipse(B(cx + sg * s * 0.2 - s * 0.07, ky - s * 0.1, cx + sg * s * 0.2 + s * 0.05, ky - s * 0.03), fill=dark)   # the loop's opening
    d.ellipse(B(cx - s * 0.05, ky - s * 0.05, cx + s * 0.05, ky + s * 0.04), fill=rib + (255,), outline=dark, width=2 * SS)
    return bottom - s - lid

gifts = Image.new("RGBA", (WW * SS, H * SS))
gd2 = ImageDraw.Draw(gifts)
for name, dx, s, rib, top in (("youtube.svg", -650, 130, (230, 30, 30), ("sonos.svg", 100, (40, 40, 44))),
                              ("jellyfin.svg", -480, 150, (170, 92, 195), ("chromecast.svg", 96, (66, 133, 244))),
                              ("plex.svg", -295, 160, (229, 160, 13), None),
                              ("emby.webp", 300, 160, (82, 181, 75), None),
                              ("navidrome.webp", 485, 150, (0, 120, 230), ("airplay.svg", 96, (70, 70, 80))),
                              ("dlna.svg", 655, 130, (40, 170, 80), None)):
    lid = logo_gift(name, TX + dx, FLOOR + 66, s, rib)
    if top:                                                                                 # a smaller box stacked on it
        logo_gift(top[0], TX + dx + 6, lid + 2, top[1], top[2])
GIFTS_BOX = (TX - 800, 560, TX + 800, H)
gifts = gifts.resize((WW, H), Image.LANCZOS).crop(GIFTS_BOX)
# two framed pictures on the wall between the window and the tree: the Apple logo, and macOS's Finder face
def picture(cx, cy, w, h, art):
    x0, y0, x1, y1 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
    d.line(B(cx - w * 0.3, y0 + 4, cx, y0 - 40, cx + w * 0.3, y0 + 4), fill=(60, 50, 40, 255), width=2 * SS)   # wire on a nail
    d.ellipse(B(cx - 5, y0 - 45, cx + 5, y0 - 35), fill=(150, 150, 150, 255))
    d.rectangle(B(x0 + 8, y0 + 8, x1 + 8, y1 + 8), fill=(60, 12, 18, 255))                   # shadow on the wall
    d.rectangle(B(x0, y0, x1, y1), fill=(196, 150, 60, 255))                                 # gold frame, bevelled
    d.rectangle(B(x0 + 6, y0 + 6, x1 - 6, y1 - 6), fill=(230, 190, 90, 255))
    d.rectangle(B(x0 + 14, y0 + 14, x1 - 14, y1 - 14), fill=(150, 108, 36, 255))
    d.rectangle(B(x0 + 18, y0 + 18, x1 - 18, y1 - 18), fill=(246, 240, 226, 255))            # mat
    bg.alpha_composite(art, (int(cx * SS - art.width / 2), int(cy * SS - art.height / 2)))
    for k, (hx, hy) in enumerate(((x1 - 6, y0 + 6), (x1 - 22, y0 - 4))):                     # holly on the corner
        d.ellipse(B(hx - 20 + 18 * k, hy - 8, hx + 6 + 18 * k, hy + 10), fill=(30, 110, 50, 255))
    for bx, by in ((x1 - 10, y0 + 6), (x1 + 2, y0 + 10), (x1 - 4, y0 + 16)):
        d.ellipse(B(bx - 6, by - 6, bx + 6, by + 6), fill=(200, 24, 36, 255))

apple = Image.new("RGBA", B(120, 140))
ImageDraw.Draw(apple).text(B(60, 66), "\uf8ff", font=ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 120 * SS), fill=(46, 48, 54, 255), anchor="mm")
picture(W + 330, 470, 170, 210, apple)

fw = 112                                                                                     # Finder face: a two-tone rounded square
face = Image.new("RGBA", B(fw, fw))
fm = Image.new("L", face.size)
ImageDraw.Draw(fm).rounded_rectangle((0, 0, face.width - 1, face.height - 1), 26 * SS, fill=255)
fd = ImageDraw.Draw(face)
fd.rectangle((0, 0, face.width, face.height), fill=(136, 206, 250, 255))
fd.polygon(B(0, 0, fw * 0.56, 0, fw * 0.5, fw * 0.4, fw * 0.4, fw * 0.58, fw * 0.52, fw * 0.6, fw * 0.58, fw, 0, fw), fill=(30, 110, 230, 255))
for ex in (0.3, 0.72):                                                                       # eyes
    fd.rounded_rectangle(B(fw * ex - 3, fw * 0.24, fw * ex + 3, fw * 0.42), 3 * SS, fill=(20, 30, 60, 255))
fd.arc(B(fw * 0.18, fw * 0.36, fw * 0.84, fw * 0.8), 30, 150, fill=(20, 30, 60, 255), width=4 * SS)   # smile
face.putalpha(fm)
picture(W + 560, 540, 170, 170, face)

pw, ph = 330, 200                                                                            # a painting right of the tree: the subreddit
canvas = Image.new("RGBA", B(pw - 36, ph - 36), (24, 52, 66, 255))
pr = random.Random(7)
cdr = ImageDraw.Draw(canvas)
for _ in range(140):                                                                         # soft brush strokes
    x, y, ln, a = pr.uniform(0, canvas.width), pr.uniform(0, canvas.height), pr.uniform(30, 90) * SS, pr.uniform(-0.5, 0.5)
    v = pr.randint(-8, 12)
    cdr.line((x, y, x + ln * math.cos(a), y + ln * math.sin(a)), fill=(24 + v, 52 + v, 66 + v, 255), width=int(pr.uniform(5, 12) * SS))
sz = 62
while ImageFont.truetype("/System/Library/Fonts/MarkerFelt.ttc", sz * SS, index=1).getlength("r/nullplayer") > canvas.width * 0.86:
    sz -= 1
mf = ImageFont.truetype("/System/Library/Fonts/MarkerFelt.ttc", sz * SS, index=1)
tx, ty = canvas.width / 2, canvas.height / 2
cdr.text((tx + 3 * SS, ty + 4 * SS), "r/nullplayer", font=mf, fill=(10, 20, 26, 255), anchor="mm")                    # shadow
cdr.text((tx, ty), "r/nullplayer", font=mf, fill=(255, 69, 0, 255), anchor="mm", stroke_width=3 * SS, stroke_fill=(250, 236, 214, 255))
picture(TX + 690, 500, pw, ph, canvas)

bg = bg.resize((WW, H), Image.LANCZOS)

# --- skins
def load(path, fit_w, fit_h):
    im = Image.open(path).convert("RGBA")
    for c in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        if im.getpixel(c)[3] == 255 and min(im.getpixel(c)[:3]) > 220:                      # a light opaque margin, as in the site's clip stills
            ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=14)
    im = im.crop(im.getchannel("A").getbbox())
    k = min(fit_w / im.width, fit_h / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)

files = [l.strip() for l in open(LIST) if l.strip()]
rng.shuffle(files)
ORN_N = 30
ornaments_src = [f for f in files if 0.55 < (lambda s: s[0] / s[1])(Image.open(f).size) < 2.2][:ORN_N]
gift_src = [f for f in files if f not in ornaments_src]

# --- the laptop's skin, playing: the site's looping clip
def clip_frames():
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", CLIP, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], capture_output=True, check=True).stdout
    w, h = 708, 354
    out = []
    for i in range(len(raw) // (w * h * 4)):
        im = Image.frombytes("RGBA", (w, h), raw[i * w * h * 4:(i + 1) * w * h * 4])
        for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
            ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=24)
        k = (LAP_SCREEN[2] - LAP_SCREEN[0]) * 0.82 / w
        out.append(im.resize((int(w * k), int(h * k)), Image.LANCZOS))
    return out

CLIP_FRAMES = clip_frames()

# --- a side table in front of the window: gingerbread skins on a plate and a glass of milk (a sprite: it sits over the snow)
TABLE_C = (W, 1013)                                                                          # sprite centre, world: its top below the sill, the pedestal runs off the frame
table = Image.new("RGBA", (360 * SS, 400 * SS))

def T(*v):
    return tuple(int(c * SS) for c in v)

td = ImageDraw.Draw(table)
WOOD, WOOD_D = (110, 64, 36, 255), (78, 44, 24, 255)
td.polygon(T(170, 130, 190, 130, 200, 340, 160, 340), fill=WOOD_D)                           # pedestal
td.ellipse(T(110, 330, 250, 360), fill=WOOD_D)                                               # foot
td.ellipse(T(80, 360 - 30, 280, 390 - 30), fill=WOOD_D)
td.rectangle(T(70, 118, 290, 134), fill=WOOD_D)                                              # top edge
td.ellipse(T(70, 100, 290, 136), fill=WOOD)                                                  # top
td.ellipse(T(98, 104, 228, 128), fill=(250, 250, 246, 255), outline=(200, 200, 196, 255), width=2 * SS)   # plate
td.ellipse(T(118, 110, 208, 124), fill=(236, 236, 232, 255))
for sid, cx, cy, ang in (("wmp-ginger-woman", 142, 115, 25), ("wmp-ginger-man", 184, 119, -20)):   # lying flat on the plate
    im = load(f"{SITE_IMG}/{sid}@2x.webp", 70 * SS, 78 * SS).rotate(ang, Image.BICUBIC, expand=True)
    im = im.resize((im.width, int(im.height * 0.36)), Image.LANCZOS)                       # foreshortened: seen from a low angle
    table.alpha_composite(im, (int(cx * SS - im.width / 2), int(cy * SS - im.height / 2)))
gx, gb, gt, rb, rt = 254, 122, 34, 12, 18                                                    # glass: centre, bottom, top, half-widths
def gw(y):                                                                                   # the glass's half-width at y (it tapers down)
    return rb + (rt - rb) * (gb - y) / (gb - gt)
td.polygon(T(gx - rb, gb, gx + rb, gb, gx + rt, gt, gx - rt, gt), fill=(214, 232, 244, 80))  # see-through body
my = (gb + gt) / 2                                                                           # half full of milk
td.polygon(T(gx - rb + 1.5, gb - 3, gx + rb - 1.5, gb - 3, gx + gw(my) - 1.5, my, gx - gw(my) + 1.5, my), fill=(250, 250, 246, 255))
td.ellipse(T(gx - gw(my) + 1.5, my - 3, gx + gw(my) - 1.5, my + 3), fill=(255, 255, 252, 255), outline=(226, 226, 222, 255), width=SS)
td.ellipse(T(gx - rb, gb - 4, gx + rb, gb + 3), fill=(236, 240, 242, 255), outline=(170, 186, 198, 255), width=SS)   # thick base
td.line(T(gx - rb, gb, gx - rt, gt), fill=(170, 190, 204, 255), width=2 * SS)                # sides
td.line(T(gx + rb, gb, gx + rt, gt), fill=(170, 190, 204, 255), width=2 * SS)
td.ellipse(T(gx - rt, gt - 4, gx + rt, gt + 4), outline=(180, 198, 212, 255), width=2 * SS)  # rim
td.line(T(gx - rt + 5, gt + 8, gx - rb + 4, gb - 8), fill=(255, 255, 255, 210), width=3 * SS)   # highlights
td.line(T(gx + rt - 6, gt + 10, gx + rt - 7, gt + 26), fill=(255, 255, 255, 170), width=2 * SS)
table = table.resize((540, 600), Image.LANCZOS)                                             # 1.5x: it is nearer the camera

# --- a cat asleep on the hearth, curled up; it breathes per frame
CAT_C = (FX + 250, 1040)                                                                     # sprite's bottom centre, world: on the floor, beside the fire
cat = Image.new("RGBA", (300 * SS, 140 * SS))
cd_ = ImageDraw.Draw(cat)
FUR, FUR_D, FUR_L = (232, 146, 62, 255), (190, 104, 36, 255), (248, 196, 130, 255)
cd_.ellipse(T(30, 30, 250, 136), fill=FUR, outline=FUR_D, width=3 * SS)                       # curled body
for x in (90, 130, 170, 210):                                                                # stripes
    cd_.arc(T(x - 30, 34, x + 30, 110), 200, 290, fill=FUR_D, width=7 * SS)
cd_.ellipse(T(20, 96, 150, 138), fill=FUR, outline=FUR_D, width=3 * SS)                       # tail round the front
cd_.ellipse(T(118, 104, 148, 134), fill=FUR_L)                                               # tail tip
cd_.ellipse(T(190, 52, 286, 132), fill=FUR, outline=FUR_D, width=3 * SS)                      # head, tucked on the right
for e in ((200, 66, 214, 24, 236, 58), (244, 54, 270, 22, 278, 64)):                          # ears
    cd_.polygon(T(*e), fill=FUR, outline=FUR_D)
    cd_.polygon(T(e[0] + 6, e[1] - 2, e[2], e[3] + 12, e[4] - 6, e[5] - 2), fill=(246, 170, 160, 255))
for x in (218, 254):                                                                         # closed eyes
    cd_.arc(T(x - 10, 86, x + 10, 100), 20, 160, fill=(60, 30, 16, 255), width=3 * SS)
cd_.polygon(T(232, 102, 240, 102, 236, 107), fill=(220, 110, 120, 255))                      # nose
cd_.ellipse(T(196, 112, 236, 134), fill=FUR_L, outline=FUR_D, width=2 * SS)                   # paw under the chin
cat = cat.resize((300, 140), Image.LANCZOS)
ZFONT = ImageFont.truetype(HN, 30, index=1)

def zzz(dr, t, x, y):
    for k in range(3):
        u = (t * 0.45 + k / 3) % 1                                                           # each z drifts up and fades
        dr.text((x + 60 * u + 12 * math.sin(6 * u), y - 110 * u), "z", font=ImageFont.truetype(HN, int(20 + 24 * u), index=1),
                fill=(255, 255, 255, int(255 * math.sin(math.pi * u))))

# --- stockings: a static front sprite each (pivot at the hook), the skins behind it and the swing per frame
CW, CH, PIV, CUFF = 360, 680, (180, 260), 275

def stocking_front(name, body, trim, stripes):
    def S(*v):
        return tuple(int(x * SS) for x in v)
    size = (CW * SS, CH * SS)
    m = Image.new("L", size)
    md = ImageDraw.Draw(m)
    md.rounded_rectangle(S(100, 330, 260, 565), 60 * SS, fill=255)
    md.rectangle(S(100, 330, 260, 480), fill=255)
    md.ellipse(S(46, 480, 262, 604), fill=255)
    pat = Image.new("RGBA", size, body + (255,))
    pd = ImageDraw.Draw(pat)
    if stripes:
        for y in range(356, 620, 46):
            pd.rectangle(S(0, y, CW, y + 20), fill=trim + (255,))
    pd.ellipse(S(20, 470, 124, 616), fill=trim + (255,))                                    # toe
    pd.ellipse(S(212, 512, 300, 626), fill=trim + (255,))                                   # heel
    out = Image.new("RGBA", size)
    out.paste((60, 10, 16, 255), (0, 0), m.filter(ImageFilter.MaxFilter(7)))
    out.paste(pat, (0, 0), m)
    od = ImageDraw.Draw(out)
    od.line(S(180, 256, 180, 282), fill=(212, 170, 70, 255), width=6 * SS)                  # loop onto the hook
    cm = Image.new("L", size)                                                               # fluffy cuff
    cd = ImageDraw.Draw(cm)
    cd.rounded_rectangle(S(88, CUFF, 272, CUFF + 110), 16 * SS, fill=255)
    for x in range(92, 272, 16):
        for y in (CUFF + 2, CUFF + 108):
            cd.ellipse(S(x - 10, y - 10, x + 10, y + 10), fill=255)
    out.paste((120, 110, 104, 255), (0, 0), cm.filter(ImageFilter.MaxFilter(5)))
    out.paste((250, 250, 246, 255), (0, 0), cm)
    od.rounded_rectangle(S(92, CUFF + 96, 268, CUFF + 112), 8 * SS, fill=(228, 226, 220, 255))
    lines = name.split(" ", 1)                                                               # "Windows / Media Player"
    sz = 50
    while max(ImageFont.truetype(SCRIPT, sz * SS, index=1).getlength(l) for l in lines) > 168 * SS:
        sz -= 1
    for i, l in enumerate(lines):
        od.text(S(180, CUFF + 32 + i * 42), l, font=ImageFont.truetype(SCRIPT, sz * SS, index=1), fill=(178, 24, 36, 255), anchor="mm")
    return out.resize((CW, CH), Image.LANCZOS)

FANS = {1: [(0, 0)], 2: [(-48, 9), (48, -9)], 3: [(0, 0), (-52, 14), (52, -14)]}          # (x offset, degrees)
stockings = []
for i, (name, body, trim, stripes, ids) in enumerate(STOCKINGS):
    skins = []
    for j, (sid, (off, ang)) in enumerate(zip(ids, FANS[len(ids)])):
        fit = (190, 240) if off == 0 else (150, 200) if len(ids) == 3 else (215, 245)         # two to a stocking: room to be bigger
        im = load(f"{SITE}/{sid}" if "/" in sid else f"{SITE_IMG}/{sid}@2x.webp", *fit)
        skins.append(dict(im=im.rotate(ang, Image.BICUBIC, expand=True), off=off, ang=ang, h=im.height,
                          t=0.5 + 0.32 * i + 0.28 * (j if off == 0 else j + 0.4)))
    skins.sort(key=lambda s: s["off"] == 0)                                                 # centre skin in front
    stockings.append(dict(front=stocking_front(name, body, trim, stripes), skins=skins, x=HOOKS[i], ph=rng.uniform(0, 6)))

def backout(x):
    x = min(max(x, 0), 1) - 1
    return 1 + 2.4 * x ** 3 + 1.4 * x ** 2

def stocking(s, t):
    lay = Image.new("RGBA", (CW, CH))
    swing = 0.9 * math.sin(1.3 * t + s["ph"])
    for k in s["skins"]:
        dt = t - k["t"]
        if dt <= 0:
            continue
        u = backout(dt / 0.55)
        bx, by = PIV[0] + k["off"], CUFF + 20 + (1 - u) * (k["h"] + 30)
        a = math.radians(k["ang"] + 3 * math.sin(2 * t + k["off"]))
        paste(lay, k["im"], bx - math.sin(a) * k["h"] / 2, by - math.cos(a) * k["h"] / 2)
        swing += 5 * math.exp(-dt * 2.6) * math.sin(dt * 8)                                 # the stocking jolts as it pops
    lay.paste((0, 0, 0, 0), (0, CUFF + 18, CW, CH))                                         # what is inside the stocking
    lay.alpha_composite(s["front"])
    return lay.rotate(swing, Image.BICUBIC, center=PIV)

# --- ornaments: skins hung on the tree, each a pre-built canvas whose centre is its hanging point
ornaments = []
for f in ornaments_src:
    for _ in range(400):
        y = rng.uniform(430, 830)
        x = TX + rng.uniform(-1, 1) * tree_hw(y) * 0.8
        if all(math.hypot(x - o["x"], (y - o["y"]) * 1.3) > 100 for o in ornaments):
            break
    im = load(f, 84, 66)
    R = 18 + im.height + 2
    c = Image.new("RGBA", (2 * R, 2 * R))
    cd = ImageDraw.Draw(c)
    cd.line((R, R, R, R + 12), fill=(230, 210, 150, 255), width=2)
    cd.rounded_rectangle((R - 7, R + 10, R + 7, R + 18), 2, fill=(222, 180, 70, 255), outline=(150, 110, 40, 255))
    c.alpha_composite(im, (R - im.width // 2, R + 17))
    ornaments.append(dict(c=c, x=x, y=y, ph=rng.uniform(0, 6.3), sw=rng.uniform(1.6, 2.4)))

LIGHTS_COL = [(255, 70, 70), (255, 210, 60), (90, 200, 255), (120, 240, 120), (255, 130, 220)]
TREE_LIGHTS = []
for r in range(7):
    y0 = 400 + r * 82
    for q in [i / 14 for i in range(15)]:
        y = y0 + 34 * q + 22 * math.sin(math.pi * q)
        hw = tree_hw(y) * 0.92
        TREE_LIGHTS.append((TX - hw + 2 * hw * q, y, LIGHTS_COL[(r + int(q * 14)) % 5], rng.uniform(0, 6.3)))
MANTLE_LIGHTS = [(x, y + 4, LIGHTS_COL[i % 5], rng.uniform(0, 6.3)) for i, (x, y) in enumerate(GARLAND[::3])]
WINDOW_SNOW = [(rng.uniform(WIN[0], WIN[2]), rng.uniform(0, 400), rng.uniform(40, 90), rng.uniform(1.5, 3.5), rng.uniform(0, 6.3)) for _ in range(90)]

def lights(dr, gd, pts, t, x0, r):
    for x, y, c, p in pts:
        sx = x - x0
        if -10 < sx < W + 10:
            b = 0.55 + 0.45 * math.sin(3.2 * t + p)
            g = r * 2.6
            gd.ellipse((sx - g, y - g, sx + g, y + g), fill=c + (int(90 * b),))
            dr.ellipse((sx - r, y - r, sx + r, y + r), fill=tuple(int(v * (0.6 + 0.4 * b)) for v in c) + (255,))

# --- fire
def flames(t):
    w, h = FBOX[2] - FBOX[0], FBOX[3] - FBOX[1]
    lay = Image.new("RGBA", (w * SS, h * SS))
    ld = ImageDraw.Draw(lay)
    for scale, col in ((1.0, (220, 60, 20, 255)), (0.72, (255, 140, 30, 255)), (0.45, (255, 226, 110, 255))):
        for k in range(7):
            bx = 40 + k * 46
            ht = (120 + 50 * math.sin(7.3 * t + k * 1.7) + 26 * math.sin(13.1 * t + k)) * scale
            hw = (34 + 6 * math.sin(5 * t + k)) * scale
            sway = 16 * math.sin(4.1 * t + k * 2.3)
            by = h - 50
            pts = [(bx + sway * q * q + s * hw * (1 - q) ** 0.8, by - ht * q) for s in (-1, 1) for q in ([i / 10 for i in range(11)][::s])]
            ld.polygon([(x * SS, y * SS) for x, y in pts], fill=col)
            ld.ellipse(((bx - hw) * SS, (by - hw * 0.8) * SS, (bx + hw) * SS, (by + hw * 0.6) * SS), fill=col)
    for x0, x1, y in ((40, 330, h - 48), (70, 300, h - 30)):                                 # logs in front
        ld.rounded_rectangle((x0 * SS, y * SS, x1 * SS, (y + 26) * SS), 13 * SS, fill=(84, 50, 30, 255), outline=(50, 28, 16, 255), width=3 * SS)
    lay = lay.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    m = Image.new("L", (w, h))
    md = ImageDraw.Draw(m)
    md.rectangle((0, 60, w, h), fill=255)
    md.ellipse((0, 0, w, 120), fill=255)
    lay.putalpha(Image.composite(lay.getchannel("A"), Image.new("L", (w, h)), m))
    return lay

glow = Image.new("RGBA", (1600, 900))
ImageDraw.Draw(glow).ellipse((300, 200, 1300, 800), fill=(255, 150, 60, 70))
glow = glow.filter(ImageFilter.GaussianBlur(140))

def halo(w, h, col, blur):
    im = Image.new("RGBA", (w + 4 * blur, h + 4 * blur))
    ImageDraw.Draw(im).ellipse((2 * blur, 2 * blur, 2 * blur + w, 2 * blur + h), fill=col)
    return im.filter(ImageFilter.GaussianBlur(blur))

STAR_GLOW, BURST = halo(150, 150, (255, 230, 120, 120), 22), halo(560, 300, (255, 240, 170, 200), 50)

# --- the hero gift: a box and a lid, shaken, then the lid flies off and the skins burst out
GX, GB, GWD, GHT = TX, FLOOR + 70, 300, 190
BOX, RIB = (196, 30, 42, 255), (240, 200, 70, 255)
gift_skins = []
for k, f in enumerate(gift_src):
    q = (k / max(1, len(gift_src) - 1)) ** 1.35                                             # a burst, then a trickle
    gift_skins.append(dict(im=load(f, 230, 190), t=POP + 0.05 + (EMIT1 - POP) * q, vx=rng.uniform(-760, 760),
                           vy=rng.uniform(-1750, -1150), rot=rng.uniform(-20, 20), vr=rng.uniform(-90, 90)))
gift_skins.reverse()                                                                         # earliest drawn on top

def hero(dr, t, x0):
    sh = smooth((t - SHAKE0) / 0.3) * (t < POP)
    jx = 7 * math.sin(55 * t) * sh * (1 + (t - SHAKE0))
    hop = 22 * abs(math.sin(9 * (t - SHAKE0))) * sh
    x = GX - x0 + jx
    f = lambda *v: tuple(int(c) for c in v)
    gift(dr, f, x, GB, GWD, GHT, BOX, RIB, bow=False)
    top = GB - GHT
    if t >= POP:
        dr.rectangle(f(x - GWD / 2 + 6, top - 4, x + GWD / 2 - 6, top + 14), fill=(90, 10, 18, 255))   # open top
        dt = t - POP
        lx, ly, a = x + 520 * dt, top - 14 - 1500 * dt + G * dt * dt / 2, 300 * dt
    else:
        lx, ly, a = x, top - 14 - hop, 0
    if ly < H + 200:
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        def rp(px, py):
            return (lx + px * ca - py * sa, ly + px * sa + py * ca)
        dr.polygon([rp(*p) for p in ((-GWD / 2 - 14, -22), (GWD / 2 + 14, -22), (GWD / 2 + 14, 22), (-GWD / 2 - 14, 22))], fill=(170, 22, 34, 255))
        dr.polygon([rp(*p) for p in ((-22, -22), (22, -22), (22, 22), (-22, 22))], fill=RIB)
        for s in (-1, 1):                                                                    # the bow
            dr.polygon([rp(*p) for p in ((0, -18), (s * 64, -70), (s * 74, -20))], fill=RIB, outline=(190, 150, 40, 255))
        cx, cy = rp(0, -22)
        dr.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=(220, 176, 50, 255))

# --- finale: snow over everything, and the caption
FLAKES = [(rng.uniform(0, W), rng.uniform(-H, 0), rng.uniform(90, 200), rng.uniform(2, 6), rng.uniform(0, 6.3)) for _ in range(420)]
cap = Image.new("RGBA", (1900, 460))
cd = ImageDraw.Draw(cap)
cd.text((950, 160), "Happy Holidays", font=ImageFont.truetype(SCRIPT, 190, index=2), fill=(178, 24, 36, 255), anchor="mm")
cap = cap.crop(cap.getbbox())
caption = plate(cap.size, 120, 100, 230, 55)
caption.alpha_composite(cap, (120, 120))

ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-"]
                      + (["-ss", str(ASTART + T0), "-t", str(SECS - T0), "-i", AUDIO,
                          "-af", f"afade=in:d=0.1,afade=out:st={SECS - T0 - 2}:d=2", "-c:a", "aac", "-b:a", "256k"] if AUDIO else [])
                      + ["-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         "-t", str(N / FPS), OUT], stdin=subprocess.PIPE)

for n in range(N):
    t = T0 + n / FPS
    x0 = int(W * smooth((t - PAN0) / (PAN1 - PAN0)))
    fr = bg.crop((x0, 0, x0 + W, H))
    dr = ImageDraw.Draw(fr)
    gl = Image.new("RGBA", (W, H))                                  # translucent glows, composited before what sits on them
    gd = ImageDraw.Draw(gl)
    if WIN[0] - x0 < W and WIN[2] - x0 > 0:                                                  # snow outside the window
        for x, y, v, r, p in WINDOW_SNOW:
            yy = WIN[1] + (y + v * t) % (WIN[3] - WIN[1])
            xx = x + 8 * math.sin(t + p) - x0
            dr.ellipse((xx - r, yy - r, xx + r, yy + r), fill=(255, 255, 255, 255))
        paste(fr, winframe, WINC[0] - x0, WINC[1])
    if FX + 800 - x0 > 0:                                                                     # the fireplace side
        flick = 0.8 + 0.2 * math.sin(11 * t) * math.sin(3.7 * t)
        paste(fr, fade(glow, flick), FX - x0, 830)
        paste(fr, flames(t), (FBOX[0] + FBOX[2]) / 2 - x0, (FBOX[1] + FBOX[3]) / 2)
        for x, h in CANDLES:
            fx, fy = x - x0, MANTLE - h - 24 + 2 * math.sin(17 * t + x)
            gd.ellipse((fx - 16, fy - 22, fx + 16, fy + 20), fill=(255, 200, 80, 70))
            dr.ellipse((fx - 6, fy - 12, fx + 6, fy + 10), fill=(255, 210, 90, 255))
            dr.ellipse((fx - 3, fy - 4, fx + 3, fy + 8), fill=(255, 250, 220, 255))
        lights(dr, gd, MANTLE_LIGHTS, t, x0, 5)
        paste(fr, CLIP_FRAMES[int(t * 30) % len(CLIP_FRAMES)], FX - x0, (LAP_SCREEN[1] + LAP_SCREEN[3]) / 2 - 4)
        fr.alpha_composite(gl)
        gl = Image.new("RGBA", (W, H))
        gd = ImageDraw.Draw(gl)
        for s in stockings:
            paste(fr, stocking(s, t), s["x"] - PIV[0] + CW / 2 - x0, HOOK_Y - PIV[1] + CH / 2)
        b = 1 + 0.035 * math.sin(2 * math.pi * t / 2.6)                                       # the cat breathing
        c = cat.resize((cat.width, int(cat.height * b)), Image.BICUBIC)
        paste(fr, c, CAT_C[0] - x0, CAT_C[1] - c.height / 2)
        zl = Image.new("RGBA", (200, 180))
        zzz(ImageDraw.Draw(zl), t, 30, 160)
        paste(fr, zl, CAT_C[0] + 150 - x0, CAT_C[1] - 120 - 90)
    paste(fr, table, TABLE_C[0] - x0, TABLE_C[1])
    if TX - 700 - x0 < W:                                                                     # the tree side
        lights(dr, gd, TREE_LIGHTS, t, x0, 5)
        sx, sy, tw = TX - x0, TREE_TOP - 4, 1 + 0.12 * math.sin(4 * t)                        # star
        fr.alpha_composite(gl)
        paste(fr, fade(STAR_GLOW, 0.75 + 0.25 * math.sin(4 * t)), sx, sy)
        if t >= POP:                                                                          # light bursting from the box
            paste(fr, fade(BURST, math.exp(-(t - POP) * 1.6)), GX - x0, GB - GHT - 70)
        for o in ornaments:
            if -100 < o["x"] - x0 < W + 100:
                paste(fr, o["c"].rotate(6 * math.sin(o["sw"] * t + o["ph"]), Image.BICUBIC), o["x"] - x0, o["y"])
        dr.polygon([(sx + (44 if k % 2 == 0 else 18) * math.sin(math.pi * k / 5), sy - (44 if k % 2 == 0 else 18) * math.cos(math.pi * k / 5))
                    for k in range(10)], fill=(255, 210, 60, 255), outline=(200, 150, 30, 255))
        paste(fr, gifts, (GIFTS_BOX[0] + GIFTS_BOX[2]) / 2 - x0, (GIFTS_BOX[1] + GIFTS_BOX[3]) / 2)
        hero(dr, t, x0)
        for s in gift_skins:
            dt = t - s["t"]
            if dt < 0:
                continue
            y = GB - GHT + s["vy"] * dt + G * dt * dt / 2
            if y > H + 260:
                continue
            k = 0.22 + 0.78 * ease(dt / 0.8)
            im = s["im"].resize((max(1, int(s["im"].width * k)), max(1, int(s["im"].height * k))), Image.BILINEAR)
            paste(fr, im.rotate(s["rot"] + s["vr"] * dt, Image.BICUBIC, expand=True), GX - x0 + s["vx"] * dt, y)
    fr.alpha_composite(brand, BRAND_XY)

    if t > SNOW:
        dt = t - SNOW
        for x, y, v, r, p in FLAKES:
            yy = y + v * dt * 2.2
            if 0 < yy < H + 10:
                xx = x + 26 * math.sin(dt * 1.3 + p)
                dr.ellipse((xx - r, yy - r, xx + r, yy + r), fill=(255, 255, 255, 255))
    if t > FINALE:
        k = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * k)), int(caption.height * (0.9 + 0.1 * k))), Image.LANCZOS)
        paste(fr, fade(c, k), W / 2, 600)
    ff.stdin.write(fr.tobytes())
    if n % 100 == 0:
        print(f"{t:.1f}s", file=sys.stderr)
ff.stdin.close()
if ff.wait():
    sys.exit("ffmpeg failed")
