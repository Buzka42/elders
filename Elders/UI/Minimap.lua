-- Minimap button (left: panel, right: settings, drag: move) and the native Settings category.

local ADDON, ns = ...
local MK = MetaKit
local UI = ns.UI
local A = ns.A

local M = A:NewModule("Minimap")
local button

-- Settings keys are flat; "minimapHide" lives in config.minimap.hide, the chat keys map onto config.eldersAnnounce and
-- config.chat, the rest straight in config. "announceChannel" is the slider form of eldersAnnounce: 0 off, 1 say, 2 group.
local ANNOUNCE = { [0] = "off", "say", "group" }
local function announceIndex(mode) for i = 0, 2 do if ANNOUNCE[i] == mode then return i end end return 0 end

local function settingsProxy()
  local cfg = A.db.config
  return setmetatable({}, {
    __index = function(_, k)
      if k == "minimapHide" then return cfg.minimap.hide and true or false end
      if k == "announceChannel" then return announceIndex(cfg.eldersAnnounce) end
      if k == "chatInterval" then return cfg.chat.interval end
      return cfg[k]
    end,
    __newindex = function(_, k, v)
      if k == "minimapHide" then
        cfg.minimap.hide = v and true or false
        if button then button:SetShown(not cfg.minimap.hide) end
      elseif k == "announceChannel" then
        cfg.eldersAnnounce = ANNOUNCE[math.floor((tonumber(v) or 0) + 0.5)] or "off"
      elseif k == "chatInterval" then
        cfg.chat.interval = tonumber(v) or cfg.chat.interval
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
    { type = "header", label = "Chat announcements" },
    { type = "slider", key = "announceChannel", label = "Announce to: 0 off, 1 say, 2 group", min = 0, max = 2, step = 1,
      tooltip = "Where Elders says its milestones. 0 = nowhere, 1 = /say (people nearby), 2 = your party or raid." },
    { type = "check", key = "announceLevel", label = "Announce level-ups", tooltip = "One short line per level." },
    { type = "check", key = "announceBracket", label = "Announce sealed brackets", tooltip = "One line when you finish the ritual for a bracket." },
    { type = "slider", key = "chatInterval", label = "Seconds between chat lines", min = 1, max = 10, step = 0.5,
      tooltip = "Public chat lines from World of Meta addons are paced at least this far apart." },
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

-- Tooltip line in a kit colour token ("good", "muted", ...); plain line if the kit is absent.
local function tokenLine(tt, text, key)
  local c = MK.UI and MK.UI.Tokens and MK.UI.Tokens[key]
  if c then tt:AddLine(text, c[1], c[2], c[3]) else tt:AddLine(text) end
end

local function tooltip(tt)
  tokenLine(tt, "Elders", "good")
  local xph, gph = UI.Quick(UI.CurrentTab())
  tt:AddDoubleLine("XP per hour", xph)
  tt:AddDoubleLine("Gold per hour", gph)
  local n = A:PendingCount() or 0
  tt:AddDoubleLine("Waiting to sync", tostring(n))
  tokenLine(tt, "Left-click: stats panel", "muted")
  tokenLine(tt, "Right-click: settings", "muted")
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
