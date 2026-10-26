# headless

Runs mod test scenarios on a headless Factorio, and inspects a save's mod state over RCON.
Python 3.9+, standard library only. Mod-specific tests and test data live in `tests/<mod>/`.

```sh
# Run every scenario in a spec (exit code 1 if any fail)
tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json

# One scenario, listing passing checks and info lines, keeping the work dir
tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json \
    --scenario killed -v --work /tmp/vdl

# Load a save on a server and run Lua inside a mod's own Lua state
tools/headless/headless.py inspect tests/vulcanus-demolisher-lifecycle/tests.json \
    --save my-save.zip --mods vulcanus-demolisher-lifecycle \
    --context vulcanus-demolisher-lifecycle --lua 'rcon.print(serpent.block(storage))'
```

Factorio is found through `FACTORIO_BIN` (the executable), or under `FACTORIO_HOME`, `~/factorio`
or `/home/claude/factorio` as `<version>/factorio/bin/x64/factorio` matching the spec's
`factorio` prefix. The headless build is enough; a full install works too. Every run gets its own
config and write-data directory, so it never touches your normal Factorio data. `inspect` works on
a copy of the save.

## How a test checks a mod

A test-only mod (in `tests/<mod>/mods/`) depends on the mod under test and checks it from inside the
game. It reads the mod's state through the mod's remote interface (one mod can't read another's
`storage`), and reports with the harness library:

```lua
local H = require("__headless-test-harness__/harness")
H.install()
H.at(60, function()
  local state = remote.call("my-mod", "get_state")
  H.equal("thing-counted", state.count, 3)
  H.done()
end)
```

Results are lines on stdout (`TEST PASS name`, `TEST FAIL name :: detail`, `TEST INFO`, `TEST DONE`)
that the runner collects. A step fails on any FAIL, on a Lua error or non-zero exit, and, with
`expect_done`, if the test mod never called `H.done()`. See `headless-test-harness/harness.lua` for
the full API.

For poking at state by hand, `inspect` (or a `server` step) runs `/sc __<mod>__ <lua>` over RCON,
which executes inside that mod's Lua state and can read its `storage` directly.

## Spec format

```jsonc
{
  "factorio": "2.1",                         // version prefix to look for
  "builtin_mods": ["base", "space-age", ...],  // optional; default: all five 2.1 built-in mods
  "mod_paths": { "my-mod": "../../mods/my-mod", "my-mod-checks": "mods/my-mod-checks" },
  "scenarios": [{
    "name": "new-game",
    "save": "data/some-save.zip",            // optional fixture to start from instead of a create step
    "settings": { "my-setting": 5 },          // optional setting overrides (see below)
    "params": { "anything": true },           // optional; available to test mods as H.params
    "steps": [
      { "phase": "create", "create": { "seed": 12345 }, "mods": ["my-mod", "my-mod-checks"] },
      { "phase": "setup", "fixture": "my-start", "create": { "seed": 12345 }, "mods": ["my-setup"] },
      { "phase": "run", "benchmark": 600, "mods": [...], "expect_done": true },
      { "phase": "live", "mods": [...], "expect_done": true, "server": { "actions": [
          { "wait": 300 },
          { "lua": "settings.global['my-setting'] = {value = 1}", "context": "my-mod" },
          { "name": "check", "lua": "rcon.print(game.tick)", "expect": "^\\d+" }
      ] } }
    ]
  }]
}
```

Step actions:

- `create`: `--create` a new map (`seed`, optional `map_gen_settings` / `map_settings` files relative
  to the spec). Only `on_init` runs; this is where setup mods build save state.
  Add `"fixture": "<name>"` to cache the result as `data/<name>.zip` next to the spec, with
  `data/<name>.json` holding a hash of everything the save depends on (Factorio version, create
  options, params, settings, and the files of the step's mods and the harness) plus the step's
  `TEST` lines, which are replayed when the fixture is reused. A stale or missing fixture is rebuilt
  automatically, and the runner says to commit it; `--refresh-fixtures` forces a rebuild. Worth it
  for slow setup (generating a planet, ~10 s); not for a plain `--create` (~5 s, about the same as
  loading a save). Fixture steps should not include the mod under test, so mod changes don't
  invalidate them, and they ignore scenario-level `settings` (only the step's own apply), so
  scenarios with different settings can share one fixture by repeating the same step.
- `benchmark`: `--benchmark` the scenario's save for N ticks. Fast, but **changes are not saved**:
  every later step starts again from the last saved state.
  - Add `"perf": {"avg_ms": 1, "max_ms": 16, "p99_ms": 4, "skip": 0, "skip_end": 0, "column": "scriptUpdate"}`
    to measure per-tick time from `--benchmark-verbose all`. All keys are optional; with no limits
    the step just reports.
  - `scriptUpdate` is all mods' script time, the test mod's included. Use `skip` and `skip_end` to
    leave out ticks where the test mod does expensive checks.
  - The runner prints the average, p99, maximum and the five slowest ticks, and fails any limit that
    is exceeded.
  - Factorio 2.1.23 crashes if `--benchmark-verbose` is given a column list, so the runner always
    passes `all`.
- `server`: start a server on the save, run RCON actions (`wait` N ticks, `lua` with an optional
  mod `context` and `expect` regex), then save (`"save": false` to skip). Runs in real time (60
  ticks per second), so keep waits short. Use it when a step must persist state or change settings.

Each step sets the phase name (`H.phase`) so one test mod can hold the checks for every step.
The harness and a generated `headless-test-config` mod are added to every step automatically.

Setting overrides change the setting's default. A runtime-global setting's value is stored in the
save when its mod is first added, so the override applies at the step that adds the mod; to change
it later, write it over RCON with `context` set to the owning mod (other mods aren't allowed to).

## Engine notes

- An event raised during `on_init` (seen with `LuaSegmentedUnit.die()` and `on_segmented_unit_died`)
  did not reach the same mod's handler. Don't rely on events from setup code in `on_init`.
- Mods load alphabetically after dependencies, so `on_init` order between unrelated mods follows
  their names.
- The server rejects `--rcon-port` together with `--rcon-bind`, and needs every key of
  `data/server-settings.example.json`; the runner handles both.
