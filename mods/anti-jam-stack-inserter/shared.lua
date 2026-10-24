local shared = {}

shared.name = "anti-jam-stack-inserter"
shared.base_name = "stack-inserter"
shared.to_anti_jam = "anti-jam-stack-inserter-from-stack-inserter"
shared.to_stack = "stack-inserter-from-anti-jam-stack-inserter"

-- Startup setting:
--   smart-swapping            no item of its own in practice: built from and mined to stack
--                             inserters; the item only exists in the cursor (control.lua)
--   distinct-item             its own item and recipe, like any other inserter
--   distinct-item-quick-swap  distinct-item plus quick conversion recipes both ways
shared.mode_setting = "anti-jam-stack-inserter-mode"
shared.mode = settings.startup[shared.mode_setting].value
shared.distinct = shared.mode ~= "smart-swapping"
shared.quick_swap = shared.mode == "distinct-item-quick-swap"

local G = "__anti-jam-stack-inserter__/graphics/"
local SA = "__space-age__/graphics/"

-- Vanilla stack inserter graphics and their purple replacements. Same sizes and
-- layout, so the stack inserter's sprite definitions are reused as they are.
shared.graphics = {
  [SA .. "entity/stack-inserter/stack-inserter-hand-base.png"] = G .. "entity/anti-jam-stack-inserter-hand-base.png",
  [SA .. "entity/stack-inserter/stack-inserter-hand-open.png"] = G .. "entity/anti-jam-stack-inserter-hand-open.png",
  [SA .. "entity/stack-inserter/stack-inserter-hand-closed.png"] = G .. "entity/anti-jam-stack-inserter-hand-closed.png",
  [SA .. "entity/stack-inserter/stack-inserter-platform.png"] = G .. "entity/anti-jam-stack-inserter-platform.png",
  [SA .. "entity/stack-inserter/remnants/stack-inserter-remnants.png"] = G .. "entity/anti-jam-stack-inserter-remnants.png",
  [SA .. "icons/stack-inserter.png"] = G .. "icons/anti-jam-stack-inserter.png",
}
shared.vanilla_icon = SA .. "icons/stack-inserter.png"
shared.conversion_icons = {
  [shared.to_anti_jam] = G .. "icons/anti-jam-stack-inserter-from-stack-inserter.png",
  [shared.to_stack] = G .. "icons/stack-inserter-from-anti-jam-stack-inserter.png",
}

-- Fallback for sprites another mod has replaced: multiplied into them.
shared.tint = {r = 0.75, g = 0.45, b = 1.0, a = 1.0}

return shared
