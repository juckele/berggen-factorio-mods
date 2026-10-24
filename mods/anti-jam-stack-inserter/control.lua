local NAME = "anti-jam-stack-inserter"

-- The anti-jam stack inserter is built from stack inserter items, so the pipette picks a
-- stack inserter. When the player pipettes an anti-jam stack inserter (or its ghost),
-- swap that for an anti-jam stack inserter ghost cursor instead.
local function is_anti_jam(entity)
  if not (entity and entity.valid) then return false end
  if entity.name == NAME then return true end
  return entity.type == "entity-ghost" and entity.ghost_name == NAME
end

script.on_event(defines.events.on_player_pipette, function(event)
  if event.item.name == NAME then return end
  if not prototypes.item[NAME] then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local entity = player.selected
  if not is_anti_jam(entity) then return end
  local quality = entity.quality.name

  if event.used_cheat_mode then
    -- Cheat mode handed out a free stack of stack inserters; make it anti-jam ones.
    local cursor = player.cursor_stack
    if cursor then
      cursor.set_stack({name = NAME, count = prototypes.item[NAME].stack_size, quality = quality})
    end
    return
  end

  -- Put the stack inserters back in the inventory and hold an anti-jam ghost instead.
  if player.clear_cursor() then
    player.cursor_ghost = {name = NAME, quality = quality}
  end
end)
