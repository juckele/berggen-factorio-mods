#!/usr/bin/env python3
"""Placeholder graphics for the Vulcanus Demolisher Lifecycle mod.

Draws every sprite sheet and icon the mod uses with plain shaded shapes, laid out exactly as the
prototypes read them, so they work in game and serve as layout references for real art. All
sheets are high resolution (drawn at scale 0.5 in game, so 64 px per tile).

    python3 tools/placeholder-graphics/vulcanus_demolisher_lifecycle.py [--out DIR] [--preview PNG]

--out defaults to mods/vulcanus-demolisher-lifecycle/graphics. Deterministic: the same code
always draws the same pixels. Requires Pillow. The layout of each sheet is listed in the mod's
graphics/README.md; keep the two in step.
"""

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[2]
SS = 4  # supersampling factor for smooth edges

# Palette
STEEL_DARK = (58, 60, 66)
STEEL = (104, 108, 116)
STEEL_LIGHT = (160, 165, 172)
TUNGSTEN = (78, 74, 88)
TUNGSTEN_LIGHT = (128, 122, 142)
HAZARD = (232, 176, 40)
MASK_GREY = (150, 150, 150)
LAVA = (255, 120, 20)
LAVA_HOT = (255, 210, 90)
BASALT = (44, 36, 34)
BASALT_LIGHT = (86, 70, 62)
SHELL_RED = (120, 36, 24)
SHELL_RED_LIGHT = (176, 70, 40)
SHADOW = (0, 0, 0)

FORESHORTEN = 0.72  # vertical squash of the ground plane in Factorio's view


