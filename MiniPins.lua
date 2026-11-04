local _, ns = ...

---------------------------------------------------------------------------
-- Points of the sources on the minimap (geometry from Questdon Minimap.lua 1.22, pins as in Guildon Map.lua): own
-- buttons parented to the minimap, which is only read (size, zoom, shape). The player's world position is the middle;
-- a point on the same continent sits at its distance in yards, scaled by the view radius, turned with the player when the
-- minimap rotates. Caves and buildings with their own small map use the zone around them (ns.PlayerWorld).
---------------------------------------------------------------------------
local MARGIN = 4 -- pixels kept free at the minimap's edge

-- Minimap view in yards (diameter) per zoom level 0-5, used only when the client has no C_Minimap.GetViewRadius.
local DIAMETER = {
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

-- Radius of the minimap view in yards; second value: where it comes from.
function ns.MinimapRadius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local r = ns.Num(ns.Call(C_Minimap.GetViewRadius))
    if r and r > 0 then return r, "client" end
  end
  local zoom = Minimap and ns.Num(ns.Call(Minimap.GetZoom, Minimap)) or 0
  zoom = math.max(0, math.min(5, math.floor(zoom)))
  local indoors = IsIndoors and ns.Call(IsIndoors) == true or false
  return DIAMETER[indoors and "indoor" or "outdoor"][zoom] / 2, "zoom"
end

-- (Questdon 1.22) Does the minimap rotate? A secret answer keeps the last readable one, else the minimap's compass ring
-- tells; second value: where the answer comes from.
local rotateCache
local function ReadRotateCVar()
  if C_CVar and C_CVar.GetCVarBool then
    local v = ns.Call(C_CVar.GetCVarBool, "rotateMinimap")
    if type(v) == "boolean" and ns.Usable(v) then return v end
  end
  local v = ns.Call((C_CVar and C_CVar.GetCVar) or GetCVar, "rotateMinimap")
  if v == nil or not ns.Usable(v) then return nil end
  return v == "1" or v == 1 or v == true
end
function ns.MinimapRotating()
  local v = ReadRotateCVar()
  if v ~= nil then rotateCache = v return v, "cvar" end
  if rotateCache ~= nil then return rotateCache, "cached" end
  local compass = MinimapCompassTexture
  if type(compass) == "table" and compass.IsShown then
    local ok, shown = pcall(compass.IsShown, compass)
    if ok and type(shown) == "boolean" and ns.Usable(shown) then return shown, "compass" end
  end
  return false, "unknown"
end

-- radians counter-clockwise from north while the minimap rotates, else nil
function ns.MinimapFacing()
  if not ns.MinimapRotating() then return nil end
  return ns.Num(ns.Call(GetPlayerFacing))
end

-- Offset in pixels from the minimap centre for a target (dNorth, dEast in yards from the player): x to the right, y up.
function ns.MinimapOffset(dNorth, dEast, radius, halfSize, facing)
  local x, y = dEast, dNorth
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    x, y = dEast * c + dNorth * s, -dEast * s + dNorth * c
  end
  local k = halfSize / radius
  return x * k, y * k
end

-- Inside the visible minimap? Round unless an addon says the minimap is square.
-- (02.11.2026) EllesmereUI makes the minimap square without GetMinimapShape. Its own reading counts first
-- (EllesmereUI._ModuleNS.EllesmereUIMinimap.MinimapShape: "circle", "textured_circle", "square", "rectangular").
-- A crop (rectangular 4:3, a square frame's title bar) keeps the square canvas and masks a strip off the top and the
-- bottom; EUI sets the minimap's hit rect to the visible part, so its top inset is that strip: "SQUARE:<px>".
-- Questdon hands the same strings through opts.view (Questdon/Minimap.lua).
-- (02.11.2026) GetMinimapShape's mixed shapes (SexyMap and others; the table as in LibDBIcon): per quarter round (true)
-- or square, quarters 1 right below, 2 left below, 3 right above, 4 left above.
local QUARTERS = {
  ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
local cropOf = { SQUARE = 0 }
local function Crop(shape)
  local c = cropOf[shape]
  if c == nil then
    c = type(shape) == "string" and tonumber(shape:match("^SQUARE:(%d+)$")) or false
    cropOf[shape] = c
  end
  return c
end
local function EllesmereShape()
  local eui = type(EllesmereUI) == "table" and type(EllesmereUI._ModuleNS) == "table"
    and EllesmereUI._ModuleNS.EllesmereUIMinimap
  local s = type(eui) == "table" and ns.Call(eui.MinimapShape)
  if type(s) ~= "string" then return nil end
  if s == "circle" or s == "textured_circle" then return "ROUND" end
  local _, _, top = ns.Call(Minimap and Minimap.GetHitRectInsets, Minimap)
  top = ns.Num(top) and math.floor(top + 0.5) or 0
  return top > 0 and "SQUARE:" .. top or "SQUARE"
end
function ns.MinimapShape()
  local e = EllesmereShape()
  if e then return e end
  local s = ns.Call(GetMinimapShape)
  return type(s) == "string" and s or "ROUND"
end
function ns.OnMinimap(x, y, halfSize, margin, shape)
  local r = halfSize - (margin or 0)
  shape = shape or ns.MinimapShape()
  local crop = Crop(shape)
  if crop then return math.abs(x) <= r and math.abs(y) <= r - crop end
  local q = QUARTERS[shape]
  if q and not q[(x < 0 and 2 or 1) + (y > 0 and 2 or 0)] then return math.abs(x) <= r and math.abs(y) <= r end
  return x * x + y * y <= r * r
end

local function Off(src)
  ns.HideFrom(src.pins.minimap, 0)
  src.n.minimap, src.view.minimap, src.view.miniPts = 0, nil, nil
  return 0
end

-- Draws a source on the minimap. Without force only when the player moved or turned, the zoom, the sizes or the points
-- changed. Returns the number of pins.
function ns.DrawMini(src, force)
  if src.opts.sticky then return ns.DrawMiniSticky(src, force) end
  local pins = src.pins.minimap
  local mm = Minimap
  if not mm or not ns.Enabled(src, "minimap") or (mm.IsVisible and not mm:IsVisible()) then return Off(src) end
  local c0, n0, w0 = ns.PlayerWorld()
  if not c0 then return Off(src) end
  local radius = ns.MinimapRadius()
  local half = (ns.Num(ns.Ask(mm, "GetWidth")) or 140) / 2
  local facing = ns.MinimapFacing()
  local shape = ns.MinimapShape()
  local size, gsize, near = ns.Sizes(src, "minimap")
  local mlv = ns.Num(ns.Ask(mm, "GetFrameLevel")) or -1
  -- (31.10.2026, D18) the last view in numbers on src.view, as DrawMiniSticky does: no table and no string every 0.1 s
  local qn, qw, qf = math.floor(n0 * 10), math.floor(w0 * 10), facing and math.floor(facing * 100) or false
  local v = src.view
  if not force and v.minimap and v.miniPts == src.sig and v.mc == c0 and v.mn == qn and v.mw == qw and v.mf == qf
      and v.mr == radius and v.mh == half and v.ms == shape and v.mz == size and v.mg == gsize and v.mnear == near
      and v.mlv == mlv then
    return src.n.minimap
  end
  v.minimap, v.miniPts = true, src.sig
  v.mc, v.mn, v.mw, v.mf, v.mr, v.mh, v.ms, v.mz, v.mg, v.mnear, v.mlv = c0, qn, qw, qf, radius, half, shape, size, gsize, near, mlv
  if mlv < 0 then mlv = nil end
  local buf = ns.Buffer(src, "minimap") -- (31.10.2026, Runde 6) reused tables, WorldPins.lua ns.Group
  for i, pt in ipairs(src.points) do
    if pt.minimap ~= false then
      local c, pn, pw = ns.WorldPos(pt.mapID, pt.x, pt.y)
      if c == c0 then
        local x, y = ns.MinimapOffset(pn - n0, -(pw - w0), radius, half, facing)
        if ns.OnMinimap(x, y, half, MARGIN, shape) then ns.AddItem(buf, pt, i, x, y) end
      end
    end
  end
  local sizeM, sizeMG = math.floor(size + 0.5), math.floor(gsize + 0.5)
  local level = mlv and ns.MiniLevel(ns.Layer(src), mlv)
  local n = 0
  local groups, ng = ns.Group(buf, near)
  for gi = 1, ng do
    local g = groups[gi]
    n = n + 1
    local b = pins[n] or ns.NewPin(src, mm, sizeM, "minimap")
    pins[n] = b
    if level then ns.SetLevel(b, level) end
    ns.Paint(src, b, g.members, sizeM, sizeMG, "minimap")
    b:ClearAllPoints()
    b:SetPoint("CENTER", mm, "CENTER", math.floor(g.x + 0.5), math.floor(g.y + 0.5))
    b:Show()
  end
  ns.HideFrom(pins, n)
  src.n.minimap = n
  local info = src.info.minimap or {}
  info.radius, info.half, info.facing, info.shape, info.have, info.near, info.pins = radius, half, facing, shape, #src.points, buf.n, n
  src.info.minimap = info
  return n
end

---------------------------------------------------------------------------
-- (M3, 30.10.2026) Sticky sources (opts.sticky; Questdon's minimap pins, from Questdon Minimap.lua 1.22 and 1.3.5): the
-- source groups its points itself and DonMap only places them. Every point keeps its button while it stays in view
-- (point.button; a button handed out by place in the list re-dressed all after one that left the view and could swap
-- the pin under the mouse). A point may bring its world position (wc, wn, ww: continent, yards north, yards west),
-- else it is worked out once from mapID, x, y and kept on the point. The pins are not put on whole pixels. hide = true leaves a point out (a member of a
-- bundle), range = yards draws it only that close. No table is made while the player walks: the last view is kept
-- in numbers and the buttons of the points that left are given back.
--   opts.view() -> c, n, w, radius, half, facing, shape   the source reads the minimap itself (nil: nothing shown)
--   opts.dress(button, point, size)                      a point got a button (newPin makes new ones)
--   opts.place(button, point, dNorth, dEast)             every time the point is placed
--   opts.release(button, point)                          the point gave its button back
--   opts.rebundle(k, radius)                             new points or another zoom (k = pixels per yard): every
--                                                        button is given back first, so all are dressed anew
--   opts.max                                             at most this many pins (the first in the list)
--   opts.miniLevel                                       levels above the minimap (else by the layer, Layers.lua)
--   opts.clock = false                                   DonMap's clock leaves the source alone: it calls
--                                                        src:Refresh("minimap") itself
---------------------------------------------------------------------------
local function StickyState(src)
  local st = src.sticky
  if not st then
    st = { free = {}, held = {}, spare = {}, round = 0, dirty = true, last = {} }
    src.sticky = st
  end
  return st
end

local function GiveBack(src, st, pt)
  local b = pt.button
  if not b then return end
  b:Hide()
  b.point, pt.button = nil, nil
  st.free[#st.free + 1] = b
  if src.opts.release then src.opts.release(b, pt) end
end

-- every button back (src:Release, a new bundling, nothing to show); the next draw places all anew
function ns.ReleaseSticky(src)
  local st = StickyState(src)
  for _, list in ipairs({ st.held, st.spare }) do -- spare: a draw that stopped on an error left its points there
    for i = #list, 1, -1 do
      GiveBack(src, st, list[i])
      list[i] = nil
    end
  end
  st.dirty = true
end

local function StickyOff(src)
  ns.ReleaseSticky(src)
  src.n.minimap = 0
  return 0, false
end

-- the point's world position, worked out once
local function PointWorld(pt)
  if pt.wc then return pt.wc, pt.wn, pt.ww end
  if pt._dmM ~= pt.mapID or pt._dmX ~= pt.x or pt._dmY ~= pt.y then
    pt._dmC, pt._dmN, pt._dmW = ns.WorldPos(pt.mapID, pt.x, pt.y)
    pt._dmM, pt._dmX, pt._dmY = pt.mapID, pt.x, pt.y
  end
  return pt._dmC, pt._dmN, pt._dmW
end

local function DefaultView()
  local c0, n0, w0 = ns.PlayerWorld()
  if not c0 then return nil end
  local facing
  if ns.MinimapRotating() then
    facing = ns.Num(ns.Call(GetPlayerFacing))
    if not facing then return nil end -- turning, but the facing is secret: cannot place them right
  end
  local half = (ns.Num(ns.Ask(Minimap, "GetWidth")) or 0) / 2
  return c0, n0, w0, ns.MinimapRadius(), half, facing, ns.MinimapShape()
end

-- Draws a sticky source. Without force only when the view, the points or the sizes changed. Returns the number of pins
-- and whether it placed them.
function ns.DrawMiniSticky(src, force)
  local mm = Minimap
  if not mm or not ns.Enabled(src, "minimap") then return StickyOff(src) end
  local st = StickyState(src)
  if force then st.dirty = true end
  local o = src.opts
  local c0, n0, w0, radius, half, facing, shape
  if o.view then c0, n0, w0, radius, half, facing, shape = o.view() else c0, n0, w0, radius, half, facing, shape = DefaultView() end
  if not (c0 and n0 and w0 and radius and radius > 0 and half and half > 0) then return StickyOff(src) end
  shape = shape or "ROUND"
  local size = ns.Sizes(src, "minimap")
  local mlv = ns.Num(ns.Ask(mm, "GetFrameLevel"))
  local L = st.last
  if not st.dirty and st.points == src.points and st.sig == src.sig and L.c == c0 and L.n == n0 and L.w == w0
      and L.f == facing and L.r == radius and L.h == half and L.s == shape and L.size == size and L.lv == mlv then
    return src.n.minimap, false
  end
  L.c, L.n, L.w, L.f, L.r, L.h, L.s, L.size, L.lv = c0, n0, w0, facing, radius, half, shape, size, mlv
  st.dirty = true -- until the draw ends: an error in a callback below draws all anew next time
  local k = half / radius
  if st.points ~= src.points or st.sig ~= src.sig or st.k ~= k then
    if o.rebundle then
      ns.ReleaseSticky(src)
      o.rebundle(k, radius)
    end
    st.points, st.sig, st.k = src.points, src.sig, k
  end
  local max = tonumber(o.max) or math.huge
  local reach2 = (radius * 1.5) ^ 2 -- cheap cut before the rotation: farther than the view's corner (square minimap)
  -- opts.miniLevel: levels above the minimap (Questdon 6, above GatherMate as before), else by the layer
  local level = mlv and (tonumber(o.miniLevel) and mlv + o.miniLevel or ns.MiniLevel(ns.Layer(src), mlv))
  local sizeM = math.floor(size + 0.5)
  st.round = st.round + 1
  local round, held, nh, n = st.round, st.spare, 0, 0
  for i = #held, 1, -1 do GiveBack(src, st, held[i]) held[i] = nil end -- left by a draw that stopped on an error
  local all = src.pins.minimap
  for _, pt in ipairs(src.points) do
    if n >= max then break end
    if not pt.hide and pt.minimap ~= false then
      local c, pn, pw = PointWorld(pt)
      if c == c0 then
        local dn, de = pn - n0, -(pw - w0)
        local d2 = dn * dn + de * de
        if d2 <= reach2 and (not pt.range or d2 <= pt.range * pt.range) then
          local x, y = ns.MinimapOffset(dn, de, radius, half, facing)
          if ns.OnMinimap(x, y, half, MARGIN, shape) then
            n = n + 1
            local b = pt.button
            if not b then
              b = table.remove(st.free)
              if not b then
                b = ns.NewPin(src, mm, sizeM, "minimap")
                all[#all + 1] = b
              end
              pt.button, b.point = b, pt
              if o.dress then o.dress(b, pt, sizeM) end
            end
            if level then ns.SetLevel(b, level) end
            if o.place then o.place(b, pt, dn, de) end
            b:ClearAllPoints()
            b:SetPoint("CENTER", mm, "CENTER", x, y) -- not on whole pixels: a pin glides while you walk (Questdon)
            b:Show()
            pt._dmRound = round
            nh = nh + 1
            held[nh] = pt
          end
        end
      end
    end
  end
  -- the points that left the view (or the list) give their buttons back
  local old = st.held
  for i = #old, 1, -1 do
    local pt = old[i]
    if pt._dmRound ~= round then GiveBack(src, st, pt) end
    old[i] = nil
  end
  st.held, st.spare = held, old
  st.dirty = false
  src.n.minimap = n
  local info = src.info.minimap or {}
  info.radius, info.half, info.facing, info.shape, info.have, info.pins = radius, half, facing, shape, #src.points, n
  src.info.minimap = info
  return n, true
end
