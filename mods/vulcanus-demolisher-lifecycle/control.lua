-- Vulcanus Demolisher Lifecycle
--
-- Performance: per-tick work is bounded. Territory data comes from the index (index.lua), never
-- from scanning the game's territories; periodic scans are spread across ticks; at most one event
-- runs per tick. See tests/vulcanus-demolisher-lifecycle (perf-* scenarios) for the limits.
--
-- storage layout (schema 4):
--   storage.schema        integer, bumped when the layout changes
--   storage.index         territory index (index.lua)
--   storage.setup         set-up job in progress (Vulcanus created mid-game), or nil
--   storage.vulcanus      nil until set up, then:
--     surface_index       index of the tracked Vulcanus surface
--     initialized_tick    tick set-up finished
--     safe_chunks         set of chunk key chunk keys forming the original safe starting area
--     safe_chunk_count    number of entries in safe_chunks
--     safe_candidates     set of chunk key keys of ungenerated chunks still to be decided
--     cleared_chunks      map of chunk key -> chunk: land of dead territories, for expansion
--     cleared_chunk_count number of entries in cleared_chunks
--     frontier            cleared chunks that may border a living territory: {list = {keys}, pos =
--                         {key -> position in list}}, so expansion can sample it
--     reserved            map of chunk key -> nest id: nest chunks expansion skips while it has eggs
--     explored            array of explored chunk positions, for the vibration sweep
--     sweep               vibration sweep in progress: {i, loudest = {tid -> {amount, position}}}
--   storage.pending       set of territory ids whose demolisher died, cleared a batch of chunks per tick
--   storage.clearing      the dead territory being cleared: {tid, list of chunks, next position}
--   storage.next_event    map of event name -> tick of its next attempt
--   storage.last_event    map of event name -> tick of its last attempt
--   storage.trips         map of unit_number -> nesting trip in progress
--   storage.nests         map of nest id -> nest (site, parent territory id, eggs)
--   storage.egg_registrations map of on_object_destroyed registration number -> {nest, egg}
--   storage.retry_after   map of unit_number -> tick before which that demolisher won't nest again
--   storage.last_investigation map of territory id -> tick its demolisher was last sent by vibration
--   storage.wreck         map of territory id -> {chunk key -> {chunk, visits}}: chunks with player
--                         buildings it took
--   storage.native_tier   map of territory id -> size the map generator places there
--   storage.tuning        overrides for tuning.lua, set through the remote interface
--   storage.stats         counters, exposed through the remote interface for tests and other mods

local tuning = require("tuning")
local coil = require("coil")
local index = require("index")
local T = tuning.get
local dist = coil.dist
local key = index.key

local SURFACE_NAME = "vulcanus"
local SCHEMA = 4
local EVENTS = { "expansion", "growth", "nest", "hatch" }

local SETTING_PROTECT = "demolisher-lifecycle-protect-starting-area"
local SETTING_INTERVAL = "demolisher-lifecycle-expansion-interval-ticks"
local SETTING_DEBUG = "demolisher-lifecycle-debug-log"

-- How far from the map origin (in chunks) to look for the starting area. Vulcanus puts its
-- starting area disc 100 * starting_area_radius + 32 tiles from the origin with a 224 tile radius.
local SAFE_ZONE_SCAN_RADIUS = 24
-- Rows of the starting-area scan per tick when set-up is spread over ticks.
local SETUP_ROWS_PER_TICK = 6
-- Growth looks at this many random demolishers per event.
local GROWTH_SAMPLES = 8
-- A travelling nester's progress is checked this often (ticks).
local TRAVEL_CHECK_INTERVAL = 10

local AI = defines.segmented_unit_ai_state
local NEIGHBOURS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

-- Set while this mod creates territories or demolishers, so the creation events don't index them
-- a second time.
local creating = false

-- Profiling (tuning key "profile"): log how long a piece of work took, for performance work.
local function profiled(name, fn, ...)
  if not T("profile") then return fn(...) end
  local profiler = helpers.create_profiler()
  local a, b = fn(...)
  profiler.stop()
  log({ "", "PROFILE ", name, " ", profiler, " tick ", game.tick })
  return a, b
end

local function debug_log(message)
  if settings.global[SETTING_DEBUG].value then
    log(message)
  end
end

local function chunk_key(chunk)
  return key(chunk.x, chunk.y)
end

local function chunk_name(chunk)
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
  storage.stats = storage.stats or new_stats()
  for k, value in pairs(new_stats()) do
    if storage.stats[k] == nil then storage.stats[k] = value end
  end
  storage.next_event = storage.next_event or {}
  storage.last_event = storage.last_event or {}
  storage.trips = storage.trips or {}
  storage.nests = storage.nests or {}
  storage.next_nest_id = storage.next_nest_id or 1
  storage.egg_registrations = storage.egg_registrations or {}
  storage.retry_after = storage.retry_after or {}
  storage.last_investigation = storage.last_investigation or {}
  storage.wreck = storage.wreck or {}
  storage.native_tier = storage.native_tier or {}
  storage.index = storage.index or index.new()
  -- Before schema 4 the pending table held territories or chunks; the set-up sweep covers them.
  if (storage.schema or 0) < SCHEMA then
    storage.pending = {}
    storage.clearing = nil
    storage.last_investigation = {}
    storage.wreck = {}
    storage.native_tier = {}
  end
  storage.pending = storage.pending or {}
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

-- No-enemies mode on Vulcanus (inherited from the new-game settings) leaves every territory
-- without a demolisher, so the mod stays inert there instead of clearing them all.
local function inert(surface)
  return surface.no_enemies_mode
end

-- The mod needs enemy expansion and enemies. Say so once each time either is found missing.
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

local function is_safe_key(k)
  local v = storage.vulcanus
  return v ~= nil and v.safe_chunks[k] == true
end

local function is_safe_chunk(chunk)
  return is_safe_key(chunk_key(chunk))
end

---------------------------------------------------------------------------------------------------
-- Cleared land and the expansion frontier

local function mark_cleared(x, y)
  local v = storage.vulcanus
  local k = key(x, y)
  if not v.cleared_chunks[k] then
    v.cleared_chunks[k] = { x = x, y = y }
    v.cleared_chunk_count = v.cleared_chunk_count + 1
  end