class Canvas:
    """A supersampled RGBA drawing surface, reduced to its final size by .image()."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _p(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def _draw(self, colours, fn):
        """Draws with fn(draw). ImageDraw replaces pixels, so a translucent colour would punch a
        see-through hole: those are drawn on a layer and blended. Fully transparent colours still
        replace (used to cut masks)."""
        if any(c is not None and len(c) == 4 and 0 < c[3] < 255 for c in colours):
            layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
            fn(ImageDraw.Draw(layer))
            self.img.alpha_composite(layer)
        else:
            fn(self.d)

    def ellipse(self, cx, cy, rx, ry, fill, outline=None, width=0):
        box = [(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS]
        self._draw((fill, outline), lambda d: d.ellipse(box, fill=fill, outline=outline, width=int(width * SS)))

    def polygon(self, pts, fill, outline=None, width=0):
        pts = self._p(pts)
        self._draw((fill, outline), lambda d: d.polygon(pts, fill=fill, outline=outline, width=int(width * SS)))

    def line(self, pts, fill, width):
        pts = self._p(pts)
        self._draw((fill,), lambda d: d.line(pts, fill=fill, width=max(1, int(width * SS)), joint="curve"))

    def shaded_ellipse(self, cx, cy, rx, ry, dark, light, steps=10):
        """An ellipse lit from the top left."""
        for i in range(steps):
            t = i / (steps - 1)
            col = tuple(int(dark[k] + (light[k] - dark[k]) * t) for k in range(3)) + (255,)
            s = 1 - 0.55 * t
            self.ellipse(cx - rx * 0.25 * t, cy - ry * 0.3 * t, rx * s, ry * s, col)

    def image(self):
        return self.img.resize((self.w, self.h), Image.LANCZOS)


def silhouette(img, colour=SHADOW):
    """Every visible pixel of img in one colour, keeping alpha (for masks and shadows)."""
    out = Image.new("RGBA", img.size, colour + (0,))
    out.putalpha(img.getchannel("A"))
    return out


def sheet(frames, columns):
    """Frames (equal size) row by row, `columns` per row."""
    w, h = frames[0].size
    rows = math.ceil(len(frames) / columns)
    out = Image.new("RGBA", (w * columns, h * rows), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f, ((i % columns) * w, (i // columns) * h))
    return out


def save(img, out, rel):
    path = out / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    return path


# ------------------------------------------------------------------------------------------------
# Lure turret. A squat tungsten-plated plinth carrying a long, slightly raised cannon barrel with a
# hazard-striped muzzle. Player colour (mask) on the plinth band and the head's collar.

TURRET_FRAME = 160          # head and base frames, px
TURRET_SHADOW_W = 208       # shadow frames are wider: shadows fall to the right
PIVOT = (80, 92)            # head pivot inside a head frame
BARREL_LEN = 66
BARREL_RAISE = 14           # the barrel's muzzle sits this much higher on screen (elevation)
SHADOW_OFFSET = (22, 12)    # ground shadow of the head relative to its pivot


def barrel_points(theta, length, start, raise_px, pivot):
    """Screen points from barrel root to muzzle for a turret facing theta (0 = north, clockwise)."""
    vx, vy = math.sin(theta), -math.cos(theta) * FORESHORTEN
    px, py = pivot
    a = (px + vx * start, py + vy * start - raise_px * start / length)
    b = (px + vx * length, py + vy * length - raise_px)
    return a, b


def thick_segment(c, a, b, width, fill):
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1
    ox, oy = -dy / n * width / 2, dx / n * width / 2
    c.polygon([(a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy), (b[0] - ox, b[1] - oy), (a[0] - ox, a[1] - oy)], fill)


def draw_barrel(c, theta, length, raise_px, mask, pivot):
    a, b = barrel_points(theta, length, 8, raise_px, pivot)
    if mask:
        # The barrel hides the collar where it passes in front of it.
        clear = (0, 0, 0, 0)
        thick_segment(c, a, b, 17, clear)
        c.ellipse(b[0], b[1], 8.5, 6.5, clear)
        return
    thick_segment(c, a, b, 15, STEEL_DARK + (255,))
    thick_segment(c, (a[0] - 1.5, a[1] - 2), (b[0] - 1.5, b[1] - 2), 6, STEEL_LIGHT + (255,))
    # Hazard band near the muzzle, then the muzzle itself.
    t0, t1 = 0.72, 0.86
    p0 = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
    p1 = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
    thick_segment(c, p0, p1, 17, HAZARD + (255,))
    c.ellipse(b[0], b[1], 8.5, 6.5, STEEL_DARK + (255,))
    c.ellipse(b[0], b[1], 5, 3.8, (20, 20, 22, 255))


def draw_head(c, theta, length, drop, mask):
    """The turret head: barrel behind or in front of the dome depending on facing."""
    px, py = PIVOT
    py += drop
    behind = math.cos(theta) > 0.05  # facing away from the viewer: barrel drawn first
    def dome():
        if mask:
            c.ellipse(px, py + 6, 30, 12, (255, 255, 255, 255))   # collar
            c.ellipse(px, py - 2, 27, 20, (0, 0, 0, 0))
            return
        c.ellipse(px, py + 6, 31, 13, STEEL_DARK + (255,))
        c.ellipse(px, py + 5, 29, 11, MASK_GREY + (255,))         # collar, player-coloured by the mask
        c.shaded_ellipse(px, py - 3, 28, 21, TUNGSTEN, TUNGSTEN_LIGHT)
        c.ellipse(px - 8, py - 11, 6, 4, (190, 186, 200, 160))      # highlight
    def barrel():
        draw_barrel(c, theta, length, BARREL_RAISE * length / BARREL_LEN, mask, (px, py))
    if behind:
        barrel(); dome()
    else:
        dome(); barrel()


def head_frame(theta, length, drop=0, mask=False):
    c = Canvas(TURRET_FRAME, TURRET_FRAME)
    draw_head(c, theta, length, drop, mask)
    img = c.image()
    if mask:
        # Only the collar: white where the collar shows, greyscale for the engine's tint.
        img = img.convert("LA").convert("RGBA")
    return img


def head_shadow_frame(theta, length, drop=0):
    c = Canvas(TURRET_SHADOW_W, TURRET_FRAME)
    px, py = PIVOT[0] + SHADOW_OFFSET[0], PIVOT[1] + SHADOW_OFFSET[1] - drop * 0.3
    c.ellipse(px, py, 28, 14, SHADOW + (255,))
    vx, vy = math.sin(theta), -math.cos(theta) * FORESHORTEN
    a = (px + vx * 8, py + vy * 8)
    b = (px + vx * length + length * 0.35, py + vy * length + length * 0.12)
    thick_segment(c, a, b, 13, SHADOW + (255,))
    return c.image()


def base_frame(mask=False):
    c = Canvas(TURRET_FRAME, TURRET_FRAME)
    cx, cy = 80, 84
    if mask:
        c.ellipse(cx, cy + 4, 52, 34, (255, 255, 255, 255))
        c.ellipse(cx, cy, 46, 29, (0, 0, 0, 0))
        img = c.image()
        return img.convert("LA").convert("RGBA")
    # Octagonal plinth with a player-coloured band.
    ring = [(cx + 62 * math.cos(a), cy + 10 + 44 * math.sin(a))
            for a in [math.pi / 8 + i * math.pi / 4 for i in range(8)]]
    c.polygon(ring, STEEL_DARK + (255,))
    top = [(cx + 58 * math.cos(a), cy + 40 * math.sin(a))
           for a in [math.pi / 8 + i * math.pi / 4 for i in range(8)]]
    c.polygon(top, STEEL + (255,))
    c.ellipse(cx, cy + 4, 52, 34, MASK_GREY + (255,))
    c.ellipse(cx, cy, 46, 29, STEEL_DARK + (255,))
    c.shaded_ellipse(cx, cy - 2, 42, 26, STEEL, STEEL_LIGHT)
    for a in [math.pi / 8 + i * math.pi / 4 for i in range(8)]:   # bolts
        c.ellipse(cx + 54 * math.cos(a), cy + 37 * math.sin(a), 3, 2.4, (40, 40, 44, 255))
    return c.image()


def base_shadow_frame():
    c = Canvas(TURRET_SHADOW_W, TURRET_FRAME)
    c.ellipse(80 + 16, 84 + 16, 64, 42, SHADOW + (255,))
    return c.image()


def remnants_frame(seed):
    rnd = random.Random(seed)
    c = Canvas(192, 192)
    cx, cy = 96, 104
    c.ellipse(cx, cy + 6, 66, 44, (30, 30, 32, 200))
    c.ellipse(cx, cy, 56, 36, STEEL_DARK + (255,))
    c.ellipse(cx, cy - 2, 44, 27, (70, 72, 78, 255))
    for _ in range(9):   # scattered plates and the broken barrel
        x, y = cx + rnd.uniform(-70, 70), cy + rnd.uniform(-46, 46)
        w, h, a = rnd.uniform(6, 16), rnd.uniform(4, 9), rnd.uniform(0, math.pi)
        pts = [(x + w * math.cos(a) - h * math.sin(a), y + (w * math.sin(a) + h * math.cos(a)) * FORESHORTEN),
               (x - w * math.cos(a) - h * math.sin(a), y + (-w * math.sin(a) + h * math.cos(a)) * FORESHORTEN),
               (x - w * math.cos(a) + h * math.sin(a), y + (-w * math.sin(a) - h * math.cos(a)) * FORESHORTEN),
               (x + w * math.cos(a) + h * math.sin(a), y + (w * math.sin(a) - h * math.cos(a)) * FORESHORTEN)]
        c.polygon(pts, rnd.choice([STEEL, TUNGSTEN, STEEL_DARK]) + (255,))
    a = rnd.uniform(0, 2 * math.pi)
    thick_segment(c, (cx + 10, cy), (cx + 10 + 52 * math.cos(a), cy + 52 * math.sin(a) * FORESHORTEN), 12, STEEL_DARK + (255,))
    b = (cx + 10 + 40 * math.cos(a), cy + 40 * math.sin(a) * FORESHORTEN)
    thick_segment(c, b, (cx + 10 + 48 * math.cos(a), cy + 48 * math.sin(a) * FORESHORTEN), 14, HAZARD + (255,))
    return c.image()


def turret_sheets(out):
    files = {}
    files["entity/lure-turret/lure-turret-base.png"] = base_frame()
    files["entity/lure-turret/lure-turret-base-mask.png"] = base_frame(mask=True)
    files["entity/lure-turret/lure-turret-base-shadow.png"] = base_shadow_frame()

    # Raising: 4 directions (N, E, S, W) x 5 frames; frame 0 is folded (head lowered, barrel short).
    def raising(kind):
        frames = []
        for d in range(4):
            theta = d * math.pi / 2
            for k in range(5):
                length = 22 + k * (BARREL_LEN - 22) / 4
                drop = (4 - k) * 5
                if kind == "main":
                    frames.append(head_frame(theta, length, drop))
                elif kind == "mask":
                    frames.append(head_frame(theta, length, drop, mask=True))
                else:
                    frames.append(head_shadow_frame(theta, length, drop))
        return sheet(frames, 5)
    files["entity/lure-turret/lure-turret-raising.png"] = raising("main")
    files["entity/lure-turret/lure-turret-raising-mask.png"] = raising("mask")
    files["entity/lure-turret/lure-turret-raising-shadow.png"] = raising("shadow")

    # Shooting: 64 directions x 2 frames (2 = recoil), split into 4 stripe files of 16 directions,
    # each 2 columns (frames) x 16 rows (directions).
    for stripe in range(4):
        for kind, suffix in (("main", ""), ("mask", "-mask"), ("shadow", "-shadow")):
            frames = []
            for d in range(stripe * 16, stripe * 16 + 16):
                theta = d * 2 * math.pi / 64
                for recoil in (0, 1):
                    length = BARREL_LEN - 8 * recoil
                    if kind == "main":
                        frames.append(head_frame(theta, length))
                    elif kind == "mask":
                        frames.append(head_frame(theta, length, mask=True))
                    else:
                        frames.append(head_shadow_frame(theta, length))
            files[f"entity/lure-turret/lure-turret-shooting{suffix}-{stripe + 1}.png"] = sheet(frames, 2)

    files["entity/lure-turret/remnants/lure-turret-remnants.png"] = sheet([remnants_frame(1), remnants_frame(2)], 2)
    for rel, img in files.items():
        save(img, out, rel)
    return files


# ------------------------------------------------------------------------------------------------
# Lure shell: a short fat shell with a glowing calcite tip.

def shell_icon():
    c = Canvas(64, 64)
    c.polygon([(24, 20), (40, 20), (40, 54), (24, 54)], (150, 120, 70, 255))
    c.polygon([(26, 21), (30, 21), (30, 53), (26, 53)], (196, 166, 110, 255))
    c.polygon([(22, 50), (42, 50), (42, 58), (22, 58)], (120, 92, 52, 255))
    c.ellipse(32, 20, 8, 3, (150, 120, 70, 255))
    c.polygon([(24, 20), (40, 20), (32, 4)], LAVA + (255,))
    c.polygon([(27, 20), (32, 20), (32, 7)], LAVA_HOT + (255,))
    c.polygon([(24, 34), (40, 34), (40, 40), (24, 40)], HAZARD + (255,))
    return c.image()


def shell_projectile():
    c = Canvas(32, 64)
    c.ellipse(16, 40, 7, 22, (255, 140, 40, 120))   # heat trail
    c.ellipse(16, 22, 6, 13, LAVA + (255,))
    c.ellipse(16, 18, 3.5, 8, LAVA_HOT + (255,))
    return c.image()


def shell_projectile_shadow():
    c = Canvas(32, 64)
    c.ellipse(16, 26, 5, 14, SHADOW + (255,))
    return c.image()


# ------------------------------------------------------------------------------------------------
# Demolisher egg: a glossy dark shell with glowing lava cracks, in 4 variations.

EGG_W, EGG_H, EGG_SHADOW_W = 128, 128, 176


def egg_shape(c, seed, fill_body, fill_light, crack):
    rnd = random.Random(seed)
    tilt = rnd.uniform(-0.25, 0.25)
    cx, cy = 64 + rnd.uniform(-4, 4), 70
    rx, ry = 34 + rnd.uniform(-3, 3), 44 + rnd.uniform(-3, 3)
    pts = []
    for i in range(48):
        a = i / 48 * 2 * math.pi
        # Egg profile: narrower at the top.
        r_x = rx * (1 - 0.18 * max(0, -math.sin(a)))
        x, y = r_x * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * math.cos(tilt) - y * math.sin(tilt), cy + x * math.sin(tilt) + y * math.cos(tilt)))
    if fill_body:
        c.polygon(pts, fill_body)
    if fill_light:
        c.ellipse(cx - rx * 0.35, cy - ry * 0.4, rx * 0.35, ry * 0.25, fill_light)
    if crack:
        for _ in range(4):
            x, y = cx + rnd.uniform(-rx * 0.5, rx * 0.5), cy + rnd.uniform(-ry * 0.5, ry * 0.6)
            path = [(x, y)]
            for _ in range(rnd.randint(3, 5)):
                x += rnd.uniform(-9, 9)
                y += rnd.uniform(-10, 10)
                path.append((x, y))
            c.line(path, crack, 3.2)
    return cx, cy, rx, ry


def egg_frames(seed):
    main = Canvas(EGG_W, EGG_H)
    cx, cy, rx, ry = egg_shape(main, seed, SHELL_RED + (255,), None, None)
    for i in range(8):   # shading, light from the top left
        t = i / 7
        col = tuple(int(SHELL_RED[k] + (SHELL_RED_LIGHT[k] - SHELL_RED[k]) * t) for k in range(3)) + (255,)
        main.ellipse(cx - rx * 0.2 * t, cy - ry * 0.25 * t, rx * (0.95 - 0.5 * t), ry * (0.95 - 0.5 * t), col)
    egg_shape(main, seed, None, (230, 150, 120, 140), (60, 14, 8, 255))
    glow = Canvas(EGG_W, EGG_H)
    egg_shape(glow, seed, None, None, LAVA + (255,))
    glow_img = glow.image().filter(ImageFilter.GaussianBlur(1.2))
    shadow = Canvas(EGG_SHADOW_W, EGG_H)
    shadow.ellipse(cx + 26, cy + ry * 0.75, rx * 1.15, ry * 0.4, SHADOW + (255,))
    return main.image(), glow_img, shadow.image()


def egg_icon():
    c = Canvas(64, 64)
    c.ellipse(32, 34, 20, 26, SHELL_RED + (255,))
    c.ellipse(28, 28, 13, 17, SHELL_RED_LIGHT + (255,))
    c.ellipse(25, 22, 5, 6, (230, 150, 120, 200))
    c.line([(36, 20), (32, 30), (38, 38), (34, 48)], LAVA + (255,), 2.5)
    c.line([(24, 40), (30, 44)], LAVA + (255,), 2)
    return c.image()


# ------------------------------------------------------------------------------------------------
# Demolisher nest: a low ring of churned basalt with glowing seams, eggs sit inside it.

NEST_W, NEST_H = 384, 320


def nest_frame(seed):
    rnd = random.Random(seed)
    c = Canvas(NEST_W, NEST_H)
    cx, cy = NEST_W / 2, NEST_H / 2 + 10
    c.ellipse(cx, cy, 170, 120, (34, 28, 26, 200))        # scorched ground
    for i in range(26):                                    # ring of rubble
        a = i / 26 * 2 * math.pi + rnd.uniform(-0.08, 0.08)
        r = rnd.uniform(118, 140)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a) * FORESHORTEN
        s = rnd.uniform(16, 28)
        c.ellipse(x, y + 4, s, s * 0.65, (24, 20, 18, 255))
        c.ellipse(x - 2, y, s * 0.9, s * 0.6, BASALT + (255,))
        c.ellipse(x - s * 0.3, y - s * 0.25, s * 0.45, s * 0.28, BASALT_LIGHT + (255,))
    c.ellipse(cx, cy, 104, 72, (52, 36, 30, 255))          # churned floor
    for _ in range(7):                                     # glowing seams
        a = rnd.uniform(0, 2 * math.pi)
        r0, r1 = rnd.uniform(20, 50), rnd.uniform(80, 120)
        path = [(cx + r0 * math.cos(a), cy + r0 * math.sin(a) * FORESHORTEN)]
        for k in range(1, 5):
            r = r0 + (r1 - r0) * k / 4
            a2 = a + rnd.uniform(-0.15, 0.15)
            path.append((cx + r * math.cos(a2), cy + r * math.sin(a2) * FORESHORTEN))
        c.line(path, LAVA + (255,), 3.5)
    c.ellipse(cx, cy, 40, 26, (90, 40, 20, 255))            # warm centre where the eggs lie
    c.ellipse(cx, cy, 24, 15, (150, 70, 30, 255))
    return c.image()


def nest_icon():
    c = Canvas(64, 64)
    c.ellipse(32, 36, 28, 18, BASALT + (255,))
    c.ellipse(32, 35, 20, 12, (90, 40, 20, 255))
    for x, y in ((24, 33), (33, 30), (40, 37)):
        c.ellipse(x, y, 5, 6.5, SHELL_RED_LIGHT + (255,))
    for i in range(8):
        a = i / 8 * 2 * math.pi
        c.ellipse(32 + 26 * math.cos(a), 36 + 16 * math.sin(a), 5, 3.5, BASALT_LIGHT + (255,))
    return c.image()


# ------------------------------------------------------------------------------------------------
# Icons

def turret_icon(size):
    """The lure turret seen from the front left, scaled to `size` (64 for items, 256 for tech)."""
    k = size / 64
    c = Canvas(size, size)
    cx, cy = 32 * k, 40 * k
    c.ellipse(cx, cy + 10 * k, 26 * k, 12 * k, STEEL_DARK + (255,))
    c.ellipse(cx, cy + 7 * k, 23 * k, 10 * k, (200, 120, 50, 255))   # icons have no player colour
    c.shaded_ellipse(cx, cy + 2 * k, 20 * k, 10 * k, STEEL, STEEL_LIGHT)
    thick_segment(c, (cx + 2 * k, cy - 6 * k), (cx + 26 * k, cy - 22 * k), 8 * k, STEEL_DARK + (255,))
    thick_segment(c, (cx + 18 * k, cy - 16.5 * k), (cx + 22.5 * k, cy - 19.5 * k), 9.5 * k, HAZARD + (255,))
    c.ellipse(cx + 26 * k, cy - 22 * k, 4.2 * k, 3.6 * k, STEEL + (255,))
    c.ellipse(cx + 26 * k, cy - 22 * k, 2.4 * k, 2 * k, (25, 25, 28, 255))
    c.shaded_ellipse(cx, cy - 4 * k, 15 * k, 12 * k, TUNGSTEN, TUNGSTEN_LIGHT)
    return c.image()


def tech_icon():
    img = turret_icon(256)
    # A demolisher-coloured target ring behind the turret: it lures.
    c = Canvas(256, 256)
    c.ellipse(128, 128, 118, 118, None, (255, 120, 20, 200), 10)
    c.ellipse(128, 128, 84, 84, None, (255, 120, 20, 120), 6)
    ring = c.image()
    ring.alpha_composite(img)
    return ring


def vibration_icon():
    c = Canvas(64, 64)
    c.ellipse(32, 44, 9, 5, LAVA + (255,))
    for i, r in enumerate((16, 24, 31)):
        alpha = 255 - i * 60
        box = [(32 - r) * SS, (44 - r * 0.7) * SS, (32 + r) * SS, (44 + r * 0.7) * SS]
        c._draw((LAVA + (alpha,),), lambda d: d.arc(box, start=200, end=340, fill=LAVA + (alpha,), width=int(4 * SS)))
    return c.image()


# ------------------------------------------------------------------------------------------------

def preview(files, out_png):
    """A contact sheet of the main sheets, scaled down, on a dark background."""
    tiles = []
    for rel, img in files.items():
        if "shooting-2" in rel or "shooting-3" in rel or "shooting-4" in rel:
            continue
        im = img.copy()
        im.thumbnail((360, 360))
        tiles.append((rel, im))
    cols = 4
    cw, ch = 380, 400
    rows = math.ceil(len(tiles) / cols)
    sheet_img = Image.new("RGBA", (cw * cols, ch * rows), (40, 40, 44, 255))
    d = ImageDraw.Draw(sheet_img)
    for i, (rel, im) in enumerate(tiles):
        x, y = (i % cols) * cw, (i // cols) * ch
        bg = (90, 90, 96, 255) if "mask" in rel else (200, 200, 205, 255) if "shadow" in rel else (60, 60, 66, 255)
        d.rectangle((x + 8, y + 30, x + cw - 8, y + ch - 8), fill=bg)
        d.text((x + 10, y + 8), rel, fill=(235, 235, 235, 255))
        sheet_img.alpha_composite(im, (x + (cw - im.size[0]) // 2, y + 30 + (ch - 38 - im.size[1]) // 2))
    sheet_img.convert("RGB").save(out_png)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=REPO / "mods" / "vulcanus-demolisher-lifecycle" / "graphics")
    ap.add_argument("--preview", type=Path, help="also write a contact sheet of every file here")
    args = ap.parse_args()
    out = args.out
    files = dict(turret_sheets(out))
    singles = {
        "icons/lure-turret.png": turret_icon(64),
        "technology/lure-turret.png": tech_icon(),
        "icons/lure-shell.png": shell_icon(),
        "entity/lure-shell/lure-shell.png": shell_projectile(),
        "entity/lure-shell/lure-shell-shadow.png": shell_projectile_shadow(),
        "icons/demolisher-egg.png": egg_icon(),
        "icons/demolisher-nest.png": nest_icon(),
        "icons/vibration.png": vibration_icon(),
        "entity/demolisher-nest/demolisher-nest.png": sheet([nest_frame(1), nest_frame(2)], 2),
    }
    eggs = [egg_frames(seed) for seed in range(1, 5)]
    singles["entity/demolisher-egg/demolisher-egg.png"] = sheet([e[0] for e in eggs], 4)
    singles["entity/demolisher-egg/demolisher-egg-glow.png"] = sheet([e[1] for e in eggs], 4)
    singles["entity/demolisher-egg/demolisher-egg-shadow.png"] = sheet([e[2] for e in eggs], 4)
    for rel, img in singles.items():
        save(img, out, rel)
    files.update(singles)
    for rel in sorted(files):
        print(f"{rel}: {files[rel].size[0]}x{files[rel].size[1]}")
    if args.preview:
        preview(files, args.preview)


if __name__ == "__main__":
    main()
