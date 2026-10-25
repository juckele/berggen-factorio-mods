# Vulcanus Demolisher Lifecycle tests

```sh
tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json
```

Takes about 65 seconds on Factorio 2.1 (100 seconds when the fixtures need rebuilding). Runner docs: [`tools/headless`](../../tools/headless).

| Scenario | What it covers |
| --- | --- |
| `new-game` | Fixed seed (12345), mod present from the start. No setup without Vulcanus; setup when Vulcanus is created mid-game; killing a demolisher removes its territory and marks the land cleared; exploring it spawns no new demolisher; neighbouring territories retake all of it; the protected starting area stays empty. |
| `unprotected` | Same starting save as `established`, protection off: territory grows into the starting area. Then, on a live server over RCON, protection is turned on: nothing is evicted and further growth there is blocked. |
| `established` | Save that visited Vulcanus and built a small base before the mod was added. Setup on add, safe zone covers the base, nothing removed, base intact, expansion blocked. |
| `map-settings` | Same starting save as `established`, no interval override. The cooldown follows the map's min/max expansion cooldowns with vanilla's evolution scaling (checked at evolution 0, 0.5 and 1), the first attempt happens after it, and turning map expansion off stops attempts. |
| `killed` | Save where 3 demolishers were killed before the mod was added. Also checks the vanilla behaviour the mod builds on (a territory stays after its last demolisher dies). On add, the dead territories are removed and marked cleared; at the default rate, neighbours retake all of it, including unexplored chunks, and exploring those afterwards spawns nothing new. |

## Layout

- `tests.json`: the scenarios.
- `mods/demolisher-lifecycle-test-setup/`: builds save state in `on_init` without the mod installed
  (create Vulcanus, build a base, kill demolishers), and serves what it did through the remote
  interface `demolisher-lifecycle-test-setup`.
- `mods/demolisher-lifecycle-test-checks/`: the checks, one handler per phase name. Reads the mod's
  state through its remote interface `vulcanus-demolisher-lifecycle`.

- `data/established-start.zip`, `data/killed-start.zip`: fixture saves from the setup steps of
  `established` (also used by `unprotected` and `map-settings`) and `killed` (Vulcanus generated, base built or demolishers killed, mod not installed), to
  skip ~14 s of generation each. They depend only on Factorio, the setup mod and the harness, and
  the runner rebuilds them when any of those change; commit the rebuilt files. `new-game` creates its
  save each run, since it starts before Vulcanus exists (~5 s).

A hand-played save can be added under `data/` (zips there are exempt from `.gitignore`) and used
with a scenario's `"save"` key.
