# frankenstein.py <out.mp4> <clip.mov> [audio] [audio_start_s] — a mad-science lab: a WMP-skinned player lies
# stitched together on the slab, wired to three jars (WMP skin / macOS / Winamp AVS); the switch is thrown,
# lightning, and the clip comes alive and sits up. Logo + url and finale caption as in the cake and piñata promos.
# [audio] (from [audio_start_s]) is the lab's ambience until it comes alive; then the clip's own sound takes over.
# Media (clip, output) lives in ~/Documents/shots/promo-kit/frankenstein, not in the repo.
import math, os, random, subprocess, sys
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

OUT, CLIP = sys.argv[1], sys.argv[2]
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
ASTART = float(sys.argv[4]) if len(sys.argv) > 4 else 0
ICON = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "../../Sources/NullPlayer/Resources/AppIcon.png")
W, H, FPS, SECS = 1920, 1080, 50, 22
N = int(os.environ.get("FRAMES", FPS * SECS))
T0 = float(os.environ.get("START", 0))           # render from this second on (stills for checking a beat)
rng = random.Random(13)
HN = "/System/Library/Fonts/HelveticaNeue.ttc"

SWITCH, STORM0, STORM1, ALIVE, UP, UNPLUG, FINALE = 2.0, 2.6, 4.6, 4.6, 6.0, 6.3, 15.2   # seconds
FLASHES = (2.7, 3.25, 3.9, 4.6)
BY, HZ, D = 832, 300, 1500                       # window's hinge (bottom edge) y, horizon y, camera distance
CLIPK = 0.78                                    # clip scale

def ease(x):
    x = min(max(x, 0), 1)
    return 1 - (1 - x) ** 3

def smooth(x):
    x = min(max(x, 0), 1)
    return x * x * (3 - 2 * x)

def back(x, s=2.2):
    x = min(max(x, 0), 1) - 1
    return 1 + (s + 1) * x ** 3 + s * x * x

def fade(im, a):
    if a >= 1:
        return im
    im = im.copy()
    im.putalpha(im.getchannel("A").point(lambda p: int(p * a)))
    return im

def plate(size, pad=150, r=120, a=190, blur=70):
    g = Image.new("RGBA", (size[0] + 2 * pad, size[1] + 2 * pad))
    ImageDraw.Draw(g).rounded_rectangle((pad, pad + 20, g.width - pad, g.height - pad - 20), r, fill=(255, 255, 255, a))
    return g.filter(ImageFilter.GaussianBlur(blur))

# --- logo (same look as cake.py / pinata.py)
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

# --- the lab: one static layer, drawn dark; `lit` is the same room with the lights up
lab = Image.new("RGBA", (W, H))
d = ImageDraw.Draw(lab)
for y in range(H):                                                                # stone wall, floor below 900
    c = 46 - 14 * y / H if y < 900 else 26
    d.line([(0, y), (W, y)], fill=(int(c * 0.8), int(c), int(c * 0.95), 255))
r = random.Random(5)
for row, y in enumerate(range(0, 900, 70)):                                      # mortar lines
    d.line([(0, y), (W, y)], fill=(22, 28, 26, 255), width=3)
    for x in range((row % 2) * 80, W, 160):
        d.line([(x, y), (x, y + 70)], fill=(22, 28, 26, 255), width=3)
for _ in range(220):                                                              # stone grain
    x, y = r.uniform(0, W), r.uniform(0, 900)
    d.ellipse((x, y, x + r.uniform(3, 14), y + r.uniform(2, 8)), fill=(30, 38, 35, 255))

SHELF_Y = 520
d.rectangle((300, SHELF_Y, 1620, SHELF_Y + 22), fill=(70, 48, 32, 255))         # shelf
d.rectangle((300, SHELF_Y + 22, 1620, SHELF_Y + 30), fill=(45, 30, 20, 255))
for x in (360, 1560):
    d.polygon([(x - 10, SHELF_Y + 30), (x + 10, SHELF_Y + 30), (x + 10, SHELF_Y + 90)], fill=(45, 30, 20, 255))

