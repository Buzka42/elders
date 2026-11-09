-- Announce: Elders says its milestones in chat, through the shared MK.Chat sink (paced, deduped, capped, silent when chat
-- is locked). Two lines exist: a level-up and a sealed bracket. Nothing here reads game state beyond the LEVEL_UP /
-- RITUAL_SUBMIT messages the collectors and the ritual already fire.
--
-- Config (EldersDB.config):
--   eldersAnnounce = "say" | "group" | "off"   where the lines go. Default "say" (people nearby); "group" = instance
--                    group > raid > party, nothing when you are alone; "off" = silent.
--   announceLevel = true     the level-up line (also the "levels 11-20 done" line on a tenth level)
--   announceBracket = true   the "bracket sealed" line after the ritual is submitted (a skipped ritual seals nothing)
--   chat = MK.Chat config    pacing / dedupe / cap shared with the sink; category "elders" (cats.elders.on is the master toggle)
-- CONTRACT NOTE: the route is read when a line is sent, so changing eldersAnnounce applies at once, no reload.

local ADDON, ns = ...
local MK = MetaKit
local U = MK.Util
local A = ns.A

local M = A:NewModule("Announce")
local Announce = {}
ns.Announce = Announce

local ROUTE = { say = "say", group = "group" }

function Announce.Mode()
  local m = A.db and A.db.config and A.db.config.eldersAnnounce
  return ROUTE[m] and m or "off"
end

-- Sends one line to the configured route; returns Chat.Say's result, or false, "off".
function Announce.Say(text, opts)
  local route = ROUTE[Announce.Mode()]
  if not route or not (MK.Chat and A.db) then return false, "off" end
  opts = opts or {}
  opts.route = route
  return MK.Chat.Say("elders", text, opts)
end

local function myName()
  local _, name = MK.PlayerKey()
  return name or "Someone"
end

-- "Tester hit level 12! Level 11: 12m 04s, no deaths. [Elders]" (the details wait for Pace's /played reading).
function Announce.LevelText(level, row)
  local parts = {}
  if row and (row.sec or 0) > 0 then parts[#parts + 1] = U.Duration(row.sec) end
  if row then
    local d = row.deaths or 0
    parts[#parts + 1] = d == 0 and "no deaths" or (d == 1 and "1 death" or (d .. " deaths"))
  end
  local head = string.format("%s hit level %d!", myName(), level)
  if level % 10 == 0 then head = head .. string.format(" Levels %d to %d done.", level - 9, level) end
  if #parts > 0 then head = head .. string.format(" Level %d: %s.", level - 1, table.concat(parts, ", ")) end
  return head .. " [Elders]"
end

function Announce.BracketText(b)
  return string.format("%s sealed levels %d to %d in the Elders' book. [Elders]", myName(), (b - 1) * 10 + 1, b * 10)
end

function M:OnInit(db)
  if MK.Chat then MK.Chat.Configure(db.config.chat) end
end

A:Listen("LEVEL_UP", function(level)
  if Announce.Mode() == "off" or not A.db.config.announceLevel then return end
  if type(level) ~= "number" then return end
  -- Pace stores the finished level's time a moment after the ding, like the toast does.
  A:After(3, function()
    local row = ns.char and ns.char.levels and ns.char.levels[level - 1]
    Announce.Say(Announce.LevelText(level, row))
  end)
end)

A:Listen("RITUAL_SUBMIT", function(b)
  if Announce.Mode() == "off" or not A.db.config.announceBracket then return end
  b = tonumber(b)
  if not b or b < 1 then return end
  Announce.Say(Announce.BracketText(b), { important = true })
end)
