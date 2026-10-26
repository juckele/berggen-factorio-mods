-- Names, settings and graphics shared by the settings, data and control stages.
local shared = {}

shared.name = "anti-jam-stack-inserter"
shared.lsi_mod = "long_stack_inserter"

-- Startup setting "mode":
--   smart-swapping            built from and mined to the base inserter's item; the variant's
--                             own item only exists in the cursor (control.lua)
--   distinct-item             its own item and recipe, like any other inserter
--   distinct-item-quick-swap  distinct-item plus quick conversion recipes both ways
shared.mode_setting = "anti-jam-stack-inserter-mode"
shared.colour_settings = {
  ["anti-jam-stack-inserter"] = "anti-jam-stack-inserter-colour",
  ["long-anti-jam-stack-inserter"] = "anti-jam-stack-inserter-long-colour",
  ["long-stack-inserter"] = "anti-jam-stack-inserter-lsi-colour",
}
shared.colours = {"purple", "aqua", "magenta", "black"}

-- Fallback tints, used on sprites another mod has replaced (multiplied into them).
shared.tints = {
  purple = {r = 0.75, g = 0.45, b = 1.0, a = 1.0},
  aqua = {r = 0.45, g = 0.95, b = 1.0, a = 1.0},
  magenta = {r = 1.0, g = 0.45, b = 0.85, a = 1.0},
  black = {r = 0.32, g = 0.32, b = 0.35, a = 1.0},
}

local G = "__anti-jam-stack-inserter__/graphics/"
local SA = "__space-age__/graphics/"
local LSI = "__long_stack_inserter__/graphics/"
shared.vanilla_stack_icon = SA .. "icons/stack-inserter.png"

-- The inserters this mod adds, each an anti-jam copy of a base inserter. The long-handed
-- one only exists when the long-handed stack inserter mod is installed.
local function variant(name, base, long)
  return {
    name = name,
    base = base,
    long = long,
    to_variant = name .. "-from-" .. base,  -- conversion recipe: base -> variant
    to_base = base .. "-from-" .. name,     -- conversion recipe: variant -> base
  }
end
shared.variants = {variant("anti-jam-stack-inserter", "stack-inserter", false)}
if mods[shared.lsi_mod] then
  table.insert(shared.variants, variant("long-anti-jam-stack-inserter", "long-stack-inserter", true))
end

-- Resolves a colour setting. "automatic" means:
--   anti-jam stack inserter: black if the long-handed stack inserter is installed (its
--     purple is taken), otherwise purple
--   long-handed anti-jam stack inserter: aqua
--   long-handed stack inserter: nil (its own graphics, unchanged)
-- For the long-handed stack inserter, "purple" also means its own graphics.
function shared.colour(name)
  local setting = settings.startup[shared.colour_settings[name]]
  local value = setting and setting.value or "automatic"
  if name == "long-stack-inserter" then
    if value == "automatic" or value == "purple" then return nil end
    return value
  end
  if value ~= "automatic" then return value end
  if name == "long-anti-jam-stack-inserter" then return "aqua" end
  return mods[shared.lsi_mod] and "black" or "purple"
end

-- Maps the base inserter's graphics files to our files for one colour.
function shared.graphics(name, colour)
  local C = G .. colour .. "/"
  local hands = {
    [SA .. "entity/stack-inserter/stack-inserter-hand-open.png"] = C .. "entity/anti-jam-stack-inserter-hand-open.png",
    [SA .. "entity/stack-inserter/stack-inserter-hand-closed.png"] = C .. "entity/anti-jam-stack-inserter-hand-closed.png",
  }
  local map
  if name == "anti-jam-stack-inserter" then
    map = {
      [SA .. "entity/stack-inserter/stack-inserter-hand-base.png"] = C .. "entity/anti-jam-stack-inserter-hand-base.png",
      [SA .. "entity/stack-inserter/stack-inserter-platform.png"] = C .. "entity/anti-jam-stack-inserter-platform.png",
      [SA .. "entity/stack-inserter/remnants/stack-inserter-remnants.png"] = C .. "entity/anti-jam-stack-inserter-remnants.png",
      [SA .. "icons/stack-inserter.png"] = C .. "icons/anti-jam-stack-inserter.png",
    }
  elseif name == "long-anti-jam-stack-inserter" then
    map = {
      [LSI .. "entity/long-stack-inserter/long-stack-inserter-platform.png"] = C .. "entity/anti-jam-stack-inserter-platform.png",
      [LSI .. "entity/long-stack-inserter/long-stack-inserter-hand-base.png"] = C .. "entity/long-anti-jam-stack-inserter-hand-base.png",
      [SA .. "entity/stack-inserter/remnants/stack-inserter-remnants.png"] = C .. "entity/anti-jam-stack-inserter-remnants.png",
      [LSI .. "icons/long-stack-inserter.png"] = C .. "icons/long-anti-jam-stack-inserter.png",
    }
  else -- recolouring the long-handed stack inserter itself: platform, arm and icon only
    return {
      [LSI .. "entity/long-stack-inserter/long-stack-inserter-platform.png"] = C .. "entity/anti-jam-stack-inserter-platform.png",
      [LSI .. "entity/long-stack-inserter/long-stack-inserter-hand-base.png"] = C .. "entity/long-anti-jam-stack-inserter-hand-base.png",
      [LSI .. "icons/long-stack-inserter.png"] = C .. "icons/long-stack-inserter.png",
    }
  end
  for k, v in pairs(hands) do map[k] = v end
  return map
end

-- Pre-drawn conversion icons, used when the stack inserter still has its vanilla icon.
function shared.conversion_icon_files(colour)
  local C = G .. colour .. "/icons/"
  return {
    to_variant = C .. "anti-jam-stack-inserter-from-stack-inserter.png",
    to_base = C .. "stack-inserter-from-anti-jam-stack-inserter.png",
  }
end

return shared