JARS = [(470, "WMP skin", (120, 170, 255)), (960, "macOS", (200, 200, 210)), (1450, "Winamp AVS", (255, 170, 60))]
JW, JH = 150, 200
tag = ImageFont.truetype(HN, 30, index=1)
for x, name, col in JARS:                                                         # specimen jars with a glowing fluid
    top = SHELF_Y - JH
    d.rounded_rectangle((x - JW / 2, top + 30, x + JW / 2, SHELF_Y), 24, fill=tuple(int(v * 0.35) for v in col) + (255,))
    d.rounded_rectangle((x - JW / 2 + 8, top + 70, x + JW / 2 - 8, SHELF_Y - 8), 18, fill=tuple(int(v * 0.6) for v in col) + (255,))
    for i in range(5):                                                            # bubbles
        bx, by = x + r.uniform(-45, 45), r.uniform(top + 80, SHELF_Y - 20)
        d.ellipse((bx - 5, by - 5, bx + 5, by + 5), outline=tuple(min(255, int(v * 1.1)) for v in col) + (255,), width=2)
    d.rounded_rectangle((x - JW / 2, top + 30, x + JW / 2, SHELF_Y), 24, outline=(170, 200, 190, 255), width=4)
    d.rectangle((x - JW / 2 + 12, top, x + JW / 2 - 12, top + 34), fill=(90, 90, 96, 255))  # lid + terminal
    d.rectangle((x - 6, top - 22, x + 6, top), fill=(150, 150, 160, 255))
    tw = tag.getlength(name) + 28
    d.rounded_rectangle((x - tw / 2, SHELF_Y + 40, x + tw / 2, SHELF_Y + 84), 6, fill=(226, 214, 180, 255))
    d.text((x, SHELF_Y + 62), name, font=tag, fill=(50, 34, 24, 255), anchor="mm")

COILS = [(150, 1000), (1770, 1000)]                                               # tesla coils: base centre
CTOP = 390                                                                        # toroid centre y
for cx, base in COILS:
    d.rectangle((cx - 70, base - 60, cx + 70, base), fill=(40, 40, 46, 255))
    d.rectangle((cx - 34, CTOP + 30, cx + 34, base - 60), fill=(150, 90, 40, 255))
    for y in range(CTOP + 36, base - 60, 9):                                      # copper winding
        d.line((cx - 34, y, cx + 34, y + 3), fill=(205, 130, 60, 255), width=3)
    d.ellipse((cx - 95, CTOP - 32, cx + 95, CTOP + 32), fill=(150, 155, 165, 255))
    d.ellipse((cx - 80, CTOP - 26, cx + 80, CTOP + 10), fill=(190, 195, 205, 255))

SW = (1600, 640)                                                                  # knife switch pivot
d.rounded_rectangle((SW[0] - 60, SW[1] - 150, SW[0] + 60, SW[1] + 40), 10, fill=(55, 40, 30, 255))
d.rectangle((SW[0] - 22, SW[1] - 130, SW[0] + 22, SW[1] - 104), fill=(180, 150, 80, 255))  # contact clips
d.rectangle((SW[0] - 22, SW[1] - 10, SW[0] + 22, SW[1] + 12), fill=(180, 150, 80, 255))

# slab: top surface trapezoid, front face, legs
d.polygon([(560, 690), (1360, 690), (1500, 856), (420, 856)], fill=(96, 98, 104, 255))
d.polygon([(560, 690), (1360, 690), (1372, 704), (548, 704)], fill=(120, 122, 128, 255))
d.rectangle((420, 856, 1500, 920), fill=(64, 66, 72, 255))
for x in (470, 1390):
    d.rectangle((x, 920, x + 60, 1040), fill=(50, 52, 58, 255))
