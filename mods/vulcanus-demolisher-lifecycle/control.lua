-- Vulcanus Demolisher Lifecycle
--
-- storage layout (schema 1):
--   storage.schema        integer, bumped when the layout changes
--   storage.vulcanus      nil until Vulcanus exists, then:
--     surface_index       index of the tracked Vulcanus surface
--     initialized_tick    tick the mod first set up on this surface
--     safe_chunks         set of "x,y" chunk keys forming the original safe starting area
--     safe_chunk_count    number of entries in safe_chunks
--     safe_candidates     set of "x,y" keys of ungenerated chunks still to be decided
--     cleared_chunks      map of "x,y" key -> chunk position: land of dead territories that living
--                         territories can retake. Includes ungenerated chunks.
--     cleared_chunk_count number of entries in cleared_chunks
--   storage.pending       territories to re-check after a demolisher died, keyed by chunk "x,y"
--   storage.last_expansion_tick
--   storage.stats         counters, exposed through the remote interface for tests and other mods

local SURFACE_NAME = "vulcanus"
local SCHEMA = 2

local SETTING_PROTECT = "demolisher-lifecycle-protect-starting-area"
local SETTING_INTERVAL = "demolisher-lifecycle-expansion-interval-ticks"
local SETTING_DEBUG = "demolisher-lifecycle-debug-log"

-- How far from the map origin (in chunks) to look for the starting area. Vulcanus puts its
-- starting area disc 100 * starting_area_radius + 32 tiles from the origin with a 224 tile radius.
local SAFE_ZONE_SCAN_RADIUS = 24
-- Expansion samples this many random territories per attempt instead of scanning all of them.
local EXPANSION_TERRITORY_SAMPLES = 8

local function debug_log(message)
  if settings.global[SETTING_DEBUG].value then
    log(message)
  end
end

local function chunk_key(chunk)
  return chunk.x .. "," .. chunk.y
end

local function new_stats()
  return {
    territories_cleared = 0,
    chunks_cleared = 0,
    expansions = 0,
    chunks_retaken = 0,
    expansions_blocked_by_safe_zone = 0,
  }
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
    -- 0.2.0 didn't mark cleared land, so land it cleared can't be retaken.
    v.cleared_chunks = {}
    v.cleared_chunk_count = 0
  end
  storage.last_expansion_tick = storage.last_expansion_tick or game.tick
end

