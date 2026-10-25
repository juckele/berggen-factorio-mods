-- Checks for Vulcanus Demolisher Lifecycle. Each phase name in tests.json maps to a handler below.
-- The mod's state is read through its remote interface ("vulcanus-demolisher-lifecycle").

local H = require("__headless-test-harness__/harness")
H.install()

local MOD = "vulcanus-demolisher-lifecycle"
local SETUP = "demolisher-lifecycle-test-setup"
local PROTECT = "demolisher-lifecycle-protect-starting-area"

local function state() return remote.call(MOD, "get_state") end
local function state_stats() return remote.call(MOD, "get_state").stats end
local function vulcanus() return game.surfaces["vulcanus"] end
local function setup_record()
  if remote.interfaces[SETUP] then return remote.call(SETUP, "get_record") end
  return nil
end

local function safe_in_territory()
  local surface, n = vulcanus(), 0
  for _, chunk in pairs(remote.call(MOD, "get_safe_chunks")) do
    if surface.get_territory_for_chunk(chunk) then n = n + 1 end
  end
  return n
end

local function dead_territories()
  local n = 0
  for _, t in pairs(vulcanus().get_territories()) do
    if #t.get_segmented_units() == 0 then n = n + 1 end
  end
  return n
end

local function chunks_with_territory(chunks)
  local surface, n = vulcanus(), 0
  for _, chunk in pairs(chunks) do
    if surface.get_territory_for_chunk(chunk) then n = n + 1 end
  end
  return n
end

local function generate(chunks)
  local surface = vulcanus()
  for _, chunk in pairs(chunks) do
    surface.request_to_generate_chunks({ chunk.x * 32 + 16, chunk.y * 32 + 16 }, 0)
  end
  surface.force_generate_chunk_requests()
end

-- What should hold right after the mod sets up on a Vulcanus surface.
local function check_initialized(prefix)
  local s = state()
  H.info(prefix .. "-state", s)
  H.check(prefix .. "-initialized", s.initialized)
  H.check(prefix .. "-safe-zone-recorded", s.safe_chunk_count > 100, s.safe_chunk_count .. " safe chunks")
  H.equal(prefix .. "-safe-zone-has-no-territory", safe_in_territory(), 0)
  H.equal(prefix .. "-no-dead-territories", dead_territories(), 0)
  local spawn = game.forces.player.get_spawn_position(vulcanus())
  H.check(prefix .. "-spawn-is-safe",
    remote.call(MOD, "is_safe_chunk", math.floor(spawn.x / 32), math.floor(spawn.y / 32)))
end

local function coil_dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local phases = {}

---------------------------------------------------------------------------------------------------
-- new-game: the mod is in the save from the start; Vulcanus is created mid-game.

phases["new-game-create"] = {
  init = function()
    local s = state()
    H.check("no-vulcanus-yet", vulcanus() == nil)
    H.check("not-initialized-without-vulcanus", not s.initialized)
    H.equal("schema", s.schema, 3)
    H.done()
  end,
}

