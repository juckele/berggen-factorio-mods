-- Each anti-jam inserter and the base inserter it's built from. The long-handed pair only
-- exists with the Long Stack Inserter mod; unknown names simply never match.
local BASE_OF = {
  ["anti-jam-stack-inserter"] = "stack-inserter",
  ["long-anti-jam-stack-inserter"] = "long-stack-inserter",
}

-- Everything here is for the "smart swapping" mode. With a distinct item it's an ordinary
-- inserter and needs no scripting.
if settings.startup["anti-jam-stack-inserter-mode"].value ~= "smart-swapping" then return end

-- With smart swapping an anti-jam inserter is built from, and mines to, its base
-- inserter's items. Its own item only ever lives in a player's cursor: base items are
-- swapped for it when the player wants to place anti-jam inserters, and it turns back into
-- base items wherever it ends up outside the cursor. That keeps construction robots,
-- logistics and recycling dealing only with the base inserters.

-- The anti-jam inserter an entity (or ghost) is, or nil.
local function anti_jam_name(entity)
  if not (entity and entity.valid) then return nil end
  if BASE_OF[entity.name] then return entity.name end
  if entity.type == "entity-ghost" and BASE_OF[entity.ghost_name] then return entity.ghost_name end
  return nil
end

-- Replace every anti-jam item in an inventory with the same number of base items.
-- Each convert_* function returns how many items it converted.
local function convert_inventory(inventory)
  if not (inventory and inventory.valid) then return 0 end
  local converted = 0
  for _, item in pairs(inventory.get_contents()) do
    local base = BASE_OF[item.name]
    if base then
      local removed = inventory.remove({name = item.name, count = item.count, quality = item.quality})
      if removed > 0 then
        local inserted = inventory.insert({name = base, count = removed, quality = item.quality})
        if inserted < removed then
          -- Shouldn't happen (same slot usage); put back what didn't fit.
          inventory.insert({name = item.name, count = removed - inserted, quality = item.quality})
        end
        converted = converted + inserted
      end
    end
  end
  return converted
end

local function convert_stack(stack)
  if stack and stack.valid_for_read and BASE_OF[stack.name] then
    local count = stack.count
    stack.set_stack({name = BASE_OF[stack.name], count = count, quality = stack.quality.name})
    return count
  end
  return 0
end

local BELT_TYPES = {
  ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["lane-splitter"] = true, ["loader"] = true, ["loader-1x1"] = true, ["linked-belt"] = true,
}

-- An entity's inventories, an item on the ground, an inserter's hand, or items on a belt.
local function convert_entity(entity)
  if not (entity and entity.valid) then return 0 end
  if entity.type == "item-entity" then
    return convert_stack(entity.stack)
  end
  local converted = 0
  for i = 1, entity.get_max_inventory_index() do
    converted = converted + convert_inventory(entity.get_inventory(i))
  end
  if entity.type == "inserter" then
    converted = converted + convert_stack(entity.held_stack)
  end
  if BELT_TYPES[entity.type] then
    for i = 1, entity.get_max_transport_line_index() do
      for _, item in pairs(entity.get_transport_line(i).get_detailed_contents()) do
        converted = converted + convert_stack(item.stack)
      end
    end
  end
  return converted
end

local function convert_player_inventories(player)
  return convert_inventory(player.get_main_inventory())
    + convert_inventory(player.get_inventory(defines.inventory.character_trash))
end

-- Holding an anti-jam ghost while carrying base items of that quality: hold real
-- anti-jam items instead (one inventory stack's worth, like picking up from the inventory).
local function upgrade_ghost_cursor(player)
  local cursor = player.cursor_stack
  if not cursor or cursor.valid_for_read then return end
  local ghost = player.cursor_ghost
  local name = ghost and ghost.name and ghost.name.name
  local base = name and BASE_OF[name]
  if not base then return end
  local quality = ghost.quality and ghost.quality.name or "normal"
  local inventory = player.get_main_inventory()
  if not inventory then return end
  local found = inventory.find_item_stack({name = base, quality = quality})
  if not found then return end
  local count = found.count
  found.clear()
  cursor.set_stack({name = name, count = count, quality = quality})
end

script.on_event(defines.events.on_player_pipette, function(event)
  if BASE_OF[event.item.name] then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local entity = player.selected
  local name = anti_jam_name(entity)
  if not (name and prototypes.item[name]) then return end
  local base = BASE_OF[name]
  local cursor = player.cursor_stack
  if not cursor then return end

  -- The pipette handed over base items (from the inventory, or free in cheat mode): hold
  -- the same number of anti-jam ones instead.
  if cursor.valid_for_read and cursor.name == base then
    cursor.set_stack({name = name, count = cursor.count, quality = cursor.quality.name})
    return
  end

  -- Nothing to place: hold an anti-jam ghost.
  if player.clear_cursor() then
    player.cursor_ghost = {name = name, quality = entity.quality.name}
  end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and BASE_OF[cursor.name] then return end
  -- Anti-jam items left the cursor: back to the inventory or trash (clear cursor), or
  -- into whatever the player had open (clicked into a chest, car, wagon...).
  convert_player_inventories(player)
  local opened = player.opened
  if player.opened_gui_type == defines.gui_type.entity and opened and opened.valid then
    convert_entity(opened)
  end
  upgrade_ghost_cursor(player)
end)

-- Items put in the inventory any other way (cheat or editor mode, other mods).
script.on_event(defines.events.on_player_main_inventory_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then convert_inventory(player.get_main_inventory()) end
end)

script.on_event(defines.events.on_player_trash_inventory_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then convert_inventory(player.get_inventory(defines.inventory.character_trash)) end
end)

-- Ctrl-click transfers from the cursor into an entity.
script.on_event(defines.events.on_player_fast_transferred, function(event)
  if event.from_player then convert_entity(event.entity) end
end)

-- Dropped on the ground (or onto a belt, where there's no item entity to convert).
script.on_event(defines.events.on_player_dropped_item, function(event)
  convert_entity(event.entity)
end)

-- Don't leave anti-jam items in a corpse or with a player who's leaving.
local function convert_cursor(event)
  local player = game.get_player(event.player_index)
  if player then convert_stack(player.cursor_stack) end
end
script.on_event(defines.events.on_pre_player_died, convert_cursor)
script.on_event(defines.events.on_pre_player_left_game, convert_cursor)

-- Switching a save to smart swapping from a distinct-item mode leaves real anti-jam items
-- around. Sweep the whole game once and turn them all into their base inserters.
local function convert_everything()
  local converted = 0
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({})) do
      converted = converted + convert_entity(entity)
    end
  end
  for _, player in pairs(game.players) do
    converted = converted + convert_player_inventories(player) + convert_stack(player.cursor_stack)
  end
  if converted > 0 then
    game.print({"anti-jam-stack-inserter.converted-items", converted})
  end
end

script.on_configuration_changed(function(data)
  if data.mod_startup_settings_changed then
    convert_everything()
  end
end)
