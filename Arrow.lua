local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (M2, 30.10.2026, DONCORE_PLAN.md "DonMap im Einzelnen") The direction arrow of the Don addons, moved here from
-- Questdon's Arrow.lua: the window (golden needle, seal when arrived, plaque with target and distance), its position,
-- size and look, which target it shows, and the way back to your corpse. Addons hand over targets:
--   DonMapAPI.SetArrowTarget(source, target, prio)   target { mapID, x, y, label, ... } or nil to release it
--   DonMapAPI.SetArrowProvider(source, fn)           fn() -> target, prio; asked at every update (Questdon)
-- prio: DonMapAPI.PRIO.auto (1, an addon's own choice), guide (2, a guide such as Leveldon), click (3, a clicked pin
-- or member). The highest wins, the newest among equals; the corpse (as a ghost) comes first.
-- What a target means stays with its addon: target.view(t) (or the controller's view) works out what the arrow shows
-- (Questdon: objective area, the way around, caves); without one DonMap measures distance and bearing itself.
-- One addon may control the arrow (DonMapAPI.SetArrowControl, Questdon): its settings table, when the arrow runs,
-- when it draws nothing (its compass shows the way), right-click and tooltip. Without one DonMap's own settings count.
---------------------------------------------------------------------------
local ARRIVED_YARDS = 8
local ARRIVED_LEAVE = 15 -- arrived stays until this far away (no flicker one step on)
local ICON = 60
local TEXT_W = 220
local FAR, NEAR = 200, 30 -- yards: matte gold beyond FAR, full shine and glow inside NEAR
local MEDIA = "Interface\\AddOns\\DonMap\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local NAVY = { 0.08, 0.09, 0.19 }

local PRIO = { auto = 1, guide = 2, click = 3 }
-- the arrow's words: from the controlling addon when it has them (Questdon speaks nine languages, DonMap two)
local control
local function T(key)
  local cl = control and control.L
  if type(cl) == "table" then
    local ok, v = pcall(function() return cl[key] end)
    if ok and type(v) == "string" then return v end
  end
  return L[key]
end
ns.PRIO = PRIO

local Style -- DonCore's kit, set in Create (Core.lua takes it)
local arrow
-- control: { id, title, L, look, runs, ghost, view, onRightClick, tooltip } (above, with T)
local targets, seq = {}, 0 -- source -> { t =, prio =, seq = } or { fn =, seq = }
local state = {}
local current, currentSrc, currentPrio
local arrivedAt = { mapID = nil, x = nil, y = nil }

local function Clamp(v, lo, hi, default)
  v = tonumber(v)
  if not v or v ~= v then return default end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- the settings that count: the controller's table (Questdon's QuestdonDB, same key names) or DonMap's own
local function Look()
  local db = control and control.look and ns.Call(control.look)
  return type(db) == "table" and db or ns.db
end
ns.ArrowLook = Look

---------------------------------------------------------------------------
-- Which target
---------------------------------------------------------------------------
local corpse, corpseTarget
local corpseAt = -1
local function Now() return ns.Num(ns.Call(GetTime)) or 0 end
local function True(v) return v == true or (type(v) == "number" and v ~= 0 and ns.Usable(v)) end

-- Dead and released (a ghost): the game's corpse position for the map you died on, else where you died.
local function CorpseTarget()
  if not (Look().arrowCorpse and True(ns.Call(UnitIsGhost, "player"))) then corpseTarget = nil return nil end
  local now = Now()
  if corpseTarget and now - corpseAt < 1 then return corpseTarget end
  corpseAt = now
  local mapID = corpse and corpse.mapID or ns.Num(C_Map and ns.Call(C_Map.GetBestMapForUnit, "player"))
  local x, y
  if mapID and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
    local pos = ns.Call(C_DeathInfo.GetCorpseMapPosition, mapID)
    if type(pos) == "table" then
      local ok, px, py = pcall(function() return pos:GetXY() end)
      if ok then x, y = ns.Num(px), ns.Num(py) end
      if not x then x, y = ns.Num(pos.x), ns.Num(pos.y) end
      if x and y and x == 0 and y == 0 then x, y = nil, nil end
    end
  end
  if not (x and y) and corpse then mapID, x, y = corpse.mapID, corpse.x, corpse.y end
  if not (mapID and x and y) then corpseTarget = nil return nil end
  corpseTarget = { mapID = mapID, x = x, y = y, label = T("Your corpse"), corpse = true }
  return corpseTarget
