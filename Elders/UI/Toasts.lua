-- Toasts: a short note on every level, a sealed banner when a bracket ends, and "Bracket sealed" after the ritual.

local ADDON, ns = ...
local MK = MetaKit
local U = MK.Util
local UI = ns.UI
local A = ns.A

local function toast(t)
  if not (MK.UI and MK.UI.Toast) or A.db.config.toasts == false then return end
  t.skin = UI.SKIN
  t.icon = t.icon or UI.Art("icon_elders")
  pcall(MK.UI.Toast, t)
end

A:Listen("LEVEL_UP", function(level)
  -- Pace stores the time of the finished level a moment after the ding (from /played).
  A:After(3, function()
    local row = ns.char and ns.char.levels and ns.char.levels[level - 1]
    local parts = {}
    if row and (row.sec or 0) > 0 then parts[#parts + 1] = U.Duration(row.sec) end
    local d = row and row.deaths or 0
    parts[#parts + 1] = d == 0 and "no deaths" or (d == 1 and "1 death" or (d .. " deaths"))
    local ends = level % 10 == 0
    toast({
      title = ends and string.format("Levels %d to %d complete", level - 9, level) or ("Level " .. level),
      text = (ends and "The Elders take note. " or "") .. table.concat(parts, ", ") .. ".",
      banner = ends and "good" or nil, duration = ends and 7 or 4,
    })
  end)
end)

A:Listen("RITUAL_SUBMIT", function(b)
  toast({ title = "Bracket sealed", banner = "good", duration = 6,
    text = string.format("Levels %d to %d are written in the Elders' book.", (b - 1) * 10 + 1, b * 10) })
end)
