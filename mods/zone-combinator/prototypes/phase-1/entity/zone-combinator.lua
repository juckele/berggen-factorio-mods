local entity_prototype = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity_prototype.name = "zone-combinator"
entity_prototype.minable.result = "zone-combinator"
entity_prototype.icons = {
  {
    icon = entity_prototype.icon,
    icon_size = entity_prototype.icon_size,
  },
  {
    icon = "__zone-combinator__/graphics/icons/zone-combinator/constant-combinator-mask.png",
    icon_size = 64,
    tint = zone_combinator.tint,
  }
}
entity_prototype.icon = nil
entity_prototype.icon_size = nil

local mask = make_4way_animation_from_spritesheet({
  layers = {
    {
      filename = "__zone-combinator__/graphics/entity/zone-combinator/hr-constant-combinator-mask.png",
      width = 114,
      height = 102,
      scale = 0.5,
      shift = util.by_pixel(0, 5),
      tint = zone_combinator.tint,
    }
  }
})
for direction_name, sprite_direction in pairs(entity_prototype.sprites) do
  table.insert(sprite_direction.layers, mask[direction_name].layers[1])
end

data:extend({entity_prototype})
