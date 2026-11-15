#!/usr/bin/env python3
"""Turns generated job images into the mod's sprite sheets, and checks them first.

    python3 art/vulcanus-demolisher-lifecycle/repack.py check JOB IMAGE [--json]
    python3 art/vulcanus-demolisher-lifecycle/repack.py apply [JOB ...]
    python3 art/vulcanus-demolisher-lifecycle/repack.py preview OUT.png

check: scores one generated image against the job's layout, cell by cell (silhouette overlap,
  centring, size), plus background, cyan and colour rules. Prints a report; exit 0 = pass.
apply: for each approved image (approved/<job>.png; all of them if no JOB is given), keys out the
  magenta, cuts the cells back to frame size and writes them into
  mods/vulcanus-demolisher-lifecycle/graphics, splitting cyan into player-colour masks, hot orange
  into glow layers and the silhouette into shadow frames. Frames of jobs not applied are left as
  they are.
preview: a review image of the mod's current graphics (turret in 8 directions on Vulcanus ground,
  a nest with eggs, icons).
Needs Pillow and numpy.
"""

import json
import math
import sys

import numpy as np
from PIL import Image, ImageFilter

import jobs as J
from kit import cell_geometry, flatten

# ------------------------------------------------------------------------------------------------
# Pixel operations


def key_magenta(img):
    """RGB image on magenta -> RGBA. Pixels close to magenta become transparent; edge pixels are
    un-blended from magenta; leftover magenta tint is removed."""
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255
    m = np.array([1.0, 0.0, 1.0])
    d = np.sqrt(((a - m) ** 2).sum(-1)) / math.sqrt(3)
    alpha = np.clip((d - 0.16) / (0.30 - 0.16), 0, 1)
    safe = np.maximum(alpha, 1e-3)[..., None]
    rgb = np.clip((a - (1 - alpha)[..., None] * m) / safe, 0, 1)
    # Despill: magenta excess (red and blue both above green) is removed.
    excess = np.clip(np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1], 0, 1)
    rgb[..., 0] -= excess
    rgb[..., 2] -= excess
    alpha[alpha < 0.06] = 0
    out = np.dstack([rgb, alpha]) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def hsv(img):
    a = np.asarray(img.convert("RGB").convert("HSV")).astype(np.float32)
    return a[..., 0] * 360 / 255, a[..., 1] / 255, a[..., 2] / 255


def cyan_pixels(img):
    h, s, v = hsv(img)
    alpha = np.asarray(img)[..., 3] > 40
    return alpha & (h > 160) & (h < 205) & (s > 0.3) & (v > 0.12)


def hot_pixels(img):
    h, s, v = hsv(img)
    alpha = np.asarray(img)[..., 3] > 40
    return alpha & (((h > 8) & (h < 58) & (s > 0.45) & (v > 0.78)) | ((s < 0.3) & (v > 0.96)))


def purple_pixels(img):
    h, s, v = hsv(img)
    alpha = np.asarray(img)[..., 3] > 40
    return alpha & (h > 270) & (h < 335) & (s > 0.35) & (v > 0.25)


def split_mask(img):
    """Cyan -> (main with neutral grey there, greyscale mask)."""
    arr = np.asarray(img).astype(np.float32).copy()
    sel = cyan_pixels(img)
    _, _, v = hsv(img)
    grey = (v * 255 * 0.8)[sel]
    arr[sel, 0] = grey
    arr[sel, 1] = grey
    arr[sel, 2] = grey
    mask = np.zeros_like(arr)
    mv = np.clip(v / max(np.percentile(v[sel], 95), 0.2) if sel.any() else v, 0, 1) * 255
    mask[sel, 0] = mv[sel]
    mask[sel, 1] = mv[sel]
    mask[sel, 2] = mv[sel]
    mask[sel, 3] = arr[sel, 3]
    return Image.fromarray(arr.astype(np.uint8), "RGBA"), Image.fromarray(mask.astype(np.uint8), "RGBA")


