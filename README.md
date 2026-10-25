# berggen-factorio-mods

Factorio mods published by [berggen](https://mods.factorio.com/user/berggen).

| Mod | Status | Factorio | Directory | Portal |
| --- | --- | --- | --- | --- |
| Space Exploration Zone Combinator | Current | 1.1 | [`mods/zone-combinator`](mods/zone-combinator) | [zone-combinator](https://mods.factorio.com/mod/zone-combinator) |
| Space Exploration Annoying Pipes | Current | 1.1 | [`mods/se-annoying-pipes`](mods/se-annoying-pipes) | [se-annoying-pipes](https://mods.factorio.com/mod/se-annoying-pipes) |
| Emotiquality | Current | 2.0 | [`mods/emotiquality`](mods/emotiquality) | [emotiquality](https://mods.factorio.com/mod/emotiquality) |
| Anti-jam Stack Inserter | Current | 2.1 | [`mods/anti-jam-stack-inserter`](mods/anti-jam-stack-inserter) | [anti-jam-stack-inserter](https://mods.factorio.com/mod/anti-jam-stack-inserter) |
| Vulcanus Demolisher Lifecycle | Draft | 2.1 | [`mods/vulcanus-demolisher-lifecycle`](mods/vulcanus-demolisher-lifecycle) | not yet published |
| Cheap Train | Draft | 1.1 | [`mods/cheap-train`](mods/cheap-train) | not yet published |
| Clean Sushi | Deprecated | 1.1 | [`mods/clean-sushi`](mods/clean-sushi) | [clean-sushi](https://mods.factorio.com/mod/clean-sushi) |

## License

The code in this repo is MIT licensed (see [`LICENSE`](LICENSE)). Some mods include graphics
adapted from Factorio's own art, which stays © Wube Software Ltd. and is distributed under the
[Factorio Terms of Service](https://factorio.com/terms-of-service), not the MIT license. Those
files are listed in the mod's own license files, e.g.
[`mods/anti-jam-stack-inserter/LICENSE-graphics.md`](mods/anti-jam-stack-inserter/LICENSE-graphics.md).

## Releasing

Bump `version` in the mod's `info.json`, add a matching entry to its `changelog.txt`, commit,
then run [`tools/upload_mod.py`](tools/README.md) (with `--publish` for a mod's first release).
