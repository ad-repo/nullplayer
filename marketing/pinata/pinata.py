# pinata.py <out.mp4> <skins.txt> [audio] [audio_start_s] — a pink donkey piñata swings in on its rope, a stick
# hits it three times, it bursts and every skin in skins.txt (one white-framed sweep shot per line) falls out of
# its belly; logo + url as in the cake and rain promos. modern_* lines are counted as the release's new skins.
# Media (shots list, audio, output) lives in ~/Documents/shots/promo-kit/pinata, not in the repo.
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT, LIST = sys.argv[1], sys.argv[2]
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
ASTART = float(sys.argv[4]) if len(sys.argv) > 4 else 0
ICON = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "../../Sources/NullPlayer/Resources/AppIcon.png")
W, H, FPS, SECS = 1920, 1080, 50, 20
N = int(os.environ.get("FRAMES", FPS * SECS))
rng = random.Random(34)
HN = "/System/Library/Fonts/HelveticaNeue.ttc"

HITS, EMIT0, EMIT1, SNAP, FINALE = (1.5, 2.3, 3.05), 3.15, 13.6, 14.4, 15.2   # seconds; the last hit bursts it
BREAK = HITS[-1]
TX, TY, ROPE = W // 2 + 110, -30, 610          # rope's fixed top and length; the donkey hangs from its end
G = 1500                                       # px/s², for the skins and the snapped donkey

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

# --- background + logo (same look as cake.py)
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

# --- the donkey, drawn at 2x in its own frame (origin = rope attach point, facing left) and downsampled
S, K = 2, 0.85                                  # supersample, donkey scale
PINK, PINK_L, PINK_D, HOT = (247, 150, 190), (252, 190, 215), (205, 90, 140), (236, 72, 140)
RAINBOW = [(255, 214, 64), (90, 200, 250), (120, 220, 140), (190, 130, 250), (255, 140, 70), (236, 72, 140)]
DC = 700                                        # canvas half-size; the attach point sits at its centre

def P(x, y):
    return ((DC + x * K) * S, (DC + y * K) * S)

def silhouette():
    m = Image.new("L", (2 * DC * S, 2 * DC * S))
    md = ImageDraw.Draw(m)
    md.rounded_rectangle((*P(-200, 0), *P(200, 200)), 90 * K * S, fill=255)                              # body
    md.polygon([P(-200, 50), P(-110, 10), P(-185, -150), P(-275, -120)], fill=255)                       # neck
    md.ellipse((*P(-330, -215), *P(-165, -85)), fill=255)                                                 # head
    md.ellipse((*P(-385, -165), *P(-250, -55)), fill=255)                                                 # snout
    md.polygon([P(-265, -190), P(-220, -200), P(-212, -330), P(-252, -325)], fill=255)                  # ears
    md.polygon([P(-215, -195), P(-175, -185), P(-150, -305), P(-188, -318)], fill=255)
    for x in (-170, -90, 50, 130):                                                                       # legs
        md.rounded_rectangle((*P(x, 150), *P(x + 50, 330)), 14 * K * S, fill=255)
    return m

def fringe(size, colors, row=26, r=None):
    """Rows of crepe-paper fringe, bottom row first so each row's tassels hang over the one below."""
    im = Image.new("RGBA", size)
    dr = ImageDraw.Draw(im)
    rows = list(range(0, size[1] + row * S, row * S))
    for i, y in enumerate(reversed(rows)):
        c = colors[(len(rows) - i) % len(colors)]
        dk = tuple(int(v * 0.82) for v in c) + (255,)
        dr.rectangle((0, y, size[0], y + row * S), fill=c + (255,))
        for x in range(0, size[0], 5 * S):
            dr.line((x, y + row * S * 0.5, x + r.uniform(-2, 2) * S, y + row * S + r.uniform(4, 12) * S), fill=dk, width=2 * S)
    return im

r = random.Random(3)
mask = silhouette()
donkey = fringe(mask.size, [PINK, PINK_L, PINK, HOT], r=r)
blanket = Image.new("L", mask.size)
ImageDraw.Draw(blanket).rectangle((*P(-75, -10), *P(75, 210)), fill=255)                                # rainbow saddle band
donkey.paste(fringe(mask.size, RAINBOW, 20, r), (0, 0), Image.composite(blanket, Image.new("L", mask.size), mask))
donkey.putalpha(mask)
edge = Image.new("RGBA", mask.size, PINK_D + (255,))
edge.putalpha(mask.filter(ImageFilter.MaxFilter(9)))
edge.alpha_composite(donkey)
donkey = edge
dd = ImageDraw.Draw(donkey)
dd.ellipse((*P(-262, -175), *P(-232, -140)), fill=(255, 255, 255, 255))                                  # eye
dd.ellipse((*P(-255, -168), *P(-235, -145)), fill=(30, 24, 30, 255))
dd.arc((*P(-275, -195), *P(-225, -160)), 200, 330, fill=(30, 24, 30, 255), width=4 * S)                 # lash line
dd.ellipse((*P(-372, -118), *P(-354, -100)), fill=PINK_D + (255,))                                        # nostril
dd.arc((*P(-370, -100), *P(-300, -70)), 20, 160, fill=PINK_D + (255,), width=4 * S)                     # smile
for x in (-170, -90, 50, 130):                                                                           # hooves
    dd.rounded_rectangle((*P(x, 300), *P(x + 50, 330)), 10 * K * S, fill=(120, 60, 90, 255))
