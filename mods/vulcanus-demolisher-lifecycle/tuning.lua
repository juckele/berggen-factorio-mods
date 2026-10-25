-- Balance constants. Every value here is a placeholder until the balance pass.
--
-- Tests (and anyone experimenting) can override any key at runtime with the remote call
-- set_tuning{key = value}; overrides are stored in storage.tuning and survive saving.

local defaults = {
  -- Four global event clocks. Each cooldown uses vanilla's biter expansion formula on the map's
  -- enemy expansion settings, lerp(max_cooldown, min_cooldown, -e^2 + 2e) with e the enemy
  -- evolution on Vulcanus, times the event's scale, divided by the pollution multiplier.
  -- On default map settings (10 to 60 minutes) a scale of 1/20 is 30 s to 3 min.
  expansion_scale = 1 / 20, -- one cleared chunk retaken
  growth_scale = 1 / 4,     -- one demolisher grows a size
  nest_scale = 1 / 2,       -- one max-size demolisher starts a nesting trip
  hatch_scale = 1 / 10,     -- one egg hatches
  -- Turn single events off (tests use this to isolate behaviour).
  expansion_enabled = true,
  growth_enabled = true,
  nest_enabled = true,
  hatch_enabled = true,

  -- Growth. Sizes in order; the last is the max size, which can nest.
  tiers = { "small-demolisher", "medium-demolisher", "big-demolisher" },
  -- Territory size (chunks) at which growth into each tier is 50% likely on a growth event.
  growth_midpoint = { ["medium-demolisher"] = 120, ["big-demolisher"] = 180 },
  -- Sigmoid width in chunks: about 2.2 widths from the midpoint takes the odds to 10% or 90%.
  growth_width = 15,
  -- Distance gate: a demolisher can grow at most this many sizes above what the map generator
  -- places at its distance from the origin (demolisher_variation_expression).
  growth_tiers_above_native = 1,

  -- Nesting.
  nest_min_chunks = 150,      -- territory size needed to nest
  nest_max_trips = 2,         -- nesting trips in progress at once, for performance
  nest_arrive_distance = 24,  -- head distance from the nest that ends travel and starts the coil
  nest_travel_timeout = 3 * 60 * 60,
  nest_coil_outer_radius = 10,
  nest_coil_inner_radius = 4, -- leaves room for the eggs inside the coil
  nest_coil_min_speed = 0.03, -- tiles per tick while coiling
  nest_build_ticks = 10 * 60, -- time spent coiled before the nest appears
  nest_retry_cooldown = 5 * 60 * 60, -- per demolisher, after an interrupted trip
  eggs_min = 1,
  eggs_max = 3,

  -- Vibration. Every check interval, each territory's loudest explored chunk is found; if its
  -- vibration is at least the threshold, the territory's demolisher investigates it (unless it is
  -- fighting, already investigating, nesting, or investigated within the cooldown).
  -- For scale: one working electric drill emits 10 per minute, and a chunk of rock absorbs
  -- about 1.2 per minute.
  vibration_check_interval = 5 * 60,
  vibration_investigate_threshold = 20,
  vibration_investigate_cooldown = 60 * 60,

  -- Hatching: each hatch event picks one egg old enough to hatch, weighted by its situation.
  egg_min_age = 2 * 60 * 60,  -- no egg hatches younger than this
  egg_old_age = 30 * 60 * 60, -- an egg with nowhere better to go hatches only once this old
  hatch_weight_dead_parent = 10,
  hatch_weight_free_space = 3,
  hatch_weight_old = 1,
}

local M = { defaults = defaults }

function M.get(key)
  local overrides = storage and storage.tuning
  if overrides and overrides[key] ~= nil then return overrides[key] end
  return defaults[key]
end

function M.set(values)
  storage.tuning = storage.tuning or {}
  for key, value in pairs(values) do
    if defaults[key] == nil then error("Unknown tuning key " .. tostring(key)) end
    storage.tuning[key] = value
  end
end

return M
