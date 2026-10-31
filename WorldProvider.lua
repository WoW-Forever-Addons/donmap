local _, ns = ...

---------------------------------------------------------------------------
-- (M3b, 30.10.2026) World map pins through the map's own data provider (from Questdon MapPins.lua 1.3.13): for a source
-- that wants Blizzard's pin look (POI pins with "!" and "?", frame level types, the map's scaling and tooltips). The
-- source keeps its templates, mixins and what it draws; DonMap keeps the rules every such provider needs:
--   * combat: new pins cannot be made in combat (the canvas calls SetPassThroughButtons on every pin it hands out, which
--     addon code may not call in combat since 10.1.5). The pins of the map last drawn stay when that map is opened again
--     in combat; another map's pins go (they would stand in wrong places).
--   * a closed map draws nothing (drawn when it opens; OnShow as a fallback), except the build right before combat:
--     with the map closed and set to the player's zone, it is drawn at PLAYER_REGEN_DISABLED, so the map opened in
--     combat shows its pins.
--   * the map asks again and the source says nothing changed: its pins stay while they are all still on the canvas.
--   * zoom: the source is asked whether the new zoom changes its pins.
-- Errors in the source's callbacks are the source's (it passes guarded functions); the provider's own calls are guarded.
--
--   local prov = DonMapAPI.NewWorldProvider("questdon", {
--     templates = { "QuestdonQuestPinTemplate", ... },   -- the templates it acquires (removed and counted by DonMap)
--     build = function(prov, map, mapID) -> true,        -- draws: prov:Acquire(template, data) for every pin; true when done
--     same = function(prov, map, mapID) -> true,         -- nothing changed since the last build (optional)
--     zoomed = function(prov, map, scale) -> true,       -- the new zoom changes the pins (optional)
--     ask = function(prov, map, closed),                 -- every request of the map, before anything else (optional)
--     removed = function(prov),                          -- the pins went (optional)
--     kept = function(prov),                             -- "same" said so and all its pins were there: they stay
--     stats = {},                                        -- counts builds, keptInCombat, closedSkips, sameSkips, preCombat
--   })
--   prov:Refresh(), prov:BuiltMap(), prov:Map(), prov:Ready(); the map's own provider methods as usual.
---------------------------------------------------------------------------
ns.worldProviders = {} -- id -> provider

local function Shown(map) return map and map.IsShown and map:IsShown() and true or false end

local function OwnCount(p, map)
  if not map.EnumeratePinsByTemplate then return nil end
  local n = 0
  local ok = pcall(function()
    for _, t in ipairs(p.dm.templates) do
      for _ in map:EnumeratePinsByTemplate(t) do n = n + 1 end
    end
  end)
  return ok and n or nil
end

local function Count(p, key) p.dm.stats[key] = (p.dm.stats[key] or 0) + 1 end

local Provider = {}

function Provider:Acquire(template, data, ...)
  local pin = self:GetMap():AcquirePin(template, data, ...)
  self.dm.count = self.dm.count + 1
  return pin
end

function Provider:BuiltMap() return self.dm.built end
function Provider:Map() return self.GetMap and self:GetMap() or nil end
function Provider:Ready() return self.dm.ready end
function Provider:Forced() return self.dm.force and true or false end -- the build before combat (map closed)
function Provider:Off() return ns.db.off and ns.db.off[self.dm.id] and true or false end -- /donmap <source> off

