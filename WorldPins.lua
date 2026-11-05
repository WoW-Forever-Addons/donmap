local _, ns = ...

---------------------------------------------------------------------------
-- Pins of the sources on the world map (from Guildon Map.lua, 25. to 27.10.2026): own buttons on the map's canvas, one
-- pool per source, reused by their place in the list. Points closer than the source's "group" distance (screen pixels)
-- become one pin (ns.Group). Sizes are screen pixels and the pins sit on whole pixels (Guildon 27.10.: half pixels
-- made the text outline uneven). A source with its own look passes newPin and paint (API.lua); otherwise DonMap draws
-- an icon in a colour with a short label.
---------------------------------------------------------------------------
ns.sources, ns.order = {}, {} -- id -> source, sources in the order they registered

local DEFAULT_ICON = "Interface\\Minimap\\ObjectIconsAtlas"
local WHITE_DOT = "Interface\\Buttons\\WHITE8x8"

-- Is a source drawn on "world" or "minimap"? Off when the player switched it off (/donmap), the source hid it
-- (src:SetShown) or its option says no (boolean or function).
function ns.Enabled(src, where)
  if (ns.db.off and ns.db.off[src.id]) or not src.shown[where] then return false end
  local v = src.opts[where]
  if type(v) == "function" then
    local ok, r = pcall(v)
    return ok and r and true or false
  end
  return v ~= false
end

-- size of one pin, of a group pin, and the grouping distance, all in screen pixels
function ns.Sizes(src, where)
  local o = src.opts
  local size, gsize, near
  if type(o.size) == "function" then size, gsize = o.size(where)
  elseif type(o.size) == "table" then size, gsize = o.size[where], o.size[where == "world" and "groupWorld" or "groupMinimap"]
  else size = o.size end
  size = tonumber(size) or (where == "world" and 16 or 12)
  gsize = tonumber(gsize) or size
  if type(o.group) == "function" then near = o.group(where)
  elseif type(o.group) == "table" then near = o.group[where]
  else near = o.group end
  return size, gsize, tonumber(near) or 0
end

