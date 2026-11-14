# hippo.py <out.mp4> <skins.txt> [audio] [audio_start_s] — a hippo stands in a shallow jungle pool, the camera zooms in on its rear,
# and every skin in skins.txt (one white-framed sweep shot per line) comes out of its backside, flung all over by
# the hippo's propeller tail, the way hippos spread dung, splashing down in the water. Camera pulls back out; logo + url and finale caption as
# in the cake and piñata promos.
# Media (shots list, audio, output) lives in ~/Documents/shots/promo-kit/hippo, not in the repo.
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
rng = random.Random(21)

ZIN0, ZIN1, SPIN0, EMIT0, EMIT1, ZOUT0, ZOUT1, SPIN1, FINALE = 2.0, 3.4, 3.3, 3.8, 13.4, 11.6, 13.0, 14.0, 15.2
ZOOM = 2.4                                       # camera zoom on the rump; the hippo and tail are drawn at S = 3
S = 3
HIPPO = (W / 2 - 60, 640)                        # world position of the hippo's origin (body centre)
RUMP = (HIPPO[0] + 236, HIPPO[1] + 10)           # what the camera zooms onto …
ANCHOR = (560, 600)                              # … and where it lands on screen
TAIL = (232, -34)                                # tail base, hippo frame
ANUS = (240, 16)
LEGS = [(-195, -125), (-110, -40), (85, 155), (165, 232)]                # hippo frame x spans
CERTIFIED = 149                                  # the release's count for the caption, whatever the list holds
G = 700                                          # world px/s² for the flung skins

# --- logo (same look as cake.py / pinata.py)

brand, BRAND_XY = brand(W)

# --- the hippo, side on facing left, drawn at S in its own frame (origin = body centre)
LAV, LAV_L, LAV_D, EDGE, PINK = (164, 150, 196), (204, 192, 226), (132, 118, 168), (78, 66, 104), (240, 160, 180)
CX, CY = 500, 270

def P(x, y):
    return ((CX + x) * S, (CY + y) * S)

def B(x0, y0, x1, y1):
    return (*P(x0, y0), *P(x1, y1))

def hippo(happy):
    size = (2 * CX * S, 2 * CY * S)
    m = Image.new("L", size)
    md = ImageDraw.Draw(m)
    for box in [(-245, -145, 245, 145), (-390, -165, -165, 55), (-465, -85, -255, 85)]:   # body, head, muzzle
        md.ellipse(B(*box), fill=255)
    md.polygon([P(-200, -100), P(-130, -118), P(-110, 120), P(-230, 40)], fill=255)        # neck
    for x0, x1 in LEGS:                                                                       # legs
        md.rounded_rectangle(B(x0, 60, x1, 212), 26 * S, fill=255)
    for box in [(-300, -205, -262, -140), (-252, -200, -214, -140)]:                          # ears
        md.ellipse(B(*box), fill=255)

    im = Image.new("RGBA", size, LAV + (255,))
    sh = ImageDraw.Draw(im)
    sh.ellipse(B(-260, -40, 250, 200), fill=LAV_L + (255,))                                   # lighter belly
    sh.ellipse(B(-235, -150, 235, 10), fill=LAV + (255,))
    sh.ellipse(B(-460, -10, -270, 95), fill=LAV_L + (255,))                                   # lighter jaw
    im = im.filter(ImageFilter.GaussianBlur(14 * S))
    far = Image.new("L", size)                                                                # far legs a shade darker, below the belly
    fd = ImageDraw.Draw(far)
    for x0, x1 in [(-110, -40), (165, 232)]:
        fd.rounded_rectangle(B(x0, 60, x1, 212), 26 * S, fill=255)
    fd.ellipse(B(-245, -145, 245, 145), fill=0)
    im.paste(LAV_D + (255,), (0, 0), far)
    im.putalpha(m)

    out = Image.new("RGBA", size)
    edge = Image.new("RGBA", size, EDGE + (255,))
    edge.putalpha(m.filter(ImageFilter.MaxFilter(4 * S + 1)))
    out.alpha_composite(edge)
    out.alpha_composite(im)

    dd = ImageDraw.Draw(out)
    for x0, x1 in LEGS:                                                                       # toenails
        for k in range(3):
            nx = x0 + 10 + k * (x1 - x0 - 20) / 3
            dd.rounded_rectangle(B(nx, 196, nx + (x1 - x0 - 20) / 3 - 4, 210), 5 * S, fill=(236, 230, 240, 255))
    for box in [(-292, -195, -270, -152), (-244, -190, -222, -152)]:                         # inner ears
        dd.ellipse(B(*box), fill=PINK + (255,))
    dd.ellipse(B(-345, -125, -290, -88), fill=LAV_L + (255,))                                 # brow bump
    if happy:                                                                                 # content, eyes shut
        dd.arc(B(-336, -118, -300, -92), 200, 340, fill=(30, 24, 36, 255), width=5 * S)
    else:
        dd.ellipse(B(-334, -120, -302, -88), fill=(255, 255, 255, 255))
        dd.ellipse(B(-330, -114, -310, -92), fill=(30, 24, 36, 255))
        dd.ellipse(B(-326, -112, -320, -105), fill=(255, 255, 255, 255))
    for x in (-440, -405):                                                                    # nostrils
        dd.ellipse(B(x, -66, x + 18, -52), fill=EDGE + (255,))
    dd.ellipse(B(-385, -10, -330, 30), fill=(222, 170, 204, 255))                             # cheek, pink over the jaw
    dd.arc(B(-465, -40, -300, 50), 25, 120, fill=EDGE + (255,), width=4 * S)                  # smile
    dd.polygon([P(-418, 44), P(-402, 47), P(-410, 60)], fill=(250, 248, 240, 255))           # tooth
    dd.ellipse(B(ANUS[0] - 9, ANUS[1] - 7, ANUS[0] + 3, ANUS[1] + 7), fill=EDGE + (255,))
    return out

