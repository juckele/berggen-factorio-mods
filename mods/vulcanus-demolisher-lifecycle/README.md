# Vulcanus Demolisher Lifecycle

Allows demolishers to grow and spawn young.

This README tracks remaining work while the mod is in development. Once the work below is done it
goes back to being player-facing text for the mod portal.

## Current behaviour (0.2.0, Factorio 2.1)

- **Setup.** The mod sets itself up whenever Vulcanus exists: in a new game, when Vulcanus is first
  created, or when the mod is added to a save that has already been to Vulcanus.
- **Dead territories become cleared land.** In vanilla a territory stays after its last demolisher
  dies. The mod removes it a tick after its last demolisher dies, and on setup it removes
  territories whose demolishers were already killed. Their chunks are set to "no territory" rather
  than destroyed (`LuaTerritory.destroy()` lets the map generator put a new territory, with a new
  demolisher, on any of those chunks that get explored later), and marked as cleared.
- **Starting area.** The territory-free starting area is recorded per Vulcanus surface, whether or not
  protection is on. A chunk counts if it is in or next to the map generator's starting-area disc
  (`demolisher_starting_area`) and has no territory once generated.
- **Four event clocks.** Expansion, growth, nesting and hatching each run on a global clock per
  surface. With the override at 0, each cooldown uses vanilla's biter formula on the map's enemy
  expansion settings, `lerp(max_cooldown, min_cooldown, -e² + 2e)` with `e` the enemy evolution on
  Vulcanus, times a per-event scale (expansion 1/20, growth 1/4, nest 1/2, hatch 1/10; see
  `tuning.lua`). Evolution rises with time and vibration, which is the global pollution effect.
  Expansion at 1/20 is 3 min at no evolution to 30 s at full evolution on default map settings.
- **Enemy expansion required.** The mod does nothing with enemy expansion turned off in the map
  settings, and says so in chat once each time it finds it off.
- **No-enemies mode.** Vulcanus inherits no-enemies mode from the new-game settings, which leaves
  its territories without demolishers. The mod is then inert: it doesn't clear those territories
  or run any events, and says in chat that it is effectively disabled. If no-enemies mode is
  turned off later, it clears the empty territories and starts its clocks (`no-enemies` test).
- **Expanding into cleared land.** Every expansion, one cleared chunk next to a territory with a living
  demolisher joins that territory, explored or not. This is the mod's main loop: land the player
  clears doesn't stay clear. Land taken this way never spawns extra demolishers.
- **Other expansion.** When no cleared chunk borders a living territory, a territory may instead
  grow into a neighbouring explored chunk without territory. In practice that's only the starting
  area, so it only happens with protection off.
- **Holes fill first.** Every candidate chunk, from every territory, is weighted by
  `exp(-3 · d / r)`: d is its distance from the gaining territory's centre, r that territory's
  mean radius. Holes and concave edges fill long before a territory pushes outward
  (`expansion-weighting` test: the hole won 29 of 30).
- **Expanding over bases.** Territory can grow over player buildings. Vanilla demolishers don't
  react to that (only to buildings placed in their territory, and they sleep with no player near),
  so when a territory gains a chunk with player buildings, the mod sends its demolisher there on
  each vibration check while it is free, until nothing of the player's is left (at most 5 trips per
  chunk). This includes buildings that make no vibration (`wreck` test: walls, chest, pole and
  solar panel destroyed after one trip).
- **Growth.** Each growth event looks at a few random demolishers; one may grow a size (small →
  medium → big), with a sigmoid chance on its territory size (50% at 120 chunks for medium, 180
  for big). It can't grow more than one size above what the map generator places at its
  territory's centre. Growing replaces the demolisher with the bigger one in the same body.
- **Nesting.** Each nest event may send one max-size demolisher with a territory of at least 150
  chunks (at most 2 trips at once, one nest per demolisher) on a nesting trip:
  1. *Travel:* its AI is put in the `investigating` state toward the nest site, the explored chunk
     nearest its territory's centre. The engine steers it there.
  2. *Coil:* within 24 tiles, the script takes over and moves the body along an inward spiral
     (10 to 4 tiles from the site) at crawling speed, keeping the engine's 1-tile node spacing.
  3. *Build:* it holds still for 10 s, then a nest marker and 1–3 eggs appear inside the coil.
  4. *Return:* it goes back to patrolling from the nearest waypoint and uncoils naturally.
  Attacks while travelling, or damage while coiling or building, end the trip without a nest and
  the demolisher waits 5 minutes before trying again.