d.ellipse((380, 1020, 1540, 1070), fill=(14, 18, 16, 255))
lab = lab.filter(ImageFilter.GaussianBlur(0.6))
lit = ImageEnhance.Brightness(lab).enhance(2.6)
vignette = Image.new("L", (W, H), 0)                                               # dark corners, lifted with the lights
ImageDraw.Draw(vignette).ellipse((-300, -200, W + 300, H + 300), fill=255)
vignette = vignette.filter(ImageFilter.GaussianBlur(220))
black = Image.new("RGBA", (W, H), (0, 0, 0, 255))

# --- the clip, cut out once: the window never moves inside it
raw = (790, 808)
CW, CH = int(raw[0] * CLIPK) // 2 * 2, int(raw[1] * CLIPK) // 2 * 2
dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", CLIP, "-vf", f"fps={FPS},scale={CW}:{CH}:flags=lanczos",
                        "-f", "rawvideo", "-pix_fmt", "rgba", "-"], stdout=subprocess.PIPE)
FB = CW * CH * 4

def clip_frame():
    b = dec.stdout.read(FB)
    return Image.frombytes("RGBA", (CW, CH), b) if len(b) == FB else None

first = clip_frame()
m = first.copy()
for c in [(0, 0), (CW - 1, 0), (0, CH - 1), (CW - 1, CH - 1)]:
    ImageDraw.floodfill(m, c, (0, 0, 0, 0), thresh=40)                          # bg + its soft drop shadow
MASK = m.getchannel("A").filter(ImageFilter.MinFilter(3))
BOX = MASK.getbbox()
MASK = MASK.crop(BOX)
WW, WH = MASK.size
PAD = 60                                                                          # room for the neck bolts

# stitches + bolts, in sprite space; they stay after it is alive
seams = Image.new("RGBA", (WW + 2 * PAD, WH + 2 * PAD))
sd = ImageDraw.Draw(seams)
r = random.Random(9)
for (x0, y0), (x1, y1) in [((0.08, 0.28), (0.62, 0.12)), ((0.55, 0.55), (0.95, 0.78)), ((0.04, 0.84), (0.5, 0.94))]:
    p0, p1 = (PAD + x0 * WW, PAD + y0 * WH), (PAD + x1 * WW, PAD + y1 * WH)
    L = math.dist(p0, p1)
    ux, uy = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
    pts = [(p0[0] + ux * s + r.uniform(-2, 2), p0[1] + uy * s + r.uniform(-2, 2)) for s in range(0, int(L), 12)]
    sd.line(pts, fill=(70, 20, 30, 255), width=5, joint="curve")                  # the scar
    for i, (x, y) in enumerate(pts[::2]):                                         # cross stitches
        k = 11 + (i % 2) * 3
        sd.line((x - uy * k - ux * 4, y + ux * k - uy * 4, x + uy * k + ux * 4, y - ux * k + uy * 4), fill=(30, 26, 24, 255), width=4)
clipped = Image.new("L", seams.size)                                              # scars only on the window itself
clipped.paste(MASK, (PAD, PAD))
seams.putalpha(ImageChops.multiply(seams.getchannel("A"), clipped))
sd = ImageDraw.Draw(seams)
BOLTS = [(PAD - 46, PAD + WH * 0.5), (PAD + WW + 46, PAD + WH * 0.5)]             # bolt tips, sprite space
for i, (bx, by) in enumerate(BOLTS):
    inner = PAD + (WW if i else 0)
    sd.rectangle((min(bx, inner), by - 13, max(bx, inner), by + 13), fill=(130, 134, 140, 255))
    for k in range(4):
        x = inner + (bx - inner) * (k + 0.5) / 4
        sd.line((x - 4, by - 13, x + 4, by + 13), fill=(90, 94, 100, 255), width=3)
    sd.rectangle((bx - 14, by - 26, bx + 14, by + 26), fill=(110, 114, 120, 255), outline=(60, 62, 68, 255), width=3)

