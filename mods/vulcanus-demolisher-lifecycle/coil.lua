-- Path math for moving a demolisher's body by script. Pure functions; no game state.
--
-- A path is a polyline with cumulative arc lengths. The body is placed so its head sits at arc
-- length s and each following node is one tile further back along the path, which keeps the
-- engine's preferred 1-tile node spacing however fast the head moves.

local M = {}

local function dist(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
M.dist = dist

local function finish(points)
  local cum = { 0 }
  for i = 2, #points do cum[i] = cum[i - 1] + dist(points[i - 1], points[i]) end
  return { points = points, cum = cum, length = cum[#cum] }
end

-- Path from the current body (tail to head), then straight to the outer radius around centre,
-- then an inward spiral long enough to hold the whole body.
function M.coil_path(body_nodes, centre, outer, inner)
  local points = {}
  for i = #body_nodes, 1, -1 do points[#points + 1] = { x = body_nodes[i].x, y = body_nodes[i].y } end
  local head = body_nodes[1]
  local angle = math.atan2(head.y - centre.y, head.x - centre.x)
  local start = { x = centre.x + outer * math.cos(angle), y = centre.y + outer * math.sin(angle) }
  local d = dist(head, start)
  for k = 1, math.floor(d) do
    local f = k / d
    points[#points + 1] = { x = head.x + (start.x - head.x) * f, y = head.y + (start.y - head.y) * f }
  end
  points[#points + 1] = start
  local needed, total, radius = #body_nodes + 2, 0, outer
  while total < needed do
    local step = 1 / radius -- about one tile of arc
    angle = angle + step
    -- Shrink by (outer - inner) over 1.5 turns, then hold the inner radius.
    radius = math.max(inner, radius - (outer - inner) * step / (3 * math.pi))
    local p = { x = centre.x + radius * math.cos(angle), y = centre.y + radius * math.sin(angle) }
    total = total + dist(points[#points], p)
    points[#points + 1] = p
  end
  return finish(points), #body_nodes - 1 -- path, and the head's starting arc length
end

local function point_at(path, s)
  local points, cum = path.points, path.cum
  if s <= 0 then return points[1] end
  if s >= path.length then return points[#points] end
  local lo, hi = 1, #cum
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if cum[mid] <= s then lo = mid else hi = mid end
  end
  local f = (s - cum[lo]) / (cum[hi] - cum[lo])
  return { x = points[lo].x + (points[hi].x - points[lo].x) * f, y = points[lo].y + (points[hi].y - points[lo].y) * f }
end

-- Body nodes, head first, with the head at arc length s. Runs every tick while coiling, so it finds
-- the head's segment once and walks back along the path from there.
function M.nodes_at(path, s, count)
  local points, cum = path.points, path.cum
  local nodes = { point_at(path, s) }
  local lo = 1
  local hi = #cum
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if cum[mid] <= s then lo = mid else hi = mid end
  end
  for i = 1, count - 1 do
    local t = s - i
    if t <= 0 then
      nodes[i + 1] = points[1]
    else
      while lo > 1 and cum[lo] > t do lo = lo - 1 end
      local a, b = points[lo], points[lo + 1]
      local span = cum[lo + 1] - cum[lo]
      local f = span > 0 and (t - cum[lo]) / span or 0
      nodes[i + 1] = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f }
    end
  end
  return nodes
end

-- A tight curl of `count` nodes around centre, head on the inside, for a hatchling.
function M.curl(centre, count)
  local nodes, angle, radius = {}, 0, 1.5
  nodes[1] = { x = centre.x + radius, y = centre.y }
  while #nodes < count do
    angle = angle + 0.25 / radius
    radius = radius + 0.25 / (2 * math.pi) * 0.9 -- about 0.9 tiles further out per turn
    local p = { x = centre.x + radius * math.cos(angle), y = centre.y + radius * math.sin(angle) }
    if dist(nodes[#nodes], p) >= 1 then nodes[#nodes + 1] = p end
  end
  return nodes
end

return M