HIP, HIP_HAPPY = hippo(False), hippo(True)

TL = 96                                                                                       # tail: pivot at canvas centre, pointing right
tail = Image.new("RGBA", (2 * (TL + 20) * S, 2 * (TL + 20) * S))
td = ImageDraw.Draw(tail)
c0 = (TL + 20) * S
td.polygon([(c0, c0 - 10 * S), (c0 + (TL - 30) * S, c0 - 7 * S), (c0 + (TL - 30) * S, c0 + 7 * S), (c0, c0 + 10 * S)], fill=EDGE + (255,))
td.polygon([(c0, c0 - 6 * S), (c0 + (TL - 32) * S, c0 - 4 * S), (c0 + (TL - 32) * S, c0 + 4 * S), (c0, c0 + 6 * S)], fill=LAV + (255,))
for k in range(-3, 4):                                                                        # flat bristle tuft
    td.line((c0 + (TL - 36) * S, c0, c0 + TL * S, c0 + k * 6 * S), fill=(60, 50, 80, 255), width=4 * S)

TAIL_REST, TAIL_AMP = 15, 75

def tail_angle(t):
    """Degrees clockwise from straight back: a lazy sway, then the propeller."""
    a = TAIL_REST + 8 * math.sin(t * 2.3)
    amp = TAIL_AMP * smooth((t - SPIN0) / 0.4) * (1 - smooth((t - SPIN1) / 0.5))
    return a + amp * math.sin(2 * math.pi * 7.5 * max(0, t - SPIN0))

# --- the jungle pool, in world space at JS x so the zoom stays sharp: `bg` is everything behind the hippo, `fg`
# the water in front of its legs (the same water, mostly opaque) plus leaves at the bottom corners. Each frame
# crops the camera's view out of both.
JS = 2
SHORE, WL = 690, 800                                  # far bank, and the waterline at the hippo's legs (world y)
jr = random.Random(8)

def J(*v):
    return tuple(int(x * JS) for x in v)

def blob_row(dr, top, col, rmin, rmax, jitter):
    x = -120
    while x < W + 120:
        r = jr.uniform(rmin, rmax)
        y = top + jr.uniform(-jitter, jitter)
        dr.ellipse(J(x - r, y - r, x + r, y + r * 0.9), fill=col)
        x += r * jr.uniform(0.7, 1.1)

def leaf(dr, x, y, ang, length, width, col):
    ux, uy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    side = [(x + ux * length * k - uy * width * math.sin(math.pi * k) ** 0.8, y + uy * length * k + ux * width * math.sin(math.pi * k) ** 0.8)
            for k in [i / 16 for i in range(17)]]
    other = [(2 * (x + ux * length * k) - px, 2 * (y + uy * length * k) - py) for (px, py), k in zip(side, [i / 16 for i in range(17)])]
    dr.polygon([J(*q) for q in side + other[::-1]], fill=col)
    dr.line(J(x, y, x + ux * length, y + uy * length), fill=tuple(min(255, int(c * 1.35)) for c in col[:3]) + (255,), width=3 * JS)

