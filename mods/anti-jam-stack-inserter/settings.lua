local colors = {"automatic", "purple", "aqua", "magenta", "black"}
local lsi = mods["long_stack_inserter"] ~= nil

data:extend({
  {
    type = "string-setting",
    name = "anti-jam-stack-inserter-mode",
    setting_type = "startup",
    default_value = "smart-swapping",
    allowed_values = {"smart-swapping", "distinct-item", "distinct-item-quick-swap", "crafted-upgrade"},
    order = "a",
  },
  {
    type = "string-setting",
    name = "anti-jam-stack-inserter-color",
    setting_type = "startup",
    default_value = "automatic",
    allowed_values = colors,
    order = "b-a",
  },
  {
    -- Keep the vanilla yellow claw, like the long-handed stack inserter does. On by default
    -- when that mod is installed, so all the stack inserters match.
    type = "bool-setting",
    name = "anti-jam-stack-inserter-yellow-hand",
    setting_type = "startup",
    default_value = lsi,
    order = "b-b",
  },
  {
    -- Bulk inserter -> anti-jam stack inserter as the default upgrade (empty upgrade planner).
    type = "bool-setting",
    name = "anti-jam-stack-inserter-bulk-upgrade",
    setting_type = "startup",
    default_value = true,
    order = "b-c",
  },
})

-- Only with the Long Stack Inserter mod installed.
if mods["long_stack_inserter"] then
  data:extend({
    {
      type = "string-setting",
      name = "anti-jam-stack-inserter-long-color",
      setting_type = "startup",
      default_value = "automatic",
      allowed_values = colors,
      order = "c-a",
    },
    {
      type = "bool-setting",
      name = "anti-jam-stack-inserter-long-yellow-hand",
      setting_type = "startup",
      default_value = true,
      order = "c-b",
    },
    {
      type = "string-setting",
      name = "anti-jam-stack-inserter-lsi-color",
      setting_type = "startup",
      default_value = "automatic",
      allowed_values = colors,
      order = "d-a",
    },
    {
      type = "bool-setting",
      name = "anti-jam-stack-inserter-lsi-yellow-hand",
      setting_type = "startup",
      default_value = true,
      order = "d-b",
    },
  })
end

-- Descriptions that mention the Long Stack Inserter mod are only used when it's installed.
if lsi then
  for _, name in pairs({"anti-jam-stack-inserter-mode", "anti-jam-stack-inserter-color", "anti-jam-stack-inserter-yellow-hand"}) do
    local setting = data.raw["string-setting"][name] or data.raw["bool-setting"][name]
    setting.localised_description = {"mod-setting-description-long-handed." .. name}
  end
end
