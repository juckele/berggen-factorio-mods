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
  `tuning.lua`), divided by a pollution multiplier (always 1 until pollution is designed).
  Expansion at 1/20 is 3 min at no evolution to 30 s at full evolution on default map settings.
- **Enemy expansion required.** The mod does nothing with enemy expansion turned off in the map
  settings, and says so in chat once each time it finds it off.
- **Retaking cleared land.** Every expansion, one cleared chunk next to a territory with a living
  demolisher joins that territory, explored or not. This is the mod's main loop: land the player
  clears doesn't stay clear. Retaken land never spawns extra demolishers.
- **Other expansion.** When no cleared chunk borders a living territory, a territory may instead
  grow into a neighbouring explored chunk without territory. In practice that's only the starting
  area, so it only happens with protection off.
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
  - parent dead (weight 10): it takes the nest chunk, which retaking leaves alone while the nest
    has eggs;
  - cleared land next to the parent's explored land (weight 3): it takes the parent chunk
    bordering it, nearest the nest, and walks there;
  - otherwise, once 30 minutes old (weight 1): it takes the parent's edge chunk nearest the nest.
  Each hatch shrinks the parent by one chunk, so repeated hatching eventually takes a parent under
  the nesting minimum. Destroyed eggs are gone for good; the nest marker disappears with its last
  egg. Nest and egg graphics are placeholders (Vulcanus hot rocks).
