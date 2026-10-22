-- Combat: fights (merged when < 3 s apart), post-fight damage-meter totals, kills, solo elites, mob level delta,
-- and cast counters for role/interrupt/dispel/CC/taunt spells. Never reads secrets; no combat log.

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local U = MK.Util
local M = A:NewModule("Combat")
local Agg = ns.Agg

local MERGE_GAP = 3
local FIGHT_EDGES = { 5, 10, 20, 40, 80 }
-- meterType -> bracket key
local METER = { { 0, "dmg" }, { 7, "taken" }, { 2, "heal" }, { 4, "absorb" }, { 5, "interrupts" }, { 6, "dispels" } }

local fight                    -- { start, last, pvp, token, ended }
local duelUntil = 0           -- GetTime() until which fights count as PvP (duel started/pending)
local playerGUID
local lru, lruOrder = {}, {}   -- guid -> classification (last 50 targets)
local spellCats = {}           -- spell name -> { category, ... } built at login
local castCache = {}           -- spellID -> categories or false

---------------------------------------------------------------------------
-- Damage meter

local function localSource(session)
  if type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
  for _, src in ipairs(session.combatSources) do
    if type(src) == "table" and MK.Safe(src.isLocalPlayer) == true then return src end
  end
end

local function readMeter()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return nil end
  local avail = MK.Call(C_DamageMeter.IsDamageMeterAvailable)
  if C_DamageMeter.IsDamageMeterAvailable and avail == false then return nil end
  local sessionType = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local out = {}
  for _, m in ipairs(METER) do
    local session = MK.Call(C_DamageMeter.GetCombatSessionFromType, sessionType, m[1])
    local src = localSource(session)
    local total = src and MK.Safe(src.totalAmount)
    if type(total) == "number" and total >= 0 then
      out[m[2]] = math.floor(total)
      if m[1] == 0 then
        local dur = MK.Safe(session.durationSeconds)
        if type(dur) == "number" and dur > 0 then out.meterSec = dur end
      end
    end
  end
  return out
end

local function postFight(f)
  if f.pvp or MK.InCombat() then return end
  local inInstance, itype = MK.InstanceState()
  if itype == "pvp" or itype == "arena" then return end
  local r = readMeter()
  if not r then return end
  for _, m in ipairs(METER) do
    if r[m[2]] and r[m[2]] > 0 then Agg.Add(m[2], r[m[2]]) end
  end
  if r.meterSec and r.dmg and r.dmg > 0 then Agg.Add("meterSec", r.meterSec) end
  f.meter = r
end

---------------------------------------------------------------------------
-- Fights

local function targetIsEnemyPlayer()
  local t = MK.UnitInfo("target")
  return t and t.isPlayer == true and MK.Call(UnitCanAttack, "player", "target") == true
end

local function finalize(f)
  if fight ~= f or not f.ended then return end
  fight = nil
  local dur = math.max(0, f.last - f.start)
  Agg.Add("fights", 1)
  Agg.Add("fightSec", dur)
  Agg.Hist("fightHist", U.Bin(dur, FIGHT_EDGES))
  A:Fire("FIGHT_END", { dur = dur, pvp = f.pvp, meter = f.meter })
end

local function onRegenDisabled()
  local now = GetTime()
  if fight and fight.ended and now - fight.last < MERGE_GAP then
    fight.ended = false          -- merge: same fight continues
  else
    if fight then finalize(fight) end
    fight = { start = now, last = now }
  end
  local inInstance, itype = MK.InstanceState()
  if itype == "pvp" or itype == "arena" or GetTime() < duelUntil or targetIsEnemyPlayer() then fight.pvp = true end
end

local function onRegenEnabled()
  local f = fight
  if not f then return end
  f.last = GetTime()
  f.ended = true
  A:After(0.5, function() postFight(f) end)
  A:After(MERGE_GAP + 0.1, function() finalize(f) end)
end

---------------------------------------------------------------------------
-- Targets, kills

