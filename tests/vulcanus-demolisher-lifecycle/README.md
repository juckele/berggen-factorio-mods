# Vulcanus Demolisher Lifecycle tests

```sh
tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json
```

Takes about 2 minutes on Factorio 2.1. Runner docs: [`tools/headless`](../../tools/headless).

| Scenario | What it covers |
| --- | --- |
| `new-game` | Fixed seed (12345), mod present from the start. No setup without Vulcanus; setup when Vulcanus is created mid-game; killing a demolisher removes its territory and marks the land cleared; exploring it spawns no new demolisher; neighbouring territories retake all of it; the protected starting area stays empty. |
| `unprotected` | Same starting save as `established`, protection off: territory grows into the starting area. Then, on a live server over RCON, protection is turned on: nothing is evicted and further growth there is blocked. |
| `established` | Save that visited Vulcanus and built a small base before the mod was added. Setup on add, safe zone covers the base, nothing removed, base intact, expansion blocked. |
| `map-settings` | Same starting save as `established`, no interval override. The cooldown follows the map's min/max expansion cooldowns with vanilla's evolution scaling (checked at evolution 0, 0.5 and 1), the first attempt happens after it, and turning map expansion off stops attempts. |
| `nests` | Growth respects the distance gate and keeps one demolisher per territory. A big demolisher travels to its territory's centre, coils (body within 12 tiles of the site), lays 4 eggs, and returns to patrol. Eggs: too young doesn't hatch; an old egg with the parent alive takes one parent chunk; after a neighbour is killed, a free-space egg takes the parent chunk bordering the cleared land; a destroyed egg is removed; after the parent dies, its land is retaken except the nest chunk, which the last egg takes; the nest and its reservation then go away. Events are driven with `run_event`. |
| `nests-natural` | Every event on its own fast clock with low thresholds and a few kills: growth, nests and hatching all happen, every territory has exactly one demolisher, and egg and nest entities match the mod's state. |
| `nest-interrupt` | Damaging a demolisher while it coils ends the trip without a nest, and it doesn't retry straight away. |
| `vibration` | Vulcanus tracks vibration (Nauvis still tracks pollution); every drill and pump type emits it and an assembler doesn't; a fuelled burner drill shows up in the vibration statistics; pollution put into an all-lava chunk falls faster than in an all-rock chunk. |
| `vibration-investigate` | Vibration over the threshold in a territory chunk sends its demolisher to investigate; a quiet chunk doesn't; no repeat while investigating or within the cooldown, but again after it; the demolisher reaches the spot and destroys a player wall there. |
| `killed` | Save where 3 demolishers were killed before the mod was added. Also checks the vanilla behaviour the mod builds on (a territory stays after its last demolisher dies). On add, the dead territories are removed and marked cleared; at the default rate, neighbours retake all of it, including unexplored chunks, and exploring those afterwards spawns nothing new. |

## Layout

- `tests.json`: the scenarios.
- `mods/demolisher-lifecycle-test-setup/`: builds save state in `on_init` without the mod installed
  (create Vulcanus, build a base, kill demolishers), and serves what it did through the remote
  interface `demolisher-lifecycle-test-setup`.
- `mods/demolisher-lifecycle-test-checks/`: the checks, one handler per phase name. Reads the mod's
  state through its remote interface `vulcanus-demolisher-lifecycle`. Every phase turns growth,
  nesting and hatching off unless it sets its own `tuning`, so older checks aren't disturbed.

- `data/established-start.zip`, `data/killed-start.zip`: fixture saves from the setup steps of
  `established` (also used by `unprotected`, `map-settings` and the nest and vibration scenarios) and `killed` (Vulcanus generated, base built or demolishers killed, mod not installed), to
  skip ~14 s of generation each. They depend only on Factorio, the setup mod and the harness, and
  the runner rebuilds them when any of those change; commit the rebuilt files. `new-game` creates its
  save each run, since it starts before Vulcanus exists (~5 s).

A hand-played save can be added under `data/` (zips there are exempt from `.gitignore`) and used
with a scenario's `"save"` key.
