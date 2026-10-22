-- Activity: the shared 1 Hz ticker (play-state buckets, zone/group/rested seconds) and the death/corpse-run tracker.
-- Other collectors hook the ticker with ns.OnTick(fn(dt)); ns.MapID() gives the cached current map id.
-- CONTRACT NOTE: corpse runs are counted in an extra bracket key `corpseRuns` (Agg.Add creates it); corpse-run
-- seconds are `ghostSec`, so avg corpse run = ghostSec / corpseRuns (spirit-healer releases are counted in `spiritRes`).

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Activity")
local Agg = ns.Agg

local state = "idle"
local eating, drinking = false, false
local names = {}              -- localized aura names -> "eat" | "drink"
local tickFns = {}
local lastTick
local death                  -- { t, released, ctx } for the death in progress
local lastDeathAt = -100

M.FOOD_IDS = { [433] = "eat", [434] = "eat", [435] = "eat", [1127] = "eat", [1129] = "eat", [2639] = "eat",
  [18071] = "eat", [24005] = "eat", [430] = "drink", [431] = "drink", [432] = "drink", [1133] = "drink",
  [1135] = "drink", [1137] = "drink", [24355] = "drink", [25689] = "drink", [26473] = "drink" }
-- Best-effort texture ids for the stock eat/drink aura icons (unverified; names and spell ids are the primary match).
M.FOOD_ICONS = { [133950] = "eat", [132794] = "drink" }

function ns.OnTick(fn) tickFns[#tickFns + 1] = fn end
function ns.State() return state end

local mapCache, mapAt = nil, -10
function ns.MapID()
  local now = GetTime()
  if now - mapAt >= 1 then
    mapCache = C_Map and MK.Call(C_Map.GetBestMapForUnit, "player") or nil
    mapAt = now
  end
  return mapCache
end

local function buildNames()
  names = {}
  for id, kind in pairs({ [433] = "eat", [430] = "drink" }) do
    local info = C_Spell and MK.Call(C_Spell.GetSpellInfo, id)
    local n = type(info) == "table" and MK.Safe(info.name) or (type(info) == "string" and info) or nil
    if type(n) == "string" then names[n] = kind end
  end
end

---------------------------------------------------------------------------
-- Eat / drink detection (out of combat only, aura data is secret in combat)

local function scanAuras()
  if MK.InCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  if next(names) == nil then buildNames() end
  local e, d = false, false
  for i = 1, 40 do
    local aura = MK.Call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if type(aura) ~= "table" then break end
    local kind = M.FOOD_IDS[MK.Safe(aura.spellId) or 0]
    local name = MK.Safe(aura.name)
    if not kind and type(name) == "string" then kind = names[name] end
    if not kind then kind = M.FOOD_ICONS[MK.Safe(aura.icon) or 0] end
    if kind == "eat" then e = true elseif kind == "drink" then d = true end
  end
  eating, drinking = e, d
end

---------------------------------------------------------------------------
-- 1 Hz tick

local function classify()
  local ghost = MK.Call(UnitIsGhost, "player")
  if ghost then return "ghost" end
  if MK.Call(UnitIsDead, "player") then return "dead" end
  if MK.Call(UnitOnTaxi, "player") then return "taxi" end
  if eating then return "eat" end
  if drinking then return "drink" end
  if MK.InCombat() then return "combat" end
  if MK.Call(IsMounted) then return "mounted" end
  local speed = MK.Call(GetUnitSpeed, "player")
  if type(speed) == "number" and speed > 0 then return "moving" end
  return "idle"
end

local function tick()
  local now = GetTime()
  local dt = lastTick and now - lastTick or 1
  lastTick = now
  if dt <= 0 or dt > 5 then dt = 1 end
  state = classify()
  Agg.Add("act", dt, state)
  Agg.Add("sec", dt)
  if state == "dead" then Agg.Add("deadSec", dt) elseif state == "ghost" then Agg.Add("ghostSec", dt) end
  local map = ns.MapID()
  if map then
    local z = Agg.Rec("zones", map, { sec = 0, xp = 0, copper = 0 })
    z.sec = z.sec + dt
  end
  if MK.Call(IsInGroup) then
    Agg.Add("groupSec", dt)
    Agg.Add("groupSizeSec", (MK.Call(GetNumGroupMembers) or 1) * dt)
  end
  local rested = MK.Call(GetXPExhaustion)
  if type(rested) == "number" and rested > 0 then Agg.Add("rested", dt, "sec") end
  for i = 1, #tickFns do
    local ok, err = pcall(tickFns[i], dt)
    if not ok then A:Error("tick", err) end
  end
end

---------------------------------------------------------------------------
-- Deaths

local function deathContext()
  local inInstance, itype = MK.InstanceState()
  if itype == "pvp" or itype == "arena" then return "pvp" end
  local target = MK.UnitInfo("target")
  if target and target.isPlayer and MK.Call(UnitCanAttack, "player", "target") then return "pvp" end
  if inInstance and (itype == "party" or itype == "raid" or itype == "scenario") then return "dungeon" end
  if MK.Call(IsInGroup) then return "group" end
  return "solo"
end

local function onDead()
  local now = GetTime()
  if now - lastDeathAt < 2 then return end
  lastDeathAt = now
  local kind = deathContext()
  local inInstance, itype, instanceID = MK.InstanceState()
  Agg.Add("deaths", 1)
  Agg.Add("deathCtx", 1, kind)
  Agg.LevelRow().deaths = (Agg.LevelRow().deaths or 0) + 1
  local ctx = { kind = kind, t = now, instance = inInstance and instanceID or nil, instanceType = itype,
    map = ns.MapID(), level = Agg.Level() }
  death = { t = now, ctx = ctx }
  A:Fire("DEATH", ctx)
end

local function onAlive()
  if not death then return end
  local now = GetTime()
  if MK.Call(UnitIsGhost, "player") then
    if not death.released then
      death.released = now
      death.ctx.sitSec = now - death.t
    end
  elseif death.released then
    -- alive without a corpse run: spirit healer resurrection
    Agg.Add("spiritRes", 1)
    death = nil
  else
    death = nil -- resurrected by someone while still a corpse
  end
end

local function onUnghost()
  if death and death.released then
    Agg.Add("corpseRuns", 1)
    death.ctx.runSec = GetTime() - death.released
  end
  death = nil
end

function M:OnLogin()
  buildNames()
  scanAuras()
  lastTick = GetTime()
  self.ticker = A:Every(1, tick)
end

A:On("PLAYER_DEAD", onDead)
A:On("PLAYER_ALIVE", onAlive)
A:On("PLAYER_UNGHOST", onUnghost)
A:On("PLAYER_REGEN_ENABLED", scanAuras)
A:On("PLAYER_REGEN_DISABLED", function() eating, drinking = false, false end) -- combat cancels eating/drinking
A:On("PLAYER_ENTERING_WORLD", function() mapAt = -10; buildNames(); scanAuras() end)
A:On("ZONE_CHANGED_NEW_AREA", function() mapAt = -10 end)
A:OnUnit("UNIT_AURA", "player", scanAuras)

function M.Test() return { state = state, eating = eating, drinking = drinking, death = death } end
