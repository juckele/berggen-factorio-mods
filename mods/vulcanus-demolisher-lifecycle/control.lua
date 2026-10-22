script.on_init(function()
  log("script.on_init")
  log(serpent.block(storage))
  storage["on_init_run_before"] = true
  check_vulcanus_initialization()
end)

script.on_load(function()
  log("script.on_load")
  log(serpent.block(storage))
end)

script.on_configuration_changed(function()
  log("script.on_configuration_changed")
  log(serpent.block(storage))
  check_vulcanus_initialization()
end)

function on_surface_created()
  log("script.on_surface_created")
  log(serpent.block(storage))
  check_vulcanus_initialization()
end

function check_vulcanus_initialization()
  log("check_vulcanus_initialization")
  log("Bonus perform_vulcanus_initialization, remove this")
--  if storage["vulcanus_is_initialized"] == nil then
    vulcanus = game.surfaces["vulcanus"]
    if vulcanus ~= nil then
      perform_vulcanus_initialization(vulcanus)
    end
--  end
end

function perform_vulcanus_initialization(vulcanus)
  log("perform_vulcanus_initialization")
  create_player_territory(vulcanus)
  delete_empty_demolisher_territories(vulcanus)
  storage["vulcanus_is_initialized"] = true
end

function create_player_territory()
  log("create_player_territory")
  -- this needx to be done before empty demolisher deleting so we can santify an area
  -- even if this has been in an old save
end

function delete_empty_demolisher_territories()
  log("delete_empty_demolisher_territories")
  territories = vulcanus.get_territories()
  log("There are "..table_size(territories).." territories")
  for i, territory in pairs(territories) do
    log("Process a territory "..i..", "..territory.object_name)
    if table_size(territory.get_segmented_units()) == 0 then
      log("Deleting an empty territory")
      territory.destroy()
    end
  end
end

function chunk_has_empty_adjacent_space(surface, chunk)
  if surface.is_chunk_generated({x=chunk.x-1, y=chunk.y}) and surface.get_territory_for_chunk({x=chunk.x-1, y=chunk.y}) == nil then
    return true
  end
  if surface.is_chunk_generated({x=chunk.x+1, y=chunk.y}) and surface.get_territory_for_chunk({x=chunk.x+1, y=chunk.y}) == nil then
    return true
  end
  if surface.is_chunk_generated({x=chunk.x, y=chunk.y-1}) and surface.get_territory_for_chunk({x=chunk.x, y=chunk.y-1}) == nil then
    return true
  end
  if surface.is_chunk_generated({x=chunk.x, y=chunk.y+1}) and surface.get_territory_for_chunk({x=chunk.x, y=chunk.y+1}) == nil then
    return true
  end
end

function territory_has_empty_adjacent_space(surface, territory)
  chunks = territory.get_chunks()
  for _, chunk in pairs(chunks) do
    if chunk_has_empty_adjacent_space(surface, chunk) then
      return true
    end
  end
end

function expand_chunk(surface, territory, chunk)
  expansion_candidates = {}
  if surface.is_chunk_generated({x=chunk.x-1, y=chunk.y}) and surface.get_territory_for_chunk({x=chunk.x-1, y=chunk.y}) == nil then
    table.insert(expansion_candidates, {x=chunk.x-1, y=chunk.y})
  end
  if surface.is_chunk_generated({x=chunk.x+1, y=chunk.y}) and surface.get_territory_for_chunk({x=chunk.x+1, y=chunk.y}) == nil then
    table.insert(expansion_candidates, {x=chunk.x+1, y=chunk.y})
  end
  if surface.is_chunk_generated({x=chunk.x, y=chunk.y-1}) and surface.get_territory_for_chunk({x=chunk.x, y=chunk.y-1}) == nil then
    table.insert(expansion_candidates, {x=chunk.x, y=chunk.y-1})
  end
  if surface.is_chunk_generated({x=chunk.x, y=chunk.y+1}) and surface.get_territory_for_chunk({x=chunk.x, y=chunk.y+1}) == nil then
    table.insert(expansion_candidates, {x=chunk.x, y=chunk.y+1})
  end
  log("expansion_candidates: "..serpent.block(expansion_candidates))
  random_candidate = expansion_candidates[math.random(1, #expansion_candidates)]
  log("Growing from "..chunk.x..", "..chunk.y.." to "..random_candidate.x..", "..random_candidate.y)
  game.print("Growing from "..chunk.x..", "..chunk.y.." to "..random_candidate.x..", "..random_candidate.y)  
  surface.set_territory_for_chunks({random_candidate}, territory)
  log("I GREW")
  game.print("I GREW")
end

function expand_territory(surface, territory)
  log("expand_territory - surface: "..serpent.block(surface).." territory: "..serpent.block(territory))
  
  candidate_chunks = territory.get_chunks()
  expandable_chunks = {}
  for _, chunk in pairs(candidate_chunks) do
    if chunk_has_empty_adjacent_space(surface, chunk) then
      table.insert(expandable_chunks, chunk)
    end
  end
  -- log(serpent.block(expandable_chunks))
  random_chunk = expandable_chunks[math.random(1, #expandable_chunks)]
  expand_chunk(surface, territory, random_chunk)
  territory.regenerate_patrol_path()
end
  
function grow_random_territory()
  game.print("Let's grow some demolishers!")
  vulcanus = game.surfaces["vulcanus"]
  if vulcanus ~= nil then
    -- log("We have a handle on Vulcanus")
    game.print("We have a handle on Vulcanus")
    territories = vulcanus.get_territories()
    expandable_territories = {}
    size = table_size(territories)
    log("There are "..size.." territories")
    game.print("There are "..size.." territories")
    for i, territory in pairs(territories) do
      -- log("Process a territory "..i)
      has_empty_friends = territory_has_empty_adjacent_space(vulcanus, territory)
      if has_empty_friends then
        -- log("territory "..i.." could expand")
        game.print("territory "..i.." could expand")
        table.insert(expandable_territories, territory)
      end
    end
    expandable_size = table_size(expandable_territories)
    log("There are ".. expandable_size .." candidates")
    game.print("There are ".. expandable_size .." candidates")
    if expandable_size < 1 then
      return 0
    end
    log("expandable_territories: " .. serpent.block(expandable_territories))
    random_territory = expandable_territories[math.random(1, #expandable_territories)]
    log("random_territory: " .. serpent.block(random_territory))
    log("grow_random_territory -> expand_territory")
    expand_territory(vulcanus, random_territory)
    -- game.print(serpent.block(random_territory))
  end
end

function on_tick()
  -- Skip all work before Vulcanus is initialized.
  if storage["vulcanus_is_initialized"] == nil then
    return false
  end

  -- Every X units of time allow a demolisher to grow.
  second = math.floor(game.tick/60);
  -- log("tick "..second)
  -- game.print("tick " .. second)
  if game.tick % 60 == 5 and second % 1 == 0 then
    log("on_tick -> grow_random_territory")
    grow_random_territory()
  end

  -- Define 
  storage["on_tick_run_before"] = true
end

script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_surface_created, on_surface_created)