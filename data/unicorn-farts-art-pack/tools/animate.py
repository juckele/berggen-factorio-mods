#!/usr/bin/env python3
"""Animate one machine in the pack's pastel style without the strokes boiling.

    animate.py 2-a -o out/anim-2a --frames 16 [--quality preview] [--fps 15]

1. build_models.py writes N looping frames (phase k/N) of the machine.
2. claude-artist renders and paints every frame (the pack's style).
   With the style's `paint.coherent: true` each stroke's random choices depend
   only on where it is, and every frame reuses frame 0's box of sticks, so a
   frame's painting differs from the last only where the picture does.
3. Frame 0 is the static base. Each other frame keeps the base everywhere
   except where something moved: the moving objects in either frame plus any
   pixel whose rendered light changed (moving cast shadows), grown a little
   and feathered. Only there is the frame's own painting used, so static
   metal keeps exactly the same strokes from frame to frame, like vanilla's
   static base + animated layer split.

Writes frames/frame_KK.png (straight RGBA, concept scale 192 px/tile),
sprite/frame_KK.png (64 px/tile, the HR sprite scale) and preview GIFs over a
game-like ground.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, gaussian_filter

PACK = Path(__file__).resolve().parents[1]
import os

ARTIST = Path(os.environ.get("CLAUDE_ARTIST", Path(__file__).resolve().parents[4] / "claude-artist" / "artist"))
MOVING = ("gear_0", "gear_1", "gear_2", "gear_shaft", "handwheel", "crank_arm", "chain", "motor_piston", "mid_gear", "mid_gear_2",
          "back_gear", "flywheel", "press_ram")  # object names posed by the phase in build_models.py


def srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def load_frame(run: Path):
    d = run / "09_paint"
    rgb = np.load(d / "pastel_rgb.npy").astype(np.float32)
    a = np.load(d / "pastel_alpha.npy").astype(np.float32)
    meta = json.loads((run / "02_render" / "passes.json").read_text())
    oid = np.asarray(Image.open(run / "02_render" / "object_id.png")).astype(np.int32)
    names = {o["id"]: o["name"] for o in meta["objects"]}
    moving = np.isin(oid, [i for i, n in names.items() if n in MOVING])
    beauty = np.asarray(Image.open(run / "02_render" / "beauty.png").convert("RGB")).astype(np.float32) / 255
    return rgb, a, moving, beauty


def ground(size, col=(118, 98, 72), seed=0):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 6, (size[1] // 8 + 1, size[0] // 8 + 1, 1))
    n = np.kron(n, np.ones((8, 8, 1)))[: size[1], : size[0]]
    return Image.fromarray(np.clip(np.array(col)[None, None, :] + n, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("machine", help="tier-direction, e.g. 2-a")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--frames", type=int, default=16)
    ap.add_argument("--quality", default="preview")
    ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("--style", default=str(PACK / "style" / "params.yaml"))
    ap.add_argument("--skip-render", action="store_true", help="reuse existing frame runs")
    args = ap.parse_args()
    out = Path(args.out).resolve()
    scenes = out / "scenes"
    subprocess.run([sys.executable, str(PACK / "models" / "build_models.py"), "--only", args.machine, "--frames", str(args.frames), "--out", str(scenes)], check=True)
    runs = []
    for k in range(args.frames):
        run = out / "runs" / f"f{k:02d}"
        runs.append(run)
        if args.skip_render and (run / "09_paint" / "pastel_rgb.npy").exists():
            continue
        cmd = [str(ARTIST), "run", str(scenes / f"frame_{k:02d}.yaml"), "--style", args.style, "-o", str(run), "--quality", args.quality, "--seed", "7", "--stop", "paint"]
        if k > 0:  # every frame paints from frame 0's box of sticks, so colours don't shift between frames
            cmd += ["--set", f"paint.sticks.fixed={runs[0] / '09_paint' / 'sticks_lab.npy'}"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            raise SystemExit(f"frame {k} failed")
        print(f"frame {k + 1}/{args.frames} painted", flush=True)

    base_rgb, base_a, base_mov, base_beauty = load_frame(runs[0])
    (out / "frames").mkdir(exist_ok=True)
    (out / "sprite").mkdir(exist_ok=True)
    big, small = [], []
    H, W = base_a.shape
    gb = ground((W, H))
    gs = ground((W // 3, H // 3), seed=3)
    for k, run in enumerate(runs):
        if k == 0:
            rgb, a = base_rgb, base_a
        else:
            f_rgb, f_a, f_mov, f_beauty = load_frame(run)
            changed = np.abs(f_beauty - base_beauty).max(-1) > 0.035
            m = binary_dilation(base_mov | f_mov | changed, iterations=3)
            m = np.clip(gaussian_filter(m.astype(np.float32), 1.2) * 1.4, 0, 1)
            rgb = base_rgb * (1 - m[..., None]) + f_rgb * m[..., None]
            a = base_a * (1 - m) + f_a * m
        im = Image.fromarray((np.concatenate([srgb(rgb), a[..., None]], -1) * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGBA")
        im.save(out / "frames" / f"frame_{k:02d}.png")
        sm = im.resize((W // 3, H // 3), Image.LANCZOS)
        sm.save(out / "sprite" / f"frame_{k:02d}.png")
        c = gb.copy(); c.alpha_composite(im); big.append(c.convert("RGB"))
        c2 = gs.copy(); c2.alpha_composite(sm); small.append(c2.resize((c2.width * 2, c2.height * 2), Image.NEAREST).convert("RGB"))
    dur = int(1000 / args.fps)
    big[0].save(out / "anim.gif", save_all=True, append_images=big[1:], duration=dur, loop=0, optimize=False)
    small[0].save(out / "anim_sprite_2x.gif", save_all=True, append_images=small[1:], duration=dur, loop=0, optimize=False)
    print("wrote", out / "anim.gif", out / "anim_sprite_2x.gif")


if __name__ == "__main__":
    main()
