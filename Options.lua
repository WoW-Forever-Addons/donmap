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

local function Build()
  if category or ns.ArrowControl() then return end
  local S = ns.Style
  category = ns.BuildSettings({
    name = "DonMap",
    status = Status,
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

function ns.OpenOptions()
  if InCombatLockdown and InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return end
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  else
    ns.Print(L["The arrow's settings are in %s's options."]:format(ns.ArrowControl() and ns.ArrowControl().title or "?"))
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() ns.Safe("options", Build) end)
