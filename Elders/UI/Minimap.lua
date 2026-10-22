-- Minimap button (left: panel, right: settings, drag: move) and the native Settings category.

local ADDON, ns = ...
local MK = MetaKit
local UI = ns.UI
local A = ns.A

local M = A:NewModule("Minimap")
local button

-- Settings keys are flat; "minimapHide" lives in config.minimap.hide, the rest straight in config.
local function settingsProxy()
  local cfg = A.db.config
  return setmetatable({}, {
    __index = function(_, k)
      if k == "minimapHide" then return cfg.minimap.hide and true or false end
      return cfg[k]
    end,
    __newindex = function(_, k, v)
      if k == "minimapHide" then
        cfg.minimap.hide = v and true or false
        if button then button:SetShown(not cfg.minimap.hide) end
      else
        cfg[k] = v
      end
    end,
  })
end

local function setupSettings()
  if not (MK.UI and MK.UI.Settings) then return end
  local ok, cat = pcall(MK.UI.Settings, { name = "Elders", db = settingsProxy(), options = {
    { type = "header", label = "The Elders" },
    { type = "check", key = "ritual", label = "Ask about each level bracket", tooltip = "Show the Elders' questions every ten levels." },
    { type = "check", key = "toasts", label = "Show level toasts", tooltip = "Short notes on level-ups and sealed brackets." },
    { type = "check", key = "minimapHide", label = "Hide the minimap button" },
    { type = "header", label = "Troubleshooting" },
    { type = "check", key = "debug", label = "Print debug messages" },
  } })
  if not ok then A:Debug("settings failed: " .. tostring(cat)); return end
  UI.settingsOpener = function()
    if not (Settings and Settings.OpenToCategory) then return A:Print("Settings are not available on this client.") end
    local id = cat
    if type(cat) == "table" then id = (cat.GetID and cat:GetID()) or cat.ID or cat end
    if not pcall(Settings.OpenToCategory, id) then A:Print("Open the Elders page from Game Menu > Options > AddOns.") end
  end
end

local function tooltip(tt)
  tt:AddLine("|cff3fbf6aElders|r")
  local xph, gph = UI.Quick(UI.CurrentTab())
  tt:AddDoubleLine("XP per hour", xph)
  tt:AddDoubleLine("Gold per hour", gph)
  local n = A:PendingCount() or 0
  tt:AddDoubleLine("Waiting to sync", tostring(n))
  tt:AddLine("Left-click: stats panel", 0.7, 0.7, 0.7)
  tt:AddLine("Right-click: settings", 0.7, 0.7, 0.7)
end

function M:OnLogin()
  local cfg = A.db.config
  cfg.minimap = cfg.minimap or {}
  setupSettings()
  if not (MK.UI and MK.UI.MinimapButton) then return end
  local ok, b = pcall(MK.UI.MinimapButton, { name = "EldersMinimapButton",
    icon = UI.Art("icon_elders") or "Interface\\Icons\\INV_Misc_Book_09", db = cfg.minimap,
    onClick = function(btn)
      if btn == "RightButton" then UI.OpenSettings() else A:Fire("TOGGLE_PANEL") end
    end,
    tooltip = tooltip })
  if ok then button = b else A:Debug("minimap failed: " .. tostring(b)) end
  UI.minimapButton = button
end