bg = Image.new("RGBA", (W * JS, H * JS))
d = ImageDraw.Draw(bg)
for y in range(SHORE * JS):                                                                    # hazy sky
    k = y / (SHORE * JS)
    d.line([(0, y), (W * JS, y)], fill=(int(238 - 40 * k), int(240 - 22 * k), int(206 - 36 * k), 255))
glow = Image.new("RGBA", bg.size)
ImageDraw.Draw(glow).ellipse(J(1050, 120, 1750, 620), fill=(255, 252, 225, 150))
bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90 * JS)))
for i, (top, col) in enumerate([(400, (176, 202, 156)), (480, (136, 176, 124)), (560, (96, 144, 96)), (630, (62, 110, 70))]):
    layer = Image.new("RGBA", bg.size, col + (0,))                                            # clear in its own colour: no dark blur halo
    ld = ImageDraw.Draw(layer)
    blob_row(ld, top, col + (255,), 50 + 15 * i, 110 + 15 * i, 45)
    ld.rectangle(J(0, top + 30, W, SHORE + 4), fill=col + (255,))
    for _ in range(90):                                                                        # leaf texture
        x, y = jr.uniform(0, W), jr.uniform(top - 60, SHORE)
        r = jr.uniform(8, 22)
        c = tuple(int(v * jr.choice((0.88, 1.1))) for v in col)
        ld.ellipse(J(x - r, y - r * 0.6, x + r, y + r * 0.6), fill=c + (255,))
    bg.alpha_composite(layer.filter(ImageFilter.GaussianBlur((3 - i) * 1.5 * JS)))
for _ in range(70):                                                                            # reeds along the far bank
    x = jr.uniform(0, W)
    h = jr.uniform(30, 90)
    d.line(J(x, SHORE + 4, x + jr.uniform(-14, 14), SHORE - h), fill=(52, 92, 50, 255), width=3 * JS)
blob_row(d, -30, (44, 86, 52, 255), 60, 120, 30)                                               # canopy overhang
for _ in range(9):                                                                             # hanging vines
    x, L = jr.uniform(40, W - 40), jr.uniform(160, 380)
    pts = [(x + 18 * math.sin(k * 3 + x), k * L) for k in [i / 20 for i in range(21)]]
    d.line([J(*q) for q in pts], fill=(48, 88, 52, 255), width=4 * JS, joint="curve")
    for k, (px, py) in enumerate(pts[3::3]):
        leaf(d, px, py, 40 if k % 2 else 140, 36, 12, (58, 108, 60, 255))

def water(y):
    k = (y - SHORE) / (H - SHORE)
    return (int(128 - 48 * k), int(170 - 46 * k), int(150 - 34 * k), 255)

for y in range(SHORE * JS, H * JS):
    d.line([(0, y), (W * JS, y)], fill=water(y / JS))
refl = bg.crop(J(0, SHORE - 240, W, SHORE)).transpose(Image.FLIP_TOP_BOTTOM).filter(ImageFilter.GaussianBlur(5 * JS))
bg.alpha_composite(fade(refl, 0.3), J(0, SHORE))                                               # the jungle, mirrored
for _ in range(150):                                                                           # shimmer
    x, y = jr.uniform(0, W), jr.uniform(SHORE + 4, H)
    w = jr.uniform(10, 50) * (0.5 + (y - SHORE) / (H - SHORE))
    d.line(J(x, y, x + w, y), fill=(220, 240, 230, 255), width=JS)

fg = Image.new("RGBA", bg.size)
fg.alpha_composite(fade(bg.crop(J(0, WL, W, H)), 0.82), J(0, WL))                             # legs show faintly through it
fd = ImageDraw.Draw(fg)
for x0, x1 in LEGS:                                                                            # ripples round each leg
    x0, x1 = HIPPO[0] + x0, HIPPO[0] + x1
    fd.ellipse(J(x0 - 14, WL - 7, x1 + 14, WL + 9), outline=(232, 246, 240, 200), width=3 * JS)
    fd.ellipse(J(x0 - 40, WL - 12, x1 + 40, WL + 18), outline=(232, 246, 240, 90), width=2 * JS)
