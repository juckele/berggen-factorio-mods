# Nano Banana prompts: Vulcanus Demolisher Lifecycle sprites

Prompts for turning the placeholder sprites in `mods/vulcanus-demolisher-lifecycle/graphics/` into
finished art with Nano Banana (Gemini image generation), in a kitbashed Factorio style: new
objects visibly assembled from parts of existing Factorio and Space Age machines.

## Why jobs and not whole sheets

The game's sheets don't suit an image model:
- **Shapes and sizes.** A firing stripe is 320×2560 px. Nano Banana only outputs fixed aspect
  ratios (1:1, 2:3, 3:2, 3:4, 4:3, 4:5, 5:4, 9:16, 16:9, 21:9).
- **No transparency.** Its output has no alpha channel.
- **Consistency.** It can't keep one object identical across 128 frames in one image.

So the art is made in **jobs**: one grid of cells per image, in a supported ratio, on flat magenta.
`nano_banana_refs.py` cuts the current placeholders into exactly those grids, to attach as the
layout reference:

```sh
python3 tools/placeholder-graphics/nano_banana_refs.py <out-dir>
```

Nano Banana paints only the main art. Everything else is derived afterwards in code, which is far
more reliable than generating it:
- **Background.** Flat magenta `#FF00FF` everywhere that isn't the object. Keyed out to
  transparency.
- **Player colour.** Areas that take the player's colour are painted in **cyan** (`#00FFFF` hue),
  shaded only in brightness. The cyan becomes the greyscale mask, and the same pixels become
  neutral grey in the main sprite.
- **Cast shadows.** None painted. Shadow layers are made from each cell's silhouette.
- **Glow.** Lava, cracks and hot tips are painted bright orange-yellow in the main art. The glow
  layers are cut from those pixels.

A repacking script reverses `nano_banana_refs.py` (same `JOBS` geometry): it keys the
background, cuts each cell, scales it back to the frame size around the cell centre, splits out
masks, glow and shadows, and writes the game sheets. **That script is not written yet.** Then run
`tools/sprite-check/sprite_check.py`, and look at it in game.

## Order and consistency

1. **`turret-design` first.** Iterate until the turret looks right; this locks the design.
2. **Then the other turret jobs**, attaching the approved design image to every one of them.
3. **Firing grids in order**, stripe 1 idle, then stripe 1 recoil, and so on. Attach the
   previously approved firing grid as well, so the same object carries through all 64
   directions.
4. **Egg, nest, shell, remnants:** independent, any order.
5. **Icons last**, attaching the approved world art so the icons match it.

If a cell drifts (barrel angle wrong, parts changing), regenerate that job; don't patch single
cells by hand unless it's minor. With Nano Banana Pro, ask for the largest output size it offers
at the same aspect ratio; the grids are the same.

## Where the vanilla references come from

All paths are inside the Factorio installation's `data/` folder: `base/...` for the base game,
`space-age/...` for Space Age (only in a full game install, not the demo).
- **Big sheets** (the demolisher head, the foundry): crop a few frames and attach the crop rather
  than the whole sheet.
- **Scale:** vanilla entity sheets are high resolution, 64 px per tile, the same as ours.

---

## Shared preamble (paste at the top of every job)

```
You are finishing game sprites for a Factorio mod. Factorio's art is pre-rendered 3D: realistic,
gritty, weathered industrial machinery with painted detail, seen from a fixed top-down camera
tilted toward the viewer (ground squashed vertically to about 0.72), lit from the upper left,
with no perspective distortion. Match the attached Factorio reference sprites exactly in camera
angle, lighting, rendering style, detail density, colour grading and wear.

Style: KITBASHED. Every new object must look built from parts of existing Factorio machines — the
gun turret, tank, artillery, foundry and Vulcanus rocks in the attached references — re-arranged,
bolted together and weathered, so it reads as belonging to the same world. Prefer reusing
recognisable shapes, plating, bolts, hazard stripes and textures from the references over
inventing new ones.

Layout is fixed: the attached placeholder grid shows exactly what goes in each cell. Keep the
same grid, the same number of cells, each object centred in its cell at the same position and
size as the placeholder, and the same facing direction and pose per cell. Replace the
placeholder's flat shapes with finished art; don't move, resize or rotate anything.

Output rules:
- Background: flat, uniform pure magenta #FF00FF everywhere that isn't the object. No gradient, no
  floor, no vignette, no frame, no labels, no grid lines, no text.
- No cast shadows on the ground (shadows are added separately). Only shading on the object
  itself.
- Never use magenta, pink or purple in the object itself.
- Player-colour areas (where stated) are painted in pure cyan hue, shaded only by brightness.
  Use cyan nowhere else.
- Crisp edges against the background; no glow or haze bleeding into the magenta.
```

---

## Job: `turret-design` (lock the design)

