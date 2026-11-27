# microscope.py <out.mp4> <skins.txt> [audio] [audio_start_s] — a robot scientist with a Claude-spark head sets a petri dish on a microscope's stage,
# the camera dives into the eyepiece, and every skin in skins.txt (one sweep shot per line) is swimming around the
# culture like a microbe, flagellum and all, while the magnification ramps up. The camera pulls back out to the lab;
# logo + url and finale caption as in the cake, piñata and hippo promos.
# Media (shots list, audio, output) lives in ~/Documents/shots/promo-kit/microscope, not in the repo.
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from promo_common import HN, brand, ease, fade, paste, plate, smooth

OUT, LIST = sys.argv[1], sys.argv[2]
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
ASTART = float(sys.argv[4]) if len(sys.argv) > 4 else 0
W, H, FPS, SECS = 1920, 1080, 50, 20
T0 = float(os.environ.get("START", 0))           # render from this second on (stills for checking a beat)
N = min(int(os.environ.get("FRAMES", FPS * SECS)), int((SECS - T0) * FPS))
rng = random.Random(35)

REACH0, REACH1, LET, ZIN0, ZIN1, IRIS0, IRIS1, FOCUS = 0.5, 2.1, 2.5, 2.7, 4.0, 4.2, 4.8, 5.8
MAG0, MAG1, MAGB0, MAGB1, CLOSE0, CLOSE1, ZOUT0, ZOUT1, FINALE = 6.2, 9.2, 12.2, 13.4, 13.8, 14.3, 14.3, 15.3, 15.2
EYE = (952, 300)                                 # eyepiece top, world: what the camera dives into
ZOOM, EYE_AT = 7, 520                            # dive depth, and the screen y the eyepiece ends at
STAGE = (820, 688)                               # where the dish's centre sits on the stage
SHOULDER, ARM = (1290, 520), 240
CERTIFIED, VERSION = 500, "0.35.2"

# --- logo (same look as the other promos)
brand, BRAND_XY = brand(W)

# --- the lab, in world space at JS x so the dive into the eyepiece stays sharp
JS = 3

def J(*v):
    return tuple(int(x * JS) for x in v)

bg = Image.new("RGBA", (W * JS, H * JS))
d = ImageDraw.Draw(bg)
for y in range(H * JS):                                                                    # mint wall
    k = y / (H * JS)
    d.line([(0, y), (W * JS, y)], fill=(int(228 - 30 * k), int(238 - 24 * k), int(234 - 26 * k), 255))
lr = random.Random(4)
LIQ = [(236, 72, 140), (90, 200, 250), (120, 220, 140), (255, 190, 60), (190, 130, 250), (255, 120, 80)]
GLASS, GLASS_E = (226, 240, 246, 255), (130, 160, 175, 255)

def flask(dr, x, base, h, col):
    w = h * 0.42
    neck = [(x - w * 0.18, base - h), (x + w * 0.18, base - h)]
    body = [neck[0], (x - w * 0.18, base - h * 0.6), (x - w, base), (x + w, base), (x + w * 0.18, base - h * 0.6), neck[1]]
    dr.polygon([J(*p) for p in body], fill=GLASS, outline=GLASS_E, width=3 * JS)
    lv = 0.35
    dr.polygon(J(x - w * (1 - lv * 0.95), base - h * lv, x + w * (1 - lv * 0.95), base - h * lv, x + w - 4, base - 3, x - w + 4, base - 3), fill=col + (255,))
    dr.rectangle(J(x - w * 0.25, base - h - 8, x + w * 0.25, base - h + 2), fill=GLASS_E)

def beaker(dr, x, base, w, h, col):
    dr.rectangle(J(x - w / 2, base - h, x + w / 2, base), fill=GLASS, outline=GLASS_E, width=3 * JS)
    dr.rectangle(J(x - w / 2 + 4, base - h * 0.5, x + w / 2 - 4, base - 3), fill=col + (255,))
    for k in range(1, 4):
        dr.line(J(x - w / 2 + 4, base - h * k / 4, x - w / 2 + 16, base - h * k / 4), fill=GLASS_E, width=2 * JS)

