"""Image-generation jobs for the Vulcanus Demolisher Lifecycle sprites.

One job = one generated image: a grid of cells in an aspect ratio Nano Banana supports, on flat
magenta. Each cell maps to one frame of the mod's sprite sheets (a Slot). This module is the
single source for the grid geometry, the prompts and the vanilla references; kit.py, check and
apply (repack.py) and PROMPTS.md are all built from it.
"""

from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
GRAPHICS = REPO / "mods" / "vulcanus-demolisher-lifecycle" / "graphics"
APPROVED = HERE / "approved"
KIT = HERE / "kit"
WORK = HERE / "work"

MAGENTA = (255, 0, 255)
CYAN = (0, 255, 255)


@dataclass
class Frame:
    """A frame in a sheet: file under graphics/, frame size, column and row."""
    rel: str
    w: int
    h: int
    col: int = 0
    row: int = 0

    def box(self):
        return (self.col * self.w, self.row * self.h, self.col * self.w + self.w, self.row * self.h + self.h)


@dataclass
class Slot:
    """One cell of a job and where its pixels go. mask: cyan in the cell becomes this player-colour
    mask frame. glow: hot orange pixels are copied to this glow frame. shadow: the silhouette is
    projected onto the ground into this (wider) shadow frame, or copied as it is when
    flat_shadow (projectiles: the game places their shadow on the ground itself)."""
    main: Frame
    mask: Frame = None
    glow: Frame = None
    shadow: Frame = None
    flat_shadow: bool = False
    float_px: int = 0        # how far the bottom of the object is above the ground, in frame px


@dataclass
class Job:
    name: str
    aspect: str              # aspect ratio to ask the model for
    size: tuple              # the grid is laid out (and checked) at this size
    grid: tuple              # columns, rows
    slots: list              # one per cell, row by row
    prompt: str
    vanilla: list = field(default_factory=list)   # (path under Factorio's data/, crop) — see kit.py
    depends: list = field(default_factory=list)   # approved jobs to attach, in order
    writes: bool = True      # False: design reference only, nothing goes into the mod
    player_colour: bool = False
    icons: bool = False
    layout_frame: object = None  # custom layout frame builder (slot index -> RGBA image)
    min_background: float = 0.3  # share of the image that must be magenta


# ------------------------------------------------------------------------------------------------
# Prompts

PREAMBLE = """You are finishing game sprites for a Factorio mod. Factorio's art is pre-rendered 3D:
realistic, gritty, weathered industrial machinery with painted detail, seen from a fixed top-down
camera tilted toward the viewer (ground squashed vertically to about 0.72), lit from the upper
left, with no perspective distortion. Match the attached Factorio reference sprites in camera
angle, lighting, rendering style, detail density, colour grading and wear.

Style: KITBASHED. Every new object must look built from parts of existing Factorio machines, the
ones in the attached references, re-arranged, bolted together and weathered, so it reads as
belonging to the same world. Prefer reusing recognisable shapes, plating, bolts, hazard stripes
and textures from the references over inventing new ones.

The FIRST attached image is the layout: a grid with exactly what goes in each cell. Keep the same
grid, the same number of cells, each object centred in its cell at the same position and size as
in the layout, and the same facing direction and pose per cell. Replace the layout's flat shapes
with finished art; don't move, resize, rotate, add or remove anything. The other attached images
are reference sheets: one with a magenta background collects earlier approved results of this
same project, which define the design (match them exactly); one with a grey background collects
vanilla Factorio sprites, for the style and the parts to kitbash from.

Output rules:
- Background: flat, uniform pure magenta #FF00FF everywhere that isn't the object. No gradient,
  floor, vignette, frame, labels, grid lines or text.
- No cast shadows on the ground (they are added separately). Only shading on the object itself.
- Never use magenta, pink or purple in the object.
- Cyan in the layout marks player-colour areas: paint those areas pure cyan hue, shaded only by
  brightness, exactly where the layout has cyan. Use cyan nowhere else.
- Crisp edges against the background; no glow, haze or smoke bleeding into the magenta.
"""