def sprite(frame, life):
    """Clip frame → cut-out window with seams; pale and corpse-green while life < 1."""
    f = frame.crop(BOX)
    if life < 1:
        dead = ImageOps.colorize(ImageOps.grayscale(f), (18, 34, 24), (186, 214, 170)).convert("RGBA")
        f = Image.blend(dead, f, life) if life > 0 else dead
    f.putalpha(MASK)
    s = Image.new("RGBA", seams.size)
    s.alpha_composite(f, (PAD, PAD))
    s.alpha_composite(seams)
    return s

# --- hinge projection: the window lies flat (phi 0) and sits up (phi 90) about its bottom edge
def project(phi, x, y, cx):
    """Sprite point (x, y) → screen, for a window hinged on its bottom edge (y = PAD + WH) at BY, centred on cx."""
    h = PAD + WH - y                                                              # height above the hinge, sprite px
    z = h * math.cos(math.radians(phi))
    s = D / (D + z)
    return cx + (x - (WW / 2 + PAD)) * s, HZ + (BY - HZ) * s - h * math.sin(math.radians(phi)) * s

def coeffs(dst, src):
    """PIL PERSPECTIVE coefficients mapping output points `dst` back to sprite points `src`."""
    A, b = [], []
    for (X, Y), (x, y) in zip(dst, src):
        A += [[X, Y, 1, 0, 0, 0, -x * X, -x * Y], [0, 0, 0, X, Y, 1, -y * X, -y * Y]]
        b += [x, y]
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()

def place(fr, sp, phi, cx, dy=0):
    src = [(0, 0), (sp.width, 0), (sp.width, sp.height), (0, sp.height)]
    dst = [(x, y + dy) for x, y in (project(phi, x, y, cx) for x, y in src)]
    x0, y0 = int(min(p[0] for p in dst)), int(min(p[1] for p in dst))
    x1, y1 = int(max(p[0] for p in dst)) + 1, int(max(p[1] for p in dst)) + 1
    im = sp.transform((x1 - x0, y1 - y0), Image.PERSPECTIVE, coeffs([(x - x0, y - y0) for x, y in dst], src), Image.BICUBIC)
    paste(fr, im, x0 + im.width / 2, y0 + im.height / 2)

def paste(fr, im, cx, cy):
    x0, y0 = int(cx - im.width / 2), int(cy - im.height / 2)
    if x0 < W and y0 < H and x0 + im.width > 0 and y0 + im.height > 0:
        fr.alpha_composite(im, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))

def pose(t):
    """(phi, centre x, extra y) for the window at time t."""
    if t < ALIVE + 0.3:
        return 0, W / 2, 0
    u = (t - ALIVE - 0.3) / (UP - ALIVE - 0.3)
    bob = -6 * abs(math.sin((t - UP) * 3.4)) * smooth((t - UP) / 0.6) if t > UP else 0   # a little hop, never through the slab
    return 90 * back(u), W / 2, bob

# --- lightning: midpoint-displacement polylines, redrawn every frame so they flicker
def bolt(p0, p1, rr, jag=0.28, depth=6):
    pts = [p0, p1]
    for _ in range(depth):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            L = math.dist(a, b)
            nx, ny = -(b[1] - a[1]) / (L or 1), (b[0] - a[0]) / (L or 1)
            o = rr.uniform(-jag, jag) * L
            out += [((a[0] + b[0]) / 2 + nx * o, (a[1] + b[1]) / 2 + ny * o), b]
        pts = out
    return pts

def zap(fr, arcs):
    glow, core = Image.new("RGBA", (W, H)), Image.new("RGBA", (W, H))
    gd, cd = ImageDraw.Draw(glow), ImageDraw.Draw(core)
    for pts in arcs:
        gd.line(pts, fill=(120, 170, 255, 255), width=18)
        cd.line(pts, fill=(235, 245, 255, 255), width=3)
    fr.alpha_composite(glow.filter(ImageFilter.GaussianBlur(14)))
    fr.alpha_composite(core)