for x0, x1 in [(40, 640), (1500, 1880)]:                                                   # shelves of glassware
    d.rectangle(J(x0, 300, x1, 318), fill=(180, 150, 112, 255))
    d.rectangle(J(x0, 318, x1, 326), fill=(150, 120, 88, 255))
    x = x0 + 50
    while x < x1 - 40:
        if lr.random() < 0.55:
            flask(d, x, 300, lr.uniform(80, 130), lr.choice(LIQ))
        else:
            beaker(d, x, 300, lr.uniform(40, 60), lr.uniform(60, 100), lr.choice(LIQ))
        x += lr.uniform(80, 120)
d.rectangle(J(60, 420, 440, 700), fill=(250, 250, 246, 255), outline=(150, 160, 160, 255), width=4 * JS)   # periodic-ish chart
for i in range(6):
    for j in range(9):
        d.rectangle(J(80 + j * 39, 440 + i * 42, 112 + j * 39, 474 + i * 42), fill=LIQ[(i + j) % 6] + (110,))

# the robot scientist, behind the bench: body and far arm here; the Claude-spark head and the reaching arm are per frame
METAL, METAL_D, METAL_E = (206, 212, 220, 255), (168, 176, 188, 255), (70, 78, 90, 255)
d.rounded_rectangle(J(1240, 490, 1500, 1000), 50 * JS, fill=METAL, outline=METAL_E, width=5 * JS)
d.rounded_rectangle(J(1290, 560, 1450, 700), 18 * JS, fill=(44, 50, 60, 255), outline=METAL_E, width=4 * JS)   # chest panel
for i, c in enumerate([(120, 220, 140), (255, 190, 60), (236, 72, 140)]):
    d.ellipse(J(1310 + i * 46, 584, 1338 + i * 46, 612), fill=c + (255,))
for i in range(5):                                                                         # equaliser bars
    hgt = (30, 52, 40, 60, 24)[i]
    d.rectangle(J(1312 + i * 26, 680 - hgt, 1330 + i * 26, 680), fill=(90, 200, 250, 255))
for x, y in [(1262, 512), (1478, 512), (1262, 800), (1478, 800)]:                         # bolts
    d.ellipse(J(x - 7, y - 7, x + 7, y + 7), fill=METAL_D, outline=METAL_E, width=2 * JS)
d.rounded_rectangle(J(1475, 520, 1535, 800), 30 * JS, fill=METAL_D, outline=METAL_E, width=4 * JS)   # far arm
for y in (600, 680):
    d.line(J(1478, y, 1532, y), fill=METAL_E, width=3 * JS)
d.rectangle(J(1340, 440, 1400, 494), fill=METAL_D, outline=METAL_E, width=4 * JS)          # neck
for y in (456, 474):
    d.line(J(1340, y, 1400, y), fill=METAL_E, width=3 * JS)

d.rectangle(J(0, 830, W, 872), fill=(196, 150, 100, 255))                                 # bench top
for y in (840, 852, 862):
    d.line(J(0, y, W, y + 4), fill=(180, 134, 88, 255), width=2 * JS)
d.rectangle(J(0, 872, W, H), fill=(90, 100, 108, 255))                                    # cabinet
for x in range(0, W, 320):
    d.rectangle(J(x + 14, 890, x + 306, H + 10), outline=(70, 80, 88, 255), width=4 * JS)
    d.rounded_rectangle(J(x + 140, 910, x + 180, 922), 6 * JS, fill=(200, 205, 210, 255))
flask(d, 330, 830, 170, (120, 220, 140))
beaker(d, 470, 830, 70, 110, (90, 200, 250))
for i in range(5):                                                                         # test-tube rack
    x = 1600 + i * 44
    d.rounded_rectangle(J(x, 690, x + 26, 820), 13 * JS, fill=GLASS, outline=GLASS_E, width=2 * JS)
    d.rounded_rectangle(J(x + 3, 760 - i * 8, x + 23, 817), 10 * JS, fill=LIQ[i] + (255,))
