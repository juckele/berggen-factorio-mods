local shared = require("shared")
local util_lib = require("prototypes.util")

local stack_entity = data.raw.inserter[shared.base_name]
local stack_item = data.raw.item[shared.base_name]

-- The stack inserter with one behaviour change.
local entity = table.deepcopy(stack_entity)
entity.name = shared.name
entity.wait_for_full_hand = false
entity.icon = nil
entity.icons = util_lib.recolored_icons(stack_entity)
entity.localised_name = nil
entity.localised_description = nil
entity.next_upgrade = nil
-- Sort right after the stack inserter (upgrade planner, Factoriopedia...). Without an order
-- the engine uses "z-" plus the order of the first item that builds it, which with smart
-- swapping is the stack inserter's, so the two would tie and sort by name.
entity.order = (stack_entity.order or ("z-" .. (stack_item.order or ""))) .. "-b[anti-jam]"
for _, key in pairs({
  "hand_base_picture", "hand_open_picture", "hand_closed_picture", "platform_picture",
}) do
  util_lib.recolor_graphics(entity[key])
end
if shared.distinct then
  entity.minable = table.deepcopy(stack_entity.minable) or {mining_time = 0.1}
  entity.minable.result = shared.name
  entity.minable.results = nil
  entity.placeable_by = nil
else
  -- Smart swapping: built from (blueprint, ghost, upgrade planner) and mined to stack
  -- inserter items.
  util_lib.sync_with_stack_inserter(entity)
end

-- Remnants in the same colours.
local stack_corpse = stack_entity.corpse and data.raw.corpse[stack_entity.corpse]
if stack_corpse then
  local corpse = table.deepcopy(stack_corpse)
  corpse.name = shared.name .. "-remnants"
  corpse.icon = nil
  corpse.icons = util_lib.recolored_icons(stack_corpse)
  util_lib.recolor_graphics(corpse.animation)
  entity.corpse = corpse.name
  data:extend({corpse})
end

-- Item. With smart swapping it has no recipe and only ever lives in a player's cursor
-- (see control.lua), so it doesn't get a recycling recipe either.
local item = table.deepcopy(stack_item)
item.name = shared.name
item.icon = nil
item.icons = util_lib.recolored_icons(stack_item)
item.place_result = shared.name
item.order = (stack_item.order or "") .. "-b[anti-jam]"
item.localised_name = nil
item.localised_description = nil
if not shared.distinct then
  item.auto_recycle = false
end

data:extend({entity, item})

if shared.distinct then
  -- Main recipe: a copy of the stack inserter recipe. data-final-fixes copies it again so
  -- changes other mods make to the stack inserter recipe carry over.
  util_lib.copy_stack_inserter_recipe()
end

if shared.quick_swap then
  -- Quick conversions between the two inserters. Neither can roll a quality upgrade, and
  -- neither is used for recycling, as an intermediate or for raw-resource totals.
  -- Pre-drawn nutrient-style icons while the stack inserter has its vanilla icon;
  -- otherwise a small copy of the input layered on the output.
  local stack_has_vanilla_icon = stack_item.icon == shared.vanilla_icon and not stack_item.icons
  local function conversion_icons(name, to, from)
    if stack_has_vanilla_icon then
      return {{icon = shared.conversion_icons[name], icon_size = 64}}
    end
    local icons = table.deepcopy(to)
    for _, layer in pairs(table.deepcopy(from)) do
      layer.scale = 0.25 * 64 / (layer.icon_size or 64)
      layer.shift = {-8, -8}
      layer.floating = true
      table.insert(icons, layer)
    end
    return icons
  end
  local stack_icons = stack_item.icons or {{icon = stack_item.icon, icon_size = stack_item.icon_size}}

  local function conversion(name, from, to, icons, order)
    return {
      type = "recipe",
      name = name,
      icons = icons,
      subgroup = stack_item.subgroup,
      order = order,
      enabled = false,
      energy_required = 0.1,
      ingredients = {{type = "item", name = from, amount = 1}},
      results = {{type = "item", name = to, amount = 1}},
      allow_quality = false,
      allow_productivity = false,
      allow_decomposition = false,
      allow_as_intermediate = false,
      auto_recycle = false,
    }
  end

  data:extend({
    -- Back to a stack inserter sorts first, then to an anti-jam stack inserter.
    conversion(shared.to_stack, shared.name, shared.base_name,
      conversion_icons(shared.to_stack, stack_icons, item.icons), item.order .. "-a"),
    conversion(shared.to_anti_jam, shared.base_name, shared.name,
      conversion_icons(shared.to_anti_jam, item.icons, stack_icons), item.order .. "-b"),
  })
end
