local shared = {}

shared.name = "anti-jam-stack-inserter"
shared.base_name = "stack-inserter"

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

-- Fallback for sprites another mod has replaced: multiplied into them.
shared.tint = {r = 0.75, g = 0.45, b = 1.0, a = 1.0}

return shared
