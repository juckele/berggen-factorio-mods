# Graphics

Everything here is a placeholder drawn by
`tools/placeholder-graphics/vulcanus_demolisher_lifecycle.py` (rerun it to regenerate; it is
deterministic). The sheets are laid out exactly as the prototypes read them, so real art can
replace any file as long as it keeps the same layout. Check a replacement with
`tools/sprite-check/sprite_check.py`.

Finished art is planned with Nano Banana: see
`tools/placeholder-graphics/vulcanus_demolisher_lifecycle_prompts.md`.

Conventions:
- **Resolution.** Entity sheets are high resolution, drawn at `scale = 0.5`: 64 px per tile.
- **View.** Factorio's top-down view, ground squashed vertically (about 0.72), lit from the top
  left.
- **Shadows.** Separate black silhouettes (`draw_as_shadow`), cast to the right. Their frames are
  wider than the main frames by 48 px, all on the right.
- **Masks.** Greyscale; the game tints them with the player colour (`apply_runtime_tint`). White
  is full player colour; transparent is none. The main sprite has a neutral grey where the mask
  goes.
- **Glow.** Layers drawn unlit at full brightness (`draw_as_glow`), for lava and heat.
- **Directions.** Direction 1 faces north, then clockwise (east is a quarter of the way through).

## Lure turret (`entity/lure-turret/`)

A squat, tungsten-plated plinth carrying a long, slightly raised cannon barrel with a hazard
stripe near the muzzle. The plinth's band and the head's collar take the player colour. 2×2 tiles.

| File | Frame | Layout | Notes |
| --- | --- | --- | --- |
| `lure-turret-base.png`, `-base-mask.png` | 160×160 | 1 frame | The plinth. Shift (0, −2) px. |
| `lure-turret-base-shadow.png` | 208×160 | 1 frame | Shift (12, −2) px. |
| `lure-turret-raising.png`, `-raising-mask.png` | 160×160 | 5 frames per row × 4 rows (directions N, E, S, W) | Frame 1 is folded (head lowered, barrel short); frame 5 fully raised. Used backwards for folding. Shift (0, −24) px. |
| `lure-turret-raising-shadow.png` | 208×160 | same | Shift (12, −24) px. |
| `lure-turret-shooting-1..4.png`, `-shooting-mask-1..4.png` | 160×160 | each file 2 columns (frames) × 16 rows (directions); file 1 holds directions 1–16, file 2 holds 17–32, and so on, 64 directions in all | Column 2 is the recoil frame (barrel pulled back). Column 1 alone is the idle, prepared head. The head pivots 18 px above the entity centre. Shift (0, −24) px. |
| `lure-turret-shooting-shadow-1..4.png` | 208×160 | same | Shift (12, −24) px. |
| `remnants/lure-turret-remnants.png` | 192×192 | 2 variations side by side | Wrecked plinth with scattered plates and the broken barrel. |

The muzzle is about a tile out from the pivot (`projectile_creation_distance = 1.0`).

## Lure shell (`entity/lure-shell/`)

| File | Frame | Notes |
| --- | --- | --- |
| `lure-shell.png` | 32×64 | In flight, pointing up (the game rotates it). Glow layer: a hot calcite tip and heat trail. |
| `lure-shell-shadow.png` | 32×64 | Its shadow. |

## Demolisher egg (`entity/demolisher-egg/`)

A glossy dark-red egg, narrower at the top, with glowing lava cracks. Collision about 1.4 tiles.

| File | Frame | Layout | Notes |
| --- | --- | --- | --- |
| `demolisher-egg.png` | 128×128 | 4 variations side by side | Shift (0, −3) px. |
| `demolisher-egg-glow.png` | 128×128 | same | Only the cracks, drawn as glow. |
| `demolisher-egg-shadow.png` | 176×128 | same | Shift (12, −3) px. |

## Demolisher nest (`entity/demolisher-nest/`)

A low ring of churned basalt rubble around a warm centre where 1–3 eggs lie, with glowing seams.
Drawn flat on the ground (render layer `floor-mechanics`), so no shadow. About 6×5 tiles.

| File | Frame | Layout | Notes |
| --- | --- | --- | --- |
| `demolisher-nest.png` | 384×320 | 2 variations side by side | Shift (0, −5) px. Eggs sit about 1.5 tiles from the centre. |

## Icons

All 64×64 without mipmaps, except the technology icon (256×256).

| File | Used by |
| --- | --- |
| `icons/lure-turret.png` | Lure turret item, entity, recipe and remnants |
| `icons/lure-shell.png` | Lure shell ammo and recipe |
| `icons/demolisher-egg.png` | Demolisher egg |
| `icons/demolisher-nest.png` | Demolisher nest |
| `icons/vibration.png` | The vibration pollutant (map pollution views) |
| `technology/lure-turret.png` | Lure turret technology |

The egg on the map is a plain red dot (`map_color`), not an image.
