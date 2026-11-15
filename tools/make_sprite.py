#!/usr/bin/env python3
"""Turn a big picture of a character (painted, AI-made, drawn...) into a sprite the game can use.

The game shows a zombie as one small picture seen from above, FACING RIGHT, turned
by the game to face the player. A PNG in assets/sprites/ with a sprite's name
replaces the generated shapes (see scripts/autoload/art.gd): this script cuts the
figure out, puts the middle of its body in the middle of the sprite, shrinks it to
the game's size and saves it there.

    tools/make_sprite.py PICTURE NAME --length 58 [--center X,Y] [--turn DEG] [--main-only]
                         [--erase "X,Y X,Y X,Y; X,Y ..."] [--mirror] [--hue DEG] [--dull F]
                         [--wounds] [--no-shadow]
    tools/make_sprite.py PICTURE NAME --portrait 380      (a standing picture for the menus)

    PICTURE     the big picture (png / webp / jpg); a plain white background is removed
    NAME        the sprite's name, e.g. runner_0 or runner_0_hurt
    --length    how long the figure is in the game, in game pixels, measured along the
                picture's width (a Shambler is about 30 across)
    --center    the spot of the PICTURE (in its own pixels) that becomes the middle of
                the sprite: the middle of the chest. The zombie turns around this spot
                and its hit circle sits on it. Default: the middle of everything.
    --turn      turn the picture clockwise by this many degrees first (a figure drawn
                facing up-right must face right). --center still means the spot in the
                picture as it was sent.
    --main-only keep only the figure itself: loose bits around it (flying drops, wisps
                of gas) are dropped, so they do not turn with the zombie or make it small
    --erase     rub out parts of the picture first: one or more shapes, each a list of
                corner points in the PICTURE's own pixels, shapes separated by ";"
                (the hero's picture came holding two guns; the game draws his gun itself)
    --portrait  no sprite: just the figure, cut to its edges and stored so that it is
                this many game pixels tall (hero_front, the hero in the menus)
    --mirror    show the figure mirrored (left and right arm swapped; it still faces right)
    --hue       turn the strong colours by this many degrees (a second look of the same
                character: another shirt colour)
    --dull      wash the strong colours out: 1 = as painted, 0.5 = half as colourful
    --wounds    paint blood and gashes on it (for NAME_hurt when there is no painted
                wounded picture)
    --no-shadow leave out the soft dark shadow that lifts the figure off the ground

Needs Python with Pillow and numpy. After adding or changing a sprite run
`godot --headless --import` once, then look at it in the game.
"""
import argparse
import colorsys
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PX = 2  # sprites are stored at twice the game's size (Art.PX)


def cut_out(im: Image.Image) -> Image.Image:
    """A picture without a see-through background gets its plain border colour removed."""
    im = im.convert("RGBA")
    alpha = np.array(im)[..., 3]
    if alpha.min() < 250:
        return im
    rgb = im.convert("RGB")
    marker = (255, 0, 255)
    w, h = rgb.size
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if rgb.getpixel(seed) != marker:
            ImageDraw.floodfill(rgb, seed, marker, thresh=42)
    filled = np.all(np.array(rgb) == np.array(marker), axis=-1)
    mask = Image.fromarray(np.where(filled, 0, 255).astype(np.uint8), "L").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = np.array(im)
    out[..., 3] = np.array(mask)
    return Image.fromarray(out, "RGBA")


def main_only(im: Image.Image, at: tuple) -> Image.Image:
    """Keep the solid shape that holds the spot `at` (and its soft rim); drop everything else."""
    a = np.array(im)
    solid = Image.fromarray(np.where(a[..., 3] > 140, 255, 0).astype(np.uint8), "L").copy()   # (a copy can be painted on)
    x, y = int(round(at[0])), int(round(at[1]))
    if solid.getpixel((x, y)) != 255:                 # (the spot is on a hole: take the nearest solid pixel)
        ys, xs = np.where(np.array(solid) == 255)
        nearest = int(np.argmin((xs - x) ** 2 + (ys - y) ** 2))
        x, y = int(xs[nearest]), int(ys[nearest])
    ImageDraw.floodfill(solid, (x, y), 128)
    keep = Image.fromarray(np.where(np.array(solid) == 128, 255, 0).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(7))
    a[..., 3] = np.minimum(a[..., 3], np.array(keep))
    return Image.fromarray(a, "RGBA")


