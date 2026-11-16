#!/usr/bin/env python3
"""Builds the generation kit: for every job, the layout grid, the prompt, the vanilla reference
crops and a manifest listing what to attach in which order. Also writes PROMPTS.md.

    python3 art/vulcanus-demolisher-lifecycle/kit.py [--factorio-data DIR] [--list]

--factorio-data is the Factorio installation's data/ folder (it must include Space Age). Without
it the kit has no vanilla references. Output: art/vulcanus-demolisher-lifecycle/kit/<job>/
(gitignored; rebuild any time).

kit/<job>/manifest.json:
  job, aspect_ratio, attachments (repo-relative paths, in order: layout first, then approved
  results of earlier jobs, then vanilla references), prompt (the full prompt text), output (where
  the approved image goes).
Approved results are listed even before they exist; they must exist when the job runs.

Image tools often take only a few attachments (Gemini's takes 3), so before generating a job run

    python3 art/vulcanus-demolisher-lifecycle/kit.py --pack JOB

It packs the job's attachments into at most 3 images in its kit folder and prints their paths:
the layout, one sheet of the approved results it depends on (if any), and one sheet of the
vanilla references.
"""

import argparse
import json
import shutil
import sys

from PIL import Image

import jobs as J


def flatten(img):
    """Opaque where the sprite is, so nothing blends with the magenta: partly transparent pixels
    (ground stains) are composited onto dark ground; faint ones are dropped."""
    base = Image.new("RGBA", img.size, (64, 52, 48, 255))
    base.alpha_composite(img)
    base.putalpha(img.getchannel("A").point(lambda a: 255 if a >= 24 else 0))
    return base


def cell_geometry(job, frame_size):
    w, h = job.size
    cols, rows = job.grid
    cw, ch = w // cols, h // rows
    k = min(cw / frame_size[0], ch / frame_size[1])
    return cw, ch, k


