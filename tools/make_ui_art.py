"""The storybook pieces of the interface, as nine-patch pictures for
StyleBoxTexture (ui.gd's make_theme): parchment for the panel and the
sheets, with a double ink rule and a curl of vine in each corner, and the
labels the buttons are made of. Everything is drawn here, nothing is
downloaded. Writes brand/ui/*.png.

    python -I tools/make_ui_art.py
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
OUT = os.path.join(os.path.dirname(HERE), "brand", "ui")

INK = (78, 56, 40)
PARCH = (247, 236, 212)
PARCH_EDGE = (226, 204, 164)
MOSS = (110, 138, 74)
GOLD = (206, 164, 92)
S = 2   # drawn at twice the size, then shrunk, for smooth edges


def parchment(w, h, seed, base=PARCH, edge=PARCH_EDGE, radius=34, burn=0.55):
    """A sheet of parchment: mottled, darker toward its rim, round corners."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), base + (255,))
    # mottling: a few soft blots, lighter and darker
    blots = Image.new("L", (w, h), 128)
    d = ImageDraw.Draw(blots)
    for _ in range(int(w * h / 900)):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.uniform(6, 26) * S
        v = 128 + rnd.choice((-1, 1)) * rnd.uniform(6, 16)
        d.ellipse([x - r, y - r, x + r, y + r], fill=int(v))
    blots = blots.filter(ImageFilter.GaussianBlur(10 * S))
    light = Image.new("RGBA", (w, h), (255, 251, 238, 255))
    dark = Image.new("RGBA", (w, h), edge + (255,))
    img = Image.composite(light, img, blots.point(lambda v: max(0, v - 128) * 6))
    img = Image.composite(dark, img, blots.point(lambda v: max(0, 128 - v) * 5))
    # a warm burn toward the rim
    rim = Image.new("L", (w, h), 0)
    ImageDraw.Draw(rim).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius * S, fill=255)
    inner = rim.filter(ImageFilter.MinFilter(1 + 2 * 9 * S)).filter(ImageFilter.GaussianBlur(14 * S))
    edge_amt = Image.eval(inner, lambda v: int((255 - v) * burn))
    img = Image.composite(dark, img, edge_amt)
    img.putalpha(rim)
    return img


def curl(d, x, y, sx, sy, scale, width):
    """A vine curling out of a corner, with two leaves: sx, sy point inward."""
    pts = []
    for k in range(80):
        t = k / 79.0
        a = t * math.pi * 1.35
        r = (1.0 - t * 0.7) * 26 * scale
        pts.append((x + sx * (t * 46 * scale + math.sin(a) * r * 0.5), y + sy * (t * 10 * scale + (1 - math.cos(a)) * r * 0.45)))
    d.line(pts, fill=INK + (255,), width=width, joint="curve")
    pts2 = [(x + sx * (t / 79.0) * 10 * scale + sx * 0, y + sy * (t / 79.0) * 46 * scale) for t in range(80)]
    d.line(pts2, fill=INK + (255,), width=width)
    for (px, py), ang in ((pts[30], -0.5), (pts2[40], 0.5)):
        leaf(d, px, py, sx, sy, ang, 13 * scale)


def leaf(d, x, y, sx, sy, ang, size):
    a = math.atan2(sy, sx) + ang
    tip = (x + math.cos(a) * size, y + math.sin(a) * size)
    nx, ny = -(tip[1] - y) * 0.34, (tip[0] - x) * 0.34
    mid = ((x + tip[0]) / 2, (y + tip[1]) / 2)
    d.polygon([(x, y), (mid[0] + nx, mid[1] + ny), tip, (mid[0] - nx, mid[1] - ny)], fill=MOSS + (255,), outline=INK + (255,))


def panel(name, size, seed, corner_curls=True, radius=30):
    w = h = size * S
    img = parchment(w, h, seed, radius=radius)
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    m = 12 * S
    # a double rule, the inner one finer
    d.rounded_rectangle([m, m, w - 1 - m, h - 1 - m], radius=(radius - 10) * S, outline=INK + (150,), width=2 * S)
    m2 = m + 6 * S
    d.rounded_rectangle([m2, m2, w - 1 - m2, h - 1 - m2], radius=(radius - 15) * S, outline=INK + (90,), width=1 * S)
    if corner_curls:
        c = m2 + 5 * S
        for sx, sy, cx, cy in ((1, 1, c, c), (-1, 1, w - c, c), (1, -1, c, h - c), (-1, -1, w - c, h - c)):
            curl(d, cx, cy, sx, sy, S * 0.55, 2 * S)
    img.alpha_composite(ink)
    img = img.resize((size, size), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))


def label(name, fill, border, seed, glow=False):
    """A button: a little tag of parchment (or moss), inked round the edge."""
    w, h = 96 * S, 48 * S
    r = 14
    if fill == PARCH:
        img = parchment(w, h, seed, radius=r, burn=0.35)
    else:
        img = parchment(w, h, seed, base=fill, edge=tuple(int(c * 0.82) for c in fill), radius=r, burn=0.45)
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    d.rounded_rectangle([1 * S, 1 * S, w - 1 - 1 * S, h - 1 - 1 * S], radius=r * S - S, outline=border + (255,), width=2 * S)
    d.rounded_rectangle([4 * S, 4 * S, w - 1 - 4 * S, h - 1 - 4 * S], radius=(r - 3) * S, outline=border + (70,), width=1 * S)
    img.alpha_composite(ink)
    if glow:
        hl = Image.new("L", (w, h), 0)
        ImageDraw.Draw(hl).rounded_rectangle([6 * S, 5 * S, w - 6 * S, h * 0.45], radius=(r - 4) * S, fill=60)
        img = Image.composite(Image.new("RGBA", (w, h), (255, 255, 255, 255)), img, hl.filter(ImageFilter.GaussianBlur(3 * S)))
    img = img.resize((w // S, h // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))


def underline(name):
    """The mark under the open tab: a stroke of ink with a leaf at its middle."""
    w, h = 96 * S, 12 * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(x, h * 0.55 + math.sin(x / w * math.pi * 2) * 1.2 * S) for x in range(6 * S, w - 6 * S)]
    d.line(pts, fill=MOSS + (255,), width=3 * S)
    img.resize((w // S, h // S), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    panel("panel", 256, 3)
    panel("sheet", 256, 7)
    label("chip", PARCH, INK, 11)
    label("chip_hover", (252, 245, 228), INK, 12, glow=True)
    label("chip_on", MOSS, (58, 76, 40), 13, glow=True)
    label("chip_gold", (232, 196, 128), (110, 76, 36), 14, glow=True)
    underline("tab_line")
    print("ui art written to", OUT)