for x, y, ang, L in [(-40, H + 30, -60, 330), (-60, H - 80, -30, 300), (60, H + 40, -85, 260),         # corner leaves
                     (W + 40, H + 30, -120, 330), (W + 60, H - 90, -150, 290), (W - 70, H + 40, -95, 250)]:
    leaf(fd, x, y, ang, L, L * 0.22, (40, 84, 46, 255))

# --- camera: zooms on the rump, holds, pulls back out
def cam(t):
    u = smooth((t - ZIN0) / (ZIN1 - ZIN0)) - smooth((t - ZOUT0) / (ZOUT1 - ZOUT0))
    z = 1 + (ZOOM - 1) * u
    f = (W / 2 + (RUMP[0] - W / 2) * u, H / 2 + (RUMP[1] - H / 2) * u)
    a = (W / 2 + (ANCHOR[0] - W / 2) * u, H / 2 + (ANCHOR[1] - H / 2) * u)
    view = tuple(v * JS for v in (f[0] - a[0] / z, f[1] - a[1] / z, f[0] + (W - a[0]) / z, f[1] + (H - a[1]) / z))
    return lambda x, y: (a[0] + (x - f[0]) * z, a[1] + (y - f[1]) * z), z, view

def local(x, y):
    return HIPPO[0] + x, HIPPO[1] + y

# --- skins: each one comes out of the rump (0.22 s), then the tail flicks it off along its sweep
files = [l.strip() for l in open(LIST) if l.strip()]
rng.shuffle(files)
skins = []
for i, f in enumerate(files):
    im = Image.open(os.path.expanduser(f)).convert("RGBA")
    for c in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        if min(im.getpixel(c)) > 240:                         # white-framed sweep shot, as in skinrain.py;
            ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=14)   # a bare window capture is left alone
    im = im.crop(im.getchannel("A").getbbox())
    k = rng.uniform(200, 300) / max(im.size)                  # screen size while zoomed in
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    birth = EMIT0 + (EMIT1 - EMIT0) * (i / max(1, len(files) - 1)) ** 0.7   # a slow start, then a torrent
    flick = birth + 0.22
    sweep = (tail_angle(flick) - TAIL_REST) / TAIL_AMP                # -1 (tail up) … 1 (tail down)
    a = math.radians(-80 + 95 * sweep + rng.uniform(-15, 15))        # up and back over the hippo … low and away
    v = rng.uniform(500, 1050)
    vx, vy = v * math.cos(a), v * math.sin(a)
    x0, y0 = local(ANUS[0] + 34, ANUS[1] + 6)
    yl = rng.uniform(WL + 15, WL + 240)                                # where it hits the water
    dtl = (-vy + math.sqrt(vy * vy + 2 * G * (yl - y0))) / G
    drops = [(rng.uniform(-1, 1) * 160, rng.uniform(180, 380)) for _ in range(9)]
    skins.append(dict(im=im, birth=birth, flick=flick, vx=vx, vy=vy, spin=rng.uniform(-540, 540),
                      land=flick + dtl, splash=(x0 + vx * dtl, yl), drops=drops))

def skin_at(s, t):
    """World centre, scale (of the zoomed-in size), rotation degrees — or None before birth."""
    if not s["birth"] <= t < s["land"]:
        return None
    if t < s["flick"]:
        u = (t - s["birth"]) / (s["flick"] - s["birth"])
        x, y = local(ANUS[0] + 34 * ease(u), ANUS[1] + 6 * u)
        return x, y, 0.15 + 0.45 * ease(u), 0
    dt = t - s["flick"]
    x0, y0 = local(ANUS[0] + 34, ANUS[1] + 6)
    return x0 + s["vx"] * dt, y0 + s["vy"] * dt + G / 2 * dt * dt, 0.6 + 0.4 * ease(dt / 0.3), s["spin"] * dt

# --- confetti burst at the finale (piñata physics)
CONF = [(255, 214, 64), (90, 200, 250), (120, 220, 140), (190, 130, 250), (255, 140, 70), (236, 72, 140), LAV_L, PINK]
confetti = []
for _ in range(220):
    a = math.radians(rng.uniform(-170, -10))
    v = rng.uniform(500, 1500) * 0.85
    confetti.append(dict(x=W / 2 + rng.uniform(-60, 60), y=560, vx=v * math.cos(a), vy=v * math.sin(a), c=rng.choice(CONF),
                         sz=rng.uniform(7, 14), rot=rng.uniform(0, 6.3), vr=rng.uniform(-9, 9), flip=rng.uniform(5, 12)))