- **Tremors.** Vulcanus gets its own pollution layer, *tremors* (vanilla Vulcanus has no pollutant).
  Mining drills, pumps and offshore pumps emit it while working (burner drill 6/min, electric drill
  10, big drill 40, pump 3, offshore pump 8; other mods' drills and pumps fall back by type). Lava
  absorbs it fastest (0.0001 per tile per second, the top vanilla rate) and volcanic ground
  medium-high (0.00002; grass absorbs pollution at 0.000018). Tremors count toward evolution, which
  shortens every demolisher event clock. They don't affect demolishers in any other way yet.
- **Settings** (all map settings):
  - *Demolishers cannot expand into the starting area* (on). Turning it on later stops further
    growth without evicting territory that already grew there.
  - *Expansion interval override* (10 ticks, very fast so testers can watch). Replaces every event
    clock's cooldown when above 0; 0 uses the map settings. Release will default to 0.
  - *Debug logging* (off): writes decisions to `factorio-current.log`.
- **Remote interface** `vulcanus-demolisher-lifecycle`. Reads: `get_state()`, `get_trips()`,
  `get_nests()`, `get_safe_chunks()`, `is_safe_chunk(x, y)`, `get_cleared_chunks()`,
  `is_cleared_chunk(x, y)`. For testing: `set_tuning{key = value}` overrides `tuning.lua` values,
  and `run_event(name)` runs one event now. The headless tests use it, and other mods can too.

Tests: [`tests/vulcanus-demolisher-lifecycle`](../../tests/vulcanus-demolisher-lifecycle).

## Remaining work

### 1. Setup on new and established games
- [x] New game, Vulcanus created later (`new-game` test).
- [x] Added to a save that has been to Vulcanus and built there (`established` test).
- [x] Added to a save where demolishers were killed (`killed` test): their land is marked cleared
      and retaken.
- [ ] Saves that ran the first 0.2.0 build: land it cleared wasn't marked, so it is never retaken.
      Only matters for testers' saves; could be fixed by marking territory-free explored chunks
      outside the safe zone as cleared.
- [x] Vulcanus created by another mod's `on_init`, which doesn't raise `on_surface_created` for us:
      a once-a-second check picks it up. Not covered by a test yet (in the tests, the setup mod's
      `on_init` runs first).
- [ ] No-enemies mode: every territory is empty, so setup currently removes them all. Decide whether
      the mod should do anything at all with no enemies.
- [ ] Test against a hand-played save (late game on Vulcanus, many kills, odd starting-area slider).
- [x] Killing a demolisher whose territory is entirely unexplored clears it (found by the `nests`
      test; dead territories were looked up by an explored chunk before).
- [ ] Decide what to do when other mods destroy demolishers with `destroy()` without raising
      `script_raised_destroy_segmented_unit`: only the setup sweep catches those today.
- [ ] Multiplayer check (a server run with two clients) before release.

### 2. Game balance
- [x] Expansion follows the map's enemy expansion settings (enabled, min/max cooldown) with
      vanilla's evolution scaling (`map-settings` test).
- [ ] Tune `tuning.lua`: event scales, growth midpoints and width, nest minimum size, egg ages and
      hatch weights.
- [ ] Switch the override's default to 0 for release.
- [ ] Measure how long a cleared area stays clear at the chosen rate, on a real base.
- [ ] Performance: nesting trips update every tick (at most 2 at once). Growth samples 8
      demolishers, and hatching scans the cleared chunks per nest.
- [ ] Performance: every attempt scans all cleared chunks for ones bordering a living territory.
      Fine for hundreds of chunks; profile with thousands, and keep a frontier set if needed.

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

Open:
- [ ] Hatchling arrival: a free-space hatchling walks from the nest to its chunk across the parent's
      land; check that it looks right in game, and whether it should wait to claim the chunk until
      it gets there.
- [ ] Free space in unexplored land can't be used: a new territory needs an explored chunk, so the
      egg waits for the old-egg rule instead.
- [ ] Real graphics for the nest and eggs, and hatching effects and sound.
- [ ] Should eggs show on the map, or only be found by scouting?
- [ ] Other ideas from the brainstorm, not planned: bifurcation, births in gaps between two
      territories, budding, fragments surviving a sloppy kill, spawning from volcanoes.

### 4. Territory expansion as a real threat
- [x] Living territories retake cleared land, explored or not.
- [ ] Decide whether retaking is the whole threat or whether territory should also push into land
      with player buildings outside the starting area.
- [ ] Retaking should prefer chunks toward the player (buildings, pollution) over random cleared edges.
- [ ] Warn the player: an alert or map marker when territory grows into a chunk with their buildings.

### 5. The original safe zone stays safe
- [x] Recorded on setup even with protection off; protection on by default; turning it on doesn't
      evict (`unprotected` test).
- [ ] Show the safe zone on the map (optional overlay or chart tags).
- [ ] Test other seeds and starting-area slider values (the disc moves with the slider).
- [ ] Decide whether the player can extend the safe zone (e.g. land they cleared and built on).

### 6. Ping rifle: automated demolisher handling
- [ ] Design: does the ping kill demolishers, lure them, or drive them out of an area? Is it a
      hand-held weapon, a building, or both? Automating suggests a building, like a turret.
- [ ] Long range, with a target filter (demolisher size, inside or outside territory, near which
      buildings), ideally settable by circuit network.
- [ ] Item, recipe, technology, graphics, and balance against the vanilla ways of killing demolishers.

### 7. Pollution (tremors)
- [x] Tremors pollution layer on Vulcanus: drills and pumps emit, lava absorbs most, rock
      medium-high; affects evolution (`tremors` test).
- [ ] Every event clock divides its cooldown by `pollution_multiplier(surface)` in control.lua,
      which returns 1. Decide what it measures.
- [ ] Decide how demolishers interact with tremors (brainstormed 2026-10-25): tremors draw
      investigation, speed up events locally or globally, steer retaking toward the source, wake
      sleeping demolishers, are absorbed by territories (spawner-like), and so on.
- [ ] Should anything besides drills and pumps make tremors (trains, foundries, rocket launches,
      big machines)? Should quiet alternatives exist (a technology or module that reduces them)?
- [ ] Make the effect visible to the player (statistics, tooltip, or map overlay).
- [ ] Balance with 2 (rate) and 4 (direction).

### 8. Release
- [ ] Player-facing README and mod portal description, thumbnail, dated changelog.
- [ ] Publish (first release uses `tools/upload_mod.py --publish`).
