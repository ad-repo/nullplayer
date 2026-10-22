# promo.py <out.mp4> [raw_dir] — 20 s rain of every non-Audion skin (plus 420 Audion faces) behind the logo and nullplayer.fyi.
# raw_dir holds transparent <family>_<skin>.png cutouts (default ~/Documents/shots/reshoot-2026-10-11-v2/raw); FRAMES=n renders a short test.
import glob, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/Documents/shots/reshoot-2026-10-11-v2/raw")
ICON = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "../../Sources/NullPlayer/Resources/AppIcon.png")
W, H, FPS, SECS = 1920, 1080, 50, 20
N = int(os.environ.get("FRAMES", FPS * SECS))
rng = random.Random(7)

fams = {}
for f in sorted(glob.glob(RAW + "/*.png")):
    fams.setdefault(os.path.basename(f).split("_")[0], []).append(f)
# every non-Audion skin, plus enough Audion faces to keep the mix even-ish
pool = []
for fam, fs in fams.items():
    rng.shuffle(fs)
    pool += fs[:420] if fam == "audion" else fs
rng.shuffle(pool)
print({k: len(v) for k, v in fams.items()}, "using", len(pool), file=sys.stderr)

# depth layers: (target max-side px range, speed px/s range, blur, alpha)
LAYERS = [((90, 150), (170, 250), 2.5, 0.55),
          ((160, 250), (270, 390), 1.0, 0.85),
          ((260, 380), (420, 590), 0, 1.0)]
sprites = []
for i, f in enumerate(pool):
    layer = rng.choices([0, 1, 2], [0.45, 0.37, 0.18])[0]
    (s0, s1), (v0, v1), blur, alpha = LAYERS[layer]
    im = Image.open(f).convert("RGBA")
    im = im.crop(im.getbbox() or (0, 0, *im.size))
    k = rng.uniform(s0, s1) / max(im.size)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    im = im.rotate(rng.uniform(-12, 12), Image.BICUBIC, expand=True)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    if alpha < 1:
        im.putalpha(im.getchannel("A").point(lambda a: int(a * alpha)))
    v = rng.uniform(v0, v1)
    # spread spawn times so the screen is already full at t=0
    t0 = (i / len(pool)) * (SECS + 4.5) - 5 + rng.uniform(-0.3, 0.3)
    x = rng.uniform(-im.width / 2, W - im.width / 2)
    sprites.append((layer, t0, x, v, im))
sprites.sort(key=lambda s: s[0])

# background: soft vertical grey-blue gradient
bg = Image.new("RGBA", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    c = int(212 - 30 * y / H)
    d.line([(0, y), (W, y)], fill=(c - 8, c - 2, c + 10, 255))

# logo: icon + wordmark on a soft white glow
font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 230, index=1)
icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
tw = int(font.getlength("NullPlayer"))
logo = Image.new("RGBA", (300 + 50 + tw + 40, 450), (0, 0, 0, 0))
logo.alpha_composite(icon, (0, 30))
ld = ImageDraw.Draw(logo)
ld.text((350, 180), "NullPlayer", font=font, fill=(28, 30, 38, 255), anchor="lm")
url_font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 76, index=0)
ld.text((logo.width // 2, 405), "nullplayer.fyi", font=url_font, fill=(45, 48, 60, 255), anchor="mm")
glow = Image.new("RGBA", (logo.width + 300, logo.height + 300), (0, 0, 0, 0))
ImageDraw.Draw(glow).rounded_rectangle((150, 170, glow.width - 150, glow.height - 170), 120, fill=(255, 255, 255, 190))
glow = glow.filter(ImageFilter.GaussianBlur(70))
lx, ly = (W - logo.width) // 2, (H - logo.height) // 2

ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                       "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                       "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
                       "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)

def ease(x):
    x = min(max(x, 0), 1)
    return 1 - (1 - x) ** 3

for n in range(N):
    t = n / FPS
    fr = bg.copy()
    logo_drawn = False
    for layer, t0, x, v, im in sprites:
        if layer == 2 and not logo_drawn:
            a = ease((t - 0.4) / 1.2)
            if a > 0:
                g, l = glow, logo
                if a < 1:
                    s = 0.85 + 0.15 * a
                    g = glow.resize((int(glow.width * s), int(glow.height * s)))
                    l = logo.resize((int(logo.width * s), int(logo.height * s)), Image.LANCZOS)
                    g.putalpha(g.getchannel("A").point(lambda p: int(p * a)))
                    l.putalpha(l.getchannel("A").point(lambda p: int(p * a)))
                fr.alpha_composite(g, ((W - g.width) // 2, (H - g.height) // 2))
                fr.alpha_composite(l, ((W - l.width) // 2, (H - l.height) // 2))
            logo_drawn = True
        y = -im.height + (t - t0) * v
        if -im.height < y < H:
            x0, y0 = int(x), int(y)
            fr.alpha_composite(im, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))
    ff.stdin.write(fr.tobytes())
    if n % 100 == 0:
        print(n, file=sys.stderr)
ff.stdin.close()
ff.wait()