local function remember(guid, class)
  if lru[guid] == nil then
    lruOrder[#lruOrder + 1] = guid
    if #lruOrder > 50 then lru[table.remove(lruOrder, 1)] = nil end
  end
  lru[guid] = class
end

local function onTarget()
  local info = MK.UnitInfo("target")
  if not info then return end
  if fight and not fight.ended and info.isPlayer == true and MK.Call(UnitCanAttack, "player", "target") then fight.pvp = true end
  if info.isPlayer ~= false then return end
  local guid = info.guid
  local known = guid and lru[guid] ~= nil
  if guid then remember(guid, info.classification or "normal") end
  if known or MK.InCombat() then return end
  if MK.Call(UnitCanAttack, "player", "target") ~= true then return end
  local lvl = info.level
  if type(lvl) ~= "number" then return end
  local mine = Agg.Level()
  local delta = lvl < 1 and 5 or lvl - mine -- "??" (-1) skull mobs count as +5
  Agg.Hist("mobDelta", U.Clamp(delta, -5, 5) + 6)
end

local ELITE = { elite = true, rareelite = true, worldboss = true }

local function onPartyKill(_, attacker, victim)
  attacker, victim = MK.Safe(attacker), MK.Safe(victim)
  if not attacker or not victim then return end
  playerGUID = playerGUID or MK.Call(UnitGUID, "player")
  if attacker ~= playerGUID then return end
  Agg.Add("kills", 1)
  if ELITE[lru[victim] or ""] and not MK.Call(IsInGroup) then Agg.Add("eliteSolo", 1) end
end

---------------------------------------------------------------------------
-- Casts

local function buildSpellSets()
  spellCats, castCache = {}, {}
  local _, class = MK.Call(UnitClass, "player")
  local data = ns.Data and ns.Data.Spells
  if not (class and data) then return end
  local map = { heal = "heal", tank = "tank", interrupt = "interruptCasts", dispel = "dispelCasts", cc = "ccCasts", taunt = "tauntCasts" }
  for cat, key in pairs(map) do
    for _, id in ipairs(data[cat] and data[cat][class] or {}) do
      local info = C_Spell and MK.Call(C_Spell.GetSpellInfo, id)
      local name = type(info) == "table" and MK.Safe(info.name) or nil
      if type(name) == "string" then
        spellCats[name] = spellCats[name] or {}
        table.insert(spellCats[name], { cat, key })
      end
    end
  end
end

local function onCast(_, unit, _, spellID)
  if unit ~= "player" then return end
  spellID = MK.Safe(spellID)
  if type(spellID) ~= "number" then return end
  local cats = castCache[spellID]
  if cats == nil then
    if next(spellCats) == nil then buildSpellSets() end
    local info = C_Spell and MK.Call(C_Spell.GetSpellInfo, spellID)
    local name = type(info) == "table" and MK.Safe(info.name) or nil
    cats = name and spellCats[name] or false
    castCache[spellID] = cats
  end
  if not cats then return end
  for _, c in ipairs(cats) do
    if c[1] == "heal" or c[1] == "tank" then Agg.Add("roleCasts", 1, c[1]) else Agg.Add(c[2], 1) end
  end
end

function M:OnLogin()
  playerGUID = MK.Call(UnitGUID, "player")
  buildSpellSets()
end

A:On("PLAYER_REGEN_DISABLED", onRegenDisabled)
A:On("PLAYER_REGEN_ENABLED", onRegenEnabled)
A:On("PLAYER_TARGET_CHANGED", onTarget)
A:On("PARTY_KILL", onPartyKill)
local function duelOn() duelUntil = GetTime() + 120; if fight then fight.pvp = true end end
A:On("DUEL_REQUESTED", function() duelUntil = GetTime() + 120 end)
A:On("DUEL_INBOUNDS", duelOn)
A:On("DUEL_OUTOFBOUNDS", duelOn)
A:On("DUEL_FINISHED", function() if fight and GetTime() < duelUntil then fight.pvp = true end duelUntil = 0 end)
A:OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", onCast)
