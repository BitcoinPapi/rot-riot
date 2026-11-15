#!/usr/bin/env python3
"""Make movement sheets (walk, idle, hit, death) out of ONE picture of a character.

The hero's second picture (both arms stretched out, hands empty) came with sheets that
could not be used: another pose, a hazy cut-out, figures sliced by the grid. This script
makes the frames instead, by bending the one good picture a little: the feet step, the
body sways and breathes, a hit pushes him back, death turns and shrinks him. Whatever
lies further ahead than --still-from (his hands, which hold the gun the game draws)
does not move while he walks or stands, so the gun stays in his hands.

    tools/make_moves.py PICTURE OUT_DIR --pivot X,Y --aim DEG --feet "X,Y X,Y" [--still-from F]
                        [--step 40] [--name NAME]

    PICTURE       the big picture, as it was sent (png / webp)
    OUT_DIR       where the sheets go: NAME_walk_12f.png, NAME_idle_8f.png,
                  NAME_hit_6f.png, NAME_death_12f.png (cells of half the picture's size)
    --pivot       the middle of his body in the picture (make_sprite's --center)
    --aim         the way he faces in the picture, in degrees clockwise from "right"
                  (the hero's picture: -30, he aims up and to the right)
    --feet        where his two boots are in the picture
    --still-from  how far ahead of the pivot (picture pixels, along --aim) the part
                  begins that must not move: his hands. Default: nothing is held still.
    --step        how far a boot swings while he walks, in picture pixels

Then cut the sheets into strips like any others (tools/make_sprite.py, ANIMATIONS):
    tools/make_sprite.py OUT_DIR/NAME_walk_12f.png player_walk --sheet 4x3 --match PICTURE ...
Needs Python with Pillow and numpy.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image


def premultiplied(im: Image.Image) -> np.ndarray:
    a = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def to_image(a: np.ndarray) -> Image.Image:
    out = a.copy()
    solid = np.maximum(out[..., 3:4], 1e-4)
    out[..., :3] = np.clip(out[..., :3] / solid, 0.0, 1.0)
    return Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def sample(src: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """The picture at the (fractional) spots x, y: bilinear, see-through outside."""
    h, w = src.shape[:2]
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]

    def at(xi, yi):
        ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
        out = src[np.clip(yi, 0, h - 1), np.clip(xi, 0, w - 1)]
        return out * ok[..., None]

    top = at(x0, y0) * (1.0 - fx) + at(x0 + 1, y0) * fx
    low = at(x0, y0 + 1) * (1.0 - fx) + at(x0 + 1, y0 + 1) * fx
    return top * (1.0 - fy) + low * fy


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("picture")
    ap.add_argument("out")
    ap.add_argument("--pivot", required=True)
    ap.add_argument("--aim", type=float, default=0.0)
    ap.add_argument("--feet", required=True)
    ap.add_argument("--still-from", type=float, default=1e9)
    ap.add_argument("--step", type=float, default=40.0)
    ap.add_argument("--name", default="hero")
    args = ap.parse_args()

    src = premultiplied(Image.open(args.picture))
    h, w = src.shape[:2]
    pivot = np.array([float(v) for v in args.pivot.split(",")], dtype=np.float32)
    feet = [np.array([float(v) for v in spot.split(",")], dtype=np.float32) for spot in args.feet.split()]
    t = math.radians(args.aim)
    ahead = np.array([math.cos(t), math.sin(t)], dtype=np.float32)       # the way he faces
    side = np.array([-ahead[1], ahead[0]], dtype=np.float32)             # to his right

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    rx, ry = xs - pivot[0], ys - pivot[1]
    forward = rx * ahead[0] + ry * ahead[1]
    # 1 on his body, falling to 0 where his hands begin (they hold the gun: they stay).
    loose = np.clip((args.still_from - forward) / max(args.still_from * 0.45, 1.0), 0.0, 1.0)
    loose = loose * loose * (3.0 - 2.0 * loose)
    boots = [np.exp(-((xs - f[0]) ** 2 + (ys - f[1]) ** 2) / (2.0 * (0.058 * w) ** 2)) for f in feet]
    trunk = np.exp(-(rx ** 2 + ry ** 2) / (2.0 * (0.25 * w) ** 2))

    def frame(dx: np.ndarray, dy: np.ndarray, turn: float = 0.0, scale: float = 1.0) -> Image.Image:
        """The picture with every spot moved by (dx, dy), then turned and resized about the pivot."""
        # (Looked up backwards: where does this spot of the frame come from?)
        c, s = math.cos(-turn), math.sin(-turn)
        ux = (rx * c - ry * s) / scale
        uy = (rx * s + ry * c) / scale
        return to_image(sample(src, pivot[0] + ux - dx, pivot[1] + uy - dy)).resize((w // 2, h // 2), Image.LANCZOS)

    def sheet(frames: list, cols: int, name: str) -> None:
        rows = (len(frames) + cols - 1) // cols
        cw, ch = frames[0].size
        out = Image.new("RGBA", (cw * cols, ch * rows), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            out.paste(f, ((i % cols) * cw, (i // cols) * ch))
        path = os.path.join(args.out, "%s_%s_%df.png" % (args.name, name, len(frames)))
        out.save(path)
        print(os.path.normpath(path), "%d frames of %dx%d" % (len(frames), cw, ch))

    os.makedirs(args.out, exist_ok=True)
    zero = np.zeros_like(xs)

    # WALK: the boots swing against each other, the body rocks a little from side to side
    # and rises and sinks with every step. His hands stay where they are.
    walk = []
    for i in range(12):
        p = math.tau * i / 12.0
        swing = math.sin(p) * args.step
        dx = (boots[0] - boots[1]) * swing * ahead[0]
        dy = (boots[0] - boots[1]) * swing * ahead[1]
        rock = math.sin(p) * 0.010 * w * trunk * loose                       # sideways
        bob = (math.cos(2.0 * p) * 0.004 * w) * trunk * loose                # two steps to a round
        dx = dx + rock * side[0] + bob * ahead[0]
        dy = dy + rock * side[1] + bob * ahead[1]
        walk.append(frame(dx, dy))
    sheet(walk, 4, "walk")

    # IDLE: he breathes - the body swells and settles; his shoulders roll a little.
    idle = []
    for i in range(8):
        p = math.tau * i / 8.0
        swell = (0.5 - 0.5 * math.cos(p)) * 0.016 * trunk * loose
        roll = math.sin(p) * 0.004 * w * trunk * loose
        idle.append(frame(rx * swell + roll * side[0], ry * swell + roll * side[1]))
    sheet(idle, 4, "idle")

    # HIT: knocked back and squeezed for a moment, then back on his feet.
    hit = []
    for i, push in enumerate([0.0, 1.0, 0.8, 0.5, 0.22, 0.0]):
        back = push * 0.022 * w
        hit.append(frame(zero - back * ahead[0] * (0.4 + 0.6 * loose), zero - back * ahead[1] * (0.4 + 0.6 * loose),
                turn=-0.07 * push, scale=1.0 - 0.035 * push))
    sheet(hit, 3, "hit")

    # DEATH: he turns, sinks and comes to rest.
    death = []
    for i in range(12):
        f = i / 11.0
        ease = 1.0 - (1.0 - f) ** 2.2
        sag = ease * 0.03 * w * trunk
        death.append(frame(zero - sag * ahead[0], zero - sag * ahead[1], turn=0.62 * ease, scale=1.0 - 0.09 * ease))
    sheet(death, 4, "death")
    return 0


if __name__ == "__main__":
    sys.exit(main())
