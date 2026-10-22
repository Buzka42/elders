-- Dungeon collector: runs, clears via final boss kill / encounter, wipes, deaths, group forming (LFG) heuristic.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local P = T.units.player

local function enter(id) T.instance = { inInstance = true, type = "party", id = id, name = "Dungeon" .. id }; T.Fire("PLAYER_ENTERING_WORLD", false, false) end
local function leave() T.instance = { inInstance = false, type = "none" }; T.Fire("PLAYER_ENTERING_WORLD", false, false) end
local function rec(id) return Agg.Bracket().dungeons[id] end

T.test("group forming time and enter time (1 -> 2 -> 5 -> instance)", function()
  T.group = { size = 2, raid = false }; T.Fire("GROUP_ROSTER_UPDATE")
  T.Advance(30)
  T.group = { size = 5, raid = false }; T.Fire("GROUP_ROSTER_UPDATE")
  T.Advance(20)
  enter(36)
  local lfg = Agg.Bracket().lfg
  T.eq(lfg.n, 1); T.near(lfg.formSec, 30, 0.01); T.near(lfg.enterSec, 50, 0.01)
end)

T.test("entering a party instance starts a run", function()
  T.eq(rec(36).runs, 1)
  enter(36) -- loading screen inside the same instance does not restart it
  T.eq(rec(36).runs, 1)
end)

T.test("death inside the run is recorded", function()
  P.dead = true; T.Fire("PLAYER_DEAD"); P.dead = false
  T.eq(rec(36).deaths, 1)
end)

T.test("wipe: whole party dead, latched, 30 s debounce", function()
  for i = 1, 4 do T.units["party" .. i] = { name = "M" .. i, class = "MAGE", level = 10, guid = "Player-1-" .. i, isPlayer = true } end
  P.dead = true
  T.units.party1.dead, T.units.party2.dead, T.units.party3.dead = true, true, true
  T.Advance(3)
  T.eq(rec(36).wipes, 0, "party4 alive")
  T.units.party4.dead = true
  T.Advance(5)
  T.eq(rec(36).wipes, 1)
  T.Advance(60)
  T.eq(rec(36).wipes, 1, "same wipe is not counted again")
  P.dead = false; T.Advance(2)
  P.dead = true; T.Advance(2)
  T.eq(rec(36).wipes, 2, "new wipe after a recovery")
  P.dead = false
  for i = 1, 4 do T.units["party" .. i] = nil end
end)

T.test("non-final boss kill is not a clear; leaving fires DUNGEON_DONE", function()
  local done
  ns.A:Listen("DUNGEON_DONE", function(r) done = r end)
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-4000-0001")
  leave()
  T.eq(rec(36).clears, 0)
  T.ok(done and done.cleared == false and done.id == 36, "done event")
end)

T.test("final boss kill by creature id -> clear with clear time", function()
  local done
  ns.A:Listen("DUNGEON_DONE", function(r) done = r end)
  T.Advance(10)
  enter(36)
  T.Advance(100)
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-639-0001") -- Edwin VanCleef
  T.Advance(50)
  leave()
  local r = rec(36)
  T.eq(r.runs, 2); T.eq(r.clears, 1); T.near(r.clearSec, 100, 0.01)
  T.ok(done.cleared and done.bosses == 1, "done cleared")
end)

T.test("final boss via ENCOUNTER_END / BOSS_KILL with optional data", function()
  ns.Data.Dungeons[33].encounterIDs = { 438 }
  ns.Data.Dungeons[47].finalBossNames = { "Charlga Razorflank" }
  enter(33); T.Advance(40)
  T.Fire("ENCOUNTER_END", 438, "Archmage Arugal", 1, 5, 0) -- wipe: ignored
  leave(); T.eq(rec(33).clears, 0)
  enter(33); T.Advance(40)
  T.Fire("ENCOUNTER_END", 438, "Archmage Arugal", 1, 5, 1)
  T.Fire("BOSS_KILL", 438, "Archmage Arugal") -- duplicate of the same kill
  T.Advance(5); leave()
  T.eq(rec(33).clears, 1); T.near(rec(33).clearSec, 40, 0.01); T.eq(rec(33).bosses, 1)
  enter(47); T.Advance(30)
  T.Fire("BOSS_KILL", 1, "charlga razorflank")
  leave(); T.eq(rec(47).clears, 1)
end)

T.test("unknown dungeon ids are tracked, raids and open world are not", function()
  enter(9999); T.eq(rec(9999).runs, 1); leave()
  T.instance = { inInstance = true, type = "raid", id = 409 }; T.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(rec(409), nil)
  leave()
  T.noErrors()
end)

T.test("logout inside a run closes it", function()
  enter(34); T.Advance(5)
  T.Fire("PLAYER_LOGOUT")
  leave()
  T.eq(rec(34).runs, 1)
  T.noErrors()
end)

T.done()