d.rectangle(J(1580, 740, 1830, 760), fill=(150, 120, 88, 255))
d.rectangle(J(1580, 810, 1830, 830), fill=(150, 120, 88, 255))

# the microscope, side on: arm at the back (right), stage poking left, eyepiece tilted up toward the scientist
BODY, BODY_D, DARK, CHROME = (244, 242, 236, 255), (210, 206, 196, 255), (52, 56, 64, 255), (190, 196, 204, 255)
d.rounded_rectangle(J(660, 790, 1040, 832), 18 * JS, fill=BODY, outline=DARK, width=4 * JS)     # base
d.ellipse(J(785, 740, 855, 770), fill=(255, 236, 150, 255), outline=DARK, width=3 * JS)          # lamp
d.line([J(*p) for p in [(985, 800), (1000, 700), (990, 600), (960, 500), (920, 430)]], fill=DARK, width=78 * JS, joint="curve")
d.line([J(*p) for p in [(985, 800), (1000, 700), (990, 600), (960, 500), (920, 430)]], fill=BODY, width=66 * JS, joint="curve")
d.rectangle(J(690, 698, 1000, 722), fill=DARK)                                                   # stage
d.rectangle(J(694, 700, 996, 716), fill=(70, 76, 86, 255))
for x in (720, 900):                                                                             # stage clips
    d.rectangle(J(x - 30, 690, x + 30, 698), fill=CHROME, outline=DARK, width=2 * JS)
d.ellipse(J(970, 610, 1040, 680), fill=CHROME, outline=DARK, width=4 * JS)                       # focus knobs
d.ellipse(J(988, 628, 1022, 662), fill=BODY_D, outline=DARK, width=3 * JS)
d.polygon(J(770, 560, 900, 560, 880, 600, 790, 600), fill=CHROME, outline=DARK, width=4 * JS)    # nosepiece
d.polygon(J(800, 600, 840, 600, 834, 652, 806, 652), fill=DARK)                                  # objectives
d.rectangle(J(808, 646, 832, 658), fill=(200, 60, 60, 255))
d.polygon(J(770, 590, 790, 600, 760, 640, 744, 630), fill=(80, 86, 96, 255))
d.polygon(J(880, 590, 860, 600, 884, 636, 900, 626), fill=(80, 86, 96, 255))
d.rounded_rectangle(J(780, 430, 930, 565), 22 * JS, fill=BODY, outline=DARK, width=4 * JS)       # head
d.line([J(860, 450), J(EYE[0], EYE[1] + 12)], fill=DARK, width=58 * JS)                          # eyepiece tube
d.line([J(860, 450), J(EYE[0], EYE[1] + 12)], fill=BODY_D, width=48 * JS)
ex, ey = EYE
d.polygon(J(ex - 40, ey - 22, ex + 12, ey + 40, ex + 32, ey + 22, ex - 20, ey - 40), fill=DARK)  # eyepiece cap
d.ellipse(J(ex - 34, ey - 34, ex + 26, ey + 26), fill=(30, 32, 38, 255))
d.ellipse(J(ex - 22, ey - 22, ex + 14, ey + 14), fill=(110, 160, 200, 255))

# --- the dish (side on, held or on the stage) with the culture as coloured specks
SPECKS = [(rng.uniform(-48, 48), rng.uniform(-14, -6), rng.choice(LIQ)) for _ in range(40)]

def dish(dr, f, s, cx, cy):
    def q(x, y):
        return f(cx + x, cy + y)
    dr.rounded_rectangle((*q(-62, -14), *q(62, 2)), int(6 * s), fill=(214, 234, 244, 200), outline=GLASS_E, width=max(1, int(3 * s)))
    dr.rectangle((*q(-56, -10), *q(56, -1)), fill=(242, 222, 150, 255))
    for x, y, c in SPECKS:
        dr.ellipse((*q(x - 2.5, y - 2), *q(x + 2.5, y + 2)), fill=c + (255,))
    dr.ellipse((*q(-64, -22), *q(64, -10)), outline=GLASS_E, width=max(1, int(3 * s)))
    dr.line((*q(-40, -18), *q(10, -18)), fill=(255, 255, 255, 220), width=max(1, int(3 * s)))

