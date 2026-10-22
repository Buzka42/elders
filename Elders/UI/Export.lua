-- Export window: the character's stats as a copyable string for the website (SHOW_EXPORT).
--
-- CONTRACT NOTE: when MK.ExportString is missing or fails, a plain "ELDERS-PLAIN:" key=value dump is shown instead.

local ADDON, ns = ...
local MK = MetaKit
local UI = ns.UI
local A = ns.A

local function dump(v, out, path)
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do dump(v[k], out, path .. "." .. tostring(k)) end
  elseif v ~= nil then
    out[#out + 1] = path .. "=" .. tostring(v)
  end
end

local function plain(payload)
  local out = {}
  dump(payload, out, "")
  return "ELDERS-PLAIN:" .. table.concat(out, ";")
end

function UI.ExportText()
  local payload = ns.ExportPayload()
  if MK.ExportString then
    local ok, s = pcall(MK.ExportString, "elders", payload)
    if ok and type(s) == "string" then return s end
  end
  return plain(payload)
end

A:Listen("SHOW_EXPORT", function()
  local text = UI.ExportText()
  if MK.UI and MK.UI.ExportBox then
    UI.ApplyTheme()
    MK.UI.ExportBox{ title = "Export your stats", text = text, skin = UI.SKIN }
  else
    A:Print("Export ready (" .. #text .. " characters), but the interface kit is not loaded.")
  end
end)