phases["new-game-run"] = {
  ticks = function()
    local victim -- { unit, chunks, ungenerated }
    H.at(1, function()
      local surface = game.planets.vulcanus.create_surface()
      surface.request_to_generate_chunks({ 0, 0 }, 12)
      surface.force_generate_chunk_requests()
    end)
    H.at(2, function()
      check_initialized("on-surface-created")
      local s = state()
      H.equal("initialized-on-creation-tick", s.initialized_tick, game.tick - 1)
      -- Pick a demolisher outside the starting area, nearest the spawn.
      local best, best_d
      for _, unit in pairs(vulcanus().get_segmented_units()) do
        local p = unit.segments[1].position
        local d = p.x * p.x + p.y * p.y
        if not best_d or d < best_d then best, best_d = unit, d end
      end
      local surface = vulcanus()
      local chunks, ungenerated = best.territory.get_chunks(), {}
      for _, c in pairs(chunks) do
        if not surface.is_chunk_generated(c) then ungenerated[#ungenerated + 1] = c end
      end
      victim = { unit = best, chunks = chunks, ungenerated = ungenerated, territories = #surface.get_territories() }
      H.info("victim", best.prototype.name .. ", " .. #chunks .. " chunks, " .. #ungenerated .. " ungenerated")
    end)
    H.at(3, function() victim.unit.die() end)
    H.at(5, function()
      local s = state()
      H.equal("kill-clears-territory", s.stats.territories_cleared, 1)
      H.equal("kill-territory-count", #vulcanus().get_territories(), victim.territories - 1)
      H.equal("kill-no-pending", s.pending_checks, 0)
      -- Expansion may already have started, so cleared + taken must account for every chunk.
      H.equal("kill-marks-chunks-cleared", s.cleared_chunk_count + s.stats.cleared_chunks_taken, #victim.chunks)
      H.equal("only-taken-chunks-have-territory", chunks_with_territory(victim.chunks), s.stats.cleared_chunks_taken)
      victim.units = #vulcanus().get_segmented_units()
      generate(victim.ungenerated)
    end)
    H.at(6, function()
      H.equal("cleared-land-no-new-territories", #vulcanus().get_territories(), victim.territories - 1)
      H.equal("cleared-land-no-new-demolishers", #vulcanus().get_segmented_units(), victim.units)
    end)
    H.at(2300, function()
      local s = state()
      H.info("final-stats", s.stats)
      H.equal("all-cleared-land-taken", chunks_with_territory(victim.chunks), #victim.chunks)
      H.equal("no-cleared-chunks-left", s.cleared_chunk_count, 0)
      H.equal("chunks-taken", s.stats.cleared_chunks_taken, #victim.chunks)
      H.equal("expansion-spawns-no-demolishers", #vulcanus().get_segmented_units(), victim.units)
      H.equal("protected-safe-zone-stays-safe", safe_in_territory(), 0)
      H.check("safe-zone-blocked-expansion", s.stats.expansions_blocked_by_safe_zone > 0,
        s.stats.expansions_blocked_by_safe_zone .. " blocked attempts")
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------
-- unprotected: added to the established save (same fixture) with protection off.

phases["unprotected-add"] = {
  init = function()
    check_initialized("added-without-protection")
    H.check("protection-off", not settings.global[PROTECT].value)
  end,
  ticks = function()
    H.at(1500, function()
      local s = state()
      H.info("stats", s.stats)
      H.check("unprotected-expands-into-starting-area", safe_in_territory() > 0, safe_in_territory() .. " safe chunks taken")
      H.check("safe-zone-still-recorded", s.safe_chunk_count > 100)
      H.done()
    end)
  end,
}

-- Driven over RCON: the test lets territory grow into the starting area, then turns protection on.
phases["toggle-protection"] = {
  setting_changed = function(event)
    if event.setting ~= PROTECT or not settings.global[PROTECT].value then return end
    local taken = safe_in_territory()
    local blocked = state().stats.expansions_blocked_by_safe_zone
    H.check("enabling-protection-does-not-evict", taken > 0, taken .. " safe chunks in territory")
    H.after(600, function()
      local s = state()
      H.equal("no-expansion-into-safe-zone-after-enabling", safe_in_territory(), taken)
      H.check("expansion-blocked-after-enabling", s.stats.expansions_blocked_by_safe_zone > blocked,
        (s.stats.expansions_blocked_by_safe_zone - blocked) .. " blocked attempts")
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------
-- established: Vulcanus was visited and built on before the mod was added.

phases["established-add"] = {
  init = function()
    local record = setup_record()
    check_initialized("added-to-established")
    local s = state()
    H.equal("initialized-on-add-tick", s.initialized_tick, game.tick)
    H.equal("no-territories-cleared", s.stats.territories_cleared, 0)
    H.equal("territories-untouched", #vulcanus().get_territories(), record.territory_count)
    H.equal("demolishers-untouched", #vulcanus().get_segmented_units(), record.unit_count)
    local unsafe = 0
    for _, chunk in pairs(record.built_chunks) do
      if not remote.call(MOD, "is_safe_chunk", chunk.x, chunk.y) then unsafe = unsafe + 1 end
    end
    H.equal("base-inside-safe-zone", unsafe, 0)
  end,
  ticks = function()
    H.at(590, function()
      local record, s = setup_record(), state()
      local alive = 0
      for _, entity in pairs(vulcanus().find_entities_filtered({ force = "player" })) do
        alive = alive + 1
      end
      H.equal("base-intact", alive, #record.built_unit_numbers)
      H.equal("only-free-land-is-safe-zone", s.stats.expansions, 0)
      H.check("expansion-attempts-blocked", s.stats.expansions_blocked_by_safe_zone > 0)
      H.equal("safe-zone-still-safe", safe_in_territory(), 0)
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------
-- map-settings: no interval override, so the cooldown comes from the map's enemy expansion settings
-- (defaults: 10 to 60 minutes) scaled by the mod (1/20) and shortened by evolution like biters.

local MAX_COOLDOWN = 60 * 60 * 60 / 20 -- 10800 ticks at evolution 0
local MIN_COOLDOWN = 10 * 60 * 60 / 20 -- 1800 ticks at evolution 1

phases["map-settings-add"] = {
  init = function()
    local s = state()
    H.equal("override-off", settings.global["demolisher-lifecycle-expansion-interval-ticks"].value, 0)
    H.equal("cooldown-at-evolution-0", s.expansion_cooldown, MAX_COOLDOWN)
    H.equal("first-expansion-scheduled", s.next_expansion_tick, s.initialized_tick + MAX_COOLDOWN)
  end,
  ticks = function()
    local enemy = function() return game.forces.enemy end
    local first
    H.at(2, function()
      enemy().set_evolution_factor(0.5, vulcanus())
      -- lerp(10800, 1800, -0.25 + 1) = 4050
      H.equal("cooldown-at-evolution-0.5", state().expansion_cooldown, 4050)
      enemy().set_evolution_factor(1, vulcanus())
      H.equal("cooldown-at-evolution-1", state().expansion_cooldown, MIN_COOLDOWN)
      game.map_settings.enemy_expansion.min_expansion_cooldown = 20 * 60 * 60
      H.equal("follows-map-min-cooldown", state().expansion_cooldown, 3600)
      game.map_settings.enemy_expansion.min_expansion_cooldown = 10 * 60 * 60
      H.equal("no-attempt-before-cooldown", state().stats.expansion_attempts, 0)
    end)
    H.at(MAX_COOLDOWN + 2, function()
      local s = state()
      H.equal("attempt-after-cooldown", s.stats.expansion_attempts, 1)
      H.equal("next-uses-current-evolution", s.next_expansion_tick, s.last_expansion_tick + MIN_COOLDOWN)
      first = s.next_expansion_tick
      game.map_settings.enemy_expansion.enabled = false
    end)
    H.at(MAX_COOLDOWN + MIN_COOLDOWN + 10, function()
      local s = state()
      H.equal("no-attempt-with-expansion-disabled", s.stats.expansion_attempts, 1)
      H.check("warns-when-expansion-disabled", s.warned_expansion_disabled)
      H.check("still-rescheduled-while-disabled", s.next_expansion_tick > first)
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------
-- nests: growth, a nesting trip, and every way an egg can end. Events are driven with run_event so
-- the order is fixed; only the trip itself runs on its own, tick by tick.

local function units_by_number()
  local map, count = {}, 0
  for _, unit in pairs(vulcanus().get_segmented_units()) do
    map[unit.unit_number] = unit
    count = count + 1
  end
  return map, count
end

local function chunk_count(territory)
  return #territory.get_chunks()
end

local function run(name, times)
  local done = 0
  for _ = 1, times or 1 do
    if remote.call(MOD, "run_event", name) then done = done + 1 end
  end
  return done
end

local nest_test = {}

phases["nests-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    growth_midpoint = { ["medium-demolisher"] = 1, ["big-demolisher"] = 1 },
    growth_width = 0.001,
    eggs_min = 4, eggs_max = 4,
    egg_min_age = 60, egg_old_age = 600,
    nest_build_ticks = 120,
  },
  init = function()
    local _, count = units_by_number()
    nest_test.units = count
    local tiers0 = { ["small-demolisher"] = 1, ["medium-demolisher"] = 2, ["big-demolisher"] = 3 }
    nest_test.original_tiers = {}
    for _, unit in pairs(vulcanus().get_segmented_units()) do nest_test.original_tiers[unit.unit_number] = tiers0[unit.prototype.name] end
    -- Distance gate: nothing may grow past what the map generator places at its distance.
    remote.call(MOD, "set_tuning", { growth_tiers_above_native = 0 })
    run("growth", 20)
    local tiers = { ["small-demolisher"] = 1, ["medium-demolisher"] = 2, ["big-demolisher"] = 3 }
    local over = 0
    for _, unit in pairs(vulcanus().get_segmented_units()) do
      -- The map generator sizes a demolisher by its territory, so judge at the territory's centre,
      -- and allow what the map generator placed.
      local sx, sy, n = 0, 0, 0
      for _, c in pairs(unit.territory.get_chunks()) do sx, sy, n = sx + c.x * 32 + 16, sy + c.y * 32 + 16, n + 1 end
      local native = math.floor(vulcanus().calculate_tile_properties({ "demolisher_variation_expression" },
        { { sx / n, sy / n } })["demolisher_variation_expression"][1]) + 1
      local original = nest_test.original_tiers[unit.unit_number]
      if tiers[unit.prototype.name] > math.max(native, original or 1) then over = over + 1 end
    end
    H.equal("no-growth-past-native-size", over, 0)
    remote.call(MOD, "set_tuning", { growth_tiers_above_native = 2 })
    local grew = run("growth", 60)
    H.check("growth-happens", grew > 0, grew .. " growths")
    local _, after = units_by_number()
    H.equal("growth-keeps-one-demolisher-per-territory", after, count)
    H.equal("growth-leaves-no-dead-territories", dead_territories(), 0)
    local bigs = 0
    for _, unit in pairs(vulcanus().get_segmented_units()) do
      if unit.prototype.name == "big-demolisher" then bigs = bigs + 1 end
    end
    H.check("some-reach-max-size", bigs > 0, bigs .. " big demolishers")
    remote.call(MOD, "set_tuning", { nest_min_chunks = 1, nest_max_trips = 1 })
    H.equal("nest-trip-starts", run("nest"), 1)
    H.equal("only-one-trip-at-a-time", run("nest"), 0)
    local trip = remote.call(MOD, "get_trips")[1]
    nest_test.trip = trip
    nest_test.parent = units_by_number()[trip.unit_number]
    H.info("trip", trip.unit_number .. " to " .. serpent.line(trip.site) .. ", head " ..
      math.floor(coil_dist(nest_test.parent.get_body_nodes()[1], trip.site)) .. " tiles away")
    H.check("nest-at-territory-centre", vulcanus().get_territory_for_chunk(trip.chunk) ~= nil)
  end,
  ticks = function()
    local step = 0
    local seen = {}
    local function poll()
      local t = nest_test
      if t.finished then return end
      local trips = remote.call(MOD, "get_trips")
      local trip = trips[1]
      if trip then
        if not seen[trip.phase] then
          seen[trip.phase] = H.phase_tick()
          H.info("trip-phase-" .. trip.phase, "at phase tick " .. H.phase_tick())
        end
        if trip.phase == "build" and not t.checked_coil then
          t.checked_coil = true
          local far = 0
          for _, node in pairs(t.parent.get_body_nodes()) do far = math.max(far, coil_dist(node, trip.site)) end
          H.check("coiled-around-nest", far <= 12, "furthest body node " .. string.format("%.1f", far) .. " tiles from the nest")
        end
        if H.phase_tick() > 13000 then
          H.check("trip-finished-in-time", false, "still in " .. trip.phase)
          t.finished = true
          H.done()
        end
        return
      end
      if not t.nest then
        local nests = remote.call(MOD, "get_nests")
        H.equal("nest-laid", #nests, 1)
        if #nests ~= 1 then t.finished = true; H.done(); return end
        t.nest = nests[1]
        t.laid_tick = game.tick
        H.check("trip-went-through-every-phase", seen.travel ~= nil and seen.coil ~= nil and seen.build ~= nil)
        H.equal("eggs-laid", #t.nest.eggs, 4)
        local furthest = 0
        for _, egg in pairs(t.nest.eggs) do furthest = math.max(furthest, coil_dist(egg.position, t.nest.site)) end
        H.check("eggs-at-nest", furthest <= 5, "furthest egg " .. string.format("%.1f", furthest) .. " tiles from the nest")
        H.equal("nest-marker-placed", vulcanus().count_entities_filtered({ name = "demolisher-nest" }), 1)
        H.equal("egg-entities", vulcanus().count_entities_filtered({ name = "demolisher-egg" }), 4)
        local egg_proto, nest_proto = prototypes.entity["demolisher-egg"], prototypes.entity["demolisher-nest"]
        local red = egg_proto.map_color and egg_proto.map_color.r > 0 and egg_proto.map_color.g == 0 and egg_proto.map_color.b == 0
        H.check("eggs-red-on-map", red and not (egg_proto.flags and egg_proto.flags["not-on-map"]), serpent.line(egg_proto.map_color))
        H.check("nest-marker-not-on-map", nest_proto.flags and nest_proto.flags["not-on-map"] or false)
        H.equal("nest-chunk-reserved", state().reserved_chunk_count, 1)
        H.check("parent-back-on-patrol", t.parent.get_ai_state().type == defines.segmented_unit_ai_state.patrolling)
        H.equal("too-young-to-hatch", run("hatch"), 0)
        t.stage = "aging"
        return
      end
      local age = game.tick - t.laid_tick
      if t.stage == "aging" and age >= 300 then
        H.equal("not-old-enough-with-parent-alive", run("hatch"), 0)
        t.stage = "old"
      elseif t.stage == "old" and age >= 620 then
        local territory = t.parent.territory
        local before = chunk_count(territory)
        local _, units_before = units_by_number()
        H.equal("old-egg-hatches", run("hatch"), 1)
        H.equal("old-hatch-reason", state().stats.hatched_old, 1)
        H.equal("old-hatch-takes-one-parent-chunk", chunk_count(territory), before - 1)
        local _, units_after = units_by_number()
        H.equal("old-hatch-adds-one-demolisher", units_after, units_before + 1)
        -- Headless doesn't chart without players, so nothing is in radar coverage: no alert. The
        -- alert itself (expansion_base_built for forces that see the chunk) is checked in game.
        H.equal("no-alert-outside-radar-coverage", state().stats.hatch_alerts, 0)
        H.equal("eggs-left-after-old-hatch", state().egg_count, 3)
        -- Free space: kill a neighbour, so cleared land borders the parent's territory. The border
        -- must be explored land: a hatchling's territory needs an explored chunk.
        local parent_set = {}
        for _, c in pairs(territory.get_chunks()) do
          if vulcanus().is_chunk_generated(c) then parent_set[c.x .. "," .. c.y] = true end
        end
        for _, unit in pairs(vulcanus().get_segmented_units()) do
          if unit.unit_number ~= t.parent.unit_number and not t.neighbour and chunk_count(unit.territory) > 1 then
            for _, c in pairs(unit.territory.get_chunks()) do
              if parent_set[(c.x + 1) .. "," .. c.y] or parent_set[(c.x - 1) .. "," .. c.y]
                or parent_set[c.x .. "," .. (c.y + 1)] or parent_set[c.x .. "," .. (c.y - 1)] then
                t.neighbour = unit
                break
              end
            end
          end
        end
        H.check("found-neighbour", t.neighbour ~= nil)
        H.info("neighbour", t.neighbour.prototype.name .. ", " .. chunk_count(t.neighbour.territory) .. " chunks")
        t.neighbour.die()
        t.stage = "free"
      elseif t.stage == "free" and age >= 640 then
        H.check("neighbour-land-cleared", state().cleared_chunk_count > 0, state().cleared_chunk_count .. " cleared chunks")
        local before = chunk_count(t.parent.territory)
        H.equal("free-space-egg-hatches", run("hatch"), 1)
        H.equal("free-space-hatch-reason", state().stats.hatched_free_space, 1)
        H.equal("free-space-hatch-takes-one-parent-chunk", chunk_count(t.parent.territory), before - 1)
        -- The hatchling's chunk must border the cleared land.
        local cleared = {}
        for _, c in pairs(remote.call(MOD, "get_cleared_chunks")) do cleared[c.x .. "," .. c.y] = true end
        local newest
        for _, unit in pairs(vulcanus().get_segmented_units()) do
          if unit.prototype.name == "small-demolisher" and chunk_count(unit.territory) == 1 then
            if not newest or unit.unit_number > newest.unit_number then newest = unit end
          end
        end
        local c = newest.territory.get_chunks()[1]
        H.check("free-space-hatchling-borders-cleared-land", cleared[(c.x + 1) .. "," .. c.y] or cleared[(c.x - 1) .. "," .. c.y]
          or cleared[c.x .. "," .. (c.y + 1)] or cleared[c.x .. "," .. (c.y - 1)] or false)
        H.check("hatchling-starts-at-egg", coil_dist(newest.get_body_nodes()[1], t.nest.site) < 12)
        -- Destroying an egg removes it.
        local egg = vulcanus().find_entities_filtered({ name = "demolisher-egg", limit = 1 })[1]
        egg.die()
        t.stage = "destroyed"
      elseif t.stage == "destroyed" and age >= 660 then
        H.equal("destroyed-egg-counted", state().stats.eggs_destroyed, 1)
        H.equal("one-egg-left", state().egg_count, 1)
        t.nest_chunk = t.nest.chunk
        t.parent.die()
        t.stage = "orphaned"
      elseif t.stage == "orphaned" and age >= 680 then
        H.check("parent-marked-dead", remote.call(MOD, "get_nests")[1].parent_dead)
        H.check("nest-chunk-cleared", remote.call(MOD, "is_cleared_chunk", t.nest_chunk.x, t.nest_chunk.y))
        -- Neighbours expand into the parent's land, except the nest chunk, which waits for the egg.
        remote.call(MOD, "set_tuning", { expansion_enabled = false })
        local taken = run("expansion", 50)
        H.check("parent-land-taken", taken > 0, taken .. " chunks")
        H.check("nest-chunk-kept-for-egg", vulcanus().get_territory_for_chunk(t.nest_chunk) == nil)
        local _, units_before = units_by_number()
        H.equal("orphan-egg-hatches", run("hatch"), 1)
        H.equal("orphan-hatch-reason", state().stats.hatched_dead_parent, 1)
        local territory = vulcanus().get_territory_for_chunk(t.nest_chunk)
        H.check("orphan-takes-nest-chunk", territory ~= nil and chunk_count(territory) == 1)
        local _, units_after = units_by_number()
        H.equal("orphan-hatch-adds-one-demolisher", units_after, units_before + 1)
        H.equal("nest-gone-when-empty", state().nest_count, 0)
        H.equal("nest-marker-removed", vulcanus().count_entities_filtered({ name = "demolisher-nest" }), 0)
        H.equal("reservation-released", state().reserved_chunk_count, 0)
        H.equal("no-dead-territories", dead_territories(), 0)
        t.finished = true
        H.done()
      end
    end
    for offset = 20, 14000, 20 do H.at(offset, poll) end
  end,
}

-- nests-natural: every event on its own clock (10-tick override), thresholds low. Nothing is
-- forced; this checks the pieces work together and keep one demolisher per territory.
phases["nests-natural-add"] = {
  tuning = {
    growth_midpoint = { ["medium-demolisher"] = 1, ["big-demolisher"] = 1 },
    growth_width = 0.001, growth_tiers_above_native = 2,
    nest_min_chunks = 1, nest_build_ticks = 60,
    egg_min_age = 300, egg_old_age = 1200,
  },
  ticks = function()
    H.at(5000, function()
      -- Kill a few demolishers so eggs have orphan and free-space reasons too.
      local killed = 0
      for _, unit in pairs(vulcanus().get_segmented_units()) do
        if killed < 4 and #unit.territory.get_chunks() > 1 then unit.die(); killed = killed + 1 end
      end
    end)
    H.at(15900, function()
      local s = state()
      H.info("stats", s.stats)
      H.check("grew", s.stats.growths > 0)
      H.check("built-nests", s.stats.nests_built > 0, s.stats.nests_built .. " nests")
      H.check("hatched", s.stats.eggs_hatched > 0, s.stats.eggs_hatched .. " hatched")
      local units, territories = #vulcanus().get_segmented_units(), #vulcanus().get_territories()
      H.equal("one-demolisher-per-territory", units, territories)
      local multi = 0
      for _, t in pairs(vulcanus().get_territories()) do if #t.get_segmented_units() > 1 then multi = multi + 1 end end
      H.equal("no-shared-territories", multi, 0)
      H.equal("no-dead-territories", dead_territories(), 0)
      local eggs = vulcanus().count_entities_filtered({ name = "demolisher-egg" })
      H.equal("egg-entities-match-state", eggs, s.egg_count)
      H.equal("nest-markers-match-state", vulcanus().count_entities_filtered({ name = "demolisher-nest" }), s.nest_count)
      H.done()
    end)
  end,
}

-- nest-interrupt: hurting a demolisher while it coils ends the trip and it doesn't retry at once.
phases["nest-interrupt-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    growth_midpoint = { ["medium-demolisher"] = 1, ["big-demolisher"] = 1 },
    growth_width = 0.001, growth_tiers_above_native = 2,
    nest_min_chunks = 1, nest_max_trips = 1,
  },
  init = function()
    run("growth", 60)
    H.equal("trip-starts", run("nest"), 1)
  end,
  ticks = function()
    local t = {}
    local function poll()
      if t.finished then return end
      local trip = remote.call(MOD, "get_trips")[1]
      if not t.unit_number and trip and trip.phase == "coil" then
        t.unit_number = trip.unit_number
        for _, unit in pairs(vulcanus().get_segmented_units()) do
          if unit.unit_number == trip.unit_number then unit.damage(100, "player", "physical") end
        end
        t.at = H.phase_tick()
      elseif t.unit_number and H.phase_tick() >= t.at + 20 then
        local s = state()
        H.equal("trip-aborted", s.stats.trips_aborted, 1)
        H.equal("no-nest-laid", s.stats.nests_built, 0)
        run("nest")
        local again = false
        for _, tr in pairs(remote.call(MOD, "get_trips")) do if tr.unit_number == t.unit_number then again = true end end
        H.check("no-immediate-retry", not again)
        t.finished = true
        H.done()
      elseif H.phase_tick() > 9000 then
        H.check("reached-coil", false)
        t.finished = true
        H.done()
      end
    end
    for offset = 10, 9500, 10 do H.at(offset, poll) end
  end,
}

---------------------------------------------------------------------------------------------------
-- vibration: Vulcanus's pollution layer. Prototypes, a working drill emitting it, and lava absorbing
-- it faster than rock.

local function emits_vibration(name)
  local p = prototypes.entity[name]
  local sources = { p.electric_energy_source_prototype, p.burner_prototype, p.void_energy_source_prototype }
  for _, source in pairs(sources) do
    if source and source.emissions_per_joule and (source.emissions_per_joule.vibration or 0) > 0 then return true end
  end
  return false
end

-- A chunk that is all lava, or all volcanic rock, near the origin.
local function find_chunk(surface, want_lava)
  for r = 2, 12 do
    for cx = -r, r do
      for cy = -r, r do
        if math.max(math.abs(cx), math.abs(cy)) == r and surface.is_chunk_generated({ cx, cy }) then
          local area = { { cx * 32, cy * 32 }, { cx * 32 + 32, cy * 32 + 32 } }
          local lava = surface.count_tiles_filtered({ area = area, name = { "lava", "lava-hot" } })
          if (want_lava and lava == 1024) or (not want_lava and lava == 0) then return { x = cx, y = cy } end
        end
      end
    end
  end
end

local vibration_test = {}

phases["vibration-add"] = {
  init = function()
    local surface = vulcanus()
    H.equal("vulcanus-pollutant", surface.pollutant_type and surface.pollutant_type.name, "vibration")
    H.check("nauvis-unchanged", game.surfaces.nauvis.pollutant_type.name == "pollution")
    for _, name in pairs({ "burner-mining-drill", "electric-mining-drill", "big-mining-drill", "pump", "offshore-pump" }) do
      H.check("emits-" .. name, emits_vibration(name))
    end
    H.check("assembler-does-not-emit", not emits_vibration("assembling-machine-2"))
    local lava = prototypes.tile["lava"].absorptions_per_second.vibration or 0
    local rock = prototypes.tile["volcanic-ash-flats"].absorptions_per_second.vibration or 0
    H.check("lava-absorbs-most", lava > rock and rock > 0, "lava " .. lava .. ", rock " .. rock)

    -- A burner drill on a resource, fuelled.
    local ore = surface.find_entities_filtered({ type = "resource", name = { "coal", "calcite" }, position = { 0, 0 }, radius = 400, limit = 50 })
    for _, resource in pairs(ore) do
      local p = resource.position
      if surface.can_place_entity({ name = "burner-mining-drill", position = p, force = "player" }) then
        local drill = surface.create_entity({ name = "burner-mining-drill", position = p, force = "player" })
        drill.insert({ name = "coal", count = 50 })
        vibration_test.drill = drill
        break
      end
    end
    H.check("placed-drill", vibration_test.drill ~= nil)

    vibration_test.lava_chunk = find_chunk(surface, true)
    vibration_test.rock_chunk = find_chunk(surface, false)
    H.check("found-lava-and-rock-chunks", vibration_test.lava_chunk ~= nil and vibration_test.rock_chunk ~= nil)
  end,
  ticks = function()
    H.at(2, function()
      local surface = vulcanus()
      for _, key in pairs({ "lava_chunk", "rock_chunk" }) do
        local c = vibration_test[key]
        surface.pollute({ c.x * 32 + 16, c.y * 32 + 16 }, 1000)
        vibration_test[key .. "_start"] = surface.get_pollution({ c.x * 32 + 16, c.y * 32 + 16 })
      end
    end)
    H.at(1800, function()
      local surface = vulcanus()
      local stats = game.get_pollution_statistics(surface)
      local emitted = stats.get_input_count("burner-mining-drill")
      H.check("drill-emits-vibration", emitted > 0, string.format("%.2f emitted", emitted))
      local function left(key)
        local c = vibration_test[key]
        return surface.get_pollution({ c.x * 32 + 16, c.y * 32 + 16 })
      end
      local lava, rock = left("lava_chunk"), left("rock_chunk")
      H.info("after-30s", string.format("lava chunk %.1f, rock chunk %.1f (from %.0f)", lava, rock, vibration_test.lava_chunk_start))
      H.check("lava-chunk-absorbs-faster", lava < rock)
      H.check("rock-absorbs", rock < vibration_test.rock_chunk_start)
      H.done()
    end)
  end,
}

-- vibration-investigate: loud vibration in a territory chunk draws its demolisher.
local inv = {}
phases["vibration-investigate-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    vibration_check_interval = 1000000, -- driven by run_event only
    vibration_investigate_threshold = 20,
    vibration_investigate_cooldown = 1000000,
  },
  init = function()
    local surface = vulcanus()
    -- A demolisher and an explored chunk of its territory 100+ tiles from its head.
    for _, unit in pairs(surface.get_segmented_units()) do
      local head = unit.get_body_nodes()[1]
      for _, c in pairs(unit.territory.get_chunks()) do
        local centre = { x = c.x * 32 + 16, y = c.y * 32 + 16 }
        if not inv.unit and surface.is_chunk_generated(c) and coil_dist(head, centre) > 100 then
          inv.unit, inv.chunk, inv.centre = unit, c, centre
        end
      end
    end
    H.check("found-target", inv.unit ~= nil)
    inv.start_distance = coil_dist(inv.unit.get_body_nodes()[1], inv.centre)
    surface.pollute(inv.centre, 10)
    H.equal("quiet-chunk-ignored", run("vibration"), 0)
    surface.pollute(inv.centre, 500)
    H.equal("loud-chunk-draws-investigation", run("vibration"), 1)
    local ai = inv.unit.get_ai_state()
    H.check("investigating", ai.type == defines.segmented_unit_ai_state.investigating)
    H.check("toward-loud-chunk", ai.destination and coil_dist(ai.destination, inv.centre) < 1, serpent.line(ai.destination))
    H.equal("not-resent-while-investigating", run("vibration"), 0)
    -- Something of the player's at the spot, to see what the demolisher does there.
    inv.target = surface.create_entity({ name = "stone-wall", position = surface.find_non_colliding_position("stone-wall", inv.centre, 10, 1), force = "player" })
    H.info("start", string.format("%.0f tiles away", inv.start_distance))
  end,
  ticks = function()
    local function report()
      if inv.reported then return end
      local d = coil_dist(inv.unit.get_body_nodes()[1], inv.centre)
      local state = inv.unit.get_ai_state().type
      local names = {}
      for k, v in pairs(defines.segmented_unit_ai_state) do names[v] = k end
      if d < 30 and not inv.arrived then
        inv.arrived = H.phase_tick()
        H.info("arrived", "at phase tick " .. inv.arrived .. ", state " .. names[state])
      end
      if inv.arrived and H.phase_tick() >= inv.arrived + 600 then
        inv.reported = true
        H.info("after-arrival", "state " .. names[state] .. ", wall " .. (inv.target.valid and ("health " .. inv.target.health) or "destroyed"))
        H.check("attacks-player-building-at-source", not inv.target.valid)
        H.check("reached-loud-chunk", true)
        vulcanus().pollute(inv.centre, 500)
        H.equal("cooldown-stops-repeat", run("vibration"), 0)
        remote.call(MOD, "set_tuning", { vibration_investigate_cooldown = 0 })
        H.equal("repeats-after-cooldown", run("vibration"), 1)
        H.equal("investigations-counted", state_stats().investigations, 2)
        H.done()
      elseif H.phase_tick() > 7900 then
        inv.reported = true
        H.check("reached-loud-chunk", false, string.format("still %.0f tiles away", d))
        H.done()
      end
    end
    for offset = 30, 8000, 30 do H.at(offset, report) end
  end,
}

-- no-enemies: a new game in no-enemies mode. Vulcanus has territories but no demolishers; the mod
-- warns, stays inert, and starts working when no-enemies mode is turned off.
phases["no-enemies-add"] = {
  tuning = {},
  init = function()
    local record, s = setup_record(), state()
    H.check("vulcanus-in-no-enemies-mode", vulcanus().no_enemies_mode)
    H.equal("no-demolishers", #vulcanus().get_segmented_units(), 0)
    H.check("has-territories", record.territory_count > 0, record.territory_count .. " territories")
    H.check("warned", s.warned_no_enemies)
    H.check("reports-inert", s.no_enemies)
    H.equal("territories-left-alone", #vulcanus().get_territories(), record.territory_count)
    H.equal("nothing-cleared", s.cleared_chunk_count, 0)
  end,
  ticks = function()
    H.at(600, function()
      local s = state()
      H.equal("no-events-while-inert", s.stats.expansion_attempts + s.stats.growth_attempts + s.stats.nest_attempts
        + s.stats.hatch_attempts + s.stats.vibration_attempts, 0)
      H.equal("territories-still-there", #vulcanus().get_territories(), setup_record().territory_count)
      vulcanus().no_enemies_mode = false
    end)
    H.at(700, function()
      local s = state()
      H.check("warning-cleared", not s.warned_no_enemies)
      H.check("no-longer-inert", not s.no_enemies)
      H.equal("empty-territories-cleared-on-resume", #vulcanus().get_territories(), 0)
      H.check("clocks-running", s.stats.expansion_attempts > 0)
      H.done()
    end)
  end,
}

-- ping-turret: a ping turret 80 tiles from a demolisher pings it slowly, and the demolisher comes
-- after the turret.
local ping = { hits = 0 }
phases["ping-turret-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    vibration_check_interval = 1000000,
  },
  init = function()
    local surface = vulcanus()
    local unit = surface.get_segmented_units()[1]
    local head = unit.get_body_nodes()[1]
    local spot = surface.find_non_colliding_position("demolisher-ping-turret", { head.x + 80, head.y }, 20, 1)
    local turret = surface.create_entity({ name = "demolisher-ping-turret", position = spot, force = "player", raise_built = true })
    H.check("placed-turret", turret ~= nil)
    ping.turret = turret
    ping.start = coil_dist(head, turret.position)
    H.equal("no-priority-list-by-default", #(turret.priority_targets or {}), 0)
    H.check("shoots-any-target-by-default", not turret.ignore_unprioritised_targets)
    for _, head in pairs({ "small-demolisher", "medium-demolisher", "big-demolisher" }) do
      local p = prototypes.entity[head]
      H.check("head-pickable-" .. head, p and not p.hidden and p.subgroup.name == "enemies")
    end
    turret.insert({ name = "demolisher-ping-shell", count = 10 })
    H.info("start", string.format("turret %.0f tiles from the demolisher's head", ping.start))
    local tech = game.forces.player.technologies["demolisher-ping-turret"]
    H.check("tech-needs-metallurgic", tech and tech.prerequisites["metallurgic-science-pack"] ~= nil)
    H.check("turret-uses-tungsten", prototypes.recipe["demolisher-ping-turret"].ingredients[2].name == "tungsten-plate")
  end,
  ticks = function()
    script.on_event(defines.events.on_segmented_unit_damaged, function(event)
      -- Follow whichever demolisher the turret picks.
      if event.cause and event.cause.unit_number == ping.turret.unit_number then
        if not ping.target then
          ping.target = event.segmented_unit
          ping.target_start = coil_dist(event.segmented_unit.get_body_nodes()[1], ping.turret.position)
          H.info("pinged-demolisher", event.segmented_unit.prototype.name .. string.format(", %.0f tiles away", ping.target_start))
        end
        ping.hits = ping.hits + 1
        ping.first_hit = ping.first_hit or H.phase_tick()
        ping.damage = event.final_damage_amount
      end
    end)
    local names = {}
    for k, v in pairs(defines.segmented_unit_ai_state) do names[v] = k end
    local function poll()
      if ping.finished then return end
      local t = H.phase_tick()
      local ai = ping.target and ping.target.valid and ping.target.get_ai_state()
      if ai and not ping.lured and (ai.type == defines.segmented_unit_ai_state.enraged_at_target or ai.type == defines.segmented_unit_ai_state.attacking)
        and ai.target == ping.turret then
        ping.lured = t
        H.info("lured", "at phase tick " .. t .. ", state " .. names[ai.type])
      end
      if t >= 3000 then
        ping.finished = true
        H.check("pinged", ping.first_hit ~= nil and ping.first_hit <= 1900, "first hit at " .. tostring(ping.first_hit))
        H.check("light-damage", (ping.damage or 0) > 0 and (ping.damage or 0) <= 20, "damage per hit " .. tostring(ping.damage))
        local used = 10 - ping.turret.get_item_count("demolisher-ping-shell")
        H.check("fires-slowly", used >= 1 and used <= 3, used .. " shells in 50 s")
        H.check("demolisher-comes-for-turret", ping.lured ~= nil)
        local start = ping.target_start or 0
        local now = (ping.target and ping.target.valid) and coil_dist(ping.target.get_body_nodes()[1], ping.turret.position) or start
        H.info("distance", string.format("%.0f -> %.0f tiles; turret %s", start, now, ping.turret.valid and ("health " .. ping.turret.health) or "destroyed"))
        H.check("demolisher-approaches", now < start - 20 or not ping.turret.valid)
        H.done()
      end
    end
    for offset = 30, 3000, 30 do H.at(offset, poll) end
  end,
}

-- ping-turret-filter: priority targets by head size. Listing only big demolishers (none nearby)
-- keeps it quiet; listing small demolishers makes it ping one.
local pf = {}
phases["ping-turret-filter-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    vibration_check_interval = 1000000,
  },
  init = function()
    local surface = vulcanus()
    local small
    for _, unit in pairs(surface.get_segmented_units()) do
      if unit.prototype.name == "small-demolisher" then small = small or unit end
    end
    local head = small.get_body_nodes()[1]
    local spot = surface.find_non_colliding_position("demolisher-ping-turret", { head.x + 70, head.y }, 20, 1)
    pf.turret = surface.create_entity({ name = "demolisher-ping-turret", position = spot, force = "player", raise_built = true })
    pf.turret.set_priority_target(1, "big-demolisher")
    pf.turret.ignore_unprioritised_targets = true
    pf.turret.insert({ name = "demolisher-ping-shell", count = 10 })
    pf.hits = {}
  end,
  ticks = function()
    script.on_event(defines.events.on_segmented_unit_damaged, function(event)
      if event.cause and event.cause.unit_number == pf.turret.unit_number then
        local name = event.segmented_unit.prototype.name
        pf.hits[name] = (pf.hits[name] or 0) + 1
      end
    end)
    H.at(2400, function()
      H.equal("big-only-filter-stays-quiet", table_size(pf.hits), 0)
      H.equal("no-shells-used-while-filtered-out", pf.turret.get_item_count("demolisher-ping-shell"), 10)
      pf.turret.set_priority_target(1, "small-demolisher")
    end)
    H.at(4800, function()
      local others = 0
      for name, n in pairs(pf.hits) do if name ~= "small-demolisher" then others = others + n end end
      H.check("small-filter-pings-small", (pf.hits["small-demolisher"] or 0) > 0, serpent.line(pf.hits))
      H.equal("small-filter-pings-nothing-else", others, 0)
      H.done()
    end)
  end,
}

-- expansion-weighting: a hole at a territory's centre fills before a gap at its edge.
local ew = { hole = 0, edge = 0 }
phases["expansion-weighting-add"] = {
  init = function()
    local surface = vulcanus()
    -- The territory with the most explored chunks.
    local territory, count
    for _, t in pairs(surface.get_territories()) do
      local n = 0
      for _, c in pairs(t.get_chunks()) do if surface.is_chunk_generated(c) then n = n + 1 end end
      if not count or n > count then territory, count = t, n end
    end
    local chunks = territory.get_chunks()
    local sx, sy, n = 0, 0, 0
    for _, c in pairs(chunks) do sx, sy, n = sx + c.x, sy + c.y, n + 1 end
    local cx, cy = sx / n, sy / n
    local near, far, nd, fd
    for _, c in pairs(chunks) do
      if surface.is_chunk_generated(c) then
        local d = math.sqrt((c.x - cx) ^ 2 + (c.y - cy) ^ 2)
        -- The far chunk must stay next to the territory once removed: keep only edge chunks.
        if not nd or d < nd then near, nd = c, d end
        if not fd or d > fd then far, fd = c, d end
      end
    end
    H.info("chunks", string.format("hole %.1f, edge %.1f chunks from the centre", nd, fd))
    for _ = 1, 30 do
      surface.set_territory_for_chunks({ near, far }, nil)
      local taken
      for _ = 1, 200 do
        run("expansion")
        local h, e = surface.get_territory_for_chunk(near) ~= nil, surface.get_territory_for_chunk(far) ~= nil
        if h or e then taken = h and "hole" or "edge"; break end
      end
      if taken then ew[taken] = ew[taken] + 1 end
      surface.set_territory_for_chunks({ near, far }, territory)
    end
    H.info("results", serpent.line(ew))
    H.check("prefers-hole-near-centre", ew.hole >= 24, ew.hole .. " of 30")
    H.done()
  end,
}

-- wreck: territory growing over player buildings sends the demolisher to wreck them, including
-- buildings that make no vibration.
local wk = {}
phases["wreck-add"] = {
  tuning = {
    expansion_enabled = false, growth_enabled = false, nest_enabled = false, hatch_enabled = false,
    vibration_check_interval = 300,
  },
  init = function()
    local surface = vulcanus()
    -- A demolisher B whose explored land borders A's; kill B, build on its land next to A.
    for _, b in pairs(surface.get_segmented_units()) do
      if not wk.spot then
        for _, c in pairs(b.territory.get_chunks()) do
          if not wk.spot and surface.is_chunk_generated(c) then
            for _, d in pairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local t = surface.get_territory_for_chunk({ c.x + d[1], c.y + d[2] })
              if t and #t.get_segmented_units() > 0 and t.get_segmented_units()[1].unit_number ~= b.unit_number then
                wk.spot, wk.victim, wk.owner = c, b, t.get_segmented_units()[1]
                break
              end
            end
          end
        end
      end
    end
    H.check("found-border", wk.spot ~= nil)
    wk.victim.die()
    local centre = { x = wk.spot.x * 32 + 16, y = wk.spot.y * 32 + 16 }
    wk.buildings = {}
    for _, name in ipairs({ "stone-wall", "stone-wall", "wooden-chest", "small-electric-pole", "solar-panel" }) do
      local p = surface.find_non_colliding_position(name, centre, 12, 1)
      wk.buildings[#wk.buildings + 1] = surface.create_entity({ name = name, position = p, force = "player" })
    end
    H.info("owner", wk.owner.prototype.name .. string.format(", head %.0f tiles away", coil_dist(wk.owner.get_body_nodes()[1], centre)))
  end,
  ticks = function()
    local function poll()
      if wk.finished then return end
      local t = H.phase_tick()
      local surface = vulcanus()
      if not wk.taken then
        for _ = 1, 400 do
          if surface.get_territory_for_chunk(wk.spot) ~= nil then break end
          run("expansion")
        end
        local territory = surface.get_territory_for_chunk(wk.spot)
        H.check("chunk-taken", territory ~= nil)
        wk.owner = territory.get_segmented_units()[1]
        wk.taken = t
        H.equal("queued-for-wrecking", state_stats().chunks_with_buildings_taken, 1)
        return
      end
      local alive = 0
      for _, e in pairs(wk.buildings) do if e.valid then alive = alive + 1 end end
      if alive == 0 or t > 14000 then
        wk.finished = true
        H.equal("all-buildings-wrecked", alive, 0)
        H.check("sent-by-mod", state_stats().wreck_dispatches >= 1, state_stats().wreck_dispatches .. " dispatches")
        H.info("time", "wrecked by phase tick " .. t)
        H.done()
      end
    end
    for offset = 30, 14500, 30 do H.at(offset, poll) end
  end,
}

---------------------------------------------------------------------------------------------------
-- killed: demolishers were killed before the mod was added.

phases["killed-add"] = {
  init = function()
    local record = setup_record()
    local s = state()
    local total = 0
    H.check("initialized", s.initialized)
    H.equal("dead-territories-cleared", s.stats.territories_cleared, #record.killed)
    H.equal("no-dead-territories-left", dead_territories(), 0)
    H.equal("territory-count", #vulcanus().get_territories(), record.territory_count - #record.killed)
    for i, killed in ipairs(record.killed) do
      H.equal("killed-" .. i .. "-chunks-free", chunks_with_territory(killed.generated), 0)
      total = total + #killed.generated + #killed.ungenerated
    end
    H.equal("dead-territories-marked-cleared", s.cleared_chunk_count, total)
    H.equal("living-demolishers-untouched", #vulcanus().get_segmented_units(), record.unit_count)
  end,
  ticks = function()
    local all, ungenerated = {}, {}
    H.at(1, function()
      for _, killed in ipairs(setup_record().killed) do
        for _, c in ipairs(killed.generated) do all[#all + 1] = c end
        for _, c in ipairs(killed.ungenerated) do
          all[#all + 1] = c
          ungenerated[#ungenerated + 1] = c
        end
      end
      H.info("cleared-chunks", #all .. " (" .. #ungenerated .. " ungenerated)")
    end)
    H.at(3500, function()
      local s = state()
      H.info("stats", s.stats)
      H.equal("all-cleared-land-taken", chunks_with_territory(all), #all)
      H.equal("no-cleared-chunks-left", s.cleared_chunk_count, 0)
      local still_ungenerated = 0
      for _, c in ipairs(ungenerated) do
        if not vulcanus().is_chunk_generated(c) then still_ungenerated = still_ungenerated + 1 end
      end
      H.equal("ungenerated-chunks-taken-unexplored", still_ungenerated, #ungenerated)
      generate(ungenerated)
    end)
    H.at(3501, function()
      local record = setup_record()
      H.equal("exploring-taken-land-keeps-territory", chunks_with_territory(ungenerated), #ungenerated)
      H.equal("no-new-demolishers", #vulcanus().get_segmented_units(), record.unit_count)
      H.equal("no-new-territories", #vulcanus().get_territories(), record.territory_count - #record.killed)
      H.equal("no-dead-territories", dead_territories(), 0)
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------

local phase = phases[H.phase]
if not phase then
  error("demolisher-lifecycle-test-checks: no checks for phase " .. tostring(H.phase))
end
if phase.ticks then phase.ticks() end
script.on_init(function()
  -- Phases test one behaviour at a time: unless a phase sets `tuning`, growth, nesting and
  -- hatching are off so they can't change unit counts or territories under the other checks.
  remote.call(MOD, "set_tuning", phase.tuning or { growth_enabled = false, nest_enabled = false, hatch_enabled = false })
  if phase.init then phase.init() end
end)
if phase.setting_changed then
  script.on_event(defines.events.on_runtime_mod_setting_changed, phase.setting_changed)
end