end
ns.CorpseTarget = CorpseTarget

function ns.ArrowDead(mapID, x, y)
  corpse = mapID and x and y and { mapID = mapID, x = x, y = y } or nil
  corpseTarget = nil
end
function ns.ArrowAlive() corpse, corpseTarget = nil, nil end

local function Pick()
  local c = CorpseTarget()
  if c then current, currentSrc, currentPrio = c, "corpse", 9 return c end
  local best, bestSrc, bestPrio, bestSeq
  for id, e in pairs(targets) do
    local t, prio = e.t, e.prio
    if e.fn then
      local ok, a, b = pcall(e.fn)
      if ok then t, prio = a, b else t = nil end
    end
    if type(t) == "table" then
      prio = tonumber(prio) or PRIO.guide
      if not best or prio > bestPrio or (prio == bestPrio and e.seq > bestSeq) then
        best, bestSrc, bestPrio, bestSeq = t, id, prio, e.seq
      end
    end
  end
  current, currentSrc, currentPrio = best, bestSrc, bestPrio
  return best
end
ns.ArrowTarget = function() return Pick() end
function ns.ArrowPick() Pick() return current, currentSrc, currentPrio end

function ns.SetArrowTarget(source, target, prio)
  source = tostring(source or "?"):lower()
  if type(target) ~= "table" then targets[source] = nil return end
  seq = seq + 1
  targets[source] = { t = target, prio = tonumber(prio) or PRIO.guide, seq = seq }
  if arrow and ns.ArrowRuns() then arrow:Show() end
end

function ns.SetArrowProvider(source, fn)
  source = tostring(source or "?"):lower()
  if type(fn) ~= "function" then targets[source] = nil return end
  seq = seq + 1
  targets[source] = { fn = fn, seq = seq }
end

---------------------------------------------------------------------------
-- When it runs and when it draws
---------------------------------------------------------------------------
local users = {} -- id -> true: someone reads the arrow's state (a compass in a window)
function ns.SetArrowUser(id, on) users[tostring(id)] = on and true or nil if ns.ApplyArrowLook then ns.ApplyArrowLook() end end

local function Runs()
  if control and control.runs then return ns.Call(control.runs) and true or false end
  return (Look().arrow or next(users)) and true or false
end
ns.ArrowRuns = Runs
local function Ghost()
  if control and control.ghost then return ns.Call(control.ghost) and true or false end
  return not Look().arrow
end
ns.ArrowGhost = Ghost

function ns.SetArrowControl(id, ctl)
  control = type(ctl) == "table" and ctl or nil
  if control then control.id = tostring(id or "?") end
  if ns.ApplyArrowLook then ns.ApplyArrowLook() end
end
function ns.ArrowControl() return control end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- 0 far away .. 1 close
local function Nearness(dist)
  if not dist then return 0 end
  if dist <= NEAR then return 1 end
  if dist >= FAR then return 0 end
  return 1 - (dist - NEAR) / (FAR - NEAR)
end
ns.Nearness = Nearness

local function Pixel(frame)
  local ok, _, h = pcall(GetPhysicalScreenSize)
  local okS, scale = false, nil
  if type(frame) == "table" and frame.GetEffectiveScale then okS, scale = pcall(frame.GetEffectiveScale, frame) end
  h, scale = ok and tonumber(h), okS and tonumber(scale)
  if h and h > 0 and scale and scale > 0 then return 768 / h / scale end
  return 1
end

local function Color(c)
  if type(c) == "string" then c = Style.COLORS[c] end
  return type(c) == "table" and c or Style.COLORS.textPrimary
end