def glow_of(img):
    arr = np.asarray(img).astype(np.float32)
    sel = hot_pixels(img)
    out = np.zeros_like(arr)
    out[sel] = arr[sel]
    return Image.fromarray(out.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.6))


def flat_shadow_of(img, size):
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", img.size, (0, 0, 0, 255)), (0, 0), img.getchannel("A").point(lambda a: 255 if a > 80 else 0))
    return out


def shadow_of(img, size):
    """Silhouette projected onto the ground to the right (light from the upper left), in a frame of
    `size` whose left edge lines up with img's."""
    alpha = img.getchannel("A").point(lambda a: 255 if a > 80 else 0)
    bbox = alpha.getbbox()
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if not bbox:
        return out
    yb = bbox[3]
    kv, s = 0.5, 0.9   # vertical squash toward the base, rightward shear
    canvas = Image.new("L", size, 0)
    canvas.paste(alpha, (0, 0))
    projected = canvas.transform(size, Image.AFFINE, (1, s / kv, -s * yb / kv, 0, 1 / kv, yb * (1 - 1 / kv)),
                                 resample=Image.BILINEAR)
    projected = projected.filter(ImageFilter.GaussianBlur(1.5))
    out.putalpha(projected)
    return out


def cells(job, img):
    """The job image (resized to the job's size) cut back into frames, one per cell."""
    img = img.resize(job.size, Image.LANCZOS)
    keyed = key_magenta(img)
    cols, _ = job.grid
    frames = []
    for i, layout in enumerate(J.layout_frames(job)):
        cw, ch, k = cell_geometry(job, layout.size)
        cell = keyed.crop(((i % cols) * cw, (i // cols) * ch, (i % cols) * cw + cw, (i // cols) * ch + ch))
        full = cell.resize((round(cw / k), round(ch / k)), Image.LANCZOS)
        left = (full.width - layout.width) // 2
        top = (full.height - layout.height) // 2
        frames.append(full.crop((left, top, left + layout.width, top + layout.height)))
    return img, keyed, frames


# ------------------------------------------------------------------------------------------------
# check

def silhouette(img):
    return np.asarray(img)[..., 3] > 128


def compare(gen, ref, core=None):
    a, b = silhouette(gen), silhouette(ref)
    inter, union = (a & b).sum(), (a | b).sum()
    iou = inter / union if union else 0
    # The part that changes from cell to cell (a turret's barrel): overlap without the shared core.
    moving = None
    if core is not None and (b & ~core).sum() > 0.01 * b.size:
        am, bm = a & ~core, b & ~core
        u = (am | bm).sum()
        moving = (am & bm).sum() / u if u else 0
    def centroid(m):
        ys, xs = np.nonzero(m)
        return (xs.mean(), ys.mean()) if len(xs) else (0, 0)
    (ax, ay), (bx, by) = centroid(a), centroid(b)
    shift = math.hypot(ax - bx, ay - by) / max(gen.size)
    ratio = a.sum() / b.sum() if b.sum() else 0
    return iou, shift, ratio, moving


def check(job, img):
    resized, keyed, frames = cells(job, img)
    refs = [flatten(f) for f in J.layout_frames(job)]  # what the model was shown
    rgb = np.asarray(resized.convert("RGB")).astype(int)
    magenta_share = (np.abs(rgb - np.array(J.MAGENTA)).sum(-1) < 60).mean()
    problems, rows = [], []
    min_iou = 0.35 if job.icons else 0.5
    # What all cells share (the same object turned): only meaningful for many views of one object.
    core = None
    if len(refs) >= 4 and len({r.size for r in refs}) == 1 and not job.icons:
        core = np.logical_and.reduce([silhouette(r) for r in refs])
        core = np.asarray(Image.fromarray(core.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))) > 0
    for i, (f, r) in enumerate(zip(frames, refs)):
        iou, shift, ratio, moving = compare(f, r, core)
        obj = silhouette(f).sum() or 1
        cyan = cyan_pixels(f).sum() / obj
        purple = purple_pixels(f).sum() / obj
        cell_problems = []
        if iou < min_iou:
            cell_problems.append(f"shape overlap {iou:.2f} < {min_iou}")
        if moving is not None and moving < 0.3:
            cell_problems.append(f"the part that turns (barrel) overlaps only {moving:.2f}: wrong direction, length or pose?")
        if shift > 0.06:
            cell_problems.append(f"off-centre by {shift:.0%} of the frame")
        if not 0.6 <= ratio <= 1.6:
            cell_problems.append(f"size {ratio:.2f}x the layout's")
        has_mask = job.player_colour and (job.layout_frame or (job.slots[i] and job.slots[i].mask))
        if has_mask and cyan < 0.003:
            cell_problems.append("no cyan player-colour area")
        if not has_mask and cyan > 0.004:
            cell_problems.append(f"cyan where there should be none ({cyan:.1%})")
        if purple > 0.01:
            cell_problems.append(f"magenta/purple in the object ({purple:.1%})")
        rows.append(dict(cell=i + 1, row=i // job.grid[0] + 1, col=i % job.grid[0] + 1,
                         overlap=round(float(iou), 3),
                         barrel_overlap=None if moving is None else round(float(moving), 3),
                         offset=round(float(shift), 3),
                         size=round(float(ratio), 2), problems=cell_problems))
        problems += [f"cell {i + 1} (row {i // job.grid[0] + 1}, column {i % job.grid[0] + 1}): {p}" for p in cell_problems]
    if magenta_share < job.min_background:
        problems.append(f"only {magenta_share:.0%} of the image is flat magenta background "
                        f"(need {job.min_background:.0%}): background not pure #FF00FF?")
    w, h = img.size
    want = job.size[0] / job.size[1]
    if abs(w / h - want) > 0.03:
        problems.append(f"aspect ratio {w}x{h} is not {job.aspect}")
    return dict(job=job.name, passed=not problems, problems=problems, cells=rows,
                magenta_background=round(float(magenta_share), 3), image_size=[w, h])


# ------------------------------------------------------------------------------------------------
# apply

def apply(job, img):
    _, _, frames = cells(job, img)
    sheets = {}

    def sheet(rel):
        if rel not in sheets:
            sheets[rel] = Image.open(J.GRAPHICS / rel).convert("RGBA")
        return sheets[rel]

    def put(frame, image):
        s = sheet(frame.rel)
        box = frame.box()
        s.paste(Image.new("RGBA", (frame.w, frame.h), (0, 0, 0, 0)), box[:2])
        s.paste(image.crop((0, 0, frame.w, frame.h)), box[:2])

    for slot, f in zip(job.slots, frames):
        if slot is None:
            continue
        if slot.main.w != f.width or slot.main.h != f.height:
            f = f.resize((slot.main.w, slot.main.h), Image.LANCZOS)
        main = f
        if slot.mask:
            main, mask = split_mask(f)
            put(slot.mask, mask)
        if slot.glow:
            put(slot.glow, glow_of(f))
        if slot.shadow:
            make = flat_shadow_of if slot.flat_shadow else shadow_of
            put(slot.shadow, make(main, (slot.shadow.w, slot.shadow.h)))
        put(slot.main, main)
    for rel, img_ in sheets.items():
        img_.save(J.GRAPHICS / rel, optimize=True)
    return sorted(sheets)


# ------------------------------------------------------------------------------------------------
# preview

def preview(out_path):
    def tint(mask, c=(1.0, 0.63, 0.26)):
        a = np.asarray(mask).astype(np.float32)
        l = a[..., :3].mean(-1) / 255
        o = np.dstack([l * c[0] * 255, l * c[1] * 255, l * c[2] * 255, a[..., 3]])
        return Image.fromarray(o.astype(np.uint8), "RGBA")

    def soft(sh):
        o = sh.copy()
        o.putalpha(sh.getchannel("A").point(lambda v: int(v * 0.5)))
        return o

    scene = Image.new("RGBA", (1040, 900), (110, 84, 70, 255))
    base = J.crop(J.BASE_SLOT.main)
    for n, d in enumerate(range(0, 64, 8)):
        slot = J.shooting_slot(d // 16 + 1, 0, d % 16)
        x, y = (n % 4) * 260 + 50, (n // 4) * 240 + 50
        scene.alpha_composite(soft(J.crop(J.BASE_SLOT.shadow)), (x, y - 4))
        scene.alpha_composite(soft(J.crop(slot.shadow)), (x, y - 48))
        scene.alpha_composite(base, (x, y - 4))
        scene.alpha_composite(tint(J.crop(J.BASE_SLOT.mask)), (x, y - 4))
        scene.alpha_composite(J.crop(slot.main), (x, y - 48))
        scene.alpha_composite(tint(J.crop(slot.mask)), (x, y - 48))
    nest = J.crop(J.Frame("entity/demolisher-nest/demolisher-nest.png", 384, 320))
    cx, cy = 280, 690
    scene.alpha_composite(nest, (cx - 192, cy - 170))
    egg_job = J.BY_NAME["egg"]
    for i, ang in enumerate((0.3, 2.4, 4.3)):
        s = egg_job.slots[i]
        ex, ey = int(cx + 96 * math.cos(ang)), int(cy + 69 * math.sin(ang))
        scene.alpha_composite(soft(J.crop(s.shadow)), (ex - 64, ey - 70))
        scene.alpha_composite(J.crop(s.main), (ex - 64, ey - 70))
        scene.alpha_composite(J.crop(s.glow), (ex - 64, ey - 70))
    panel = Image.new("RGBA", (480, 420), (40, 40, 44, 255))
    icons = [J.crop(s.main) for s in J.BY_NAME["icons"].slots]
    for i, ic in enumerate(icons[:5]):
        panel.alpha_composite(ic.resize((96, 96), Image.LANCZOS), (20 + (i % 3) * 150, 20 + (i // 3) * 120))
    panel.alpha_composite(icons[5].resize((160, 160), Image.LANCZOS), (300, 250))
    shell = J.crop(J.BY_NAME["lure-shell-projectile"].slots[0].main).resize((64, 128), Image.LANCZOS)
    panel.alpha_composite(shell, (40, 270))
    scene.alpha_composite(panel, (540, 470))
    scene.convert("RGB").save(out_path)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("check", "apply", "preview"):
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "check":
        if len(sys.argv) < 4 or sys.argv[2] not in J.BY_NAME:
            sys.exit("usage: repack.py check JOB IMAGE [--json]; jobs: " + ", ".join(J.BY_NAME))
        report = check(J.BY_NAME[sys.argv[2]], Image.open(sys.argv[3]))
        if "--json" in sys.argv:
            print(json.dumps(report, indent=2))
        else:
            print(f"{report['job']}: {'PASS' if report['passed'] else 'FAIL'} "
                  f"(image {report['image_size'][0]}x{report['image_size'][1]}, "
                  f"magenta background {report['magenta_background']:.0%})")
            for c in report["cells"]:
                moving = "" if c["barrel_overlap"] is None else f"  barrel {c['barrel_overlap']:.2f}"
                print(f"  cell {c['cell']:2d}: overlap {c['overlap']:.2f}{moving}  offset {c['offset']:.1%}  size {c['size']:.2f}"
                      + ("  <- " + "; ".join(c["problems"]) if c["problems"] else ""))
            for p in report["problems"]:
                if not p.startswith("cell"):
                    print("  " + p)
        return 0 if report["passed"] else 1
    if cmd == "apply":
        names = sys.argv[2:] or [j.name for j in J.JOBS if (J.APPROVED / f"{j.name}.png").exists()]
        for name in names:
            job = J.BY_NAME[name]
            if not job.writes:
                continue
            path = J.APPROVED / f"{name}.png"
            if not path.exists():
                sys.exit(f"{path} is missing")
            written = apply(job, Image.open(path))
            print(f"{name}: wrote {', '.join(written)}")
        return 0
    if cmd == "preview":
        if len(sys.argv) != 3:
            sys.exit("usage: repack.py preview OUT.png")
        preview(sys.argv[2])
        return 0


if __name__ == "__main__":
    sys.exit(main())
