local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Data/GlobalStringsFallback", "Strings" }) do
  dofile("MetaKit/" .. f .. ".lua")
end
local MK = MetaKit

T.test("GS prefers client global then fallback", function()
  T.eq(MK.GS("DUEL_COUNTDOWN"), "Duel starting: %d")
  local saved = _G.DUEL_COUNTDOWN
  _G.DUEL_COUNTDOWN = nil
  T.eq(MK.GS("DUEL_COUNTDOWN"), "Duel starting: %d")
  _G.DUEL_COUNTDOWN = "Custom %d"
  T.eq(MK.GS("DUEL_COUNTDOWN"), "Custom %d")
  T.eq(MK.Match("DUEL_COUNTDOWN", "Custom 3"), "3")
  _G.DUEL_COUNTDOWN = saved
  T.eq(MK.GS("NO_SUCH_STRING"), nil)
end)

T.test("Pattern compiles, escapes and caches", function()
  local p = MK.Pattern("DUEL_WINNER_KNOCKOUT")
  T.eq(p.pattern, "^(.+) has defeated (.+) in a duel$")
  T.eq(p.order[1], 1); T.eq(p.order[2], 2)
  T.ok(MK.Pattern("DUEL_WINNER_KNOCKOUT") == p, "cached")
  local r = MK.Pattern("DUEL_WINNER_RETREAT")
  T.eq(r.pattern, "^(.+) has fled from (.+) in a duel$")
  T.eq(r.order[1], 2); T.eq(r.order[2], 1)
  T.eq(MK.Pattern("COMBATLOG_XPGAIN_FIRSTPERSON").pattern, "^(.+) dies, you gain (%-?%d+) experience%.$")
  T.eq(MK.Pattern("NO_SUCH_STRING"), nil)
end)

T.test("knockout and retreat return winner first", function()
  local w, l = MK.Match("DUEL_WINNER_KNOCKOUT", "Arwen has defeated Boromir in a duel")
  T.eq(w, "Arwen"); T.eq(l, "Boromir")
  w, l = MK.Match("DUEL_WINNER_RETREAT", "Boromir has fled from Arwen in a duel")
  T.eq(w, "Arwen"); T.eq(l, "Boromir")
end)

T.test("names with hyphens, apostrophes, realms", function()
  local w, l = MK.Match("DUEL_WINNER_KNOCKOUT", "Jean-Luc has defeated O'Brien-Nor Realm in a duel")
  T.eq(w, "Jean-Luc"); T.eq(l, "O'Brien-Nor Realm")
  w, l = MK.Match("DUEL_WINNER_RETREAT", "Du-Val-Ragnaros has fled from A'b-Realm in a duel")
  T.eq(w, "A'b-Realm"); T.eq(l, "Du-Val-Ragnaros")
end)

T.test("countdown and xp variants", function()
  T.eq(MK.Match("DUEL_COUNTDOWN", "Duel starting: 3"), "3")
  local mob, xp = MK.Match("COMBATLOG_XPGAIN_FIRSTPERSON", "Young Wolf dies, you gain 54 experience.")
  T.eq(mob, "Young Wolf"); T.eq(xp, "54")
  T.eq(MK.Match("COMBATLOG_XPGAIN_FIRSTPERSON", "Young Wolf dies, you gain 54 experience. (+5 group bonus)"), nil)
  local a, b, c, d = MK.Match("COMBATLOG_XPGAIN_EXHAUSTION1", "Boar dies, you gain 100 experience. (Rested exp +50 bonus)")
  T.eq(a, "Boar"); T.eq(b, "100"); T.eq(c, "Rested"); T.eq(d, "+50")
  a, b, c = MK.Match("COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "Boar dies, you gain 12 experience. (+3 group bonus)")
  T.eq(c, "3")
  T.eq(MK.Match("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "You gain 77 experience."), "77")
end)

T.test("no placeholders returns true, mismatch nil", function()
  T.eq(MK.Match("ERR_DUEL_CANCELLED", "Duel canceled."), true)
  T.eq(MK.Match("ERR_DUEL_CANCELLED", "Something else"), nil)
  T.eq(MK.Match("DUEL_COUNTDOWN", "Hello"), nil)
end)

T.test("secret and non-string input is nil", function()
  T.eq(MK.Match("DUEL_COUNTDOWN", T.Secret("Duel starting: 3")), nil)
  T.eq(MK.Match("DUEL_COUNTDOWN", nil), nil)
  T.eq(MK.Match("DUEL_COUNTDOWN", 42), nil)
  T.eq(MK.Match("NO_SUCH_STRING", "x"), nil)
end)

T.done()
