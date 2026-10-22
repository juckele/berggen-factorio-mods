local entity_prototype = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity_prototype.name = "zone-combinator"
entity_prototype.minable.result = "zone-combinator"
local base_icon = entity_prototype.icon
local base_icon_size = entity_prototype.icon_size
local base_icon_mipmaps = entity_prototype.icon_mipmaps
entity_prototype.icons = {
  {
    icon = base_icon,
    icon_size = base_icon_size,
    icon_mipmaps = base_icon_mipmaps,
  },
  {
    icon = "__zone-combinator__/graphics/icons/zone-combinator/constant-combinator-mask.png",
    icon_size = 64,
    icon_mipmaps = 4,
    tint = zone_combinator.tint,
  }
}
local sprites = make_4way_animation_from_spritesheet({
  layers = {
    {
      filename = "__zone-combinator__/graphics/entity/zone-combinator/constant-combinator-mask.png",
      width = 58,
      height = 52,
      frame_count = 1,
      shift = util.by_pixel(0, 5),
      tint = zone_combinator.tint,
      hr_version =
      {
        scale = 0.5,
        filename = "__zone-combinator__/graphics/entity/zone-combinator/hr-constant-combinator-mask.png",
        width = 114,
        height = 102,
        frame_count = 1,
        shift = util.by_pixel(0, 5),
        tint = zone_combinator.tint,
      }
    }
  }
})
for direction_name, sprite_direction in pairs(entity_prototype.sprites) do
  table.insert(sprite_direction.layers, sprites[direction_name])
end

entity_prototype.item_slot_count = 30

data:extend({entity_prototype})