-- Items { pt, i, x, y, key } in pixels; items closer than "near" become one group at their middle. Sorted by key first
-- (a source gives a name or id), so the same points always make the same groups. Each group: { x, y, members = { pt } }.
-- (31.10.2026, Runde 6) No new tables while the player walks: every source keeps a buffer per place ("world",
-- "minimap") with its item and group tables, which every draw overwrites. Group k always belongs to pin k, so
-- pin.points (= the group's members) is the pin's own table and shows what the pin shows.
local function ByKey(a, b)
  if a.key ~= b.key then return a.key < b.key end
  return a.i < b.i
end

-- the empty buffer of a source for one place, before a draw
function ns.Buffer(src, where)
  local all = src.buf
  if not all then all = {} src.buf = all end
  local buf = all[where]
  if not buf then
    buf = { pool = {}, items = {}, n = 0, used = 0, groups = {}, ng = 0 }
    all[where] = buf
  end
  buf.n = 0
  return buf
end

-- one item into the buffer
function ns.AddItem(buf, pt, i, x, y)
  local n = buf.n + 1
  buf.n = n
  local it = buf.pool[n]
  if not it then it = {} buf.pool[n] = it end
  local k = pt.key or pt.label or ""
  if type(k) ~= "string" then -- a number key as text once per point, not every draw
    if pt._dmKeyOf ~= k then pt._dmKey, pt._dmKeyOf = tostring(k), k end
    k = pt._dmKey
  end
  it.pt, it.i, it.x, it.y, it.key = pt, i, x, y, k
  buf.items[n] = it
end

-- groups the buffer's items; returns the groups (reused tables) and their number
function ns.Group(buf, near)
  local items, n = buf.items, buf.n
  for k = #items, n + 1, -1 do items[k] = nil end
  for k = n + 1, buf.used do buf.pool[k].pt = nil end -- no hold on points that left
  buf.used = n
  table.sort(items, ByKey)
  local groups, ng = buf.groups, 0
  local n2 = near > 0 and near * near or -1
  for idx = 1, n do
    local it = items[idx]
    local hit
    if n2 > 0 then
      for gi = 1, ng do
        local g = groups[gi]
        if (g.x - it.x) ^ 2 + (g.y - it.y) ^ 2 <= n2 then hit = g break end
      end
    end
    if hit then
      local m = hit.members
      local c = #m + 1
      m[c] = it.pt
      hit.x, hit.y = hit.x + (it.x - hit.x) / c, hit.y + (it.y - hit.y) / c
    else
      ng = ng + 1
      local g = groups[ng]
      if not g then g = { members = {} } groups[ng] = g end
      local m = g.members
      for k = #m, 2, -1 do m[k] = nil end
      m[1] = it.pt
      g.x, g.y = it.x, it.y
    end
  end
  for gi = ng + 1, buf.ng do -- groups no longer drawn let their points go (their pins are hidden)
    local m = groups[gi].members
    for k = #m, 1, -1 do m[k] = nil end
  end
  buf.ng = ng
  return groups, ng
end

---------------------------------------------------------------------------
-- Pins: the source's own (opts.newPin, opts.paint) or DonMap's plain one
---------------------------------------------------------------------------
local function PlainTooltip(self)
  local src, pts = self.source, self.points
  if not (src and pts and GameTooltip) then return end
  if src.opts.tooltip then ns.Safe(src.id .. " tooltip", src.opts.tooltip, self, pts) return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(src.title)
  for _, pt in ipairs(pts) do
    if pt.label then GameTooltip:AddLine(tostring(pt.label), 1, 1, 1) end
  end
  GameTooltip:Show()
end

local function PlainPin(src, parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, 2)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnEnter", PlainTooltip)
  b:SetScript("OnLeave", function(self)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  b:SetScript("OnClick", function(self, button)
    if src.opts.onClick and self.points then ns.Safe(src.id .. " click", src.opts.onClick, self, button, self.points) end
  end)
  return b
end

local function PlainPaint(b, points, size, gsize)
  local one = points[1]
  local n = #points
  b:SetSize(n == 1 and size or gsize, n == 1 and size or gsize)
  b.icon:SetTexture(one.icon or (one.color and WHITE_DOT) or DEFAULT_ICON)
  local c = one.color
  if type(c) == "table" then b.icon:SetVertexColor(c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1) else b.icon:SetVertexColor(1, 1, 1) end
  b.label:SetText(n > 1 and (n .. "x") or (one.label and tostring(one.label)) or "")
end

function ns.NewPin(src, parent, size, where)
  local b
  if src.opts.newPin then b = src.opts.newPin(parent, size, where) else b = PlainPin(src, parent, size) end
  b.source = src
  return b
end

function ns.Paint(src, b, members, size, gsize, where)
  b.points = members
  if src.opts.paint then src.opts.paint(b, members, size, gsize, where) else PlainPaint(b, members, size, gsize) end
end

function ns.HideFrom(pins, n)
  for i = n + 1, #pins do pins[i]:Hide() end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local function Canvas()
  local f = WorldMapFrame
  local sc = f and f.ScrollContainer
  return sc and sc.Child, sc
end

-- whole screen pixels: the canvas is drawn at "scale", so a size or place of k / scale is k pixels on the screen
local function Px(v, scale) return math.floor(v * scale + 0.5) / scale end

-- Draws a source on the open world map. Without force only when the map, its size, zoom, the sizes or the points changed.
-- Returns the number of pins.
function ns.DrawWorld(src, force)
  local pins = src.pins.world
  local wm = WorldMapFrame
  local canvas, sc = Canvas()
  if not canvas or not (wm.IsShown and wm:IsShown()) or not ns.Enabled(src, "world") then
    ns.HideFrom(pins, 0)
    src.n.world, src.view.world, src.view.worldPts = 0, nil, nil
    return 0
  end
  local map = ns.Num(ns.Call(wm.GetMapID, wm))
  local w, h = ns.Num(ns.Ask(canvas, "GetWidth")) or 0, ns.Num(ns.Ask(canvas, "GetHeight")) or 0
  local scale = math.max(0.2, sc and sc.GetCanvasScale and ns.Num(ns.Call(sc.GetCanvasScale, sc)) or 1)
  local size, gsize, near = ns.Sizes(src, "world")
  local lv = ns.Num(ns.Ask(canvas, "GetFrameLevel"))
  local topLv = src.opts.top and ns.TopWorldLevel() or nil
  -- (M3) the points' signature apart: a long list made a new long string every 0.1 s while the map was open
  -- (31.10.2026, D18) the view in numbers on src.view: no table and no string every 0.1 s
  local v, vmap, vlv = src.view, map or 0, (lv or -1) + (topLv or 0) * 100000
  if not force and v.world and v.worldPts == src.sig and v.wmap == vmap and v.ww == w and v.wh == h and v.wsc == scale
      and v.wz == size and v.wg == gsize and v.wnear == near and v.wlv == vlv then
    return src.n.world
  end
  v.world, v.worldPts = true, src.sig
  v.wmap, v.ww, v.wh, v.wsc, v.wz, v.wg, v.wnear, v.wlv = vmap, w, h, scale, size, gsize, near, vlv
  local sizeW, sizeG = Px(size / scale, scale), Px(gsize / scale, scale)
  local n, onMap = 0, 0
  if map and w > 0 then
    local buf = ns.Buffer(src, "world")
    for i, pt in ipairs(src.points) do
      if pt.world ~= false and (not pt.only or pt.mapID == map) then -- (M3) only: not on the maps above
        local x, y = ns.PosOnMap(pt.mapID, pt.x, pt.y, map)
        if x then ns.AddItem(buf, pt, i, x * w, y * h) end
      end
    end
    onMap = buf.n
    local level = ns.WorldLevel(ns.Layer(src), lv)
    if topLv and topLv > level then level = topLv end
    local groups, ng = ns.Group(buf, near / scale)
    for gi = 1, ng do
      local g = groups[gi]
      n = n + 1
      local b = pins[n] or ns.NewPin(src, canvas, sizeW, "world")
      pins[n] = b
      if lv then ns.SetLevel(b, level) end
      ns.Paint(src, b, g.members, sizeW, sizeG, "world")
      b:ClearAllPoints()
      b:SetPoint("CENTER", canvas, "TOPLEFT", Px(g.x, scale), -Px(g.y, scale))
      b:Show()
    end
  end
  ns.HideFrom(pins, n)
  src.n.world = n
  local info = src.info.world or {}
  info.map, info.w, info.h, info.scale, info.have, info.onMap, info.pins, info.canvasLevel = map, w, h, scale, #src.points, onMap, n, lv
  src.info.world = info
  return n
end