dd.line((*P(195, 40), *P(225, 110), *P(232, 170)), fill=PINK_D + (255,), width=10 * S, joint="curve")    # tail
for i, c in enumerate(RAINBOW):
    x = 215 + i * 6
    dd.line((*P(232, 165), *P(x, 250 + (i % 3) * 10)), fill=c + (255,), width=7 * S)
dd.ellipse((*P(-14, -26), *P(14, 4)), outline=(150, 115, 70, 255), width=6 * S)                         # rope loop on its back

broken = donkey.copy()                                                                                   # same donkey, belly torn open
bd = ImageDraw.Draw(broken)
pts = []
for i in range(28):
    a = 2 * math.pi * i / 28
    rr = (1 if i % 2 else 0.72) * r.uniform(0.85, 1.1)
    pts.append(P(15 + 105 * rr * math.cos(a), 180 + 40 * rr * math.sin(a)))
bd.polygon(pts, fill=(60, 30, 45, 255))
bd.ellipse((*P(-60, 165), *P(85, 205)), fill=(25, 12, 20, 255))
donkey = donkey.resize((2 * DC, 2 * DC), Image.LANCZOS)
broken = broken.resize((2 * DC, 2 * DC), Image.LANCZOS)
HOLE = (15 * K, 185 * K)                                                                                 # belly hole, donkey frame

# --- stick: horizontal, pivot at its left end in the middle of a square canvas so it can rotate about the pivot
SL = 1000
stick = Image.new("RGBA", (2 * SL * S, 2 * SL * S))
sd = ImageDraw.Draw(stick)
sd.rounded_rectangle((SL * S, (SL - 17) * S, (2 * SL - 10) * S, (SL + 17) * S), 17 * S, fill=(150, 100, 55, 255))
sd.line((SL * S, (SL - 8) * S, (2 * SL - 30) * S, (SL - 8) * S), fill=(185, 135, 80, 255), width=6 * S)
for i in range(14):                                                                                      # spiral tape
    x = SL + 300 + i * 48
    sd.polygon([(x * S, (SL - 17) * S), ((x + 20) * S, (SL - 17) * S), ((x + 40) * S, (SL + 17) * S), ((x + 20) * S, (SL + 17) * S)],
               fill=RAINBOW[i % len(RAINBOW)] + (255,))
stick = stick.resize((2 * SL, 2 * SL), Image.LANCZOS)
SPX, SPY = 330, H + 260                                                                                  # stick pivot, off-screen
CONTACT = (TX - 180, TY + ROPE + 70)                                                                 # where its tip meets the donkey's flank
A_HIT = math.degrees(math.atan2(CONTACT[1] - SPY, CONTACT[0] - SPX))
STICK_D = SL - 40 - math.dist((SPX, SPY), CONTACT)                                                       # slide it so the tip lands on CONTACT
# (time, degrees clockwise away from the contact angle); a segment ending in a hit accelerates into it
KEYS = [(0.4, 95), (1.0, 38), (HITS[0], 0), (1.75, 32), (2.1, 46), (HITS[1], 0), (2.5, 34), (2.85, 60), (HITS[2], 0),
        (3.35, 22), (4.1, 100)]

def stick_angle(t):
    for (t0, a0), (t1, a1) in zip(KEYS, KEYS[1:]):
        if t0 <= t < t1:
            x = (t - t0) / (t1 - t0)
            return a0 + (a1 - a0) * (x * x if a1 == 0 else smooth(x))
    return 100

def swing(t):
    """Pendulum angle (rad): an idle sway plus a damped kick per hit, the bursting one hardest."""
    th = 0.08 * math.sin(t * 1.9)
    for h, amp in zip(HITS, (0.18, 0.24, 0.36)):
        if t > h:
            th += amp * math.exp(-(t - h) * 0.25) * math.sin((t - h) * 2.7)
    return th

def drop(t):
    """Vertical offset of the rope's end: falls in from above, then bounces on the rope; falls away after the snap."""
    y = -900 * (1 - ease(t / 0.9)) + 40 * math.exp(-t * 3) * math.sin(t * 14) * (t > 0.5)
    return y + (G / 2 * (t - SNAP) ** 2 if t > SNAP else 0)

def attach(t):
    th = swing(t)
    return TX + ROPE * math.sin(th), TY + ROPE * math.cos(th) + drop(t), th

