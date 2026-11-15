#!/usr/bin/env python3
"""Reference grids for generating the Vulcanus Demolisher Lifecycle sprites with Nano Banana.

The game's sheets don't fit an image model: they are too tall (a 320x2560 strip), need alpha, and
hold up to 32 frames of one object. So the art is generated in jobs (see
vulcanus_demolisher_lifecycle_prompts.md): each job is one grid of cells in an aspect ratio the
model supports, on a flat magenta background. This script cuts the current sheets in
mods/vulcanus-demolisher-lifecycle/graphics into those grids, one PNG per job, to attach as the
layout reference. Cell order is row by row, left to right.

    python3 tools/placeholder-graphics/nano_banana_refs.py OUT_DIR

The same grid geometry (JOBS below) is what a repacking script reverses to rebuild the game
sheets from the generated grids.
"""

import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
GRAPHICS = REPO / "mods" / "vulcanus-demolisher-lifecycle" / "graphics"
MAGENTA = (255, 0, 255, 255)
GROUND = (64, 52, 48)  # partly transparent pixels (ground stains) are flattened onto this


def flatten(img):
    """Opaque where the sprite is, so nothing blends with the magenta: partly transparent pixels
    are composited onto dark ground and made opaque; faint ones are dropped."""
    base = Image.new("RGBA", img.size, GROUND + (255,))
    base.alpha_composite(img)
    alpha = img.getchannel("A").point(lambda a: 255 if a >= 24 else 0)
    base.putalpha(alpha)
    return base


def frames(rel, w, h, cells):
    """Cut frames out of a sheet: cells is a list of (column, row)."""
    img = Image.open(GRAPHICS / rel).convert("RGBA")
    return [img.crop((c * w, r * h, c * w + w, r * h + h)) for c, r in cells]


def whole_turret(direction):
    """Base and head together for one of the 64 firing directions, as the game draws them (base
    shifted 2 px up, head 24 px up, in game pixels; twice that in these high-resolution frames)."""
    stripe, row = direction // 16 + 1, direction % 16
    base = Image.open(GRAPHICS / "entity/lure-turret/lure-turret-base.png").convert("RGBA")
    head = frames(f"entity/lure-turret/lure-turret-shooting-{stripe}.png", 160, 160, [(0, row)])[0]
    out = Image.new("RGBA", (160, 220), (0, 0, 0, 0))
    out.alpha_composite(base, (0, 60 - 4))
    out.alpha_composite(head, (0, 60 - 48))
    return out


def egg_frames():
    main = frames("entity/demolisher-egg/demolisher-egg.png", 128, 128, [(i, 0) for i in range(4)])
    glow = frames("entity/demolisher-egg/demolisher-egg-glow.png", 128, 128, [(i, 0) for i in range(4)])
    for m, g in zip(main, glow):
        m.alpha_composite(g)
    return main


# Each job: output size, grid (columns, rows), the frames in cell order.
JOBS = {}

# Design lock: the whole turret in 8 directions (N, NE, E, SE, S, SW, W, NW), base and head.
JOBS["turret-design"] = dict(
    size=(1820, 1024), grid=(4, 2),
    frames=lambda: [whole_turret(d) for d in range(0, 64, 8)])

# Turret firing heads: per stripe file, idle (column 0) and recoil (column 1), 16 directions as 4x4.
for stripe in range(1, 5):
    for col, kind in ((0, "idle"), (1, "recoil")):
        JOBS[f"turret-shooting-{stripe}-{kind}"] = dict(
            size=(1024, 1024), grid=(4, 4),
            frames=lambda stripe=stripe, col=col: frames(
                f"entity/lure-turret/lure-turret-shooting-{stripe}.png", 160, 160, [(col, r) for r in range(16)]))

JOBS["turret-raising"] = dict(
    size=(1280, 1024), grid=(5, 4),
    frames=lambda: frames("entity/lure-turret/lure-turret-raising.png", 160, 160,
                          [(c, r) for r in range(4) for c in range(5)]))
JOBS["turret-base"] = dict(
    size=(1024, 1024), grid=(1, 1),
    frames=lambda: frames("entity/lure-turret/lure-turret-base.png", 160, 160, [(0, 0)]))
JOBS["turret-remnants"] = dict(
    size=(1820, 1024), grid=(2, 1),
    frames=lambda: frames("entity/lure-turret/remnants/lure-turret-remnants.png", 192, 192, [(0, 0), (1, 0)]))
JOBS["lure-shell-projectile"] = dict(
    size=(1024, 1024), grid=(1, 1),
    frames=lambda: frames("entity/lure-shell/lure-shell.png", 32, 64, [(0, 0)]))
JOBS["egg"] = dict(
    size=(1024, 1024), grid=(2, 2),
    frames=egg_frames)
for v in range(2):
    JOBS[f"nest-{v + 1}"] = dict(
        size=(1280, 1024), grid=(1, 1),
        frames=lambda v=v: frames("entity/demolisher-nest/demolisher-nest.png", 384, 320, [(v, 0)]))
JOBS["icons"] = dict(
    size=(1536, 1024), grid=(3, 2),
    frames=lambda: [Image.open(GRAPHICS / p).convert("RGBA") for p in (
        "icons/lure-turret.png", "icons/lure-shell.png", "icons/demolisher-egg.png",
        "icons/demolisher-nest.png", "icons/vibration.png", "technology/lure-turret.png")])


def build(job):
    w, h = job["size"]
    cols, rows = job["grid"]
    cw, ch = w // cols, h // rows
    out = Image.new("RGBA", (w, h), MAGENTA)
    for i, f in enumerate(job["frames"]()):
        # Scale each frame to fill its cell, keeping its aspect, centred: the cell's centre is the
        # frame's centre, so the repack can map it straight back.
        k = min(cw / f.width, ch / f.height)
        f = flatten(f.resize((round(f.width * k), round(f.height * k)), Image.LANCZOS))
        x = (i % cols) * cw + (cw - f.width) // 2
        y = (i // cols) * ch + (ch - f.height) // 2
        out.alpha_composite(f, (x, y))
    return out.convert("RGB")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, job in JOBS.items():
        build(job).save(out / f"{name}.png")
        print(f"{name}.png: {job['size'][0]}x{job['size'][1]}, grid {job['grid'][0]}x{job['grid'][1]}")


if __name__ == "__main__":
    main()