def hand_and_dish(t):
    """World hand position, and the dish centre (None once it is on the stage and let go)."""
    rest = (1210, 650)
    hold = (rest[0] - 46, rest[1] + 2)
    if t < LET:
        u = ease((t - REACH0) / (REACH1 - REACH0))
        dx, dy = hold[0] + (STAGE[0] - hold[0]) * u, hold[1] + (STAGE[1] - hold[1]) * u - 90 * math.sin(math.pi * u)
        return (dx + 46, dy - 2), (dx, dy)
    u = smooth((t - LET) / 0.6)                                      # let go, back to rest
    hx, hy = STAGE[0] + 46, STAGE[1] - 2
    return (hx + (rest[0] - hx) * u, hy + (rest[1] - hy) * u), None

CLAUDE = (217, 119, 87, 255)
RAYS = [(rng.uniform(-0.12, 0.12), rng.uniform(0.72, 1.0)) for _ in range(12)]

def spark(dr, f, cx, cy, R, rot):
    """The Claude spark: tapered rounded rays round a centre, `rot` degrees turned."""
    for i, (jit, ln) in enumerate(RAYS):
        a = math.radians(rot) + 2 * math.pi * i / len(RAYS) + jit
        ux, uy, px, py = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
        tip, wb, wt = R * ln, R * 0.2, R * 0.11
        pts = [(cx + px * wb, cy + py * wb), (cx + ux * tip + px * wt, cy + uy * tip + py * wt),
               (cx + ux * tip - px * wt, cy + uy * tip - py * wt), (cx - px * wb, cy - py * wb)]
        dr.polygon([f(*q) for q in pts], fill=CLAUDE)
        x, y = f(cx + ux * tip, cy + uy * tip)
        r = abs(f(cx + wt, cy)[0] - f(cx, cy)[0])
        dr.ellipse((x - r, y - r, x + r, y + r), fill=CLAUDE)
    x, y = f(cx, cy)
    r = abs(f(cx + R * 0.16, cy)[0] - f(cx, cy)[0])
    dr.ellipse((x - r, y - r, x + r, y + r), fill=CLAUDE)

def elbow(s, h, L):
    dx, dy = h[0] - s[0], h[1] - s[1]
    dd = min(math.hypot(dx, dy), 2 * L - 1)
    a, b = math.atan2(dy, dx), math.acos(dd / (2 * L))
    return max(((s[0] + L * math.cos(a + k), s[1] + L * math.sin(a + k)) for k in (b, -b)), key=lambda p: p[1])

# --- camera into the eyepiece: same shape as the hippo's rump zoom
def cam(t):
    u = smooth((t - ZIN0) / (ZIN1 - ZIN0)) - smooth((t - ZOUT0) / (ZOUT1 - ZOUT0))
    z = 1 + (ZOOM - 1) * u ** 2
    f = (W / 2 + (EYE[0] - W / 2) * u, H / 2 + (EYE[1] - H / 2) * u)
    a = (W / 2 + (EYE[0] - W / 2) * u, H / 2 + (EYE_AT - H / 2) * u)          # where f lands on screen, below the logo
    x0 = min(max(f[0] - a[0] / z, 0), W - W / z)                              # the crop stays inside the scene
    y0 = min(max(f[1] - a[1] / z, 0), H - H / z)
    view = tuple(v * JS for v in (x0, y0, x0 + W / z, y0 + H / z))
    return lambda x, y: ((x - x0) * z, (y - y0) * z), z, view

