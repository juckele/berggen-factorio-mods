-- Vibration emissions and absorption. Placeholders until the balance pass.

-- Emissions per minute while working. Mining drills shake the ground most; pumps a little.
-- Prototypes not listed (including other mods') fall back by type.
local EMISSIONS = {
  ["burner-mining-drill"] = 6,
  ["electric-mining-drill"] = 10,
  ["big-mining-drill"] = 40,
  ["pump"] = 3,
  ["offshore-pump"] = 8,
}
local FALLBACK = {
  ["mining-drill"] = 10,
  ["pump"] = 3,
  ["offshore-pump"] = 8,
}

for type_name, fallback in pairs(FALLBACK) do
  for name, prototype in pairs(data.raw[type_name] or {}) do
    local source = prototype.energy_source
    if source then
      source.emissions_per_minute = source.emissions_per_minute or {}
      if source.emissions_per_minute.vibration == nil then
        source.emissions_per_minute.vibration = EMISSIONS[name] or fallback
      end
    end
  end
end

-- Absorption per tile per second. For scale, vanilla grass absorbs 0.000018 pollution and the
-- highest vanilla value (out of map) is 0.0001.
local LAVA = 0.0001  -- very high: lava swallows the vibration
local ROCK = 0.00002 -- medium-high: Vulcanus's solid volcanic ground

for name, tile in pairs(data.raw.tile) do
  local rate
  if name:find("^lava") then
    rate = LAVA
  elseif name:find("^volcanic") then
    rate = ROCK
  end
  if rate then
    -- Copy first: Space Age's Vulcanus tiles all share one absorption table.
    tile.absorptions_per_second = table.deepcopy(tile.absorptions_per_second or {})
    tile.absorptions_per_second.vibration = rate
  end
end