- **Eggs and hatching.** Each hatch event picks one egg at least 2 minutes old, weighted by its
  situation. The hatchling is a small demolisher with a one-chunk territory, which then grows like
  any other:
  - parent dead (weight 10): it takes the nest chunk, which expansion leaves alone while the nest
    has eggs;
  - cleared land next to the parent's explored land (weight 3): it takes the parent chunk
    bordering it, nearest the nest, with that chunk's patrol route, and finds its own way there;
  - otherwise, once 30 minutes old (weight 1): it takes the parent's edge chunk nearest the nest.
  In both cases the chunk taken from a living parent must leave the parent's territory in one piece,
  so a chunk on a one-chunk-wide neck is skipped for the next nearest (`hatch-no-split` test).
  Expansion keeps territories in one piece too: a chunk only goes to a territory that owns a chunk
  beside it.
  A hatch inside a force's radar coverage raises the game's expansion alert (the one for new
  biter bases) on the hatchling. Each hatch shrinks the parent by one chunk, so repeated hatching eventually takes a parent under
  the nesting minimum. Destroyed eggs are gone for good; the nest marker disappears with its last
  egg. Eggs show as red dots on the map; the nest marker doesn't show. Nest and egg graphics are
  placeholders (Vulcanus hot rocks); real art comes later.
