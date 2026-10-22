# cake.py <out.mp4> <skins.txt> [audio] [audio_start_s] — the cake's lid pops off and every skin in
# skins.txt (one white-framed sweep shot per line) floats out of the top; logo + url as in the rain promo.
# Media (shots list, audio, output) lives in ~/Documents/shots/promo-kit/cake, not in the repo.
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT, LIST = sys.argv[1], sys.argv[2]
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
ASTART = float(sys.argv[4]) if len(sys.argv) > 4 else 0
ICON = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "../../Sources/NullPlayer/Resources/AppIcon.png")
W, H, FPS, SECS = 1920, 1080, 50, 20
N = int(os.environ.get("FRAMES", FPS * SECS))
rng = random.Random(25)
HN = "/System/Library/Fonts/HelveticaNeue.ttc"

POP, EMIT0, EMIT1, LIFE, FINALE = 2.4, 2.9, 12.8, 5.0, 15.4   # seconds
CX, RIM, BODY_H, CW, RY, LID_H = W // 2, 800, 230, 640, 70, 95  # cake geometry; RIM = y of the top ellipse centre

def ease(x):
    x = min(max(x, 0), 1)
    return 1 - (1 - x) ** 3

def smooth(x):
    x = min(max(x, 0), 1)
    return x * x * (3 - 2 * x)

def fade(im, a):
    if a >= 1:
        return im
    im = im.copy()
    im.putalpha(im.getchannel("A").point(lambda p: int(p * a)))
    return im

