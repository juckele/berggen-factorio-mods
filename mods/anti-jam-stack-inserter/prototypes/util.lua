local shared = require("shared")

local lib = {}

local function is_sprite(t)
  return t.filename ~= nil or t.filenames ~= nil or t.stripes ~= nil
end

-- Swaps vanilla stack inserter sprites in a graphics table for the purple ones.
-- Sprites it doesn't recognise (another mod's reskin) are tinted instead.
-- Shadows are left alone.
function lib.recolor_graphics(graphics)
  if type(graphics) ~= "table" then return end
  if is_sprite(graphics) and not graphics.draw_as_shadow then
    local replacement = graphics.filename and shared.graphics[graphics.filename]
    if replacement then
      graphics.filename = replacement
    else
      graphics.tint = shared.tint
    end
  end
  for key, value in pairs(graphics) do
    if type(value) == "table" and key ~= "tint" then
      lib.recolor_graphics(value)
    end
  end
end

-- Icon layers for a prototype with either `icon` or `icons`, recoloured the same way.
function lib.recolored_icons(prototype)
  local icons
  if prototype.icons then
    icons = table.deepcopy(prototype.icons)
  else
    icons = {{icon = prototype.icon, icon_size = prototype.icon_size}}
  end
  for _, layer in pairs(icons) do
    local replacement = shared.graphics[layer.icon]
    if replacement then
      layer.icon = replacement
    else
      layer.tint = shared.tint
    end
  end
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

-- Makes `data.raw.recipe[shared.name]` an exact copy of the current stack inserter
-- recipe, producing the anti-jam inserter instead.
function lib.copy_stack_inserter_recipe()
  local source = data.raw.recipe[shared.base_name]
  if not source then return false end
  local recipe = table.deepcopy(source)
  recipe.name = shared.name
  recipe.localised_name = nil
  recipe.localised_description = nil
  rename_item(recipe.results, shared.base_name, shared.name)
  if recipe.main_product == shared.base_name then
    recipe.main_product = shared.name
  end
  -- The recycler (data-updates) recycles it to the stack inserter recipe's ingredients.
  recipe.recycle_to_ingredients_of = shared.base_name
  recipe.auto_recycle = nil
  local item = data.raw.item[shared.name]
  if item then
    recipe.order = item.order
  end
  data.raw.recipe[shared.name] = recipe
  return true
end

-- Every technology that unlocks the stack inserter also unlocks the given recipes.
function lib.unlock_with_stack_inserter(recipe_names)
  local wanted = {}
  for _, name in pairs(recipe_names) do wanted[name] = true end

  for _, technology in pairs(data.raw.technology) do
    if technology.effects then
      local present, unlocks_stack = {}, false
      for _, effect in pairs(technology.effects) do
        if effect.type == "unlock-recipe" then
          present[effect.recipe] = true
          if effect.recipe == shared.base_name then unlocks_stack = true end
        end
      end
      if unlocks_stack then
        local effects = {}
        for _, effect in pairs(technology.effects) do
          table.insert(effects, effect)
          if effect.type == "unlock-recipe" and effect.recipe == shared.base_name then
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

  local source = data.raw.recipe[shared.base_name]
  for name in pairs(wanted) do
    local recipe = data.raw.recipe[name]
    if recipe and source then
      recipe.enabled = source.enabled
    end
  end
end

-- Smart swapping: built from, and mines to,
-- whatever builds and mines the stack inserter. Re-run in data-final-fixes so changes
-- other mods make to the stack inserter carry over.
function lib.sync_with_stack_inserter(entity)
  local stack = data.raw.inserter[shared.base_name]
  if not (entity and stack) then return end
  entity.minable = table.deepcopy(stack.minable)
  if stack.placeable_by then
    entity.placeable_by = table.deepcopy(stack.placeable_by)
  else
    local items = {}
    for name, item in pairs(data.raw.item) do
      if item.place_result == shared.base_name then
        table.insert(items, {item = name, count = 1})
      end
    end
    table.sort(items, function(a, b) return a.item < b.item end)
    entity.placeable_by = items
  end
end

return lib