def layout_image(job):
    w, h = job.size
    cols, _ = job.grid
    out = Image.new("RGBA", (w, h), J.MAGENTA + (255,))
    for i, f in enumerate(J.layout_frames(job)):
        cw, ch, k = cell_geometry(job, f.size)
        f = flatten(f.resize((round(f.width * k), round(f.height * k)), Image.LANCZOS))
        out.alpha_composite(f, ((i % cols) * cw + (cw - f.width) // 2, (i // cols) * ch + (ch - f.height) // 2))
    return out.convert("RGB")


def vanilla_crop(data_dir, rel, spec):
    img = Image.open(data_dir / rel).convert("RGBA")
    if spec:
        fw, fh, cols, rows = spec
        img = img.crop((0, 0, min(img.width, fw * cols), min(img.height, fh * rows)))
    else:
        img = img.crop((0, 0, min(img.width, 1024), min(img.height, 1024)))
    # Vanilla sprites are transparent; show them on neutral grey (magenta is reserved).
    bg = Image.new("RGBA", img.size, (128, 128, 128, 255))
    bg.alpha_composite(img)
    return bg.convert("RGB")


def rel(path):
    return str(path.relative_to(J.REPO))


def contact_sheet(images, background, max_side=2048, gap=16):
    """Images side by side in a near-square grid, each scaled to fit its tile."""
    cols = max(1, round(len(images) ** 0.5 + 0.49))
    rows = -(-len(images) // cols)
    tile = (max_side - gap * (cols + 1)) // cols
    out = Image.new("RGB", (cols * tile + gap * (cols + 1), rows * tile + gap * (rows + 1)), background)
    for i, img in enumerate(images):
        img = img.convert("RGB")
        k = min(tile / img.width, tile / img.height)
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
        x = gap + (i % cols) * (tile + gap) + (tile - img.width) // 2
        y = gap + (i // cols) * (tile + gap) + (tile - img.height) // 2
        out.paste(img, (x, y))
    return out


def pack(name):
    """The job's attachments as at most 3 images; returns their paths."""
    job = J.BY_NAME[name]
    n = J.JOBS.index(job) + 1
    d = J.KIT / f"{n:02d}-{name}"
    manifest = json.loads((d / "manifest.json").read_text())
    paths = [J.REPO / p for p in manifest["attachments"]]
    approved = [p for p in paths if p.parent == J.APPROVED]
    missing = [p for p in approved if not p.exists()]
    if missing:
        sys.exit("approve these first: " + ", ".join(p.stem for p in missing))
    vanilla = [p for p in paths[1:] if p.parent != J.APPROVED]
    out = [paths[0]]
    if approved:
        sheet = d / "packed-approved.png"
        contact_sheet([Image.open(p) for p in approved], (255, 0, 255)).save(sheet)
        out.append(sheet)
    if vanilla:
        sheet = d / "packed-references.png"
        contact_sheet([Image.open(p) for p in vanilla], (128, 128, 128)).save(sheet)
        out.append(sheet)
    return out


def build(data_dir):
    if J.KIT.exists():
        shutil.rmtree(J.KIT)
    missing = []
    for n, job in enumerate(J.JOBS, 1):
        d = J.KIT / f"{n:02d}-{job.name}"
        d.mkdir(parents=True)
        layout = d / "01-layout.png"
        layout_image(job).save(layout)
        attachments = [rel(layout)] + [rel(J.APPROVED / f"{dep}.png") for dep in job.depends]
        for i, (vrel, spec) in enumerate(job.vanilla if data_dir else []):
            src = data_dir / vrel
            if not src.exists():
                missing.append(vrel)
                continue
            out = d / f"{10 + i:02d}-{src.stem}.png"
            vanilla_crop(data_dir, vrel, spec).save(out)
            attachments.append(rel(out))
        prompt = J.full_prompt(job)
        (d / "prompt.txt").write_text(prompt)
        (d / "manifest.json").write_text(json.dumps({
            "job": job.name,
            "aspect_ratio": job.aspect,
            "attachments": attachments,
            "prompt": prompt,
            "output": rel(J.APPROVED / f"{job.name}.png"),
            "writes_into_mod": job.writes,
        }, indent=2))
        print(f"{d.name}: {job.aspect}, {len(attachments)} attachments")
    if missing:
        print("Missing vanilla references (wrong data folder, or no Space Age?):\n  " + "\n  ".join(missing))
        return 1
    return 0


def prompts_md():
    lines = ["# Nano Banana prompts: Vulcanus Demolisher Lifecycle sprites", "",
             "Generated by `kit.py` from `jobs.py`; edit those, not this file. The agent instructions are in",
             "`AGENT.md`. Every job's full prompt is the shared preamble followed by the job's text.", "",
             "## Shared preamble", "", "```", J.PREAMBLE.rstrip(), "```", ""]
    for n, job in enumerate(J.JOBS, 1):
        lines += [f"## {n}. `{job.name}`", "",
                  f"- Aspect ratio: {job.aspect}; grid {job.grid[0]}×{job.grid[1]}"
                  + ("" if job.writes else " (design reference only, nothing goes into the mod)"),
                  "- Attach, in order: the layout grid"
                  + "".join(f", approved `{d}`" for d in job.depends)
                  + "".join(f", `{v[0]}`" for v in job.vanilla), "",
                  "```", job.prompt.rstrip(), "```", ""]
    (J.HERE / "PROMPTS.md").write_text("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factorio-data", type=lambda p: __import__("pathlib").Path(p).expanduser())
    ap.add_argument("--list", action="store_true", help="print the jobs in order and exit")
    ap.add_argument("--pack", metavar="JOB", help="pack JOB's attachments into at most 3 images and print them")
    args = ap.parse_args()
    if args.pack:
        for p in pack(args.pack):
            print(rel(p))
        return 0
    if args.list:
        for n, job in enumerate(J.JOBS, 1):
            done = (J.APPROVED / f"{job.name}.png").exists()
            print(f"{n:2d}. {job.name:28s} {'approved' if done else 'pending'}  needs: {', '.join(job.depends) or '-'}")
        return 0
    prompts_md()
    if args.factorio_data and not (args.factorio_data / "space-age" / "graphics").is_dir():
        sys.exit(f"{args.factorio_data} is not a Factorio data/ folder with Space Age graphics")
    return build(args.factorio_data)


if __name__ == "__main__":
    sys.exit(main())
