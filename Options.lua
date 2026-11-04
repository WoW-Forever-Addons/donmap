local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (M2, 30.10.2026) DonMap's own options in Blizzard's settings (Esc > Options > AddOns > DonMap), through DonCore's
-- Settings: the direction arrow's window and look. Only while no addon controls the arrow: with Questdon its own
-- options page has the same settings (QuestdonDB), and a second page here would only be overwritten.
---------------------------------------------------------------------------
local category

local function Look() if ns.ApplyArrowLook then ns.ApplyArrowLook() end end

local function Status()
  local lines = { ("v%s"):format(ns.VERSION) }
  local n = 0
  for _ in ipairs(ns.order or {}) do n = n + 1 end
  lines[#lines + 1] = L["Sources: %d"]:format(n)
  return lines
end

local function Help()
  return L["/donmap <source>: switch a source on or off. /donmap diag: levels of the other addons' pins."] .. "\n"
    .. L["/donmap arrow: show or hide the arrow. /donmap options: its settings."]
end

local function Build()
  if category or ns.ArrowControl() then return end
  local S = ns.Style
  category = ns.BuildSettings({
    name = "DonMap",
    status = Status,
    help = Help, -- (01.11.2026) the commands on the Tools tab of DonCore's options window
    tools = {
      { "Reset position", "Reset", function() ns.ResetArrowPosition() end, "Puts the arrow back to its default place." },
    },
    pages = {
      { title = "Direction arrow", tip = "The arrow other addons point (a guild member, a guide step), and the way back to your corpse.",
        items = {
          { key = "arrow", name = "Show window", tip = "Arrow with the distance to the target an addon gave it. Drag to move, right click to drop a clicked target.", onChange = Look },
          { key = "arrowPlain", name = "No background and frame", tip = "Hides the plate behind the arrow's text and its frame: only the arrow and the writing stay.", parent = "arrow", onChange = Look },
          { key = "arrowLocked", name = "Lock window", tip = "The arrow can no longer be dragged.", parent = "arrow" },
          { key = "arrowScale", kind = "slider", name = "Size", tip = "Size of the direction arrow and its text.", min = S.SCALE_MIN, max = S.SCALE_MAX, step = 0.05, parent = "arrow", onChange = Look },
          { key = "arrowAlpha", kind = "slider", name = "Background opacity", tip = "Opacity of the plate behind the arrow's text.", min = 0, max = 1, step = 0.05, parent = "arrow", onChange = Look },
          { key = "arrowCombatFade", name = "Dim in combat", tip = "The arrow fades to 40 % while you fight.", parent = "arrow", onChange = Look },
          { key = "arrowCorpse", name = "Lead back to your corpse", tip = "Dead and released, the arrow points the way back to your corpse." },
        } },
    },
  })
end
ns.BuildOptions = Build

-- (01.11.2026, StyleKit 2 step 3) DonCore's options window of all Don addons (no Blizzard panel, so also in combat):
-- DonMap's tab, or while an addon controls the arrow that addon's options. Blizzard's settings only without that
-- window (an older DonCore), and those stay closed in combat.
function ns.OpenOptions()
  local ctl, Opt = ns.ArrowControl(), LibStub("DonCore-1.0"):Get("Options", 1)
  if ctl then
    if Opt and type(ctl.title) == "string" and Opt.addons[ctl.title] and Opt.Open(ctl.title) then return end
  elseif ns.OpenDonOptions and ns.OpenDonOptions() then
    return
  end
  if InCombatLockdown and InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return end
  if category and not ctl and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  else
    ns.Print(L["The arrow's settings are in %s's options."]:format(ctl and ctl.title or "?"))
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() ns.Safe("options", Build) end)
