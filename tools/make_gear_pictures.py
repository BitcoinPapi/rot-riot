#!/usr/bin/env python3
"""Put the owner's pictures of gear into the game.

He makes one picture per piece with ChatGPT (1024x1024, see-through background) and
names the files after the piece, mostly with a number in front:
"01_dockworkers_hard_hat.png", "05_brothers_dog_tags.png"... This script finds out which
piece each file is (by its name as shown in the game, by its code name, or by the number
= its place in Config.GEAR_ITEMS), cuts it to its edges and writes

    assets/sprites/gear_item_<id>.png    128 px: inventory tiles, slots, the forge
    assets/sprites/gear_drop_<id>.png     72 px: on the lid of a gear case on the ground
    art_source/gear/<id>.webp             the picture as it was sent (kept for later)

    tools/make_gear_pictures.py FOLDER_OR_FILES...

A piece without a picture keeps the symbol of its kind (gear_helmet.png ...). After
running it: godot --headless --import, then look (--screen=character --gear=40,
--drop-gear). Needs Python with Pillow and numpy.
"""
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
BIG, SMALL = 128, 72          # stored sizes (the picture's longer side fills them, less a little room)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower().replace("'", "")).strip("_")


def pieces() -> list:
    """[(code name, name shown in the game)] in the order of Config.GEAR_ITEMS."""
    text = open(os.path.join(ROOT, "scripts", "config.gd"), encoding="utf-8").read()
    start = text.index("const GEAR_ITEMS")
    block = text[start:text.index("\n}", start)]
    return re.findall(r'\t"(\w+)": \{"name": "([^"]+)"', block)


def shrink(im: Image.Image, size: tuple) -> Image.Image:
    """Resize without a dark or light rim: the colours are weighted by how solid they are."""
    a = np.asarray(im).astype(np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    small = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    b = np.asarray(small).astype(np.float32) / 255.0
    solid = np.maximum(b[..., 3:4], 1e-4)
    b[..., :3] = np.clip(b[..., :3] / solid, 0.0, 1.0)
    return Image.fromarray((b * 255.0 + 0.5).astype(np.uint8), "RGBA")


def fitted(figure: Image.Image, side: int) -> Image.Image:
    room = max(2, round(side * 0.04))
    k = min((side - 2 * room) / figure.width, (side - 2 * room) / figure.height)
    small = shrink(figure, (max(1, round(figure.width * k)), max(1, round(figure.height * k))))
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.alpha_composite(small, ((side - small.width) // 2, (side - small.height) // 2))
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    files = []
    for arg in sys.argv[1:]:
        if os.path.isdir(arg):
            files += [os.path.join(arg, f) for f in sorted(os.listdir(arg)) if f.lower().endswith((".png", ".webp", ".jpg", ".jpeg"))]
        else:
            files.append(arg)
    known = pieces()
    by_slug = {}
    for code, shown in known:
        by_slug[slug(shown)] = code
        by_slug[code] = code
    os.makedirs(os.path.join(ROOT, "art_source", "gear"), exist_ok=True)
    done, unknown = [], []
    for path in files:
        base = os.path.splitext(os.path.basename(path))[0]
        number = re.match(r"^(\d+)[_\- ]+(.*)$", base)
        name = slug(number.group(2) if number else base)
        code = by_slug.get(name)
        if code is None and number and 1 <= int(number.group(1)) <= len(known):
            code = known[int(number.group(1)) - 1][0]       # (no name we know: trust its number)
        if code is None:
            unknown.append(os.path.basename(path))
            continue
        im = Image.open(path).convert("RGBA")
        box = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
        if box is None:
            unknown.append(os.path.basename(path) + " (empty picture)")
            continue
        figure = im.crop(box)
        fitted(figure, BIG).save(os.path.join(ROOT, "assets", "sprites", "gear_item_%s.png" % code))
        fitted(figure, SMALL).save(os.path.join(ROOT, "assets", "sprites", "gear_drop_%s.png" % code))
        im.save(os.path.join(ROOT, "art_source", "gear", "%s.webp" % code), "WEBP", quality=92, method=6)
        done.append(code)
        print("%-34s -> %-16s (%s)" % (os.path.basename(path), code, dict(known)[code]))
    have = sorted(f[len("gear_item_"):-4] for f in os.listdir(os.path.join(ROOT, "assets", "sprites")) if f.startswith("gear_item_") and f.endswith(".png"))
    missing = [code for code, _ in known if code not in have]
    print("%d put in now; %d of %d pieces have a picture." % (len(done), len(have), len(known)))
    if missing:
        print("still without one: " + ", ".join(missing))
    for name in unknown:
        print("NOT USED (which piece is it?): " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
