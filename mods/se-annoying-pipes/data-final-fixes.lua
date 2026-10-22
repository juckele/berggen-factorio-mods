--data-final-fixes.lua

-- players should collide with pipes again.
for _, type in pairs({"pipe", "pipe-to-ground"}) do
  for _, prototype in pairs(data.raw[type]) do
    prototype.collision_mask = collision_mask_util_extended.get_mask(prototype)
    collision_mask_util_extended.add_layer(prototype.collision_mask, "player-layer")
  end
end