- **Aspect ratio:** 16:9
- **Attach:**
  - `turret-design.png` (placeholder grid: 8 directions, N, NE, E, SE in the top row; S, SW, W, NW in the bottom row)
  - `base/graphics/entity/gun-turret/gun-turret-base.png`
  - a crop of `base/graphics/entity/gun-turret/gun-turret-shooting-1.png` (a few frames)
  - `base/graphics/entity/tank/tank-turret.png` (crop a few frames)
  - a crop of `base/graphics/entity/artillery-wagon/artillery-wagon-cannon-barrel.png`
  - `base/graphics/entity/artillery-turret/artillery-turret-base.png`
  - a crop of `space-age/graphics/entity/foundry/foundry-base.png`
  - `space-age/graphics/icons/tungsten-plate.png`

```
[preamble]

Object: the LURE TURRET, a slow, very long-range cannon that hurts demolishers (giant lava worms)
just enough to make them chase it. It occupies 2×2 tiles.

Kitbash it from:
- The base: the gun turret's round bolted base ring, mounted on a heavier octagonal plinth like
  the artillery turret's, clad in dark blue-grey tungsten plates (Vulcanus foundry plating).
- The head: a squat armoured dome built from the tank turret, with a collar ring where it meets
  the base.
- The barrel: a long, thick artillery-style barrel (from the artillery wagon cannon), shortened,
  slightly raised, with a reinforced muzzle and one band of yellow-black hazard stripes near the
  muzzle.

Player colour (cyan): the band around the plinth and the collar ring under the dome, exactly
where the placeholder has the grey band and collar.

Each cell shows the whole turret (base and head together) facing the cell's direction. The barrel
direction, length and elevation per cell must match the placeholder. Same object in all 8 cells.
```

## Job: `turret-base`

- **Aspect ratio:** 1:1
- **Attach:** `turret-base.png`, the approved `turret-design` output, `gun-turret-base.png`, `artillery-turret-base.png`

```
[preamble]

Object: only the base (plinth) of the attached approved lure turret design, without the head:
the octagonal tungsten-clad plinth with the gun-turret-style bolted ring on top. The top centre,
where the head will sit, is a flat round mounting plate. Match the approved design exactly.
Player colour (cyan): the band around the plinth, where the placeholder's grey band is. One cell.
```

## Jobs: `turret-shooting-1-idle` … `turret-shooting-4-recoil` (8 jobs)

- **Aspect ratio:** 1:1
- **Attach:**
  - the job's placeholder grid
  - the approved `turret-design` output
  - the previous approved firing grid (for every job after the first)
  - a crop of `gun-turret-shooting-1.png`
- **Directions:** each grid holds 16 of the 64 directions, row by row.
  - Stripe 1: directions 1–16 (north, turning clockwise to just before east).
  - Stripe 2: 17–32 (east to just before south).
  - Stripe 3: 33–48 (south to just before west).
  - Stripe 4: 49–64 (west to just before north).
  - Each step is 5.625°.

```
[preamble]

Object: only the HEAD of the attached approved lure turret design (dome, collar and barrel), no
base: it is drawn on top of the base in game. 16 cells, each the head turned to the direction
shown in the placeholder cell: copy each cell's barrel angle, length and elevation exactly. The
pivot (centre of the dome) stays at the same point in every cell. The dome, collar and barrel are
identical in every cell; only the rotation changes, as if one 3D model were rendered from 16
headings.

{idle}   The barrel is at rest, fully forward.
{recoil} The barrel is recoiled: pulled back into the dome by about an eighth of its length, as
         in the placeholder, with a faint muzzle scorch. Everything else matches the idle grid.

Player colour (cyan): the collar ring under the dome.
```

Use the `{idle}` or `{recoil}` line that matches the job and delete the other.

## Job: `turret-raising`

- **Aspect ratio:** 5:4
- **Attach:** `turret-raising.png`, the approved `turret-design` output, the approved stripe 1 idle grid, `base/graphics/entity/gun-turret/gun-turret-raising.png`

```
[preamble]

Object: the HEAD of the approved lure turret design, raising from its folded travel position.
Grid: 5 columns × 4 rows. Each row is one direction: north, east, south, west. Left to right is
the raising sequence: column 1 folded (dome lowered into the base, barrel retracted short),
column 5 fully raised and extended (identical to the firing head facing that direction). Columns
2–4 are even steps between them. Match the placeholder's height and barrel length in every cell.
Player colour (cyan): the collar ring.
```

## Job: `turret-remnants`

- **Aspect ratio:** 16:9
- **Attach:** `turret-remnants.png`, the approved `turret-design` output, `base/graphics/entity/gun-turret/remnants/gun-turret-remnants.png`, `base/graphics/entity/tank/remnants/tank-remnants.png`

