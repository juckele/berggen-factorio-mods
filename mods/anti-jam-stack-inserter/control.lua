local NAME = "anti-jam-stack-inserter"
local BASE = "stack-inserter"

-- Everything here is for the "smart swapping" mode. With a distinct item it's an ordinary
-- inserter and needs no scripting.
if settings.startup["anti-jam-stack-inserter-mode"].value ~= "smart-swapping" then return end

-- With smart swapping the anti-jam stack inserter is built from, and mines to, stack
-- inserter items. Its own item only ever lives in a player's cursor: stack inserters are
-- swapped for it when the player wants to place anti-jam stack inserters, and it turns
-- back into stack inserters wherever it ends up outside the cursor. That keeps construction robots, logistics and
-- recycling dealing only with stack inserters.

local function is_anti_jam(entity)
  if not (entity and entity.valid) then return false end
  if entity.name == NAME then return true end
  return entity.type == "entity-ghost" and entity.ghost_name == NAME
end

-- Replace every anti-jam item in an inventory with the same number of stack inserters.
local function convert_inventory(inventory)
  if not (inventory and inventory.valid) then return end
  for _, item in pairs(inventory.get_contents()) do
    if item.name == NAME then
      local removed = inventory.remove({name = NAME, count = item.count, quality = item.quality})
      if removed > 0 then
        local inserted = inventory.insert({name = BASE, count = removed, quality = item.quality})
        if inserted < removed then
          -- Shouldn't happen (same slot usage); put back what didn't fit.
          inventory.insert({name = NAME, count = removed - inserted, quality = item.quality})
        end
      end
    end
  end
end

local function convert_stack(stack)
  if stack and stack.valid_for_read and stack.name == NAME then
    stack.set_stack({name = BASE, count = stack.count, quality = stack.quality.name})
  end
end

local function convert_entity(entity)
  if not (entity and entity.valid) then return end
  if entity.type == "item-entity" then
    convert_stack(entity.stack)
    return
  end
  for i = 1, entity.get_max_inventory_index() do
    convert_inventory(entity.get_inventory(i))
  end
end

local function convert_player_inventories(player)
  convert_inventory(player.get_main_inventory())
  convert_inventory(player.get_inventory(defines.inventory.character_trash))
end

-- Holding an anti-jam ghost while carrying stack inserters of that quality: hold real
-- anti-jam items instead (one inventory stack's worth, like picking up from the inventory).
local function upgrade_ghost_cursor(player)
  local cursor = player.cursor_stack
  if not cursor or cursor.valid_for_read then return end
  local ghost = player.cursor_ghost
  if not (ghost and ghost.name and ghost.name.name == NAME) then return end
  local quality = ghost.quality and ghost.quality.name or "normal"
  local inventory = player.get_main_inventory()
  if not inventory then return end
  local found = inventory.find_item_stack({name = BASE, quality = quality})
  if not found then return end
  local count = found.count
  found.clear()
  cursor.set_stack({name = NAME, count = count, quality = quality})
end

script.on_event(defines.events.on_player_pipette, function(event)
  if event.item.name == NAME then return end
  if not prototypes.item[NAME] then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local entity = player.selected
  if not is_anti_jam(entity) then return end
  local cursor = player.cursor_stack
  if not cursor then return end

  -- The pipette handed over stack inserters (from the inventory, or free in cheat mode):
  -- hold the same number of anti-jam ones instead.
  if cursor.valid_for_read and cursor.name == BASE then
    cursor.set_stack({name = NAME, count = cursor.count, quality = cursor.quality.name})
    return
  end

  -- Nothing to place: hold an anti-jam ghost.
  if player.clear_cursor() then
    player.cursor_ghost = {name = NAME, quality = entity.quality.name}
  end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == NAME then return end
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
