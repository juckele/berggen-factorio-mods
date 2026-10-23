local shared = require("shared")
local util_lib = require("prototypes.util")

local stack_entity = data.raw.inserter[shared.base_name]
local stack_item = data.raw.item[shared.base_name]

-- Entity: the stack inserter with one behaviour change.
local entity = table.deepcopy(stack_entity)
entity.name = shared.name
entity.wait_for_full_hand = false
entity.icon = nil
entity.icons = util_lib.tinted_icons(stack_entity)
entity.minable = table.deepcopy(stack_entity.minable) or {mining_time = 0.1}
entity.minable.result = shared.name
entity.localised_name = nil
entity.localised_description = nil
entity.next_upgrade = nil
for _, key in pairs({
  "hand_base_picture", "hand_open_picture", "hand_closed_picture", "platform_picture",
}) do
  util_lib.tint_graphics(entity[key])
end

-- Remnants in the same colour.
local stack_corpse = stack_entity.corpse and data.raw.corpse[stack_entity.corpse]
if stack_corpse then
  local corpse = table.deepcopy(stack_corpse)
  corpse.name = shared.name .. "-remnants"
  corpse.icon = nil
  corpse.icons = util_lib.tinted_icons(stack_corpse)
  util_lib.tint_graphics(corpse.animation)
  entity.corpse = corpse.name
  data:extend({corpse})
end

-- Item.
local item = table.deepcopy(stack_item)
item.name = shared.name
item.icon = nil
item.icons = util_lib.tinted_icons(stack_item)
item.place_result = shared.name
item.order = (stack_item.order or "") .. "-b[anti-jam]"
item.localised_name = nil
item.localised_description = nil

data:extend({entity, item})

-- Main recipe: a copy of the stack inserter recipe. data-final-fixes copies it
-- again so changes other mods make to the stack inserter recipe carry over.
util_lib.copy_stack_inserter_recipe()

-- Optional quick conversions between the two inserters. Neither can roll a
-- quality upgrade, and neither is used for recycling, as an intermediate or for
-- raw-resource totals.
if settings.startup[shared.conversion_setting].value then
  local function conversion_icons(to, from)
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
    conversion(shared.to_anti_jam, shared.base_name, shared.name,
      conversion_icons(item.icons, stack_icons), item.order .. "-a"),
    conversion(shared.to_stack, shared.name, shared.base_name,
      conversion_icons(stack_icons, item.icons), item.order .. "-b"),
  })
end
