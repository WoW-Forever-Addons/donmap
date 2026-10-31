local _, ns = ...

---------------------------------------------------------------------------
-- (M2, 30.10.2026) From Questdon's Compass.lua, the same but for the media path: DonMapAPI.NewCompass.
-- (1.3.6, Daniel 12.10.: "the arrow built into the window") A small round compass for our own
-- windows: the golden ring of the quest book, the compass rose of the arrow's seal as the dial
-- (it turns with you, its north is the world's north), the arrow's golden needle on top. Arrived:
-- the needle goes, the rose shines. Own textures only (Media), no Blizzard frames.
--   local c = DonMapAPI.NewCompass(parent, size)
--   c:Point(bearing, facing, nearness)   bearing: radians clockwise from north (nil: no direction)
--   c:Arrived(true|false)
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\DonMap\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local Methods = {}

local function Rotate(tex, angle)
  if tex and tex.SetRotation and type(angle) == "number" and angle == angle then pcall(tex.SetRotation, tex, angle) end
end

-- facing: radians counter-clockwise from north (GetPlayerFacing); bearing: clockwise from north.
-- On the screen "up" is where you look: the target is (bearing + facing) clockwise from up, the
-- world's north is facing clockwise from up. SetRotation turns counter-clockwise.
function Methods:Point(bearing, facing, nearness)
  self._bearing, self._facing = bearing, facing
  if type(facing) == "number" then
    Rotate(self.rose, -facing)
    local r = self._size * 0.5 - 7
    if self.north and self.north.SetPoint then
      self.north:ClearAllPoints()
      self.north:SetPoint("CENTER", self, "CENTER", math.sin(facing) * r, math.cos(facing) * r)
      self.north:Show()
    end
  elseif self.north then
    self.north:Hide()
  end
  if type(bearing) == "number" and type(facing) == "number" and not self._arrived then
    Rotate(self.needle, -(bearing + facing))
    Rotate(self.glow, -(bearing + facing))
    self.needle:Show()
    local n = math.max(0, math.min(1, tonumber(nearness) or 0))
    self.glow:SetAlpha(0.15 + 0.6 * n)
    self.glow:Show()
  else
    self.needle:Hide()
    self.glow:Hide()
  end
  return self
end

function Methods:Arrived(on)
  on = on and true or false
  if self._arrived == on then return self end
  self._arrived = on
  self.rose:SetAlpha(on and 1 or 0.38)
  if on then self.needle:Hide() self.glow:Hide() end
  if self.pulse then
    if on then pcall(self.pulse.Play, self.pulse) else pcall(self.pulse.Stop, self.pulse) end
  end
  self.shine:SetShown(on)
  return self
end

function ns.NewCompass(parent, size)
  size = size or 56
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f._size = size
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetPoint("CENTER")
  f.bg:SetSize(size * 0.9, size * 0.9)
  f.bg:SetTexture(WHITE)
  f.bg:SetVertexColor(0.06, 0.07, 0.17, 0.96)
  if f.CreateMaskTexture then
    local ok, m = pcall(f.CreateMaskTexture, f)
    if ok and m then
      m:SetAllPoints(f.bg)
      pcall(m.SetTexture, m, MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      if f.bg.AddMaskTexture then pcall(f.bg.AddMaskTexture, f.bg, m) end
    end
  end
  -- the dial: the seal's compass rose, faint, turning with you
  f.rose = f:CreateTexture(nil, "BORDER")
  f.rose:SetPoint("CENTER")
  f.rose:SetSize(size * 0.92, size * 0.92)
  f.rose:SetTexture(MEDIA .. "ArrowSeal")
  f.rose:SetAlpha(0.38)
  f.shine = f:CreateTexture(nil, "ARTWORK")
  f.shine:SetPoint("CENTER")
  f.shine:SetSize(size * 1.25, size * 1.25)
  f.shine:SetTexture(MEDIA .. "ArrowSealGlow")
  f.shine:SetVertexColor(1, 0.85, 0.5)
  f.shine:SetBlendMode("ADD")
  f.shine:Hide()
  if f.shine.CreateAnimationGroup then
    local ok, group = pcall(f.shine.CreateAnimationGroup, f.shine)
    if ok and group then
      group:SetLooping("BOUNCE")
      local fade = group:CreateAnimation("Alpha")
      if fade then
        fade:SetFromAlpha(0.15)
        fade:SetToAlpha(0.6)
        fade:SetDuration(0.9)
        if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
      end
      f.pulse = group
    end
  end
  -- the golden ring of the quest book
  f.ring = f:CreateTexture(nil, "ARTWORK")
  f.ring:SetAllPoints()
  f.ring:SetTexture(MEDIA .. "BookRing")
  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetPoint("CENTER")
  f.glow:SetSize(size * 1.3, size * 1.3)
  f.glow:SetTexture(MEDIA .. "ArrowNeedleGlow")
  f.glow:SetVertexColor(1, 0.82, 0.45)
  f.glow:SetBlendMode("ADD")
  f.glow:Hide()
  f.needle = f:CreateTexture(nil, "OVERLAY")
  f.needle:SetPoint("CENTER")
  f.needle:SetSize(size * 0.86, size * 0.86)
  f.needle:SetTexture(MEDIA .. "ArrowNeedle")
  f.needle:Hide()
  f.north = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if f.north and f.north.SetTextColor then f.north:SetTextColor(0.97, 0.87, 0.60, 1) end
  if f.north then
    if f.north.SetFont then pcall(function() local p = f.north:GetFont() if p then f.north:SetFont(p, 8, "OUTLINE") end end) end
    f.north:SetText(ns.L["N"]) -- (review 4) north in the client's language
    f.north:Hide()
  end
  for k, fn in pairs(Methods) do f[k] = fn end
  f._arrived = nil
  f:Arrived(false)
  return f
end
