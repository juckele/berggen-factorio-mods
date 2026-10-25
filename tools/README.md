# tools

- [`upload_mod.py`](#upload_modpy): package and upload a mod to the mod portal.
- [`headless/`](headless/README.md): run mod test scenarios on headless Factorio; tests live in `tests/<mod>/`.

## upload_mod.py

Packages a mod from `mods/` and uploads it to the Factorio mod portal as a new release.
Python 3.9+, standard library only.

```sh
# Validate and build dist/<name>_<version>.zip without uploading
tools/upload_mod.py clean-sushi --dry-run

# Same, without touching the network at all
tools/upload_mod.py clean-sushi --dry-run --offline

# Upload (asks for confirmation first)
FACTORIO_API_KEY=... tools/upload_mod.py clean-sushi

# Publish a mod that isn't on the portal yet (asks for confirmation first)
FACTORIO_API_KEY=... tools/upload_mod.py anti-jam-stack-inserter --publish
```

Before uploading, the script:

- validates `info.json` (name, version in `X.Y.Z` form, title, author, factorio_version)
- requires a `Version: X.Y.Z` entry in `changelog.txt` for the release, in Factorio's format
- refuses if the mod directory has uncommitted changes (`--allow-dirty` to override)
- refuses if the version already exists on the portal or isn't newer than the latest release
  (with `--publish`: refuses if the mod already exists)

The zip contains a single `<name>_<version>/` folder. Version-control and editor files are
always left out, as are `.exe`, `.bat`, `.ps1`, `.sh` and `.py` files (the portal rejects
uploads containing executables), and anything matched by `package.ignore` in the mod's `info.json`
(the same convention the Factorio Mod Tool Kit uses), e.g.:

```json
"package": { "ignore": ["make-mask.py", "*.xcf"] }
```

### Publishing a new mod

`--publish` uses the portal's publish API instead of the release upload API. Along with the
zip it sends:

- `description`: the mod's `README.md` (Markdown)
- `source_url`: the mod's folder in this repo on GitHub (`main` branch)
- `category` and `license`: from `--category`/`--license`, or from info.json, e.g.
  `"package": { "category": "content", "license": "default_mit" }`. The license defaults to
  `default_mit` when the mod's LICENSE file is MIT. Allowed values are listed on the
  [Mod details API](https://wiki.factorio.com/Mod_details_API) page.

### API key

Create a key at <https://factorio.com/profile> with the **ModPortal: Upload Mods** usage (and
**ModPortal: Publish Mods** for `--publish`), then either export it as `FACTORIO_API_KEY` or put
it in a file and pass `--api-key-file PATH`. The key is intentionally not accepted as a
command-line argument.
