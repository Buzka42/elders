-- Build: talent snapshot per level (3-level API fallback chain), profession skill gains, level-up stat snapshot.
-- Talent string: one digit per talent (rank, clamped to 9) per tree, trees joined with "/", e.g. "05032/00/0".
-- levels[level].talentApi records the path that worked: 1 = legacy globals, 2 = C_SpecializationInfo, 3 = C_Traits.
-- CONTRACT NOTE: the C_SpecializationInfo / C_Traits / C_SkillInfo shapes are unverified on Forever, so every shape is
-- tolerated (table or multiple returns, rank / currentRank / ...). Skill gains are recorded for every non-header skill line.

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Build")
local Agg = ns.Agg

local MAX_LEN = 600

local function digit(r)
  r = tonumber(r)
  if not r or r < 0 then return "0" end
  return tostring(math.min(9, math.floor(r)))
end

local function rankOf(t)
  if type(t) ~= "table" then return nil end
  for _, k in ipairs({ "rank", "currentRank", "activeRank", "talentRank", "ranksPurchased" }) do
    local v = MK.Safe(t[k])
    if type(v) == "number" then return v end
  end
end

local function joinTabs(tabs)
  local out, any = {}, false
  for i, s in ipairs(tabs) do
    out[i] = s
    if s ~= "" then any = true end
  end
  if any then return table.concat(out, "/") end
end

