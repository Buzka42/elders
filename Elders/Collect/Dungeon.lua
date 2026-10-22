-- Dungeon: party-instance runs (enter/leave), final-boss clears, wipe polling on the shared 1 Hz tick,
-- deaths inside the run and the "group forming time" heuristic (1 -> 2 members ... 5 members ... enter).
-- CONTRACT NOTE: Data/Dungeons.lua only has creature ids for final bosses (no names / encounter ids), so ENCOUNTER_END
-- and BOSS_KILL only mark a final-boss kill if the row has optional `finalBossNames` / `encounterIDs` lists.
-- Dungeons with an empty finalBoss list (e.g. Blackfathom Deeps) never register a clear. Extra rec key: `bosses`.

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Dungeon")
local Agg = ns.Agg

local DEFAULTS = { runs = 0, clears = 0, clearSec = 0, wipes = 0, deaths = 0 }
local run
local prevSize = 0
local form                    -- { t0, full }  group-forming sequence
local lastWipe, wipeLatched = -100, false

local function dungeonRow(id) return ns.Data and ns.Data.Dungeons and ns.Data.Dungeons[id] end
local function rec() return Agg.Rec("dungeons", run.id, DEFAULTS) end

local function creatureID(guid)
  guid = MK.Safe(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

---------------------------------------------------------------------------
-- Run lifecycle

local function startRun(id, name)
  run = { id = id, name = name, t0 = GetTime(), deaths = 0, wipes = 0, bosses = 0, seen = {} }
  rec().runs = rec().runs + 1
  if form then
    local now = GetTime()
    local lfg = Agg.Bracket().lfg
    lfg.n = lfg.n + 1
    lfg.enterSec = lfg.enterSec + (now - form.t0)
    lfg.formSec = lfg.formSec + ((form.full or now) - form.t0)
    form = nil
  end
end

local function endRun()
  if not run then return end
  local r = run
  run = nil
  local cleared = r.finalAt ~= nil
  local secs = cleared and (r.finalAt - r.t0) or (GetTime() - r.t0)
  if cleared then
    local row = Agg.Rec("dungeons", r.id, DEFAULTS)
    row.clears = row.clears + 1
    row.clearSec = row.clearSec + secs
  end
  A:Fire("DUNGEON_DONE", { id = r.id, name = r.name, cleared = cleared, sec = secs, deaths = r.deaths,
    wipes = r.wipes, bosses = r.bosses })
end

local function check()
  local inInstance, itype, id = MK.InstanceState()
  local inParty = inInstance and itype == "party" and type(id) == "number"
  if run and (not inParty or id ~= run.id) then endRun() end
  if inParty and not run then
    local name = MK.Call(GetInstanceInfo)
    startRun(id, type(name) == "string" and name or nil)
  end
end

---------------------------------------------------------------------------
-- Boss kills

local function markBoss(key, final)
  if not run then return end
  if key and not run.seen[key] then
    run.seen[key] = true
    run.bosses = run.bosses + 1
    local r = rec()
    r.bosses = (r.bosses or 0) + 1
  end
  if final and not run.finalAt then run.finalAt = GetTime() end
end

local function listHas(list, v)
  if type(list) ~= "table" then return false end
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function isFinalEncounter(id, name)
  local row = run and dungeonRow(run.id)
  if not row then return false end
  if listHas(row.encounterIDs, id) then return true end
  if type(name) == "string" and type(row.finalBossNames) == "table" then
    local n = name:lower()
    for _, x in ipairs(row.finalBossNames) do if type(x) == "string" and x:lower() == n then return true end end
  end
  return false
end

local function onEncounter(event, id, name, _, _, success)
  if not run then return end
  id, name = MK.Safe(id), MK.Safe(name)
  if event == "ENCOUNTER_END" and not (success == 1 or success == true) then return end
  markBoss("e" .. tostring(id or name), isFinalEncounter(id, name))
end

local function onPartyKill(_, attacker, victim)
  if not run then return end
  local cid = creatureID(victim)
  if not cid then return end
  local row = dungeonRow(run.id)
  if row and listHas(row.finalBoss, cid) then markBoss("c" .. cid, true) end
end

---------------------------------------------------------------------------
-- Wipes (1 Hz, only inside a party instance)

local function partyAllDead()
  local members = 1
  if MK.Call(UnitIsDeadOrGhost, "player") ~= true then return false end
  for i = 1, 4 do
    local u = "party" .. i
    if MK.Call(UnitExists, u) then
      members = members + 1
      if MK.Call(UnitIsDeadOrGhost, u) ~= true then return false end
    end
  end
  return members >= 2
end

local function onTick()
  if not run then return end
  if partyAllDead() then
    local now = GetTime()
    if not wipeLatched and now - lastWipe >= 30 then
      lastWipe = now
      run.wipes = run.wipes + 1
      rec().wipes = rec().wipes + 1
    end
    wipeLatched = true
  else
    wipeLatched = false
  end
end

---------------------------------------------------------------------------
-- LFG-style group forming heuristic

local function onRoster()
  local size = MK.Call(IsInGroup) and (MK.Call(GetNumGroupMembers) or 1) or 1
  local now = GetTime()
  if size <= 1 then
    form = nil
  elseif prevSize <= 1 and not run then
    form = { t0 = now }
  end
  if form and size >= 5 and not form.full then form.full = now end
  prevSize = size
end

function M:OnLogin()
  prevSize = MK.Call(IsInGroup) and (MK.Call(GetNumGroupMembers) or 1) or 1
  if ns.OnTick then ns.OnTick(onTick) end
end

A:On("PLAYER_ENTERING_WORLD", check)
A:On("ZONE_CHANGED_NEW_AREA", check)
A:On("GROUP_ROSTER_UPDATE", onRoster)
A:On("BOSS_KILL", onEncounter)
A:On("ENCOUNTER_END", onEncounter)
A:On("PARTY_KILL", onPartyKill)
A:On("PLAYER_LOGOUT", endRun)
A:Listen("DEATH", function()
  if not run then return end
  run.deaths = run.deaths + 1
  rec().deaths = rec().deaths + 1
end)
