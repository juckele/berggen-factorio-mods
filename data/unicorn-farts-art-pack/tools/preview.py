#!/usr/bin/env python3
"""Composite claude-artist pastel paint layers over a game-like ground for review.

    preview.py OUT.png RUN_DIR [RUN_DIR ...] [--labels a,b,...] [--sprite]

Reads RUN_DIR/09_paint/pastel_rgb.npy + pastel_alpha.npy (straight alpha, linear RGB).
Each run gets a large cell (concept scale) and, with --sprite, an in-game-scale
cell (64 px/tile, the HR sprite scale; concept renders are 192 px/tile) over
two grounds: dirt and grass-ish, to check that the cut-out edge holds up.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

GROUNDS = [(118, 98, 72), (86, 92, 58), (150, 138, 118)]


def srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def load(run):
    d = Path(run) / "09_paint"
    rgb = np.load(d / "pastel_rgb.npy").astype(np.float32)
    a = np.load(d / "pastel_alpha.npy").astype(np.float32)
    im = np.concatenate([srgb(rgb), a[..., None]], -1)
    return Image.fromarray((np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def ground(size, col, seed=0):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 6, (size[1] // 8 + 1, size[0] // 8 + 1, 1))
    n = np.kron(n, np.ones((8, 8, 1)))[: size[1], : size[0]]
    g = np.clip(np.array(col)[None, None, :] + n, 0, 255).astype(np.uint8)
    return Image.fromarray(g, "RGB").convert("RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--labels")
    ap.add_argument("--sprite", action="store_true")
    ap.add_argument("--cell", type=float, default=0.6, help="scale of the big cell")
    args = ap.parse_args()
    labels = args.labels.split(",") if args.labels else [Path(r).name for r in args.runs]
    ims = [load(r) for r in args.runs]
    W = max(int(i.width * args.cell) for i in ims)
    Hc = max(int(i.height * args.cell) for i in ims)
    sw = max(i.width // 3 for i in ims)
    sh = max(i.height // 3 for i in ims)
    rows = 1 + (1 if args.sprite else 0)
    sheet = Image.new("RGBA", (len(ims) * W, Hc + (sh + 8 if args.sprite else 0) + 26), (230, 226, 218, 255))
    d = ImageDraw.Draw(sheet)
    for k, (im, lab) in enumerate(zip(ims, labels)):
        big = im.resize((int(im.width * args.cell), int(im.height * args.cell)), Image.LANCZOS)
        cell = ground((W, Hc), GROUNDS[0], k)
        cell.alpha_composite(big, ((W - big.width) // 2, (Hc - big.height) // 2))
        sheet.alpha_composite(cell, (k * W, 26))
        d.text((k * W + 8, 6), lab, fill=(30, 30, 30, 255))
        if args.sprite:
            sm = im.resize((im.width // 3, im.height // 3), Image.LANCZOS)
            for j, gc in enumerate(GROUNDS[1:3]):
                c2 = ground((W // 2, sh), gc, k + 5 * j)
                c2.alpha_composite(sm, ((W // 2 - sm.width) // 2, 0))
                sheet.alpha_composite(c2, (k * W + j * (W // 2), 26 + Hc + 8))
    sheet.convert("RGB").save(args.out)
    print(args.out, sheet.size)


if __name__ == "__main__":
    main()
