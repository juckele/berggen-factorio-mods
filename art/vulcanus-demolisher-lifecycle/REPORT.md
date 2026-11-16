# Vulcanus Demolisher Lifecycle — Sprite Generation Report

- **Image model used:** `gemini-3.1-flash-image` (Nano Banana via `generate_image`)
- **Result:** 17/17 jobs approved (16/17 passed `repack.py check` outright; 1 weak job `icons` approved after 5 attempts; 0 skipped)
- **Sprite check:** `tools/sprite-check/sprite_check.py --factorio /home/juckele/factorio_ubuntu/client_sa_2_1_23/bin/x64/factorio mods/vulcanus-demolisher-lifecycle` → **Checked 64 sprite and icon references in 31 files. No problems.**

## Per-job summary

| # | Job | Attempts | Final checker result | Notes |
| ---: | --- | ---: | --- | --- |
| 1 | `turret-design` | 4 | **PASS** (`1376x768`, magenta 75%, overlap `0.94–0.98`, barrel `0.84–0.92`, offset `0.2%–0.9%`, size `1.02–1.03x`) | Clean 8-direction base design matching layout and kitbash references. |
| 2 | `turret-base` | 1 | **PASS** (`1024x1024`, magenta 63%, overlap `0.92`, offset `2.4%`, size `1.09x`) | Clean octagonal tungsten plinth with flat bolted top plate and cyan band. |
| 3 | `turret-shooting-1-idle` | 3 | **PASS** (`1024x1024`, magenta 87%, overlap `0.92–0.96`, barrel `0.80–0.96`, offset `0.1%–0.6%`, size `1.01–1.04x`) | Smooth N→E rotation; isolated dome, cyan collar, and barrel. |
| 4 | `turret-shooting-1-recoil` | 2 | **PASS** (`1024x1024`, magenta 88%, overlap `0.91–0.94`, barrel `0.73–0.90`, offset `0.1%–0.9%`, size `1.01–1.07x`) | Consistent N→E recoil frames with scorched muzzle. |
| 5 | `turret-shooting-2-idle` | 5 | **PASS** (`1024x1024`, magenta 88%, overlap `0.96–0.97`, barrel `0.89–0.95`, offset `0.1%–0.5%`, size `1.01–1.03x`) | Smooth E→S rotation using isolated head reference card. |
| 6 | `turret-shooting-2-recoil` | 1 | **PASS** (`1024x1024`, magenta 89%, overlap `0.93–0.96`, barrel `0.86–0.91`, offset `0.2%–0.6%`, size `1.03–1.05x`) | Consistent E→S recoil frames. |
| 7 | `turret-shooting-3-idle` | 2 | **PASS** (`1024x1024`, magenta 88%, overlap `0.95–0.96`, barrel `0.91–0.96`, offset `0.1%–0.3%`, size `1.02–1.04x`) | Smooth S→W rotation. |
| 8 | `turret-shooting-3-recoil` | 3 | **PASS** (`1024x1024`, magenta 88%, overlap `0.90–0.93`, barrel `0.65–0.76`, offset `0.8%–1.5%`, size `1.06–1.09x`) | Consistent S→W recoil frames. |
| 9 | `turret-shooting-4-idle` | 1 | **PASS** (`1024x1024`, magenta 87%, overlap `0.95–0.96`, barrel `0.91–0.94`, offset `0.1%–0.3%`, size `1.00–1.03x`) | Smooth W→N rotation. |
| 10 | `turret-shooting-4-recoil` | 1 | **PASS** (`1024x1024`, magenta 87%, overlap `0.91–0.92`, barrel `0.74–0.80`, offset `1.2%–2.0%`, size `1.06–1.08x`) | Consistent W→N recoil frames. |
| 11 | `turret-raising` | 2 | **PASS** (`1280x1024`, magenta 88%, overlap `0.72–0.88`, barrel `0.49–0.84`, offset `0.8%–3.8%`, size `1.12–1.20x`) | Generated at `4:3` and resized to `1280x1024` (`5:4`); smooth 5-step raise per cardinal direction. |
| 12 | `turret-remnants` | 4 | **PASS** (`1376x768`, magenta 71%, overlap `0.83 / 0.87`, offset `3.4% / 2.0%`, size `1.19 / 1.14x`) | Two caved-in, scorched turret wrecks with broken hazard-striped barrels and torn plates. |
| 13 | `lure-shell-projectile` | 2 | **PASS** (`1024x1024`, magenta 83%, overlap `0.97`, offset `0.1%`, size `1.03x`) | Upright brass/steel shell with glowing white-hot calcite tip and orange trail. |
| 14 | `egg` | 1 | **PASS** (`1024x1024`, magenta 72%, overlap `0.99`, offset `0.0%–0.2%`, size `1.00–1.01x`) | Four basalt carapace eggs with glowing orange lava seams. |
| 15 | `nest-1` | 1 | **PASS** (`1280x1024`, magenta 43%, overlap `0.89`, offset `2.3%`, size `1.12x`) | Generated at `4:3` and resized to `1280x1024` (`5:4`); basalt rubble ring and glowing lava fissures. |
| 16 | `nest-2` | 2 | **PASS** (`1280x1024`, magenta 39%, overlap `0.83`, offset `3.0%`, size `1.21x`) | **Weak:** generated at `4:3` and resized to `5:4`; shares the same outer boulder ring silhouette as `nest-1`, differing mainly in inner crack branching. |
| 17 | `icons` | 5 | **FAIL (weak)** (`1264x848`, magenta 57%, cells 2–6 PASS overlap `0.74–0.93` offset `1.2%–4.9%`, cell 1 overlap `0.69` size `1.07x` **offset `6.0%`**) | **Weak:** cell 1 (`lure-turret.png`) remained marginally above the 6% offset threshold (`6.0%`); cell 6 (`technology/lure-turret.png`) shows an exposed mechanical breech behind the dome unlike the closed dome in world art. |

