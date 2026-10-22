--data-final-fixes.lua

for _, belt in pairs(data.raw["transport-belt"]) do
  belt.connector_frame_sprites.frame_main.sheet.filename = "__clean-sushi__/data/hr-ccm-belt-04a-sequence.png";
  belt.connector_frame_sprites.frame_shadow.sheet.filename = "__clean-sushi__/data/hr-ccm-belt-04b-sequence-shadow.png";
  belt.connector_frame_sprites.frame_back_patch.sheet.filename = "__clean-sushi__/data/hr-ccm-belt-04a-sequence-back-patch.png";
  for _, connection_point in pairs(belt.circuit_wire_connection_points) do
    connection_point.wire.red["x"] = 0.45
    connection_point.wire.red["y"] = -0.70
    connection_point.shadow.red["x"] = 0.70
    connection_point.shadow.red["y"] = -0.45
    connection_point.wire.green["x"] = 0.55
    connection_point.wire.green["y"] = -0.60
    connection_point.shadow.green["x"] = 0.80
    connection_point.shadow.green["y"] = -0.35
  end
end