-- draws now if the map is open (the source's own refresh after its data changed)
function Provider:Refresh()
  local map = self:Map()
  if map and Shown(map) then self:RefreshAllData() end
end

local function Remove(self)
  local d = self.dm
  d.built, d.count = nil, 0
  local map = self:GetMap()
  for _, t in ipairs(d.templates) do map:RemoveAllPinsByTemplate(t) end
  if d.opts.removed then d.opts.removed(self) end
end

local function Refresh(self)
  local d = self.dm
  local map = self:GetMap()
  local closed = not Shown(map)
  -- /donmap <source> off: its pins go, also in combat (only making pins is not allowed then)
  if ns.db.off and ns.db.off[d.id] then
    if d.opts.ask then d.opts.ask(self, map, closed) end
    self:RemoveAllData()
    return
  end
  if InCombatLockdown() then
    local m = ns.Num(ns.Call(map.GetMapID, map))
    if m and m == d.built then Count(self, "keptInCombat") return end
    self:RemoveAllData()
    return
  end
  if d.opts.ask then d.opts.ask(self, map, closed) end
  if closed and not d.force then
    Count(self, "closedSkips")
    d.built, d.count = nil, 0
    if d.opts.removed then d.opts.removed(self) end
    return
  end
  local mapID = ns.Num(ns.Call(map.GetMapID, map))
  if not mapID then self:RemoveAllData() return end
  if mapID == d.built and d.opts.same and d.opts.same(self, map, mapID) and OwnCount(self, map) == d.count then
    Count(self, "sameSkips")
    if d.opts.kept then d.opts.kept(self) end
    return
  end
  self:RemoveAllData()
  d.count = 0
  -- (review) only a build that ran through counts as drawn (a half-built map is not kept in combat)
  if d.opts.build(self, map, mapID) then
    Count(self, "builds")
    d.built = mapID
  end
end

local function Zoomed(self)
  local d = self.dm
  if InCombatLockdown() or not self:GetMap() or not d.opts.zoomed then return end
  local map = self:GetMap()
  local scale = map.GetCanvasScale and ns.Call(map.GetCanvasScale, map) or nil
  if d.opts.zoomed(self, map, scale) then self:RefreshAllData() end
end

function ns.NewWorldProvider(id, opts)
  assert(type(id) == "string" and id ~= "", "DonMapAPI.NewWorldProvider: id expected")
  assert(type(opts) == "table" and type(opts.build) == "function", "DonMapAPI.NewWorldProvider: opts.build expected")
  id = id:lower()
  if ns.worldProviders[id] then return ns.worldProviders[id] end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and CreateFromMixins) then return nil end
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  for k, v in pairs(Provider) do p[k] = v end
  p.dm = { id = id, opts = opts, templates = opts.templates or {}, stats = opts.stats or {}, count = 0 }
  p.RemoveAllData = ns.Guard(id .. " world map", Remove)
  p.RefreshAllData = ns.Guard(id .. " world map", Refresh)
  -- the map opened: drawn now if a request while it was closed was skipped (the map normally asks itself)
  p.OnShow = ns.Guard(id .. " world map", function(self)
    if not self.dm.built and self:GetMap() and not InCombatLockdown() then self:RefreshAllData() end
  end)
  p.OnCanvasScaleChanged = ns.Guard(id .. " world map", Zoomed)
  if not pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, p) then return nil end
  p.dm.ready = true
  ns.worldProviders[id] = p
  for _, t in ipairs(p.dm.templates) do ns.ownTemplates[t] = true end
  return p
end

-- Combat starts (the lockdown begins right after this event): a closed map set to the player's zone draws now.
local function PreCombat()
  if InCombatLockdown() or Shown(WorldMapFrame) then return end
  local zone = C_Map and C_Map.GetBestMapForUnit and ns.Num(ns.Call(C_Map.GetBestMapForUnit, "player"))
  for _, p in pairs(ns.worldProviders) do
    local map = p.GetMap and p:GetMap()
    local m = map and ns.Num(ns.Call(map.GetMapID, map))
    if m and m == zone and m ~= p.dm.built then
      Count(p, "preCombat")
      p.dm.force = true
      p:RefreshAllData()
      p.dm.force = false
    end
  end
end
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function() ns.Safe("world map before combat", PreCombat) end)

