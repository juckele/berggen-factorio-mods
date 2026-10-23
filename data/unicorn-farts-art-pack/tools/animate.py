#!/usr/bin/env python3
"""Animate one machine in the pack's pastel style, painted in layers.

    animate.py 2-c -o out/anim-2c --frames 16 [--quality preview] [--style style/params_bold.yaml] [--reuse]

1. build_models.py writes N looping frames (phase k/N) of the machine and an
   animation spec (animation.yaml): which objects move and how.
2. `artist layers` (claude-artist) paints the still machine once, each moving
   group on its own sheet (rotating parts repainted per frame with coherent
   strokes, the chain's straight runs and the piston painted once and slid),
   cuts the still painting into depth slices so the moving parts sit between
   them, and composites every frame, checking it against a full render.
3. This script turns the composited frames into preview GIFs over a game-like
   ground, at concept scale (192 px/tile) and in-game scale (64 px/tile, x2).

Only design C writes an animation spec.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PACK = Path(__file__).resolve().parents[1]
ARTIST = Path(os.environ.get("CLAUDE_ARTIST", Path(__file__).resolve().parents[4] / "claude-artist" / "artist"))


def ground(size, col=(118, 98, 72), seed=0):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 6, (size[1] // 8 + 1, size[0] // 8 + 1, 1))
    n = np.kron(n, np.ones((8, 8, 1)))[: size[1], : size[0]]
    return Image.fromarray(np.clip(np.array(col)[None, None, :] + n, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def gifs(frames_dir: Path, out: Path, n: int, fps: float):
    big, small = [], []
    first = Image.open(frames_dir / "frame_00.png")
    W, H = first.size
    gb, gs = ground((W, H)), ground((W // 3, H // 3), seed=3)
    for k in range(n):
        im = Image.open(frames_dir / f"frame_{k:02d}.png").convert("RGBA")
        sm = im.resize((W // 3, H // 3), Image.LANCZOS)
        c = gb.copy(); c.alpha_composite(im); big.append(c.convert("RGB"))
        c2 = gs.copy(); c2.alpha_composite(sm); small.append(c2.resize((c2.width * 2, c2.height * 2), Image.NEAREST).convert("RGB"))
    dur = int(1000 / fps)
    for frames, name in ((big, "anim.gif"), (small, "anim_sprite_2x.gif")):
        # One palette for every frame and no dithering: a GIF otherwise quantises each frame on its
        # own, and still pixels shimmer although the frames themselves are identical there.
        strip = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
        for i, f in enumerate(frames):
            strip.paste(f, (0, i * f.height))
        pal = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
        q[0].save(out / name, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False)
    print("wrote", out / "anim.gif", out / "anim_sprite_2x.gif")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("machine", help="variant key, e.g. 2-c")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--frames", type=int, default=16)
    ap.add_argument("--quality", default="preview")
    ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("--style", default=str(PACK / "style" / "params_bold.yaml"))
    ap.add_argument("--reuse", action="store_true", help="keep finished renders and paintings")
    ap.add_argument("--gifs-only", action="store_true", help="only rebuild the GIFs from existing frames")
    args = ap.parse_args()
    out = Path(args.out).resolve()
    if args.gifs_only:
        gifs(out / "layers" / "frames", out, args.frames, args.fps)
        return
    scenes = out / "scenes"
    subprocess.run([sys.executable, str(PACK / "models" / "build_models.py"), "--only", args.machine, "--frames", str(args.frames), "--out", str(scenes)], check=True)
    if not (scenes / "animation.yaml").exists():
        raise SystemExit(f"{args.machine} has no animation spec (only design C does)")
    cmd = [str(ARTIST), "layers", str(scenes / "animation.yaml"), "-o", str(out / "layers"), "--style", args.style, "--quality", args.quality, "--seed", "7"]
    if args.reuse:
        cmd.append("--reuse")
    subprocess.run(cmd, check=True)
    gifs(out / "layers" / "frames", out, args.frames, args.fps)


if __name__ == "__main__":
    main()