TURRET_DESIGN = """Object: the LURE TURRET, a slow, very long-range cannon that hurts demolishers (Vulcanus's
giant armoured lava worms) just enough to make them chase it. It occupies 2x2 tiles.

Kitbash it from:
- Base: the gun turret's round bolted base ring, mounted on a heavier octagonal plinth like the
  artillery turret's, clad in dark blue-grey tungsten plates (Vulcanus foundry plating).
- Head: a squat armoured dome built from the tank turret, with a collar ring where it meets the
  base.
- Barrel: a long, thick artillery-style barrel (from the artillery wagon cannon), shortened,
  slightly raised, with a reinforced muzzle and one band of yellow-black hazard stripes near the
  muzzle.

Player colour (cyan): the band around the plinth and the collar ring under the dome.

The grid has 8 cells: the whole turret (base and head together) facing north, north-east, east,
south-east in the top row and south, south-west, west, north-west in the bottom row. Barrel
direction, length and elevation per cell must match the layout. The same object in all 8 cells.
"""

TURRET_BASE = """Object: only the BASE (plinth) of the approved lure turret design, without the head: the
octagonal tungsten-clad plinth with the gun-turret-style bolted ring on top. The top centre, where
the head sits, is a flat round mounting plate. Match the approved design exactly. Player colour
(cyan): the band around the plinth, where the layout has cyan. One cell.
"""

TURRET_HEAD = """Object: only the HEAD of the approved lure turret design (dome, collar and barrel), no base:
it is drawn on top of the base in game. 16 cells, each the head turned to the direction shown in
the layout cell (row by row, turning clockwise in 5.625 degree steps, {range}); copy each cell's
barrel angle, length and elevation exactly. The pivot (centre of the dome) stays at the same point
in every cell. The dome, collar and barrel are identical in every cell; only the heading changes,
as if one 3D model were rendered from 16 headings. Player colour (cyan): the collar ring under the
dome. {variant}
"""

IDLE = "The barrel is at rest, fully forward."
RECOIL = ("The barrel is recoiled: pulled back into the dome by about an eighth of its length, as in "
          "the layout, with a faint scorch at the muzzle. Everything else matches the approved idle "
          "grid for these directions.")

TURRET_RAISING = """Object: the HEAD of the approved lure turret design raising from its folded travel position.
Grid: 5 columns x 4 rows. Each row is one direction: north, east, south, west. Left to right is
the raising sequence: column 1 folded (dome lowered into the base, barrel retracted short), column
5 fully raised and extended (identical to the approved firing head facing that direction).
Columns 2-4 are even steps between them. Match the layout's height and barrel length in every
cell. Player colour (cyan): the collar ring.
"""

TURRET_REMNANTS = """Object: the wreck of the approved lure turret after it is destroyed, two variations side by
side. The plinth is cracked and blackened, plates are torn off and scattered around it, the dome
is caved in, and the barrel lies broken off with its hazard stripe visible. Kitbash the debris
from the gun turret and tank remnants. Flat on the ground, scorched. No player colour (no cyan).
"""

SHELL = """Object: the LURE SHELL in flight, seen from above, nose pointing straight up the image: a short,
fat cannon shell (kitbashed from the cannon shell) with a glowing white-hot calcite tip and a short
orange heat trail behind it. Keep the layout's size and position. The tip and trail are bright
orange-yellow and white (they glow in game). No cyan.
"""

EGG = """Object: a DEMOLISHER EGG, four variations in a 2x2 grid. A demolisher is Vulcanus's giant armoured
lava worm; its egg is about 2 tiles tall and lies in a nest of rubble. Kitbash it from the
demolisher's own armour: overlapping dark basalt-grey carapace plates (from the attached
demolisher head and segment sprites) wrapped into an upright egg shape, narrower at the top, with
molten orange-yellow light showing through the seams and cracks between plates (like the hot
volcanic rocks' glowing cracks). The variations differ in plate arrangement, crack pattern and a
slight tilt. Same size and position as the layout's eggs. The glowing seams are bright
orange-yellow (they glow in game). No cyan.
"""

