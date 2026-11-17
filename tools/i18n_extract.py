"""Gather the words the player sees from the scripts, and keep the
translation table (i18n/strings.csv) in step: new Swedish lines are added
with an empty English column, lines no longer used are dropped, every
translation already made is kept.

    python -I tools/i18n_extract.py           (then fill the empty cells)

Godot translates a Control's text and tooltip by itself when the exact
Swedish line is in the table; lines put together in code go through tr().
"""
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
ROOT = os.path.dirname(HERE)
TABLE = os.path.join(ROOT, "i18n", "strings.csv")
SKIP_FILES = {"test_driver.gd"}
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
# names in code, not words for the player
NOT_WORDS = {
    "Button", "Label", "HSlider", "PanelContainer", "Sheet", "Card", "CardOpen", "TitleButton",
    "PrimaryButton", "SheetButton", "SmallButton", "TabButton", "Handle", "Heading", "Tagline",
    "CheckButton", "LineEdit", "PopupMenu", "TooltipPanel", "TooltipLabel", "VScrollBar", "TabBar",
    "HSeparator", "Master", "Godot Engine", "OmniLight3D", "Light3D", "MeshInstance3D",
    "GeometryInstance3D", "BaseButton", "GPUParticles3D", "FogVolume", "Skyholme", "PanelContainer",
    "Leaves", "Bark", "Rock", "Mushroom", "GridContainer",
}


def is_word(s):
    if not re.search(r"[A-Za-zÅÄÖåäö]", s):
        return False
    if s in NOT_WORDS or s.startswith(("res://", "user://", "--", "#", "*.")):
        return False
    if re.fullmatch(r"[a-z_0-9.:/%|\-]+", s):        # keys, paths, formats
        return False
    if re.fullmatch(r"[A-Za-z_0-9]+", s) and not re.search(r"[A-Z].*[a-z]", s):
        return False
    if re.fullmatch(r"[A-Z][a-z]+[A-Z][A-Za-z]*", s):  # CamelCase class names
        return False
    if "%s" in s and not re.search(r"[a-zåäö]{3}", s.replace("%s", "")):
        return False
    return True


def gather():
    found = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "scripts", "*.gd"))):
        name = os.path.basename(path)
        if name in SKIP_FILES:
            continue
        for ln, line in enumerate(open(path, encoding="utf-8"), 1):
            if line.lstrip().startswith("#"):
                continue
            for m in LITERAL.finditer(line):
                s = m.group(1).replace('\\"', '"').replace("\\n", "\n")
                if is_word(s):
                    found.setdefault(s, "%s:%d" % (name, ln))
    return found


def english():
    """i18n/en.py: Swedish -> English, kept by hand."""
    scope = {}
    with open(os.path.join(ROOT, "i18n", "en.py"), encoding="utf-8") as f:
        exec(f.read(), scope)
    return scope["EN"]


SWEDISH = re.compile(r"[åäöÅÄÖ]|(och|eller|en|ett|som|det|på|för|till|med|av|är|inte|hur)")


if __name__ == "__main__":
    found = gather()
    en = english()
    os.makedirs(os.path.dirname(TABLE), exist_ok=True)
    rows = [{"keys": s, "sv": s, "en": en[s]} for s in en]
    # words in the code that look Swedish but have no English yet
    missing = [s for s in found if s not in en and (SWEDISH.search(s) or re.fullmatch(r"[A-ZÅÄÖ][a-zåäö]+( [a-zåäö]+)*", s))]
    with open(TABLE, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["keys", "sv", "en"])
        w.writeheader()
        w.writerows(rows)
    print("%d lines in the table; %d in the code look Swedish and have no English:" % (len(rows), len(missing)))
    for s in missing:
        print("  %r  %s" % (s, found[s]))