local function tracked_surface()
  local v = storage.vulcanus
  if not v then return nil end
  local surface = game.surfaces[v.surface_index]
  if surface and surface.valid then return surface end
  return nil
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
-- living territories can retake it, so it removes the territory. LuaTerritory.destroy() would let
-- the map generator create a fresh territory (with a fresh demolisher) on any of its chunks that
-- get generated later, so instead the chunks are set to no territory, which also deletes the
-- territory. The chunks are marked as cleared so living territories can
-- retake them (see Expansion).
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
  storage.stats.territories_cleared = storage.stats.territories_cleared + 1
  storage.stats.chunks_cleared = storage.stats.chunks_cleared + #chunks
  debug_log("Cleared a territory of " .. #chunks .. " chunks")
end

local function clear_dead_territories(surface)
  for _, territory in pairs(surface.get_territories()) do
    if territory.valid and #territory.get_segmented_units() == 0 then
      clear_territory(surface, territory)
    end
  end
end

local function territory_reference_chunk(surface, territory)
  for _, chunk in pairs(territory.get_chunks()) do
    if surface.is_chunk_generated(chunk) then return chunk end
  end
  return nil
end

local function queue_territory_check(segmented_unit)
  local surface = tracked_surface()
  if not surface or not segmented_unit.valid or segmented_unit.surface ~= surface then return end
  local territory = segmented_unit.territory
  if not territory or not territory.valid then return end
  local chunk = territory_reference_chunk(surface, territory)
  if chunk then storage.pending[chunk_key(chunk)] = chunk end
end

-- Runs a tick after a death: during on_segmented_unit_died the dying unit is still listed as
-- guarding its territory.
local function process_pending()
  local surface = tracked_surface()
  local pending = storage.pending
  storage.pending = {}
  if not surface then return end
  for _, chunk in pairs(pending) do
    local territory = surface.get_territory_for_chunk(chunk)
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

-- Retaking: a cleared chunk next to a territory with a living demolisher joins that territory. This
-- works on cleared chunks nobody has explored yet, which plain expansion can't see.
local function try_retake(surface, protect)
  local v = storage.vulcanus
  local frontier, blocked = {}, false
  for key, chunk in pairs(v.cleared_chunks) do
    if surface.get_territory_for_chunk(chunk) ~= nil then
      unmark_cleared(key) -- taken some other way
    else
      for _, d in ipairs(NEIGHBOURS) do
        local territory = surface.get_territory_for_chunk({ x = chunk.x + d[1], y = chunk.y + d[2] })
        if has_living_units(territory) then
          if protect and is_safe_chunk(chunk) then
            blocked = true
          else
            frontier[#frontier + 1] = { key = key, chunk = chunk, territory = territory }
          end
          break
        end
      end
    end
  end
  if #frontier == 0 then return false, blocked end
  local pick = frontier[math.random(1, #frontier)]
  surface.set_territory_for_chunks({ pick.chunk }, pick.territory)
  pick.territory.regenerate_patrol_path()
  unmark_cleared(pick.key)
  storage.stats.expansions = storage.stats.expansions + 1
  storage.stats.chunks_retaken = storage.stats.chunks_retaken + 1
  debug_log("Territory retook cleared chunk " .. pick.key)
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
local function try_expand_free_land(surface, protect)
  local territories = {}
  for _, t in pairs(surface.get_territories()) do
    if #t.get_segmented_units() > 0 then territories[#territories + 1] = t end
  end
  if #territories == 0 then return false, false end

  local blocked_any = false
  for _ = 1, math.min(EXPANSION_TERRITORY_SAMPLES, #territories) do
    local index = math.random(1, #territories)
    local territory = territories[index]
    table.remove(territories, index)
    local targets, blocked = expansion_targets(surface, territory, protect)
    if blocked > 0 then blocked_any = true end
    if #targets > 0 then
      local target = targets[math.random(1, #targets)]
      surface.set_territory_for_chunks({ target }, territory)
      territory.regenerate_patrol_path()
      storage.stats.expansions = storage.stats.expansions + 1
      debug_log("Territory expanded into chunk " .. chunk_key(target))
      return true, blocked_any
    end
  end
  return false, blocked_any
end

local function try_expand(surface)
  local protect = settings.global[SETTING_PROTECT].value
  local done, blocked = try_retake(surface, protect)
  if not done then
    local blocked_free
    done, blocked_free = try_expand_free_land(surface, protect)
    blocked = blocked or blocked_free
  end
  if not done and blocked then
    storage.stats.expansions_blocked_by_safe_zone = storage.stats.expansions_blocked_by_safe_zone + 1
  end
  return done
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function initialize_vulcanus(surface)
  local v = storage.vulcanus
  if v and v.surface_index == surface.index then
    clear_dead_territories(surface)
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
  }
  storage.last_expansion_tick = game.tick
  debug_log("Initialized on " .. surface.name .. " with " .. count .. " safe chunks")
  clear_dead_territories(surface)
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
end)

script.on_event(defines.events.on_surface_created, function(event)
  local surface = game.surfaces[event.surface_index]
  if surface and surface.name == SURFACE_NAME then initialize_vulcanus(surface) end
end)

script.on_event(defines.events.on_surface_deleted, function(event)
  if storage.vulcanus and storage.vulcanus.surface_index == event.surface_index then
    storage.vulcanus = nil
    storage.pending = {}
  end
end)

script.on_event(defines.events.on_chunk_generated, on_chunk_generated)

script.on_event(defines.events.on_segmented_unit_died, function(event)
  queue_territory_check(event.segmented_unit)
end)

script.on_event(defines.events.script_raised_destroy_segmented_unit, function(event)
  queue_territory_check(event.segmented_unit)
end)

script.on_event(defines.events.on_tick, function(event)
  if next(storage.pending) then process_pending() end
  if event.tick - storage.last_expansion_tick >= settings.global[SETTING_INTERVAL].value then
    local surface = tracked_surface()
    if surface then
      storage.last_expansion_tick = event.tick
      try_expand(surface)
    end
  end
end)

script.on_nth_tick(60, function()
  -- Catches a Vulcanus created where on_surface_created doesn't reach this mod, such as another
  -- mod's on_init.
  if not tracked_surface() and game.surfaces[SURFACE_NAME] then check_vulcanus() end
end)

---------------------------------------------------------------------------------------------------
-- Remote interface (read-only). Used by the headless tests and available to other mods.

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

remote.add_interface("vulcanus-demolisher-lifecycle", {
  -- Summary of the mod's state. Returns a fresh table; changing it has no effect on the mod.
  get_state = function()
    local v = storage.vulcanus
    return {
      schema = storage.schema,
      initialized = v ~= nil,
      surface_index = v and v.surface_index,
      initialized_tick = v and v.initialized_tick,
      safe_chunk_count = v and v.safe_chunk_count or 0,
      safe_candidate_count = v and table_size(v.safe_candidates) or 0,
      cleared_chunk_count = v and v.cleared_chunk_count or 0,
      pending_checks = table_size(storage.pending or {}),
      last_expansion_tick = storage.last_expansion_tick,
      stats = copy(storage.stats or new_stats()),
    }
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
  -- Array of {x, y} chunk positions marked cleared and not yet retaken.
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
})
