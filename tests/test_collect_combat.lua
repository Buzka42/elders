-- Combat collector: fights, damage meter totals (secret values ignored), kills, elites, mob level delta, casts.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local P = T.units.player

local function meter(dmg, taken, heal, dur)
  T.meter = {
    [0] = { durationSeconds = dur, combatSources = { { isLocalPlayer = false, totalAmount = 9999 }, { isLocalPlayer = true, totalAmount = dmg } } },
    [7] = { durationSeconds = dur, combatSources = { { isLocalPlayer = true, totalAmount = taken } } },
    [2] = { durationSeconds = dur, combatSources = { { isLocalPlayer = true, totalAmount = heal } } },
    [4] = { durationSeconds = dur, combatSources = { { isLocalPlayer = true, totalAmount = 7 } } },
    [5] = { durationSeconds = dur, combatSources = { { isLocalPlayer = true, totalAmount = 2 } } },
    [6] = { durationSeconds = dur, combatSources = { { isLocalPlayer = true, totalAmount = 1 } } },
  }
end

local function fight(sec)
  T.combat = true; T.Fire("PLAYER_REGEN_DISABLED"); T.Advance(sec)
  T.combat = false; T.Fire("PLAYER_REGEN_ENABLED")
end

T.test("a fight is counted, binned, and the meter is read after 0.5 s", function()
  local b = Agg.Bracket()
  local done
  ns.A:Listen("FIGHT_END", function(info) done = info end)
  meter(500, 120, 40, 12)
  fight(12)
  T.Advance(0.6)
  T.eq(b.dmg, 500); T.eq(b.taken, 120); T.eq(b.heal, 40); T.eq(b.absorb, 7); T.eq(b.interrupts, 2); T.eq(b.dispels, 1)
  T.eq(b.meterSec, 12)
  T.Advance(4)
  T.eq(b.fights, 1); T.near(b.fightSec, 12, 0.01); T.eq(b.fightHist[3], 1)
  T.ok(done and done.dur >= 12, "FIGHT_END fired")
end)

T.test("fights closer than 3 s merge", function()
  local b = Agg.Bracket()
  local f0 = b.fights
  meter(0, 0, 0, 1)
  fight(4); T.Advance(1.5); fight(3); T.Advance(5)
  T.eq(b.fights, f0 + 1)
  T.near(b.fightSec, 12 + 4 + 1.5 + 3, 0.01)
  T.eq(b.fightHist[2], 1) -- 8.5 s -> <10
  fight(2); T.Advance(5)
  T.eq(b.fights, f0 + 2)
end)

T.test("secret meter values are ignored", function()
  local b = Agg.Bracket()
  local d0, m0 = b.dmg, b.meterSec
  T.meter = { [0] = { durationSeconds = 5, combatSources = { { isLocalPlayer = true, totalAmount = T.Secret(900) } } } }
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0); T.eq(b.meterSec, m0)
  T.meter = { [0] = { durationSeconds = T.Secret(5), combatSources = { { isLocalPlayer = T.Secret(true), totalAmount = 10 } } } }
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0)
  T.noErrors()
end)

T.test("pvp fights (enemy player target, duel, bg) skip the meter", function()
  local b = Agg.Bracket()
  local d0 = b.dmg
  meter(300, 0, 0, 5)
  T.units.target = { name = "Gank", class = "ROGUE", isPlayer = true, enemy = true, level = 10, guid = "Player-1-3" }
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0, "enemy player")
  T.units.target = nil
  T.Fire("DUEL_INBOUNDS")
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0, "duel")
  T.Fire("DUEL_FINISHED")
  T.instance = { inInstance = true, type = "pvp", id = 30 }
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0, "battleground")
  T.instance = { inInstance = false, type = "none" }
  fight(5); T.Advance(5)
  T.eq(b.dmg, d0 + 300, "pve again")
end)

T.test("kills via PARTY_KILL only count the player's own", function()
  local b = Agg.Bracket()
  local k0 = b.kills
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-100-0001")
  T.Fire("PARTY_KILL", "Player-1-9999", "Creature-0-1-2-3-100-0002")
  T.Fire("PARTY_KILL", T.Secret("x"), "Creature-0-1-2-3-100-0003")
  T.eq(b.kills, k0 + 1)
end)

T.test("solo elite kills use the target LRU and group state", function()
  local b = Agg.Bracket()
  T.units.target = { name = "Big", isPlayer = false, enemy = true, level = 13, guid = "Creature-0-1-2-3-200-0001", classification = "elite" }
  T.Fire("PLAYER_TARGET_CHANGED")
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-200-0001")
  T.eq(b.eliteSolo, 1)
  T.group = { size = 3, raid = false }
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-200-0001")
  T.eq(b.eliteSolo, 1, "not solo")
  T.group = { size = 0, raid = false }
  T.Fire("PARTY_KILL", P.guid, "Creature-0-1-2-3-999-0001")
  T.eq(b.eliteSolo, 1, "unknown guid")
end)

T.test("mob level delta histogram (clamped, once per guid, out of combat)", function()
  local b = Agg.Bracket()
  local function tgt(lvl, guid)
    T.units.target = { name = "Mob", isPlayer = false, enemy = true, level = lvl, guid = guid, classification = "normal" }
    T.Fire("PLAYER_TARGET_CHANGED")
  end
  tgt(10, "Creature-0-0-0-0-1-a")   -- delta 0 -> index 6
  tgt(10, "Creature-0-0-0-0-1-a")   -- same guid, ignored
  tgt(12, "Creature-0-0-0-0-1-b")   -- +2 -> 8
  tgt(30, "Creature-0-0-0-0-1-c")   -- clamp +5 -> 11
  tgt(1, "Creature-0-0-0-0-1-d")    -- clamp -5 -> 1
  tgt(-1, "Creature-0-0-0-0-1-e")   -- skull -> +5 -> 11
  T.eq(b.mobDelta[6], 1); T.eq(b.mobDelta[8], 1); T.eq(b.mobDelta[11], 2); T.eq(b.mobDelta[1], 1)
  T.combat = true
  tgt(10, "Creature-0-0-0-0-1-f")
  T.combat = false
  T.eq(b.mobDelta[6], 1, "not sampled in combat")
  T.units.target = { name = "Friend", isPlayer = true, enemy = false, level = 10, guid = "Player-1-5" }
  T.Fire("PLAYER_TARGET_CHANGED")
  T.eq(b.mobDelta[6], 1, "players are skipped")
  T.units.target = nil
end)

T.test("spell casts feed role / interrupt / dispel / cc / taunt counters", function()
  local b = Agg.Bracket()
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 6552)  -- Pummel
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 355)   -- Taunt (tank + taunt)
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 5246)  -- Intimidating Shout (cc)
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 71)    -- Defensive Stance (tank)
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 12345) -- unrelated
  T.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", T.Secret(1))
  T.eq(b.interruptCasts, 1); T.eq(b.tauntCasts, 1); T.eq(b.ccCasts, 1); T.eq(b.roleCasts.tank, 2); T.eq(b.roleCasts.heal, 0)
  T.noErrors()
end)

T.done()
