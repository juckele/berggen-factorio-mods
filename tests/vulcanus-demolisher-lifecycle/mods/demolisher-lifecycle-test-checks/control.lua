-- Checks for Vulcanus Demolisher Lifecycle. Each phase name in tests.json maps to a handler below.
-- The mod's state is read through its remote interface ("vulcanus-demolisher-lifecycle").

local H = require("__headless-test-harness__/harness")
H.install()

local MOD = "vulcanus-demolisher-lifecycle"
local SETUP = "demolisher-lifecycle-test-setup"
local PROTECT = "demolisher-lifecycle-protect-starting-area"

local function state() return remote.call(MOD, "get_state") end
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

local phases = {}

---------------------------------------------------------------------------------------------------
-- new-game: the mod is in the save from the start; Vulcanus is created mid-game.

phases["new-game-create"] = {
  init = function()
    local s = state()
    H.check("no-vulcanus-yet", vulcanus() == nil)
    H.check("not-initialized-without-vulcanus", not s.initialized)
    H.equal("schema", s.schema, 2)
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
      -- Retaking may already have started, so cleared + retaken must account for every chunk.
      H.equal("kill-marks-chunks-cleared", s.cleared_chunk_count + s.stats.chunks_retaken, #victim.chunks)
      H.equal("only-retaken-chunks-have-territory", chunks_with_territory(victim.chunks), s.stats.chunks_retaken)
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
      H.equal("all-cleared-land-retaken", chunks_with_territory(victim.chunks), #victim.chunks)
      H.equal("no-cleared-chunks-left", s.cleared_chunk_count, 0)
      H.equal("chunks-retaken", s.stats.chunks_retaken, #victim.chunks)
      H.equal("retaking-spawns-no-demolishers", #vulcanus().get_segmented_units(), victim.units)
      H.equal("protected-safe-zone-stays-safe", safe_in_territory(), 0)
      H.check("safe-zone-blocked-expansion", s.stats.expansions_blocked_by_safe_zone > 0,
        s.stats.expansions_blocked_by_safe_zone .. " blocked attempts")
      H.done()
    end)
  end,
}

---------------------------------------------------------------------------------------------------
-- unprotected: Vulcanus exists when the mod initializes; protection is off.

phases["unprotected-create"] = {
  init = function()
    check_initialized("on-init-with-vulcanus")
    H.check("protection-off", not settings.global[PROTECT].value)
    H.done()
  end,
}

phases["unprotected-run"] = {
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
      H.equal("all-cleared-land-retaken", chunks_with_territory(all), #all)
      H.equal("no-cleared-chunks-left", s.cleared_chunk_count, 0)
      local still_ungenerated = 0
      for _, c in ipairs(ungenerated) do
        if not vulcanus().is_chunk_generated(c) then still_ungenerated = still_ungenerated + 1 end
      end
      H.equal("ungenerated-chunks-retaken-unexplored", still_ungenerated, #ungenerated)
      generate(ungenerated)
    end)
    H.at(3501, function()
      local record = setup_record()
      H.equal("exploring-retaken-land-keeps-territory", chunks_with_territory(ungenerated), #ungenerated)
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
if phase.init then
  script.on_init(phase.init)
end
if phase.setting_changed then
  script.on_event(defines.events.on_runtime_mod_setting_changed, phase.setting_changed)
end
