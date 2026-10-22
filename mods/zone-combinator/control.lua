local function table_contains(table, check)
  for _, v in pairs(table) do if v == check then return true end end
  return false
end

local signal_prototypes = {
  item = function(name) return prototypes.item[name] end,
  fluid = function(name) return prototypes.fluid[name] end,
  virtual = function(name) return prototypes.virtual_signal[name] end,
}

---Sets the signals on the zone combinator to the given values
---@param entity LuaEntity the combinator
local function set_zone_combinator_signals(entity, params)
  local filters = {}
  local function add(type, name, count)
    if not (name and count) then return end
    count = math.floor(count)
    if count == 0 then return end
    if not signal_prototypes[type](name) then return end
    table.insert(filters, {
      value = {type = type, name = name, quality = "normal", comparator = "="},
      min = count,
    })
  end

  add("virtual", "signal-X", params.x_pos)
  add("virtual", "signal-Y", params.y_pos)
  add("virtual", params.signal, params.index)
  add("virtual", "se-radius", params.radius)
  add("virtual", "zc-day-length", params.ticks_per_day)
  add("virtual", "zc-solar", params.solar)
  add("virtual", "zc-threat", params.threat)
  if params.has_water then add("fluid", "water", 1) end
  if params.biter_meteors then add("virtual", "se-meteor", 1) end
  if params.plagued then add("item", "se-plague-bomb", 1) end
  if params.life_support then add("item", "se-lifesupport-canister", 1) end
  add("item", params.fragment_name, 1)
  add("virtual", "zc-robot-interference", params.robot_attrition)
  for resource, amount in pairs(params.resources) do
    add(prototypes.item[resource] and "item" or "fluid", resource, amount)
  end

  local control_behavior = entity.get_or_create_control_behavior()
  for i = control_behavior.sections_count, 1, -1 do
    control_behavior.remove_section(i)
  end
  control_behavior.add_section().filters = filters
end

local icon_prefix = "virtual-signal/"

local function get_zone_signal(zone)
  local zone_icon = remote.call("space-exploration", "get_zone_icon", {zone_index = zone.index})
  if not (zone_icon and zone_icon:sub(1, #icon_prefix) == icon_prefix) then return zone.index, nil end
  return zone.index, zone_icon:sub(#icon_prefix + 1)
end

-- Water is reported as a flag, not as a resource (see has_water below).
local non_resource_controls = {water = true}

local function get_resources(zone)
  local resources = {}
  for resource, control in pairs(zone.controls or {}) do
    if not non_resource_controls[resource] and (prototypes.item[resource] or prototypes.fluid[resource]) then
      local value = (control.frequency or 0) * (control.richness or 0) * (control.size or 0)
      if value > 0 then
        resources[resource] = value * 10000
      end
    end
  end
  return resources
end

local function update_zone_combinator(entity)
  -- compute and set the values for the combinator
  local surface_index = entity.surface.index
  local zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
  if not zone then return end

  local threat = remote.call("space-exploration", "threat_for_surface", {surface_index = surface_index}) or 0
  local robot_attrition = remote.call("space-exploration", "robot_attrition_for_surface", {surface_index = surface_index}) or 0
  local hazards = remote.call("space-exploration", "hazards_for_surface", {surface_index = surface_index}) or {}
  local solar = remote.call("space-exploration", "solar_for_surface", {surface_index = surface_index}) or 0

  local index, signal = get_zone_signal(zone)
  local is_solid = zone.type == "planet" or zone.type == "moon"
  local plagued = table_contains(hazards, "plague-world")
  local life_support = plagued or not is_solid -- this probably will change in some future version of SE where some planets/moons don't just happen to all have breathable atmospheres
  local has_water = is_solid and not table_contains(hazards, "waterless")
  local fragment_name = nil
  if zone.type ~= "orbit" then
    fragment_name = zone.fragment_name
  end

  set_zone_combinator_signals(entity, {
    x_pos = entity.position.x,
    y_pos = entity.position.y,
    radius = zone.radius,
    ticks_per_day = zone.ticks_per_day,
    solar = solar * 100,
    threat = threat * 100,
    has_water = has_water,
    biter_meteors = table_contains(hazards, "biter-meteors"),
    plagued = plagued,
    fragment_name = fragment_name,
    robot_attrition = robot_attrition * 100,
    index = index,
    signal = signal,
    life_support = life_support,
    resources = get_resources(zone),
  })
end

local function on_entity_created(event)
  local entity = event.entity or event.destination
  if not (entity and entity.valid and entity.name == "zone-combinator") then return end
  update_zone_combinator(entity)
end

local filters = {{filter = "name", name = "zone-combinator"}}
script.on_event(defines.events.on_entity_cloned, on_entity_created, filters)
script.on_event(defines.events.on_built_entity, on_entity_created, filters)
script.on_event(defines.events.on_robot_built_entity, on_entity_created, filters)
script.on_event(defines.events.script_raised_built, on_entity_created, filters)
script.on_event(defines.events.script_raised_revive, on_entity_created, filters)

-- Refresh existing combinators when this mod or Space Exploration changes.
script.on_configuration_changed(function()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = "zone-combinator"}) do
      update_zone_combinator(entity)
    end
  end
end)
