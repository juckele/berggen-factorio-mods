-- Territory index: which territory owns each chunk, and each territory's chunks, size, centre and
-- demolisher, kept in storage so the mod never has to ask the game for them during play.
--
-- The index assumes only this mod and the map generator change territories. It is built once when
-- the mod sets up (and rebuilt on configuration changes), and from then on is updated by this mod's
-- own changes and by the map generator's territory and demolisher creation events.
--
-- storage.index:
--   next_id   next territory id
--   owner     map of chunk key (index.key) -> territory id (includes unexplored chunks)
--   terr      map of territory id -> record:
--     territory   LuaTerritory
--     chunks      map of chunk key -> {x, y}
--     count       number of chunks
--     sx, sy, sq  sums of x, y and x^2 + y^2 over its chunks (for centre and radius)
--     unit        its LuaSegmentedUnit, or nil once dead
--     unit_number
--   by_unit   map of unit_number -> territory id

local M = {}

-- Chunk keys are numbers, not "x,y" strings: building and hashing strings was a large part of
-- the mod's per-tick cost. Chunk coordinates stay well inside +-32768 (the map is 2M tiles wide).
local function key(x, y)
  return (x + 32768) * 65536 + (y + 32768)
end
M.key = key

function M.unkey(k)
  local y = k % 65536
  return (k - y) / 65536 - 32768, y - 32768
end

function M.new()
  return { next_id = 1, owner = {}, terr = {}, by_unit = {} }
end

local function I()
  return storage.index
end

function M.get(tid)
  return I().terr[tid]
end

function M.owner_at(x, y)
  return I().owner[key(x, y)]
end

function M.owner_of_key(k)
  return I().owner[k]
end

function M.tid_of_unit(unit_number)
  return I().by_unit[unit_number]
end

function M.alive(t)
  return t ~= nil and t.unit ~= nil and t.unit.valid
end

local function drop(tid)
  local idx = I()
  local t = idx.terr[tid]
  if not t then return end
  if t.unit_number and idx.by_unit[t.unit_number] == tid then idx.by_unit[t.unit_number] = nil end
  idx.terr[tid] = nil
end
M.drop = drop

function M.remove_chunk(tid, k)
  local idx = I()
  local t = idx.terr[tid]
  if not t then return end
  local c = t.chunks[k]
  if not c then return end
  t.chunks[k] = nil
  t.count = t.count - 1
  t.sx, t.sy, t.sq = t.sx - c.x, t.sy - c.y, t.sq - c.x * c.x - c.y * c.y
  if idx.owner[k] == tid then idx.owner[k] = nil end
end

-- Gives the chunk to tid, taking it from its previous owner.
function M.add_chunk(tid, x, y)
  local idx = I()
  local k = key(x, y)
  local old = idx.owner[k]
  if old == tid then return end
  if old then
    M.remove_chunk(old, k)
    local o = idx.terr[old]
    if o and o.count == 0 then drop(old) end
  end
  local t = idx.terr[tid]
  t.chunks[k] = { x = x, y = y }
  t.count = t.count + 1
  t.sx, t.sy, t.sq = t.sx + x, t.sy + y, t.sq + x * x + y * y
  idx.owner[k] = tid
end

function M.set_unit(tid, unit)
  local idx = I()
  local t = idx.terr[tid]
  if not t then return end
  if t.unit_number and idx.by_unit[t.unit_number] == tid then idx.by_unit[t.unit_number] = nil end
  t.unit = unit
  t.unit_number = unit and unit.unit_number or nil
  if unit then idx.by_unit[unit.unit_number] = tid end
end

-- Indexes a territory the game created (one get_chunks call). Chunks it took from other
-- territories move to it.
function M.index_territory(territory)
  local idx = I()
  local tid = idx.next_id
  idx.next_id = tid + 1
  idx.terr[tid] = { territory = territory, chunks = {}, count = 0, sx = 0, sy = 0, sq = 0 }
  for _, c in pairs(territory.get_chunks()) do M.add_chunk(tid, c.x, c.y) end
  local unit = territory.get_segmented_units()[1]
  if unit then M.set_unit(tid, unit) end
  if idx.terr[tid].count == 0 then
    drop(tid)
    return nil
  end
  return tid
end

-- The territory id a game territory is indexed under, found through one of its chunks.
function M.tid_of_territory(territory)
  local c = territory.get_chunks()[1]
  return c and M.owner_at(c.x, c.y) or nil
end

-- Centre and root-mean-square radius, in chunks.
function M.geometry(t)
  local n = t.count
  local cx, cy = t.sx / n, t.sy / n
  local variance = t.sq / n - cx * cx - cy * cy
  return { x = cx, y = cy, radius = math.max(1, math.sqrt(math.max(0, variance))) }
end

function M.rebuild(surface)
  storage.index = M.new()
  for _, territory in pairs(surface.get_territories()) do
    if territory.valid then M.index_territory(territory) end
  end
end

return M