def lab(t):
    to, z, view = cam(t)
    fr = bg.resize((W, H), Image.BICUBIC, box=view)
    ss = 2                                                           # dynamic layer drawn at 2x for antialiasing
    lay = Image.new("RGBA", (W * ss, H * ss))
    ld = ImageDraw.Draw(lay)
    f = lambda x, y: tuple(v * ss for v in to(x, y))
    s = z * ss
    happy = t > ZOUT0
    spin = 25 * t + (260 * (t - ZOUT0) if happy else 0)             # idles round; spins with joy at the end
    bob = 10 * abs(math.sin(9 * (t - ZOUT0))) if happy else 0
    spark(ld, f, 1370, 375 - bob, 95, spin)
    h, dc = hand_and_dish(t)
    if dc is None:
        dish(ld, f, s, *STAGE)
    e = elbow(SHOULDER, h, ARM)
    for wdt, col in ((50, METAL_E), (40, METAL_D)):                 # metal arm: outline, then plate
        ld.line([f(*SHOULDER), f(*e), f(*h)], fill=col, width=int(wdt * s), joint="curve")
        for p in (SHOULDER, e):
            r = wdt / 2 * s
            ld.ellipse((f(*p)[0] - r, f(*p)[1] - r, f(*p)[0] + r, f(*p)[1] + r), fill=col)
    if dc is not None:
        dish(ld, f, s, *dc)
    for p in (SHOULDER, e):                                          # joints
        x, y = f(*p)
        ld.ellipse((x - 16 * s, y - 16 * s, x + 16 * s, y + 16 * s), fill=METAL, outline=METAL_E, width=int(4 * s))
    for k in (-1, 1):                                                # claw: two fingers either side of the dish rim
        ld.line([f(*h), f(h[0] - 14, h[1] + 22 * k), f(h[0] - 34, h[1] + 16 * k)], fill=METAL_E, width=int(10 * s), joint="curve")
    x, y = f(*h)
    ld.ellipse((x - 18 * s, y - 18 * s, x + 18 * s, y + 18 * s), fill=METAL, outline=METAL_E, width=int(4 * s))
    fr.alpha_composite(lay.resize((W, H), Image.LANCZOS))
    black = smooth((t - (ZIN1 - 0.5)) / 0.5) * (1 - smooth((t - ZOUT0) / 0.5))
    if black > 0:
        fr.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * black))))
    return fr

# --- the culture: skins swimming in a disc of radius DR (world units), seen through a circular field of view
DR, SW = 1100, 60                                # dish radius, and a skin's longer side in world units
CC, RC = (W / 2, 690), 370                       # field of view on screen
M_LO, M_HI = RC / DR, 2.5                        # screen px per world unit: whole dish … close up

files = [l.strip() for l in open(LIST) if l.strip()]
rng.shuffle(files)
STEPS = int(SECS * FPS) + 1
skins = []
for f in files:
    im = Image.open(os.path.expanduser(f)).convert("RGBA")
    for c in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        if min(im.getpixel(c)) > 240:                             # white-framed sweep shot, as in hippo.py
            ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=14)
    im = im.crop(im.getchannel("A").getbbox())
    k = SW * M_HI * 1.15 / max(im.size)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    r, a = DR * 0.9 * math.sqrt(rng.random()), rng.uniform(0, 2 * math.pi)
    x, y, th = r * math.cos(a), r * math.sin(a), rng.uniform(0, 2 * math.pi)
    v, w0, wf, wp = rng.uniform(30, 70), rng.uniform(-0.4, 0.4), rng.uniform(0.6, 1.6), rng.uniform(0, 6.3)
    path = []
    for n in range(STEPS):                                        # wander; steer home off the dish's edge
        t = n / FPS
        th += (w0 + 1.4 * math.sin(wf * t + wp)) / FPS
        if math.hypot(x, y) > DR * 0.88:
            home = math.atan2(-y, -x)
            th += math.atan2(math.sin(home - th), math.cos(home - th)) * 3 / FPS
        x, y = x + v * math.cos(th) / FPS, y + v * math.sin(th) / FPS
        path.append((x, y, th))
    sc = rng.uniform(0.75, 1.0)
    skins.append(dict(im=im, sc=sc, path=path, ph=rng.uniform(0, 6.3), beat=rng.uniform(7, 11)))

SPECK = [(rng.uniform(-DR, DR), rng.uniform(-DR, DR), rng.uniform(1.5, 5), rng.uniform(0, 6.3)) for _ in range(900)]

