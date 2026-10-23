local shared = require("shared")

local lib = {}

local function is_sprite(t)
  return t.filename ~= nil or t.filenames ~= nil or t.stripes ~= nil
end

-- Tints every sprite definition inside a graphics table, leaving shadows alone.
function lib.tint_graphics(graphics)
  if type(graphics) ~= "table" then return end
  if is_sprite(graphics) and not graphics.draw_as_shadow then
    graphics.tint = shared.tint
  end
  for key, value in pairs(graphics) do
    if type(value) == "table" and key ~= "tint" then
      lib.tint_graphics(value)
    end
  end
end

-- Returns tinted icon layers for a prototype with either `icon` or `icons`.
function lib.tinted_icons(prototype)
  local icons
  if prototype.icons then
    icons = table.deepcopy(prototype.icons)
  else
    icons = {{icon = prototype.icon, icon_size = prototype.icon_size}}
  end
  for _, layer in pairs(icons) do
    layer.tint = shared.tint
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

return lib
