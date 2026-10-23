local shared = require("shared")
local util_lib = require("prototypes.util")

-- Re-copy the stack inserter recipe so changes other mods made to it carry over.
util_lib.copy_stack_inserter_recipe()

-- Unlock alongside the stack inserter, wherever the tech tree now puts it.
local unlocks = {shared.name}
if settings.startup[shared.conversion_setting].value then
  table.insert(unlocks, shared.to_anti_jam)
  table.insert(unlocks, shared.to_stack)
end
util_lib.unlock_with_stack_inserter(unlocks)
