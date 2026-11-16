# Agent task: finish the Vulcanus Demolisher Lifecycle sprites with Nano Banana

You are an agent with this repository checked out, a shell, and an image-generation tool
(Nano Banana: Gemini image generation that accepts reference images). Your job: replace the
mod's placeholder sprites with finished, kitbashed Factorio-style art, **without asking the person
anything** unless a step below says to stop. Work through every job, judge your own results with
the checker and your own eyes, and leave a finished, committed result plus a report.

Everything you need is in this folder (`art/vulcanus-demolisher-lifecycle/`):
- **`jobs.py`:** the 17 jobs (grids, prompts, references). Read it; don't change it.
- **`kit.py`:** builds each job's attachments, prompt and manifest.
- **`repack.py`:**
  - `check` scores a generated image.
  - `apply` writes approved images into the mod.
  - `preview` renders a review image.
- **`PROMPTS.md`:** the prompts in readable form (generated).
- **Mod graphics:** the output lands in `mods/vulcanus-demolisher-lifecycle/graphics/` (layouts in its
  `README.md`).

## Rules

- **What not to touch:**
  - Don't edit Lua, prototypes, other mods, `jobs.py`, or the checker's thresholds.
  - Don't hand-edit files in `mods/.../graphics/`: only `repack.py apply` writes there.
- **Prompts:** use each job's prompt exactly as given in its manifest. You may append a short
  correction paragraph when regenerating (see the loop), but never remove or reword the given
  text.
- **Attachments:** attach exactly the images `kit.py --pack <job>` prints, in that order (at most 3:
  the layout first). Don't build your own composites.
- **Aspect ratio:** ask for the manifest's aspect ratio, and the largest output size the tool
  offers. If the tool doesn't offer that ratio, use the nearest one it has and save the result
  as it comes; `check` and `apply` resize it themselves. Use Nano Banana Pro if you can choose;
  otherwise the default image model.
- **Git:** don't push and don't open pull requests. Commit locally at the end (see Finish).
- **When to stop and ask:** only for the problems listed under "Stop and ask". Everything else
  you decide yourself and record in the report.

## Setup

1. Install the Python packages if missing: `python3 -m pip install pillow numpy`.
2. Find Factorio's `data/` folder. It must contain `space-age/graphics`. Try, in order:
   - Windows Steam: `C:\Program Files (x86)\Steam\steamapps\common\Factorio\data`
   - macOS Steam: `~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/data`
   - Linux Steam: `~/.steam/steam/steamapps/common/Factorio/data`, `~/.local/share/Steam/steamapps/common/Factorio/data`
   - Standalone: `~/factorio/data`, `/opt/factorio/data`, `C:\Program Files\Factorio\data`
   - Otherwise search the disk for a `space-age/graphics/entity/foundry` folder, limited to home
     and program folders.

   Also note the Factorio executable next to it (`../bin/x64/factorio`, `factorio.exe`, or on
   macOS `factorio.app/Contents/MacOS/factorio`); it's used for the final check.
3. Build the kit from the repository root:
   `python3 art/vulcanus-demolisher-lifecycle/kit.py --factorio-data "<data folder>"`.
   If it reports missing vanilla references, first check you have the right `data/` folder.
   If files are still missing, carry on without them and list them in the report; don't
   substitute other files.
4. Run `python3 art/vulcanus-demolisher-lifecycle/kit.py --list` to see the jobs in order and
   which are already approved. Approved images live in `art/vulcanus-demolisher-lifecycle/approved/`;
   skip those jobs (this lets you resume).

## The loop, for each job in order

Each job's folder is `art/vulcanus-demolisher-lifecycle/kit/NN-<job>/`. Read its `manifest.json`.
1. **Check prerequisites.** Every `approved/...` path in `attachments` must exist. They do if you
   go in order.
2. **Generate.** Run `python3 art/vulcanus-demolisher-lifecycle/kit.py --pack <job>`, then call
   the image tool with:
   - the manifest's `prompt`;
   - the images it printed, in order;
   - the manifest's `aspect_ratio`.

   Save the result as `art/vulcanus-demolisher-lifecycle/work/<job>/attempt-N.png`, with N
   starting at 1, as a lossless PNG.
3. **Check by script.** Run
   `python3 art/vulcanus-demolisher-lifecycle/repack.py check <job> <that file>`.
   - It scores each cell against the layout:
     - **overlap:** shape match.
     - **barrel:** the part that turns, for the turret.
     - **offset** and **size**.
   - It also checks the magenta background, cyan player-colour areas and stray purple.
   - Exit code 0 means pass.