---------------------------------------------------------------------------
-- The game's quest markers on the world map, taken away for a source that draws its own (from Questdon MapPins.lua,
-- option hideGamePOIs 17. and 18.10.2026). No hook on the game's code: after the source's refresh, after the quest events
-- the game redraws them on, and while the map is open (a small frame looks every 0.03 s and clears a marker as soon as
-- it shows, so they do not flash), the game's two quest providers are asked to remove their pins. The quest areas
-- (one pin the provider keeps for good) are only hidden. Of the round markers those the source wants are kept
-- (opts.keep(pin): true keep, false remove, nil cannot be told; then all go and opts.keeps(false) says so).
--
--   DonMapAPI.HideGameQuestMarks("questdon", { on = function() -> bool, keep = function(pin) -> bool|nil,
--     keeps = function(v), keeping = function() -> v, prefix = "Questdon" })   -- v: true the game keeps the wanted
--     markers, false it keeps none, nil not known yet; prefix: the source's own templates start so
--   DonMapAPI.ClearGameQuestMarks(), QueueClearGameQuestMarks(), ApplyGameQuestMarks(), RedrawGameIfPending()
---------------------------------------------------------------------------
ns.ownTemplates = {} -- templates of DonMap's providers: never the game's
local marks = { stats = { providers = 0, templates = 0, runs = 0 }, hidden = setmetatable({}, { __mode = "k" }) }
ns.gameMarks = marks

local function MarksOn()
  local o = marks.opts
  if not o then return false end
  local ok, r = pcall(o.on)
  return ok and r and true or false
end