NEST = """Object: a DEMOLISHER NEST, about 6x5 tiles, lying flat on the ground (it is drawn under everything
else). A low oval ring of churned, broken basalt rubble and chunks of volcanic rock, kitbashed
from the attached huge Vulcanus rocks, pushed up where a demolisher coiled around this spot. The
floor inside is churned, darker ground with glowing orange fissures (like the demolisher's crack
effect) radiating from a warm, faintly glowing centre where eggs will lie. No eggs in the image:
they are separate sprites. Keep the layout's outline, size and position. Fissures and centre are
bright orange (they glow). No cyan. {variant}
"""

ICONS = """Six Factorio ICONS, one per cell, in Factorio's icon style: a single object, large in its cell,
bold readable silhouette, strong contrast, slightly stylised, matching the attached Factorio
icons. Icons may use a three-quarter view (the fixed camera rule doesn't apply). Row 1: the lure
turret (whole turret, barrel pointing up-right; its player-colour areas painted a neutral
orange-grey, NOT cyan); the lure shell standing upright with its glowing calcite tip; a demolisher
egg. Row 2: the demolisher nest seen from above at an angle, with three eggs in it; "vibration",
an abstract icon of ground-tremor waves rising from a cracked rock (orange waves); the lure turret
technology icon (the turret large and detailed with an orange target ring behind it, in
Factorio's technology icon style). Match the approved world art for the turret, shell, egg and
nest. No cyan anywhere.
"""


# ------------------------------------------------------------------------------------------------
# Layout frames (what each cell shows in the reference grid)

def load(rel):
    return Image.open(GRAPHICS / rel).convert("RGBA")


def crop(frame):
    return load(frame.rel).crop(frame.box())


def paint_cyan(img, mask_img):
    """Player-colour areas in cyan, shaded by the mask's brightness."""
    out = img.copy()
    m = mask_img.convert("RGBA")
    px, mp = out.load(), m.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = mp[x, y]
            if a > 40:
                v = (r + g + b) / 765
                v = 0.45 + 0.55 * v
                px[x, y] = (0, int(255 * v), int(255 * v), max(a, px[x, y][3]))
    return out


def layout_frame(slot):
    img = crop(slot.main)
    if slot.mask:
        img = paint_cyan(img, crop(slot.mask))
    if slot.glow:
        img.alpha_composite(crop(slot.glow))
    return img


def whole_turret(direction):
    """Base and head for one of the 64 firing directions, as the game stacks them (base 2 px up,
    head 24 px up in game pixels, twice that in these high-resolution frames)."""
    stripe, row = direction // 16 + 1, direction % 16
    base = layout_frame(BASE_SLOT)
    head = layout_frame(shooting_slot(stripe, 0, row))
    out = Image.new("RGBA", (160, 220), (0, 0, 0, 0))
    out.alpha_composite(base, (0, 60 - 4))
    out.alpha_composite(head, (0, 60 - 48))
    return out


# ------------------------------------------------------------------------------------------------
# Slots

T = "entity/lure-turret/"
# The head is drawn 44 px higher than the base (shifts -24 and -2 game px, doubled here): its
# shadow falls that far below it.
HEAD_FLOAT = 44


def shooting_slot(stripe, col, row):
    return Slot(Frame(f"{T}lure-turret-shooting-{stripe}.png", 160, 160, col, row),
                mask=Frame(f"{T}lure-turret-shooting-mask-{stripe}.png", 160, 160, col, row),
                shadow=Frame(f"{T}lure-turret-shooting-shadow-{stripe}.png", 208, 160, col, row),
                float_px=HEAD_FLOAT)


BASE_SLOT = Slot(Frame(f"{T}lure-turret-base.png", 160, 160),
                 mask=Frame(f"{T}lure-turret-base-mask.png", 160, 160),
                 shadow=Frame(f"{T}lure-turret-base-shadow.png", 208, 160))

# ------------------------------------------------------------------------------------------------
# Vanilla references: (path under Factorio's data/, crop). Crop is (frame_w, frame_h, cols, rows):
# the top-left cols x rows frames; None keeps the image (up to 1024x1024 from the top left).

