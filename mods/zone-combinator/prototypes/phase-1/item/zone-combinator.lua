data:extend({
  {
    type = "item",
    name = "zone-combinator",
    icons =
    {
      -- Base
      {
        icon = "__base__/graphics/icons/constant-combinator.png",
        icon_size = 64,
        icon_mipmaps = 4,
      },
      -- Mask
      {
        icon = "__zone-combinator__/graphics/icons/zone-combinator/constant-combinator-mask.png",
        icon_size = 64,
        icon_mipmaps = 4,
        tint = zone_combinator.tint,
      },
    },
    order = "c[combinators]-c[zone-combinator]",
    subgroup = "circuit-network",
    stack_size = 50,
    place_result = "zone-combinator",
  }
})