# render.py [out.mp4] [frame numbers...] — the 16 s NullPlayer demo: intro, skin showcase, skin wall, end card; frame numbers write stills instead.
# Media comes from $ASSETS (default ~/Documents/shots/demo-video): cut/ and close/ hold the cutouts; out and stills land there too.
import math, os, subprocess, sys, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

D = os.environ.get("ASSETS", os.path.expanduser("~/Documents/shots/demo-video"))
CUT = os.path.join(D, "cut")
ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../Sources/NullPlayer/Resources/AppIcon.png")
W, H, FPS, DUR = 1920, 1080, 60, 14.0
SLOW = 1.15  # uniform playback stretch; scene timings above stay as authored
BG = (251, 251, 253)
INK = (29, 29, 31)
GRAY = (110, 110, 115)
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([100, min(96, size), 400, weight])
    return f


# ---------- easing ----------
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

def ease_out(t):  # cubic-bezier-ish (0.22, 1, 0.36, 1)
    t = clamp(t); return 1 - (1 - t) ** 4

def ease_in_out(t):
    t = clamp(t); return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2

def spring(t):
    t = clamp(t)
    return 1 - math.exp(-6 * t) * math.cos(9 * t) if t < 1 else 1.0

def prog(t, start, dur):
    return clamp((t - start) / dur)


# ---------- assets ----------
def text_layer(s, size, weight, color=INK, tracking=0.0, gradient=None):
    f = font(size, weight)
    pad = size // 2
    # measure with tracking
    widths = [f.getlength(c) for c in s]
    tw = int(sum(widths) + tracking * size * (len(s) - 1)) + pad * 2
    asc, desc = f.getmetrics()
    th = asc + desc + pad * 2
    img = Image.new("L", (tw, th), 0)
    d = ImageDraw.Draw(img)
    x = pad
    for c, w in zip(s, widths):
        d.text((x, pad), c, font=f, fill=255)
        x += w + tracking * size
    bbox = img.getbbox()
    img = img.crop((bbox[0] - 4, 0, bbox[2] + 4, th))
    if gradient:
        c0, c1 = gradient
        grad = Image.linear_gradient("L").rotate(90, expand=True).resize(img.size)
        col = Image.composite(Image.new("RGB", img.size, c1), Image.new("RGB", img.size, c0), grad.transpose(Image.FLIP_LEFT_RIGHT))
        out = col.convert("RGBA"); out.putalpha(img)
        return out
    out = Image.new("RGBA", img.size, color + (0,))
    out.putalpha(img)
    return out


def with_shadow(img, radius=28, offset=18, opacity=0.22):
    """Soft Apple-style floating shadow under a cut-out window."""
    pad = radius * 3
    w, h = img.size
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    a = img.getchannel("A").point(lambda v: int(v * opacity))
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0)); sh.putalpha(a)
    canvas.alpha_composite(sh, (pad, pad + offset))
    canvas = canvas.filter(ImageFilter.GaussianBlur(radius))
    canvas.alpha_composite(img, (pad, pad))
    return canvas


def load_cut(name_prefix):
    for f in sorted(os.listdir(CUT)):
        if f.startswith(name_prefix):
            return Image.open(os.path.join(CUT, f)).convert("RGBA")
    raise SystemExit("missing " + name_prefix)


def fit(img, maxw, maxh):
    s = min(maxw / img.width, maxh / img.height)
    return img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)


def place(frame, layer, cx, cy, scale=1.0, alpha=1.0):
    """Composite layer centred at (cx, cy) with sub-pixel position + scale."""
    if alpha <= 0.002 or scale <= 0.01:
        return
    lw, lh = layer.size
    ow, oh = lw * scale, lh * scale
    x0, y0 = cx - ow / 2, cy - oh / 2
    ix, iy = math.floor(x0), math.floor(y0)
    bw, bh = math.ceil(ow) + 2, math.ceil(oh) + 2
    fx, fy = x0 - ix, y0 - iy
    inv = 1.0 / scale
    t = layer.transform((bw, bh), Image.AFFINE, (inv, 0, -fx * inv, 0, inv, -fy * inv), resample=Image.BICUBIC)
    if alpha < 1:
        t.putalpha(t.getchannel("A").point(lambda v: int(v * alpha)))
    frame.alpha_composite(t, (ix, iy)) if ix >= 0 and iy >= 0 and ix + bw <= W and iy + bh <= H else paste_clipped(frame, t, ix, iy)


def paste_clipped(frame, t, ix, iy):
    l, tp = max(0, -ix), max(0, -iy)
    r, b = min(t.width, W - ix), min(t.height, H - iy)
    if r <= l or b <= tp:
        return
    frame.alpha_composite(t.crop((l, tp, r, b)), (ix + l, iy + tp))


# Scene 1/4 assets
icon = Image.open(ICON).convert("RGBA")
icon = icon.crop(icon.getbbox())
icon_big = with_shadow(fit(icon, 300, 300), radius=30, offset=20, opacity=0.25)
icon_small = with_shadow(fit(icon, 150, 150), radius=18, offset=12, opacity=0.22)
ORANGE = ((255, 159, 28), (255, 214, 102))
t_name = text_layer("NullPlayer", 150, 700, tracking=-0.02)
t_tag = text_layer("Your media. Your backend. Your UI.", 52, 500, GRAY, tracking=-0.005)

