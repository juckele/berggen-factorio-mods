-- Vulcanus Demolisher Lifecycle
--
-- storage layout (schema 3):
--   storage.schema        integer, bumped when the layout changes
--   storage.vulcanus      nil until Vulcanus exists, then:
--     surface_index       index of the tracked Vulcanus surface
--     initialized_tick    tick the mod first set up on this surface
--     safe_chunks         set of "x,y" chunk keys forming the original safe starting area
--     safe_chunk_count    number of entries in safe_chunks
--     safe_candidates     set of "x,y" keys of ungenerated chunks still to be decided
--     cleared_chunks      map of "x,y" key -> chunk position: land of dead territories that living
--                         territories can expand into. Includes ungenerated chunks.
--     cleared_chunk_count number of entries in cleared_chunks
--     reserved            map of "x,y" key -> nest id: nest chunks that expansion skips while the
--                         nest has eggs, so a hatchling always has its chunk
--   storage.pending       territories to re-check after a demolisher died, keyed by unit_number
--   storage.next_event    map of event name -> tick of its next attempt
--   storage.last_event    map of event name -> tick of its last attempt
--   storage.trips         map of unit_number -> nesting trip in progress
--   storage.nests         map of nest id -> nest (site, parent, eggs)
--   storage.egg_registrations map of on_object_destroyed registration number -> {nest, egg}
--   storage.retry_after   map of unit_number -> tick before which that demolisher won't nest again
--   storage.last_investigation map of unit_number -> tick it was last sent after vibration
--   storage.wreck         map of unit_number -> {chunk key -> {chunk, visits}}: chunks with player
--                         buildings its territory took, to send it to
--   storage.tuning        overrides for tuning.lua, set through the remote interface
--   storage.stats         counters, exposed through the remote interface for tests and other mods

local tuning = require("tuning")
local coil = require("coil")
local T = tuning.get
local dist = coil.dist

local SURFACE_NAME = "vulcanus"
local SCHEMA = 3
local EVENTS = { "expansion", "growth", "nest", "hatch" }

local SETTING_PROTECT = "demolisher-lifecycle-protect-starting-area"
local SETTING_INTERVAL = "demolisher-lifecycle-expansion-interval-ticks"
local SETTING_DEBUG = "demolisher-lifecycle-debug-log"

-- How far from the map origin (in chunks) to look for the starting area. Vulcanus puts its
-- starting area disc 100 * starting_area_radius + 32 tiles from the origin with a 224 tile radius.
local SAFE_ZONE_SCAN_RADIUS = 24
-- Growth looks at this many random demolishers per event.
local GROWTH_SAMPLES = 8

local AI = defines.segmented_unit_ai_state

local function debug_log(message)
  if settings.global[SETTING_DEBUG].value then
    log(message)
  end
end

local function chunk_key(chunk)
  return chunk.x .. "," .. chunk.y
end

local function chunk_centre(chunk)
  return { x = chunk.x * 32 + 16, y = chunk.y * 32 + 16 }
end

local function chunk_of(position)
  return { x = math.floor(position.x / 32), y = math.floor(position.y / 32) }
end

local function new_stats()
  return {
    territories_cleared = 0,
    chunks_cleared = 0,
    expansions = 0,
    cleared_chunks_taken = 0,
    expansions_blocked_by_safe_zone = 0,
    expansion_attempts = 0,
    growth_attempts = 0,
    growths = 0,
    nest_attempts = 0,
    trips_started = 0,
    trips_aborted = 0,
    nests_built = 0,
    eggs_laid = 0,
    hatch_attempts = 0,
    eggs_hatched = 0,
    hatched_dead_parent = 0,
    hatched_free_space = 0,
    hatched_old = 0,
    eggs_destroyed = 0,
    vibration_attempts = 0,
    investigations = 0,
    chunks_with_buildings_taken = 0,
    wreck_dispatches = 0,
    hatch_alerts = 0,
  }
end

local function stat(name, amount)
  storage.stats[name] = (storage.stats[name] or 0) + (amount or 1)
end

local function setup_storage()
  -- Keys left behind by 0.1.
  storage.on_init_run_before = nil
  storage.on_tick_run_before = nil
  storage.vulcanus_is_initialized = nil
  storage.schema = SCHEMA
  storage.pending = storage.pending or {}
  storage.stats = storage.stats or new_stats()
  for key, value in pairs(new_stats()) do
    if storage.stats[key] == nil then storage.stats[key] = value end
  end
  local v = storage.vulcanus
  if v and not v.cleared_chunks then
    -- 0.2.0 didn't mark cleared land, so land it cleared can't be expanded into.
    v.cleared_chunks = {}
    v.cleared_chunk_count = 0
  end
  if v and not v.reserved then v.reserved = {} end
  storage.next_event = storage.next_event or {}
  storage.last_event = storage.last_event or {}
  -- Schema 2 had a single expansion clock.
  if storage.next_expansion_tick then
    storage.next_event.expansion = storage.next_expansion_tick
    storage.last_event.expansion = storage.last_expansion_tick
    storage.next_expansion_tick = nil
    storage.last_expansion_tick = nil
  end
  storage.trips = storage.trips or {}
  storage.nests = storage.nests or {}
  storage.next_nest_id = storage.next_nest_id or 1
  storage.egg_registrations = storage.egg_registrations or {}
  storage.retry_after = storage.retry_after or {}
end

local function tracked_surface()
  local v = storage.vulcanus
  if not v then return nil end
  local surface = game.surfaces[v.surface_index]
  if surface and surface.valid then return surface end
  return nil
end

---------------------------------------------------------------------------------------------------
-- Event clocks

-- Vanilla's biter expansion cooldown on the map's settings, times the event's scale. Evolution on
-- Vulcanus rises with time and vibration, which is how vibration speeds every event up.
local function event_cooldown(surface, event)
  local override = settings.global[SETTING_INTERVAL].value
  if override > 0 then return override end
  local config = game.map_settings.enemy_expansion
  local e = game.forces.enemy.get_evolution_factor(surface)
  local t = -e * e + 2 * e
  local scale = T(event .. "_scale")
  local max = config.max_expansion_cooldown * scale
  local min = config.min_expansion_cooldown * scale
  local cooldown = max + (min - max) * t
  return math.max(1, math.floor(cooldown + 0.5))
