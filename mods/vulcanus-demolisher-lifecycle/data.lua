-- Nest and egg entities. Placeholder graphics are the mod's own (graphics/README.md lists every
-- sheet's layout); the egg's hit and death debris are the big hot volcanic rock's.

local util = require("util")
local G = "__vulcanus-demolisher-lifecycle__/graphics/"

local function rock(name)
  local source = data.raw["simple-entity"][name]
  assert(source, "Space Age rock " .. name .. " not found")
  return source
end

local egg_rock = rock("big-volcanic-rock-hot")

-- Nest: 2 variations of 384x320. Egg: 4 variations of 128x128, each with a glow layer and a
-- 176x128 shadow.
local nest_pictures, egg_pictures = {}, {}
for i = 0, 1 do
  nest_pictures[i + 1] = {
    filename = G .. "entity/demolisher-nest/demolisher-nest.png",
    width = 384, height = 320, x = 384 * i, shift = util.by_pixel(0, -5), scale = 0.5,
  }
end
for i = 0, 3 do
  egg_pictures[i + 1] = {
    layers = {
      { filename = G .. "entity/demolisher-egg/demolisher-egg.png",
        width = 128, height = 128, x = 128 * i, shift = util.by_pixel(0, -3), scale = 0.5 },
      { filename = G .. "entity/demolisher-egg/demolisher-egg-glow.png", draw_as_glow = true,
        width = 128, height = 128, x = 128 * i, shift = util.by_pixel(0, -3), scale = 0.5 },
      { filename = G .. "entity/demolisher-egg/demolisher-egg-shadow.png", draw_as_shadow = true,
        width = 176, height = 128, x = 176 * i, shift = util.by_pixel(12, -3), scale = 0.5 },
    },
  }
end

data:extend({
  {
    -- Marks the nest site. Can't be damaged or mined; it disappears when its last egg is gone.
    type = "simple-entity-with-force",
    name = "demolisher-nest",
    icon = G .. "icons/demolisher-nest.png",
    icon_size = 64,
    flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable" },
    hidden = true,
    collision_box = { { -1.2, -0.9 }, { 1.2, 0.9 } },
    selection_box = { { -1.7, -1.3 }, { 1.7, 1.3 } },
    collision_mask = { layers = {} },
    render_layer = "floor-mechanics",
    max_health = 1,
    pictures = nest_pictures,
  },
  {
    -- One future demolisher. Destroying it before it hatches stops that demolisher.
    type = "simple-entity-with-force",
    name = "demolisher-egg",
    icon = G .. "icons/demolisher-egg.png",
    icon_size = 64,
    -- Red dots on the map.
    flags = { "placeable-off-grid", "not-blueprintable", "not-deconstructable" },
    hidden = true,
    collision_box = { { -0.7, -0.7 }, { 0.7, 0.7 } },
    selection_box = { { -1.0, -1.0 }, { 1.0, 0.8 } },
    render_layer = "object",
    max_health = 5000,
    resistances = { { type = "fire", percent = 100 } },
    damaged_trigger_effect = table.deepcopy(egg_rock.damaged_trigger_effect),
    dying_trigger_effect = table.deepcopy(egg_rock.dying_trigger_effect),
    pictures = egg_pictures,
    map_color = { 255, 0, 0 },
    enemy_map_color = { 255, 0, 0 },
    is_military_target = true,
  },
})
require("prototypes.lure-turret")
