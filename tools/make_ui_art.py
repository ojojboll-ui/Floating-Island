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


RUST = (196, 104, 44)


def lance(d, x, y, dx, dy, size, col):
    """A small lance tip pointing (dx, dy)."""
    nx, ny = -dy, dx
    d.polygon([(x + dx * size, y + dy * size), (x + nx * size * 0.35, y + ny * size * 0.35),
               (x - dx * size * 0.5, y - dy * size * 0.5), (x - nx * size * 0.35, y - ny * size * 0.35)], fill=col)


def quatrefoil(d, x, y, r, col, width, back):
    """A four-petalled flower: four filled pointed petals, each with a light
    vein, round a small eye."""
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        ca, sa = math.cos(a), math.sin(a)
        tip = (x + ca * r, y + sa * r)
        mid = (x + ca * r * 0.55, y + sa * r * 0.55)
        side = (-sa * r * 0.3, ca * r * 0.3)
        d.polygon([(x + ca * r * 0.12, y + sa * r * 0.12), (mid[0] + side[0], mid[1] + side[1]), tip, (mid[0] - side[0], mid[1] - side[1])], fill=col)
        d.line([(x + ca * r * 0.3, y + sa * r * 0.3), (x + ca * r * 0.72, y + sa * r * 0.72)], fill=back, width=max(1, width // 2))
    d.ellipse([x - r * 0.16, y - r * 0.16, x + r * 0.16, y + r * 0.16], fill=col)


def spiral(x, y, r0, turns, sx, sy, start):
    """Points of a spiral winding inward from radius r0."""
    pts = []
    n = int(90 * turns)
    for k in range(n + 1):
        t = k / n
        a = start + sx * sy * t * turns * 2 * math.pi
        r = r0 * (1.0 - t * 0.85)
        pts.append((x + math.cos(a) * r, y + math.sin(a) * r))
    return pts


def scroll(d, x, y, sx, size, col, width):
    """A tendril along the edge ending in a curl, like a fiddlehead."""
    end = (x + sx * size * 1.3, y)
    stem = [(x - sx * size * 1.2 + sx * t * size * 2.5 / 60, y + math.sin(t / 60 * math.pi) * size * 0.25) for t in range(61)]
    d.line(stem, fill=col, width=width, joint="curve")
    cx, cy = stem[-1][0], stem[-1][1] - size * 0.5
    d.line(spiral(cx, cy, size * 0.5, 1.4, sx, 1, math.pi / 2), fill=col, width=width, joint="curve")
    d.line(spiral(stem[0][0], stem[0][1] - size * 0.32, size * 0.32, 1.1, -sx, -1, math.pi / 2), fill=col, width=width, joint="curve")


def corner(d, cx, cy, sx, sy, scale, ink):
    """One corner: a bracket of fine rule with a diamond where it turns and
    lance tips at its ends, a rust scroll and a little flower inside it."""
    w = max(1, int(2 * scale))
    reach = 46 * scale
    d.line([(cx, cy), (cx + sx * reach, cy)], fill=ink, width=w)
    d.line([(cx, cy), (cx, cy + sy * reach)], fill=ink, width=w)
    s = 5 * scale
    d.polygon([(cx - s, cy), (cx, cy - s), (cx + s, cy), (cx, cy + s)], fill=ink)
    lance(d, cx + sx * reach, cy, sx, 0, 6 * scale, ink)
    lance(d, cx, cy + sy * reach, 0, sy, 6 * scale, ink)
    scroll(d, cx + sx * 26 * scale, cy + sy * 15 * scale, sx, 10 * scale, RUST + (255,), w)
    quatrefoil(d, cx + sx * 16 * scale, cy + sy * 31 * scale, 9 * scale, ink, w, PARCH + (255,))


def panel(name, size, seed, corner_curls=True, radius=30):
    w = h = size * S
    img = parchment(w, h, seed, radius=radius)
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    m = 12 * S
    # a double rule, the inner one finer
    d.rounded_rectangle([m, m, w - 1 - m, h - 1 - m], radius=(radius - 10) * S, outline=INK + (70,), width=1 * S)
    m2 = m + 6 * S
    if corner_curls:
        c = m2 + 5 * S
        for sx, sy, cx, cy in ((1, 1, c, c), (-1, 1, w - c, c), (1, -1, c, h - c), (-1, -1, w - c, h - c)):
            corner(d, cx, cy, sx, sy, S, INK + (255,))
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
