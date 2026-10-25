# Vulcanus Demolisher Lifecycle

Allows demolishers to grow and spawn young.

This README tracks remaining work while the mod is in development. Once the work below is done it
goes back to being player-facing text for the mod portal.

## Current behaviour (0.2.0, Factorio 2.1)

- **Setup.** The mod sets itself up whenever Vulcanus exists: in a new game, when Vulcanus is first
  created, or when the mod is added to a save that has already been to Vulcanus.
- **Dead territories are removed.** In vanilla a territory outlives its last demolisher. The mod
  removes it a tick after its last demolisher dies, and on setup it removes territories whose
  demolishers were already killed. Their chunks are set to "no territory" rather than destroyed:
  `LuaTerritory.destroy()` lets the map generator put a new territory, with a new demolisher, on
  any of those chunks that get explored later.
- **Starting area.** The territory-free starting area is recorded per Vulcanus surface, whether or not
  protection is on. A chunk counts if it is in or next to the map generator's starting-area disc
  (`demolisher_starting_area`) and has no territory once generated.
- **Expansion.** Every interval, one territory with a living demolisher grows by one chunk into a
  neighbouring generated chunk that has no territory.
- **Settings** (all map settings):
  - *Demolishers cannot expand into the starting area* (on). Turning it on later stops further
    growth without evicting territory that already grew there.
  - *Seconds between territory expansions* (600, a placeholder until the balance pass).
  - *Debug logging* (off): writes decisions to `factorio-current.log`.
- **Remote interface** `vulcanus-demolisher-lifecycle` (read-only): `get_state()`,
  `get_safe_chunks()`, `is_safe_chunk(x, y)`. The headless tests use it, and other mods can too.

Tests: [`tests/vulcanus-demolisher-lifecycle`](../../tests/vulcanus-demolisher-lifecycle).

## Remaining work

### 1. Setup on new and established games
- [x] New game, Vulcanus created later (`new-game` test).
- [x] Added to a save that has been to Vulcanus and built there (`established` test).
- [x] Added to a save where demolishers were killed (`killed` test).
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
- [ ] Expansion rate: the 600 s interval is a placeholder. Decide whether it scales with territory
      count, demolisher size, time on Vulcanus, or pollution (see 7).
- [ ] Cap on territory size, and on total territory per surface.
- [ ] Measure how long a cleared area stays clear at the chosen rate, on a real base.
- [ ] Performance: expansion samples 8 random territories per attempt; profile on a fully explored
      Vulcanus with many territories.

### 3. Spawn logic that feels coherent
- [ ] Growth: small demolishers become medium, then big, over time (replace the unit in place,
      keeping its position and body shape).
- [ ] Young: a territory past some size splits; the new part gets a small demolisher that starts near
      the parent's edge, not somewhere random.
- [ ] Decide which demolisher size retakes land the player cleared (currently: whichever territory
      expands into it, and no new unit is created).
- [ ] Limits per territory and per surface, so the planet can't fill up.

### 4. Territory expansion as a real threat
- [ ] Today the only land without territory is the starting area and cleared territories, so with
      protection on, expansion means demolishers retaking land the player cleared. Decide whether
      that is the whole threat or whether territory should also push into land with player
      buildings outside the starting area.
- [ ] Expansion should prefer chunks toward the player (buildings, pollution) over random edges.
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
