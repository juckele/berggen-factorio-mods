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
- **Retaking cleared land.** Every interval, one cleared chunk next to a territory with a living
  demolisher joins that territory, explored or not. This is the mod's main loop: land the player
  clears doesn't stay clear. Retaken land never spawns extra demolishers.
- **Other expansion.** When no cleared chunk borders a living territory, a territory may instead
  grow into a neighbouring explored chunk without territory. In practice that's only the starting
  area, so it only happens with protection off.
- **Settings** (all map settings):
  - *Demolishers cannot expand into the starting area* (on). Turning it on later stops further
    growth without evicting territory that already grew there.
  - *Ticks between territory expansions* (10, very fast so testers can watch land being retaken;
    the balance pass will slow it down).
  - *Debug logging* (off): writes decisions to `factorio-current.log`.
- **Remote interface** `vulcanus-demolisher-lifecycle` (read-only): `get_state()`,
  `get_safe_chunks()`, `is_safe_chunk(x, y)`, `get_cleared_chunks()`, `is_cleared_chunk(x, y)`. The headless tests use it, and other mods can too.

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
- [ ] Decide what to do when other mods destroy demolishers with `destroy()` without raising
      `script_raised_destroy_segmented_unit`: only the setup sweep catches those today.
- [ ] Multiplayer check (a server run with two clients) before release.

### 2. Game balance
- [ ] Calibrate expansion and splitting from the game's map settings (`map_settings.enemy_expansion`:
      enabled, cooldowns), so a map's enemy expansion settings also set how aggressive
      demolishers are. The tick setting stays as a test override.
- [ ] Retake rate: the 10-tick interval is for testing.
- [ ] Measure how long a cleared area stays clear at the chosen rate, on a real base.
- [ ] Performance: every attempt scans all cleared chunks for ones bordering a living territory.
      Fine for hundreds of chunks; profile with thousands, and keep a frontier set if needed.

### 3. Spawn logic that feels coherent
Decided:
- One demolisher per territory, always. A new demolisher means a new territory, and a territory
  without a demolisher becomes cleared land. Explored land is finite, so the population is bounded
  without extra limits.
- Expansion is global per surface, like biter and pentapod expansion: the rate doesn't scale with
  explored area or territory count.

Candidate mechanics (brainstorm, not yet chosen):
- [ ] Growth by territory size: a territory above a size threshold has a chance (sigmoid-like
      curve) to upgrade its demolisher small → medium → big. Retaking cleared land then makes
      neighbours stronger, which punishes leaving a gap open.
- [ ] Bifurcation: a demolisher splits into 2+ small demolishers, and its territory is partitioned
      between them.
- [ ] Births in gaps: cleared land bordered by two or more living territories gets a new small
      demolisher and territory, instead of only being absorbed. Probably gives the most
      interesting emergent shapes.
- [ ] Budding: a big demolisher's tail breaks off as a small one at the territory edge.
- [ ] Eggs: a visible, destroyable egg that hatches into a new territory (a target for the ping
      rifle).
- [ ] Fragment survives a sloppy kill and keeps the territory.
- [ ] Spawning from volcanoes or lava, so a fully cleared planet still refills.
- [ ] Implementation notes: there's no in-place upgrade, so growth creates the new unit with the old
      body nodes and destroys the old one. `LuaTerritory.regenerate_segmented_units()` spawns the
      demolisher the map generator would place for a script-made territory (sized by distance).

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

### 7. Pollution
- [ ] Decide the model: territories absorb pollution like spawners and grow faster with it, pollution
      draws expansion toward the base, or both.
- [ ] Make the effect visible to the player (statistics, tooltip, or map overlay).
- [ ] Balance with 2 (rate) and 4 (direction).

### 8. Release
- [ ] Player-facing README and mod portal description, thumbnail, dated changelog.
- [ ] Publish (first release uses `tools/upload_mod.py --publish`).