def to_world(t, lx, ly):
    ax, ay, th = attach(t)
    return ax + lx * math.cos(th) + ly * math.sin(th), ay - lx * math.sin(th) + ly * math.cos(th)

# --- skins
files = [l.strip() for l in open(LIST) if l.strip()]
NEW = sum(os.path.basename(f).startswith("modern_") for f in files)
rng.shuffle(files)
skins = []
for i, f in enumerate(files):
    im = Image.open(os.path.expanduser(f)).convert("RGBA")
    for c in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=14)   # white-framed sweep shot, as in skinrain.py
    im = im.crop(im.getchannel("A").getbbox())
    k = rng.uniform(230, 330) / max(im.size)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    birth = EMIT0 + (EMIT1 - EMIT0) * i / max(1, len(files) - 1)
    side = 1 if i % 2 else -1
    skins.append(dict(im=im, birth=birth, at=to_world(birth, *HOLE), vx=side * rng.uniform(120, 650),
                      vy=rng.uniform(-420, 60), sway=rng.uniform(4, 9), swph=rng.uniform(0, 6.3), spin=-side * rng.uniform(4, 12)))

# --- confetti bursts: (time, count, origin, speed)
confetti = []
for t0, n, (ox, oy), sp in [(BREAK, 320, to_world(BREAK, *HOLE), 1.0), (FINALE, 220, (W / 2, 560), 0.85)]:
    for _ in range(n):
        a = math.radians(rng.uniform(-170, -10) if t0 == FINALE else rng.uniform(0, 360))
        v = rng.uniform(500, 1500) * sp
        confetti.append(dict(t0=t0, x=ox + rng.uniform(-60, 60), y=oy, vx=v * math.cos(a), vy=v * math.sin(a),
                             c=rng.choice(RAINBOW + [PINK, PINK_L, HOT]), sz=rng.uniform(7, 14), rot=rng.uniform(0, 6.3),
                             vr=rng.uniform(-9, 9), flip=rng.uniform(5, 12)))

# --- finale caption
cap = Image.new("RGBA", (1900, 330))
cd = ImageDraw.Draw(cap)
cd.text((950, 90), "Now supporting Sonique skins", font=ImageFont.truetype(HN, 120, index=1), fill=(28, 30, 38, 255), anchor="mm")
cd.text((950, 215), f"+ {NEW} more Winamp Modern skins, engine certified", font=ImageFont.truetype(HN, 62, index=0), fill=(45, 48, 60, 255), anchor="mm")
cd.text((950, 290), "version 0.34.0", font=ImageFont.truetype(HN, 46, index=0), fill=(70, 74, 88, 255), anchor="mm")
cap = cap.crop(cap.getbbox())
caption = plate(cap.size, 120, 100, 200, 55)
caption.alpha_composite(cap, (120, 120))

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
    ax, ay, th = attach(t)
    for s in skins:                                         # behind the donkey, so they drop out from under its belly
        dt = t - s["birth"]
        if dt < 0:
            continue
        x, y = s["at"][0] + s["vx"] * dt, s["at"][1] + s["vy"] * dt + G / 2 * dt * dt
        if y - 250 > H:
            continue
        sc = 0.25 + 0.75 * ease(dt / 0.35)
        im = s["im"].resize((max(1, int(s["im"].width * sc)), max(1, int(s["im"].height * sc))), Image.BICUBIC)
        paste(fr, fade(im.rotate(s["sway"] * math.sin(t * 2.2 + s["swph"]) + s["spin"] * smooth(dt / 1.5), Image.BICUBIC, expand=True), min(1, dt / 0.06)), x, y)
    rd = ImageDraw.Draw(fr)
    if t < SNAP:
        rd.line((TX, TY, ax, ay - 20), fill=(150, 115, 70, 255), width=5)
    else:                                                   # the rope snaps: a stub stays, the rest falls with the donkey
        rd.line((TX, TY, TX, TY + 140), fill=(150, 115, 70, 255), width=5)
        rd.line((ax, ay - 20, ax - 12, ay - 260), fill=(150, 115, 70, 255), width=5)
    if ay - DC < H:
        paste(fr, (broken if t >= BREAK else donkey).rotate(math.degrees(th), Image.BICUBIC), ax, ay)
    a = stick_angle(t)
    if a < 99:
        rad = math.radians(A_HIT + a)
        im = stick.rotate(-(A_HIT + a), Image.BICUBIC)
        paste(fr, im, SPX - STICK_D * math.cos(rad), SPY - STICK_D * math.sin(rad))
    fr.alpha_composite(fade(brand, ease((t - 0.3) / 1.0)), BRAND_XY)   # logo stays above everything but the finale

    if t > FINALE:
        a = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * a)), int(caption.height * (0.9 + 0.1 * a))), Image.LANCZOS)
        paste(fr, fade(c, a), W / 2, 560)

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
