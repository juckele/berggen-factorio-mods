# Vulcanus Demolisher Lifecycle art pipeline

Turns the mod's placeholder sprites into finished, kitbashed art with Nano Banana, run by an
agent.

**To run it:** open a Gemini agent that can use Nano Banana, with this repository checked out on
the machine where Factorio (with Space Age) is installed, and give it this one instruction:

> Read `art/vulcanus-demolisher-lifecycle/AGENT.md` and do what it says.

It works through all 17 jobs on its own, resumes from `approved/` if interrupted, writes the
sheets into the mod, checks them, commits locally (no push) and reports back. It only stops to
ask if it can't find Factorio, can't generate images, or can't get an acceptable turret design.

| File | What it is |
| --- | --- |
| `AGENT.md` | The agent's instructions. |
| `jobs.py` | The jobs: grid geometry, prompts, vanilla references, dependencies. |
| `kit.py` | Builds `kit/` (layouts, reference crops, prompts, manifests) and `PROMPTS.md`. |
| `repack.py` | `check` a generated image, `apply` approved images to the mod, render a `preview`. |
| `PROMPTS.md` | All prompts, readable (generated from `jobs.py`). |
| `approved/` | Accepted images, one per job (committed; the source art). |
| `kit/`, `work/` | Generated kit and attempts (not committed). |

**How it works:** the model only paints the main art, on flat magenta, with player-colour areas
in cyan. `repack.py` derives everything else:
- the transparency (from the magenta);
- the player-colour masks (from the cyan);
- the glow layers (from hot orange pixels);
- the shadows (from each silhouette).

The checker scores every cell against the layout: shape overlap, the turret barrel's direction,
centring and size. Weak cells get regenerated before anything reaches the mod.