DEAD = sprite(first, 0)
BOLT_SCREEN = [project(0, *p, W / 2) for p in BOLTS]                              # where the bolts sit while it lies
JAR_TERM = [(x, SHELF_Y - JH - 22) for x, _, _ in JARS]
JAR_FOOT = [(x, SHELF_Y + 84) for x, _, _ in JARS]

def cable(fr, a, b, sag, col, w=7):
    pts = [((1 - s) ** 2 * a[0] + 2 * (1 - s) * s * (a[0] + b[0]) / 2 + s * s * b[0],
            (1 - s) ** 2 * a[1] + 2 * (1 - s) * s * (max(a[1], b[1]) + sag) + s * s * b[1]) for s in [i / 24 for i in range(25)]]
    ImageDraw.Draw(fr).line(pts, fill=col, width=w, joint="curve")
    return pts

# --- sparks: (time, count, origin, speed); the confetti physics from the other promos, in electric colours
SPARK = [(255, 240, 160), (255, 210, 90), (170, 210, 255), (255, 255, 255)]
sparks = []
for t0, n, (ox, oy), sp in ([(f, 60, BOLT_SCREEN[i % 2], 0.7) for i, f in enumerate(FLASHES)]
                            + [(UNPLUG, 70, BOLT_SCREEN[0], 0.6), (UNPLUG, 70, BOLT_SCREEN[1], 0.6)]
                            + [(FINALE, 240, (W / 2, 560), 0.85)]):
    for _ in range(n):
        a = math.radians(rng.uniform(-170, -10) if t0 == FINALE else rng.uniform(0, 360))
        v = rng.uniform(500, 1500) * sp
        sparks.append(dict(t0=t0, x=ox, y=oy, vx=v * math.cos(a), vy=v * math.sin(a), c=rng.choice(SPARK),
                           life=rng.uniform(0.5, 1.4) if t0 != FINALE else 9, sz=rng.uniform(5, 11)))

# --- finale caption
cap = Image.new("RGBA", (1900, 330))
cd = ImageDraw.Draw(cap)
cd.text((950, 90), "It's alive!", font=ImageFont.truetype(HN, 120, index=1), fill=(28, 30, 38, 255), anchor="mm")
cd.text((950, 215), "NullPlayer now has AVS", font=ImageFont.truetype(HN, 62, index=0), fill=(45, 48, 60, 255), anchor="mm")
cd.text((950, 290), "version 0.35.0", font=ImageFont.truetype(HN, 46, index=0), fill=(70, 74, 88, 255), anchor="mm")
cap = ImageOps.expand(cap.crop(cap.getbbox()), 60)                                # a margin, and a more solid card than the piñata's:
caption = plate(cap.size, 120, 100, 245, 30)                                       # it sits over the dark window
caption.alpha_composite(cap, (120, 120))

# electricity, synthesized on the absolute timeline: a clunk as the switch closes, a mains hum with tremolo and
# random crackle until it lives (then dying away), and a burst of noise on every lightning flash
ON = SWITCH + 0.5
env = f"between(t,{ON},{ALIVE + 1.5})*if(lt(t,{ALIVE}),1,exp(-(t-{ALIVE})*3))*(0.65+0.35*sin(2*PI*7*t))"
hum = "(sin(2*PI*120*t)+0.6*sin(2*PI*240*t)+0.35*sin(2*PI*360*t)+0.2*sin(2*PI*600*t))"
noise = "(2*random(0)-1)"
X = "(sin(floor(t*45)*12.9898)*43758.5453)"                                       # a fresh pseudo-random value every 22 ms
crackle = f"gt(abs({X}-trunc({X})),0.6)"
zaps = "+".join(f"exp(-abs(t-{f})*22)" for f in FLASHES)
clunk = f"between(t,{ON},{ON + 0.3})*sin(2*PI*70*t)*exp(-(t-{ON})*16)"
elec = (f"aevalsrc=exprs='{env}*(0.12*{hum}+0.35*{crackle}*{noise})+0.8*({zaps})*{noise}+0.9*{clunk}':s=44100:d={SECS},"
        f"atrim=start={T0},asetpts=PTS-STARTPTS[e]")
