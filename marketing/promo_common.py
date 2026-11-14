# promo_common.py — what the promo scripts in marketing/ share: easing curves, an alpha fade, a clipped paste,
# the soft white plate behind text, and the NullPlayer logo + url card at the top of the frame.
# A script one directory down imports it after putting marketing/ on sys.path.
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HN = "/System/Library/Fonts/HelveticaNeue.ttc"
ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../Sources/NullPlayer/Resources/AppIcon.png")

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

def paste(fr, im, cx, cy):
    """Alpha-composite `im` centred on (cx, cy), clipped to the frame."""
    x0, y0 = int(cx - im.width / 2), int(cy - im.height / 2)
    if x0 < fr.width and y0 < fr.height and x0 + im.width > 0 and y0 + im.height > 0:
        fr.alpha_composite(im, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))

def plate(size, pad=150, r=120, a=190, blur=70):
    """A blurred white rounded rectangle to sit behind text of `size`, `pad` px larger all round."""
    g = Image.new("RGBA", (size[0] + 2 * pad, size[1] + 2 * pad))
    ImageDraw.Draw(g).rounded_rectangle((pad, pad + 20, g.width - pad, g.height - pad - 20), r, fill=(255, 255, 255, a))
    return g.filter(ImageFilter.GaussianBlur(blur))

def brand(frame_w, url_y=405):
    """The icon + "NullPlayer" + url card on its plate, and where it goes at the top centre of the frame.
    `url_y` places the url line in the 450 px tall logo before its half-size downsample."""
    font = ImageFont.truetype(HN, 230, index=1)
    icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
    logo = Image.new("RGBA", (300 + 50 + int(font.getlength("NullPlayer")) + 40, 450))
    logo.alpha_composite(icon, (0, 30))
    ld = ImageDraw.Draw(logo)
    ld.text((350, 180), "NullPlayer", font=font, fill=(28, 30, 38, 255), anchor="lm")
    ld.text((logo.width // 2, url_y), "nullplayer.fyi", font=ImageFont.truetype(HN, 76, index=0), fill=(45, 48, 60, 255), anchor="mm")
    logo = logo.resize((int(logo.width * 0.5), int(logo.height * 0.5)), Image.LANCZOS)
    card = plate(logo.size, 110, 90, 170, 50)
    card.alpha_composite(logo, (110, 110))
    return card, ((frame_w - card.width) // 2, 40 - 110)
