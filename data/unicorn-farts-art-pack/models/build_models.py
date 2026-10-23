#!/usr/bin/env python3
"""Generate the assembling machine scenes for the unicorn farts art pack.

Writes assembling-machine-{1,2,3}.yaml next to this file. The scenes are
claude-artist scene files (see juckele/claude-artist, docs/PIPELINE.md);
render them with `artist render <scene> -o out/...`.

Units are Factorio tiles (1 unit = 1 tile). x is right, y is up, z is toward
the camera (the south edge of the machine). A 3x3 machine occupies roughly
[-1.4, 1.4] on x and z.

Run:  python3 build_models.py
"""

from __future__ import annotations

import math
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- palette
# Pastel, colourful, a bit candy-glossy.
PINK = "#f9b9d6"
PINK_DEEP = "#f08fbb"
MINT = "#b6efd8"
MINT_DEEP = "#8fdcbf"
LAVENDER = "#cdbcf5"
LAVENDER_DEEP = "#a894e6"
BUTTER = "#fff0a8"
GOLD = "#ffd86b"
PEACH = "#ffcdb0"
SKY = "#b5dcff"
CREAM = "#fff6ec"
PEARL = "#f6f0fc"
RAINBOW = ["#ff9db8", "#ffc59a", "#fff0a0", "#b6f0c0", "#a9dcff", "#c9b6f5"]

GLOSS = {"roughness": 0.32, "specular": 0.45}
MATTE = {"roughness": 0.6, "specular": 0.15}


def mat(color, **kw):
    return {"color": color, **(GLOSS | kw)}


# ----------------------------------------------------------------- parts
def box(size, pos, color, rot=None, **kw):
    p = {"shape": "box", "size": list(size), "position": list(pos), "material": mat(color, **kw)}
    if rot:
        p["rotation"] = list(rot)
    return p


def cyl(radius, height, pos, color, rot=None, **kw):
    p = {"shape": "cylinder", "radius": radius, "height": height, "position": list(pos), "material": mat(color, **kw)}
    if rot:
        p["rotation"] = list(rot)
    return p


def ball(radius, pos, color, **kw):
    return {"shape": "sphere", "radius": radius, "position": list(pos), "material": mat(color, **kw)}


def ring(major, minor, pos, color, rot=None, **kw):
    p = {"shape": "torus", "major": major, "minor": minor, "position": list(pos), "material": mat(color, **kw)}
    p["rotation"] = list(rot) if rot else [0, 0, 0]
    return p


def lathe(profile, pos, color, rot=None, **kw):
    p = {"shape": "lathe", "profile": [list(q) for q in profile], "position": list(pos), "material": mat(color, **kw)}
    if rot:
        p["rotation"] = list(rot)
    return p


def body(color, half, rounding, center_y, name="body"):
    """Puffy rounded block (smooth-union blob so the corners are soft)."""
    return {
        "name": name,
        "shape": "blob",
        "resolution": 0.03,
        "material": mat(color),
        "elements": [{"type": "roundbox", "center": [0, center_y, 0], "half": list(half), "rounding": rounding}],
    }


def gear(center, radius, teeth, color, hub_color, y_thick=0.1):
    """A chunky gear lying flat: disc + teeth + hub. Parts are in world coords."""
    cx, cy, cz = center
    parts = [cyl(radius, y_thick, (cx, cy, cz), color)]
    for i in range(teeth):
        a = 360.0 * i / teeth
        r = radius + 0.03
        x = cx + r * math.sin(math.radians(a))
        z = cz + r * math.cos(math.radians(a))
        parts.append(box((0.2, y_thick, 0.2), (x, cy, z), color, rot=(0, a, 0)))
    parts.append(cyl(radius * 0.38, y_thick + 0.05, (cx, cy + 0.02, cz), hub_color))
    return parts


def rainbow_band(z, y0, width, thickness=0.04, stripe=0.07, depth=0.04):
    """Rainbow stripes across a vertical face at z (facing +z)."""
    out = []
    for i, c in enumerate(RAINBOW):
        out.append(box((width, stripe, depth), (0, y0 + i * stripe, z), c, **MATTE))
    return out


def gumdrops(points, radius=0.12, colors=None):
    colors = colors or [PINK_DEEP, MINT_DEEP, GOLD, SKY]
    return [ball(radius, p, colors[i % len(colors)]) for i, p in enumerate(points)]


