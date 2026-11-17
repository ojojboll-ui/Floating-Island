"""The pictures a Steam store page asks for, made from the game's own
renders (shots/store/, the store_shots test) and the lettering
(brand/logo.png, tools/make_logo.py). Writes store/steam/.

    python -I tools/make_store_art.py
"""
import os
import shutil
import sys

from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
ROOT = os.path.dirname(HERE)
SHOTS = os.path.join(ROOT, "shots", "store")
OUT = os.path.join(ROOT, "store", "steam")

LOGO = Image.open(os.path.join(ROOT, "brand", "logo.png")).convert("RGBA")
EMBLEM = Image.open(os.path.join(ROOT, "brand", "emblem_1024.png")).convert("RGBA")


def shot(name):
    return Image.open(os.path.join(SHOTS, name + ".png")).convert("RGBA")


def cover(img, w, h, focus=(0.5, 0.45), zoom=1.0):
    """Scale `img` to cover w x h (times `zoom`), cropped round `focus`."""
    s = max(w / img.width, h / img.height) * zoom
    big = img.resize((int(img.width * s + 0.5), int(img.height * s + 0.5)), Image.LANCZOS)
    x = min(max(int(big.width * focus[0] - w / 2), 0), big.width - w)
    y = min(max(int(big.height * focus[1] - h / 2), 0), big.height - h)
    return big.crop((x, y, x + w, y + h))


def logo(width):
    return LOGO.resize((width, int(LOGO.height * width / LOGO.width)), Image.LANCZOS)


def put(canvas, overlay, cx, cy):
    """`overlay` centred on (cx, cy), in shares of the canvas."""
    canvas.alpha_composite(overlay, (int(canvas.width * cx - overlay.width / 2), int(canvas.height * cy - overlay.height / 2)))


def capsule(name, w, h, src, focus, zoom, logo_w, logo_at, keep_text=True):
    c = cover(shot(src), w, h, focus, zoom)
    if keep_text:
        put(c, logo(int(w * logo_w)), *logo_at)
    c.convert("RGB").save(os.path.join(OUT, name + ".png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    # the store's capsules: the island to one side, the name on the sky
    capsule("header_capsule_920x430", 920, 430, "capsule", (0.5, 0.42), 1.0, 0.5, (0.5, 0.2))
    capsule("small_capsule_462x174", 462, 174, "capsule", (0.5, 0.3), 1.0, 0.8, (0.5, 0.42))
    capsule("main_capsule_1232x706", 1232, 706, "capsule", (0.5, 0.42), 1.0, 0.46, (0.5, 0.18))
    capsule("vertical_capsule_748x896", 748, 896, "capsule", (0.5, 0.5), 1.0, 0.86, (0.5, 0.15))
    capsule("library_capsule_600x900", 600, 900, "capsule", (0.5, 0.5), 1.0, 0.88, (0.5, 0.14))
    capsule("library_hero_3840x1240", 3840, 1240, "golden", (0.5, 0.4), 1.0, 0, (0, 0), keep_text=False)
    # the page background: the morning, faded so the store's text reads on it
    bg = cover(shot("morning"), 1438, 810, (0.5, 0.45), 1.0).filter(ImageFilter.GaussianBlur(3))
    bg = ImageEnhance.Brightness(ImageEnhance.Color(bg).enhance(0.6)).enhance(0.55)
    bg.convert("RGB").save(os.path.join(OUT, "page_background_1438x810.png"))
    # the name alone, on nothing, for the library
    lib = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    put(lib, logo(1180), 0.5, 0.5)
    lib.save(os.path.join(OUT, "library_logo_1280x720.png"))
    # icons
    EMBLEM.resize((184, 184), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, "community_icon_184x184.jpg"), quality=92)
    EMBLEM.resize((32, 32), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, "client_icon_32x32.jpg"), quality=95)
    shutil.copy(os.path.join(ROOT, "brand", "icon.ico"), os.path.join(OUT, "client_icon.ico"))
    # screenshots at 1920x1080
    for n in ("golden", "morning", "dusk", "night", "close"):
        shot(n).resize((1920, 1080), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, "screenshot_%s_1920x1080.png" % n))
    print("store art written to", OUT)
