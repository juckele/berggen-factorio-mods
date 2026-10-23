# Unicorn Farts Art Pack: source art

Source models and tooling for the unicorn farts art pack, a reskin of Factorio
(and Space Age) drawn in **soft pastel** (the medium, not the colour scheme):
metal machines that a vanilla player still recognises, painted in a strong
pastel style. Nothing here is shipped in the mod zip.

Rendering and painting use [claude-artist](https://github.com/juckele/claude-artist)
(`artist` CLI, checked out next to this repo).

## Layout

| Path | What |
| --- | --- |
| `models/build_models.py` | Generates claude-artist scene files for each machine. Edit this, not the YAML. |
| `models/*.yaml` | Generated scenes: `assembling-machine-<tier>-<direction>.yaml`. |
| `animation.yaml` | Written by `build_models.py --only <C variant> --frames N --out DIR` next to the frame scenes: which objects move and how, for `artist layers`. |
| `style/params.yaml`, `style/params_bold.yaml` | The pack's claude-artist styles: pastel, `coverage: full`, coherent strokes, painted on a transparent sheet with stroke-owned fading edges (bold: bigger, fewer, varied strokes). |
| `tools/preview.py` | Composites painted runs over game-like grounds, at concept and in-game scale. |
| `tools/animate.py` | A looping animation painted in layers (`artist layers`): the machine once, rotating parts repainted per frame, chain runs and the piston painted once and slid. Writes preview GIFs. |
| `tools/export_sprites.py` | Turns a layered animation into Factorio sprites (64 px/tile, `scale = 0.5`): static layers, frame sheets, the ground shadow, and a Lua table of layers with shifts. |

## Conventions

- Units are tiles; x right, y up, z toward the camera (south). Near-orthographic
  camera at 45 degrees, key light from the upper left like vanilla.
- Concept renders are 192 px/tile (3x the HR sprite scale of 64 px/tile).
- Each machine keeps vanilla's anatomy (see the docstring in `build_models.py`).
  Moving parts are separate objects posed from an animation phase. Each cycle
  advances every gear a whole number of teeth, so loops are seamless.
- Sprites are cut-outs: full pastel coverage inside the silhouette, strokes
  fading out over about 1-2 px (in-game scale) past it, and nothing else painted.

## Commands

```sh
cd data/unicorn-farts-art-pack
python3 models/build_models.py                       # regenerate all scenes
A=~/claude-artist/artist
$A run models/assembling-machine-2-a.yaml --style style/params.yaml -o out/2a --quality preview
python3 tools/preview.py out/sheet.png out/2a --sprite
python3 tools/animate.py 2-c -o out/anim-2c --frames 16             # layered, bold style
python3 tools/export_sprites.py out/anim-2c/layers --entity assembling-machine-2 -o out/sprites
```
