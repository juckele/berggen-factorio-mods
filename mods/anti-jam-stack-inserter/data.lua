local shared = require("shared")
local util_lib = require("prototypes.util")

local stack_entity = data.raw.inserter[shared.base_name]

-- The stack inserter with one behaviour change. It has no item or recipe: it's built
-- from stack inserter items (by blueprint, ghost or upgrade planner) and mines back to
-- stack inserters.
local entity = table.deepcopy(stack_entity)
entity.name = shared.name
entity.wait_for_full_hand = false
entity.icon = nil
entity.icons = util_lib.recolored_icons(stack_entity)
entity.localised_name = nil
entity.localised_description = nil
entity.next_upgrade = nil
for _, key in pairs({
  "hand_base_picture", "hand_open_picture", "hand_closed_picture", "platform_picture",
}) do
  util_lib.recolor_graphics(entity[key])
end
util_lib.sync_with_stack_inserter(entity)

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

data:extend({entity})