end

-- A frontier is {list = {keys}, pos = {key -> position in list}}: a set that can be sampled.
local function frontier_add(k, name)
  local f = storage.vulcanus[name or "frontier"]
  if f.pos[k] then return end
  local n = #f.list + 1
  f.list[n] = k
  f.pos[k] = n
end

local function frontier_remove(k, name)
  local f = storage.vulcanus[name or "frontier"]
  local i = f.pos[k]
  if not i then return end
  local n = #f.list
  local last = f.list[n]
  f.list[i] = last
  f.pos[last] = i
  f.list[n] = nil
  f.pos[k] = nil
end

local function unmark_cleared(k)
  local v = storage.vulcanus
  if v.cleared_chunks[k] then
    v.cleared_chunks[k] = nil
    v.cleared_chunk_count = v.cleared_chunk_count - 1
  end
  frontier_remove(k)
end

-- Living territories bordering a chunk, as a list of territory ids (no duplicates).
local function living_neighbours(x, y)
  local result, seen = {}, {}
  for _, d in ipairs(NEIGHBOURS) do
    local tid = index.owner_at(x + d[1], y + d[2])
    if tid and not seen[tid] and index.alive(index.get(tid)) then
      seen[tid] = true
      result[#result + 1] = tid
    end
  end
  return result
end

-- Whether a living territory borders a chunk (no allocation, for hot loops).
local function has_living_neighbour(x, y)
  local owner, terr = storage.index.owner, storage.index.terr
  for _, d in ipairs(NEIGHBOURS) do
    local tid = owner[key(x + d[1], y + d[2])]
    if tid and index.alive(terr[tid]) then return true end
  end
  return false
end

-- A cleared chunk joins the frontier if it borders a living territory; an unclaimed chunk of the
-- starting area joins the safe frontier. Entries go stale when that territory dies or the chunk is
-- taken; expansion drops them when it finds them.
local function frontier_consider(x, y)
  local v = storage.vulcanus
  local k = key(x, y)
  local cleared = v.cleared_chunks[k]
  local free_safe = v.safe_chunks[k] and not storage.index.owner[k]
  if (cleared or free_safe) and has_living_neighbour(x, y) then
    if cleared then frontier_add(k) end
    if free_safe then frontier_add(k, "safe_frontier") end
  end
end

-- After a chunk joins territory, its free neighbours border a living territory.
local function frontier_around(x, y)
  for _, d in ipairs(NEIGHBOURS) do frontier_consider(x + d[1], y + d[2]) end
end

local function rebuild_frontier()
  local v = storage.vulcanus
  v.frontier = { list = {}, pos = {} }
  v.safe_frontier = { list = {}, pos = {} }
  for _, c in pairs(v.cleared_chunks) do frontier_consider(c.x, c.y) end
  for k in pairs(v.safe_chunks) do frontier_consider(index.unkey(k)) end
end

---------------------------------------------------------------------------------------------------
-- Dead territories

-- In vanilla a territory stays after its last demolisher dies. This mod needs that land free so
-- living territories can expand into it, so it removes the territory. LuaTerritory.destroy() would
-- let the map generator create a fresh territory (with a fresh demolisher) on any of its chunks
-- that get generated later, so instead the chunks are set to no territory, which also deletes the
-- territory. The chunks are marked as cleared so living territories can expand into them.
local function clear_territory(surface, tid)
  local t = index.get(tid)
  if not t then return end
  local list = {}
  for _, c in pairs(t.chunks) do list[#list + 1] = c end
  if t.territory.valid then surface.set_territory_for_chunks(list, nil) end
  for _, c in ipairs(list) do
    index.remove_chunk(tid, key(c.x, c.y))
    mark_cleared(c.x, c.y)
  end
  index.drop(tid)
  for _, c in ipairs(list) do frontier_consider(c.x, c.y) end
  stat("territories_cleared")
  stat("chunks_cleared", #list)
  debug_log("Cleared a territory of " .. #list .. " chunks")
end

-- During play a territory is cleared a batch of chunks per tick: setting territory on a few hundred
-- chunks at once costs several milliseconds.
local CLEAR_BATCH = 48

local function clear_batch(surface, job)
  local t = index.get(job.tid)
  local last = math.min(#job.list, job.i + CLEAR_BATCH - 1)
  local batch = {}
  -- Skip chunks that changed hands meanwhile (a hatchling's nest chunk).
  for i = job.i, last do
    local c = job.list[i]
    if index.owner_at(c.x, c.y) == job.tid then batch[#batch + 1] = c end
  end
  job.i = last + 1
  if t and t.territory.valid then surface.set_territory_for_chunks(batch, nil) end
  for _, c in ipairs(batch) do
    index.remove_chunk(job.tid, key(c.x, c.y))
    mark_cleared(c.x, c.y)
  end
  for _, c in ipairs(batch) do frontier_consider(c.x, c.y) end
  if job.i > #job.list then
    index.drop(job.tid)
    stat("territories_cleared")
    stat("chunks_cleared", #job.list)
    debug_log("Cleared a territory of " .. #job.list .. " chunks")
    return true
  end
  return false
end

-- At load time: clear every dead territory now.
local function clear_dead_territories(surface)
  for tid, t in pairs(storage.index.terr) do
    if not index.alive(t) then clear_territory(surface, tid) end
  end
end

-- During play: queue them, cleared one per tick.
local function queue_dead_territories()
  for tid, t in pairs(storage.index.terr) do
    if not index.alive(t) then storage.pending[tid] = true end
  end
end

local function process_pending(surface)
  local job = storage.clearing
  if not job then
    local tid = next(storage.pending)
    if not tid then return end
    storage.pending[tid] = nil
    local t = index.get(tid)
    if not t or index.alive(t) then return end
    local list = {}
    for _, c in pairs(t.chunks) do list[#list + 1] = c end
    job = { tid = tid, list = list, i = 1 }
    storage.clearing = job
  end
  if clear_batch(surface, job) then storage.clearing = nil end
end

---------------------------------------------------------------------------------------------------
-- Expansion

-- Expansion prefers chunks near the centre of the territory that gains them, so holes and
-- concave edges fill first: weight = exp(-strength * d / r), with d the chunk's distance from
-- the territory's centre and r the territory's radius (both in chunks).
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

-- Gives a chunk to a territory, in the game and the index.
local function give_chunk(surface, tid, chunk)
  local t = index.get(tid)
  surface.set_territory_for_chunks({ chunk }, t.territory)
  t.territory.regenerate_patrol_path()
  index.add_chunk(tid, chunk.x, chunk.y)
  unmark_cleared(chunk_key(chunk))
  frontier_remove(chunk_key(chunk), "safe_frontier")
  frontier_around(chunk.x, chunk.y)
  on_chunk_gained(surface, tid, chunk)
end

-- Frontier chunks weighed per expansion. A large frontier (after big territories die) is sampled
-- rather than weighed in full, which keeps the cost of an expansion flat.
local FRONTIER_SAMPLES = 48

-- Up to FRONTIER_SAMPLES distinct frontier keys: all of them if it is small, else a random sample.
local function frontier_sample(name)
  local list = storage.vulcanus[name or "frontier"].list
  local n = #list
  if n <= FRONTIER_SAMPLES then
    local copy_ = {}
    for i = 1, n do copy_[i] = list[i] end
    return copy_
  end
  local picked, result = {}, {}
  while #result < FRONTIER_SAMPLES do
    local i = math.random(1, n)
    if not picked[i] then
      picked[i] = true
      result[#result + 1] = list[i]
    end
  end
  return result
end

-- Expanding into cleared land: a cleared chunk next to a living territory joins it. This works on
-- cleared chunks nobody has explored yet. Only the frontier is weighed.
local function try_expand_into_cleared(surface, protect)
  local v = storage.vulcanus
  local candidates, blocked, geometry = {}, false, {}
  for _, k in ipairs(frontier_sample()) do
    local c = v.cleared_chunks[k]
    if not c then
      frontier_remove(k)
    elseif not v.reserved[k] then
      local tids = living_neighbours(c.x, c.y)
      if #tids == 0 then
        frontier_remove(k)
      elseif protect and v.safe_chunks[k] then
        blocked = true
      else
        for _, tid in ipairs(tids) do
          geometry[tid] = geometry[tid] or index.geometry(index.get(tid))
          candidates[#candidates + 1] = { chunk = c, tid = tid, weight = expansion_weight(geometry[tid], c) }
        end
      end
    end
  end
  if #candidates == 0 then return false, blocked end
  local pick = weighted_pick(candidates)
  give_chunk(surface, pick.tid, pick.chunk)
  stat("expansions")
  stat("cleared_chunks_taken")
  debug_log("Territory expanded into cleared chunk " .. chunk_name(pick.chunk))
  return true, blocked
end

-- Plain expansion: into an explored neighbouring chunk without territory that was never marked
-- cleared. The only such land is the starting area, so this works through the safe frontier. With
-- protection on it only notes whether a living territory presses on it.
local function try_expand_free_land(surface, protect)
  local candidates, blocked, geometry = {}, false, {}
  local owner = storage.index.owner
  for _, k in ipairs(frontier_sample("safe_frontier")) do
    local x, y = index.unkey(k)
    if owner[k] or not has_living_neighbour(x, y) then
      frontier_remove(k, "safe_frontier")
    elseif protect then
      blocked = true
      break
    else
      local chunk = { x = x, y = y }
      for _, tid in ipairs(living_neighbours(x, y)) do
        geometry[tid] = geometry[tid] or index.geometry(index.get(tid))
        candidates[#candidates + 1] = { chunk = chunk, tid = tid, weight = expansion_weight(geometry[tid], chunk) }
      end
    end
  end
  if #candidates == 0 then return false, blocked end
  local pick = weighted_pick(candidates)
  give_chunk(surface, pick.tid, pick.chunk)
  stat("expansions")
  debug_log("Territory expanded into chunk " .. chunk_name(pick.chunk))
  return true, blocked
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

-- The size the map generator would place here (1 = smallest), from the same noise expression.
local function native_tier(surface, position)
  local value = surface.calculate_tile_properties({ "demolisher_variation_expression" },
    { { position.x, position.y } })["demolisher_variation_expression"][1]
  return math.max(1, math.min(#T("tiers"), math.floor(value) + 1))
end

local function head_of(unit)
  return unit.get_body_nodes()[1]
end

-- Living territories with a known size, as a list of {tid, t}.
local function living_territories()
  local result = {}
  for tid, t in pairs(storage.index.terr) do
    if index.alive(t) and t.territory.valid then result[#result + 1] = { tid = tid, t = t } end
  end
  return result
end

---------------------------------------------------------------------------------------------------
-- Growth: a demolisher with a big enough territory grows one size, up to a limit set by distance.

local function sigmoid(x)
  return 1 / (1 + math.exp(-x))
end

local function grow(surface, tid, t, next_name)
  local unit = t.unit
  creating = true
  local replacement = surface.create_segmented_unit({
    name = next_name,
    force = unit.force,
    territory = t.territory,
    body_nodes = unit.get_body_nodes(),
  })
  creating = false
  if not replacement then return false end
  replacement.health = replacement.max_health * unit.health_ratio
  local old_number = unit.unit_number
  storage.retry_after[replacement.unit_number] = storage.retry_after[old_number]
  storage.retry_after[old_number] = nil
  for _, nest in pairs(storage.nests) do
    if nest.parent_tid == tid then nest.parent_unit_number = replacement.unit_number end
  end
  index.set_unit(tid, replacement)
  unit.destroy()
  stat("growths")
  debug_log("Demolisher grew into " .. next_name)
  return true
end

local function run_growth(surface)
  local list = living_territories()
  local tiers = T("tiers")
  for _ = 1, math.min(GROWTH_SAMPLES, #list) do
    local i = math.random(1, #list)
    local entry = list[i]
    list[i] = list[#list]
    list[#list] = nil
    local tid, t = entry.tid, entry.t
    local tier = tier_of(t.unit.prototype.name)
    if tier and tier < #tiers and not storage.trips[t.unit_number] then
      local next_name = tiers[tier + 1]
      local midpoint = T("growth_midpoint")[next_name]
      if midpoint then
        -- Judged at the territory's centre: the map generator sizes a demolisher by its territory.
        local native = storage.native_tier[tid]
        if not native then
          local g = index.geometry(t)
          native = native_tier(surface, { x = g.x * 32 + 16, y = g.y * 32 + 16 })
          storage.native_tier[tid] = native
        end
        if tier + 1 <= native + T("growth_tiers_above_native")
          and math.random() < sigmoid((t.count - midpoint) / T("growth_width")) then
          return grow(surface, tid, t, next_name)
        end
      end
    end
  end
  return false
end

---------------------------------------------------------------------------------------------------
-- Nesting: a max-size demolisher with a big territory travels to the territory's centre, coils
-- around the spot, lays a nest of eggs, and returns to its patrol.

local function owns_nest(tid)
  for _, nest in pairs(storage.nests) do
    if nest.parent_tid == tid then return true end
  end
  return false
end

-- Centre of the territory's chunks, snapped to its nearest explored chunk.
local function nest_site(surface, t)
  local g = index.geometry(t)
  local ranked = {}
  for _, c in pairs(t.chunks) do
    ranked[#ranked + 1] = { c = c, d = (c.x - g.x) ^ 2 + (c.y - g.y) ^ 2 }
  end
  table.sort(ranked, function(a, b) return a.d < b.d end)
  for _, entry in ipairs(ranked) do
    if surface.is_chunk_generated(entry.c) then
      local centre = chunk_centre(entry.c)
      local position = surface.find_non_colliding_position("demolisher-egg", centre, 12, 1) or centre
      return position, { x = entry.c.x, y = entry.c.y }
    end
  end
  return nil
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
  local min_chunks = T("nest_min_chunks")
  local candidates = {}
  for _, entry in ipairs(living_territories()) do
    local t = entry.t
    local number = t.unit_number
    if t.count >= min_chunks and t.unit.prototype.name == max_tier and not storage.trips[number]
      and game.tick >= (storage.retry_after[number] or 0) and not owns_nest(entry.tid) then
      candidates[#candidates + 1] = entry
    end
  end
  -- In random order, the first with an explored chunk to nest on.
  local entry, site, chunk
  while #candidates > 0 do
    local i = math.random(1, #candidates)
    entry = candidates[i]
    candidates[i] = candidates[#candidates]
    candidates[#candidates] = nil
    site, chunk = nest_site(surface, entry.t)
    if site then break end
  end
  if not site then return false end
  local unit = entry.t.unit
  storage.trips[unit.unit_number] = {
    unit = unit,
    unit_number = unit.unit_number,
    tid = entry.tid,
    site = site,
    chunk = chunk,
    phase = "travel",
    started = game.tick,
    reissues = 0,
  }
  unit.set_ai_state({ type = AI.investigating, destination = site })
  stat("trips_started")
  debug_log("Nesting trip started to " .. chunk_name(chunk))
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
    parent_tid = trip.tid,
    parent_unit_number = unit.unit_number,
    force = unit.force.name,
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
  if v and v.reserved[nest.chunk_key] == nest.id then
    v.reserved[nest.chunk_key] = nil
    local c = nest.chunk
    frontier_consider(c.x, c.y)
  end
end

local function update_trip(surface, trip)
  local unit = trip.unit
  if not unit.valid then
    storage.trips[trip.unit_number] = nil
    return
  end
  if trip.phase == "travel" then
    -- The engine steers; checking every few ticks is enough.
    if (game.tick + trip.unit_number) % TRAVEL_CHECK_INTERVAL ~= 0 then return end
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
-- With the parent alive the chunk always comes from the parent's edge, never a nest chunk.
-- The hatchling's territory is that one chunk; it grows from there like any other. A parent chunk
-- is only taken if the parent's territory stays in one piece without it.

-- The parent edge chunk nearest the nest that is explored, isn't a nest chunk (this nest's or
-- another's), and can be given away without splitting the parent's territory in two.
local function nearest_takeable(surface, tid, chunks, position)
  local reserved = storage.vulcanus.reserved
  local ranked = {}
  for _, c in pairs(chunks) do
    if not reserved[chunk_key(c)] then
      ranked[#ranked + 1] = { c = c, d = dist(chunk_centre(c), position) }
    end
  end
  table.sort(ranked, function(a, b) return a.d < b.d end)
  for _, entry in ipairs(ranked) do
    local c = entry.c
    if surface.is_chunk_generated(c) and not index.would_split(tid, c.x, c.y) then return c end
  end
  return nil
end

-- Parent chunks next to cleared land the parent could expand into.
local function chunks_next_to_free_space(tid)
  local v = storage.vulcanus
  local protect = settings.global[SETTING_PROTECT].value
  local t = index.get(tid)
  local result = {}
  local cleared, reserved, safe = v.cleared_chunks, v.reserved, v.safe_chunks
  for _, c in pairs(t.chunks) do
    for _, d in ipairs(NEIGHBOURS) do
      local nk = key(c.x + d[1], c.y + d[2])
      if cleared[nk] and not reserved[nk] and not (protect and safe[nk]) then
        result[#result + 1] = c
        break
      end
    end
  end
  return result
end

local function edge_chunks(tid)
  local t = index.get(tid)
  local result = {}
  for _, c in pairs(t.chunks) do
    for _, d in ipairs(NEIGHBOURS) do
      if index.owner_at(c.x + d[1], c.y + d[2]) ~= tid then
        result[#result + 1] = c
        break
      end
    end
  end
  return result
end

-- Weight, child chunk and reason for one nest's eggs right now (the same for all its eggs).
-- `old_enough` says whether any egg could use the old-egg rule, which is the costly one.
local function hatch_option(surface, nest, old_enough)
  local t = index.get(nest.parent_tid)
  if not index.alive(t) then
    return T("hatch_weight_dead_parent"), nest.chunk, "dead_parent"
  end
  if t.count <= 1 then return 0 end
  local free = chunks_next_to_free_space(nest.parent_tid)
  if #free > 0 then
    local chunk = nearest_takeable(surface, nest.parent_tid, free, nest.site)
    if chunk then return T("hatch_weight_free_space"), chunk, "free_space" end
  end
  if not old_enough then return 0 end
  local chunk = nearest_takeable(surface, nest.parent_tid, edge_chunks(nest.parent_tid), nest.site)
  if chunk then return T("hatch_weight_old"), chunk, "old" end
  return 0
end

local function hatch(surface, nest, egg, chunk, reason)
  local v = storage.vulcanus
  local k = chunk_key(chunk)
  local parent = index.get(nest.parent_tid)
  creating = true
  local territory = surface.create_territory({ chunks = { chunk } })
  creating = false
  if not territory then return false end
  local tid = index.index_territory(territory)
  unmark_cleared(k)
  if reason ~= "dead_parent" and parent and parent.territory.valid then
    parent.territory.regenerate_patrol_path()
  end
  creating = true
  local child = surface.create_segmented_unit({
    name = T("tiers")[1],
    force = nest.force or "enemy",
    territory = territory,
    position = egg.position,
  })
  creating = false
  if not child then
    -- Give the chunk back: to the parent if it had it, otherwise clear it again.
    if parent and reason ~= "dead_parent" then
      surface.set_territory_for_chunks({ chunk }, parent.territory)
      index.add_chunk(nest.parent_tid, chunk.x, chunk.y)
    else
      surface.set_territory_for_chunks({ chunk }, nil)
      if tid then index.remove_chunk(tid, k); index.drop(tid) end
      mark_cleared(chunk.x, chunk.y)
    end
    return false
  end
  index.set_unit(tid, child)
  child.set_body_nodes(coil.curl(egg.position, child.max_body_nodes))
  -- It owns its chunk straight away and finds its own way there along its patrol route.
  child.set_ai_state({ type = AI.patrolling, waypoint = 1 })
  frontier_around(chunk.x, chunk.y)
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
  storage.egg_registrations[egg.registration] = nil
  nest.eggs[egg.id] = nil
  if egg.entity.valid then egg.entity.destroy() end
  remove_nest_if_empty(nest)
  stat("eggs_hatched")
  stat("hatched_" .. reason)
  debug_log("Egg hatched (" .. reason .. ") into chunk " .. chunk_name(chunk))
  return true
end

local function run_hatch(surface)
  local options, total = {}, 0
  local min_age, old_age = T("egg_min_age"), T("egg_old_age")
  for _, nest in pairs(storage.nests) do
    local ready, old_enough = false, false
    for _, egg in pairs(nest.eggs) do
      local age = game.tick - egg.laid
      if age >= min_age then ready = true end
      if age >= old_age then old_enough = true end
    end
    if ready then
      local weight, chunk, reason = hatch_option(surface, nest, old_enough)
      if weight > 0 then
        for _, egg in pairs(nest.eggs) do
          local age = game.tick - egg.laid
          if egg.entity.valid and age >= min_age and (reason ~= "old" or age >= old_age) then
            options[#options + 1] = { nest = nest, egg = egg, chunk = chunk, reason = reason, weight = weight }
            total = total + weight
          end
        end
      end
    end
  end
  if total == 0 then return false end
  local pick = weighted_pick(options)
  return hatch(surface, pick.nest, pick.egg, pick.chunk, pick.reason)
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

-- A demolisher died or was destroyed: its territory is cleared on a later tick.
local function on_unit_gone(unit)
  if not unit.valid then return end
  local number = unit.unit_number
  storage.trips[number] = nil
  local tid = index.tid_of_unit(number)
  if tid then
    index.set_unit(tid, nil)
    storage.pending[tid] = true
  end
end

---------------------------------------------------------------------------------------------------
-- Vibration and wrecking. Demolishers are sent to investigate: buildings their territory grew over
-- first, then the loudest chunk of their territory once its vibration passes a threshold. The
-- explored chunks are swept a slice per tick, so a full pass takes vibration_check_interval ticks.

local function busy(unit)
  local state = unit.get_ai_state().type
  return state == AI.attacking or state == AI.enraged_at_target or state == AI.enraged_at_nothing
    or state == AI.investigating or storage.trips[unit.unit_number] ~= nil
end

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

on_chunk_gained = function(surface, tid, chunk)
  if not player_target_in(surface, chunk) then return end
  local queue = storage.wreck[tid] or {}
  storage.wreck[tid] = queue
  queue[chunk_key(chunk)] = { chunk = { x = chunk.x, y = chunk.y }, visits = 0 }
  stat("chunks_with_buildings_taken")
  debug_log("Territory took chunk " .. chunk_name(chunk) .. " with player buildings")
end

-- Sends demolishers after queued chunks. Returns the set of territory ids it sent.
local function run_wreck_dispatch(surface)
  local sent = {}
  for tid, queue in pairs(storage.wreck) do
    local t = index.get(tid)
    if not index.alive(t) then
      storage.wreck[tid] = nil
    else
      local best, best_entry, best_d
      for k, entry in pairs(queue) do
        local target = index.owner_of_key(k) == tid and player_target_in(surface, entry.chunk)
        if not target or entry.visits >= T("wreck_max_visits") then
          queue[k] = nil
        else
          local d = dist(head_of(t.unit), target.position)
          if not best_d or d < best_d then best, best_entry, best_d = target, entry, d end
        end
      end
      if not next(queue) then
        storage.wreck[tid] = nil
      elseif best and not busy(t.unit) then
        t.unit.set_ai_state({ type = AI.investigating, destination = best.position })
        best_entry.visits = best_entry.visits + 1
        sent[tid] = true
        stat("wreck_dispatches")
        debug_log("Demolisher sent to wreck buildings")
      end
    end
  end
  return sent
end

-- Looks at explored chunks [first, last] and records the loudest one per territory.
local function sweep_chunks(surface, first, last, loudest)
  local v = storage.vulcanus
  local threshold = T("vibration_investigate_threshold")
  for i = first, last do
    local c = v.explored[i]
    local tid = index.owner_at(c.x, c.y)
    if tid then
      local centre = chunk_centre(c)
      local amount = surface.get_pollution(centre)
      if amount >= threshold then
        local best = loudest[tid]
        if not best or amount > best.amount then loudest[tid] = { amount = amount, position = centre } end
      end
    end
  end
end

local function dispatch_after_sweep(surface, loudest)
  local wrecking = run_wreck_dispatch(surface)
  local sent = table_size(wrecking)
  local cooldown = T("vibration_investigate_cooldown")
  for tid, best in pairs(loudest) do
    local t = index.get(tid)
    local last = storage.last_investigation[tid]
    if index.alive(t) and not wrecking[tid] and (not last or game.tick - last >= cooldown) and not busy(t.unit) then
      t.unit.set_ai_state({ type = AI.investigating, destination = best.position })
      storage.last_investigation[tid] = game.tick
      stat("investigations")
      sent = sent + 1
      debug_log("Demolisher investigates vibration of " .. string.format("%.1f", best.amount))
    end
  end
  return sent > 0
end

-- A full pass at once (the remote run_event("vibration"), for tests).
local function run_vibration_check(surface)
  local loudest = {}
  sweep_chunks(surface, 1, #storage.vulcanus.explored, loudest)
  return dispatch_after_sweep(surface, loudest)
end

-- One tick's slice of the pass.
local function step_vibration_sweep(surface)
  local v = storage.vulcanus
  local total = #v.explored
  local per_tick = math.max(1, math.ceil(total / T("vibration_check_interval")))
  local sweep = v.sweep
  if not sweep then
    sweep = { i = 1, loudest = {} }
    v.sweep = sweep
  end
  local last = math.min(total, sweep.i + per_tick - 1)
  if sweep.i <= last then sweep_chunks(surface, sweep.i, last, sweep.loudest) end
  sweep.i = last + 1
  if sweep.i > total then
    v.sweep = nil
    stat("vibration_attempts")
    profiled("vibration", dispatch_after_sweep, surface, sweep.loudest)
  end
end

---------------------------------------------------------------------------------------------------
-- Set-up. Builds the territory index, records the starting area and the explored chunks, then
-- starts the clocks. When the mod is added to a save this runs at load time, all at once; when
-- Vulcanus is created mid-game it runs as a job over several ticks.

-- The starting-area scan: chunk centres first, then the corners of chunks next to ones found, so
-- only the disc's edge gets the finer sampling.
local function scan_rows(job, surface, first_row, last_row)
  local positions, chunks = {}, {}
  for cx = first_row, last_row do
    for cy = -SAFE_ZONE_SCAN_RADIUS, SAFE_ZONE_SCAN_RADIUS do
      positions[#positions + 1] = { cx * 32 + 16, cy * 32 + 16 }
      chunks[#chunks + 1] = key(cx, cy)
    end
  end
  if #positions == 0 then return end
  local values = surface.calculate_tile_properties({ "demolisher_starting_area" }, positions)["demolisher_starting_area"]
  for i, value in ipairs(values) do
    if value > 0 then job.in_disc[chunks[i]] = true end
  end
end

local function refine_edge(job, surface)
  local positions, chunks = {}, {}
  local corners = { { 1, 1 }, { 31, 1 }, { 1, 31 }, { 31, 31 } }
  local seen = {}
  for k in pairs(job.in_disc) do
    local x, y = index.unkey(k)
    for dx = -1, 1 do
      for dy = -1, 1 do
        local nk = key(x + dx, y + dy)
        if not job.in_disc[nk] and not seen[nk] then
          seen[nk] = true
          for _, o in ipairs(corners) do
            positions[#positions + 1] = { (x + dx) * 32 + o[1], (y + dy) * 32 + o[2] }
            chunks[#chunks + 1] = nk
          end
        end
      end
    end
  end
  if #positions == 0 then return end
  local values = surface.calculate_tile_properties({ "demolisher_starting_area" }, positions)["demolisher_starting_area"]
  for i, value in ipairs(values) do
    if value > 0 then job.in_disc[chunks[i]] = true end
  end
end

-- Safe chunks are those in or next to the disc with no territory: generated ones now, ungenerated
-- ones when they generate (see on_chunk_generated).
local function decide_safe(job, surface)
  local safe, count, candidates, seen = {}, 0, {}, {}
  for k in pairs(job.in_disc) do
    local x, y = index.unkey(k)
    for dx = -1, 1 do
      for dy = -1, 1 do
        local nk = key(x + dx, y + dy)
        if not seen[nk] then
          seen[nk] = true
          if not index.owner_of_key(nk) then
            if surface.is_chunk_generated({ x + dx, y + dy }) then
              safe[nk] = true
              count = count + 1
            else
              candidates[nk] = true
            end
          end
        end
      end
    end
  end
  return safe, count, candidates
end

local function new_setup_job(surface)
  return {
    surface_index = surface.index,
    stage = "index",
    row = -SAFE_ZONE_SCAN_RADIUS,
    in_disc = {},
    explored = {},
    load_time = false,
  }
end

-- Runs the next piece of the job; returns true when finished.
local function step_setup(job, surface, rows)
  if job.stage == "index" then
    index.rebuild(surface)
    job.stage = "scan"
  elseif job.stage == "scan" then
    local last = math.min(SAFE_ZONE_SCAN_RADIUS, job.row + rows - 1)
    scan_rows(job, surface, job.row, last)
    job.row = last + 1
    if job.row > SAFE_ZONE_SCAN_RADIUS then job.stage = "refine" end
  elseif job.stage == "refine" then
    refine_edge(job, surface)
    job.stage = "finish"
  elseif job.stage == "finish" then
    local safe, count, candidates = decide_safe(job, surface)
    local explored = job.explored
    if job.load_time then
      explored = {}
      for c in surface.get_chunks() do explored[#explored + 1] = { x = c.x, y = c.y } end
    end
    storage.vulcanus = {
      surface_index = surface.index,
      initialized_tick = game.tick,
      safe_chunks = safe,
      safe_chunk_count = count,
      safe_candidates = candidates,
      cleared_chunks = {},
      cleared_chunk_count = 0,
      frontier = { list = {}, pos = {} },
      safe_frontier = { list = {}, pos = {} },
      reserved = {},
      explored = explored,
    }
    rebuild_frontier()
    for _, event in ipairs(EVENTS) do storage.last_event[event] = game.tick end
    schedule_all(surface)
    if not inert(surface) then
      if job.load_time then clear_dead_territories(surface) else queue_dead_territories() end
    end
    debug_log("Initialized on " .. surface.name .. " with " .. count .. " safe chunks")
    check_settings()
    return true
  end
  return false
end

-- Set up now (load time) or start the job (during play).
local function start_setup(surface, load_time)
  local job = new_setup_job(surface)
  job.load_time = load_time
  storage.index = index.new()
  if load_time then
    storage.setup = nil
    while not step_setup(job, surface, 2 * SAFE_ZONE_SCAN_RADIUS + 1) do end
  else
    storage.setup = job
  end
end

-- Existing set-up on a configuration change: rebuild the index and derived data, keep the rest.
local function refresh(surface)
  local v = storage.vulcanus
  index.rebuild(surface)
  v.reserved = v.reserved or {}
  v.cleared_chunks = v.cleared_chunks or {}
  v.cleared_chunk_count = v.cleared_chunk_count or 0
  v.explored = {}
  for c in surface.get_chunks() do v.explored[#v.explored + 1] = { x = c.x, y = c.y } end
  v.sweep = nil
  rebuild_frontier()
  -- Nests from before schema 4 named their parent by unit number.
  for _, nest in pairs(storage.nests) do
    if not nest.parent_tid then
      nest.parent_tid = index.tid_of_unit(nest.parent_unit_number) or -1
      nest.force = nest.force or "enemy"
    end
  end
  for _, trip in pairs(storage.trips) do
    if not trip.tid then trip.tid = index.tid_of_unit(trip.unit_number) end
  end
  if not inert(surface) then clear_dead_territories(surface) end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local HANDLERS = {
  expansion = run_expansion,
  growth = run_growth,
  nest = run_nest,
  hatch = run_hatch,
  vibration = run_vibration_check,
}

local function run_event(surface, event)
  stat(event .. "_attempts")
  storage.last_event[event] = game.tick
  return profiled(event, HANDLERS[event], surface)
end

-- No-enemies mode was turned off: catch up on territories that died meanwhile, restart the clocks.
local function resume(surface)
  queue_dead_territories()
  schedule_all(surface)
end

-- At load time (on_init, on_configuration_changed).
local function check_vulcanus_at_load()
  if storage.vulcanus and not tracked_surface() then storage.vulcanus = nil end
  local surface = game.surfaces[SURFACE_NAME]
  if not surface then return end
  storage.setup = nil
  if storage.vulcanus and storage.vulcanus.surface_index == surface.index and (storage.schema or 0) >= SCHEMA then
    refresh(surface)
  else
    profiled("setup", start_setup, surface, true)
  end
end

script.on_init(function()
  setup_storage()
  check_vulcanus_at_load()
  storage.schema = SCHEMA
end)

script.on_configuration_changed(function()
  local old_schema = storage.schema or 0
  setup_storage()
  if storage.vulcanus and old_schema < SCHEMA then
    -- Older layouts: keep the safe zone, cleared land and nests; rebuild everything derived.
    storage.schema = SCHEMA
    local surface = tracked_surface()
    if surface then refresh(surface) end
  else
    check_vulcanus_at_load()
  end
  storage.schema = SCHEMA
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

local function begin_setup_during_play(surface)
  if storage.vulcanus or storage.setup then return end
  start_setup(surface, false)
end

script.on_event(defines.events.on_surface_created, function(event)
  local surface = game.surfaces[event.surface_index]
  if surface and surface.name == SURFACE_NAME then begin_setup_during_play(surface) end
end)

script.on_event(defines.events.on_surface_deleted, function(event)
  if storage.setup and storage.setup.surface_index == event.surface_index then storage.setup = nil end
  if storage.vulcanus and storage.vulcanus.surface_index == event.surface_index then
    storage.vulcanus = nil
    storage.index = index.new()
    storage.pending = {}
    storage.clearing = nil
    storage.trips = {}
    storage.nests = {}
    storage.egg_registrations = {}
    storage.wreck = {}
  end
end)

local function on_vulcanus(surface_index)
  local v = storage.vulcanus
  if v and v.surface_index == surface_index then return v end
  return nil
end

script.on_event(defines.events.on_chunk_generated, function(event)
  local surface_index = event.surface.index
  local p = event.position
  local job = storage.setup
  if job and job.surface_index == surface_index then
    job.explored[#job.explored + 1] = { x = p.x, y = p.y }
    return
  end
  local v = on_vulcanus(surface_index)
  if not v then return end
  v.explored[#v.explored + 1] = { x = p.x, y = p.y }
  local k = key(p.x, p.y)
  if v.safe_candidates[k] then
    v.safe_candidates[k] = nil
    if event.surface.get_territory_for_chunk(p) == nil then
      v.safe_chunks[k] = true
      v.safe_chunk_count = v.safe_chunk_count + 1
      frontier_consider(p.x, p.y)
    end
  end
end)

-- The map generator creates territories and demolishers as land is explored.
script.on_event(defines.events.on_territory_created, function(event)
  if creating then return end
  local territory = event.territory
  if not (territory and territory.valid) then return end
  local surface_index = territory.surface.index
  if not (on_vulcanus(surface_index) or (storage.setup and storage.setup.surface_index == surface_index)) then return end
  index.index_territory(territory)
end)

script.on_event(defines.events.on_segmented_unit_created, function(event)
  if creating then return end
  local unit = event.segmented_unit
  if not (unit and unit.valid and unit.territory and unit.territory.valid) then return end
  local surface_index = unit.surface.index
  if not (on_vulcanus(surface_index) or (storage.setup and storage.setup.surface_index == surface_index)) then return end
  local tid = index.tid_of_territory(unit.territory) or index.index_territory(unit.territory)
  if not tid then return end
  index.set_unit(tid, unit)
  -- Free land next to the new territory is now on the frontier.
  if storage.vulcanus then
    for _, c in pairs(index.get(tid).chunks) do frontier_around(c.x, c.y) end
  end
end)

script.on_event(defines.events.on_object_destroyed, on_object_destroyed)

script.on_event(defines.events.on_segmented_unit_died, function(event)
  on_unit_gone(event.segmented_unit)
end)

script.on_event(defines.events.script_raised_destroy_segmented_unit, function(event)
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
  local job = storage.setup
  if job then
    local surface = game.surfaces[job.surface_index]
    if not (surface and surface.valid) then
      storage.setup = nil
    elseif profiled("setup", step_setup, job, surface, SETUP_ROWS_PER_TICK) then
      storage.setup = nil
    end
    return
  end
  local surface = tracked_surface()
  if not surface or inert(surface) then return end
  if storage.clearing or next(storage.pending) then profiled("pending", process_pending, surface) end
  if next(storage.trips) then profiled("trips", update_trips, surface) end
  step_vibration_sweep(surface)
  -- At most one event per tick; others that are due wait for the next tick.
  local enabled = game.map_settings.enemy_expansion.enabled
  for _, name in ipairs(EVENTS) do
    if event.tick >= (storage.next_event[name] or 0) then
      storage.next_event[name] = event.tick + event_cooldown(surface, name)
      -- Like biters, demolishers don't expand when the map has enemy expansion turned off.
      if enabled and T(name .. "_enabled") then
        run_event(surface, name)
        break
      end
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
  if not tracked_surface() and not storage.setup then
    local surface = game.surfaces[SURFACE_NAME]
    if surface then begin_setup_during_play(surface) end
  end
  check_settings(resume)
end)

---------------------------------------------------------------------------------------------------
-- Remote interface. Reads are for tests and other mods; set_tuning, clear_chunks and run_event
-- are for testing.

local function copy(t)
  local c = {}
  for k, value in pairs(t) do c[k] = value end
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
      setting_up = storage.setup ~= nil,
      surface_index = v and v.surface_index,
      initialized_tick = v and v.initialized_tick,
      safe_chunk_count = v and v.safe_chunk_count or 0,
      safe_candidate_count = v and table_size(v.safe_candidates) or 0,
      cleared_chunk_count = v and v.cleared_chunk_count or 0,
      frontier_count = v and #v.frontier.list or 0,
      safe_frontier_count = v and #v.safe_frontier.list or 0,
      explored_count = v and #v.explored or 0,
      territory_count = table_size(storage.index and storage.index.terr or {}),
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
        parent_dead = not index.alive(index.get(nest.parent_tid)), eggs = eggs,
      }
    end
    return result
  end,
  -- Array of {x, y} chunk positions in the recorded safe starting area.
  get_safe_chunks = function()
    local result = {}
    local v = storage.vulcanus
    if not v then return result end
    for k in pairs(v.safe_chunks) do
      local x, y = index.unkey(k)
      result[#result + 1] = { x = x, y = y }
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
    return v ~= nil and v.cleared_chunks[key(x, y)] ~= nil
  end,
  is_safe_chunk = function(x, y)
    return is_safe_chunk({ x = x, y = y })
  end,
  -- Testing: check the index against the game. Returns a list of problems (empty if consistent).
  verify_index = function()
    local surface = tracked_surface()
    local problems = {}
    if not surface then return problems end
    local seen = 0
    for _, territory in pairs(surface.get_territories()) do
      seen = seen + 1
      local tid = index.tid_of_territory(territory)
      local t = tid and index.get(tid)
      if not t then
        problems[#problems + 1] = "territory not indexed"
      else
        local chunks = territory.get_chunks()
        if #chunks ~= t.count then problems[#problems + 1] = "territory " .. tid .. " has " .. #chunks .. " chunks, index " .. t.count end
        for _, c in pairs(chunks) do
          if index.owner_at(c.x, c.y) ~= tid then problems[#problems + 1] = "chunk " .. chunk_name(c) .. " owner mismatch"; break end
        end
        local unit = territory.get_segmented_units()[1]
        if (unit and unit.unit_number) ~= t.unit_number then problems[#problems + 1] = "territory " .. tid .. " unit mismatch" end
      end
    end
    if seen ~= table_size(storage.index.terr) then
      problems[#problems + 1] = "game has " .. seen .. " territories, index " .. table_size(storage.index.terr)
    end
    return problems
  end,
  -- Testing: override tuning.lua values, e.g. set_tuning{nest_min_chunks = 10}.
  set_tuning = function(values)
    tuning.set(values)
    local surface = tracked_surface()
    if surface then schedule_all(surface) end
  end,
  -- Testing: lay a nest for a demolisher now, without the trip: at its territory's centre, or in
  -- the given chunk of its territory. Returns the nest chunk, or nil.
  place_nest = function(unit_number, in_chunk)
    local surface = tracked_surface()
    local tid = index.tid_of_unit(unit_number)
    local t = tid and index.get(tid)
    if not (surface and index.alive(t)) then return nil end
    local site, chunk
    if in_chunk then
      if index.owner_at(in_chunk.x, in_chunk.y) ~= tid then return nil end
      chunk = { x = in_chunk.x, y = in_chunk.y }
      local centre = chunk_centre(chunk)
      site = surface.find_non_colliding_position("demolisher-egg", centre, 12, 1) or centre
    else
      site, chunk = nest_site(surface, t)
    end
    if not site then return nil end
    lay_nest(surface, { unit = t.unit, unit_number = unit_number, tid = tid, site = site, chunk = chunk })
    return chunk
  end,
  -- Testing: clear chunks the way a dead territory is cleared (no territory, marked cleared).
  clear_chunks = function(chunks)
    local surface = tracked_surface()
    if not surface then return end
    surface.set_territory_for_chunks(chunks, nil)
    for _, c in pairs(chunks) do
      local k = key(c.x, c.y)
      local tid = index.owner_of_key(k)
      if tid then
        index.remove_chunk(tid, k)
        local t = index.get(tid)
        if t and t.count == 0 then index.drop(tid) end
      end
      mark_cleared(c.x, c.y)
    end
    for _, c in pairs(chunks) do frontier_consider(c.x, c.y) end
  end,
  -- Testing: run one event now ("expansion", "growth", "nest", "hatch" or "vibration"). Returns
  -- whether it did something.
  run_event = function(name)
    local surface = tracked_surface()
    if not surface or not HANDLERS[name] then return false end
    return run_event(surface, name) and true or false
  end,
})
