-- Build collector: talent snapshot through each fallback path, professions, level-up stat snapshot.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local B = ns.A:GetModule("Build")

local saved = { GetNumTalentTabs = GetNumTalentTabs, GetTalentInfo = GetTalentInfo, GetNumTalents = GetNumTalents,
  GetNumSkillLines = GetNumSkillLines, GetSkillLineInfo = GetSkillLineInfo }

local function setTalents()
  T.talents = {
    { name = "Arms", points = 8, talents = { { name = "a", rank = 0, tier = 1, column = 1 }, { name = "b", rank = 5, tier = 1, column = 2 },
      { name = "c", rank = 0, tier = 2, column = 1 }, { name = "d", rank = 3, tier = 2, column = 2 }, { name = "e", rank = 2, tier = 3, column = 1 } } },
    { name = "Fury", points = 0, talents = { { name = "f", rank = 0, tier = 1, column = 1 }, { name = "g", rank = 0, tier = 1, column = 2 } } },
    { name = "Protection", points = 1, talents = { { name = "h", rank = 1, tier = 1, column = 1 } } },
  }
end

T.test("path 1: legacy globals", function()
  setTalents()
  local s, api = B.ReadTalents()
  T.eq(s, "05032/00/1"); T.eq(api, 1)
end)

local function disableGlobals() GetNumTalentTabs, GetTalentInfo, GetNumTalents = nil, nil, nil end

T.test("path 2a: C_SpecializationInfo by talentIndex", function()
  disableGlobals()
  C_SpecializationInfo = { GetTalentInfo = function(q)
    local tab = T.talents[q.specializationIndex]
    local t = tab and q.talentIndex and tab.talents[q.talentIndex]
    if t then return { rank = t.rank, maxRank = 5 } end
  end }
  local s, api = B.ReadTalents()
  T.eq(s, "05032/00/1"); T.eq(api, 2)
end)

T.test("path 2b: C_SpecializationInfo by tier/column, currentRank", function()
  C_SpecializationInfo = { GetTalentInfo = function(q)
    if q.talentIndex then return nil end
    local tab = T.talents[q.specializationIndex]
    for _, t in ipairs(tab and tab.talents or {}) do
      if t.tier == q.tier and t.column == q.column then return { currentRank = t.rank } end
    end
  end }
  local s, api = B.ReadTalents()
  T.eq(s, "05032/00/1"); T.eq(api, 2)
end)

T.test("path 3: C_Traits tree nodes", function()
  C_SpecializationInfo = nil
  C_ClassTalents = { GetActiveConfigID = function() return 42 end }
  local nodes = { [1] = { 1, 2, 3 }, [2] = { 4, 5 } }
  local ranks = { [1] = 0, [2] = 2, [3] = 1, [4] = 0, [5] = 5 }
  C_Traits = {
    GetConfigInfo = function(id) if id == 42 then return { treeIDs = { 1, 2 } } end end,
    GetTreeNodes = function(tree) return nodes[tree] end,
    GetNodeInfo = function(cfg, node) return { currentRank = ranks[node] } end,
  }
  local s, api = B.ReadTalents()
  T.eq(s, "021/05"); T.eq(api, 3)
end)

T.test("nothing available -> no snapshot, no error", function()
  C_ClassTalents, C_Traits = nil, nil
  T.eq(B.ReadTalents(), nil)
  B.SnapshotTalents()
  T.noErrors()
end)

T.test("snapshot is stored on the level row with the api marker, debounced after events", function()
  GetNumTalentTabs, GetTalentInfo, GetNumTalents = saved.GetNumTalentTabs, saved.GetTalentInfo, saved.GetNumTalents
  setTalents()
  T.Fire("CHARACTER_POINTS_CHANGED", -1)
  T.Fire("PLAYER_TALENT_UPDATE")
  T.Fire("TRAIT_CONFIG_UPDATED")
  local row = Agg.LevelRow()
  T.eq(row.talents, nil)
  T.Advance(1.1)
  T.eq(row.talents, "05032/00/1"); T.eq(row.talentApi, 1)
end)

T.test("level-up stat snapshot", function()
  T.units.player.level = 11
  T.Fire("PLAYER_LEVEL_UP", 11)
  T.Advance(3)
  local row = Agg.LevelRow(11)
  T.eq(row.ilvl, 10); T.eq(row.dodge, 5); T.eq(row.parry, 5); T.eq(row.block, 0); T.eq(row.crit, 5)
  T.eq(row.talents, "05032/00/1")
end)

T.test("professions via legacy globals: baseline, then deltas", function()
  GetNumSkillLines, GetSkillLineInfo = saved.GetNumSkillLines, saved.GetSkillLineInfo
  T.skills = { { name = "Professions", header = true }, { name = "Mining", rank = 50, max = 75 }, { name = "Herbalism", rank = 10, max = 75 } }
  B.SyncSkills()
  T.eq(next(Agg.Bracket().prof), nil, "baseline only")
  T.skills[2].rank = 53; T.skills[3].rank = 11
  T.Fire("SKILL_LINES_CHANGED"); T.Advance(1)
  T.eq(Agg.Bracket().prof.Mining, 3); T.eq(Agg.Bracket().prof.Herbalism, 1)
  T.skills[2].rank = 54
  T.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 54."); T.Advance(1)
  T.eq(Agg.Bracket().prof.Mining, 4)
  T.skills[2].rank = 54
  T.Fire("SKILL_LINES_CHANGED"); T.Advance(1)
  T.eq(Agg.Bracket().prof.Mining, 4, "no change")
end)

T.test("professions via C_SkillInfo returning a table", function()
  GetNumSkillLines, GetSkillLineInfo = nil, nil
  local lines = { { skillLineName = "Professions", isHeader = true }, { skillLineName = "Mining", skillRank = 54 }, { skillLineName = "Skinning", skillRank = 5 } }
  C_SkillInfo = { GetNumSkillLines = function() return #lines end, GetSkillLineInfo = function(i) return lines[i] end }
  B.SyncSkills()
  lines[2].skillRank = 60; lines[3].skillRank = 6
  B.SyncSkills()
  T.eq(Agg.Bracket().prof.Mining, 4 + 6); T.eq(Agg.Bracket().prof.Skinning, 1)
end)

T.test("professions via C_SkillInfo returning multiple values", function()
  local rows = { { "Professions", true, true, 0 }, { "Mining", false, false, 60 }, { "Skinning", false, false, 6 } }
  C_SkillInfo = { GetNumSkillLines = function() return #rows end, GetSkillLineInfo = function(i) return unpack(rows[i]) end }
  B.SyncSkills()
  rows[2][4] = 65
  B.SyncSkills()
  T.eq(Agg.Bracket().prof.Mining, 10 + 5)
  rows[2][1] = T.Secret("Mining")   -- secret names are skipped
  B.SyncSkills()
  T.noErrors()
end)

T.done()
