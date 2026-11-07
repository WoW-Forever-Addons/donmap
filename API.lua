local _, ns = ...

---------------------------------------------------------------------------
-- DonMapAPI (versions 1 to 5 below, DONCORE_PLAN.md "Anmelde-API"): other addons register a source and hand over points; DonMap
-- draws them. Versions only add, never change: an addon checks DonMapAPI.version >= what it needs.
--
--   local src = DonMapAPI.Register("guildon", {
--     title = "Guildon",                 -- shown in /donmap
--     layer = 2,                         -- 0 to 4: order of the sources, a higher one draws above (Layers.lua)
--     world = true, minimap = true,      -- where to draw: boolean or function() -> boolean (read on every draw)
--     size = 16 | { world =, minimap =, groupWorld =, groupMinimap = } | function(where) -> size, groupSize
--     group = 0 | { world =, minimap = } | function(where) -> pixels   -- closer points become one pin
--     newPin = function(parent, size, where) -> frame                  -- own look (optional, with paint)
--     paint = function(pin, points, size, groupSize, where)            -- own look; pin.points = the points
--     onClick = function(pin, button, points), tooltip = function(pin, points)   -- for DonMap's plain pins
--   })
--   src:SetPoints({ { mapID =, x =, y =, key =, icon =, color = { r, g, b }, label =, world = false, minimap = false,
--                     sig = "...", ... } })   -- any other fields stay on the point for the source's own use
--   src:Update(where)      -- draw now ("world", "minimap" or both), returns the pins drawn (world, minimap)
--   src:Clear(), src:SetShown(on, where), src:Pins(where), src:Info(where)
-- Sizes and distances are screen pixels. A point's key sorts the points before grouping; "sig" is the part of a point
-- that is not in its other fields but changes its look (DonMap redraws by itself only when something changed).
-- Helpers: WorldPos, PosOnMap, PlayerPosition, PlayerWorld, DistanceTo, ZoneMap, WorldLevel, ForeignPinLevels, MapLevels.
---------------------------------------------------------------------------
local API = { version = 1 }

local Source = {}
Source.__index = Source

local function Round(v) return v and math.floor(v * 100000 + 0.5) or "" end

local function Sig(points)
  local parts = {}
  for i, pt in ipairs(points) do
    local c = pt.color
    parts[i] = table.concat({ tostring(pt.key or ""), tostring(pt.mapID or ""), Round(ns.Num(pt.x)), Round(ns.Num(pt.y)),
      tostring(pt.icon or ""), tostring(pt.label or ""), type(c) == "table" and table.concat({ c[1] or c.r or "", c[2] or c.g or "", c[3] or c.b or "" }, ",") or "",
      pt.world == false and "w" or "", pt.minimap == false and "m" or "", pt.only and "o" or "", tostring(pt.sig or "") }, "|")
  end
  return #points .. "#" .. table.concat(parts, ";")
end

-- sig (version 3): the source's own signature of the list (DonMap then does not build one; Questdon's minimap)
function Source:SetPoints(list, sig)
  if type(list) ~= "table" then list = {} end
  self.points = list
  self.sig = sig ~= nil and ("own:" .. tostring(sig)) or Sig(list)
end

function Source:Clear()
  self:SetPoints({})
  self:Update()
end

-- on = false hides the source's pins until SetShown(true); where = "world" or "minimap", nil = both
function Source:SetShown(on, where)
  for _, w in ipairs({ "world", "minimap" }) do
    if not where or where == w then self.shown[w] = on and true or false end
  end
  self:Update(where)
end

function Source:Update(where)
  local nw, nm = self.n.world, self.n.minimap
  if not where or where == "world" then nw = ns.DrawWorld(self, true) end
  if not where or where == "minimap" then nm = ns.DrawMini(self, true) end
  if where == "minimap" then return nm end
  return nw, nm
end

-- (version 3) draw only when something changed (Update always draws)
function Source:Refresh(where)
  if where == "minimap" then return ns.DrawMini(self) end -- a sticky source: count and whether it placed them
  local nw, nm = self.n.world, self.n.minimap
  if not where or where == "world" then nw = ns.DrawWorld(self) end
  if not where or where == "minimap" then nm = ns.DrawMini(self) end
  if where == "minimap" then return nm end
  return nw, nm
end

-- (version 3) a sticky source gives every button back (MiniPins.lua); the next draw dresses them anew
function Source:Release()
  if self.opts.sticky then ns.ReleaseSticky(self) end
end

function Source:Pins(where) return self.pins[where or "world"] end
function Source:Info(where) return self.info[where or "world"] end