- **Vibration.** Vulcanus gets its own pollution layer, *vibration* (vanilla Vulcanus has no pollutant).
  Mining drills, pumps and offshore pumps emit it while working (burner drill 6/min, electric drill
  10, big drill 40, pump 3, offshore pump 8; other mods' drills and pumps fall back by type). Lava
  absorbs it fastest (0.0001 per tile per second, the top vanilla rate) and volcanic ground
  medium-high (0.00002; grass absorbs pollution at 0.000018). Vibration counts toward evolution,
  which shortens every demolisher event clock. Efficiency modules reduce it like any pollution.
- **Vibration draws investigation.** Every 5 s the mod finds each territory's loudest explored
  chunk. At 20 vibration or more, the territory's demolisher investigates it, unless it is
  fighting, already investigating, nesting, or was sent in the last minute. On arrival the vanilla
  AI attacks player buildings it finds there (`vibration-investigate` test).
- **Settings** (all map settings):
  - *Demolishers cannot expand into the starting area* (on). Turning it on later stops further
    growth without evicting territory that already grew there.
  - *Expansion interval override* (10 ticks, very fast so testers can watch). Replaces every event
    clock's cooldown when above 0; 0 uses the map settings. Release will default to 0.
  - *Debug logging* (off): writes decisions to `factorio-current.log`.
- **Remote interface** `vulcanus-demolisher-lifecycle`. Reads: `get_state()`, `get_trips()`,
  `get_nests()`, `get_safe_chunks()`, `is_safe_chunk(x, y)`, `get_cleared_chunks()`,
  `is_cleared_chunk(x, y)`. For testing: `set_tuning{key = value}` overrides `tuning.lua` values,
  `run_event(name)` runs one event now, and `clear_chunks(chunks)` clears chunks as a kill would. The headless tests use it, and other mods can too.

- **Lure turret.** A very slow, very long-range turret (behind metallurgic science) that hits
  demolishers for light damage so they come for it; see roadmap section 6.

## Testing this build

- **Install:** copy `vulcanus-demolisher-lifecycle_0.2.0.zip` into your Factorio `mods` folder (Factorio
  2.1 with Space Age). Start a new game or add it to a save; it says nothing in chat unless enemy
  expansion is off or Vulcanus is in no-enemies mode.
- **Speed:** *Expansion interval override* (map settings) is 10 ticks, so expansion, growth, nesting
  and hatching all run about every 10 ticks. Set it to 0 for real map-settings timing, or e.g. 600
  for one event of each kind every 10 s.
- **Console** (`/c`, disables achievements), to inspect or speed things up:
  - `remote.call("vulcanus-demolisher-lifecycle", "get_state")` with `game.print(serpent.line(...))`
    shows counters, clocks and nest/egg counts; `get_nests()` and `get_trips()` list them.
  - `remote.call("vulcanus-demolisher-lifecycle", "set_tuning", {nest_min_chunks = 20, egg_min_age = 600})`
    changes any value in `tuning.lua` for this save.
  - `remote.call("vulcanus-demolisher-lifecycle", "run_event", "nest")` runs one event now
    (`expansion`, `growth`, `nest`, `hatch`, `vibration`).
- **Map:** the *Vibration* overlay shows vibration; eggs are red dots.
- **Debug logging** (map setting) writes the mod's decisions to `factorio-current.log`.

Tests: [`tests/vulcanus-demolisher-lifecycle`](../../tests/vulcanus-demolisher-lifecycle).

## Performance

Targets: a few hundred microseconds per tick on average. No single tick during play should come
near 16 ms. Set-up when the mod is added or Vulcanus is created may take a slow tick or two. The
`perf-*` test scenarios measure this on a radius-24 map with 35 territories:

| Scenario | Avg per tick | Worst tick |
| --- | --- | --- |
| `perf-steady`: map-settings timing, evolution 0.5, 5 min | 0.14 ms | 4–10 ms (varies run to run) |
| `perf-stress`: every clock every 10 ticks, low thresholds | 0.4 ms | 8–12 ms, counting the tick where the test kills 4 demolishers |

How it stays bounded:
- **Territory index (`index.lua`).** The mod keeps its own map of which territory owns each chunk,
  plus each territory's chunks, size, centre and demolisher. It updates the index on its own changes
  and on the map generator's creation events, so play never needs `get_territories` or
  `get_chunks`. It assumes no other mod edits Vulcanus territories (see Compatibility).
- **Frontiers.** Cleared chunks and unclaimed starting-area chunks that border a living territory
  are kept as sets. Expansion weighs a random sample of up to 48 entries rather than every cleared
  chunk.
- **Spread work.**
  - The vibration check sweeps the explored chunks a slice per tick, one full pass every 5 s.
  - A dead territory is cleared 48 chunks per tick.
  - At most one event runs per tick; the others wait a tick.
  - A travelling nester is checked every 10 ticks.
  - Set-up when Vulcanus is created during play runs over about 12 ticks.
- **Numeric chunk keys.** Keys are numbers, not `"x,y"` strings. String keys were the largest cost
  in the first version.
- What remains per-tick is a demolisher coiling while it nests, at about 0.4 ms each. At most 2
  demolishers nest at once.

Profiling: `set_tuning{profile = true}` logs `PROFILE <section> Duration: … tick …` lines to
`factorio-current.log`; the `perf-*` scenarios take `params.profile`.

## Compatibility

- **Mods that edit Vulcanus territories.** The mod keeps its own index of territories and
  assumes only it and the map generator change them, for performance. A mod that creates, resizes or
  removes Vulcanus territories with `set_territory_for_chunks`, `create_territory` or
  `LuaTerritory.destroy` desynchronises that index until the next mod or game update rebuilds it.

- **Mods that remove demolishers.** A mod that removes a demolisher with
  `LuaSegmentedUnit.destroy()` without raising `script_raised_destroy_segmented_unit` leaves its
  territory empty without this mod hearing about it. That territory isn't cleared or expanded into until
  the next time the mod sets up (a mod change or game update), and any nest it had keeps waiting
  for its parent. This mod won't work around it; such mods should call `destroy{raise_destroy = true}`
  or kill the unit with `die()`.

## Remaining work

### 1. Setup on new and established games
- [x] New game, Vulcanus created later (`new-game` test).
- [x] Added to a save that has been to Vulcanus and built there (`established` test).
- [x] Added to a save where demolishers were killed (`killed` test): their land is marked cleared
      and expanded into.
- [ ] Saves that ran the first 0.2.0 build: land it cleared wasn't marked, so it is never expanded into.
      Only matters for testers' saves; could be fixed by marking territory-free explored chunks
      outside the safe zone as cleared.
- [x] Vulcanus created by another mod's `on_init`, which doesn't raise `on_surface_created` for us:
      a once-a-second check picks it up. Not covered by a test yet (in the tests, the setup mod's
      `on_init` runs first).
- [x] No-enemies mode: inert with a chat warning, picks up if turned off (`no-enemies` test).
- [ ] Test against a hand-played save (late game on Vulcanus, many kills, odd starting-area slider).
- [x] Killing a demolisher whose territory is entirely unexplored clears it (found by the `nests`
      test; dead territories were looked up by an explored chunk before).
- [x] Other mods destroying demolishers without raising `script_raised_destroy_segmented_unit`:
      not handled, by decision; noted under Compatibility.
- [ ] Multiplayer check (a server run with two clients) before release.

### 2. Game balance
- [x] Expansion follows the map's enemy expansion settings (enabled, min/max cooldown) with
      vanilla's evolution scaling (`map-settings` test).
- [ ] Tune `tuning.lua`: event scales, growth midpoints and width, nest minimum size, egg ages and
      hatch weights.
- [ ] Switch the override's default to 0 for release.
- [ ] Measure how long a cleared area stays clear at the chosen rate, on a real base.
- [x] Performance: see the Performance section and the `perf-*` scenarios.
- [ ] Performance on a hand-played late-game Vulcanus save (thousands of explored chunks).

### 3. Spawn logic that feels coherent
Decided:
- One demolisher per territory, always. A new demolisher means a new territory, and a territory
  without a demolisher becomes cleared land. Explored land is finite, so the population is bounded
  without extra limits.
- Expansion is global per surface, like biter and pentapod expansion: the rate doesn't scale with
  explored area or territory count.

- Four kinds of event, each on its own global clock scaled by map settings × pollution: chunk
  expansion, growth, nest creation, egg hatching.

Built:
- [x] Growth by territory size, gated by distance (`nests`, `nests-natural` tests).
- [x] Nests: max-size demolishers travel to their territory's centre, coil, lay 1–3 eggs and return
      to patrol (`nests`, `nest-interrupt` tests).
- [x] Hatching weighted dead parent > free space > old, one chunk per hatchling (`nests` test).
- [x] Hatching never splits the living parent's territory (`hatch-no-split` test).

Open:
- [x] Hatchling arrival: it owns its chunk and patrol route at once and finds its own way there.
- [ ] Free space in unexplored land can't be used: a new territory needs an explored chunk, so the
      egg waits for the old-egg rule instead.
- [ ] Real graphics for the nest and eggs, and hatching effects and sound.
- [x] Eggs show as red dots on the map.
- [ ] Other ideas from the brainstorm, not planned: bifurcation, births in gaps between two
      territories, budding, fragments surviving a sloppy kill, spawning from volcanoes.

### 4. Territory expansion as a real threat
- [x] Living territories expand into cleared land, explored or not.
- [x] Territory can grow into bases; the demolisher is sent to wreck what it covers (`wreck` test).
- [x] Expansion prefers chunks near the territory's centre: holes and curves fill first
      (`expansion-weighting` test).
- Decided: no alerts for territory growing or demolishers moving. Hatches in radar coverage use
  the game's expansion alert.
- [ ] Check the hatch alert in game (headless can't chart without players, so the test only checks
      that a hatch outside radar coverage raises none).

### 5. The original safe zone stays safe
- [x] Recorded on setup even with protection off; protection on by default; turning it on doesn't
      evict (`unprotected` test).
- [ ] Show the safe zone on the map (optional overlay or chart tags).
- [ ] Test other seeds and starting-area slider values (the disc moves with the slider).
- [x] The player can't extend the safe zone: it is only the original starting area. Land they
      clear and build on stays open to expansion.

### 6. Lure turret: automated demolisher handling
Decided: it lures demolishers by hurting them a little, so they come for the turret and into the
player's defences. It's a turret, so it can be automated.

Starting version:
- [x] *Lure turret* (`demolisher-lure-turret`): an ammo turret kitbashed from the gun turret
      (graphics and icons unchanged until real art exists), firing a cannon-shell
      projectile with the tank cannon's sound. Range 96 (past a demolisher's vision), one shot
      every 15 s, 15 s for a full turn, 20 physical damage per hit (10 after a head's resistance).
- [x] Built with no priority list, like vanilla turrets. To lure only some sizes, add the size's
      head (small/medium/big demolisher, all in the picker's enemies group) to its priority targets
      and set it to ignore other targets; the head entry covers the whole demolisher
      (`lure-turret-filter` test). The segments are hidden prototypes and aren't needed.
- [x] *Lure shell* ammo: 2 iron plate + 1 calcite → 2 shells.
- [x] Recipe: 1 gun turret, 10 tungsten plate, 10 steel plate. Technology *Lure turret* after
      metallurgic science pack (automation, logistic, chemical, space, metallurgic; 300 × 30 s).
- [x] `lure-turret` test: a demolisher 128 tiles away is hit, goes `enraged_at_target` on the
      turret, and closes to 9 tiles in about 40 s.

Open:
- [ ] Real graphics and icons (it currently looks exactly like a gun turret). Untested visually (headless
      has no graphics). A bigger or different body (rocket turret or artillery parts) may read
      better as a cannon.
- [ ] Check in game that the three heads show in the turret's priority-target picker.
- [ ] Balance: range, damage, cooldown, turn speed, costs.
- [ ] Circuit control of the target list.

### 7. Pollution (vibration)
- [x] Vibration pollution layer on Vulcanus: drills and pumps emit, lava absorbs most, rock
      medium-high; affects evolution (`vibration` test).
- [x] Global effect: through evolution only (time and vibration).
- [x] Local effect: loud vibration in a territory chunk draws its demolisher to investigate
      (`vibration-investigate` test).
- [ ] Tune the threshold (20), check interval (5 s) and per-demolisher cooldown (1 min) against a
      real base; check what a typical mining outpost's chunk reaches.
- [x] Performance: the check is spread over its interval, a slice of explored chunks per tick.
- Decided: nests stay at the territory centre regardless of vibration; efficiency modules are the
  player's way to make less.

### 8. Release
- [ ] Player-facing README and mod portal description, thumbnail, dated changelog.
- [ ] Publish (first release uses `tools/upload_mod.py --publish`).
