-- Data-stage helpers. `v` is one of shared.variants: {name, base, to_variant, to_base, ...}.
local lib = {}

local function is_sprite(t)
  return t.filename ~= nil or t.filenames ~= nil or t.stripes ~= nil
end

-- Swaps known sprites in a graphics table for ours (`map`: original file -> our file).
-- Sprites it doesn't recognise (another mod's reskin) get `tint` instead, if given.
-- Shadows are left alone.
function lib.recolor_graphics(graphics, map, tint)
  if type(graphics) ~= "table" then return end
  if is_sprite(graphics) and not graphics.draw_as_shadow then
    local replacement = graphics.filename and map[graphics.filename]
    if replacement then
      graphics.filename = replacement
    elseif tint then
      graphics.tint = tint
    end
  end
  for key, value in pairs(graphics) do
    if type(value) == "table" and key ~= "tint" then
      lib.recolor_graphics(value, map, tint)
    end
  end
end

local function icon_layers(prototype)
  if prototype.icons then return table.deepcopy(prototype.icons) end
  return {{icon = prototype.icon, icon_size = prototype.icon_size}}
end

-- Icon layers for a prototype with either `icon` or `icons`, recoloured the same way.
function lib.recolored_icons(prototype, map, tint)
  local icons = icon_layers(prototype)
  for _, layer in pairs(icons) do
    local replacement = map[layer.icon]
    if replacement then
      layer.icon = replacement
    elseif tint then
      layer.tint = tint
    end
  end
  return icons
end

-- Nutrient-style recipe icon built from layers: the input at the top left, the output
-- slightly larger at the bottom right, in front. Item icons are 32 units across.
function lib.conversion_icons(input, output)
  local icons = {}
  local function add(layers, factor, offset)
    for _, layer in pairs(table.deepcopy(layers)) do
      local base_scale = layer.scale or (32 / (layer.icon_size or 64))
      local shift = layer.shift or {0, 0}
      layer.scale = base_scale * factor
      layer.shift = {(shift[1] or shift.x or 0) * factor + offset, (shift[2] or shift.y or 0) * factor + offset}
      table.insert(icons, layer)
    end
  end
  add(icon_layers(input), 0.66, -(32 - 32 * 0.66) / 2)
  add(icon_layers(output), 0.72, (32 - 32 * 0.72) / 2)
  return icons
end

local function rename_item(list, from, to)
  if not list then return end
  for _, entry in pairs(list) do
    if entry.type == "item" and entry.name == from then
      entry.name = to
    end
  end
end

-- Makes `data.raw.recipe[v.name]` an exact copy of the base inserter's recipe, producing
-- the variant instead, and recycling to the base recipe's ingredients.
function lib.copy_base_recipe(v)
  local source = data.raw.recipe[v.base]
  if not source then return false end
  local recipe = table.deepcopy(source)
  recipe.name = v.name
  recipe.localised_name = nil
  recipe.localised_description = nil
  rename_item(recipe.results, v.base, v.name)
  if recipe.main_product == v.base then
    recipe.main_product = v.name
  end
  recipe.recycle_to_ingredients_of = v.base
  recipe.auto_recycle = nil
  local item = data.raw.item[v.name]
  if item then
    recipe.order = item.order
  end
  data.raw.recipe[v.name] = recipe
  return true
end

-- Every technology that unlocks the base inserter's recipe also unlocks `recipe_names`,
-- right after it.
function lib.unlock_with_base(v, recipe_names)
  local wanted = {}
  for _, name in pairs(recipe_names) do wanted[name] = true end

  for _, technology in pairs(data.raw.technology) do
    if technology.effects then
      local present, unlocks_base = {}, false
      for _, effect in pairs(technology.effects) do
        if effect.type == "unlock-recipe" then
          present[effect.recipe] = true
          if effect.recipe == v.base then unlocks_base = true end
        end
      end
      if unlocks_base then
        local effects = {}
        for _, effect in pairs(technology.effects) do
          table.insert(effects, effect)
          if effect.type == "unlock-recipe" and effect.recipe == v.base then
            for _, name in pairs(recipe_names) do
              if not present[name] then
                table.insert(effects, {type = "unlock-recipe", recipe = name})
                present[name] = true
              end
            end
          end
        end
        technology.effects = effects
      end
    end
  end

  local source = data.raw.recipe[v.base]
  for name in pairs(wanted) do
    local recipe = data.raw.recipe[name]
    if recipe and source then
      recipe.enabled = source.enabled
    end
  end
end

-- Smart swapping: built from, and mines to, whatever builds and mines the base inserter.
-- Re-run in data-final-fixes so changes other mods make to the base carry over.
function lib.sync_with_base(v, entity)
  local base = data.raw.inserter[v.base]
  if not (entity and base) then return end
  entity.minable = table.deepcopy(base.minable)
  if base.placeable_by then
    entity.placeable_by = table.deepcopy(base.placeable_by)
  else
    local items = {}
    for name, item in pairs(data.raw.item) do
      if item.place_result == v.base then
        table.insert(items, {item = name, count = 1})
      end
    end
    table.sort(items, function(a, b) return a.item < b.item end)
    entity.placeable_by = items
  end
end

return lib
