-- Social collector: ritual rating / votes / insight rows, once-per-bracket rule, skip, ns.Insights.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg
local A = ns.A

local function rows(kind)
  local out = {}
  for _, r in ipairs(EldersDB.outbox.rows) do if r.kind == kind then out[#out + 1] = r end end
  return out
end

T.test("submit writes the ritual, rating, votes and a cleaned, truncated insight", function()
  local text = "  Line one\nline|cffff0000 two\t" .. string.rep("x", 400)
  A:Fire("RITUAL_SUBMIT", 1, 4, 3, { { id = "i1", v = 1 }, { id = "i2", v = -1 }, { id = "i3", v = 5 } }, text)
  local b = Agg.Bracket(1)
  T.eq(b.ritual.pve, 4); T.eq(b.ritual.pvp, 3); T.ok(b.ritual.at, "at")
  local rating = rows("rating")
  T.eq(#rating, 1); T.eq(rating[1].data.bracket, 1); T.eq(rating[1].data.pve, 4); T.eq(rating[1].data.class, "WARRIOR")
  T.eq(#rows("vote"), 2)
  T.eq(EldersDB.votes.i1, 1); T.eq(EldersDB.votes.i2, -1); T.eq(EldersDB.votes.i3, nil, "invalid vote value")
  local ins = rows("insight")
  T.eq(#ins, 1)
  T.eq(#ins[1].data.text, 280)
  T.ok(not ins[1].data.text:find("[|\n\t]"), "control chars removed")
  T.eq(ins[1].data.text:sub(1, 20), "Line one linecffff00")
end)

T.test("one rating per character per bracket; votes dedupe across the account", function()
  A:Fire("RITUAL_SUBMIT", 1, 1, 1, { { id = "i1", v = -1 }, { id = "i4", v = 1 } }, "again")
  T.eq(Agg.Bracket(1).ritual.pve, 4)
  T.eq(#rows("rating"), 1); T.eq(#rows("insight"), 1)
  T.eq(#rows("vote"), 3); T.eq(EldersDB.votes.i1, 1)
end)

T.test("ratings are clamped; nil stars allowed", function()
  A:Fire("RITUAL_SUBMIT", 2, 9, nil, {}, "")
  T.eq(Agg.Bracket(11).ritual.pve, 5); T.eq(Agg.Bracket(11).ritual.pvp, nil)
  T.eq(#rows("insight"), 1)
end)

T.test("skip marks the bracket", function()
  A:Fire("RITUAL_SKIP", 3)
  T.eq(Agg.Bracket(21).ritual.skipped, true)
  T.eq(Agg.Bracket(21).ritual.pve, nil)
  A:Fire("RITUAL_SKIP", "bad")
  T.noErrors()
end)

T.test("ns.Insights: unvoted, random, capped", function()
  T.eq(#ns.Insights("WARRIOR", 3), 0, "no data addon")
  WorldOfMetaData = { elders = { insights = { WARRIOR = {
    { id = "i1", text = "voted", author = "a", votes = 3 },
    { id = "i2", text = "voted", author = "a", votes = 3 },
    { id = "n1", text = "one", author = "a", votes = 1 }, { id = "n2", text = "two", author = "b", votes = 2 },
    { id = "n3", text = "three", author = "c", votes = 0 }, { id = "n4", text = "four", author = "d", votes = 5 },
  } } } }
  local got = ns.Insights("WARRIOR", 3)
  T.eq(#got, 3)
  local seen = {}
  for _, g in ipairs(got) do T.ok(g.id:sub(1, 1) == "n", "unvoted only"); T.ok(not seen[g.id], "distinct"); seen[g.id] = true end
  T.eq(#ns.Insights("WARRIOR", 10), 4)
  T.eq(#ns.Insights("MAGE", 3), 0)
  local orders = {}
  for _ = 1, 30 do local o = ns.Insights("WARRIOR", 4); orders[o[1].id .. o[2].id] = true end
  local n = 0 for _ in pairs(orders) do n = n + 1 end
  T.ok(n > 1, "order is random")
end)

T.done()