# Scene 2 — one player, every skin
t_every = text_layer("Every skin. Live.", 96, 700, tracking=-0.02)
# The user's chosen close-ups ("untitled folder"), cut out into close/; Anemone uses the
# full-res corpus shot instead of the 500px GIF-frame TIFF.
CLOSE = os.path.join(D, "close")
CLASSIC, MODERN, WMP = "Winamp Classic", "Winamp Modern", "Windows Media Player"
SHOWCASE = [
    (CLOSE, "classic_winamp_screenshot", CLASSIC),
    (CLOSE, "modern_cPro_Insomnis_v2", MODERN),
    (CLOSE, "wmp_Alienware-Invader", WMP),
    (CLOSE, "modern_mmd3", MODERN),
    (CUT, "wmp_anemone", WMP),
    (CLOSE, "modern_cassette_screenshot", MODERN),
    (CLOSE, "Screenshot_2026-09-30", WMP),
    (CLOSE, "modern_Anaheim_Player_01", MODERN),
    (CLOSE, "wmp_Half-Life_2", WMP),
    (CLOSE, "modern_winampmodern566", MODERN),
    (CLOSE, "wmp_cerulean", WMP),
]
labels = {k: text_layer(k, 40, 500, GRAY) for k in (CLASSIC, MODERN, WMP)}
show = []
for folder, pref, label in SHOWCASE:
    f = next(x for x in sorted(os.listdir(folder)) if x.startswith(pref))
    im = Image.open(os.path.join(folder, f)).convert("RGBA")
    s = min(1150 / im.width, 600 / im.height, 2.6)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    show.append((with_shadow(im, radius=34, offset=24, opacity=0.24), labels[label]))

# Scene 3 — the wall
# Hand-picked: no close-up skins, no stock defaults, families interleaved in every row.
WALL = [
    ["wmp_Asimov_Radio", "modern_Rika", "classic_QOTSA", "wmp_Jaws", "modern_T800", "wmp_Plus-Aquarium",
     "original_HyperPopPrism", "wmp_Gorillaz", "modern_ZDL_Reel", "wmp_TDK", "classic_Rush_Hemispheres",
     "wmp_Heart_Butterfly", "modern_Ujola-Cat", "wmp_Raptor", "modern_Sony_Walkman", "wmp_NVIDIA"],
    ["modern_Bio-Nid", "wmp_Age_of_Mythology_MP7", "classic_aquamp", "wmp_Project-Gotham-Racing-2_2026",
     "modern_The_Nokia", "wmp_Grinch", "wmp_Alienware_Darkstar", "wmp_Plus-da-Vinci", "modern_Overdrive_2",
     "wmp_Josie", "classic_ExpensiveHi-Fi", "wmp_MechAssault", "modern_HeadAMP", "modern_PokemonDS", "wmp_Rave-MP", "classic_Nucleo-Alien"],
    ["wmp_KungFuChaos", "modern_1-Hal", "classic_RUSH_DEBUT", "wmp_Tomb-Raider-2", "modern_BLAKK",
     "wmp_The_Last_Samurai", "wmp_Toothy", "modern_Lobe", "classic_retradio", "wmp_elvis",
     "wmp_SplinterCell", "modern_2222-cPro__Bento", "wmp_springflower", "wmp_xsn_sports", "modern_Enkera", "wmp_Plus-Bionic-Dot"],
]
ROW_H = 210
WALL_DUR = 4.5
rows = []
for names, speed, direction in zip(WALL, (400, 460, 360), (-1, 1, -1)):
    tiles = []
    for n in names:
        im = load_cut(n)
        im = fit(im, 520, ROW_H)
        tiles.append(with_shadow(im, radius=14, offset=10, opacity=0.18))
    rows.append((tiles, speed, direction))

t_first = text_layer("Any skin on the internet.", 76, 700, tracking=-0.02)
t_first_sub = text_layer("Thousands of Winamp and Windows Media Player skins. The first Mac player to run them all.", 34, 500, GRAY)

# Scene 4 — end card
t_lines = [text_layer(x, 34, 500, GRAY) for x in (
    "Local files  ·  Plex  ·  Jellyfin  ·  Emby  ·  Navidrome  ·  YouTube  ·  Radio",
    "Sonos  ·  Chromecast  ·  AirPlay  ·  DLNA",
    "projectM  ·  Geiss  ·  Tripex  ·  Cava",
)]
t_free = text_layer("Free and open source. For macOS.", 44, 600, INK, tracking=-0.005)
t_name_end = text_layer("NullPlayer", 120, 700, tracking=-0.02)


def build_strip(tiles, gap=56):
    widths = [t.width - 2 * 42 for t in tiles]  # shadow padding overlaps
    return tiles, widths, sum(widths) + gap * len(tiles)


