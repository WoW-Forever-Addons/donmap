local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 4) -- shared kit from DonCore (Libs\DonCore\Style.lua), for the arrow (M2)
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns) -- Blizzard options from DonCore (Options.lua)

---------------------------------------------------------------------------
-- DonMap (DONCORE_PLAN.md "DonMap im Einzelnen"): the map layer of the Don addons. Other addons register a source
-- (DonMapAPI.Register, API.lua) and hand over points; DonMap draws them on the world map (WorldPins.lua) and the
-- minimap (MiniPins.lua), groups points close together and keeps its pins below Questie and GatherMate (Layers.lua).
-- What the points mean stays with the addon. DonMap shows nothing by itself.
-- Own frames only: no hooksecurefunc, no HookScript, no scripts on Blizzard frames; the maps are only read.
---------------------------------------------------------------------------
ns.defaults = {
  off = {},  -- source id -> true: switched off by the player (/donmap <source>)
  -- (M2) the direction arrow, while no addon controls it (Questdon keeps these in QuestdonDB, same names)
  arrow = true,
  arrowScale = 1.15,
  arrowAlpha = 0.82,
  arrowPlain = true,
  arrowLocked = false,
  arrowCombatFade = false,
  arrowCorpse = true,
}
-- the arrow's settings that come over from QuestdonDB once (Arrow.lua, when Questdon takes control)
ns.ARROW_KEYS = { "arrow", "arrowScale", "arrowAlpha", "arrowPlain", "arrowLocked", "arrowCombatFade", "arrowCorpse", "arrowPos" }

do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, addonName, "Version")
  ns.VERSION = ok and type(v) == "string" and v or "?"
end

---------------------------------------------------------------------------
-- Values the client may hand out as secret (the same checks as in Guildon and Questdon)
---------------------------------------------------------------------------
function ns.Usable(v)
  if canaccessvalue then
    local ok, r = pcall(canaccessvalue, v)
    if ok then return r and true or false end
    return false
  end
  if issecretvalue then
    local ok, r = pcall(issecretvalue, v)
    if ok then return not r end
    return false
  end
  return true
end

function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

function ns.Str(v)
  if type(v) == "string" and ns.Usable(v) and v ~= "" then return v end
  return nil
end

function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

-- method on a frame, nil when it is missing or fails
function ns.Ask(f, method, ...)
  if f and type(f[method]) == "function" then
    local ok, v = pcall(f[method], f, ...)
    if ok then return v end
  end
end

-- for DonCore's Settings (a protected wrapper, as ns.Guard in the other addons)
function ns.Guard(where, fn)
  return function(...) return ns.Safe(where, fn, ...) end
end

function ns.Print(msg)
  print("|cff3fa9f5Don|rMap: " .. tostring(msg))
end

-- Errors in a source's callbacks while DonMap draws on its own: told once per source and place, then counted.
local errors = {}
function ns.Errors() return errors end
function ns.Safe(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return true end
  local e = errors[where]
  if e then e.count = e.count + 1 return false end
  errors[where] = { count = 1, msg = tostring(err) }
  ns.Print(L["Error in %s: %s"]:format(where, tostring(err)))
  return false
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local function InitDB()
  DonMapDB = type(DonMapDB) == "table" and DonMapDB or {}
  for k, v in pairs(ns.defaults) do
    if DonMapDB[k] == nil then DonMapDB[k] = type(v) == "table" and {} or v end
  end
  ns.db = DonMapDB
end
ns.db = { off = {} } -- until ADDON_LOADED: sources may register before the saved variables are there
for k, v in pairs(ns.defaults) do if ns.db[k] == nil and type(v) ~= "table" then ns.db[k] = v end end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    local early = ns.db
    InitDB()
    for id, v in pairs(early.off) do if ns.db.off[id] == nil then ns.db.off[id] = v end end
    if ns.Redraw then ns.Redraw() end
  end
end)

---------------------------------------------------------------------------
-- /donmap: the sources and their pins, a source on or off, the other addons' pin levels
---------------------------------------------------------------------------
SLASH_DONMAP1 = "/donmap"
function ns.Slash(msg)
  msg = (type(msg) == "string" and msg or ""):match("^%s*(.-)%s*$")
  if msg == "diag" then
    for _, line in ipairs(ns.ForeignPinLevels()) do print("  " .. line) end
    for where, e in pairs(errors) do print(("  error [%s] x%d: %s"):format(where, e.count, e.msg)) end
    return
  end
  -- (M2) the arrow: its settings (DonMap's own, or the controlling addon's, e.g. Questdon's /qd arrow)
  if msg == "arrow" then
    local db = ns.ArrowLook()
    db.arrow = not db.arrow
    if db.arrow then db.arrowAuto = nil end
    ns.ApplyArrowLook()
    ns.Print(L["The arrow is now %s."]:format(db.arrow and L["on"] or L["off"]))
    return
  end
  if msg == "options" or msg == "config" then ns.OpenOptions() return end
  if msg ~= "" then
    local src = ns.sources[msg:lower()]
    if not src then ns.Print(L["Unknown source: %s"]:format(msg)) return end
    ns.db.off[src.id] = (not ns.db.off[src.id]) or nil
    ns.Redraw()
    local prov = ns.worldProviders and ns.worldProviders[src.id] -- (M3b) its pins through the map's data provider
    if prov then ns.Safe(src.id .. " world map", prov.Refresh, prov) end
    ns.Print(L["%s is now %s."]:format(src.title, ns.db.off[src.id] and L["off"] or L["on"]))
    return
  end
  ns.Print(("v%s. %s"):format(ns.VERSION, L["Map layer of the Don addons. Sources:"]))
  if #ns.order == 0 then print("  " .. L["none yet"]) end
  for _, src in ipairs(ns.order) do
    print("  " .. L["%s: world map %d, minimap %d"]:format(src.title .. " (" .. src.id .. ", " .. (ns.db.off[src.id] and L["off"] or L["on"]) .. ")",
      src.n.world, src.n.minimap))
  end
  print("  " .. L["/donmap <source>: switch a source on or off. /donmap diag: levels of the other addons' pins."])
  print("  " .. L["/donmap arrow: show or hide the arrow. /donmap options: its settings."])
end
-- (05.11.2026) never assign the global SlashCmdList itself: that taints every chat slash command, and the first /run
-- then fails ("DonMap has been blocked", SetAllowDangerousScripts, taint.log on Forever live).
if type(SlashCmdList) == "table" then SlashCmdList.DONMAP = function(msg) ns.Slash(msg) end end