## Jobs skipped

None.

## Pipeline notes (no repo scripts edited)

- **Space Age vanilla references:** `kit.py` initially reported missing files because 6 paths in `jobs.py` differed from Factorio's `data/space-age/graphics/` layout (`foundry-base.png` → `foundry-main-1.png`; `vulcanus-rocks/vulcanus-rock-big-1.png` → `big-volcanic-rock/big-volcanic-rock-01.png`; `vulcanus-rock-big-emissive-1.png` → `vulcanus-cracks/vulcanus-cracks-hot-large-01.png`; `vulcanus-rock-huge-1/2.png` → `huge-volcanic-rock/huge-volcanic-rock-05/06.png`; `icons/big-volcanic-rock-hot.png` → `icons/big-volcanic-rock.png`). Resolved via a temporary symlinked data directory in scratch.
- **`ImagePaths` limit (`maxItems: 3`):** `generate_image` enforces at most 3 image attachments, so `01-layout.png` was always passed first and additional approved/vanilla references were packed into composite contact sheets in scratch.
- **`5:4` aspect ratio (`11`, `15`, `16`):** `generate_image` rejects `"5:4"` (`4:3` was requested and resized cleanly to `1280x1024`).

## What to look at in game

- **Lure turret (`preview.png` and in-game):** Check the turret collar ring at south/south-west headings in game—in `preview.png`, a faint ~1 px dark-blue fringe appears along the shadowed front edge of the collar where `split_mask` stops thresholding dark cyan (`v <= 0.12` or `s <= 0.3`), and verify smooth rotation/recoil/raising animation transitions across all 64 firing directions.
- **Eggs and nests:** Verify the glow intensity of egg seams (`demolisher-egg-glow.png`) and nest fissures against Vulcanus terrain, and check whether `nest-2` needs more distinct outer rock variation from `nest-1` when multiple nests sit side by side.
- **Icons and technology:** Check the `lure-turret` item icon (`64x64`, slight framing offset) and `lure-turret` technology icon (`256x256`) in the crafting and tech UI.
