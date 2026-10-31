local _, ns = ...

---------------------------------------------------------------------------
-- Geometry (from Questdon Arrow.lua "Geometry" and Minimap.lua, Guildon Map.lua): world positions in yards, the
-- position of a point on another map, distance and direction from the player.
-- World position = continentID, north, west (what C_Map.GetWorldPosFromMapPos answers).
---------------------------------------------------------------------------

-- The client's answer, two vector tables per call.
local function AskWorldPos(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not ns.Num(continent) or type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok2, wx, wy = pcall(pos.GetXY, pos)
  if not ok2 or not (ns.Num(wx) and ns.Num(wy)) then return nil end
  return continent, wx, wy
end

-- (Questdon 1.23) A map is an axis-aligned rectangle in the world, so its world position is linear in x and y (what
-- HereBeDragons does with the map's corners). Per map, the client is asked for three corners once and every point after
-- that is arithmetic. The first real point of a map is checked against the client; a map that does not fit (or any
-- unreadable answer) keeps asking the client. Replacing the client function (another addon) starts over.
local transforms, transformFn = {}, nil
local NONLINEAR = false
local function Transform(mapID)
  local fn = C_Map and C_Map.GetWorldPosFromMapPos
  if fn ~= transformFn then transforms, transformFn = {}, fn end
  local t = transforms[mapID]
  if t ~= nil then return t end
  local c0, n0, w0 = AskWorldPos(mapID, 0, 0)
  local c1, n1, w1 = AskWorldPos(mapID, 1, 0)
  local c2, n2, w2 = AskWorldPos(mapID, 0, 1)
  if not (c0 and c1 and c2) or c0 ~= c1 or c0 ~= c2 then return nil end -- not cached: ask again next time
  t = { c = c0, n0 = n0, w0 = w0, nx = n1 - n0, wx = w1 - w0, ny = n2 - n0, wy = w2 - w0, checked = false }
  transforms[mapID] = t
  return t
end

function ns.WorldPos(mapID, x, y)
  mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
  if not (mapID and x and y) then return nil end
  local t = Transform(mapID)
  if not t then return AskWorldPos(mapID, x, y) end
  local n, w = t.n0 + x * t.nx + y * t.ny, t.w0 + x * t.wx + y * t.wy
  if not t.checked then
    t.checked = true
    local c, an, aw = AskWorldPos(mapID, x, y)
    if c ~= t.c or not an or math.abs(an - n) > 0.5 or math.abs(aw - w) > 0.5 then
      transforms[mapID] = NONLINEAR
      return c, an, aw
    end
  end
  return t.c, n, w
end

-- The other way round: the map position (0-1) of a world position on mapID; nil when the map's corners are not known,
-- or it is another continent.
function ns.MapFromWorld(mapID, c, n, w)
  local t = Transform(mapID)
  if not t or t.c ~= c then return nil end
  local det = t.nx * t.wy - t.ny * t.wx
  if det == 0 then return nil end
  local dn, dw = n - t.n0, w - t.w0
  return (dn * t.wy - t.ny * dw) / det, (t.nx * dw - dn * t.wx) / det
end

-- Position of a point (mapID, x, y) on the map "shown" (0-1 each), nil when it is not on that map.
function ns.PosOnMap(mapID, x, y, shown)
  if mapID == shown then return x, y end
  local c, n, w = ns.WorldPos(mapID, x, y)
  if not c then return nil end
  local sx, sy = ns.MapFromWorld(shown, c, n, w)
  if not sx and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then -- (Guildon's way) the client's answer
    local ok, _, mp = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(n, w), shown)
    if ok and type(mp) == "table" and mp.GetXY then
      local ok2, a, b = pcall(mp.GetXY, mp)
      if ok2 then sx, sy = ns.Num(a), ns.Num(b) end
    end
  end
  if not (sx and sy) or sx < 0 or sx > 1 or sy < 0 or sy > 1 then return nil end
  return sx, sy
end

---------------------------------------------------------------------------
-- The player
---------------------------------------------------------------------------
-- (Questdon 1.22) Caves, mines and buildings can have their own small map (micro map): use the zone around them.
-- Static per map, cached.
local zoneOf = {}
local MICRO, DUNGEON, ZONE = 5, 4, 3
function ns.ZoneMap(mapID)
  if not mapID then return nil end
  local z = zoneOf[mapID]
  if z ~= nil then return z or mapID end
  z = false
  local info = C_Map and C_Map.GetMapInfo and ns.Call(C_Map.GetMapInfo, mapID)
  local t = type(info) == "table" and ns.Num(info.mapType)
  local types = Enum and Enum.UIMapType
  local micro = types and ns.Num(types.Micro) or MICRO
  local dungeon = types and ns.Num(types.Dungeon) or DUNGEON
  local zone = types and ns.Num(types.Zone) or ZONE
  if t and (t == micro or t == dungeon) then
    local parent = ns.Num(info.parentMapID)
    local pinfo = parent and parent > 0 and ns.Call(C_Map.GetMapInfo, parent)
    if type(pinfo) == "table" and ns.Num(pinfo.mapType) == zone then z = parent end
  end
  zoneOf[mapID] = z
  return z or mapID
end

local function MapRead(mapID)
  local pos = ns.Call(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok or not (ns.Num(x) and ns.Num(y)) or (x == 0 and y == 0) then return nil end
  return x, y
end

-- (M2, from Questdon Core.lua FromUnitPosition, Daniel's /qd mem 16.10.: about 1 MB a second) GetPlayerMapPosition makes
-- a new vector table at each call, and the arrow asks 33 times a second. UnitPosition answers with plain numbers: the
-- world position, turned into the map position with the map's corners. Checked against the map's own answer on each
-- new map and every 20 seconds (which of its two numbers is north too); one mismatch and it is not used again.
local unitPos = { state = nil, order = nil, map = nil, at = -100 } -- state: nil unknown, true fine, false off
local UNITPOS_TOLERANCE = 0.002 -- map units (2 to 8 yards on a zone map)
local function MapPos(mapID)
  if unitPos.state == false or type(UnitPosition) ~= "function" then return MapRead(mapID) end
  local ok, a, b, _, inst = pcall(UnitPosition, "player")
  a, b, inst = ok and ns.Num(a), ok and ns.Num(b), ok and ns.Num(inst)
  if not (a and b and inst) then return MapRead(mapID) end -- instances, secret values: the map's answer
  local now = ns.Num(ns.Call(GetTime)) or 0
  if unitPos.state and unitPos.map == mapID and now - unitPos.at < 20 and now >= unitPos.at then
    local x, y
    if unitPos.order == 1 then x, y = ns.MapFromWorld(mapID, inst, a, b) else x, y = ns.MapFromWorld(mapID, inst, b, a) end
    if x then return x, y end
  end
  local mx, my = MapRead(mapID)
  if not mx then return nil end
  local x1, y1 = ns.MapFromWorld(mapID, inst, a, b)
  local x2, y2 = ns.MapFromWorld(mapID, inst, b, a)
  local fit1 = x1 and math.abs(x1 - mx) < UNITPOS_TOLERANCE and math.abs(y1 - my) < UNITPOS_TOLERANCE
  local fit2 = x2 and math.abs(x2 - mx) < UNITPOS_TOLERANCE and math.abs(y2 - my) < UNITPOS_TOLERANCE
  if not x1 and not x2 then return mx, my end -- the map's corners not known yet: ask again next time
  -- where both world numbers are about equal both orders fit: that says nothing, asked again next time
  if fit1 and fit2 then
    if unitPos.state and unitPos.order then unitPos.map, unitPos.at = mapID, now end
    return mx, my
  end
  local order = fit1 and 1 or fit2 and 2 or nil
  if not order or (unitPos.order and order ~= unitPos.order) then
    unitPos.state = false -- does not fit this client: the map's answer from now on
    return mx, my
  end
  unitPos.state, unitPos.order, unitPos.map, unitPos.at = true, order, mapID, now
  return mx, my
end
function ns.UnitPositionState() return unitPos.state, unitPos.order end -- (diag, tests)

-- The player's map and position on it (0-1); nil in instances and wherever the client gives none.
function ns.PlayerPosition()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapID = ns.Num(ns.Call(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local x, y = MapPos(mapID)
  if not x then return nil end
  return mapID, x, y
end

-- The player's world position (continent, north, west). In caves and buildings with a small map of their own: from the
-- zone around when the small map gives no position or no world position (Questdon Minimap.lua PlayerOnZone).
function ns.PlayerWorld()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local mapID = ns.Num(ns.Call(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local x, y = MapPos(mapID)
  if x then
    local c, n, w = ns.WorldPos(mapID, x, y)
    if c then return c, n, w end
  end
  local zone = ns.ZoneMap(mapID)
  if zone == mapID then return nil end
  local zx, zy = MapPos(zone)
  if not zx then return nil end
  return ns.WorldPos(zone, zx, zy)
end

-- Distance (yards) and bearing (radians, clockwise from north) from the player to a point; nil on another continent.
function ns.DistanceTo(mapID, x, y)
  local pc, pn, pw = ns.PlayerWorld()
  if not pc then return nil end
  local tc, tn, tw = ns.WorldPos(mapID, x, y)
  if not tc or tc ~= pc then return nil end
  local north, east = tn - pn, -(tw - pw)
  local bearing = math.atan2 and math.atan2(east, north) or math.atan(east, north)
  return math.sqrt(north * north + east * east), bearing
end