def puffs(base, count, r0, drift=(0.0, 0.16, -0.08)):
    """A little rising trail of rainbow fart-clouds, shrinking as they go."""
    out = []
    x, y, z = base
    for i in range(count):
        out.append(ball(r0 * (1 - 0.12 * i), (x + 0.05 * math.sin(i * 1.7), y + drift[1] * i, z + drift[2] * i), RAINBOW[i % len(RAINBOW)], **MATTE))
    return out


# ----------------------------------------------------------------- scene frame
def scene(name, objects):
    # Camera: steeply tilted (66 deg) and nearly orthographic, framed like a
    # Factorio entity sprite (about 3 tiles wide). Key light from the upper
    # left like the vanilla art; soft pastel fill from the right.
    return {
        "name": name,
        "units": "tile",
        "image": {"width": 792, "height": 752},
        "camera": {"look_at": [0, 0.3, 0], "azimuth": 0, "elevation": 66, "distance": 14.0, "fov": 12.4},
        "lights": [
            {"name": "key", "azimuth": -50, "elevation": 55, "intensity": 2.0, "color": "#fff4ea", "softness": 6.0},
            {"name": "fill", "azimuth": 120, "elevation": 35, "intensity": 0.55, "color": "#e2e6ff", "shadows": False, "specular": False},
        ],
        "environment": {"sky": "#f3ecff", "ground": "#e9dff0", "intensity": 0.9},
        "exposure": 0.95,
        "objects": objects,
    }


def ground():
    return {
        "name": "ground",
        "role": "ground",
        "shape": "box",
        "size": [8, 0.05, 8],
        "position": [0, -0.025, 0],
        "material": {"color": "#e8e0ee", "roughness": 0.9, "specular": 0.05},
    }


def trim(name, parts):
    return {"name": name, "parts": parts}


# ----------------------------------------------------------------- tier 1: candy box
def assembling_machine_1():
    objs = [ground(), body(PINK, (1.34, 0.42, 1.26), 0.22, 0.42)]
    top = 0.84
    parts = [
        box((2.3, 0.05, 2.1), (0, top, -0.02), CREAM, **MATTE),
        ring(0.74, 0.07, (0, top + 0.06, -0.02), BUTTER, rot=(90, 0, 0)),
        cyl(0.7, 0.04, (0, top + 0.04, -0.02), MINT_DEEP),
    ]
    parts += gear((0, top + 0.1, -0.02), 0.42, 8, LAVENDER, PINK_DEEP)
    parts += rainbow_band(1.275, 0.2, 2.2, stripe=0.065)
    parts += gumdrops([(-1.0, top + 0.1, 0.85), (1.0, top + 0.1, 0.85), (-1.0, top + 0.1, -0.9), (1.0, top + 0.1, -0.9)])
    parts += puffs((0.0, top + 0.1, -0.9), 4, 0.15, drift=(0.0, 0.1, -0.07))
    objs.append(trim("details", parts))
    return scene("unicorn-assembling-machine-1", objs)


# ----------------------------------------------------------------- tier 2: lavender sparkle
def sparkle(pos, size, color):
    h = size
    return lathe([(0, -h), (h * 0.55, 0), (0, h)], pos, color, rot=(0, 0, 0))


def assembling_machine_2():
    objs = [ground(), body(LAVENDER, (1.35, 0.55, 1.28), 0.22, 0.55)]
    # second, smaller tier on top
    objs.append(body("#b9a6ef", (0.98, 0.2, 0.92), 0.22, 1.16, name="upper"))
    parts = [
        box((2.2, 0.05, 1.95), (0, 1.1, -0.05), CREAM, **MATTE),  # top plate beside the upper tier
        ring(0.62, 0.07, (0, 1.4, -0.04), GOLD, rot=(90, 0, 0)),
        cyl(0.58, 0.04, (0, 1.38, -0.04), SKY),
    ]
    parts += gear((0, 1.46, -0.04), 0.36, 10, PINK, GOLD)
    parts += rainbow_band(1.305, 0.2, 2.3, stripe=0.08)
    parts += []
    parts += gumdrops([(-1.05, 1.18, 0.9), (1.05, 1.18, 0.9), (-1.05, 1.18, -0.95), (1.05, 1.18, -0.95)], radius=0.13, colors=[MINT_DEEP, PINK_DEEP, GOLD, SKY])
    # sparkle crystals on the shoulders of the upper tier
    parts += [sparkle((-0.95, 1.5, 0.75), 0.24, SKY), sparkle((0.95, 1.5, 0.75), 0.24, PINK), sparkle((0.0, 1.55, -0.9), 0.3, MINT)]
    parts += puffs((-0.6, 1.2, -0.95), 3, 0.14, drift=(0.0, 0.09, -0.05)) + puffs((0.6, 1.2, -0.95), 3, 0.14, drift=(0.0, 0.09, -0.05))
    objs.append(trim("details", parts))
    return scene("unicorn-assembling-machine-2", objs)


