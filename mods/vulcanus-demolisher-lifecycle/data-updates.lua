-- Vibration: Vulcanus's own pollution layer. Vanilla Vulcanus has no pollutant at all.
-- Emissions and tile absorption are added in data-final-fixes, so other mods' drills and pumps
-- are covered too.

data:extend({
  {
    type = "airborne-pollutant",
    name = "vibration",
    chart_color = { r = 230, g = 110, b = 20, a = 149 },
    icon = {
      filename = "__core__/graphics/icons/mip/side-map-menu-buttons.png",
      priority = "high",
      size = 64,
      mipmap_count = 2,
      y = 3 * 64,
      flags = { "gui-icon" },
    },
    -- Vibration raises evolution on Vulcanus, which shortens every demolisher event clock.
    affects_evolution = true,
    affects_water_tint = false,
    damages_trees = false,
  },
})

data.raw.planet.vulcanus.pollutant_type = "vibration"
