-- Pace: XP deltas split by source (quest / kill / other), rested bonus, per-zone xp, level-ups, /played capture.
-- CONTRACT NOTE: if MK.Match is missing at runtime a tiny local matcher over the client global strings is used.

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Pace")
local Agg = ns.Agg

local lastXP, lastMax
local pending = 0              -- xp gained and not yet attributed to quest/kill (signed: credits may arrive first)
local lastPlayed               -- { total, level, forLevel, clock }
local ding                     -- level-up awaiting its /played reply

---------------------------------------------------------------------------
-- XP chat message parsing

local function localMatch(name, text)
  local fmt = _G[name] or (MK.GS and MK.GS(name))
  if type(fmt) ~= "string" or type(text) ~= "string" then return nil end
  local pat = fmt:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%-?%%d+)")
  local r = { text:match("^" .. pat .. "$") }
  if #r == 0 then return nil end
  return unpack(r)
end

local function match(name, text)
  if MK.Match then return MK.Match(name, text) end
  return localMatch(name, text)
end

-- name, index of the xp argument, has mob name, index of the rested-bonus argument
local FAMILIES = {
  { "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", 2, true, 3 },
  { "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", 2, true, 3 },
  { "COMBATLOG_XPGAIN_EXHAUSTION1", 2, true, 3 },
  { "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", 2, true },
  { "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", 2, true },
  { "COMBATLOG_XPGAIN_FIRSTPERSON", 2, true },
  { "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP", 1, false },
  { "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", 1, false },
  { "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", 1, false },
}

-- Returns xp, isKill, restedBonus or nil.
function M.ParseXPMessage(text)
  text = MK.Safe(text)
  if type(text) ~= "string" then return nil end
  for _, f in ipairs(FAMILIES) do
    local args = { match(f[1], text) }
    if #args > 0 then
      local xp = tonumber(args[f[2]])
      if xp then
        local bonus = f[4] and tonumber(tostring(args[f[4]] or ""):match("%d+")) or nil
        return xp, f[3], bonus
      end
    end
  end
end

---------------------------------------------------------------------------
-- XP

local function readXP()
  local cur, max = MK.Call(UnitXP, "player"), MK.Call(UnitXPMax, "player")
  if type(cur) == "number" and type(max) == "number" then return cur, max end
end

local function flush()
  if pending > 0 then Agg.Add("xpOther", pending) end
  pending = 0
end

local function onXP(_, unit)
  if unit and unit ~= "player" then return end
  local cur, max = readXP()
  if not cur then return end
  if not lastXP then lastXP, lastMax = cur, max return end
  local gain
  if max == lastMax then gain = cur - lastXP else gain = (lastMax - lastXP) + cur end
  lastXP, lastMax = cur, max
  if gain <= 0 then return end
  Agg.Add("xp", gain)
  pending = pending + gain
  local map = ns.MapID and ns.MapID()
  if map then
    local z = Agg.Rec("zones", map, { sec = 0, xp = 0, copper = 0 })
    z.xp = z.xp + gain
  end
  A:Debounce("xpflush", 0.5, flush)
end

local function onQuest(_, questID, xp)
  Agg.Add("quests", 1)
  xp = MK.Safe(xp)
  if type(xp) == "number" and xp > 0 then
    Agg.Add("xpQuest", xp)
    pending = pending - xp
    A:Debounce("xpflush", 0.5, flush)
  end
end

local function onXPMessage(_, text)
  local xp, isKill, bonus = M.ParseXPMessage(text)
  if not xp then return end
  if isKill then
    Agg.Add("killsXP", 1)
    Agg.Add("xpKill", xp)
    pending = pending - xp
    A:Debounce("xpflush", 0.5, flush)
  end
  if bonus and bonus > 0 then Agg.Add("xpRested", bonus) end
end

---------------------------------------------------------------------------
-- /played and level-ups

local function silentPlayed()
  local cf = DEFAULT_CHAT_FRAME
  if cf and cf.UnregisterEvent then cf:UnregisterEvent("TIME_PLAYED_MSG") end
  if RequestTimePlayed then pcall(RequestTimePlayed) end
  A:After(2, function() if cf and cf.RegisterEvent then cf:RegisterEvent("TIME_PLAYED_MSG") end end)
end

local function finishDing()
  if not ding or ding.done then return end
  ding.done = true
  local row = Agg.LevelRow(ding.level - 1)
  A:Push("levelup", { level = ding.level, sec = row.sec, deaths = row.deaths, class = ns.char and ns.char.class,
    played = ns.char and ns.char.played and ns.char.played.total, talents = Agg.LevelRow(ding.level - 1).talents })
end

local function onPlayed(_, total, levelTime)
  total, levelTime = MK.Safe(total), MK.Safe(levelTime)
  if type(total) ~= "number" or type(levelTime) ~= "number" then return end
  local level = Agg.Level()
  ns.char.played = { total = total, level = levelTime, at = MK.Util.ServerTime() }
  if ding and not ding.done then
    -- Some clients answer with the finished level's time, others with ~0 for the new level.
    if levelTime >= 30 then Agg.LevelRow(ding.level - 1).sec = math.floor(levelTime) end
    finishDing()
    local sinceDing = GetTime() - ding.clock
    lastPlayed = { total = total, level = levelTime >= 30 and sinceDing or levelTime, forLevel = level, clock = GetTime() }
  else
    lastPlayed = { total = total, level = levelTime, forLevel = level, clock = GetTime() }
  end
end

local function onLevelUp(_, level)
  level = MK.Safe(level)
  if type(level) ~= "number" then level = MK.Call(UnitLevel, "player") end
  if type(level) ~= "number" then return end
  -- estimate the finished level's time from the last /played reading before the ding changes anything
  local est
  if lastPlayed and lastPlayed.forLevel == level - 1 then
    est = math.floor(lastPlayed.level + (GetTime() - lastPlayed.clock))
  end
  Agg.SetLevel(level)
  if est and est > 0 then Agg.LevelRow(level - 1).sec = est end
  ding = { level = level, clock = GetTime() }
  silentPlayed()
  A:After(3, finishDing)
  A:Fire("LEVEL_UP", level)
  if level % 10 == 0 then A:Fire("RITUAL_DUE", level / 10) end
end

function M:OnLogin()
  lastXP, lastMax = readXP()
  silentPlayed()
end

A:On("PLAYER_XP_UPDATE", onXP)
A:On("QUEST_TURNED_IN", onQuest)
A:On("CHAT_MSG_COMBAT_XP_GAIN", onXPMessage)
A:On("PLAYER_LEVEL_UP", onLevelUp)
A:On("TIME_PLAYED_MSG", onPlayed)