function API.Register(id, opts)
  assert(type(id) == "string" and id ~= "", "DonMapAPI.Register: id expected")
  id = id:lower()
  opts = type(opts) == "table" and opts or {}
  local src = ns.sources[id]
  if not src then
    src = setmetatable({ id = id, points = {}, sig = "0#", shown = { world = true, minimap = true },
      pins = { world = {}, minimap = {} }, n = { world = 0, minimap = 0 }, view = {}, info = {} }, Source)
    ns.sources[id] = src
    ns.order[#ns.order + 1] = src
  end
  src.opts = opts
  src.title = tostring(opts.title or id)
  src.view = {} -- new options: draw again
  return src
end

function API.Get(id) return type(id) == "string" and ns.sources[id:lower()] or nil end

function API.Sources()
  local out = {}
  for _, src in ipairs(ns.order) do
    out[#out + 1] = { id = src.id, title = src.title, on = not ns.db.off[src.id], world = src.n.world, minimap = src.n.minimap }
  end
  return out
end

API.WorldPos = function(mapID, x, y) return ns.WorldPos(mapID, x, y) end
API.PosOnMap = function(mapID, x, y, shown) return ns.PosOnMap(mapID, x, y, shown) end
API.PlayerPosition = function() return ns.PlayerPosition() end
API.PlayerWorld = function() return ns.PlayerWorld() end
API.DistanceTo = function(mapID, x, y) return ns.DistanceTo(mapID, x, y) end
API.ZoneMap = function(mapID) return ns.ZoneMap(mapID) end
API.WorldLevel = function(layer, canvasLevel) return ns.WorldLevel(layer, canvasLevel) end
API.ForeignPinLevels = function() return ns.ForeignPinLevels() end
API.MapLevels = function() return ns.MapLevels() end

---------------------------------------------------------------------------
-- Version 2 (M2, 30.10.2026): the direction arrow and the compass (Arrow.lua, Compass.lua)
--   DonMapAPI.SetArrowTarget(source, target, prio)  target { mapID, x, y (0-1), label, view =, arrivedText = } or nil
--   DonMapAPI.SetArrowProvider(source, fn)          fn() -> target, prio (asked at every update)
--   DonMapAPI.PRIO = { auto = 1, guide = 2, click = 3 }; the corpse (as a ghost) comes first
--   DonMapAPI.ArrowTarget()                         the target the arrow shows now (and its source, prio)
--   DonMapAPI.ArrowState()                          what the arrow shows: angle, needle, nearness, seal, label, distText,
--                                                   distColor, dist, bearing (to the target), distShort, distWay,
--                                                   hasTarget, source; one table filled anew: read it at once
--   DonMapAPI.NewCompass(parent, size)              compass for a window: c:Point(bearing, facing, nearness), c:Arrived(on)
--   DonMapAPI.SetArrowUser(id, on)                  a window reads the arrow's state: the arrow runs without its window
--   DonMapAPI.SetArrowControl(id, ctl)              one addon controls the arrow (Questdon): ctl.look() -> settings table
--                                                   (keys arrow, arrowScale, arrowAlpha, arrowPlain, arrowLocked,
--                                                   arrowCombatFade, arrowCorpse, arrowPos), runs(), ghost(), view(t),
--                                                   onRightClick(t, source, prio), tooltip(t, lines, source)
--   DonMapAPI.ArrowStateRaw()                       the arrow's own state table (read only)
--   DonMapAPI.ApplyArrow(), ResetArrowPosition(), ArrowFrame(), CreateArrow(), SplitDistance(text, dist),
--   Nearness(dist), PlainView(t), ArrivedAt()
---------------------------------------------------------------------------
API.version = 2
API.PRIO = ns.PRIO
API.SetArrowTarget = function(source, target, prio) return ns.SetArrowTarget(source, target, prio) end
API.SetArrowProvider = function(source, fn) return ns.SetArrowProvider(source, fn) end
API.SetArrowControl = function(id, ctl) return ns.SetArrowControl(id, ctl) end
API.SetArrowUser = function(id, on) return ns.SetArrowUser(id, on) end
API.ArrowTarget = function() return ns.ArrowPick() end
local answer = {}
function API.ArrowState()
  local st, r = ns.ArrowStateRaw(), answer
  r.angle, r.needle, r.nearness, r.seal, r.label = st.angle, st.needle, st.nearness, st.seal, st.label
  r.distText, r.distColor, r.dist, r.bearing, r.hasTarget = st.distText, st.distColor, st.dist, st.bearing, st.t ~= nil
  r.distShort, r.distWay, r.source, r.t = st.distShort, st.distWay, st.source, st.t
  return r
end
-- the arrow's own state table (the fields of ArrowState, plus t, source, prio), for Questdon's quest list that reads it
-- many times a second; do not change it
API.ArrowStateRaw = function() return ns.ArrowStateRaw() end
API.NewCompass = function(parent, size) return ns.NewCompass(parent, size) end
API.ApplyArrow = function() if ns.ApplyArrowLook then ns.ApplyArrowLook() end end
API.ApplyArrowPosition = function() return ns.ApplyArrowPosition() end
API.ResetArrowPosition = function() return ns.ResetArrowPosition() end
API.ArrowFrame = function() return ns.ArrowFrame() end
API.CreateArrow = function() return ns.CreateArrow() end
API.ArrowRuns = function() return ns.ArrowRuns() end
API.ArrowGhost = function() return ns.ArrowGhost() end
API.SplitDistance = function(text, dist) return ns.SplitDistance(text, dist) end
API.Nearness = function(dist) return ns.Nearness(dist) end
API.PlainView = function(t) return ns.PlainView(t) end
API.ArrivedAt = function() return ns.ArrivedAt() end
API.CorpseTarget = function() return ns.CorpseTarget() end

---------------------------------------------------------------------------
-- Version 3 (M3, 30.10.2026): Questdon's minimap pins and its symbols for inns, banks and the like
--   src:SetPoints(list, sig)    sig: the source's own signature of the list (no signature built by DonMap)
--   src:Refresh(where)          draws only when something changed; src:Release() gives a sticky source's buttons back
--   point.only = true           on the world map only on the point's own map, not on the maps above it
--   opts.sticky (minimap)       the source groups itself and every point keeps its button while in view; with
--                               view, dress, place, release, rebundle, max, clock (MiniPins.lua "Sticky sources")
---------------------------------------------------------------------------
API.version = 3

---------------------------------------------------------------------------
-- Version 4 (M3b, 30.10.2026): world map pins through the map's own data provider, and the game's quest markers
-- (WorldProvider.lua)
--   DonMapAPI.NewWorldProvider(id, opts)      a data provider with DonMap's rules (combat, closed map, zoom, the build
--                                             before combat); opts templates, build, same, zoomed, ask, removed, stats
--   DonMapAPI.HideGameQuestMarks(id, opts)    take the game's quest markers away while opts.on(); keep(pin), keeps(v)
--   DonMapAPI.ClearGameQuestMarks(), QueueClearGameQuestMarks(), ApplyGameQuestMarks(), RedrawGameIfPending(),
--   GameQuestProviders(), IsGameQuestTemplate(t), GameMarkShown(map), GameQuestMarkStats(), HiddenGameBlobs()
---------------------------------------------------------------------------
API.version = 4
API.NewWorldProvider = function(id, opts) return ns.NewWorldProvider(id, opts) end
API.WorldProvider = function(id) return type(id) == "string" and ns.worldProviders[id:lower()] or nil end
API.HideGameQuestMarks = function(id, opts) return ns.HideGameQuestMarks(id, opts) end
API.ClearGameQuestMarks = function() return ns.ClearGameQuestMarks() end
API.QueueClearGameQuestMarks = function() return ns.QueueClearGameQuestMarks() end
API.ApplyGameQuestMarks = function() return ns.ApplyGameQuestMarks() end
API.RedrawGameIfPending = function() return ns.RedrawGameIfPending() end
API.GameQuestProviders = function() return ns.GameQuestProviders() end
API.IsGameQuestTemplate = function(t) return ns.IsGameQuestTemplate(t) end
API.GameMarkShown = function(map) return ns.GameMarkShown(map) end
API.GameQuestMarkStats = function() return ns.gameMarks.stats end
API.HiddenGameBlobs = function() return ns.gameMarks.hidden end
API.GameRedrawPending = function() return ns.gameMarks.redraw and true or false end

---------------------------------------------------------------------------
-- Version 5 (31.10.2026): a guide's compass in its own window
--   DonMapAPI.SetArrowCompass(id, on)         while on, the compass in that addon's window shows the way: the arrow
--                                             runs for it but draws nothing (only without a controlling addon;
--                                             Questdon has its own rule, QuestdonAPI.SetGuideCompass)
---------------------------------------------------------------------------
API.version = 5
API.SetArrowCompass = function(id, on) return ns.SetArrowCompass(id, on) end

---------------------------------------------------------------------------
-- Version 6 (07.11.2026): opts.playerOnTop = true | function() -> boolean: while a minimap pin of the source covers
-- the middle, a copy of the player's arrow is drawn above it (MiniPins.lua ns.PlayerOnTop)
---------------------------------------------------------------------------
API.version = 6

DonMapAPI = API
ns.API = API

---------------------------------------------------------------------------
-- One frame of our own redraws what changed, 10 times a second (map moved or zoomed, player moved or turned, points)
---------------------------------------------------------------------------
function ns.Redraw()
  for _, src in ipairs(ns.order) do src.view = {} end
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
  acc = acc + (dt or 0)
  if acc < 0.1 then return end
  acc = 0
  for _, src in ipairs(ns.order) do
    if src.opts.clock ~= false and (#src.points > 0 or src.n.world > 0 or src.n.minimap > 0) then
      ns.Safe(src.id .. " world map", ns.DrawWorld, src)
      ns.Safe(src.id .. " minimap", ns.DrawMini, src)
    end
  end
  ns.Safe("player arrow", ns.PlayerOnTop) -- (07.11.2026) the player's arrow above the pins (MiniPins.lua)
end)
