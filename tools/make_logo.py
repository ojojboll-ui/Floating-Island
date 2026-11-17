"""Skyholme's title lettering, as a storybook heading: IM Fell English
(fonts/, SIL OFL) set on a gentle arch, cream letters with an ink rim and a
warm gold edge, a vine with leaves curling out under the name, a few
sparkles. Writes brand/logo.png (for the sky) and brand/logo_ink.png (dark,
for paper), at 2400 px wide; the game scales them down.

    python -I tools/make_logo.py
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
ROOT = os.path.dirname(HERE)
FONT = os.path.join(ROOT, "fonts", "IMFeENrm28P.ttf")
OUT = os.path.join(ROOT, "brand")

W, H = 2400, 1000
SIZE = 440          # letter size, px
ARCH = 70           # how far the middle of the word rises above its ends
TRACK = 6           # extra space between letters
WORD = "Skyholme"

INK = (62, 44, 32)
CREAM = (255, 249, 232)
GOLD = (236, 196, 118)
LEAF = (112, 150, 74)
LEAF_DARK = (74, 106, 52)


def letters_mask(font):
    """The word on its arch, as a mask: each letter turned to follow it."""
    widths = [font.getlength(c) + TRACK for c in WORD]
    total = sum(widths) - TRACK
    mask = Image.new("L", (W, H), 0)
    x = (W - total) / 2.0
    base = H * 0.58
    for c, w in zip(WORD, widths):
        mid = x + (w - TRACK) / 2.0
        t = (mid - W / 2.0) / (total / 2.0)          # -1 .. 1 along the word
        y = base - ARCH * (1.0 - t * t)
        slope = 2.0 * ARCH * t / (total / 2.0)       # dy/dx of the arch
        ang = math.degrees(math.atan(slope))
        tile = Image.new("L", (int(SIZE * 1.8), int(SIZE * 1.8)), 0)
        d = ImageDraw.Draw(tile)
        d.text((tile.width / 2.0, tile.height / 2.0), c, font=font, fill=255, anchor="ms")
        tile = tile.rotate(ang, resample=Image.BICUBIC)
        mask.paste(255, (int(mid - tile.width / 2.0), int(y - tile.height / 2.0)), tile)
        x += w
    return mask


def grow(mask, px):
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def vine(draw, ink, leaf, leaf_dark, scale=1.0):
    """A curling vine under the name, mirrored about the middle, with leaves."""
    cx = W / 2.0
    y0 = H * 0.735
    for side in (-1,):
        pts = []
        for k in range(121):
            t = k / 120.0
            x = cx + side * (40 + t * 760)
            y = y0 + math.sin(t * math.pi * 1.6) * 34 * (1.0 - t * 0.5) - t * 40
            pts.append((x, y))
        draw.line(pts, fill=ink, width=int(13 * scale), joint="curve")
        draw.line(pts, fill=leaf_dark, width=int(5 * scale), joint="curve")
        # the curl at its end
        ex, ey = pts[-1]
        for k in range(60):
            a = k / 59.0 * math.pi * 1.6
            r = 40 * (1.0 - k / 70.0)
            p = (ex + side * (math.sin(a) * r), ey - 40 + math.cos(a) * r)
            if k:
                draw.line([q, p], fill=ink, width=int(11 * scale))
            q = p
        # leaves along it, alternately above and below
        for k, t in enumerate([0.12, 0.27, 0.42, 0.58, 0.74, 0.88]):
            px, py = pts[int(t * 120)]
            up = -1 if k % 2 == 0 else 1
            leaf_at(draw, px, py, side, up, 58 * (1.1 - t * 0.5), ink, leaf)
    # a small bud where the two halves meet
    draw.ellipse([cx - 26, y0 - 26, cx + 26, y0 + 26], fill=ink)
    draw.ellipse([cx - 15, y0 - 15, cx + 15, y0 + 15], fill=GOLD)


def leaf_at(draw, x, y, side, up, size, ink, fill):
    """A pointed leaf leaning out along the vine."""
    a = math.radians(-35 * up) + (0 if side > 0 else math.pi)
    tip = (x + math.cos(a) * size, y + math.sin(a) * size * 1.0 + up * size * 0.5)
    nx, ny = -(tip[1] - y), tip[0] - x
    n = math.hypot(nx, ny) or 1.0
    nx, ny = nx / n * size * 0.32, ny / n * size * 0.32
    mid = ((x + tip[0]) / 2.0, (y + tip[1]) / 2.0)
    shape = [(x, y), (mid[0] + nx, mid[1] + ny), tip, (mid[0] - nx, mid[1] - ny)]
    draw.polygon(shape, fill=ink)
    inner = [(x + (p[0] - x) * 0.78 + (tip[0] - x) * 0.1, y + (p[1] - y) * 0.78 + (tip[1] - y) * 0.1) for p in shape]
    draw.polygon(inner, fill=fill)
    draw.line([(x, y), tip], fill=ink, width=3)


def sparkle(draw, x, y, r, col):
    """A four-pointed glint."""
    pts = []
    for k in range(8):
        a = k * math.pi / 4.0
        rr = r if k % 2 == 0 else r * 0.22
        pts.append((x + math.sin(a) * rr, y - math.cos(a) * rr))
    draw.polygon(pts, fill=col)


def make(light):
    font = ImageFont.truetype(FONT, SIZE)
    letters = letters_mask(font)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # a soft shadow under everything, only on the sky version
    if light:
        sh = grow(letters, 20).filter(ImageFilter.GaussianBlur(24))
        shadow = Image.new("RGBA", (W, H), (20, 30, 70, 0))
        shadow.putalpha(sh.point(lambda v: int(v * 0.45)))
        out.alpha_composite(shadow, (0, 14))

    # the vine: its left half drawn, the right half the same mirrored
    deco = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    vine(ImageDraw.Draw(deco), INK + (255,), LEAF + (255,) if light else (150, 170, 110, 255), LEAF_DARK + (255,))
    half = deco.crop((0, 0, W // 2, H))
    deco.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (W // 2, 0), half.transpose(Image.FLIP_LEFT_RIGHT))
    bud = ImageDraw.Draw(deco)
    bud.ellipse([W / 2 - 26, H * 0.735 - 26, W / 2 + 26, H * 0.735 + 26], fill=INK + (255,))
    bud.ellipse([W / 2 - 15, H * 0.735 - 15, W / 2 + 15, H * 0.735 + 15], fill=GOLD + (255,))
    out.alpha_composite(deco)

    # the ink rim, the gold edge inside it, then the face
    rim = Image.new("RGBA", (W, H), INK + (255,))
    rim.putalpha(grow(letters, 13))
    out.alpha_composite(rim)
    if light:
        gold = Image.new("RGBA", (W, H), GOLD + (255,))
        gold.putalpha(grow(letters, 6))
        out.alpha_composite(gold)
        # the face: cream, warming a little toward the foot of each letter
        face = Image.new("RGBA", (W, H), CREAM + (255,))
        warm = Image.linear_gradient("L").resize((W, H)).point(lambda v: int(max(0, v - 120) * 0.35))
        face = Image.composite(Image.new("RGBA", (W, H), (248, 226, 180, 255)), face, warm)
        face.putalpha(letters)
        out.alpha_composite(face)
        # a fine highlight along the tops of the letters
        hi = ImageChops.subtract(letters, letters.transform(letters.size, Image.AFFINE, (1, 0, 0, 0, 1, -7)))
        hi_img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
        hi_img.putalpha(hi.point(lambda v: int(v * 0.8)))
        out.alpha_composite(hi_img)
    else:
        face = Image.new("RGBA", (W, H), (120, 84, 52, 255))
        face.putalpha(letters)
        out.alpha_composite(face)

    d = ImageDraw.Draw(out)
    glint = (255, 244, 210, 255) if light else (176, 132, 70, 255)
    for x, y, r in [(470, 240, 34), (1980, 210, 42), (2080, 330, 20), (360, 380, 18), (1200, 120, 26)]:
        sparkle(d, x, y, r, glint)
    return out.crop(out.getbbox())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make(True).save(os.path.join(OUT, "logo.png"))
    make(False).save(os.path.join(OUT, "logo_ink.png"))
    print("logo written to", OUT)


# ------------------------------------------------------------------ emblem

def emblem(size=1024):
    """The program icon: a parchment medallion with an inked rim, sky inside,
    and the island with its tree, drawn like a woodcut coloured by hand."""
    S = size / 1024.0
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2.0

    def circ(r, **kw):
        d.ellipse([c - r * S, c - r * S, c + r * S, c + r * S], **kw)

    circ(500, fill=INK)
    circ(484, fill=(238, 222, 186))
    circ(462, fill=INK)
    # the sky, lighter toward the horizon
    sky = Image.new("RGBA", (size, size))
    grad = Image.linear_gradient("L").resize((size, size))
    top, low = (92, 140, 196), (196, 222, 236)
    sky = Image.merge("RGB", [grad.point(lambda v, a=a, b=b: int(a + (b - a) * v / 255)) for a, b in zip(top, low)]).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([c - 452 * S, c - 452 * S, c + 452 * S, c + 452 * S], fill=255)
    img.paste(sky, (0, 0), mask)
    d = ImageDraw.Draw(img)
    lw = max(2, int(12 * S))

    def poly(pts, fill):
        q = [(c + x * S, c + y * S) for x, y in pts]
        d.polygon(q, fill=fill)
        d.line(q + [q[0]], fill=INK, width=lw, joint="curve")

    def blob(x, y, r, fill):
        d.ellipse([c + (x - r) * S, c + (y - r) * S, c + (x + r) * S, c + (y + r) * S], fill=fill, outline=INK, width=lw)

    # clouds
    for x, y, r in [(-250, -170, 60), (-195, -185, 75), (-140, -165, 55), (250, 210, 50), (300, 195, 62), (345, 215, 45)]:
        blob(x, y, r, (255, 251, 240))
    # the rock under the island, hanging to a point
    poly([(-270, 90), (270, 90), (230, 150), (160, 175), (110, 270), (60, 230), (0, 380), (-55, 240), (-120, 265), (-160, 170), (-235, 150)], (150, 108, 74))
    poly([(0, 380), (-55, 240), (-20, 120), (35, 120), (60, 230)], (118, 82, 56))
    # the grass top
    d.ellipse([c - 300 * S, c + 30 * S, c + 300 * S, c + 140 * S], fill=(124, 176, 78), outline=INK, width=lw)
    d.ellipse([c - 250 * S, c + 40 * S, c + 220 * S, c + 100 * S], fill=(156, 204, 100))
    # the tree
    poly([(-26, 70), (-14, -60), (-50, -110), (-30, -118), (0, -80), (24, -130), (44, -120), (16, -56), (28, 70)], (112, 76, 48))
    for x, y, r, col in [(-110, -150, 95, (92, 146, 64)), (100, -150, 100, (86, 138, 60)), (0, -235, 125, (118, 172, 78)), (-55, -260, 60, (150, 200, 100))]:
        blob(x, y, r, col)
    d.ellipse([c - 85 * S, c - 300 * S, c - 35 * S, c - 250 * S], fill=(186, 222, 130))
    # a path of gold glints round it
    for x, y, r in [(-330, -40, 34), (320, -60, 26), (230, -300, 22), (-280, 260, 20)]:
        sparkle(d, c + x * S, c + y * S, r * S, (255, 238, 180, 255))
    return img


def save_icons():
    big = emblem(1024)
    big.save(os.path.join(OUT, "emblem_1024.png"))
    big.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "icon.png"))
    big.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == "__main__":
    save_icons()
    print("icons written")