strips = []
for tiles, speed, direction in rows:
    tl, widths, total = build_strip(tiles)
    strips.append((tl, widths, total, speed, direction))


# ---------- scenes ----------
def scene_intro(f, t):
    # icon springs in, rises, name + tagline follow
    p = spring(prog(t, 0.0, 0.9))
    rise = ease_in_out(prog(t, 0.55, 0.6))
    cy = H / 2 - 20 - rise * 170
    place(f, icon_big, W / 2, cy, scale=0.6 + 0.4 * p, alpha=clamp(t / 0.35))
    a = ease_out(prog(t, 0.8, 0.5))
    place(f, t_name, W / 2, H / 2 + 110 + (1 - a) * 30, alpha=a)
    b = ease_out(prog(t, 1.05, 0.5))
    place(f, t_tag, W / 2, H / 2 + 230 + (1 - b) * 24, alpha=b)


def scene_skins(f, t):
    a = ease_out(prog(t, 0.0, 0.5))
    place(f, t_every, W / 2, 150 + (1 - a) * 24, alpha=a)
    per = 0.5
    for i, (img, label) in enumerate(show):
        s = i * per
        local = t - s
        if local < 0 or local > per:
            continue
        inn = ease_out(local / 0.25)
        out = ease_in_out(clamp((local - per + 0.15) / 0.15)) if i < len(show) - 1 else 0
        alpha = inn * (1 - out)
        scale = 0.94 + 0.06 * inn
        dx = (1 - inn) * 90 - out * 90
        place(f, img, W / 2 + dx, H / 2 + 50, scale=scale, alpha=alpha)
        place(f, label, W / 2, H - 110, alpha=alpha)


def scene_wall(f, t):
    top = 300
    for r, (tl, widths, total, speed, direction) in enumerate(strips):
        y = top + r * (ROW_H + 40) + ROW_H / 2
        start = -200 - (speed * WALL_DUR if direction > 0 else 0)
        x = (start + direction * speed * t + 600) % total - 600 - total
        idx = 0
        a = ease_out(prog(t, 0.08 * r, 0.6))
        while x < W + 400:
            tile = tl[idx % len(tl)]; w = widths[idx % len(tl)]
            if x + w > -400:
                place(f, tile, x + w / 2, y + (1 - a) * 40, alpha=a)
            x += w + 56
            idx += 1
    # headline on a soft band
    a = ease_out(prog(t, 0.1, 0.45))
    band = Image.new("RGBA", (W, 290), BG + (0,))
    grad = Image.linear_gradient("L").resize((W, 290)).point(lambda v: int(255 - v))
    band.putalpha(grad.point(lambda v: min(255, int(v * 1.6))))
    f.alpha_composite(band, (0, 0))
    place(f, t_first, W / 2, 125 + (1 - a) * 24, alpha=a)
    b = ease_out(prog(t, 0.35, 0.55))
    place(f, t_first_sub, W / 2, 215 + (1 - b) * 18, alpha=b)


def scene_end(f, t):
    p = spring(prog(t, 0.0, 0.8))
    place(f, icon_small, W / 2, 290, scale=0.7 + 0.3 * p, alpha=clamp(t / 0.3))
    a = ease_out(prog(t, 0.15, 0.5))
    place(f, t_name_end, W / 2, 480 + (1 - a) * 26, alpha=a)
    b = ease_out(prog(t, 0.35, 0.5))
    place(f, t_free, W / 2, 600 + (1 - b) * 22, alpha=b)
    for k, line in enumerate(t_lines):
        c = ease_out(prog(t, 0.55 + 0.12 * k, 0.5))
        place(f, line, W / 2, 690 + 56 * k + (1 - c) * 18, alpha=c)


SCENES = [  # (start, end, fn)
    (0.0, 2.0, scene_intro),
    (2.0, 7.5, scene_skins),
    (7.5, 12.0, scene_wall),
    (12.0, 14.0, scene_end),
]
XF = 0.18


def render(i):
    t = i / FPS / SLOW
    frame = Image.new("RGBA", (W, H), BG + (255,))
    for s, e, fn in SCENES:
        if s <= t < e:
            layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            fn(layer, t - s)
            fade = 1.0
            if s > 0 and t < s + XF:
                fade = ease_in_out((t - s) / XF)
            if e < DUR and t > e - XF:
                fade = min(fade, 1 - ease_in_out((t - (e - XF)) / XF))
            if fade < 1:
                layer.putalpha(layer.getchannel("A").point(lambda v: int(v * fade)))
            frame.alpha_composite(layer)
    return frame.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(D, "nullplayer-demo.mp4")
    only = sys.argv[2:]
    if only:  # stills: frame numbers
        for n in only:
            render(int(n)).save(os.path.join(D, f"still_{n}.png"))
        sys.exit()
    n = int(round(DUR * SLOW * FPS))
    p = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                          "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                          "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
                          "-movflags", "+faststart", out], stdin=subprocess.PIPE)
    for i in range(n):
        p.stdin.write(render(i).tobytes())
        if i % 60 == 0:
            print(i, flush=True)
    p.stdin.close(); p.wait()
    print("wrote", out)