function ns.GameQuestProviders()
  local out = {}
  local list = WorldMapFrame and WorldMapFrame.dataProviders
  if type(list) ~= "table" then return out end
  for dp in pairs(list) do
    for _, name in ipairs({ "QuestDataProviderMixin", "QuestBlobDataProviderMixin" }) do
      local m = rawget(_G, name)
      if type(m) == "table" and type(dp) == "table" and m.RefreshAllData and dp.RefreshAllData == m.RefreshAllData then
        out[#out + 1] = dp
      end
    end
  end
  return out
end

-- the game's quest markers and quest areas; never a template of ours or of the source, never the "!" to pick up
local GAME_TEMPLATES = { QuestPinTemplate = true, QuestBlobPinTemplate = true }
function ns.IsGameQuestTemplate(t)
  if type(t) ~= "string" or ns.ownTemplates[t] then return false end
  if marks.prefix and t:find(marks.prefix, 1, true) == 1 then return false end
  return (GAME_TEMPLATES[t] or t:find("QuestBlob") ~= nil) and true or false
end

local function Keep(pin)
  local f = marks.opts and marks.opts.keep
  if not f then return nil end
  local ok, r = pcall(f, pin)
  if not ok then return nil end
  return r
end

-- what the game keeps: the source's own state if it holds one (opts.keeping), else DonMap's
local function Keeps()
  local f = marks.opts and marks.opts.keeping
  if f then return f() end
  return marks.keeps
end
local function SetKeeps(v)
  if Keeps() == v then return end
  marks.keeps = v
  local f = marks.opts and marks.opts.keeps
  if f then pcall(f, v) end
end

function ns.ClearGameQuestMarks()
  if not MarksOn() or InCombatLockdown() then return 0 end
  local st = marks.stats
  local n = 0
  local blobMixin = rawget(_G, "QuestBlobDataProviderMixin")
  for _, dp in ipairs(ns.GameQuestProviders()) do
    -- the quest provider keeps its ? pins (taken one by one below), unless they cannot be told apart
    local isBlob = type(blobMixin) == "table" and blobMixin.RefreshAllData and dp.RefreshAllData == blobMixin.RefreshAllData
    if (isBlob or Keeps() == false) and dp.RemoveAllData and pcall(dp.RemoveAllData, dp) then n = n + 1 end
  end
  st.providers, st.templates, st.runs = n, 0, st.runs + 1
  local map = WorldMapFrame
  if map and type(map.pinPools) == "table" and map.RemoveAllPinsByTemplate then
    for t in pairs(map.pinPools) do
      if ns.IsGameQuestTemplate(t) then
        if t:find("QuestBlob") then
          -- the quest area is one pin its provider keeps for good: given back to the pool it never came again
          if map.EnumeratePinsByTemplate then
            local ok = pcall(function() for pin in map:EnumeratePinsByTemplate(t) do pin:Hide() marks.hidden[pin] = true end end)
            if ok then st.templates = st.templates + 1 end
          end
        else
          local done = false
          if Keeps() ~= false and map.EnumeratePinsByTemplate and map.RemovePin then
            local drop, unknown, seen = nil, false, 0
            local ok = pcall(function()
              for pin in map:EnumeratePinsByTemplate(t) do
                seen = seen + 1
                local keep = Keep(pin)
                if keep == nil then unknown = true end
                if not keep then drop = drop or {} drop[#drop + 1] = pin end
              end
            end)
            if ok and not unknown then
              local all = true
              for _, pin in ipairs(drop or {}) do if not pcall(map.RemovePin, map, pin) then all = false end end
              if all then done = true if seen > 0 then SetKeeps(true) end end -- (true only once pins were seen that carry their quest)
            end
          end
          if not done then
            SetKeeps(false) -- the pins cannot be told apart: all go, the source draws its own
            if pcall(map.RemoveAllPinsByTemplate, map, t) then st.templates = st.templates + 1 end
          else
            st.templates = st.templates + 1
          end
        end
      end
    end
  end
  return n + st.templates
end

local function After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, function() ns.Safe("game quest markers", fn) end) end
end

local clearQueued = false
function ns.QueueClearGameQuestMarks()
  if clearQueued or not MarksOn() then return end
  clearQueued = true
  After(0.05, function() clearQueued = false ns.ClearGameQuestMarks() end)
end

-- the option went off: every provider of the map draws anew (the map's own RefreshAllDataProviders), right away and
-- once more the next time the source's map is drawn (the map may be closed while the option changes)
local function RedrawGame()
  local map = WorldMapFrame
  for pin in pairs(marks.hidden) do pcall(pin.Show, pin) marks.hidden[pin] = nil end
  for _, dp in ipairs(ns.GameQuestProviders()) do if dp.RefreshAllData then pcall(dp.RefreshAllData, dp) end end
  if map and map.RefreshAllDataProviders then pcall(map.RefreshAllDataProviders, map) end
end
function ns.RedrawGameIfPending()
  if not marks.redraw or MarksOn() or InCombatLockdown() then return end
  marks.redraw = false
  After(0.05, function() if not MarksOn() and not InCombatLockdown() then RedrawGame() end end)
end
function ns.ApplyGameQuestMarks()
  if MarksOn() then marks.redraw = false ns.ClearGameQuestMarks() return end
  marks.redraw = true
  if InCombatLockdown() then return end
  RedrawGame()
end

-- a game marker shown now (only reads the map's pools, no new tables)
function ns.GameMarkShown(map)
  local pools = map and map.pinPools
  if type(pools) ~= "table" then return false end
  for t, pool in pairs(pools) do
    if ns.IsGameQuestTemplate(t) and type(pool) == "table" and type(pool.activeObjects) == "table" then
      local blob = t:find("QuestBlob") ~= nil
      for pin in pairs(pool.activeObjects) do
        if not blob then
          if Keeps() == false or Keep(pin) ~= true then return true end
        elseif type(pin) == "table" and pin.IsShown and pin:IsShown() then return true end
      end
    end
  end
  return false
end

function ns.HideGameQuestMarks(id, opts)
  assert(type(id) == "string" and type(opts) == "table" and type(opts.on) == "function", "DonMapAPI.HideGameQuestMarks: id and opts.on expected")
  marks.id, marks.opts, marks.prefix = id:lower(), opts, opts.prefix
  return marks
end

local function WatchCheck(map) if ns.GameMarkShown(map) then ns.ClearGameQuestMarks() end end
local watch = CreateFrame("Frame")
local watchElapsed = 0
watch:SetScript("OnUpdate", function(_, dt)
  if not marks.opts then return end
  watchElapsed = watchElapsed + (tonumber(dt) or 0)
  if watchElapsed < 0.03 then return end
  watchElapsed = 0
  local map = WorldMapFrame
  if not Shown(map) or InCombatLockdown() or not MarksOn() then return end
  ns.Safe("game markers watch", WatchCheck, map) -- no closure every 0.03 s
end)
local markEvents = CreateFrame("Frame")
-- (Era has no SUPER_TRACKING_CHANGED: an unknown event is an error there)
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do pcall(markEvents.RegisterEvent, markEvents, e) end
markEvents:SetScript("OnEvent", function() if marks.opts and Shown(WorldMapFrame) then ns.QueueClearGameQuestMarks() end end)
