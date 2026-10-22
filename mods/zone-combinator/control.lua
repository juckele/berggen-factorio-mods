function table_contains(table, check)
  for k,v in pairs(table) do if v == check then return true end end
  return false
end

---Sets the signals on the zone combinator to the given values
---@param entity LuaEntity the combinator
function set_zone_combinator_signals(entity, params)
  local control_behavior = entity.get_control_behavior()

  local control_behavior_params = {}
  local index = 1
  if params.x_pos then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="signal-X"}, count=params.x_pos})
    index = index + 1
  end
  if params.y_pos then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="signal-Y"}, count=params.y_pos})
    index = index + 1
  end
  if params.index and params.signal then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name=params.signal}, count=params.index})
    index = index + 1
  end
  if params.radius then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="se-radius"}, count=params.radius})
    index = index + 1
  end
  if params.ticks_per_day then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="zc-day-length"}, count=params.ticks_per_day})
    index = index + 1
  end
  if params.solar then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="zc-solar"}, count=params.solar})
    index = index + 1
  end
  if params.threat then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="zc-threat"}, count=params.threat})
    index = index + 1
  end
  if not params.waterless then
    table.insert(control_behavior_params, {index=index, signal={type="fluid", name="water"}, count=1})
    index = index + 1
  end
  if params.biter_meteors then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="se-meteor"}, count=1})
    index = index + 1
  end
  if params.plagued then
    table.insert(control_behavior_params, {index=index, signal={type="item", name="se-plague-bomb"}, count=1})
    index = index + 1
  end
  if params.life_support then
    table.insert(control_behavior_params, {index=index, signal={type="item", name="se-lifesupport-canister"}, count=1})
    index = index + 1
  end
  if params.fragment_name then
    if game.item_prototypes[params.fragment_name] then
      table.insert(control_behavior_params, {index=index, signal={type="item", name=params.fragment_name}, count=1})
      index = index + 1
    end
  end
  if params.robot_attrition then
    table.insert(control_behavior_params, {index=index, signal={type="virtual", name="zc-robot-interference"}, count=params.robot_attrition})
    index = index + 1
  end
  if params.resources then
    for resource, amount in pairs(params.resources) do
      if game.item_prototypes[resource] then
        table.insert(control_behavior_params, {index=index, signal={type="item", name=resource}, count=amount})
        index = index + 1
      elseif game.fluid_prototypes[resource] then
        table.insert(control_behavior_params, {index=index, signal={type="fluid", name=resource}, count=amount})
	index = index + 1
      end
    end
  end

  control_behavior.parameters = control_behavior_params
end

local icon_prefix = "virtual-signal/"

function get_zone_signal(zone)
  local zone_icon = remote.call("space-exploration", "get_zone_icon", {zone_index = zone.index})
  return zone.index, string.sub(zone_icon, string.len(icon_prefix) + 1, string.len(zone_icon))
end

function get_resources(zone)
  local resources = {}
  if zone.controls then
    for resource, control in pairs(zone.controls) do
      if game.item_prototypes[resource] or game.fluid_prototypes[resource] then
	local value = (control.frequency or 0) * (control.richness or 0) * (control.size or 0)
        if value > 0 then
	  resources[resource] = value * 10000
	end
      end
    end
  end

  return resources
end  

function update_zone_combinator(entity)
  -- compute and set the values for the combinator
  local surface_index = entity.surface.index
  local zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
  if not zone then return end
  -- log("zone_information:" .. serpent.block(zone, {maxlevel = 3}))

  local threat = remote.call("space-exploration", "threat_for_surface", {surface_index = surface_index})
  local robot_attrition = remote.call("space-exploration", "robot_attrition_for_surface", {surface_index = surface_index})
  local hazards = remote.call("space-exploration", "hazards_for_surface", {surface_index = surface_index})
  local solar = remote.call("space-exploration", "solar_for_surface", {surface_index = surface_index})

  local index, signal = get_zone_signal(zone)
  local plagued = table_contains(hazards, "plague-world")
  local life_support = plagued or (zone.type ~= "moon" and zone.type ~= "planet") -- this probably will change in some future version of SE where some planets/moons don't just happen to all have breathable atmospheres
  local waterless = table_contains(hazards, "waterless") or (zone.type ~= "moon" and zone.type ~= "planet")
  local fragment_name = nil
  if zone.type ~= "orbit" then
    fragment_name = zone.fragment_name
  end

  local resources = get_resources(zone)

  set_zone_combinator_signals(entity, {
    x_pos = entity.position.x,
    y_pos = entity.position.y,
    radius = zone.radius,
    ticks_per_day = zone.ticks_per_day,
    solar = math.floor(solar * 100),
    threat = math.floor(threat * 100),
    waterless = waterless,
    biter_meteors = table_contains(hazards, "biter-meteors"),
    plagued = plagued,
    fragment_name = fragment_name,
    robot_attrition = math.floor(robot_attrition * 100),
    index = index,
    signal = signal,
    life_support = life_support,
    resources = resources,
  })
end

local filters = {{
  filter = "name",
  name = "zone-combinator",
}}
function on_entity_created(event)
  local entity
  if event.entity and event.entity.valid then
    entity = event.entity
  end
  if event.created_entity and event.created_entity.valid then
    entity = event.created_entity
  end
  if event.destination and event.destination.valid then
    entity = event.destination
  end
  if not entity then return end
  if entity.name ~= "zone-combinator" then return end
  update_zone_combinator(entity)
end
script.on_event(defines.events.on_entity_cloned, on_entity_created, filters)
script.on_event(defines.events.on_built_entity, on_entity_created, filters)
script.on_event(defines.events.on_robot_built_entity, on_entity_created, filters)
script.on_event(defines.events.script_raised_built, on_entity_created, filters)
script.on_event(defines.events.script_raised_revive, on_entity_created, filters)