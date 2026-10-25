data:extend({
  {
    type = "bool-setting",
    name = "demolisher-lifecycle-protect-starting-area",
    setting_type = "runtime-global",
    default_value = true,
    order = "a",
  },
  {
    type = "int-setting",
    name = "demolisher-lifecycle-expansion-interval-ticks",
    setting_type = "runtime-global",
    -- 0 uses the map's enemy expansion settings scaled by evolution. Defaults to very fast so testers
    -- can watch territory grow back; release will default to 0.
    default_value = 10,
    minimum_value = 0,
    maximum_value = 216000,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "demolisher-lifecycle-debug-log",
    setting_type = "runtime-global",
    default_value = false,
    order = "z",
  },
})