end

local function schedule_all(surface)
  for _, event in ipairs(EVENTS) do
    storage.next_event[event] = game.tick + event_cooldown(surface, event)
  end
end

-- The mod needs enemy expansion. Say so once each time it is found turned off.
-- No-enemies mode on Vulcanus (inherited from the new-game settings) leaves every territory
-- without a demolisher, so the mod stays inert there instead of clearing them all.
local function inert(surface)
  return surface.no_enemies_mode
end

-- The mod needs enemy expansion and enemies. Say so once each time either is found missing.
-- Defined before the lifecycle code, which provides on_resume.
local function check_settings(on_resume)
  local surface = tracked_surface()
  if not surface then return end
  if game.map_settings.enemy_expansion.enabled then
    storage.warned_expansion_disabled = nil
  elseif not storage.warned_expansion_disabled then
    storage.warned_expansion_disabled = true
    game.print({ "vulcanus-demolisher-lifecycle.enemy-expansion-disabled" })
  end
  if inert(surface) then
    if not storage.warned_no_enemies then
      storage.warned_no_enemies = true
      game.print({ "vulcanus-demolisher-lifecycle.no-enemies" })
    end
  elseif storage.warned_no_enemies then
    storage.warned_no_enemies = nil
    if on_resume then on_resume(surface) end
  end
end

---------------------------------------------------------------------------------------------------
-- Safe starting area

