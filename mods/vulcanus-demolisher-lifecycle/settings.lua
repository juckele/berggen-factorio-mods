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
    -- Very fast so testers can watch territory grow back; the balance pass will slow it down.
    default_value = 10,
    minimum_value = 1,
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