# --- finale caption
cap = Image.new("RGBA", (1900, 330))
cd = ImageDraw.Draw(cap)
cd.text((950, 90), f"{CERTIFIED} more Winamp Modern skins", font=ImageFont.truetype(HN, 120, index=1), fill=(28, 30, 38, 255), anchor="mm")
cd.text((950, 215), "clean room engine tested and certified", font=ImageFont.truetype(HN, 62, index=0), fill=(45, 48, 60, 255), anchor="mm")
cd.text((950, 290), "version 0.35.1", font=ImageFont.truetype(HN, 46, index=0), fill=(70, 74, 88, 255), anchor="mm")
cap = cap.crop(cap.getbbox())
caption = plate(cap.size, 120, 100, 200, 55)
caption.alpha_composite(cap, (120, 120))

ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-"]
                      + (["-ss", str(ASTART + T0), "-t", str(SECS - T0), "-i", AUDIO,
                          "-af", f"afade=in:d=0.1,afade=out:st={SECS - T0 - 2}:d=2", "-c:a", "aac", "-b:a", "256k"] if AUDIO else [])
                      + ["-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         "-t", str(N / FPS), OUT], stdin=subprocess.PIPE)

sized = {}
for n in range(N):
    t = T0 + n / FPS
    to, z, view = cam(t)
    fr = bg.resize((W, H), Image.BICUBIC, box=view)

    src = HIP_HAPPY if SPIN0 + 0.3 < t < SPIN1 + 0.6 else HIP
    key = (id(src), round(z, 3))
    if key not in sized:
        sized = {key: src.resize((int(src.width * z / S), int(src.height * z / S)), Image.BICUBIC)}
    paste(fr, sized[key], *to(*HIPPO))
    fr.alpha_composite(fg.resize((W, H), Image.BICUBIC, box=view))

    sd = ImageDraw.Draw(fr, "RGBA")
    for s in skins:                                           # splashes where skins hit the water
        dt = t - s["land"]
        if not 0 <= dt < 0.7:
            continue
        u, (sx, sy) = dt / 0.7, to(*s["splash"])
        rx = (25 + 120 * ease(u)) * z
        sd.ellipse((sx - rx, sy - rx * 0.22, sx + rx, sy + rx * 0.22), outline=(236, 248, 242, int(210 * (1 - u))), width=max(1, int(3 * z)))
        if dt < 0.5:
            for dx, up in s["drops"]:
                px, py = sx + dx * dt * z, sy + (-up * dt + G * dt * dt) * z
                r = 4 * z * (1 - dt * 1.6)
                sd.ellipse((px - r, py - r, px + r, py + r), fill=(236, 248, 242, 220))

    for s in skins:                                           # in front of the body, under the tail
        p = skin_at(s, t)
        if p is None:
            continue
        x, y = to(p[0], p[1])
        sc = p[2] * z / ZOOM
        im = s["im"]
        im = im.resize((max(1, int(im.width * sc)), max(1, int(im.height * sc))), Image.BICUBIC)
        im = im.rotate(p[3], Image.BICUBIC, expand=True)
        if y - im.height / 2 > H or x + im.width / 2 < 0 or x - im.width / 2 > W:
            continue
        paste(fr, im, x, y)

    bx, by = to(*local(*TAIL))
    a = tail_angle(t)
    ts = tail.resize((int(tail.width * z / S), int(tail.height * z / S)), Image.BICUBIC)
    if SPIN0 < t < SPIN1 + 0.5:                               # motion blur: fading ghosts of the last few hundredths
        for k, al in ((3, 0.12), (2, 0.22), (1, 0.38)):
            paste(fr, fade(ts.rotate(-tail_angle(t - 0.008 * k), Image.BICUBIC), al), bx, by)
    paste(fr, ts.rotate(-a, Image.BICUBIC), bx, by)

    fr.alpha_composite(brand, BRAND_XY)                       # on screen from the first frame

    if t > FINALE:
        k = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * k)), int(caption.height * (0.9 + 0.1 * k))), Image.LANCZOS)
        paste(fr, fade(c, k), W / 2, 560)

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
