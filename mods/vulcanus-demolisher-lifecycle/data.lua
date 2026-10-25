-- Nest and egg entities. Placeholder graphics: Vulcanus's hot volcanic rocks, until real art exists.

local function rock(name)
  local source = data.raw["simple-entity"][name]
  assert(source, "Space Age rock " .. name .. " not found")
  return source
end

local nest_rock = rock("huge-volcanic-rock-hot")
local egg_rock = rock("big-volcanic-rock-hot")

data:extend({
  {
    -- Marks the nest site. Can't be damaged or mined; it disappears when its last egg is gone.
    type = "simple-entity-with-force",
    name = "demolisher-nest",
    icon = nest_rock.icon,
    flags = { "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable" },
    hidden = true,
    collision_box = { { -1.2, -0.9 }, { 1.2, 0.9 } },
    selection_box = { { -1.7, -1.3 }, { 1.7, 1.3 } },
    collision_mask = { layers = {} },
    render_layer = "floor-mechanics",
    max_health = 1,
    pictures = table.deepcopy(nest_rock.pictures),
    map_color = { 255, 120, 30 },
  },
  {
    -- One future demolisher. Destroying it before it hatches stops that demolisher.
    type = "simple-entity-with-force",
    name = "demolisher-egg",
    icon = egg_rock.icon,
    flags = { "placeable-off-grid", "not-blueprintable", "not-deconstructable" },
    hidden = true,
    collision_box = { { -0.7, -0.7 }, { 0.7, 0.7 } },
    selection_box = { { -1.0, -1.0 }, { 1.0, 0.8 } },
    render_layer = "object",
    max_health = 5000,
    resistances = { { type = "fire", percent = 100 } },
    damaged_trigger_effect = table.deepcopy(egg_rock.damaged_trigger_effect),
    dying_trigger_effect = table.deepcopy(egg_rock.dying_trigger_effect),
    pictures = table.deepcopy(egg_rock.pictures),
    map_color = { 255, 160, 60 },
    is_military_target = true,
  },
})