local function Font(parent, template, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  local c = Color(color)
  fs:SetTextColor(c[1], c[2], c[3], 1)
  return fs
end
ns.ArrowFont = Font

-- Plaque: dark blue plate with a 1 px golden line.
local function GoldPlate(frame)
  local GOLD = Style.BOOK.gold
  local plate = { border = {} }
  plate.bg = frame:CreateTexture(nil, "BACKGROUND")
  plate.bg:SetTexture(WHITE)
  plate.bg:SetAllPoints(frame)
  for i = 1, 4 do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(WHITE)
    plate.border[i] = t
  end
  function plate:Layout(px)
    px = px or Pixel(frame)
    local b = self.border
    for i = 1, 4 do b[i]:ClearAllPoints() end
    b[1]:SetPoint("TOPLEFT", frame, "TOPLEFT"); b[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT"); b[1]:SetHeight(px)
    b[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT"); b[2]:SetHeight(px)
    b[3]:SetPoint("TOPLEFT", frame, "TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT"); b[3]:SetWidth(px)
    b[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT"); b[4]:SetWidth(px)
  end
  function plate:SetAlpha(alpha)
    alpha = Clamp(alpha, 0, 1, Style.DEFAULT_ALPHA)
    self.alpha = alpha
    self.bg:SetVertexColor(NAVY[1], NAVY[2], NAVY[3], alpha)
    local a = 0.75 * math.min(1, alpha / Style.DEFAULT_ALPHA)
    for _, t in ipairs(self.border) do t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], a) end
  end
  -- no frame and no background: only the text stays
  function plate:SetPlain(plain)
    self.plain = plain and true or false
    if self.plain then self.bg:Hide() else self.bg:Show() end
    for _, t in ipairs(self.border) do if self.plain then t:Hide() else t:Show() end end
  end
  plate:Layout()
  plate:SetAlpha(Style.DEFAULT_ALPHA)
  return plate
end

-- What the arrow shows, for compasses in other windows (DonMapAPI.ArrowState). While the arrow runs but is a
-- "ghost" (a compass shows the way instead), it keeps working but draws nothing and takes no clicks.
function ns.ArrowStateRaw() return state end

local function Turn(self, angle)
  state.angle = angle
  self.icon:SetRotation(angle)
  self.glow:SetRotation(angle)
  self.shadow:SetRotation(angle)
end

local function ShowNeedle(self, shown, nearness)
  state.needle, state.nearness = shown and true or false, shown and (nearness or 0) or nil
  if shown and Ghost() then shown = false end
  if shown then
    local n = nearness or 0
    local v = 0.78 + 0.22 * n -- matte antique gold far away, full shine near
    self.icon:SetVertexColor(v, v, v * 0.96, 1)
    self.glow:SetAlpha(0.45 * n)
    self.icon:Show() self.glow:Show() self.shadow:Show()
  else
    self.icon:Hide() self.glow:Hide() self.shadow:Hide()
  end
end

local function ShowSeal(self, shown)
  state.seal = shown and true or false
  if shown and Ghost() then shown = false end
  if shown then
    if not self.seal:IsShown() then
      self.seal:Show() self.sealGlow:Show()
      if self.pulse then self.pulse:Play() end
    end
  elseif self.seal:IsShown() then
    if self.pulse then self.pulse:Stop() end
    self.seal:Hide() self.sealGlow:Hide()
  end
end

local function Scale()
  return Clamp(Look().arrowScale, Style.SCALE_MIN, Style.SCALE_MAX, 1.15)
end

local function SavePosition()
  local point, _, relPoint, x, y = arrow:GetPoint(1)
  if point then Look().arrowPos = { point, relPoint or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function DefaultPosition()
  arrow:ClearAllPoints()
  arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
end

local function ApplyPosition()
  local p = Look().arrowPos
  arrow:ClearAllPoints()
  if type(p) == "table" and type(p[1]) == "string" and pcall(arrow.SetPoint, arrow, p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0) then return end
  DefaultPosition()
end
ns.ApplyArrowPosition = function() if arrow then ApplyPosition() end end

function ns.ResetArrowPosition()
  Look().arrowPos = nil
  if arrow then DefaultPosition() end
end

-- Text plate: sized from the measured text (falls back to an estimate).
local function TextSize(fs)
  local t = fs:GetText()
  if t == nil or t == "" then return 0, 0 end
  local okW, w = pcall(fs.GetStringWidth, fs)
  local okH, h = pcall(fs.GetStringHeight, fs)
  w = okW and tonumber(w) or nil
  h = okH and tonumber(h) or nil
  local estimated = false
  if not w or w ~= w or w <= 0 then w = #(tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 estimated = true end
  if not h or h ~= h or h <= 0 then h = 12 estimated = true end
  return math.min(TEXT_W, math.ceil(w)), math.ceil(h), estimated
end

-- "240 yards, the way around" in its parts, in every language: the plain distance and the rest when the text starts
-- with it (and a separator follows); else the whole text and no way
function ns.SplitDistance(full, dist)
  if type(full) ~= "string" then return nil, nil end
  dist = dist or tonumber(full:match("%d+"))
  if not dist then return full, nil end
  local short = T("%d yards"):format(dist)
  if full == short then return short, nil end
  local rest = full:sub(#short + 1)
  if full:sub(1, #short) == short and (rest == "" or rest:find("^[%s,，、:：]")) then
    local way = rest:gsub("^[%s,，、:：]+", "")
    return short, way ~= "" and way or nil
  end
  return full, nil
end

local lastLabel, lastDist, lastDistColor
local function SetTexts(self, label, dist, distColor)
  label, dist = label or "", dist or ""
  state.label, state.distText, state.distColor = label, dist, distColor
  state.distShort, state.distWay = nil, nil -- set by the caller for "N yards, ..." only
  if Ghost() then label, dist = "", "" end
  if label == lastLabel and dist == lastDist and distColor == lastDistColor and not self.box.estimated then return end
  lastLabel, lastDist, lastDistColor = label, dist, distColor
  self.label:SetWidth(TEXT_W)
  self.dist:SetWidth(TEXT_W)
  self.label:SetText(label)
  self.dist:SetText(dist)
  -- distance in champagne gold, states in their status colour
  local c = Color((distColor == nil or distColor == "textSecondary") and Style.BOOK.goldLight or distColor)
  self.dist:SetTextColor(c[1], c[2], c[3], 1)
  local lw, lh, e1 = TextSize(self.label)
  local dw, dh, e2 = TextSize(self.dist)
  self.box.estimated = e1 or e2
  local hasLabel, hasDist = lw > 0, dw > 0
  if not (hasLabel or hasDist) then self.box:Hide() return end
  local S = Style.SPACING
  local w = math.max(lw, dw)
  self.label:SetWidth(w)
  self.dist:SetWidth(w)
  self.dist:ClearAllPoints()
  if hasLabel then
    self.dist:SetPoint("TOP", self.label, "BOTTOM", 0, -S.rowGap)
  else
    self.dist:SetPoint("TOP", self.box, "TOP", 0, -S.padY)
  end
  local h = S.padY * 2 + lh + dh + ((hasLabel and hasDist) and S.rowGap or 0)
  self.box:SetSize(w + 2 * S.padX, h)
  self.box.plate:Layout()
  self.box:Show()
end

-- DonMap's own view of a target: distance and bearing, "Arrived" (with a little room), "Other zone or no position".
-- A view = { mode = "needle" | "seal" | "text", label, text, color, dist, bearing (to the target, for compasses),
-- needleBearing (what the needle follows, default bearing), distShort, distWay }.
-- One table, filled anew at each update (33 times a second, no new table each time).
local pv = {}
local function View(mode, label, text, color, dist, bearing)
  pv.mode, pv.label, pv.text, pv.color, pv.dist, pv.bearing = mode, label, text, color, dist, bearing
  pv.needleBearing, pv.distShort, pv.distWay = nil, nil, nil
  return pv
end
local function PlainView(t)
  if not t.mapID then return View("text", t.label, "") end -- nothing to walk to: text only
  local dist, bearing = ns.DistanceTo(t.mapID, t.x, t.y)
  if not dist then return View("text", t.label, T("Other zone or no position"), "textHint") end
  local here = arrivedAt.mapID == t.mapID and arrivedAt.x == t.x and arrivedAt.y == t.y
  if dist < ARRIVED_YARDS or (here and dist < ARRIVED_LEAVE) then
    arrivedAt.mapID, arrivedAt.x, arrivedAt.y = t.mapID, t.x, t.y
    return View("seal", t.label, t.arrivedText or T("Arrived"), "good", dist, bearing)
  end
  local v = View("needle", t.label, T("%d yards"):format(dist), "textSecondary", dist, bearing)
  v.distShort = v.text
  return v
end
ns.PlainView = PlainView
-- the shared "arrived" memory, for views of other addons that want the same room (Questdon)
function ns.ArrivedAt() return arrivedAt end

local function Update(self)
  local t = Pick()
  state.t, state.dist, state.bearing, state.source, state.prio = t, nil, nil, currentSrc, currentPrio
  -- Without a target the frame is invisible: let clicks pass through to the world.
  local wantMouse = (Runs() and t) and true or false
  local mouse = wantMouse and not Ghost()
  if self.dmMouse ~= mouse then
    self.dmMouse = mouse
    self:EnableMouse(mouse)
  end
  if not wantMouse then ShowNeedle(self, false) ShowSeal(self, false) SetTexts(self, "", "") return end
  local view
  local fn = t.view or (control and control.view)
  if fn then view = fn(t) end
  if type(view) ~= "table" then view = PlainView(t) end
  state.dist, state.bearing = view.dist, view.bearing
  if view.mode == "seal" then
    ShowNeedle(self, false) ShowSeal(self, true)
  else
    ShowSeal(self, false)
  end
  SetTexts(self, view.label, view.text, view.color)
  state.distShort, state.distWay = view.distShort, view.distWay
  if view.mode ~= "needle" then
    if view.mode ~= "seal" then ShowNeedle(self, false) end
    return
  end
  local nb = view.needleBearing or view.bearing
  local facing = ns.Num(ns.Call(GetPlayerFacing))
  if facing and nb then
    -- facing: radians counter-clockwise from north; bearing: clockwise from north.
    -- Angle to turn (clockwise) = bearing + facing; SetRotation turns counter-clockwise.
    Turn(self, -(nb + facing))
    ShowNeedle(self, true, Nearness(view.dist))
  else
    ShowNeedle(self, false)
  end
end

local function Tooltip(self)
  local t = Pick()
  if not t then return end
  local lines = {}
  if t.mapID then
    local dist = state.dist or ns.DistanceTo(t.mapID, t.x, t.y)
    lines[1] = { T("Distance"), dist and T("%d yards"):format(dist) or T("Other zone or no position") }
  end
  if control and control.tooltip then ns.Call(control.tooltip, t, lines, currentSrc) end
  -- the right-click only when there is a clicked target to drop
  local hint = (currentPrio and currentPrio >= PRIO.click and currentSrc ~= "corpse") and T("Right-click: drop a clicked target.") or nil
  if not Look().arrowLocked then hint = hint and (hint .. " " .. T("Drag to move.")) or T("Drag to move.") end
  Style.Tooltip(self, t.label or T("Direction arrow"), lines, hint)
end

local function RightClick()
  local t, src, prio = Pick(), currentSrc, currentPrio
  if control and control.onRightClick then control.onRightClick(t, src, prio) end
  -- a clicked target of another addon (a guild member): dropped here; the controller drops its own
  if t and src and src ~= "corpse" and prio and prio >= PRIO.click and not (control and control.id == src)
      and targets[src] and targets[src].t == t then
    targets[src] = nil
  end
end

local function Create()
  if arrow then return arrow end
  Style = ns.Style
  arrow = CreateFrame("Button", "DonMapArrow", UIParent)
  arrow:SetSize(ICON, ICON)
  arrow:SetClampedToScreen(true)
  arrow:SetMovable(true)
  arrow:EnableMouse(true)
  arrow:RegisterForDrag("LeftButton")
  arrow:RegisterForClicks("RightButtonUp")
  arrow:SetScript("OnDragStart", function(self) if not Look().arrowLocked then self:StartMoving() end end)
  arrow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  arrow:SetScript("OnClick", function() ns.Safe("arrow", RightClick) end)
  arrow:SetScript("OnEnter", function(self) ns.Safe("arrow tooltip", Tooltip, self) end)
  arrow:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  ApplyPosition()

  -- needle with a soft dark shadow (readable on snow and sand) and a golden glow that grows as you get near; all
  -- three turn together. Artwork made with Gemini, own TGA files (from Questdon).
  arrow.shadow = arrow:CreateTexture(nil, "BACKGROUND")
  arrow.shadow:SetPoint("CENTER")
  arrow.shadow:SetSize(ICON * 1.7, ICON * 1.7) -- glow art: silhouette at 60 % of the texture
  arrow.shadow:SetTexture(MEDIA .. "ArrowNeedleGlow")
  arrow.shadow:SetVertexColor(0, 0, 0, 0.55)
  arrow.glow = arrow:CreateTexture(nil, "BORDER")
  arrow.glow:SetPoint("CENTER")
  arrow.glow:SetSize(ICON * 1.75, ICON * 1.75)
  arrow.glow:SetTexture(MEDIA .. "ArrowNeedleGlow")
  arrow.glow:SetVertexColor(1, 0.82, 0.45)
  arrow.glow:SetBlendMode("ADD")
  arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
  arrow.icon:SetAllPoints()
  arrow.icon:SetTexture(MEDIA .. "ArrowNeedle")

  -- arrived: golden seal with a slow pulsing glow
  arrow.sealGlow = arrow:CreateTexture(nil, "BORDER")
  arrow.sealGlow:SetPoint("CENTER")
  arrow.sealGlow:SetSize(ICON * 1.4, ICON * 1.4)
  arrow.sealGlow:SetTexture(MEDIA .. "ArrowSealGlow")
  arrow.sealGlow:SetVertexColor(1, 0.85, 0.5)
  arrow.sealGlow:SetBlendMode("ADD")
  arrow.seal = arrow:CreateTexture(nil, "ARTWORK")
  arrow.seal:SetPoint("CENTER")
  arrow.seal:SetSize(ICON * 0.8, ICON * 0.8)
  arrow.seal:SetTexture(MEDIA .. "ArrowSeal")
  if arrow.sealGlow.CreateAnimationGroup then
    local ok, group = pcall(arrow.sealGlow.CreateAnimationGroup, arrow.sealGlow)
    if ok and group then
      group:SetLooping("BOUNCE")
      local fade = group:CreateAnimation("Alpha")
      if fade then
        fade:SetFromAlpha(0.15)
        fade:SetToAlpha(0.55)
        fade:SetDuration(0.9)
        if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
      end
      arrow.pulse = group
    end
  end
  arrow.seal:Hide() arrow.sealGlow:Hide()
  arrow.icon:Hide() arrow.glow:Hide() arrow.shadow:Hide()

  -- text plaque below the arrow (own frame, no mouse: clicks go to the world)
  local S = Style.SPACING
  local box = CreateFrame("Frame", nil, arrow)
  box:SetPoint("TOP", arrow, "BOTTOM", 0, -S.rowGap * 2)
  box:EnableMouse(false)
  box.plate = GoldPlate(box)
  arrow.box = box

  arrow.label = Font(box, "GameFontHighlightSmall", Style.BOOK.textPrimary)
  arrow.label:SetPoint("TOP", box, "TOP", 0, -S.padY)
  arrow.label:SetJustifyH("CENTER")
  arrow.label:SetWordWrap(true)
  arrow.dist = Font(box, "GameFontNormal", Style.BOOK.goldLight)
  arrow.dist:SetJustifyH("CENTER")
  arrow.dist:SetPoint("TOP", arrow.label, "BOTTOM", 0, -S.rowGap)
  box:Hide()

  -- Throttled (33 times a second); the update itself runs protected. No closure or table per frame.
  local elapsed = 0
  local function UpdateArrow() Update(arrow) end
  arrow:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.03 then return end
    elapsed = 0
    ns.Safe("arrow", UpdateArrow)
  end)
  ns.ApplyArrowLook()
  return arrow
end
ns.CreateArrow = Create
function ns.ArrowFrame() return arrow end

-- size, plate opacity, plain, combat dimming, shown
function ns.ApplyArrowLook()
  if not arrow then return end
  local db = Look()
  -- the controller's settings once into DonMap's own (plan: "beim ersten Start aus QuestdonDB übernehmen"), so the
  -- arrow keeps its place and look when the controlling addon is switched off later
  if db ~= ns.db and type(DonMapDB) == "table" and ns.db == DonMapDB and not ns.db.arrowFrom and db.arrow ~= nil then
    for _, k in ipairs(ns.ARROW_KEYS) do
      local v = db[k]
      if type(v) == "table" then local c = {} for i, x in pairs(v) do c[i] = x end v = c end
      ns.db[k] = v
    end
    ns.db.arrowFrom = control and control.id or "?"
  end
  arrow:SetShown(Runs() and true or false)
  arrow:SetScale(Scale())
  arrow.box.plate:SetAlpha(db.arrowAlpha)
  arrow.box.plate:SetPlain(db.arrowPlain == true)
  Style.CombatFade(arrow, db.arrowCombatFade)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ns.Safe("arrow", Create)
  elseif event == "PLAYER_DEAD" then
    ns.ArrowDead(ns.PlayerPosition())
  elseif event == "PLAYER_UNGHOST" or (event == "PLAYER_ALIVE" and not True(ns.Call(UnitIsGhost, "player"))) then
    ns.ArrowAlive()
  end
end)