-- 1) legacy globals: GetNumTalentTabs / GetNumTalents / GetTalentInfo (5th return = rank)
local function viaGlobals()
  if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then return nil end
  local n = MK.Call(GetNumTalentTabs)
  if type(n) ~= "number" or n < 1 then return nil end
  local tabs, found = {}, false
  for tab = 1, n do
    local count = type(GetNumTalents) == "function" and MK.Call(GetNumTalents, tab) or 40
    local s = {}
    for i = 1, (type(count) == "number" and count or 40) do
      local name, _, _, _, rank = MK.Call(GetTalentInfo, tab, i)
      if name == nil then break end
      found = true
      s[#s + 1] = digit(rank)
    end
    tabs[tab] = table.concat(s)
  end
  if found then return joinTabs(tabs) end
end

-- 2) C_SpecializationInfo.GetTalentInfo({ specializationIndex, talentIndex }) then ({ tier, column }) variants
local function viaSpecInfo()
  local get = C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo
  if type(get) ~= "function" then return nil end
  local tabs, found = {}, false
  for tab = 1, 3 do
    local s = {}
    for i = 1, 60 do
      local info = MK.Call(get, { specializationIndex = tab, talentIndex = i })
      local r = rankOf(info)
      if not r then break end
      found = true
      s[#s + 1] = digit(r)
    end
    tabs[tab] = table.concat(s)
  end
  if found then return joinTabs(tabs) end
  tabs = {}
  for tab = 1, 3 do
    local s = {}
    for tier = 1, 11 do
      for col = 1, 4 do
        local info = MK.Call(get, { specializationIndex = tab, tier = tier, column = col })
        local r = rankOf(info)
        if r then found = true; s[#s + 1] = digit(r) end
      end
    end
    tabs[tab] = table.concat(s)
  end
  if found then return joinTabs(tabs) end
end

-- 3) C_ClassTalents.GetActiveConfigID + C_Traits tree nodes, one tree per "tab"
local function viaTraits()
  if not (C_ClassTalents and C_Traits) then return nil end
  local configID = MK.Call(C_ClassTalents.GetActiveConfigID)
  if not configID then return nil end
  local cfg = MK.Call(C_Traits.GetConfigInfo, configID)
  if type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return nil end
  local tabs, found = {}, false
  for t, treeID in ipairs(cfg.treeIDs) do
    local nodes = MK.Call(C_Traits.GetTreeNodes, treeID)
    local s = {}
    if type(nodes) == "table" then
      for _, nodeID in ipairs(nodes) do
        local info = MK.Call(C_Traits.GetNodeInfo, configID, nodeID)
        local r = type(info) == "table" and MK.Safe(info.currentRank) or nil
        if type(r) == "number" then found = true; s[#s + 1] = digit(r) end
      end
    end
    tabs[t] = table.concat(s)
  end
  if found then return joinTabs(tabs) end
end

local PATHS = { viaGlobals, viaSpecInfo, viaTraits }

-- Returns talentString, apiLevel or nil.
function M.ReadTalents()
  for api, fn in ipairs(PATHS) do
    local ok, s = pcall(fn)
    if ok and type(s) == "string" and s ~= "" then return MK.Util.Truncate(s, MAX_LEN), api end
  end
end

function M.SnapshotTalents()
  local s, api = M.ReadTalents()
  if not s then return end
  local row = Agg.LevelRow()
  row.talents, row.talentApi = s, api
end

---------------------------------------------------------------------------
-- Level-up stat snapshot

local function num(fn, ...)
  local v = MK.Call(fn, ...)
  if type(v) == "number" then return MK.Util.Round(v, 2) end
end

local function snapshotStats()
  local row = Agg.LevelRow()
  local avg, equipped = MK.Call(GetAverageItemLevel)
  row.ilvl = type(equipped) == "number" and MK.Util.Round(equipped, 1) or (type(avg) == "number" and MK.Util.Round(avg, 1) or nil)
  row.dodge, row.parry, row.block, row.crit = num(GetDodgeChance), num(GetParryChance), num(GetBlockChance), num(GetCritChance)
end

---------------------------------------------------------------------------
-- Professions

-- Returns array of { name, rank, header } from C_SkillInfo (table or multi-return) or the legacy globals.
function M.ReadSkills()
  local list = {}
  local S = C_SkillInfo
  local n = S and MK.Call(S.GetNumSkillLines)
  if type(n) == "number" and n > 0 then
    for i = 1, n do
      local r = { MK.Call(S.GetSkillLineInfo, i) }
      local first = r[1]
      if type(first) == "table" then
        local name = MK.Safe(first.skillLineName) or MK.Safe(first.name)
        local rank = MK.Safe(first.skillRank) or MK.Safe(first.rank)
        list[#list + 1] = { name = name, rank = rank, header = MK.Safe(first.isHeader) and true or false }
      elseif first ~= nil then
        list[#list + 1] = { name = first, rank = r[4], header = r[2] and true or false }
      end
    end
    if #list > 0 then return list end
  end
  if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    n = MK.Call(GetNumSkillLines)
    for i = 1, type(n) == "number" and n or 0 do
      local name, header, _, rank = MK.Call(GetSkillLineInfo, i)
      if name ~= nil then list[#list + 1] = { name = name, rank = rank, header = header and true or false } end
    end
  end
  return list
end

local lastRanks, baselined = {}, false

function M.SyncSkills()
  local list = M.ReadSkills()
  local ranks, any = {}, false
  for _, s in ipairs(list) do
    if not s.header and type(s.name) == "string" and type(s.rank) == "number" and s.rank > 0 then
      ranks[s.name] = s.rank
      any = true
      local old = lastRanks[s.name]
      if baselined and old and s.rank > old then Agg.Add("prof", s.rank - old, s.name) end
    end
  end
  if not any then return end
  lastRanks, baselined = ranks, true
end

---------------------------------------------------------------------------

local function snapshotSoon() A:Debounce("talents", 1, M.SnapshotTalents) end
local function skillsSoon() A:Debounce("skills", 0.5, M.SyncSkills) end

function M:OnLogin()
  A:After(3, function() M.SnapshotTalents(); M.SyncSkills() end)
end

A:On("PLAYER_LEVEL_UP", function() snapshotSoon(); A:After(1, snapshotStats) end)
A:On("CHARACTER_POINTS_CHANGED", snapshotSoon)
A:On("TRAIT_CONFIG_UPDATED", snapshotSoon)
A:On("PLAYER_TALENT_UPDATE", snapshotSoon)
A:On("SKILL_LINES_CHANGED", skillsSoon)
A:On("CHAT_MSG_SKILL", skillsSoon)
