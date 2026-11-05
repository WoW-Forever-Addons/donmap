local _, ns = ...

---------------------------------------------------------------------------
-- Frame levels (from Guildon Map.lua, 27.10.2026): our pins above the map's tiles and below the other addons' marks.
-- Questie puts its world map icons at the fixed level 2016 and up, its lines at 2015 (it counts the scroll container from
-- 2000); GatherMate2 only uses the minimap, at minimap + 5 (Daniel's /gn diag on Era, 27.10.). A source's "layer"
-- (0 to 4, default 2) picks its level: world map WORLD_BASE + layer (Guildon 2012, as tested in the game), minimap one
-- above the minimap as before (layers 3 and 4 one and two higher, still below GatherMate). A higher layer draws above.
---------------------------------------------------------------------------
ns.WORLD_BASE = 2010
ns.LAYER_MAX = 4

function ns.Layer(src)
  local v = tonumber(src and src.opts.layer) or 2
  return math.max(0, math.min(ns.LAYER_MAX, math.floor(v)))
end

-- (05.11.2026, Daniel: "aber weltmap sollte hovern möglich sein", a guild member under Questdon's "!") a source with
-- opts.top = true: its world map pins go one above the highest of Questdon's quest pins (they take their level from the
-- map's own level manager, above the fixed 2010 + layer). Looked up at most once a second.
local TOP_TEMPLATES = { "QuestdonQuestPinTemplate", "QuestdonObjectivePinTemplate", "QuestdonAreaPinTemplate" }
local top = { t = -10, level = nil }
function ns.TopWorldLevel()
  local now = GetTime and GetTime() or 0
  if now - top.t < 1 then return top.level end
  top.t = now
  local wm, hi = WorldMapFrame, nil
  if wm and type(wm.EnumeratePinsByTemplate) == "function" then
    for _, tpl in ipairs(TOP_TEMPLATES) do
      pcall(function()
        for pin in wm:EnumeratePinsByTemplate(tpl) do
          local l = ns.Ask(pin, "GetFrameLevel")
          if type(l) == "number" and (not hi or l > hi) then hi = l end
        end
      end)
    end
  end
  top.level = hi and hi + 1 or nil
  return top.level
end
function ns.ForgetTopLevel() top.t = -10 end -- (tests)

-- level of a source's world map pins; one above the canvas if that is higher already
function ns.WorldLevel(layer, canvasLevel)
  return math.max(ns.WORLD_BASE + (layer or 2), (canvasLevel or 0) + 1)
end

-- Guildon's dots sat at minimap + 1 (a child frame's default), GatherMate is at + 5
function ns.MiniLevel(layer, minimapLevel)
  return (minimapLevel or 0) + 1 + math.max(0, (layer or 2) - 2)
end

-- put a pin on a level and keep it there (the world map's canvas would hand out its own)
function ns.SetLevel(b, want)
  if b._dmLevel == want or not b.SetFrameLevel then return end
  b._dmLevel = want
  if b.SetFixedFrameLevel then pcall(b.SetFixedFrameLevel, b, false) end
  pcall(b.SetFrameLevel, b, want)
  if b.SetFixedFrameLevel then pcall(b.SetFixedFrameLevel, b, true) end
end

---------------------------------------------------------------------------
-- Read only, for /donmap diag and the sources' own diag: the levels of Questie's (HereBeDragons) and GatherMate2's pins on
-- the open world map and on the minimap, next to ours.
---------------------------------------------------------------------------
local function Range(lo, hi, n, lv)
  if not lv then return lo, hi, n end
  return (lo and math.min(lo, lv) or lv), (hi and math.max(hi, lv) or lv), n + 1
end

function ns.ForeignPinLevels()
  local Ask = ns.Ask
  local out = {}
  local wm = WorldMapFrame
  if wm and wm.EnumeratePinsByTemplate and wm.IsShown and wm:IsShown() then
    for _, tpl in ipairs({ "HereBeDragonsPinsTemplateQuestie", "HereBeDragonsPinsTemplate", "GatherMate2WorldMapPinTemplate" }) do
      local lo, hi, n, clo, chi, cn = nil, nil, 0, nil, nil, 0
      local ok = pcall(function()
        for pin in wm:EnumeratePinsByTemplate(tpl) do
          lo, hi, n = Range(lo, hi, n, Ask(pin, "GetFrameLevel"))
          if pin.icon then clo, chi, cn = Range(clo, chi, cn, Ask(pin.icon, "GetFrameLevel")) end
        end
      end)
      if ok and n > 0 then
        out[#out + 1] = ("world %s: %d pins, level %s to %s%s"):format(tpl, n, tostring(lo), tostring(hi),
          cn > 0 and (", icons %s to %s"):format(tostring(clo), tostring(chi)) or "")
      end
    end
  end
  if Minimap and Minimap.GetChildren then
    local lo, hi, n, glo, ghi, gn = nil, nil, 0, nil, nil, 0
    for _, c in ipairs({ Minimap:GetChildren() }) do
      local name = Ask(c, "GetName")
      if type(name) == "string" and name:find("^GatherMatePin") and Ask(c, "IsShown") then
        glo, ghi, gn = Range(glo, ghi, gn, Ask(c, "GetFrameLevel"))
      elseif c.data or c.miniMapIcon then -- Questie's icon frames carry their data
        if Ask(c, "IsShown") then lo, hi, n = Range(lo, hi, n, Ask(c, "GetFrameLevel")) end
      end
    end
    local mine
    for _, src in ipairs(ns.order or {}) do
      local b = src.pins.minimap[1]
      if b then mine = Ask(b, "GetFrameLevel") break end
    end
    out[#out + 1] = ("minimap level %s, ours %s, Questie %d (%s to %s), GatherMate %d (%s to %s)"):format(
      tostring(Ask(Minimap, "GetFrameLevel")), tostring(mine), n, tostring(lo), tostring(hi), gn, tostring(glo), tostring(ghi))
  end
  return out
end

-- The world map's own levels (its frame level manager), only shown in diag: explored areas, area POI (the type
-- GatherMate and HereBeDragons use).
local function TypeLevel(mgr, t)
  if not mgr or type(mgr.GetValidFrameLevel) ~= "function" then return nil end
  local ok, v = pcall(mgr.GetValidFrameLevel, mgr, t)
  return ok and type(v) == "number" and v or nil
end
function ns.MapLevels()
  local wm = WorldMapFrame
  local mgr = wm and type(wm.GetPinFrameLevelsManager) == "function" and select(2, pcall(wm.GetPinFrameLevelsManager, wm)) or nil
  if type(mgr) ~= "table" then mgr = nil end
  return TypeLevel(mgr, "PIN_FRAME_LEVEL_MAP_EXPLORATION"), TypeLevel(mgr, "PIN_FRAME_LEVEL_AREA_POI")
end