# ----------------------------------------------------------------- tier 3: pearl, horn, mane
def horn(base, tilt_deg, length=1.25, radius=0.18):
    """Gold spiral horn leaning toward the camera (+z). Returns parts."""
    t = math.radians(tilt_deg)
    d = (0.0, math.cos(t), math.sin(t))
    bx, by, bz = base
    prof = [(0, 0), (radius, 0), (radius * 0.85, length * 0.2), (radius * 0.6, length * 0.5), (radius * 0.3, length * 0.8), (0, length)]
    parts = [lathe(prof, base, GOLD, rot=(tilt_deg, 0, 0), roughness=0.22, specular=0.7)]
    # spiral rings along the horn
    for i in range(1, 6):
        f = i / 6
        r = radius * (1.02 - 0.95 * f) + 0.01
        c = (bx + d[0] * length * f, by + d[1] * length * f, bz + d[2] * length * f)
        parts.append(ring(r, 0.025, c, "#ffefb0", rot=(tilt_deg + 90, 0, 0), roughness=0.25, specular=0.6))
    return parts


def mane(z, x0, x1, y, n, r0):
    """Row of rainbow puffs along the back edge: the unicorn mane."""
    parts = []
    for i in range(n):
        f = i / (n - 1)
        x = x0 + (x1 - x0) * f
        r = r0 * (1.0 + 0.2 * math.sin(f * math.pi))
        parts.append(ball(r, (x, y + 0.05 * math.sin(f * 9), z + 0.06 * math.cos(f * 7)), RAINBOW[i % len(RAINBOW)], **MATTE))
    return parts


def assembling_machine_3():
    objs = [ground(), body(PEARL, (1.34, 0.6, 1.3), 0.22, 0.6)]
    top = 1.2
    parts = [
        box((2.3, 0.05, 2.0), (0, top, 0.0), "#efe6fb", **MATTE),
        box((2.3, 0.07, 0.1), (0, top + 0.02, 0.98), GOLD, roughness=0.25, specular=0.7),  # gold trim front
        ring(0.66, 0.08, (0, top + 0.07, 0.05), GOLD, rot=(90, 0, 0), roughness=0.25, specular=0.7),
        cyl(0.62, 0.04, (0, top + 0.05, 0.05), "#d9c7f7"),
    ]
    parts += gear((0, top + 0.12, 0.05), 0.4, 12, MINT, GOLD)
    # iridescent panels on the front face
    for i, c in enumerate([PINK, PEACH, BUTTER, MINT, SKY, LAVENDER]):
        parts.append(box((0.36, 0.7, 0.04), (-0.95 + i * 0.38, 0.55, 1.33), c, **MATTE))
    parts += gumdrops([(-1.05, top + 0.1, 0.85), (1.05, top + 0.1, 0.85)], radius=0.13, colors=[PINK_DEEP, SKY])
    parts += horn((0.78, top + 0.05, 0.2), 38)
    parts += mane(-1.05, -1.1, 1.0, top + 0.18, 7, 0.19)
    objs.append(trim("details", parts))
    return scene("unicorn-assembling-machine-3", objs)


def main():
    for n, fn in ((1, assembling_machine_1), (2, assembling_machine_2), (3, assembling_machine_3)):
        path = HERE / f"assembling-machine-{n}.yaml"
        header = f"# Generated by build_models.py: edit that, not this. Unicorn farts art pack, assembling machine {n}.\n"
        path.write_text(header + yaml.safe_dump(fn(), sort_keys=False, default_flow_style=None, width=120))
        print("wrote", path.relative_to(HERE.parent.parent.parent))


if __name__ == "__main__":
    main()