V_GUN_BASE = ("base/graphics/entity/gun-turret/gun-turret-base.png", None)
V_GUN_HEAD = ("base/graphics/entity/gun-turret/gun-turret-shooting-1.png", (132, 130, 2, 4))
V_GUN_RAISING = ("base/graphics/entity/gun-turret/gun-turret-raising.png", None)
V_TANK_TURRET = ("base/graphics/entity/tank/tank-turret.png", (179, 132, 4, 2))
V_ART_BARREL = ("base/graphics/entity/artillery-wagon/artillery-wagon-cannon-barrel-1.png", (530, 384, 2, 1))
V_ART_BASE = ("base/graphics/entity/artillery-turret/artillery-turret-base.png", None)
V_FOUNDRY = ("space-age/graphics/entity/foundry/foundry-base.png", (356, 384, 1, 1))
V_GUN_REMNANTS = ("base/graphics/entity/gun-turret/remnants/gun-turret-remnants.png", None)
V_TANK_REMNANTS = ("base/graphics/entity/tank/remnants/tank-remnants.png", None)
V_DEMO_HEAD = ("space-age/graphics/entity/lavaslug/lavaslug-head-1.png", (610, 586, 2, 1))
V_DEMO_SEGMENT = ("space-age/graphics/entity/lavaslug/lavaslug-segment-1.png", (606, 586, 2, 1))
V_ROCK_BIG = ("space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-big-1.png", None)
V_ROCK_BIG_GLOW = ("space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-big-emissive-1.png", None)
V_ROCK_HUGE = ("space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-huge-1.png", None)
V_ROCK_HUGE_2 = ("space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-huge-2.png", None)
V_CRACKS = ("space-age/graphics/entity/demolisher/fissure/demolisher-crack-effect.png", (926, 718, 1, 1))
V_ICON_GUN = ("base/graphics/icons/gun-turret.png", (64, 64, 1, 1))
V_ICON_CANNON = ("base/graphics/icons/cannon-shell.png", (64, 64, 1, 1))
V_ICON_ARTILLERY = ("base/graphics/icons/artillery-shell.png", (64, 64, 1, 1))
V_ICON_ROCK = ("space-age/graphics/icons/big-volcanic-rock-hot.png", (64, 64, 1, 1))
V_ICON_CALCITE = ("space-age/graphics/icons/calcite.png", (64, 64, 1, 1))
V_TECH_ARTILLERY = ("base/graphics/technology/artillery.png", (256, 256, 1, 1))
V_TECH_GUN = ("base/graphics/technology/gun-turret.png", (256, 256, 1, 1))

# ------------------------------------------------------------------------------------------------
# Jobs, in the order to run them.

JOBS = []

JOBS.append(Job(
    name="turret-design", aspect="16:9", size=(1820, 1024), grid=(4, 2),
    slots=[None] * 8, writes=False, player_colour=True,
    layout_frame=lambda i: whole_turret(i * 8),
    prompt=TURRET_DESIGN,
    vanilla=[V_GUN_BASE, V_TANK_TURRET, V_ART_BARREL, V_ART_BASE, V_FOUNDRY, V_GUN_HEAD],
))

JOBS.append(Job(
    name="turret-base", aspect="1:1", size=(1024, 1024), grid=(1, 1),
    slots=[BASE_SLOT], player_colour=True, prompt=TURRET_BASE, depends=["turret-design"],
    vanilla=[V_GUN_BASE, V_ART_BASE, V_FOUNDRY],
))

STRIPE_RANGES = {1: "north to just before east", 2: "east to just before south",
                 3: "south to just before west", 4: "west to just before north"}
previous = "turret-design"
for stripe in range(1, 5):
    for col, kind in ((0, "idle"), (1, "recoil")):
        name = f"turret-shooting-{stripe}-{kind}"
        deps = ["turret-design"]
        if kind == "recoil":
            deps.append(f"turret-shooting-{stripe}-idle")
        elif previous != "turret-design":
            deps.append(previous)
        JOBS.append(Job(
            name=name, aspect="1:1", size=(1024, 1024), grid=(4, 4),
            slots=[shooting_slot(stripe, col, r) for r in range(16)], player_colour=True,
            prompt=TURRET_HEAD.format(range=STRIPE_RANGES[stripe], variant=IDLE if kind == "idle" else RECOIL),
            depends=deps, vanilla=[V_GUN_HEAD, V_TANK_TURRET],
        ))
        if kind == "idle":
            previous = name