def mag(t):
    return M_LO + (M_HI - M_LO) * (smooth((t - MAG0) / (MAG1 - MAG0)) - smooth((t - MAGB0) / (MAGB1 - MAGB0)) * 0.55)

field = Image.new("RGBA", (W, H), (0, 0, 0, 255))                # bright-field glow, warm centre
fd = ImageDraw.Draw(field)
for i in range(60):
    k = i / 59
    r = RC * (1 - k)
    fd.ellipse((CC[0] - r, CC[1] - r, CC[0] + r, CC[1] + r), fill=(int(206 + 44 * k), int(212 + 34 * k), int(186 + 30 * k), 255))
field = field.filter(ImageFilter.GaussianBlur(12))
vig = Image.new("L", (W, H), 0)                                    # dark rim inside the circle, black outside
ImageDraw.Draw(vig).ellipse((CC[0] - RC + 18, CC[1] - RC + 18, CC[0] + RC - 18, CC[1] + RC - 18), fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(16))
ring = Image.new("RGBA", (W, H), (0, 0, 0, 255))
ring.putalpha(vig.point(lambda p: 255 - p))
MAGFONT = ImageFont.truetype(HN, 34, index=1)

def scope(t):
    m = mag(t)
    u = (m - M_LO) / (M_HI - M_LO)
    c = (u * 260 * math.sin(0.22 * t), u * 200 * math.cos(0.19 * t))    # wander the slide once zoomed in
    to = lambda x, y: (CC[0] + (x - c[0]) * m, CC[1] + (y - c[1]) * m)
    fr = field.copy()
    dr = ImageDraw.Draw(fr, "RGBA")
    ex0, ey0 = to(-DR, -DR)
    ex1, ey1 = to(DR, DR)
    dr.ellipse((ex0, ey0, ex1, ey1), outline=(120, 120, 100, 160), width=max(2, int(8 * m)))   # dish wall
    for x, y, r, p in SPECK:
        sx, sy = to(x + 12 * math.sin(t * 0.7 + p), y + 9 * math.cos(t * 0.6 + p))
        rr = r * m
        dr.ellipse((sx - rr, sy - rr, sx + rr, sy + rr), fill=(150, 160, 120, 70))
    n = min(int(t * FPS), STEPS - 1)
    for s in skins:
        x, y, th = s["path"][n]
        sx, sy = to(x, y)
        size = SW * s["sc"] * m
        if math.hypot(sx - CC[0], sy - CC[1]) > RC + size:
            continue
        beat = math.sin(s["beat"] * t + s["ph"])
        im = s["im"]
        k = size / max(im.size)
        sz = (max(1, int(im.width * k * (1 + 0.07 * beat))), max(1, int(im.height * k * (1 - 0.05 * beat))))
        im = im.resize(sz, Image.BICUBIC if k > 0.3 else Image.BILINEAR)
        # flagellum: a travelling wave trailing behind the direction of travel
        bx, by = -math.cos(th), -math.sin(th)
        reach = 0.5 * (abs(bx) * sz[0] + abs(by) * sz[1])
        pts = []
        for i in range(13):
            q = i / 12
            along = reach * 0.9 + q * size * 0.5
            wave = math.sin(q * 9 - t * 14 + s["ph"]) * size * 0.07 * q
            pts.append((sx + bx * along - by * wave, sy + by * along + bx * wave))
        dr.line(pts, fill=(110, 120, 96, 130), width=max(1, int(size * 0.022)), joint="curve")
        im = im.rotate(9 * math.sin(2.1 * t + s["ph"]), Image.BICUBIC, expand=True)
        paste(fr, im, sx, sy)
    fr.alpha_composite(ring)
    label = f"{int(round(40 * m / M_LO, -1))}×"
    dr = ImageDraw.Draw(fr)
    dr.text((CC[0] + RC * 0.62, CC[1] + RC * 0.86), label, font=MAGFONT, fill=(230, 230, 220, 255), anchor="mm")
    if t < FOCUS:                                                     # coming into focus
        fr = fr.filter(ImageFilter.GaussianBlur(14 * (1 - smooth((t - IRIS0) / (FOCUS - IRIS0)))))
    rad = RC * 1.15 * (smooth((t - IRIS0) / (IRIS1 - IRIS0)) - smooth((t - CLOSE0) / (CLOSE1 - CLOSE0)))
    iris = Image.new("L", (W, H), 255)
    ImageDraw.Draw(iris).ellipse((CC[0] - rad, CC[1] - rad, CC[0] + rad, CC[1] + rad), fill=0)
    fr.paste((0, 0, 0, 255), (0, 0), iris)
    return fr

