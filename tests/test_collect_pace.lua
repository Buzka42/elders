-- Pace collector: xp sources, level wrap, rested bonus, level-up + /played.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local P = T.units.player

T.test("login /played is captured silently", function()
  T.Advance(1)
  T.eq(ns.char.played.total, 3600)
  T.eq(ns.char.played.level, 600)
end)

T.test("kill xp via chat, remainder is other (either order)", function()
  local b = Agg.Bracket()
  P.xp = 100; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 60 experience.")
  T.Advance(1)
  T.eq(b.xp, 100); T.eq(b.xpKill, 60); T.eq(b.killsXP, 1); T.eq(b.xpOther, 40)
  -- message first, update second
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 50 experience.")
  P.xp = 150; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Advance(1)
  T.eq(b.xp, 150); T.eq(b.xpKill, 110); T.eq(b.killsXP, 2); T.eq(b.xpOther, 40)
end)

T.test("group bonus and unnamed (non-kill) messages", function()
  local b = Agg.Bracket()
  local k0, o0 = b.killsXP, b.xpOther
  P.xp = 200; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 30 experience. (+5 group bonus)")
  T.Advance(1)
  T.eq(b.killsXP, k0 + 1)
  P.xp = 230; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 30 experience.")
  T.Advance(1)
  T.eq(b.killsXP, k0 + 1, "unnamed is not a kill")
  T.eq(b.xpOther, o0 + 20 + 30)
end)

T.test("quest xp from QUEST_TURNED_IN", function()
  local b = Agg.Bracket()
  local q0, x0 = b.quests, b.xpQuest
  P.xp = 430; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Fire("QUEST_TURNED_IN", 77, 200, 50)
  T.Advance(1)
  T.eq(b.quests, q0 + 1); T.eq(b.xpQuest, x0 + 200)
  -- reversed order
  T.Fire("QUEST_TURNED_IN", 78, 100, 0)
  P.xp = 530; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Advance(1)
  T.eq(b.xpQuest, x0 + 300)
end)

T.test("rested bonus is parsed from the exhaustion variants", function()
  local b = Agg.Bracket()
  P.xp = 650; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 120 experience. (+60 exp Rested bonus)")
  T.Advance(1)
  T.eq(b.xpRested, 60)
end)

T.test("secret chat text is ignored", function()
  local b = Agg.Bracket()
  local k0 = b.killsXP
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", T.Secret("Boar dies, you gain 60 experience."))
  T.eq(b.killsXP, k0)
  T.noErrors()
end)

T.test("zone xp is credited to the current map", function()
  local z = Agg.Bracket().zones[T.map.id]
  T.ok(z and z.xp > 0, "zone xp")
end)

T.test("level wrap uses the previous max", function()
  local b = Agg.Bracket()
  local before = b.xp
  P.xp = 900; T.Fire("PLAYER_XP_UPDATE", "player")
  T.eq(b.xp, before + 250)
  P.xp, P.xpMax = 100, 1500
  T.Fire("PLAYER_XP_UPDATE", "player")
  T.eq(b.xp, before + 250 + 200)
  P.xpMax = 1000
  T.Advance(1)
end)

T.test("level-up: sec per level, /played, outbox row, messages", function()
  local fired, due = {}, {}
  ns.A:Listen("LEVEL_UP", function(l) fired[#fired + 1] = l end)
  ns.A:Listen("RITUAL_DUE", function(n) due[#due + 1] = n end)
  P.level = 11
  T.played = { total = 5000, level = 700 }
  T.Fire("PLAYER_LEVEL_UP", 11)
  T.eq(fired[1], 11); T.eq(#due, 0)
  T.eq(Agg.Level(), 11)
  T.Advance(5)
  T.eq(Agg.LevelRow(10).sec, 700)
  T.eq(ns.char.played.total, 5000)
  local rows = EldersDB.outbox.rows
  local last = rows[#rows]
  T.eq(last.kind, "levelup"); T.eq(last.data.level, 11); T.eq(last.data.sec, 700)
end)

T.test("level % 10 == 0 fires RITUAL_DUE for the finished bracket", function()
  local due = {}
  ns.A:Listen("RITUAL_DUE", function(n) due[#due + 1] = n end)
  T.played = { total = 9000, level = 1 }
  T.Fire("PLAYER_LEVEL_UP", 20)
  T.eq(due[1], 2)
  T.Advance(5)
  T.eq(Agg.Level(), 20)
  T.noErrors()
end)

T.done()