def shrink(im: Image.Image, size: tuple) -> Image.Image:
    """Resize without a dark or light rim: the colours are weighted by how solid they are."""
    a = np.array(im).astype(np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    small = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    b = np.array(small).astype(np.float32) / 255.0
    solid = np.maximum(b[..., 3:4], 1e-4)
    b[..., :3] = np.clip(b[..., :3] / solid, 0.0, 1.0)
    return Image.fromarray((b * 255.0 + 0.5).astype(np.uint8), "RGBA")


def turn_hue(im: Image.Image, degrees: float, dull: float = 1.0) -> Image.Image:
    """Turn (and wash out) only the strong colours (clothes), not skin, steel or outlines."""
    a = np.array(im).astype(np.float32) / 255.0
    out = a.copy()
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    top, low = a[..., :3].max(-1), a[..., :3].min(-1)
    strong = (top - low) > 0.30
    for y, x in zip(*np.where(strong)):
        hh, ll, ss = colorsys.rgb_to_hls(r[y, x], g[y, x], b[y, x])
        out[y, x, :3] = colorsys.hls_to_rgb((hh + degrees / 360.0) % 1.0, ll * 0.94, ss * 0.92 * dull)
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def wound(im: Image.Image) -> Image.Image:
    """Blood stains and a few gashes, only where the figure is. The same every time."""
    rng = random.Random(7)
    w, h = im.size
    alpha = np.array(im)[..., 3]
    solid = np.argwhere(alpha > 200)
    paint = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(paint)
    for _ in range(9):
        y, x = solid[rng.randrange(len(solid))]
        rad = rng.uniform(0.022, 0.05) * w
        draw.ellipse([x - rad, y - rad * rng.uniform(0.6, 1.0), x + rad, y + rad * rng.uniform(0.6, 1.0)], fill=(112, 14, 14, 215))
        for _ in range(3):  # drops beside it
            ang, far = rng.uniform(0, math.tau), rad * rng.uniform(1.2, 2.2)
            dot = rad * rng.uniform(0.2, 0.4)
            cx, cy = x + math.cos(ang) * far, y + math.sin(ang) * far
            draw.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(128, 18, 18, 215))
    for _ in range(4):  # gashes: a dark cut with a red rim
        y, x = solid[rng.randrange(len(solid))]
        ang, long = rng.uniform(0, math.tau), rng.uniform(0.06, 0.1) * w
        ends = [x - math.cos(ang) * long / 2, y - math.sin(ang) * long / 2, x + math.cos(ang) * long / 2, y + math.sin(ang) * long / 2]
        draw.line(ends, fill=(150, 24, 20, 235), width=max(2, w // 48))
        draw.line(ends, fill=(46, 6, 8, 245), width=max(1, w // 110))
    paint = paint.filter(ImageFilter.GaussianBlur(0.5))
    p = np.array(paint)
    p[..., 3] = (p[..., 3].astype(np.float32) * (alpha.astype(np.float32) / 255.0)).astype(np.uint8)
    out = im.copy()
    out.alpha_composite(Image.fromarray(p, "RGBA"))
    return out


def shadow(im: Image.Image) -> Image.Image:
    """A soft dark shape under the figure, so it stands out on any ground."""
    alpha = im.getchannel("A").filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(im.width * 0.022))
    dark = Image.new("RGBA", im.size, (0, 0, 0, 0))
    dark.putalpha(alpha.point(lambda v: int(v * 0.42)))
    dark.alpha_composite(im)
    return dark


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("picture")
    ap.add_argument("name")
    ap.add_argument("--length", type=float, default=0.0)
    ap.add_argument("--portrait", type=float, default=0.0)
    ap.add_argument("--erase", default="")
    ap.add_argument("--center", default="")
    ap.add_argument("--turn", type=float, default=0.0)
    ap.add_argument("--main-only", action="store_true")
    ap.add_argument("--mirror", action="store_true")
    ap.add_argument("--hue", type=float, default=0.0)
    ap.add_argument("--dull", type=float, default=1.0)
    ap.add_argument("--wounds", action="store_true")
    ap.add_argument("--no-shadow", action="store_true")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites"))
    args = ap.parse_args()

    im = cut_out(Image.open(args.picture))
    if args.erase:
        hole = Image.new("L", im.size, 255)
        for shape in args.erase.split(";"):
            corners = [tuple(float(v) for v in pt.split(",")) for pt in shape.split()]
            if len(corners) >= 3:
                ImageDraw.Draw(hole).polygon(corners, fill=0)
        hole = hole.filter(ImageFilter.GaussianBlur(1.2))
        a = np.array(im)
        a[..., 3] = (a[..., 3].astype(np.float32) * np.array(hole).astype(np.float32) / 255.0).astype(np.uint8)
        im = Image.fromarray(a, "RGBA")
    if args.portrait > 0.0:
        box = im.getchannel("A").point(lambda v: 255 if v > 25 else 0).getbbox()
        figure = im.crop(box)
        tall = int(round(args.portrait * PX))
        figure = shrink(figure, (max(1, round(figure.width * tall / figure.height)), tall))
        os.makedirs(args.out, exist_ok=True)
        path = os.path.join(args.out, args.name + ".png")
        figure.save(path)
        print("%s: %dx%d stored = %dx%d in the game" % (os.path.normpath(path), figure.width, figure.height, figure.width // PX, figure.height // PX))
        return 0
    if args.length <= 0.0:
        print("say how long the figure is in the game: --length")
        return 1
    spot = [float(v) for v in args.center.split(",")] if args.center else None
    if args.turn:
        old = (im.width / 2.0, im.height / 2.0)
        im = im.rotate(-args.turn, resample=Image.BICUBIC, expand=True)
        if spot:
            t = math.radians(args.turn)
            dx, dy = spot[0] - old[0], spot[1] - old[1]
            spot = [im.width / 2.0 + dx * math.cos(t) - dy * math.sin(t), im.height / 2.0 + dx * math.sin(t) + dy * math.cos(t)]
    if args.main_only:
        im = main_only(im, spot if spot else (im.width / 2.0, im.height / 2.0))
    alpha = np.array(im)[..., 3].astype(np.float32) / 255.0
    ys, xs = np.where(alpha > 0.1)
    if len(xs) == 0:
        print("nothing to see in that picture")
        return 1
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    if spot:
        cx, cy = spot
    else:
        yy, xx = np.mgrid[0:alpha.shape[0], 0:alpha.shape[1]]
        cx, cy = float((xx * alpha).sum() / alpha.sum()), float((yy * alpha).sum() / alpha.sum())
    scale = args.length * PX / float(x1 - x0)          # picture pixels -> stored pixels
    reach = max(cx - x0, x1 - cx, cy - y0, y1 - cy) * scale
    half = int(math.ceil(reach / 2.0 + 1.0)) * 2      # (an even number, so the game size is whole)
    figure = shrink(im.crop((x0, y0, x1, y1)), (max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))))
    sprite = Image.new("RGBA", (half * 2, half * 2), (0, 0, 0, 0))
    sprite.alpha_composite(figure, (round(half - (cx - x0) * scale), round(half - (cy - y0) * scale)))
    if args.mirror:
        sprite = sprite.transpose(Image.FLIP_TOP_BOTTOM)
    if args.hue or args.dull != 1.0:
        sprite = turn_hue(sprite, args.hue, args.dull)
    if args.wounds:
        sprite = wound(sprite)
    if not args.no_shadow:
        sprite = shadow(sprite)
    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, args.name + ".png")
    sprite.save(path)
    print("%s: %dx%d stored = %dx%d in the game; the figure is %.0f long and %.0f wide" % (
        os.path.normpath(path), sprite.width, sprite.height, sprite.width // PX, sprite.height // PX,
        (x1 - x0) * scale / PX, (y1 - y0) * scale / PX))
    return 0


if __name__ == "__main__":
    sys.exit(main())