# --- confetti burst at the finale (piñata physics)
CONF = [(255, 214, 64), (90, 200, 250), (120, 220, 140), (190, 130, 250), (255, 140, 70), (236, 72, 140)]
confetti = []
for _ in range(220):
    a = math.radians(rng.uniform(-170, -10))
    v = rng.uniform(500, 1500) * 0.85
    confetti.append(dict(x=W / 2 + rng.uniform(-60, 60), y=560, vx=v * math.cos(a), vy=v * math.sin(a), c=rng.choice(CONF),
                         sz=rng.uniform(7, 14), rot=rng.uniform(0, 6.3), vr=rng.uniform(-9, 9), flip=rng.uniform(5, 12)))

# --- finale caption
cap = Image.new("RGBA", (1900, 460))
cd = ImageDraw.Draw(cap)
big = ImageFont.truetype(HN, 100, index=1)
cd.text((950, 70), f"{CERTIFIED} more Winamp Modern and", font=big, fill=(28, 30, 38, 255), anchor="mm")
cd.text((950, 185), "Windows Media Player skins", font=big, fill=(28, 30, 38, 255), anchor="mm")
cd.text((950, 300), "tested and certified", font=ImageFont.truetype(HN, 62, index=0), fill=(45, 48, 60, 255), anchor="mm")
cd.text((950, 380), f"version {VERSION}", font=ImageFont.truetype(HN, 46, index=0), fill=(70, 74, 88, 255), anchor="mm")
cap = cap.crop(cap.getbbox())
caption = plate(cap.size, 120, 100, 225, 55)
caption.alpha_composite(cap, (120, 120))

ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-"]
                      + (["-ss", str(ASTART + T0), "-t", str(SECS - T0), "-i", AUDIO,
                          "-af", f"afade=in:d=0.1,afade=out:st={SECS - T0 - 2}:d=2", "-c:a", "aac", "-b:a", "256k"] if AUDIO else [])
                      + ["-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         "-t", str(N / FPS), OUT], stdin=subprocess.PIPE)

for n in range(N):
    t = T0 + n / FPS
    fr = scope(t) if IRIS0 <= t < ZOUT0 else lab(t)
    fr.alpha_composite(brand, BRAND_XY)                       # on screen from the first frame

    if t > FINALE:
        k = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * k)), int(caption.height * (0.9 + 0.1 * k))), Image.LANCZOS)
        paste(fr, fade(c, k), W / 2, 580)

    cfd = ImageDraw.Draw(fr)
    for c in confetti:
        dt = t - FINALE
        if dt < 0:
            break
        drag = 1 - math.exp(-dt * 2.2)                        # air drag: fast burst, then a slow flutter down
        x = c["x"] + c["vx"] / 2.2 * drag + 30 * math.sin(dt * 3 + c["rot"])
        y = c["y"] + c["vy"] / 2.2 * drag + 140 * dt
        if y > H + 20:
            continue
        rot = c["rot"] + c["vr"] * dt
        hw, hh = c["sz"], c["sz"] * 0.45 * abs(math.cos(dt * c["flip"]))
        pts = [(x + px * math.cos(rot) - py * math.sin(rot), y + px * math.sin(rot) + py * math.cos(rot))
               for px, py in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]]
        cfd.polygon(pts, fill=c["c"])
    ff.stdin.write(fr.tobytes())
    if n % 100 == 0:
        print(f"{t:.1f}s", file=sys.stderr)
ff.stdin.close()
if ff.wait():
    sys.exit("ffmpeg failed")