# --- background + logo (same look as promo-kit/rain/rain.py)
bg = Image.new("RGBA", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    c = int(212 - 30 * y / H)
    d.line([(0, y), (W, y)], fill=(c - 8, c - 2, c + 10, 255))

def plate(size, pad=150, r=120, a=190, blur=70):
    g = Image.new("RGBA", (size[0] + 2 * pad, size[1] + 2 * pad))
    ImageDraw.Draw(g).rounded_rectangle((pad, pad + 20, g.width - pad, g.height - pad - 20), r, fill=(255, 255, 255, a))
    return g.filter(ImageFilter.GaussianBlur(blur))

font = ImageFont.truetype(HN, 230, index=1)
icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
tw = int(font.getlength("NullPlayer"))
logo = Image.new("RGBA", (300 + 50 + tw + 40, 450))
logo.alpha_composite(icon, (0, 30))
ld = ImageDraw.Draw(logo)
ld.text((350, 180), "NullPlayer", font=font, fill=(28, 30, 38, 255), anchor="lm")
ld.text((logo.width // 2, 405), "nullplayer.fyi", font=ImageFont.truetype(HN, 76, index=0), fill=(45, 48, 60, 255), anchor="mm")
logo = logo.resize((int(logo.width * 0.5), int(logo.height * 0.5)), Image.LANCZOS)
brand = plate(logo.size, 110, 90, 170, 50)
brand.alpha_composite(logo, (110, 110))
BRAND_XY = ((W - brand.width) // 2, 40 - 110)

# --- the cake, drawn at 2x and downsampled
S = 2
PINK, PINK_D, CREAM, CREAM_D, JAM, CHOC = (247, 160, 190), (222, 120, 158), (252, 236, 206), (232, 208, 168), (214, 70, 104), (92, 52, 40)
SPRINKLES = [(255, 214, 64), (90, 200, 250), (120, 220, 140), (255, 255, 255), (190, 130, 250)]

def big(w, h):
    return Image.new("RGBA", (w * S, h * S))

def ell(dr, cx, cy, rx, ry, fill):
    dr.ellipse(((cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S), fill=fill)

def drum(dr, top, h, side, shade):
    """Cylinder side from `top` (ellipse centre) down `h`, with a darker lower band for roundness."""
    rx = CW // 2
    ell(dr, CX, top + h, rx, RY, shade)
    dr.rectangle(((CX - rx) * S, top * S, (CX + rx) * S, (top + h) * S), fill=side)
    ell(dr, CX, top + h - 6, rx - 4, RY - 4, side)

def drips(dr, top, depth, r):
    """Frosting band under a rim at `top`, with drips hanging off the front arc."""
    rx = CW // 2
    for i in range(46):
        a = math.pi * (i + r.uniform(0.2, 0.8)) / 46
        x, y = CX - rx * math.cos(a), top + RY * math.sin(a)
        L = r.uniform(0.3, 1.0) * depth
        dr.rounded_rectangle(((x - 9) * S, (y - 10) * S, (x + 9) * S, (y + L) * S), 9 * S, fill=PINK)
    for i in range(70):
        a = math.pi * r.uniform(0.05, 0.95)
        x, y = CX - (rx - 10) * math.cos(a), top + (RY - 6) * math.sin(a) + r.uniform(8, depth * 0.5)
        ang = r.uniform(0, math.pi)
        dx, dy = 6 * math.cos(ang), 6 * math.sin(ang)
        dr.line(((x - dx) * S, (y - dy) * S, (x + dx) * S, (y + dy) * S), fill=r.choice(SPRINKLES), width=4 * S)

r = random.Random(3)
# body: side wall with its top ellipse cut away, so the hole shows through and hides a rising skin's lower half
body = big(W, H)
bd = ImageDraw.Draw(body)
ell(bd, CX, RIM + BODY_H + 18, CW // 2 + 70, RY + 34, (236, 238, 244, 255))            # plate
ell(bd, CX, RIM + BODY_H + 12, CW // 2 + 60, RY + 26, (250, 251, 253, 255))
drum(bd, RIM, BODY_H, CREAM, CREAM_D)
drum(bd, RIM + BODY_H * 0.48, 22, JAM, JAM)                                              # jam layer
drum(bd, RIM + BODY_H * 0.48 + 22, BODY_H * 0.52 - 22, CREAM, CREAM_D)
drips(bd, RIM, 90, r)
ell(bd, CX, RIM, CW // 2 + 2, RY + 2, (0, 0, 0, 0))
bd.arc(((CX - CW // 2) * S, (RIM - RY) * S, (CX + CW // 2) * S, (RIM + RY) * S), 0, 180, fill=PINK_D, width=10 * S)  # front lip only; the back is behind the skins
body = body.resize((W, H), Image.LANCZOS)
hole = big(W, H)
hd = ImageDraw.Draw(hole)
ell(hd, CX, RIM, CW // 2, RY, PINK)
ell(hd, CX, RIM + 6, CW // 2 - 26, RY - 18, CHOC)
hole = hole.resize((W, H), Image.LANCZOS)

# lid: a short drum sitting on the rim, frosted, with candles; drawn on its own canvas so it can fly
LT = RIM - LID_H
lid = big(W, H)
lidd = ImageDraw.Draw(lid)
drum(lidd, LT, LID_H, CREAM, CREAM_D)
ell(lidd, CX, LT, CW // 2, RY, PINK)
drips(lidd, LT, 60, r)
ell(lidd, CX, LT - 4, CW // 2 - 24, RY - 16, (252, 186, 210, 255))
for i, (dx, dy) in enumerate([(-170, 8), (-60, 26), (60, 26), (170, 8), (-110, -28), (0, -34), (110, -28)]):
    x, y = CX + dx, LT + dy
    lidd.rounded_rectangle(((x - 9) * S, (y - 90) * S, (x + 9) * S, y * S), 6 * S, fill=SPRINKLES[i % 5])
    for k in range(3):
        lidd.line(((x - 9) * S, (y - 70 + 25 * k) * S, (x + 9) * S, (y - 80 + 25 * k) * S), fill=(255, 255, 255, 200), width=4 * S)
    lidd.line((x * S, (y - 90) * S, x * S, (y - 100) * S), fill=(60, 50, 40, 255), width=3 * S)
glowl = lid.resize((W, H), Image.LANCZOS)
fl = Image.new("RGBA", (W, H))
fd = ImageDraw.Draw(fl)
for dx, dy in [(-170, 8), (-60, 26), (60, 26), (170, 8), (-110, -28), (0, -34), (110, -28)]:
    x, y = CX + dx, LT + dy - 112
    fd.ellipse((x - 22, y - 26, x + 22, y + 22), fill=(255, 200, 80, 120))
fl = fl.filter(ImageFilter.GaussianBlur(10))
fd = ImageDraw.Draw(fl)
for dx, dy in [(-170, 8), (-60, 26), (60, 26), (170, 8), (-110, -28), (0, -34), (110, -28)]:
    x, y = CX + dx, LT + dy - 112
    fd.ellipse((x - 8, y - 16, x + 8, y + 10), fill=(255, 170, 40, 255))
    fd.ellipse((x - 4, y - 6, x + 4, y + 8), fill=(255, 245, 200, 255))
lid = glowl
lid.alpha_composite(fl)
LID_BOX = lid.getbbox()
lid = lid.crop(LID_BOX)                                                                  # pivot = its own centre

# --- skins
files = [l.strip() for l in open(LIST) if l.strip()]
rng.shuffle(files)
skins = []
for i, f in enumerate(files):
    im = Image.open(os.path.expanduser(f)).convert("RGBA")
    for c in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=14)   # white-framed sweep shot, as in skinrain.py
    im = im.crop(im.getchannel("A").getbbox())
    k = rng.uniform(270, 380) / max(im.size)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    side = 1 if i % 2 else -1
    birth = EMIT0 + (EMIT1 - EMIT0) * i / max(1, len(files) - 1)
    end = (CX + side * rng.uniform(520, 1100), rng.uniform(-420, -260))
    skins.append(dict(im=im, birth=birth, side=side, end=end, bend=rng.uniform(260, 520),
                      sway=rng.uniform(4, 9), swph=rng.uniform(0, 6.3), spin=side * rng.uniform(4, 12)))

# --- confetti bursts: (time, count, origin y, speed)
confetti = []
for t0, n, oy, sp in [(POP, 260, RIM - 40, 1.0), (FINALE, 220, RIM - 10, 0.85)]:
    for _ in range(n):
        a = math.radians(rng.uniform(-150, -30))
        v = rng.uniform(500, 1500) * sp
        confetti.append(dict(t0=t0, x=CX + rng.uniform(-200, 200), y=oy, vx=v * math.cos(a), vy=v * math.sin(a),
                             c=rng.choice(SPRINKLES + [PINK, JAM]), sz=rng.uniform(7, 14), rot=rng.uniform(0, 6.3),
                             vr=rng.uniform(-9, 9), flip=rng.uniform(5, 12)))

# --- finale caption
cap = Image.new("RGBA", (1500, 330))
cd = ImageDraw.Draw(cap)
cd.text((750, 90), f"{len(files)} more skins certified", font=ImageFont.truetype(HN, 130, index=1), fill=(28, 30, 38, 255), anchor="mm")
cd.text((750, 215), "Winamp Modern skins, on a Mac only in NullPlayer", font=ImageFont.truetype(HN, 58, index=0), fill=(45, 48, 60, 255), anchor="mm")
cd.text((750, 290), "version 0.33.1", font=ImageFont.truetype(HN, 46, index=0), fill=(70, 74, 88, 255), anchor="mm")
cap = cap.crop(cap.getbbox())
caption = plate(cap.size, 120, 100, 200, 55)
caption.alpha_composite(cap, (120, 120))

def bez(p0, p1, p2, s):
    return tuple((1 - s) ** 2 * a + 2 * (1 - s) * s * b + s * s * c for a, b, c in zip(p0, p1, p2))

LID_VX, LID_VY, G, FLOOR, BOUNCE = 520, -1500, 3000, 150, 0.5   # lid flight, px/s; FLOOR = landing drop below its rest

def lid_y(dt):
    """Lid's vertical offset `dt` s after the pop: a parabola to FLOOR, then damped bounces."""
    y, vy = 0, LID_VY
    while dt > 0 and abs(vy) > 50:
        tl = (-vy + math.sqrt(vy * vy + 2 * G * (FLOOR - y))) / G   # time until it hits the floor
        if dt < tl:
            return y + vy * dt + G * dt * dt / 2
        dt, y, vy = dt - tl, FLOOR, -BOUNCE * (vy + G * tl)
    return y if dt <= 0 else FLOOR

LID_LAND = (-LID_VY + math.sqrt(LID_VY ** 2 + 2 * G * FLOOR)) / G   # first touchdown, s after the pop

def paste(fr, im, cx, cy):
    x0, y0 = int(cx - im.width / 2), int(cy - im.height / 2)
    if x0 < W and y0 < H and x0 + im.width > 0 and y0 + im.height > 0:
        fr.alpha_composite(im, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))

ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-"]
                      + (["-ss", str(ASTART), "-t", str(SECS), "-i", AUDIO,
                          "-af", f"afade=in:d=0.1,afade=out:st={SECS - 2}:d=2", "-c:a", "aac", "-b:a", "256k"] if AUDIO else [])
                      + ["-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         "-t", str(SECS), OUT], stdin=subprocess.PIPE)

for n in range(N):
    t = n / FPS
    fr = bg.copy()
    rise = ease(t / 1.1)                                    # cake slides up from below at the start
    oy = int((1 - rise) * 600)

    stage = Image.new("RGBA", (W, H))                       # cake + skins, shifted by the intro slide
    stage.alpha_composite(hole)
    for s in skins:
        u = (t - s["birth"]) / LIFE
        if not 0 <= u <= 1:
            continue
        sc = 0.2 + 0.8 * ease(u / 0.3)
        p = bez((CX, RIM + 50), (CX + s["side"] * s["bend"], RIM - 380), s["end"], u ** 1.15)
        im = s["im"].resize((max(1, int(s["im"].width * sc)), max(1, int(s["im"].height * sc))), Image.BICUBIC)
        ang = s["sway"] * math.sin(t * 2.2 + s["swph"]) + s["spin"] * smooth(u)
        im = im.rotate(ang, Image.BICUBIC, expand=True)
        paste(stage, fade(im, min(1, u / 0.04)), *p)
    stage.alpha_composite(body)
    if t < POP + 3.6:                                       # lid: wobble, pops up flipping, lands flat, bounces off right
        w = max(0, t - (POP - 0.9))
        dt = max(0, t - POP)
        dx = LID_VX * dt
        ang = (4 * math.sin(w * 38) * min(1, w / 0.9)) * (t < POP) - 360 * smooth(dt / LID_LAND)
        hop = 10 * abs(math.sin(w * 19)) * min(1, w / 0.9) * (t < POP)
        im = lid.rotate(ang, Image.BICUBIC, expand=True)
        lx = (LID_BOX[0] + LID_BOX[2]) / 2 + dx
        ly = (LID_BOX[1] + LID_BOX[3]) / 2 - hop + lid_y(dt)
        paste(stage, im, lx, ly)
    fr.alpha_composite(stage, (0, oy)) if oy < H else None
    fr.alpha_composite(fade(brand, ease((t - 0.3) / 1.0)), BRAND_XY)   # logo stays above the skins

    if t > FINALE:
        a = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * a)), int(caption.height * (0.9 + 0.1 * a))), Image.LANCZOS)
        paste(fr, fade(c, a), W / 2, 470)

    cfd = ImageDraw.Draw(fr)
    for c in confetti:
        dt = t - c["t0"]
        if dt < 0:
            continue
        drag = 1 - math.exp(-dt * 2.2)                       # air drag: fast burst, then a slow flutter down
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
        print(n, file=sys.stderr)
ff.stdin.close()
ff.wait()