clip_a = f"[1:a]adelay={int(ALIVE * 1000)}:all=1,atrim=start={T0},asetpts=PTS-STARTPTS[c]"   # the clip's own sound, from the moment it lives
if AUDIO:                                                                         # the lab's ambience until then, ducking out as it lives
    ain = ["-i", CLIP, "-ss", str(ASTART + T0), "-i", AUDIO]
    beds = f"[2:a]atrim=end={max(0.01, ALIVE + 0.3 - T0)},afade=in:d=0.5,afade=out:st={max(0, ALIVE - 0.2 - T0)}:d=0.5[r];"
    ins = "[r][c][e]"
else:
    ain = ["-i", CLIP]
    beds, ins = "", "[c][e]"
af = (f"{clip_a};{elec};{beds}{ins}amix=inputs={ins.count('[')}:duration=longest:normalize=0,"
      f"afade=out:st={SECS - T0 - 2}:d=2[a]")
ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                       "-r", str(FPS), "-i", "-"] + ain
                      + ["-filter_complex", af, "-map", "0:v", "-map", "[a]", "-c:a", "aac", "-b:a", "256k",
                         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         "-t", str(SECS - T0), OUT], stdin=subprocess.PIPE)

frame = first
for _ in range(max(0, int((T0 - ALIVE) * FPS))):                                  # skip clip frames when starting late
    frame = clip_frame() or frame
