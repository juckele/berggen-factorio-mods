local shared = require("shared")
local util_lib = require("prototypes.util")

local mode = settings.startup[shared.mode_setting].value
local distinct = mode ~= "smart-swapping"
local quick_swap = mode == "distinct-item-quick-swap"

-- One anti-jam inserter: a copy of the base inserter that doesn't wait for a full hand.
local function make_variant(v)
  local base_entity = data.raw.inserter[v.base]
  local base_item = data.raw.item[v.base]
  if not (base_entity and base_item) then return end
  local colour = shared.colour(v.name)
  local map = shared.graphics(v.name, colour)
  local tint = shared.tints[colour]

  local entity = table.deepcopy(base_entity)
  entity.name = v.name
  entity.wait_for_full_hand = false
  entity.icon = nil
  entity.icons = util_lib.recolored_icons(base_entity, map, tint)
  entity.localised_name = nil
  entity.localised_description = nil
  entity.next_upgrade = nil
  -- Sort right after the base inserter (upgrade planner, Factoriopedia...). Without an
  -- order the engine uses "z-" plus the order of the first item that builds it, which with
  -- smart swapping is the base inserter's, so the two would tie and sort by name.
  entity.order = (base_entity.order or ("z-" .. (base_item.order or ""))) .. "-b[anti-jam]"
  for _, key in pairs({"hand_base_picture", "hand_open_picture", "hand_closed_picture", "platform_picture"}) do
    util_lib.recolor_graphics(entity[key], map, tint)
  end
  if distinct then
    entity.minable = table.deepcopy(base_entity.minable) or {mining_time = 0.1}
    entity.minable.result = v.name
    entity.minable.results = nil
    entity.placeable_by = nil
  else
    util_lib.sync_with_base(v, entity)
  end

  -- Remnants in the same colours.
  local base_corpse = base_entity.corpse and data.raw.corpse[base_entity.corpse]
  if base_corpse then
    local corpse = table.deepcopy(base_corpse)
    corpse.name = v.name .. "-remnants"
    corpse.icon = nil
    corpse.icons = util_lib.recolored_icons(base_corpse, map, tint)
    util_lib.recolor_graphics(corpse.animation, map, tint)
    entity.corpse = corpse.name
    data:extend({corpse})
  end

  -- Item. With smart swapping it has no recipe and only ever lives in a player's cursor
  -- (see control.lua), so it doesn't get a recycling recipe either.
  local item = table.deepcopy(base_item)
  item.name = v.name
  item.icon = nil
  item.icons = util_lib.recolored_icons(base_item, map, tint)
  item.place_result = v.name
  item.order = (base_item.order or "") .. "-b[anti-jam]"
  item.localised_name = nil
  item.localised_description = nil
  if not distinct then
    item.auto_recycle = false
  end

  data:extend({entity, item})

  if distinct then
    -- Main recipe: a copy of the base recipe. data-final-fixes copies it again so changes
    -- other mods make to the base recipe carry over.
    util_lib.copy_base_recipe(v)
  end
end

-- Quick conversions between a variant and its base inserter. Neither can roll a quality
-- upgrade, and neither is used for recycling, as an intermediate or for raw-resource totals.
-- Built after the long-handed stack inserter is recoloured, so its icons are current.
local function make_conversions(v)
  local base_item = data.raw.item[v.base]
  local item = data.raw.item[v.name]
  if not (base_item and item) then return end
  local function conversion(name, from, to, icons, order)
    return {
      type = "recipe",
      name = name,
      icons = icons,
      subgroup = base_item.subgroup,
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
  -- Pre-drawn nutrient-style icons for the stack inserter while it has its vanilla icon;
  -- otherwise the same layout built from icon layers.
  local to_variant_icons = util_lib.conversion_icons(base_item, item)
  local to_base_icons = util_lib.conversion_icons(item, base_item)
  if v.name == "anti-jam-stack-inserter" and base_item.icon == shared.vanilla_stack_icon and not base_item.icons then
    local files = shared.conversion_icon_files(shared.colour(v.name))
    to_variant_icons = {{icon = files.to_variant, icon_size = 64}}
    to_base_icons = {{icon = files.to_base, icon_size = 64}}
  end
  -- Back to the base inserter sorts first, then to the anti-jam one.
  data:extend({
    conversion(v.to_base, v.name, v.base, to_base_icons, item.order .. "-a"),
    conversion(v.to_variant, v.base, v.name, to_variant_icons, item.order .. "-b"),
  })
end

for _, v in pairs(shared.variants) do
  make_variant(v)
end

-- Optional recolour of the long-handed stack inserter itself (platform, arm and icon; its
-- hand stays yellow). Done after the long-handed anti-jam stack inserter was copied from it.
local lsi_colour = mods[shared.lsi_mod] and shared.colour("long-stack-inserter")
if lsi_colour then
  local map = shared.graphics("long-stack-inserter", lsi_colour)
  local lsi_entity = data.raw.inserter["long-stack-inserter"]
  if lsi_entity then
    lsi_entity.icons = util_lib.recolored_icons(lsi_entity, map, nil)
    lsi_entity.icon = nil
    for _, key in pairs({"hand_base_picture", "platform_picture"}) do
      util_lib.recolor_graphics(lsi_entity[key], map, nil)
    end
  end
  local lsi_item = data.raw.item["long-stack-inserter"]
  if lsi_item then
    lsi_item.icons = util_lib.recolored_icons(lsi_item, map, nil)
    lsi_item.icon = nil
  end
end

if quick_swap then
  for _, v in pairs(shared.variants) do
    make_conversions(v)
  end
end
