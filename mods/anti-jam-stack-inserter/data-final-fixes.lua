local shared = require("shared")
local util_lib = require("prototypes.util")

local mode = settings.startup[shared.mode_setting].value

for _, v in pairs(shared.variants) do
  local entity = data.raw.inserter[v.name]
  if entity then
    if mode ~= "smart-swapping" then
      if mode ~= "crafted-upgrade" then
        -- Re-copy the base recipe so changes other mods made to it carry over.
        util_lib.copy_base_recipe(v)
      end
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

-- The anti-jam stack inserter as the bulk inserter's default upgrade (what an upgrade planner
-- with no rules does). Left alone if another mod already gave the bulk inserter an upgrade.
-- The stack inserter itself still has no upgrade or downgrade.
local bulk_upgrade = settings.startup["anti-jam-stack-inserter-bulk-upgrade"]
local bulk = data.raw.inserter["bulk-inserter"]
if bulk_upgrade and bulk_upgrade.value and bulk and data.raw.inserter["anti-jam-stack-inserter"] then
  if bulk.next_upgrade == nil or bulk.next_upgrade == "" then
    bulk.next_upgrade = "anti-jam-stack-inserter"
  else
    log("Anti-jam Stack Inserter: bulk inserter already upgrades to " .. bulk.next_upgrade .. "; not changing it.")
  end
end