JOBS.append(Job(
    name="turret-raising", aspect="5:4", size=(1280, 1024), grid=(5, 4),
    slots=[Slot(Frame(f"{T}lure-turret-raising.png", 160, 160, k, d),
                mask=Frame(f"{T}lure-turret-raising-mask.png", 160, 160, k, d),
                shadow=Frame(f"{T}lure-turret-raising-shadow.png", 208, 160, k, d), float_px=HEAD_FLOAT)
           for d in range(4) for k in range(5)],
    player_colour=True, prompt=TURRET_RAISING, depends=["turret-design", "turret-shooting-1-idle"],
    vanilla=[V_GUN_RAISING],
))

JOBS.append(Job(
    name="turret-remnants", aspect="16:9", size=(1820, 1024), grid=(2, 1),
    slots=[Slot(Frame(f"{T}remnants/lure-turret-remnants.png", 192, 192, i, 0)) for i in range(2)],
    prompt=TURRET_REMNANTS, depends=["turret-design"], vanilla=[V_GUN_REMNANTS, V_TANK_REMNANTS],
))

JOBS.append(Job(
    name="lure-shell-projectile", aspect="1:1", size=(1024, 1024), grid=(1, 1),
    slots=[Slot(Frame("entity/lure-shell/lure-shell.png", 32, 64),
                shadow=Frame("entity/lure-shell/lure-shell-shadow.png", 32, 64), flat_shadow=True)],
    prompt=SHELL, vanilla=[V_ICON_CANNON, V_ICON_ARTILLERY, V_ICON_CALCITE], min_background=0.6,
))

E = "entity/demolisher-egg/"
JOBS.append(Job(
    name="egg", aspect="1:1", size=(1024, 1024), grid=(2, 2),
    slots=[Slot(Frame(f"{E}demolisher-egg.png", 128, 128, i, 0),
                glow=Frame(f"{E}demolisher-egg-glow.png", 128, 128, i, 0),
                shadow=Frame(f"{E}demolisher-egg-shadow.png", 176, 128, i, 0)) for i in range(4)],
    prompt=EGG, vanilla=[V_DEMO_HEAD, V_DEMO_SEGMENT, V_ROCK_BIG, V_ROCK_BIG_GLOW],
))

for v in range(2):
    JOBS.append(Job(
        name=f"nest-{v + 1}", aspect="5:4", size=(1280, 1024), grid=(1, 1),
        slots=[Slot(Frame("entity/demolisher-nest/demolisher-nest.png", 384, 320, v, 0))],
        prompt=NEST.format(variant="" if v == 0 else
                           "This is the second variation: match the approved first nest's look with a "
                           "different rubble arrangement and crack pattern."),
        depends=["egg"] + (["nest-1"] if v == 1 else []),
        vanilla=[V_ROCK_HUGE, V_ROCK_HUGE_2, V_CRACKS, V_DEMO_SEGMENT], min_background=0.15,
    ))

JOBS.append(Job(
    name="icons", aspect="3:2", size=(1536, 1024), grid=(3, 2),
    slots=[Slot(Frame(rel, s, s)) for rel, s in (
        ("icons/lure-turret.png", 64), ("icons/lure-shell.png", 64), ("icons/demolisher-egg.png", 64),
        ("icons/demolisher-nest.png", 64), ("icons/vibration.png", 64), ("technology/lure-turret.png", 256))],
    icons=True, prompt=ICONS,
    depends=["turret-design", "egg", "nest-1"],
    vanilla=[V_ICON_GUN, V_ICON_CANNON, V_ICON_ROCK, V_TECH_ARTILLERY, V_TECH_GUN],
))

BY_NAME = {j.name: j for j in JOBS}


def layout_frames(job):
    if job.layout_frame:
        return [job.layout_frame(i) for i in range(len(job.slots))]
    return [layout_frame(s) for s in job.slots]


def full_prompt(job):
    return PREAMBLE + "\n" + job.prompt
