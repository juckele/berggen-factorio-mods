local colours = {"automatic", "purple", "aqua", "magenta", "black"}

data:extend({
  {
    type = "string-setting",
    name = "anti-jam-stack-inserter-mode",
    setting_type = "startup",
    default_value = "smart-swapping",
    allowed_values = {"smart-swapping", "distinct-item", "distinct-item-quick-swap"},
    order = "a",
  },
  {
    type = "string-setting",
    name = "anti-jam-stack-inserter-colour",
    setting_type = "startup",
    default_value = "automatic",
    allowed_values = colours,
    order = "b",
  },
})

-- Only with the long-handed stack inserter mod installed.
if mods["long_stack_inserter"] then
  data:extend({
    {
      type = "string-setting",
      name = "anti-jam-stack-inserter-long-colour",
      setting_type = "startup",
      default_value = "automatic",
      allowed_values = colours,
      order = "c",
    },
    {
      type = "string-setting",
      name = "anti-jam-stack-inserter-lsi-colour",
      setting_type = "startup",
      default_value = "automatic",
      allowed_values = colours,
      order = "d",
    },
  })
end
