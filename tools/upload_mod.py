#!/usr/bin/env python3
"""Package a mod from this repo and upload it to the Factorio mod portal, as a new release
of an existing mod or (with --publish) as a brand-new mod.

Usage:
    tools/upload_mod.py <mod> [--dry-run] [--yes] [--allow-dirty] [--dist DIR]
    tools/upload_mod.py <mod> --publish [--category C] [--license L] [...]

<mod> is either a directory name under mods/ (e.g. "clean-sushi") or a path to a
mod directory containing info.json.

The portal API key is read from the FACTORIO_API_KEY environment variable, or
from the file given with --api-key-file. Create a key at
https://factorio.com/profile with the "ModPortal: Upload Mods" usage (and
"ModPortal: Publish Mods" for --publish). The key is
deliberately not accepted as a command-line argument, so it does not end up in
shell history.

What it does, in order:
  1. Reads and validates info.json (name, version, title, author, factorio_version).
  2. Checks changelog.txt (if present) has an entry for the version being released.
  3. Refuses to continue if the mod directory has uncommitted git changes
     (override with --allow-dirty).
  4. Asks the mod portal for the mod's existing releases and refuses to upload
     a version that already exists or is not newer than the latest release.
     With --publish it instead refuses if the mod already exists.
  5. Builds dist/<name>_<version>.zip with a single <name>_<version>/ top folder.
  6. Asks for confirmation, then uploads via the portal's two-step API:
     init_upload -> finish_upload for a new release, or
     init_publish -> finish_upload for a new mod. Publishing also sends the mod's
     README.md as the portal description, the repo folder as the source URL, and a
     category and license (from --category/--license, or "package": {"category": ...,
     "license": ...} in info.json; the license defaults to MIT if the mod's LICENSE
     file is MIT).

--dry-run stops after step 5 (and skips the network entirely if combined with
--offline).

API reference: https://wiki.factorio.com/Mod_upload_API
               https://wiki.factorio.com/Mod_publish_API
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODS_DIR = REPO_ROOT / "mods"
DEFAULT_DIST = REPO_ROOT / "dist"

PORTAL = "https://mods.factorio.com"
INIT_UPLOAD_URL = f"{PORTAL}/api/v2/mods/releases/init_upload"
INIT_PUBLISH_URL = f"{PORTAL}/api/v2/mods/init_publish"
SOURCE_URL_BASE = "https://github.com/juckele/berggen-factorio-mods/tree/main/mods"

# https://wiki.factorio.com/Mod_details_API
CATEGORIES = ("no-category", "content", "overhaul", "tweaks", "utilities", "scenarios",
              "mod-packs", "localizations", "internal")
LICENSES = ("default_mit", "default_gnugplv3", "default_gnulgplv3", "default_mozilla2",
            "default_apache2", "default_unlicense")
USER_AGENT = "berggen-factorio-mods-upload/1.0"

REQUIRED_INFO_FIELDS = ("name", "version", "title", "author", "factorio_version")
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")

# Never packaged, regardless of info.json. Matched against each path component
# and against the full relative path.
ALWAYS_IGNORE = (
    ".git",
    ".github",
    ".gitignore",
    ".gitattributes",
    ".vscode",
    ".idea",
    ".DS_Store",
    "Thumbs.db",
    "__pycache__",
    "*.pyc",
    "*.zip",
)


class UploadError(Exception):
    pass


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def resolve_mod_dir(mod: str) -> Path:
    candidate = Path(mod)
    if not candidate.is_dir():
        candidate = MODS_DIR / mod
    if not (candidate / "info.json").is_file():
        raise UploadError(f"No info.json found for '{mod}' (looked in {candidate}).")
    return candidate.resolve()


def load_info(mod_dir: Path) -> dict:
    try:
        info = json.loads((mod_dir / "info.json").read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise UploadError(f"info.json is not valid JSON: {e}") from e

    missing = [f for f in REQUIRED_INFO_FIELDS if not info.get(f)]
    if missing:
        raise UploadError(f"info.json is missing required field(s): {', '.join(missing)}")
    if not VERSION_RE.match(str(info["version"])):
        raise UploadError(f"info.json version '{info['version']}' is not of the form X.Y.Z")
    if not re.match(r"^[A-Za-z0-9_-]+$", info["name"]):
        raise UploadError(f"info.json name '{info['name']}' contains characters the portal rejects")
    if info["name"] != mod_dir.name:
        print(f"warning: info.json name '{info['name']}' differs from directory name '{mod_dir.name}'")
    return info


def version_tuple(v: str) -> tuple[int, ...]:
    return tuple(int(p) for p in v.split("."))


def check_changelog(mod_dir: Path, version: str) -> None:
    changelog = mod_dir / "changelog.txt"
    if not changelog.is_file():
        print("warning: no changelog.txt; the portal's changelog tab will be empty for this release")
        return
    text = changelog.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    lines = text.split("\n")

    # Factorio's format: every version block starts with a line of exactly 99
    # dashes, followed by "Version: X.Y.Z".
    versions = []
    for i, line in enumerate(lines):
        m = re.match(r"^Version: (\S+)\s*$", line)
        if m:
            versions.append(m.group(1))
            if i == 0 or lines[i - 1] != "-" * 99:
                raise UploadError(
                    f"changelog.txt: 'Version: {m.group(1)}' (line {i + 1}) must be preceded by a line of 99 dashes"
                )
    if version not in versions:
        raise UploadError(f"changelog.txt has no 'Version: {version}' entry")
    for i, line in enumerate(lines):
        if "\t" in line:
            raise UploadError(f"changelog.txt line {i + 1} contains a tab; Factorio's changelog parser rejects tabs")


def check_git_clean(mod_dir: Path) -> None:
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain", "--", "."],
            cwd=mod_dir, capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("warning: could not run git status; skipping uncommitted-changes check")
        return
    if out.strip():
        raise UploadError(
            "mod directory has uncommitted changes (commit them, or pass --allow-dirty):\n" + out.rstrip()
        )


# ---------------------------------------------------------------------------
# Packaging
# ---------------------------------------------------------------------------

def is_ignored(rel: str, patterns: list[str]) -> bool:
    parts = rel.split("/")
    for pat in patterns:
        pat = pat.rstrip("/")
        if fnmatch.fnmatch(rel, pat):
            return True
        if any(fnmatch.fnmatch(part, pat) for part in parts):
            return True
    return False


def build_zip(mod_dir: Path, info: dict, dist: Path) -> Path:
    name, version = info["name"], info["version"]
    top = f"{name}_{version}"
    dist.mkdir(parents=True, exist_ok=True)
    zip_path = dist / f"{top}.zip"

    # info.json "package.ignore" is the convention used by the Factorio Mod
    # Tool Kit (fmtk); honouring it keeps existing mods packaging the same way.
    patterns = list(ALWAYS_IGNORE) + list(info.get("package", {}).get("ignore", []))

    files = []
    for path in sorted(mod_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(mod_dir).as_posix()
        if is_ignored(rel, patterns):
            continue
        files.append((path, rel))

    if not any(rel == "info.json" for _, rel in files):
        raise UploadError("info.json would be excluded from the zip by an ignore pattern")

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path, rel in files:
            zf.write(path, f"{top}/{rel}")

    print(f"Built {zip_path.relative_to(REPO_ROOT) if zip_path.is_relative_to(REPO_ROOT) else zip_path}"
          f" ({len(files)} files, {zip_path.stat().st_size / 1024:.1f} KiB):")
    for _, rel in files:
        print(f"    {rel}")
    return zip_path


# ---------------------------------------------------------------------------
# Portal
# ---------------------------------------------------------------------------

def _request(req: urllib.request.Request) -> dict:
    req.add_header("User-Agent", USER_AGENT)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            data = json.loads(body)
        except ValueError:
            raise UploadError(f"HTTP {e.code} from {req.full_url}: {body[:500]!r}") from e
        data.setdefault("_status", e.code)
        return data
    except urllib.error.URLError as e:
        raise UploadError(f"could not reach {req.full_url}: {e.reason}") from e
    try:
        return json.loads(body)
    except ValueError as e:
        raise UploadError(f"non-JSON response from {req.full_url}: {body[:500]!r}") from e


def check_portal_versions(name: str, version: str, publish: bool) -> None:
    data = _request(urllib.request.Request(f"{PORTAL}/api/mods/{name}"))
    if data.get("_status") == 404 or "releases" not in data:
        if publish:
            print(f"Portal: '{name}' is not on the portal yet; publishing it as a new mod")
            return
        raise UploadError(
            f"'{name}' was not found on the mod portal. To publish it as a new mod, pass --publish."
        )
    if publish:
        raise UploadError(f"'{name}' already exists on the portal; drop --publish to upload a new release")
    existing = [r["version"] for r in data["releases"]]
    if version in existing:
        raise UploadError(f"{name} {version} already exists on the portal; bump the version in info.json")
    if existing:
        latest = max(existing, key=version_tuple)
        if version_tuple(version) <= version_tuple(latest):
            raise UploadError(f"{name} {version} is not newer than the latest portal release {latest}")
        print(f"Portal: latest release of {name} is {latest}; uploading {version}")


def read_api_key(api_key_file: str | None) -> str:
    if api_key_file:
        key = Path(api_key_file).expanduser().read_text(encoding="utf-8").strip()
    else:
        key = os.environ.get("FACTORIO_API_KEY", "").strip()
    if not key:
        raise UploadError("no API key: set FACTORIO_API_KEY or pass --api-key-file")
    return key


def publish_metadata(mod_dir: Path, info: dict, category: str | None, license_: str | None) -> dict[str, str]:
    package = info.get("package", {})
    category = category or package.get("category")
    license_ = license_ or package.get("license")
    if not license_:
        for candidate in ("LICENSE.md", "LICENSE", "LICENSE.txt"):
            path = mod_dir / candidate
            if path.is_file() and path.read_text(encoding="utf-8").lstrip().startswith("MIT License"):
                license_ = "default_mit"
                break
    if not category:
        raise UploadError(f"--publish needs a category (--category, or package.category in info.json): {', '.join(CATEGORIES)}")
    if category not in CATEGORIES:
        raise UploadError(f"unknown category '{category}'; one of: {', '.join(CATEGORIES)}")
    if not license_:
        raise UploadError(f"--publish needs a license (--license, or package.license in info.json): {', '.join(LICENSES)}, or custom_<id>")
    if license_ not in LICENSES and not re.match(r"^custom_[0-9a-f]+$", license_):
        raise UploadError(f"unknown license '{license_}'; one of: {', '.join(LICENSES)}, or custom_<id>")
    fields = {"category": category, "license": license_, "source_url": f"{SOURCE_URL_BASE}/{mod_dir.name}"}
    readme = mod_dir / "README.md"
    if readme.is_file():
        fields["description"] = readme.read_text(encoding="utf-8")
    else:
        print("warning: no README.md; the portal description will be empty")
    return fields


def encode_multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    out = bytearray()
    for k, v in fields.items():
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    for k, path in files.items():
        out += (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{path.name}\"\r\n"
            "Content-Type: application/zip\r\n\r\n"
        ).encode()
        out += path.read_bytes() + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


def portal_error(step: str, data: dict) -> UploadError:
    return UploadError(f"{step} failed: {data.get('error', 'unknown error')}: {data.get('message', data)}")


def upload(name: str, zip_path: Path, api_key: str, publish_fields: dict[str, str] | None = None) -> None:
    """New release (publish_fields None) or new mod (publish_fields = description etc.)."""
    init_url, step = (INIT_PUBLISH_URL, "init_publish") if publish_fields is not None else (INIT_UPLOAD_URL, "init_upload")
    body, ctype = encode_multipart({"mod": name}, {})
    req = urllib.request.Request(init_url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {api_key}")
    req.add_header("Content-Type", ctype)
    data = _request(req)
    upload_url = data.get("upload_url")
    if not upload_url:
        raise portal_error(step, data)

    body, ctype = encode_multipart(publish_fields or {}, {"file": zip_path})
    req = urllib.request.Request(upload_url, data=body, method="POST")
    req.add_header("Content-Type", ctype)
    data = _request(req)
    if not data.get("success"):
        raise portal_error("finish_upload", data)


# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("mod", help="mod directory name under mods/, or a path to a mod directory")
    p.add_argument("--dry-run", action="store_true", help="validate and build the zip, but do not upload")
    p.add_argument("--offline", action="store_true", help="with --dry-run: skip the portal version check too")
    p.add_argument("--yes", "-y", action="store_true", help="do not ask for confirmation before uploading")
    p.add_argument("--allow-dirty", action="store_true", help="allow uncommitted changes in the mod directory")
    p.add_argument("--dist", default=str(DEFAULT_DIST), help="where to write the zip (default: dist/)")
    p.add_argument("--api-key-file", help="read the API key from this file instead of FACTORIO_API_KEY")
    p.add_argument("--publish", action="store_true", help="publish a mod that isn't on the portal yet")
    p.add_argument("--category", help=f"with --publish: portal category ({', '.join(CATEGORIES)})")
    p.add_argument("--license", dest="license_", help="with --publish: portal license (default_mit, ..., custom_<id>)")
    args = p.parse_args(argv)

    if args.offline and not args.dry_run:
        p.error("--offline only makes sense with --dry-run")
    if (args.category or args.license_) and not args.publish:
        p.error("--category and --license only apply with --publish")

    try:
        mod_dir = resolve_mod_dir(args.mod)
        info = load_info(mod_dir)
        name, version = info["name"], info["version"]
        print(f"{info['title']} ({name}) {version} for Factorio {info['factorio_version']}")

        check_changelog(mod_dir, version)
        if not args.allow_dirty:
            check_git_clean(mod_dir)
        publish_fields = publish_metadata(mod_dir, info, args.category, args.license_) if args.publish else None
        api_key = None if args.dry_run else read_api_key(args.api_key_file)
        if not args.offline:
            check_portal_versions(name, version, args.publish)

        zip_path = build_zip(mod_dir, info, Path(args.dist))
        if publish_fields is not None:
            print("Publish metadata:")
            for k, v in publish_fields.items():
                shown = f"{len(v)} characters from README.md" if k == "description" else v
                print(f"    {k}: {shown}")

        if args.dry_run:
            print("Dry run: not uploading.")
            return 0

        action = "Publish new mod" if args.publish else "Upload"
        if not args.yes:
            answer = input(f"{action} {name} {version} to the Factorio mod portal? [y/N] ").strip().lower()
            if answer not in ("y", "yes"):
                print("Aborted.")
                return 1

        upload(name, zip_path, api_key, publish_fields)
        print(f"{'Published' if args.publish else 'Uploaded'} {name} {version}: {PORTAL}/mod/{name}")
        print(f"Suggested: git tag {name}/{version} && git push origin {name}/{version}")
        return 0
    except UploadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
