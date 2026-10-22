-- Elders UI helpers: the skin name, art lookup (rank badges only) and the formatting helpers used by the other UI files (ns.UI).
--

local ADDON, ns = ...
local MK = MetaKit

local UI = {}
ns.UI = UI

UI.SKIN = "elders"
UI.DASH = "\226\128\148" -- em dash, shown when there is too little data

-- Art path for one of our textures, or nil when the file is not shipped.
function UI.Art(name)
  if MK.UI and MK.UI.Art then return MK.UI.Art(ns, name) end
  if ns.Media and ns.Media.has and ns.Media.has[name] then return ns.Media.path .. name end
  return nil
end

-- Kept for callers: the kit's "elders" skin is already the flat palette and Elders adds no art tokens to it.
function UI.ApplyTheme() UI.themed = true end

UI.ApplyTheme()

---------------------------------------------------------------------------
-- Formatting helpers

function UI.Num(n)
  if type(n) ~= "number" then return UI.DASH end
  local a = math.abs(n)
  if a >= 10000 then return string.format("%.1fk", n / 1000) end
  if a >= 100 then return string.format("%d", math.floor(n + 0.5)) end
  if a >= 10 then return string.format("%.1f", n) end
  return string.format("%.2f", n)
end

function UI.Pct(x)
  if type(x) ~= "number" then return UI.DASH end
  return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- "Elders rank" 1..14 of a character from the downloaded site data (number or { rank = n }), default 1.
function UI.Rank(charId)
  local r = MK.Wom("elders", "ranks", charId)
  if type(r) == "table" then r = r.rank end
  r = tonumber(r) or 1
  return MK.Util.Clamp(math.floor(r), 1, 14)
end

local RANK_NAMES = { "Initiate", "Listener", "Witness", "Scribe", "Speaker", "Truthseeker", "Lorekeeper", "Sage",
  "Seer", "Oracle", "Councilor", "Elder", "High Elder", "Ancient" }
function UI.RankName(r) return RANK_NAMES[r] or RANK_NAMES[1] end

function UI.OpenSettings()
  if UI.settingsOpener then return UI.settingsOpener() end
  ns.A:Print("Settings are not available on this client.")
end
