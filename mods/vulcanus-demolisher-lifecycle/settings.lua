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
    name = "demolisher-lifecycle-expansion-interval",
    setting_type = "runtime-global",
    -- Placeholder until the balance pass; see the README roadmap.
    default_value = 600,
    minimum_value = 1,
    maximum_value = 36000,
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
