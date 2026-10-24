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

-- The anti-jam stack inserter has no item of its own: it's built from, and mines to,
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