-- The safe zone is recorded once per Vulcanus surface, whether or not protection is enabled, so
-- that turning protection on later has something to protect. A chunk is a candidate if it is in or
-- next to the map generator's starting-area disc. A candidate is safe once it is generated and
-- holds no territory: generated chunks are decided now (so a save that already lost part of its
-- starting area keeps what is left, and nothing is evicted), ungenerated candidates are decided by
-- on_chunk_generated, after the map generator has assigned their territory.
local function record_safe_zone(surface)
  local positions = {}
  local sample_offsets = { { 16, 16 }, { 1, 1 }, { 31, 1 }, { 1, 31 }, { 31, 31 } }
  for cx = -SAFE_ZONE_SCAN_RADIUS, SAFE_ZONE_SCAN_RADIUS do
    for cy = -SAFE_ZONE_SCAN_RADIUS, SAFE_ZONE_SCAN_RADIUS do
      for _, o in ipairs(sample_offsets) do
        positions[#positions + 1] = { cx * 32 + o[1], cy * 32 + o[2] }
      end
    end
  end
  local values = surface.calculate_tile_properties({ "demolisher_starting_area" }, positions)["demolisher_starting_area"]

  local in_disc = {}
  local per_chunk = #sample_offsets
  for i = 1, #positions, per_chunk do
    for j = i, i + per_chunk - 1 do
      if values[j] > 0 then
        in_disc[chunk_key({ x = math.floor(positions[i][1] / 32), y = math.floor(positions[i][2] / 32) })] = true
        break
      end
    end
  end

  local safe, count, candidates = {}, 0, {}
  for cx = -SAFE_ZONE_SCAN_RADIUS, SAFE_ZONE_SCAN_RADIUS do
    for cy = -SAFE_ZONE_SCAN_RADIUS, SAFE_ZONE_SCAN_RADIUS do
      local chunk = { x = cx, y = cy }
      local key = chunk_key(chunk)
      local near_disc = false
      for dx = -1, 1 do
        for dy = -1, 1 do
          if in_disc[(cx + dx) .. "," .. (cy + dy)] then near_disc = true end
        end
      end
      if near_disc and surface.get_territory_for_chunk(chunk) == nil then
        if surface.is_chunk_generated(chunk) then
          safe[key] = true
          count = count + 1
        else
          candidates[key] = true
        end
      end
    end
  end
  return safe, count, candidates
end

local function on_chunk_generated(event)
  local v = storage.vulcanus
  if not v or event.surface.index ~= v.surface_index then return end
  local key = chunk_key(event.position)
  if not v.safe_candidates[key] then return end
  v.safe_candidates[key] = nil
  if event.surface.get_territory_for_chunk(event.position) == nil then
    v.safe_chunks[key] = true
    v.safe_chunk_count = v.safe_chunk_count + 1
  end
end

local function is_safe_chunk(chunk)
  local v = storage.vulcanus
  return v ~= nil and v.safe_chunks[chunk_key(chunk)] == true
end

---------------------------------------------------------------------------------------------------
-- Dead territories

-- In vanilla a territory stays after its last demolisher dies. This mod needs that land free so
-- living territories can expand into it, so it removes the territory. LuaTerritory.destroy() would let
-- the map generator create a fresh territory (with a fresh demolisher) on any of its chunks that
-- get generated later, so instead the chunks are set to no territory, which also deletes the
-- territory. The chunks are marked as cleared so living territories can
-- expand into them (see Expansion).
local function mark_cleared(chunk)
  local v = storage.vulcanus
  local key = chunk_key(chunk)
  if not v.cleared_chunks[key] then
    v.cleared_chunks[key] = { x = chunk.x, y = chunk.y }
    v.cleared_chunk_count = v.cleared_chunk_count + 1
  end
end

local function unmark_cleared(key)
  local v = storage.vulcanus
  if v.cleared_chunks[key] then
    v.cleared_chunks[key] = nil
    v.cleared_chunk_count = v.cleared_chunk_count - 1
  end
end

local function clear_territory(surface, territory)
  local chunks = territory.get_chunks()
  surface.set_territory_for_chunks(chunks, nil)
  for _, chunk in pairs(chunks) do mark_cleared(chunk) end
  stat("territories_cleared")
  stat("chunks_cleared", #chunks)
  debug_log("Cleared a territory of " .. #chunks .. " chunks")
end

local function clear_dead_territories(surface)
  for _, territory in pairs(surface.get_territories()) do
    if territory.valid and #territory.get_segmented_units() == 0 then
      clear_territory(surface, territory)
    end
  end
end

local function queue_territory_check(segmented_unit)
  local surface = tracked_surface()
  if not surface or not segmented_unit.valid or segmented_unit.surface ~= surface then return end
  local territory = segmented_unit.territory
  if not territory or not territory.valid then return end
  -- Keep the territory itself: a territory can lie entirely in unexplored chunks, so it can't
  -- always be found again by chunk.
  storage.pending[segmented_unit.unit_number] = territory
end

-- Runs a tick after a death: during on_segmented_unit_died the dying unit is still listed as
-- guarding its territory.
local function process_pending()
  local surface = tracked_surface()
  local pending = storage.pending
  storage.pending = {}
  if not surface then return end
  for _, entry in pairs(pending) do
    local territory = entry
    if type(entry) == "table" and entry.object_name ~= "LuaTerritory" then
      territory = surface.get_territory_for_chunk(entry) -- queued by schema 2, by chunk
    end
    if territory and territory.valid and #territory.get_segmented_units() == 0 then
      clear_territory(surface, territory)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Expansion

local NEIGHBOURS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function has_living_units(territory)
  return territory ~= nil and territory.valid and #territory.get_segmented_units() > 0
end

-- Expansion prefers chunks near the centre of the territory that gains them, so holes and
-- concave edges fill first: weight = exp(-strength * d / r), with d the chunk's distance from
-- the territory's centre and r the territory's mean radius (both in chunks).
local function territory_geometry(territory)
  local chunks = territory.get_chunks()
  local sx, sy, n = 0, 0, 0
  for _, c in pairs(chunks) do sx, sy, n = sx + c.x, sy + c.y, n + 1 end
  if n == 0 then return nil end
  local cx, cy = sx / n, sy / n
  local sum = 0
  for _, c in pairs(chunks) do sum = sum + math.sqrt((c.x - cx) ^ 2 + (c.y - cy) ^ 2) end
  return { x = cx, y = cy, radius = math.max(1, sum / n) }
end

local function expansion_weight(geometry, chunk)
  local d = math.sqrt((chunk.x - geometry.x) ^ 2 + (chunk.y - geometry.y) ^ 2)
  return math.exp(-T("expansion_centre_weight") * d / geometry.radius)
end

local function weighted_pick(candidates)
  local total = 0
  for _, c in ipairs(candidates) do total = total + c.weight end
  if total <= 0 then return candidates[math.random(1, #candidates)] end
  local roll = math.random() * total
  for _, c in ipairs(candidates) do
    roll = roll - c.weight
    if roll <= 0 then return c end
  end
  return candidates[#candidates]
end

-- Defined with the wrecking code below; queues a newly gained chunk that has player buildings.
local on_chunk_gained

-- Expanding into cleared land: a cleared chunk next to a territory with a living demolisher joins that territory. This
-- works on cleared chunks nobody has explored yet, which plain expansion can't see.
local function try_expand_into_cleared(surface, protect)
  local v = storage.vulcanus
  local candidates, blocked, geometry = {}, false, {}
  for key, chunk in pairs(v.cleared_chunks) do
    if v.reserved[key] then
      -- A nest's chunk, kept for its hatchling.
    elseif surface.get_territory_for_chunk(chunk) ~= nil then
      unmark_cleared(key) -- taken some other way
    else
      local seen = {}
      for _, d in ipairs(NEIGHBOURS) do
        local territory = surface.get_territory_for_chunk({ x = chunk.x + d[1], y = chunk.y + d[2] })
        if has_living_units(territory) then
          local number = territory.get_segmented_units()[1].unit_number
          if protect and is_safe_chunk(chunk) then
            blocked = true
          elseif not seen[number] then
            seen[number] = true
            geometry[number] = geometry[number] or territory_geometry(territory)
            candidates[#candidates + 1] = { key = key, chunk = chunk, territory = territory,
              weight = expansion_weight(geometry[number], chunk) }
          end
        end
      end
    end
  end
  if #candidates == 0 then return false, blocked end
  local pick = weighted_pick(candidates)
  surface.set_territory_for_chunks({ pick.chunk }, pick.territory)
  pick.territory.regenerate_patrol_path()
  unmark_cleared(pick.key)
  stat("expansions")
  stat("cleared_chunks_taken")
  debug_log("Territory expanded into cleared chunk " .. pick.key)
  on_chunk_gained(surface, pick.territory, pick.chunk)
  return true, blocked
end

local function expansion_targets(surface, territory, protect)
  local targets, blocked = {}, 0
  for _, chunk in pairs(territory.get_chunks()) do
    for _, d in ipairs(NEIGHBOURS) do
      local n = { x = chunk.x + d[1], y = chunk.y + d[2] }
      if surface.is_chunk_generated(n) and surface.get_territory_for_chunk(n) == nil then
        if protect and is_safe_chunk(n) then
          blocked = blocked + 1
        else
          targets[#targets + 1] = n
        end
      end
    end
  end
  return targets, blocked
end

-- Plain expansion: into a generated neighbouring chunk without territory that was never marked
-- cleared, which in practice means the starting area, so this only finds targets with protection off.
-- Candidates from every territory are weighed together, so a hole in one territory beats a gap at
-- another's edge.
local function try_expand_free_land(surface, protect)
  local candidates, blocked_any = {}, false
  for _, territory in pairs(surface.get_territories()) do
    if #territory.get_segmented_units() > 0 then
      local targets, blocked = expansion_targets(surface, territory, protect)
      if blocked > 0 then blocked_any = true end
      if #targets > 0 then
        local geometry = territory_geometry(territory)
        for _, chunk in ipairs(targets) do
          candidates[#candidates + 1] = { chunk = chunk, territory = territory, weight = expansion_weight(geometry, chunk) }
        end
      end
    end
  end
  if #candidates == 0 then return false, blocked_any end
  local pick = weighted_pick(candidates)
  surface.set_territory_for_chunks({ pick.chunk }, pick.territory)
  pick.territory.regenerate_patrol_path()
  stat("expansions")
  debug_log("Territory expanded into chunk " .. chunk_key(pick.chunk))
  on_chunk_gained(surface, pick.territory, pick.chunk)
  return true, blocked_any
end

local function run_expansion(surface)
  local protect = settings.global[SETTING_PROTECT].value
  local done, blocked = try_expand_into_cleared(surface, protect)
  if not done then
    local blocked_free
    done, blocked_free = try_expand_free_land(surface, protect)
    blocked = blocked or blocked_free
  end
  if not done and blocked then
    stat("expansions_blocked_by_safe_zone")
  end
  return done
end

---------------------------------------------------------------------------------------------------
-- Sizes

local function tier_of(name)
  for i, tier in ipairs(T("tiers")) do
    if tier == name then return i end
  end
  return nil
end

-- Centre of a territory's chunks (may fall outside it for odd shapes).
local function territory_centre(territory)
  local sx, sy, n = 0, 0, 0
  for _, chunk in pairs(territory.get_chunks()) do
    sx, sy, n = sx + chunk.x * 32 + 16, sy + chunk.y * 32 + 16, n + 1
  end
  if n == 0 then return nil end
  return { x = sx / n, y = sy / n }
end

-- The size the map generator would place here (1 = smallest), from the same noise expression.
local function native_tier(surface, position)
  local value = surface.calculate_tile_properties({ "demolisher_variation_expression" },
    { { position.x, position.y } })["demolisher_variation_expression"][1]
  return math.max(1, math.min(#T("tiers"), math.floor(value) + 1))
end

local function head_of(unit)
  return unit.get_body_nodes()[1]
end

local function living_units(surface)
  local units = {}
  for _, unit in pairs(surface.get_segmented_units()) do
    if unit.valid and unit.territory and unit.territory.valid and tier_of(unit.prototype.name) then
      units[#units + 1] = unit
    end
  end
  return units
end

local function territory_chunk_set(territory)
  local set, count = {}, 0
  for _, chunk in pairs(territory.get_chunks()) do
    set[chunk_key(chunk)] = chunk
    count = count + 1
  end
  return set, count
end

---------------------------------------------------------------------------------------------------
-- Growth: a demolisher with a big enough territory grows one size, up to a limit set by distance.

local function sigmoid(x)
  return 1 / (1 + math.exp(-x))
end

local function retarget_nests(old_number, new_unit)
  for _, nest in pairs(storage.nests) do
    if nest.parent_unit_number == old_number then
      nest.parent = new_unit
      nest.parent_unit_number = new_unit.unit_number
    end
  end
end

local function grow(surface, unit, next_name)
  local replacement = surface.create_segmented_unit({
    name = next_name,
    force = unit.force,
    territory = unit.territory,
    body_nodes = unit.get_body_nodes(),
  })
  if not replacement then return false end
  replacement.health = replacement.max_health * unit.health_ratio
  retarget_nests(unit.unit_number, replacement)
  for _, map in pairs({ storage.retry_after, storage.wreck or {}, storage.last_investigation or {} }) do
    map[replacement.unit_number] = map[unit.unit_number]
    map[unit.unit_number] = nil
  end
  unit.destroy()
  stat("growths")
  debug_log("Demolisher grew into " .. next_name)
  return true
end

local function run_growth(surface)
  local units = living_units(surface)
  local tiers = T("tiers")
  for _ = 1, math.min(GROWTH_SAMPLES, #units) do
    local index = math.random(1, #units)
    local unit = units[index]
    table.remove(units, index)
    local tier = tier_of(unit.prototype.name)
    if tier < #tiers and not storage.trips[unit.unit_number] then
      -- Judged at the territory's centre: the map generator sizes a demolisher by its territory.
      local limit = native_tier(surface, territory_centre(unit.territory)) + T("growth_tiers_above_native")
      local next_name = tiers[tier + 1]
      local midpoint = T("growth_midpoint")[next_name]
      if tier + 1 <= limit and midpoint then
        local _, size = territory_chunk_set(unit.territory)
        if math.random() < sigmoid((size - midpoint) / T("growth_width")) then
          return grow(surface, unit, next_name)
        end
      end
    end
  end
  return false
end

---------------------------------------------------------------------------------------------------
-- Nesting: a max-size demolisher with a big territory travels to the territory's centre, coils
-- around the spot, lays a nest of eggs, and returns to its patrol.

local function owns_nest(unit_number)
  for _, nest in pairs(storage.nests) do
    if nest.parent_unit_number == unit_number then return true end
  end
  return false
end

-- Centre of the territory's chunks, snapped to its nearest explored chunk.
local function nest_site(surface, territory)
  local sx, sy, n = 0, 0, 0
  local chunks = territory.get_chunks()
  for _, chunk in pairs(chunks) do
    sx, sy, n = sx + chunk.x, sy + chunk.y, n + 1
  end
  if n == 0 then return nil end
  local cx, cy = sx / n, sy / n
  local best, best_d
  for _, chunk in pairs(chunks) do
    if surface.is_chunk_generated(chunk) then
      local d = (chunk.x - cx) ^ 2 + (chunk.y - cy) ^ 2
      if not best_d or d < best_d then best, best_d = chunk, d end
    end
  end
  if not best then return nil end
  local position = surface.find_non_colliding_position("demolisher-egg", chunk_centre(best), 12, 1)
    or chunk_centre(best)
  return position, best
end

local function nearest_waypoint(unit)
  local head = head_of(unit)
  local best, best_d = 1, nil
  for i, p in ipairs(unit.territory.get_patrol_path()) do
    local d = dist(p, head)
    if not best_d or d < best_d then best, best_d = i, d end
  end
  return best
end

local function release(unit)
  if unit.valid then
    unit.set_ai_state({ type = AI.patrolling, waypoint = nearest_waypoint(unit) })
  end
end

local function end_trip(trip, aborted, reason)
  storage.trips[trip.unit_number] = nil
  if aborted then
    stat("trips_aborted")
    storage.retry_after[trip.unit_number] = game.tick + T("nest_retry_cooldown")
    debug_log("Nesting trip aborted: " .. reason)
  end
end

local function run_nest(surface)
  if table_size(storage.trips) >= T("nest_max_trips") then return false end
  local tiers = T("tiers")
  local max_tier = tiers[#tiers]
  local candidates = {}
  for _, unit in pairs(living_units(surface)) do
    local number = unit.unit_number
    if unit.prototype.name == max_tier and not storage.trips[number] and not owns_nest(number)
      and game.tick >= (storage.retry_after[number] or 0) then
      local _, size = territory_chunk_set(unit.territory)
      if size >= T("nest_min_chunks") then candidates[#candidates + 1] = unit end
    end
  end
  if #candidates == 0 then return false end
  local unit = candidates[math.random(1, #candidates)]
  local site, chunk = nest_site(surface, unit.territory)
  if not site then return false end
  storage.trips[unit.unit_number] = {
    unit = unit,
    unit_number = unit.unit_number,
    site = site,
    chunk = chunk,
    phase = "travel",
    started = game.tick,
    reissues = 0,
  }
  unit.set_ai_state({ type = AI.investigating, destination = site })
  stat("trips_started")
  debug_log("Nesting trip started to " .. chunk_key(chunk))
  return true
end

local function lay_nest(surface, trip)
  local unit = trip.unit
  local id = storage.next_nest_id
  storage.next_nest_id = id + 1
  local marker = surface.create_entity({ name = "demolisher-nest", position = trip.site, force = unit.force })
  if marker then marker.destructible = false end
  local nest = {
    id = id,
    site = trip.site,
    chunk = trip.chunk,
    chunk_key = chunk_key(trip.chunk),
    parent = unit,
    parent_unit_number = unit.unit_number,
    parent_dead = false,
    marker = marker,
    eggs = {},
    next_egg = 1,
  }
  local count = math.random(T("eggs_min"), T("eggs_max"))
  for i = 1, count do
    -- A tight ring inside the coil, clear of the parent's segments.
    local angle = (i / count + math.random() * 0.2) * 2 * math.pi
    local wanted = { x = trip.site.x + 1.5 * math.cos(angle), y = trip.site.y + 1.5 * math.sin(angle) }
    local position = surface.find_non_colliding_position("demolisher-egg", wanted, 3, 0.25) or wanted
    local egg = surface.create_entity({ name = "demolisher-egg", position = position, force = unit.force })
    if egg then
      local egg_id = nest.next_egg
      nest.next_egg = egg_id + 1
      local registration = script.register_on_object_destroyed(egg)
      nest.eggs[egg_id] = { id = egg_id, entity = egg, position = egg.position, laid = game.tick, registration = registration }
      storage.egg_registrations[registration] = { nest = id, egg = egg_id }
      stat("eggs_laid")
    end
  end
  storage.nests[id] = nest
  storage.vulcanus.reserved[nest.chunk_key] = id
  stat("nests_built")
  debug_log("Nest " .. id .. " laid with " .. table_size(nest.eggs) .. " eggs")
end

local function remove_nest_if_empty(nest)
  if next(nest.eggs) then return end
  if nest.marker and nest.marker.valid then nest.marker.destroy() end
  storage.nests[nest.id] = nil
  local v = storage.vulcanus
  if v and v.reserved[nest.chunk_key] == nest.id then v.reserved[nest.chunk_key] = nil end
end

local function update_trip(surface, trip)
  local unit = trip.unit
  if not unit.valid then
    storage.trips[trip.unit_number] = nil
    return
  end
  if trip.phase == "travel" then
    local head = head_of(unit)
    if dist(head, trip.site) <= T("nest_arrive_distance") then
      local nodes = unit.get_body_nodes()
      trip.path, trip.s = coil.coil_path(nodes, trip.site, T("nest_coil_outer_radius"), T("nest_coil_inner_radius"))
      trip.node_count = #nodes
      trip.speed = math.max(unit.speed, T("nest_coil_min_speed"))
      trip.phase = "coil"
      return
    end
    local state = unit.get_ai_state().type
    if state == AI.attacking or state == AI.enraged_at_target or state == AI.enraged_at_nothing then
      end_trip(trip, true, "disturbed while travelling")
    elseif game.tick - trip.started > T("nest_travel_timeout") then
      release(unit)
      end_trip(trip, true, "travel timed out")
    elseif state ~= AI.investigating then
      trip.reissues = trip.reissues + 1
      if trip.reissues > 5 then
        release(unit)
        end_trip(trip, true, "kept losing the way")
      else
        unit.set_ai_state({ type = AI.investigating, destination = trip.site })
      end
    end
  elseif trip.phase == "coil" then
    trip.s = math.min(trip.s + trip.speed, trip.path.length)
    unit.set_body_nodes(coil.nodes_at(trip.path, trip.s, trip.node_count))
    unit.speed = 0
    if trip.s >= trip.path.length then
      trip.phase = "build"
      trip.build_until = game.tick + T("nest_build_ticks")
    end
  elseif trip.phase == "build" then
    unit.speed = 0
    if game.tick >= trip.build_until then
      lay_nest(surface, trip)
      release(unit)
      end_trip(trip, false)
    end
  end
end

local function update_trips(surface)
  for _, trip in pairs(storage.trips) do
    update_trip(surface, trip)
  end
end

---------------------------------------------------------------------------------------------------
-- Hatching: each hatch event picks one egg old enough to hatch, weighted by its situation:
--   parent dead                          -> hatchling takes the nest chunk (highest weight)
--   cleared land next to parent's land   -> hatchling takes the parent chunk next to it
--   egg old and nowhere better to go     -> hatchling takes a parent chunk on the edge (lowest)
-- The hatchling's territory is that one chunk; it grows from there like any other.

local NEIGHBOURS4 = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function nearest_chunk(surface, chunks, position)
  local best, best_d
  for _, chunk in pairs(chunks) do
    if surface.is_chunk_generated(chunk) then
      local d = dist(chunk_centre(chunk), position)
      if not best_d or d < best_d then best, best_d = chunk, d end
    end
  end
  return best
end

-- Parent chunks next to cleared land the parent could expand into.
local function chunks_next_to_free_space(parent_set)
  local v = storage.vulcanus
  local protect = settings.global[SETTING_PROTECT].value
  local result = {}
  for key, chunk in pairs(v.cleared_chunks) do
    if not v.reserved[key] and not (protect and is_safe_chunk(chunk)) then
      for _, d in ipairs(NEIGHBOURS4) do
        local neighbour = parent_set[(chunk.x + d[1]) .. "," .. (chunk.y + d[2])]
        if neighbour then result[#result + 1] = neighbour end
      end
    end
  end
  return result
end

local function edge_chunks(parent_set)
  local result = {}
  for _, chunk in pairs(parent_set) do
    for _, d in ipairs(NEIGHBOURS4) do
      if not parent_set[(chunk.x + d[1]) .. "," .. (chunk.y + d[2])] then
        result[#result + 1] = chunk
        break
      end
    end
  end
  return result
end

-- Weight, child chunk and reason for one nest's eggs right now (the same for all its eggs).
local function hatch_option(surface, nest)
  if nest.parent_dead or not (nest.parent and nest.parent.valid) then
    return T("hatch_weight_dead_parent"), nest.chunk, "dead_parent"
  end
  local territory = nest.parent.territory
  if not (territory and territory.valid) then return 0 end
  local parent_set, size = territory_chunk_set(territory)
  if size <= 1 then return 0 end
  local free = chunks_next_to_free_space(parent_set)
  if #free > 0 then
    local chunk = nearest_chunk(surface, free, nest.site)
    if chunk then return T("hatch_weight_free_space"), chunk, "free_space" end
  end
  local chunk = nearest_chunk(surface, edge_chunks(parent_set), nest.site)
  if chunk then return T("hatch_weight_old"), chunk, "old" end
  return 0
end

local function hatch(surface, nest, egg, chunk, reason)
  local v = storage.vulcanus
  local key = chunk_key(chunk)
  local territory = surface.create_territory({ chunks = { chunk } })
  if not territory then return false end
  if v.cleared_chunks[key] then unmark_cleared(key) end
  if reason ~= "dead_parent" and nest.parent.valid and nest.parent.territory.valid then
    nest.parent.territory.regenerate_patrol_path()
  end
  local child = surface.create_segmented_unit({
    name = T("tiers")[1],
    force = nest.parent.valid and nest.parent.force or "enemy",
    territory = territory,
    position = egg.position,
  })
  if child then
    child.set_body_nodes(coil.curl(egg.position, child.max_body_nodes))
    -- It owns its chunk straight away and finds its own way there along its patrol route.
    child.set_ai_state({ type = AI.patrolling, waypoint = 1 })
    -- Like a new biter base: the game's expansion alert, for forces with radar coverage there.
    local head = child.segments[1] and child.segments[1].entity
    if head then
      for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral"
          and force.is_chunk_visible(surface, chunk_of(egg.position)) then
          force.add_alert(head, defines.alert_type.expansion_base_built)
          stat("hatch_alerts")
        end
      end
    end
  else
    territory.destroy()
    return false
  end
  storage.egg_registrations[egg.registration] = nil
  nest.eggs[egg.id] = nil
  if egg.entity.valid then egg.entity.destroy() end
  remove_nest_if_empty(nest)
  stat("eggs_hatched")
  stat("hatched_" .. reason)
  debug_log("Egg hatched (" .. reason .. ") into chunk " .. key)
  return true
end

local function run_hatch(surface)
  local options, total = {}, 0
  for _, nest in pairs(storage.nests) do
    local weight, chunk, reason = hatch_option(surface, nest)
    if weight > 0 then
      for _, egg in pairs(nest.eggs) do
        local age = game.tick - egg.laid
        if egg.entity.valid and age >= T("egg_min_age") and (reason ~= "old" or age >= T("egg_old_age")) then
          options[#options + 1] = { nest = nest, egg = egg, chunk = chunk, reason = reason, weight = weight }
          total = total + weight
        end
      end
    end
  end
  if total == 0 then return false end
  local roll = math.random() * total
  for _, option in ipairs(options) do
    roll = roll - option.weight
    if roll <= 0 then
      return hatch(surface, option.nest, option.egg, option.chunk, option.reason)
    end
  end
  local last = options[#options]
  return hatch(surface, last.nest, last.egg, last.chunk, last.reason)
end

local function on_object_destroyed(event)
  local ref = storage.egg_registrations[event.registration_number]
  if not ref then return end
  storage.egg_registrations[event.registration_number] = nil
  local nest = storage.nests[ref.nest]
  if not nest or not nest.eggs[ref.egg] then return end
  nest.eggs[ref.egg] = nil
  stat("eggs_destroyed")
  remove_nest_if_empty(nest)
end

local function on_unit_gone(unit)
  if not unit.valid then return end
  local number = unit.unit_number
  if storage.trips[number] then storage.trips[number] = nil end
  for _, nest in pairs(storage.nests) do
    if nest.parent_unit_number == number then nest.parent_dead = true end
  end
end

---------------------------------------------------------------------------------------------------
-- Vibration: a demolisher investigates the loudest chunk of its territory once the vibration
-- there passes a threshold, the way vanilla demolishers investigate a disturbance.

local function busy(unit)
  local state = unit.get_ai_state().type
  return state == AI.attacking or state == AI.enraged_at_target or state == AI.enraged_at_nothing
    or state == AI.investigating or storage.trips[unit.unit_number] ~= nil
end

-- Wrecking: when a territory gains a chunk with player buildings, its demolisher is sent there
-- (and sent again, while it has nothing else to do) until nothing of the player's is left. Vanilla
-- demolishers only react to buildings placed in their territory, not to territory growing over
-- existing ones, and sleep when no player is near.

local function player_forces()
  local names = {}
  for _, force in pairs(game.forces) do
    if force.name ~= "enemy" and force.name ~= "neutral" then names[#names + 1] = force.name end
  end
  return names
end

-- A player entity in the chunk that a demolisher can go after (not a ghost), or nil.
local function player_target_in(surface, chunk)
  local area = { { chunk.x * 32, chunk.y * 32 }, { chunk.x * 32 + 32, chunk.y * 32 + 32 } }
  for _, entity in pairs(surface.find_entities_filtered({ area = area, force = player_forces(), limit = 20 })) do
    if entity.type ~= "entity-ghost" and entity.type ~= "tile-ghost" and entity.destructible then
      return entity
    end
  end
  return nil
end

on_chunk_gained = function(surface, territory, chunk)
  if not player_target_in(surface, chunk) then return end
  local unit = territory.get_segmented_units()[1]
  if not unit then return end
  storage.wreck = storage.wreck or {}
  local queue = storage.wreck[unit.unit_number] or {}
  storage.wreck[unit.unit_number] = queue
  queue[chunk_key(chunk)] = { chunk = { x = chunk.x, y = chunk.y }, visits = 0 }
  stat("chunks_with_buildings_taken")
  debug_log("Territory took chunk " .. chunk_key(chunk) .. " with player buildings")
end

-- Sends demolishers after queued chunks. Returns the set of unit numbers it sent.
local function run_wreck_dispatch(surface)
  local sent = {}
  if not storage.wreck then return sent end
  for number, queue in pairs(storage.wreck) do
    local unit, best, best_entry, best_key, best_d
    for key, entry in pairs(queue) do
      local territory = surface.get_territory_for_chunk(entry.chunk)
      local owner = territory and territory.get_segmented_units()[1]
      local target = owner and owner.unit_number == number and player_target_in(surface, entry.chunk)
      if not target or entry.visits >= T("wreck_max_visits") then
        queue[key] = nil
      else
        unit = owner
        local d = dist(head_of(owner), target.position)
        if not best_d or d < best_d then best, best_entry, best_key, best_d = target, entry, key, d end
      end
    end
    if not next(queue) then
      storage.wreck[number] = nil
    elseif unit and best and not busy(unit) then
      unit.set_ai_state({ type = AI.investigating, destination = best.position })
      best_entry.visits = best_entry.visits + 1
      sent[number] = true
      stat("wreck_dispatches")
      debug_log("Demolisher sent to wreck buildings in chunk " .. best_key)
    end
  end
  return sent
end

local function run_vibration_check(surface)
  local threshold = T("vibration_investigate_threshold")
  -- Loudest explored chunk per territory, found by walking the explored chunks once.
  local loudest = {}
  for chunk in surface.get_chunks() do
    local centre = chunk_centre(chunk)
    local amount = surface.get_pollution(centre)
    if amount >= threshold then
      local territory = surface.get_territory_for_chunk(chunk)
      if territory then
        local units = territory.get_segmented_units()
        local unit = units[1]
        if unit and unit.valid then
          local best = loudest[unit.unit_number]
          if not best or amount > best.amount then
            loudest[unit.unit_number] = { unit = unit, amount = amount, position = centre }
          end
        end
      end
    end
  end
  -- Buildings in its own territory come first.
  local wrecking = run_wreck_dispatch(surface)
  local sent = table_size(wrecking)
  storage.last_investigation = storage.last_investigation or {}
  local cooldown = T("vibration_investigate_cooldown")
  for number, best in pairs(loudest) do
    local last = storage.last_investigation[number]
    if not wrecking[number] and (not last or game.tick - last >= cooldown) and not busy(best.unit) then
      best.unit.set_ai_state({ type = AI.investigating, destination = best.position })
      storage.last_investigation[number] = game.tick
      stat("investigations")
      sent = sent + 1
      debug_log("Demolisher investigates vibration of " .. string.format("%.1f", best.amount))
    end
  end
  return sent > 0
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local HANDLERS = {
  expansion = function(surface) return run_expansion(surface) end,
  growth = run_growth,
  nest = run_nest,
  hatch = run_hatch,
  vibration = run_vibration_check, -- not a scaled event: runs on its own fixed interval
}

local function run_event(surface, event)
  stat(event .. "_attempts")
  storage.last_event[event] = game.tick
  return HANDLERS[event](surface)
end

local function initialize_vulcanus(surface)
  local v = storage.vulcanus
  if v and v.surface_index == surface.index then
    if not inert(surface) then clear_dead_territories(surface) end
    return
  end
  local safe, count, candidates = record_safe_zone(surface)
  storage.vulcanus = {
    surface_index = surface.index,
    initialized_tick = game.tick,
    safe_chunks = safe,
    safe_chunk_count = count,
    safe_candidates = candidates,
    cleared_chunks = {},
    cleared_chunk_count = 0,
    reserved = {},
  }
  for _, event in ipairs(EVENTS) do storage.last_event[event] = game.tick end
  schedule_all(surface)
  debug_log("Initialized on " .. surface.name .. " with " .. count .. " safe chunks")
  if not inert(surface) then clear_dead_territories(surface) end
  check_settings()
end

-- No-enemies mode was turned off: catch up on territories that died meanwhile, restart the clocks.
local function resume(surface)
  clear_dead_territories(surface)
  schedule_all(surface)
end

local function check_vulcanus()
  if storage.vulcanus and not tracked_surface() then
    storage.vulcanus = nil
  end
  local surface = game.surfaces[SURFACE_NAME]
  if surface then initialize_vulcanus(surface) end
end

script.on_init(function()
  setup_storage()
  check_vulcanus()
end)

script.on_configuration_changed(function()
  setup_storage()
  check_vulcanus()
  local surface = tracked_surface()
  if surface then
    for _, event in ipairs(EVENTS) do
      if not storage.next_event[event] then
        storage.next_event[event] = game.tick + event_cooldown(surface, event)
      end
    end
  end
  check_settings(resume)
end)

script.on_event(defines.events.on_surface_created, function(event)
  local surface = game.surfaces[event.surface_index]
  if surface and surface.name == SURFACE_NAME then initialize_vulcanus(surface) end
end)

script.on_event(defines.events.on_surface_deleted, function(event)
  if storage.vulcanus and storage.vulcanus.surface_index == event.surface_index then
    storage.vulcanus = nil
    storage.pending = {}
    storage.trips = {}
    storage.nests = {}
    storage.egg_registrations = {}
  end
end)

script.on_event(defines.events.on_chunk_generated, on_chunk_generated)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)

script.on_event(defines.events.on_segmented_unit_died, function(event)
  queue_territory_check(event.segmented_unit)
  on_unit_gone(event.segmented_unit)
end)

script.on_event(defines.events.script_raised_destroy_segmented_unit, function(event)
  queue_territory_check(event.segmented_unit)
  on_unit_gone(event.segmented_unit)
end)

script.on_event(defines.events.on_segmented_unit_damaged, function(event)
  local unit = event.segmented_unit
  local trip = unit.valid and storage.trips[unit.unit_number]
  if trip and trip.phase ~= "travel" then
    -- Stop holding it in the coil; its AI takes over and goes after whatever hurt it.
    end_trip(trip, true, "attacked while nesting")
  end
end)

script.on_event(defines.events.on_tick, function(event)
  local surface = tracked_surface()
  if surface and inert(surface) then return end
  if next(storage.pending) then process_pending() end
  if not surface then return end
  if next(storage.trips) then update_trips(surface) end
  if event.tick % T("vibration_check_interval") == 0 then run_event(surface, "vibration") end
  local enabled = game.map_settings.enemy_expansion.enabled
  for _, name in ipairs(EVENTS) do
    if event.tick >= (storage.next_event[name] or 0) then
      storage.next_event[name] = event.tick + event_cooldown(surface, name)
      -- Like biters, demolishers don't expand when the map has enemy expansion turned off.
      if enabled and T(name .. "_enabled") then run_event(surface, name) end
    end
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == SETTING_INTERVAL then
    local surface = tracked_surface()
    if surface then schedule_all(surface) end
  end
end)

script.on_nth_tick(60, function()
  -- Catches a Vulcanus created where on_surface_created doesn't reach this mod, such as another
  -- mod's on_init.
  if not tracked_surface() and game.surfaces[SURFACE_NAME] then check_vulcanus() end
  check_settings(resume)
end)

---------------------------------------------------------------------------------------------------
-- Remote interface. Reads are for tests and other mods; set_tuning and run_event are for testing.

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

remote.add_interface("vulcanus-demolisher-lifecycle", {
  -- Summary of the mod's state. Returns a fresh table; changing it has no effect on the mod.
  get_state = function()
    local v = storage.vulcanus
    local surface = tracked_surface()
    local cooldowns = {}
    if surface then
      for _, event in ipairs(EVENTS) do cooldowns[event] = event_cooldown(surface, event) end
    end
    local eggs = 0
    for _, nest in pairs(storage.nests or {}) do eggs = eggs + table_size(nest.eggs) end
    return {
      schema = storage.schema,
      initialized = v ~= nil,
      surface_index = v and v.surface_index,
      initialized_tick = v and v.initialized_tick,
      safe_chunk_count = v and v.safe_chunk_count or 0,
      safe_candidate_count = v and table_size(v.safe_candidates) or 0,
      cleared_chunk_count = v and v.cleared_chunk_count or 0,
      reserved_chunk_count = v and table_size(v.reserved) or 0,
      pending_checks = table_size(storage.pending or {}),
      cooldowns = cooldowns,
      next_event = copy(storage.next_event or {}),
      last_event = copy(storage.last_event or {}),
      -- Expansion clock, under the names used before there were several clocks.
      expansion_cooldown = cooldowns.expansion,
      next_expansion_tick = storage.next_event and storage.next_event.expansion,
      last_expansion_tick = storage.last_event and storage.last_event.expansion,
      trip_count = table_size(storage.trips or {}),
      nest_count = table_size(storage.nests or {}),
      egg_count = eggs,
      warned_expansion_disabled = storage.warned_expansion_disabled == true,
      no_enemies = surface ~= nil and inert(surface),
      warned_no_enemies = storage.warned_no_enemies == true,
      stats = copy(storage.stats or new_stats()),
    }
  end,
  -- Nesting trips in progress: {unit_number, phase, site, chunk, started}.
  get_trips = function()
    local result = {}
    for _, trip in pairs(storage.trips or {}) do
      result[#result + 1] = { unit_number = trip.unit_number, phase = trip.phase, site = trip.site, chunk = trip.chunk, started = trip.started }
    end
    return result
  end,
  -- Nests: {id, site, chunk, parent_unit_number, parent_dead, eggs = {{position, laid}}}.
  get_nests = function()
    local result = {}
    for _, nest in pairs(storage.nests or {}) do
      local eggs = {}
      for _, egg in pairs(nest.eggs) do eggs[#eggs + 1] = { position = egg.position, laid = egg.laid } end
      result[#result + 1] = {
        id = nest.id, site = nest.site, chunk = nest.chunk, parent_unit_number = nest.parent_unit_number,
        parent_dead = nest.parent_dead or not (nest.parent and nest.parent.valid), eggs = eggs,
      }
    end
    return result
  end,
  -- Array of {x, y} chunk positions in the recorded safe starting area.
  get_safe_chunks = function()
    local result = {}
    local v = storage.vulcanus
    if not v then return result end
    for key in pairs(v.safe_chunks) do
      local x, y = key:match("^(-?%d+),(-?%d+)$")
      result[#result + 1] = { x = tonumber(x), y = tonumber(y) }
    end
    return result
  end,
  -- Array of {x, y} chunk positions marked cleared and not yet expanded into.
  get_cleared_chunks = function()
    local result = {}
    local v = storage.vulcanus
    if not v then return result end
    for _, chunk in pairs(v.cleared_chunks) do result[#result + 1] = { x = chunk.x, y = chunk.y } end
    return result
  end,
  is_cleared_chunk = function(x, y)
    local v = storage.vulcanus
    return v ~= nil and v.cleared_chunks[x .. "," .. y] ~= nil
  end,
  is_safe_chunk = function(x, y)
    return is_safe_chunk({ x = x, y = y })
  end,
  -- Testing: override tuning.lua values, e.g. set_tuning{nest_min_chunks = 10}.
  set_tuning = function(values)
    tuning.set(values)
    local surface = tracked_surface()
    if surface then schedule_all(surface) end
  end,
  -- Testing: run one event now ("expansion", "growth", "nest", "hatch" or "vibration"). Returns whether it did
  -- something.
  run_event = function(name)
    local surface = tracked_surface()
    if not surface or not HANDLERS[name] then return false end
    return run_event(surface, name) and true or false
  end,
})
