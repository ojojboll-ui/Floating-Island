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