4. **Check by eye.** Look at the image yourself and compare it with the layout and the approved
   images it depends on. Reject it if any of these hold:
   - **Design drift:** it doesn't look like the same object as the approved design (shape, parts,
     colours).
   - **Wrong pose:** in a turret grid, a cell's barrel points a different way from the layout's
     cell. For example, it should turn steadily clockwise, cell by cell.
   - **Wrong layout:** there are labels, numbers, grid lines, borders, a floor or painted ground
     shadows; or cells are merged, missing or extra.
   - **Wrong look:** it doesn't read as Factorio art next to the vanilla references (camera
     angle, top-left light, gritty pre-rendered style), or it isn't visibly kitbashed from
     those references.
   - **Cyan missing:** the player-colour areas aren't cyan where the layout has cyan.
5. **Accept** if both checks pass: copy the file to `art/vulcanus-demolisher-lifecycle/approved/<job>.png`
   (exactly that name).
6. **Otherwise retry**, up to 5 attempts per job:
   - **Small fix:** if only a few cells or details are wrong and the image tool can edit, edit the
     attempt with a precise instruction ("in row 2, column 3, turn the barrel to match the layout:
     pointing up and to the right at about 30 degrees"). Then check again.
   - **Otherwise regenerate**, appending a short correction paragraph to the prompt. Base it on
     the checker's output and what you saw, for example: "Previous attempt failed: cells 5–8 had
     the barrel pointing left; the background had a gradient. Fix these."
7. **After 5 attempts without a pass**, approve the attempt with the fewest checker problems that
   also looks acceptable, and record it in the report as a weak job. If none is acceptable to the
   eye, record the job as skipped, leave its placeholder in place, and move on. Don't let one job
   block the rest, but **don't skip `turret-design`** (see "Stop and ask").

Do the jobs in the listed order: later jobs attach earlier approved images to stay consistent.
After approving `turret-design`, look at it critically once more before continuing; everything
on the turret follows from it.

## Apply and verify

When every job is approved or skipped, run from the repository root:

1. **Write the sheets:** `python3 art/vulcanus-demolisher-lifecycle/repack.py apply`. This
   writes all approved jobs into the mod's sheets, deriving the player-colour masks, glow layers
   and shadows.
2. **Check every sprite reference:**
   `python3 tools/sprite-check/sprite_check.py --factorio "<factorio executable>" mods/vulcanus-demolisher-lifecycle`.
   It must print "No problems". If it reports a problem, a sheet was written with the wrong
   size, which means a bug. Stop and report it rather than working around it.
3. **Render the review image:**
   `python3 art/vulcanus-demolisher-lifecycle/repack.py preview art/vulcanus-demolisher-lifecycle/preview.png`.
4. **Look at the preview.** It should show:
   - the turret in 8 directions, with player-coloured (orange) bands and soft shadows to the
     right;
   - a nest with three glowing eggs;
   - the icons.

   If something is clearly broken (for example a cell cut off at an edge, or a shadow on the
   wrong side), find which job it comes from. Redo that job with the loop, then apply again.

## Finish

1. **Write the report.** Create `art/vulcanus-demolisher-lifecycle/REPORT.md` with:
   - the image model used;
   - for each job: attempts, final checker result (pass, or the remaining problems), and a
     one-line note on anything weak;
   - jobs skipped;
   - anything the person should look at in game.
2. **Commit locally** on the current branch, staging only:
   - `art/vulcanus-demolisher-lifecycle/approved/`
   - `art/vulcanus-demolisher-lifecycle/REPORT.md`
   - `art/vulcanus-demolisher-lifecycle/preview.png`
   - `mods/vulcanus-demolisher-lifecycle/graphics/`

   Use the message "Vulcanus Demolisher Lifecycle: generated sprites (Nano Banana)" followed by a
   short summary. Don't push.
3. **Tell the person you're done** in one short message:
   - where the report and preview are;
   - which jobs are weak or skipped;
   - that they should run the game once to look at the turret, eggs and nest.

## Stop and ask (the only reasons to interrupt the person)

- **No Factorio data:** you can't find a Factorio `data/` folder with Space Age graphics.
- **No image tool:** the image tool is unavailable, or refuses every attempt (quota, policy). Say
  which job you were on; approved work is kept, and rerunning this task resumes.
- **No acceptable design:** `turret-design` has no acceptable result after 5 attempts. Show your
  best two attempts and ask which direction to take.
- **A script crashes:** `kit.py` or `repack.py` fails with an error, not just a failed check.
  Report the error; don't modify the scripts.
