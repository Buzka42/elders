-- Activity collector: 1 Hz buckets, zone/group/rested seconds, eat/drink aura detection, death -> ghost -> unghost.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local P = T.units.player

local function act() return Agg.Bracket().act end

T.test("idle seconds accumulate over T.Advance(10)", function()
  local b = Agg.Bracket()
  local s0, i0 = b.sec, act().idle
  T.Advance(10)
  T.eq(b.sec, s0 + 10); T.eq(act().idle, i0 + 10)
  T.eq(b.zones[T.map.id].sec, 10)
end)

T.test("state priority: moving, mounted, combat, taxi", function()
  local a = act()
  local m0 = a.moving
  T.speed = 7; T.Advance(3); T.eq(a.moving, m0 + 3)
  T.mounted = true; local mo0 = a.mounted; T.Advance(2); T.eq(a.mounted, mo0 + 2)
  T.combat = true; local c0 = a.combat; T.Advance(2); T.eq(a.combat, c0 + 2, "combat beats mounted")
  T.taxi = true; local t0 = a.taxi; T.Advance(2); T.eq(a.taxi, t0 + 2, "taxi beats combat")
  T.taxi, T.combat, T.mounted, T.speed = false, false, false, 0
end)

T.test("eat and drink from player auras (out of combat only)", function()
  local a = act()
  T.spellNames[433], T.spellNames[430] = "Food", "Drink"
  T.Fire("PLAYER_ENTERING_WORLD", false, false) -- names are rebuilt on zoning
  T.auras.player = { { name = "Drink", spellId = 99999 } }
  T.Fire("UNIT_AURA", "player")
  local d0 = a.drink
  T.Advance(4); T.eq(a.drink, d0 + 4)
  T.auras.player = { { name = "Well Fed", spellId = 1 }, { name = "Food", spellId = 99998 } }
  T.Fire("UNIT_AURA", "player")
  local e0 = a.eat
  T.Advance(3); T.eq(a.eat, e0 + 3)
  -- in combat the aura list is not read: flag stays, combat bucket wins
  T.combat = true; T.Fire("PLAYER_REGEN_DISABLED")
  T.auras.player = {}
  T.Fire("UNIT_AURA", "player")
  local c0 = a.combat
  T.Advance(2); T.eq(a.combat, c0 + 2)
  T.combat = false
  T.Fire("PLAYER_REGEN_ENABLED")
  local i0 = a.idle
  T.Advance(2); T.eq(a.idle, i0 + 2, "flags cleared after leaving combat")
end)

T.test("secret aura data is ignored", function()
  T.auras.player = { T.Secret({ name = "Food" }) }
  T.Fire("UNIT_AURA", "player")
  T.Advance(2)
  T.noErrors()
  T.auras.player = {}
  T.Fire("UNIT_AURA", "player")
end)

T.test("group and rested seconds", function()
  local b = Agg.Bracket()
  T.group = { size = 3, raid = false }
  T.rested = 500
  local g0, r0, s0 = b.groupSec, b.rested.sec, b.groupSizeSec
  T.Advance(5)
  T.eq(b.groupSec, g0 + 5); T.eq(b.groupSizeSec, s0 + 15); T.eq(b.rested.sec, r0 + 5)
  T.group = { size = 0, raid = false }; T.rested = nil
end)

T.test("death -> release -> corpse run -> unghost", function()
  local b = Agg.Bracket()
  local ctxs = {}
  ns.A:Listen("DEATH", function(c) ctxs[#ctxs + 1] = c end)
  local d0, dead0, ghost0 = b.deaths, b.deadSec, b.ghostSec
  P.dead = true; T.Fire("PLAYER_DEAD")
  T.Fire("PLAYER_DEAD") -- duplicate within 2 s is ignored
  T.eq(b.deaths, d0 + 1); T.eq(b.deathCtx.solo, 1); T.eq(Agg.LevelRow().deaths, 1)
  T.eq(ctxs[1].kind, "solo")
  T.Advance(5); T.eq(b.deadSec, dead0 + 5); T.eq(act().dead >= 5, true)
  P.dead = false; P.ghost = true; T.Fire("PLAYER_ALIVE")
  T.Advance(12); T.eq(b.ghostSec, ghost0 + 12)
  P.ghost = false; T.Fire("PLAYER_UNGHOST")
  T.eq(b.corpseRuns, 1); T.eq(b.spiritRes, 0)
  T.near(ctxs[1].runSec, 12, 1.01)
  T.near(ctxs[1].sitSec, 5, 1.01)
end)

T.test("spirit healer resurrection", function()
  local b = Agg.Bracket()
  T.Advance(3)
  P.dead = true; T.Fire("PLAYER_DEAD")
  T.Advance(1)
  P.dead = false; P.ghost = true; T.Fire("PLAYER_ALIVE")
  T.Advance(2)
  P.ghost = false; T.Fire("PLAYER_ALIVE")
  T.eq(b.spiritRes, 1)
  T.eq(b.corpseRuns, 1)
end)

T.test("death context: pvp target, group, dungeon", function()
  local b = Agg.Bracket()
  T.Advance(3)
  T.units.target = { name = "Gank", class = "ROGUE", isPlayer = true, enemy = true, level = 10, guid = "Player-1-2" }
  T.Fire("PLAYER_DEAD"); T.eq(b.deathCtx.pvp, 1)
  T.units.target = nil; P.dead = false; T.Advance(3)
  T.group = { size = 2, raid = false }
  T.Fire("PLAYER_DEAD"); T.eq(b.deathCtx.group, 1)
  T.Advance(3)
  T.instance = { inInstance = true, type = "party", id = 36 }
  T.Fire("PLAYER_DEAD"); T.eq(b.deathCtx.dungeon, 1)
  T.instance = { inInstance = false, type = "none" }; T.group = { size = 0, raid = false }
  T.noErrors()
end)

T.done()
