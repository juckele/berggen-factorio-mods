# Vulcanus Demolisher Lifecycle tests

```sh
tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json
```

Takes about 90 seconds on Factorio 2.1. Runner docs: [`tools/headless`](../../tools/headless).

| Scenario | What it covers |
| --- | --- |
| `new-game` | Fixed seed (12345), mod present from the start. No setup without Vulcanus; setup when Vulcanus is created mid-game; killing a demolisher removes its territory; that land doesn't respawn demolishers when explored; territory expands and retakes it; the protected starting area stays empty. |
| `unprotected` | Protection off: territory grows into the starting area. Then, on a live server over RCON, protection is turned on: nothing is evicted and further growth there is blocked. |
| `established` | Save that visited Vulcanus and built a small base before the mod was added. Setup on add, safe zone covers the base, nothing removed, base intact, expansion blocked. |
| `killed` | Save where 3 demolishers were killed before the mod was added. Also checks the vanilla behaviour the mod corrects (the territory outlives its demolisher). On add, the dead territories are removed and their unexplored chunks don't spawn new demolishers. |

## Layout

- `tests.json`: the scenarios.
- `mods/demolisher-lifecycle-test-setup/`: builds save state in `on_init` without the mod installed
  (create Vulcanus, build a base, kill demolishers), and serves what it did through the remote
  interface `demolisher-lifecycle-test-setup`.
- `mods/demolisher-lifecycle-test-checks/`: the checks, one handler per phase name. Reads the mod's
  state through its remote interface `vulcanus-demolisher-lifecycle`.

Saves are generated from the fixed seed on each run, so none are committed. A hand-played save can be
added as a fixture under `data/` (zips there are exempt from `.gitignore`) and used with a scenario's
`"save"` key.