for n in range(min(N, int((SECS - T0) * FPS))):
    t = T0 + n / FPS
    zr = random.Random(n)
    light = 0.15 + 0.85 * smooth((t - UP) / 6)                                     # lights come up after it sits up
    fl = max([max(0, 1 - abs(t - f) / 0.12) for f in FLASHES] + [0])              # lightning flash, 0..1
    fr = Image.blend(lab, lit, min(1, light * 0.75 + fl * 0.6))
    fr = Image.composite(fr, black, vignette.point(lambda p: int(p * (0.55 + 0.45 * light))))
    fr.alpha_composite(fade(brand, ease((t - 0.3) / 1.0)), BRAND_XY)
    fr = Image.composite(fr, black, Image.new("L", (W, H), int(255 * ease(t / 1.2))))   # fade in from black

    storm = STORM0 <= t < STORM1 + 0.15
    if t < UNPLUG:                                                                 # cables jar → bolts / clip on top
        hot = (255, 230, 150, 255) if storm and zr.random() < 0.6 else (30, 30, 34, 255)
        phi, cx, _ = pose(t)
        bs = [project(phi, *p, cx) for p in BOLTS]
        top = project(phi, PAD + WW / 2, PAD, cx)
        cable(fr, JAR_FOOT[0], bs[0], 120, hot)
        cable(fr, JAR_FOOT[2], bs[1], 120, hot)
        cable(fr, JAR_FOOT[1], top, 60, hot)

    a = (1 - smooth((t - SWITCH) / 0.5)) * math.radians(110)                       # knife switch: open at 110°, closed upright
    bx, by = SW[0] + 118 * math.sin(a), SW[1] - 118 * math.cos(a)
    hx, hy = SW[0] + 150 * math.sin(a), SW[1] - 150 * math.cos(a)
    dr = ImageDraw.Draw(fr)
    dr.line((SW[0], SW[1], bx, by), fill=(200, 170, 90, 255), width=14)           # blade
    dr.line((bx, by, hx, hy), fill=(40, 20, 16, 255), width=20)                    # insulated handle
    if t < SWITCH + 1.2:                                                           # the gloved hand on the handle
        k = 1 - smooth((t - SWITCH - 0.6) / 0.6)
        gx, gy = hx + 60 * (1 - k) + 20, hy + 40 * (1 - k)
        g = (20, 22, 20, int(255 * k))
        dr.ellipse((gx - 34, gy - 26, gx + 34, gy + 26), fill=g)
        for i in range(4):
            dr.rounded_rectangle((gx - 34 + i * 17, gy - 40, gx - 22 + i * 17, gy - 10), 6, fill=g)
        dr.polygon([(gx + 10, gy + 20), (gx + 80, gy + 70), (gx + 120, gy + 40), (gx + 30, gy - 6)], fill=g)  # cuff

    phi, cx, bob = pose(t)
    if t < ALIVE:
        sp = DEAD
    else:
        frame = clip_frame() or frame
        sp = sprite(frame, smooth((t - ALIVE) / 0.4))
    place(fr, sp, phi, cx, bob)

    if storm:                                                                      # arcs: coils → jars, jars → slab, the switch
        arcs = []
        for (cx_, _), (jx, jy) in zip(COILS, (JAR_TERM[0], JAR_TERM[2])):
            if zr.random() < 0.8:
                arcs.append(bolt((cx_ + (60 if cx_ < W / 2 else -60), CTOP), (jx, jy), zr))
        for jt, b in zip((JAR_TERM[0], JAR_TERM[2]), BOLT_SCREEN):
            if zr.random() < 0.35:
                arcs.append(bolt(b, (b[0] + zr.uniform(-120, 120), b[1] - zr.uniform(80, 200)), zr, 0.35, 4))
        if zr.random() < 0.5:
            arcs.append(bolt((COILS[0][0], CTOP - 30), (COILS[0][0] + zr.uniform(-80, 160), CTOP - zr.uniform(120, 260)), zr, 0.35, 4))
        if zr.random() < 0.5:
            arcs.append(bolt((COILS[1][0], CTOP - 30), (COILS[1][0] + zr.uniform(-160, 80), CTOP - zr.uniform(120, 260)), zr, 0.35, 4))
        if fl > 0.5:                                                               # the big one, down into the body
            arcs.append(bolt((JAR_TERM[1][0], JAR_TERM[1][1]), project(0, PAD + WW / 2, PAD + WH / 2, W / 2), zr, 0.3))
        zap(fr, arcs)
    if fl:
        fr = Image.blend(fr, Image.new("RGBA", (W, H), (235, 240, 255, 255)), fl * 0.55)

    if t > FINALE:
        a = ease((t - FINALE) / 0.9)
        c = caption.resize((int(caption.width * (0.9 + 0.1 * a)), int(caption.height * (0.9 + 0.1 * a))), Image.LANCZOS)
        paste(fr, fade(c, a), W / 2, 560)

    sd = ImageDraw.Draw(fr)
    for s in sparks:
        dt = t - s["t0"]
        if not 0 <= dt < s["life"]:
            continue
        drag = 1 - math.exp(-dt * 2.2)
        x = s["x"] + s["vx"] / 2.2 * drag
        y = s["y"] + s["vy"] / 2.2 * drag + 300 * dt * dt
        if y > H + 20:
            continue
        vx, vy = s["vx"] * math.exp(-dt * 2.2), s["vy"] * math.exp(-dt * 2.2) + 600 * dt
        v = math.hypot(vx, vy) or 1
        k = s["sz"] * (1 + v / 300)
        sd.line((x, y, x - vx / v * k, y - vy / v * k), fill=s["c"], width=3)

    if storm:                                                                      # shake
        fr = ImageChops.offset(fr, zr.randint(-6, 6), zr.randint(-5, 5))
    ff.stdin.write(fr.tobytes())
    if n % 100 == 0:
        print(f"{t:.1f}s", file=sys.stderr)
ff.stdin.close()
ff.wait()
dec.kill()
