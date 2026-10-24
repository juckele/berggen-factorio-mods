local shared = require("shared")
local util_lib = require("prototypes.util")

if shared.distinct then
  -- Re-copy the stack inserter recipe so changes other mods made to it carry over.
  util_lib.copy_stack_inserter_recipe()

  -- Unlock alongside the stack inserter, wherever the tech tree now puts it.
  local unlocks = {shared.name}
  if shared.quick_swap then
    table.insert(unlocks, shared.to_anti_jam)
    table.insert(unlocks, shared.to_stack)
  end
  util_lib.unlock_with_stack_inserter(unlocks)
else
  -- Build from and mine to whatever the stack inserter uses, after other mods' changes.
  util_lib.sync_with_stack_inserter(data.raw.inserter[shared.name])
end