```
[preamble]

Object: the wreck of the approved lure turret after it is destroyed, two variations side by side.
The plinth is cracked and blackened, plates are torn off and scattered around it, the dome is
caved in, and the barrel lies broken off with its hazard stripe visible. Kitbash the debris from
the gun turret and tank remnants. Flat on the ground, scorched. No player colour.
```

## Job: `lure-shell-projectile`

- **Aspect ratio:** 1:1
- **Attach:** `lure-shell-projectile.png`, `base/graphics/icons/cannon-shell.png`, `base/graphics/icons/artillery-shell.png`, `space-age/graphics/icons/calcite.png`

```
[preamble]

Object: the LURE SHELL in flight, seen from above, nose pointing straight up the image. A short,
fat cannon shell (kitbashed from the cannon shell) with a glowing white-hot calcite tip and a
short orange heat trail behind it. Keep it the placeholder's size and position. The tip and
trail are bright orange-yellow and white (they glow in game).
```

## Job: `egg`

- **Aspect ratio:** 1:1
- **Attach:**
  - `egg.png` (2×2 grid, 4 variations)
  - a crop of `space-age/graphics/entity/lavaslug/lavaslug-head.png` (the demolisher's head)
  - a crop of `space-age/graphics/entity/lavaslug/lavaslug-segment.png`
  - `space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-big.png` and `-emissive.png` (crops)
  - `space-age/graphics/icons/big-volcanic-rock-hot.png`

```
[preamble]

Object: a DEMOLISHER EGG, four variations. A demolisher is Vulcanus's giant armoured lava worm;
its egg is about 2 tiles tall, laid in a nest of rubble. Kitbash it from the demolisher's own
armour: overlapping dark basalt-grey carapace plates (from the demolisher head and segment
sprites) wrapped into an upright egg shape, narrower at the top, with molten orange-yellow light
showing through the seams and cracks between plates (like the hot volcanic rocks' glowing
cracks). Each variation differs in plate arrangement, crack pattern and a slight tilt. Same size
and position as the placeholder eggs. The glowing seams are bright orange-yellow (they glow in
game). No player colour.
```

## Jobs: `nest-1`, `nest-2`

- **Aspect ratio:** 5:4
- **Attach:**
  - the job's placeholder
  - `space-age/graphics/decorative/vulcanus-rocks/vulcanus-rock-huge.png` and `-emissive.png` (crops)
  - a crop of `space-age/graphics/entity/demolisher/fissure/demolisher-crack-effect.png`
  - a crop of `space-age/graphics/entity/lavaslug/lavaslug-segment.png`
  - the approved `egg` output

```
[preamble]

Object: a DEMOLISHER NEST, about 6×5 tiles, lying flat on the ground (it is drawn under
everything else). A low oval ring of churned, broken basalt rubble and chunks of volcanic rock,
kitbashed from the huge Vulcanus rocks, pushed up where a demolisher coiled around this spot. The
floor inside is churned, darker ground with glowing orange fissures (like the demolisher's crack
effect) radiating from a warm, faintly glowing centre where eggs will lie. No eggs in the image:
they are separate sprites. Keep the placeholder's outline, size and position. The fissures and
centre are bright orange (they glow in game). No player colour. For the second nest, the same
design with a different rubble arrangement and crack pattern.
```

## Job: `icons`

- **Aspect ratio:** 3:2
- **Attach:**
  - `icons.png` (3×2 grid)
  - the approved turret, shell, egg and nest outputs
  - Factorio icons for the icon style:
    - `base/graphics/icons/gun-turret.png`
    - `base/graphics/icons/cannon-shell.png`
    - `base/graphics/icons/artillery-shell.png`
    - `space-age/graphics/icons/big-volcanic-rock-hot.png`
    - `space-age/graphics/icons/calcite.png`
  - Factorio technology icons for the technology icon style:
    - `base/graphics/technology/artillery.png`
    - `base/graphics/technology/gun-turret.png`

```
[preamble — but icons may use a three-quarter view and no fixed camera]

Six Factorio icons, one per cell, in Factorio's icon style: a single object, large in its cell,
bold readable silhouette, strong contrast, slightly stylised, matching the attached Factorio
icons. Row 1: the lure turret (whole turret, barrel pointing up-right; player-colour areas
painted a neutral orange-grey here, not cyan); the lure shell standing upright with its glowing
calcite tip; a demolisher egg. Row 2: the demolisher nest seen from above at an angle, with three
eggs in it; "vibration", an abstract icon of ground tremor waves rising from a cracked rock
(orange waves); the lure turret technology icon (the turret large and detailed with an orange
target ring behind it, in Factorio's technology icon style). The background stays flat magenta.
```

---

## After generating

- Keep each approved output under its job name (`turret-design.png`, `turret-shooting-1-idle.png`, …).
- The repacking script turns them into the game sheets.
- Until that exists, the placeholders stay in place, and the mod keeps working with them.
