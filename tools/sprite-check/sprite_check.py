#!/usr/bin/env python3
"""Checks a mod's sprite and icon references against its image files, without a graphical client.

Headless Factorio never loads images, so a wrong path, frame size or frame count only shows up
when a player starts the game. This runs `factorio --dump-data` (headless works) with the given
mods, then walks every prototype for references into those mods and checks:

- every `__mod__/...` path exists;
- sprites, animations and rotated animations (width/height or size, x/y, frame_count,
  direction_count, line_length, stripes) fit inside their image;
- icons (`icon`/`icon_size`, `icons`) and `size`-only sprites fit inside their image.

    python3 tools/sprite-check/sprite_check.py --factorio PATH/bin/x64/factorio MOD_DIR [MOD_DIR...]

MOD_DIRs are mod folders (their info.json names them). Base and the Space Age mods are enabled.
Exits non-zero on any problem. Requires Pillow.
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

BUILTIN_MODS = ["base", "space-age", "quality", "elevated-rails"]


def dump_data(factorio, mod_dirs, work):
    mods = work / "mods"
    write = work / "write"
    mods.mkdir(parents=True)
    write.mkdir()
    read_data = Path(factorio).resolve().parents[2] / "data"
    config = work / "config.ini"
    config.write_text(f"[path]\nread-data={read_data}\nwrite-data={write}\n")
    mod_list = [{"name": m, "enabled": True} for m in BUILTIN_MODS]
    names = {}
    for d in mod_dirs:
        info = json.loads((d / "info.json").read_text())
        shutil.copytree(d, mods / info["name"], ignore=shutil.ignore_patterns(".git", "*.zip"))
        mod_list.append({"name": info["name"], "enabled": True})
        names[info["name"]] = d
    (mods / "mod-list.json").write_text(json.dumps({"mods": mod_list}))
    result = subprocess.run([str(factorio), "--config", str(config), "--mod-directory", str(mods), "--dump-data"],
                            capture_output=True, text=True)
    dump = write / "script-output" / "data-raw-dump.json"
    if result.returncode != 0 or not dump.exists():
        sys.exit("factorio --dump-data failed:\n" + result.stdout[-4000:] + result.stderr[-2000:])
    return json.loads(dump.read_text()), names


class Checker:
    def __init__(self, mods):
        self.mods = mods
        self.sizes = {}
        self.problems = []
        self.checked = 0
        self.files = set()

    def resolve(self, filename):
        for name, d in self.mods.items():
            prefix = f"__{name}__/"
            if filename.startswith(prefix):
                return d / filename[len(prefix):]
        return None

    def size(self, path):
        if path not in self.sizes:
            self.sizes[path] = Image.open(path).size if path.exists() else None
        return self.sizes[path]

    def problem(self, where, message):
        self.problems.append(f"{where}: {message}")

    def image(self, where, filename):
        path = self.resolve(filename)
        if path is None:
            return None
        self.files.add(path)
        size = self.size(path)
        if size is None:
            self.problem(where, f"missing file {filename}")
        return size

    @staticmethod
    def dims(node):
        w, h = node.get("width"), node.get("height")
        size = node.get("size")
        if isinstance(size, list):
            w, h = w or size[0], h or size[1]
        elif size is not None:
            w, h = w or size, h or size
        return w, h

    def check_layer(self, where, node, parent=None):
        """A sprite/animation layer with a filename, or stripes."""
        w, h = self.dims(node)
        if parent:
            pw, ph = self.dims(parent)
            w, h = w or pw, h or ph
        frames = node.get("frame_count", (parent or {}).get("frame_count", 1)) or 1
        directions = node.get("direction_count", (parent or {}).get("direction_count", 1)) or 1
        if "stripes" in node:
            if not any(self.resolve(st.get("filename", "")) for st in node["stripes"]):
                return
            total_rows = 0
            for i, stripe in enumerate(node["stripes"]):
                size = self.image(f"{where}.stripes[{i}]", stripe["filename"])
                if not size:
                    continue
                self.checked += 1
                need_w = stripe.get("x", 0) + w * stripe["width_in_frames"]
                need_h = stripe.get("y", 0) + h * stripe["height_in_frames"]
                if need_w > size[0] or need_h > size[1]:
                    self.problem(where, f"stripe {stripe['filename']} needs {need_w}x{need_h}, image is {size[0]}x{size[1]}")
                if stripe["width_in_frames"] < frames:
                    self.problem(where, f"stripe {stripe['filename']} has {stripe['width_in_frames']} frames per row, animation needs {frames}")
                total_rows += stripe["height_in_frames"]
            if total_rows < directions and directions > 1:
                self.problem(where, f"stripes cover {total_rows} directions, animation has {directions}")
            return
        filename = node.get("filename")
        if not isinstance(filename, str):
            return
        size = self.image(where, filename)
        if not size:
            return
        self.checked += 1
        if w is None or h is None:
            self.problem(where, f"{filename}: no width/height or size")
            return
        x, y = node.get("x", 0), node.get("y", 0)
        if isinstance(node.get("position"), list):
            x, y = node["position"]
        line_length = node.get("line_length", 0) or 0
        if line_length == 0:
            cols, rows = frames, directions
        else:
            cols = min(line_length, frames * directions)
            rows = math.ceil(frames * directions / line_length)
        need_w, need_h = x + cols * w, y + rows * h
        if need_w > size[0] or need_h > size[1]:
            self.problem(where, f"{filename} needs {need_w}x{need_h} ({cols}x{rows} frames of {w}x{h} at {x},{y}), image is {size[0]}x{size[1]}")

    def check_icon(self, where, filename, icon_size):
        size = self.image(where, filename)
        if not size:
            return
        self.checked += 1
        icon_size = icon_size or 64
        if size[0] < icon_size or size[1] < icon_size:
            self.problem(where, f"{filename} is {size[0]}x{size[1]}, icon_size {icon_size}")

    def walk(self, node, where, parent=None):
        if isinstance(node, dict):
            if isinstance(node.get("icon"), str):
                self.check_icon(where + ".icon", node["icon"], node.get("icon_size"))
            if "filename" in node and isinstance(node["filename"], str) or "stripes" in node:
                self.check_layer(where, node, parent)
            for k, v in node.items():
                if k in ("filename", "stripes") or (k == "icon" and isinstance(v, str)):
                    continue
                if k == "icons" and isinstance(v, list):
                    for i, icon in enumerate(v):
                        if isinstance(icon, dict) and isinstance(icon.get("icon"), str):
                            self.check_icon(f"{where}.icons[{i}]", icon["icon"], icon.get("icon_size", node.get("icon_size")))
                    continue
                self.walk(v, f"{where}.{k}", node if "stripes" in node else None)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                self.walk(v, f"{where}[{i}]")
        elif isinstance(node, str):
            path = self.resolve(node)
            if path is not None and not path.exists():
                self.problem(where, f"missing file {node}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factorio", required=True, type=Path)
    ap.add_argument("mod_dirs", nargs="+", type=Path)
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        raw, mods = dump_data(args.factorio, [d.resolve() for d in args.mod_dirs], Path(tmp))
    checker = Checker(mods)
    for ptype, protos in raw.items():
        for name, proto in protos.items():
            checker.walk(proto, f"{ptype}.{name}")
    unused = []
    for name, d in mods.items():
        for png in sorted(d.rglob("*.png")):
            if png not in checker.files:
                unused.append(str(png.relative_to(d)))
    print(f"Checked {checker.checked} sprite and icon references in {len(checker.files)} files.")
    if unused:
        print("Images no prototype uses:\n  " + "\n  ".join(unused))
    if checker.problems:
        print(f"{len(checker.problems)} problem(s):")
        for p in checker.problems:
            print("  " + p)
        sys.exit(1)
    print("No problems.")


if __name__ == "__main__":
    main()
