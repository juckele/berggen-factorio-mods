local shared = require("shared")
local util_lib = require("prototypes.util")

local mode = settings.startup[shared.mode_setting].value

for _, v in pairs(shared.variants) do
  local entity = data.raw.inserter[v.name]
  if entity then
    if mode ~= "smart-swapping" then
      -- Re-copy the base recipe so changes other mods made to it carry over.
      util_lib.copy_base_recipe(v)
      -- Unlock alongside the base inserter, wherever the tech tree now puts it.
      local unlocks = {v.name}
      if mode == "distinct-item-quick-swap" then
        table.insert(unlocks, v.to_base)
        table.insert(unlocks, v.to_variant)
      end
      util_lib.unlock_with_base(v, unlocks)
    else
      -- Build from and mine to whatever the base inserter uses, after other mods' changes.
      util_lib.sync_with_base(v, entity)
    end
  end
end
