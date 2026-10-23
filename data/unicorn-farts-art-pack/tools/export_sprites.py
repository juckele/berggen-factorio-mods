#!/usr/bin/env python3
"""Export a layered animation (claude-artist `artist layers` output) as Factorio sprites.

    export_sprites.py LAYERS_DIR --entity assembling-machine-2 -o OUT [--mod unicorn-farts-art-pack]

Factorio draws an entity's animation as a list of layers in order; each layer
is a sprite (or a sprite sheet of frames) with its own size and shift. The
layer stack maps onto that directly:

  static_j        one frame, `repeat_count` = the animation's frame count
  <group>         a sheet of frames (rotating parts; slid chain runs; the piston)
  self_shadow     a sheet of frames: the moving parts' shadows on the still parts
  ground_shadow   one frame, `draw_as_shadow`: the machine's shadow on the ground

Sprites are written at the high-resolution scale (64 px per tile, `scale =
0.5`), cropped to what they cover; sheets put `line_length` frames per row.
The entity's position is its footprint centre on the ground, projected with
the render's camera; each layer's `shift` is its crop centre relative to it.

Writes OUT/<entity>-<layer>.png, OUT/<entity>-layers.lua (a Lua table of
layers ready for an animation's `layers`), and OUT/export_check.png: frame 0
rebuilt from the exported sprites beside the composite, with the difference.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

HR = 64  # px per tile at the high-resolution scale (drawn at scale 0.5)


def project(camera, p):
    V = np.asarray(camera["world_to_camera"], np.float64)
    pc = V[:3, :3] @ np.asarray(p, np.float64) + V[:3, 3]
    s = -pc[2]
    return camera["cx"] + camera["fx"] * pc[0] / s, camera["cy"] - camera["fy"] * pc[1] / s


def px_per_tile(camera):
    a = project(camera, (0, 0, 0))
    b = project(camera, (1, 0, 0))
    return math.hypot(b[0] - a[0], b[1] - a[1])


def load(path):
    return Image.open(path).convert("RGBA")


def bbox_union(images, pad=2):
    box = None
    for im in images:
        b = im.getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        return None
    W, H = images[0].size
    return (max(0, box[0] - pad), max(0, box[1] - pad), min(W, box[2] + pad), min(H, box[3] + pad))


def lua_layer(d):
    keys = ["filename", "priority", "width", "height", "frame_count", "repeat_count", "line_length", "shift", "scale", "draw_as_shadow", "draw_as_glow", "blend_mode"]
    parts = []
    for k in keys:
        if k not in d:
            continue
        v = d[k]
        if isinstance(v, bool):
            s = "true" if v else "false"
        elif isinstance(v, str):
            s = f'"{v}"'
        elif isinstance(v, (list, tuple)):
            s = "{" + ", ".join(f"{x:.4f}" for x in v) + "}"
        else:
            s = str(v)
        parts.append(f"      {k} = {s},")
    return "    {\n" + "\n".join(parts) + "\n    },"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layers_dir")
    ap.add_argument("--entity", required=True)
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--mod", default="unicorn-farts-art-pack")
    ap.add_argument("--line-length", type=int, default=8)
    args = ap.parse_args()
    src = Path(args.layers_dir)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    meta = json.loads((src / "layers.json").read_text())
    cam = meta["camera"]
    n = len(meta["frames"])
    W, H = meta["size"]
    k = HR / px_per_tile(cam)  # concept px -> HR sprite px
    Ws, Hs = round(W * k), round(H * k)
    ox, oy = project(cam, (0, 0, 0))
    ox, oy = ox * k, oy * k  # entity position in sprite px
    gpath = f"__{args.mod}__/graphics/entity/{args.entity}"

    def scaled(im):
        return im.resize((Ws, Hs), Image.LANCZOS)

    layers = []
    rebuilt = []  # (image at sprite scale, crop box) for the check, per layer, frame 0

    def emit(name, frames, static=False, shadow=False):
        frames = [scaled(f) for f in frames]
        box = bbox_union(frames)
        if box is None:
            return
        x0, y0, x1, y1 = box
        x1 += (x1 - x0) % 2  # even sizes: the centre (what `shift` places) is on a pixel corner
        y1 += (y1 - y0) % 2
        box = (x0, y0, x1, y1)
        w, h = x1 - x0, y1 - y0
        crops = [f.crop(box) for f in frames]
        if len(crops) == 1:
            sheet = crops[0]
            ll = 1
        else:
            ll = min(args.line_length, len(crops))
            rows = math.ceil(len(crops) / ll)
            sheet = Image.new("RGBA", (w * ll, h * rows), (0, 0, 0, 0))
            for i, c in enumerate(crops):
                sheet.paste(c, ((i % ll) * w, (i // ll) * h))
        fn = f"{args.entity}-{name}.png"
        sheet.save(out / fn, optimize=True)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        d = {"filename": f"{gpath}/{fn}", "priority": "high", "width": w, "height": h, "shift": ((cx - ox) / HR, (cy - oy) / HR), "scale": 0.5}
        if len(crops) == 1:
            d["frame_count"] = 1
            d["repeat_count"] = n
        else:
            d["frame_count"] = n
            d["line_length"] = ll
        if shadow:
            d["draw_as_shadow"] = True
        layers.append((name, d))
        if not shadow:
            rebuilt.append((crops[0], box))

    for name in meta["layers"]:
        if name.startswith("static_"):
            emit(name, [load(src / "layers" / f"{name}.png")], static=True)
        else:
            emit(name, [load(src / "layers" / name / f"frame_{i:02d}.png") for i in range(n)])
    if meta.get("ground_shadow"):
        g = np.asarray(Image.open(src / meta["ground_shadow"]).convert("L")).astype(np.float32) / 255
        sh = np.zeros(g.shape + (4,), np.uint8)
        sh[..., 3] = np.clip(g * 255 * 0.9, 0, 255).astype(np.uint8)
        emit("shadow", [Image.fromarray(sh, "RGBA")], shadow=True)

    lua = [f"-- Generated by export_sprites.py from {src.name}: {args.entity}, {n} frames, layers back to front.",
           "-- Use as an animation's `layers` (e.g. graphics_set.animation = {layers = require(...)}).", "return", "{"]
    lua += [lua_layer(d) for _, d in layers]
    lua.append("}")
    (out / f"{args.entity}-layers.lua").write_text("\n".join(lua) + "\n")

    # check: rebuild frame 0 from the exported pieces, the way the game places them
    canvas = Image.new("RGBA", (Ws, Hs), (0, 0, 0, 0))
    for (name, d), (crop, box) in zip([l for l in layers if not l[1].get("draw_as_shadow")], rebuilt):
        cx = ox + d["shift"][0] * HR
        cy = oy + d["shift"][1] * HR
        canvas.alpha_composite(crop, (int(round(cx - d["width"] / 2)), int(round(cy - d["height"] / 2))))
    want = scaled(load(src / "frames" / "frame_00.png"))
    a = np.asarray(canvas).astype(np.float32)
    b = np.asarray(want).astype(np.float32)
    # compare premultiplied: a fully transparent pixel's colour means nothing
    a[..., :3] *= a[..., 3:] / 255
    b[..., :3] *= b[..., 3:] / 255
    diff = np.abs(a - b).max(-1)
    sheet = Image.new("RGBA", (Ws * 3, Hs), (118, 98, 72, 255))
    sheet.alpha_composite(canvas, (0, 0))
    sheet.alpha_composite(want, (Ws, 0))
    sheet.paste(Image.fromarray(np.clip(diff * 4, 0, 255).astype(np.uint8)).convert("RGBA"), (2 * Ws, 0))
    sheet.save(out / "export_check.png")
    print(f"exported {len(layers)} layers to {out}; rebuilt frame 0 differs from the composite by mean {diff.mean():.2f}, max {diff.max():.0f} (of 255)")


if __name__ == "__main__":
    main()
