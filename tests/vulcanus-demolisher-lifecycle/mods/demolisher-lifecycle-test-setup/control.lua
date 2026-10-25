-- Builds save state in on_init, before Vulcanus Demolisher Lifecycle is added to the save.
--   params.vulcanus_radius  create Vulcanus and generate this many chunks around the origin
--   params.build            place a small base around the Vulcanus spawn
--   params.kill             kill this many demolishers, nearest to the spawn first
-- What it did is kept in storage.record and served through the remote interface below.

local H = require("__headless-test-harness__/harness")

local function chunk_of(position)
  return { x = math.floor(position.x / 32), y = math.floor(position.y / 32) }
end

local function build_base(surface, record)
  local force = game.forces.player
  local spawn = force.get_spawn_position(surface)
  local placed = {}
  local layout = {
    { "steel-chest", 4 }, { "small-electric-pole", 4 }, { "solar-panel", 4 },
    { "assembling-machine-2", 3 }, { "stone-wall", 10 },
  }
  for _, entry in ipairs(layout) do
    for _ = 1, entry[2] do
      local position = surface.find_non_colliding_position(entry[1], spawn, 48, 1)
      if position then
        local entity = surface.create_entity({ name = entry[1], position = position, force = force })
        if entity then placed[#placed + 1] = entity end
      end
    end
  end
  record.built_unit_numbers = {}
  record.built_chunks = {}
  for _, entity in ipairs(placed) do
    record.built_unit_numbers[#record.built_unit_numbers + 1] = entity.unit_number
    record.built_chunks[#record.built_chunks + 1] = chunk_of(entity.position)
  end
  record.spawn_chunk = chunk_of(spawn)
  H.check("setup-built-base", #placed >= 20, #placed .. " entities placed")
end

local function kill_demolishers(surface, count, record)
  local spawn = game.forces.player.get_spawn_position(surface)
  local units = surface.get_segmented_units()
  table.sort(units, function(a, b)
    local pa, pb = a.segments[1].position, b.segments[1].position
    return (pa.x - spawn.x) ^ 2 + (pa.y - spawn.y) ^ 2 < (pb.x - spawn.x) ^ 2 + (pb.y - spawn.y) ^ 2
  end)
  record.killed = {}
  for i = 1, math.min(count, #units) do
    local unit = units[i]
    local territory = unit.territory
    local generated, ungenerated = {}, {}
    for _, chunk in pairs(territory.get_chunks()) do
      if surface.is_chunk_generated(chunk) then
        generated[#generated + 1] = chunk
      else
        ungenerated[#ungenerated + 1] = chunk
      end
    end
    local name = unit.prototype.name
    unit.die()
    -- Vanilla behaviour this mod corrects: the territory outlives its last demolisher.
    H.check("vanilla-territory-survives-kill-" .. i, territory.valid and #territory.get_segmented_units() == 0,
      name .. " killed, territory valid=" .. tostring(territory.valid))
    record.killed[#record.killed + 1] = { name = name, generated = generated, ungenerated = ungenerated }
  end
  H.equal("setup-killed-count", #record.killed, count)
end

script.on_init(function()
  local p = H.params
  local record = {}
  storage.record = record
  if p.vulcanus_radius then
    local surface = game.planets.vulcanus.create_surface()
    surface.request_to_generate_chunks({ 0, 0 }, p.vulcanus_radius)
    surface.force_generate_chunk_requests()
    record.surface_index = surface.index
    if p.build then build_base(surface, record) end
    if p.kill then kill_demolishers(surface, p.kill, record) end
    record.territory_count = #surface.get_territories()
    record.unit_count = #surface.get_segmented_units()
    H.info("setup-territories", record.territory_count)
    H.info("setup-demolishers", record.unit_count)
  end
  H.done()
end)

remote.add_interface("demolisher-lifecycle-test-setup", {
  get_record = function() return storage.record end,
})
