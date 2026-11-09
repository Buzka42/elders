-- MetaKit Ext: the public extension registry (docs/ADDON_API.md). The whole Elders addon loads from its TOC (so the TOC
-- line for Ext.lua is covered), then the example extension addon loads on top of it, as the client would via OptionalDeps.
local stubPath = os.getenv("WOW_STUB") or "tests/wow_stub.lua"
local T = dofile(stubPath)
local root = stubPath:match("^(.*)/tests/wow_stub.lua$") or "."

T.LoadAddon(root .. "/Elders/Elders.toc")
local MK = MetaKit
local Ext = MK.Ext

T.test("Elders TOC loads Ext v1", function()
  T.ok(Ext, "MK.Ext")
  T.eq(Ext.VERSION, 1)
  T.ok(Ext.Compatible(1))
  T.eq(Ext.Compatible(2), false)
  T.eq(table.concat(Ext.Kinds(), ","), "market,narrator,row,section")
  T.ok(MetaKit.minor >= 2, "MetaKit MINOR bumped so an older embedded copy cannot shadow Ext")
end)

T.test("unknown kind and bad ids are refused, never raised", function()
  local ok, msg = Ext.Register("widget", "x", {})
  T.eq(ok, false); T.ok(msg:find("unknown kind", 1, true))
  T.eq((Ext.List("widget")), nil)
  for _, bad in ipairs({ "", "Upper", "1abc", "has space", "dash-ed", string.rep("a", 25) }) do
    ok = Ext.Register("narrator", bad, function() end)
    T.eq(ok, false, "id " .. bad)
  end
  T.eq((Ext.Register("narrator", nil, function() end)), false)
  T.eq((Ext.Register("market", "ok_id", nil)), false)
end)

T.test("market: validation, duplicate, outcomes builder and settle hook", function()
  T.eq((Ext.Register("market", "m_bad", { label = "x", outcomes = { "only one" } })), false)
  T.eq((Ext.Register("market", "m_bad", { label = "x", outcomes = { "a", "b" }, lockOn = "never" })), false)
  T.eq((Ext.Register("market", "m_bad", { outcomes = { "a", "b" } })), false)
  T.eq(Ext.Get("market", "m_bad"), nil)

  local ok, msg = Ext.Register("market", "coin", { label = "Coin", owner = "T", outcomes = { "Heads", "Tails" },
    settle = function(m, ev) if ev.type == "fight_end" then return ev.winner == "x" and 1 or 2 end end })
  T.ok(ok, msg)
  ok, msg = Ext.Register("market", "coin", { label = "Coin", outcomes = { "a", "b" } })
  T.eq(ok, false); T.ok(msg:find("already registered by T", 1, true), msg)

  local out = Ext.BuildOutcomes("coin", {})
  T.eq(#out, 2); T.eq(out[1].label, "Heads")
  local market = { outcomes = out }
  T.eq(Ext.Settle("coin", market, { type = "fight_end", winner = "x" }), 1)
  T.eq(Ext.Settle("coin", market, { type = "fight_end", winner = "y" }), 2)
  T.eq(Ext.Settle("coin", market, { type = "manual" }), nil)

  -- Hostile extensions: errors and out-of-range answers are contained.
  Ext.Register("market", "boom", { label = "Boom", outcomes = function() error("kaput") end,
    settle = function() error("kaput") end })
  local o, why = Ext.BuildOutcomes("boom", {})
  T.eq(o, nil); T.ok(why:find("kaput", 1, true))
  T.eq((Ext.Settle("boom", { outcomes = { {}, {} } }, {})), nil)
  Ext.Register("market", "wild", { label = "Wild", outcomes = { "a", "b" }, settle = function() return 9 end })
  T.eq((Ext.Settle("wild", { outcomes = { {}, {} } }, {})), nil)
  Ext.Register("market", "voider", { label = "V", outcomes = { "a", "b" }, settle = function() return false end })
  T.eq(Ext.Settle("voider", { outcomes = { {}, {} } }, {}), false)
  Ext.Register("market", "toomany", { label = "T", outcomes = function() return { "1", "2", "3", "4", "5", "6", "7", "8", "9" } end })
  T.eq((Ext.BuildOutcomes("toomany", {})), nil)
  Ext.Register("market", "long", { label = "L", outcomes = { string.rep("z", 40), "b" } })
  T.eq(#Ext.BuildOutcomes("long", {})[1].label, Ext.LIMITS.LABEL_MAX)
end)

T.test("row: charset, reserved core kinds, field validation and passthrough", function()
  T.eq((Ext.Register("row", "bet", { fields = { a = "string" } })), false)
  T.eq((Ext.Register("row", "Bad-Kind", { fields = { a = "string" } })), false)
  T.eq((Ext.Register("row", "empty", { fields = {} })), false)
  T.eq((Ext.Register("row", "badtype", { fields = { a = "table" } })), false)
  local ok, msg = Ext.Register("row", "x_tally", { owner = "T", fields = { name = "string", count = "number", live = "boolean" } })
  T.ok(ok, msg)
  T.eq((Ext.Register("row", "x_tally", { fields = { a = "string" } })), false)

  local pushed
  local addon = { Push = function(_, kind, data) pushed = { kind = kind, data = data }; return 7 end }
  T.eq(Ext.PushRow(addon, "x_tally", { name = "hi", count = 3, live = true }), 7)
  T.eq(pushed.kind, "x_tally"); T.eq(pushed.data.count, 3)
  pushed = nil
  T.eq((Ext.PushRow(addon, "x_tally", { name = 5 })), false)
  T.eq((Ext.PushRow(addon, "x_tally", { extra = 1 })), false)
  T.eq((Ext.PushRow(addon, "x_tally", { count = 0 / 0 })), false)
  T.eq((Ext.PushRow(addon, "nope", {})), false)
  T.eq(pushed, nil, "invalid rows never reach the outbox")
  Ext.PushRow(addon, "x_tally", { name = string.rep("n", 500) })
  T.eq(#pushed.data.name, Ext.LIMITS.STRING_MAX)
end)

T.test("narrator: function or table, category filter, broken provider skipped", function()
  T.ok(Ext.Register("narrator", "n_all", function(cat) return { "line for " .. cat } end))
  T.ok(Ext.Register("narrator", "n_kill", { categories = { "kill" }, lines = function() return { "boom", 5, "" } end }))
  T.ok(Ext.Register("narrator", "n_err", function() error("bad provider") end))
  T.eq((Ext.Register("narrator", "n_none", { lines = "no" })), false)
  local lines = Ext.NarratorLines("kill", {})
  T.eq(table.concat(lines, "|"), "line for kill|boom")
  T.eq(table.concat(Ext.NarratorLines("flee", {}), "|"), "line for flee")
end)

T.test("section: forwarded to the shared shell, no replacing an existing pane", function()
  T.eq((Ext.Register("section", "s_bad", { tab = "elders", label = "x" })), false)
  T.eq((Ext.Register("section", "s_bad", { label = "x", build = function() end })), false)
  local ok, msg = Ext.Register("section", "s_ok", { owner = "T", tab = "elders", label = "Mine", order = 77,
    build = function(parent) return parent end })
  T.ok(ok, msg)
  local forwarded
  for _, s in ipairs(MK.UI._sharedState.sections) do if s.id == "s_ok" then forwarded = s end end
  T.ok(forwarded, "section reached the shared shell queue")
  T.eq(forwarded.tab, "elders"); T.eq(forwarded.order, 77)
  -- The core Elders pane is already queued under this id: an extension may not take it over.
  ok, msg = Ext.Register("section", "overview", { tab = "elders", label = "Hijack", build = function() end })
  T.eq(ok, false); T.ok(msg:find("already has", 1, true), msg)
end)

T.test("example addon registers through OptionalDeps load order", function()
  T.eq(Ext.Get("market", "firstblood"), nil)
  T.LoadAddon(root .. "/examples/WomExampleMarket/WomExampleMarket.toc", { login = false })
  local markets, sections = Ext.List("market"), Ext.List("section")
  local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end
  T.ok(has(markets, "firstblood"), "firstblood in MK.Ext.List('market')")
  T.ok(has(sections, "example_market"), "example_market in MK.Ext.List('section')")
  T.eq(Ext.Get("market", "firstblood").owner, "WomExampleMarket")

  local out, why = Ext.BuildOutcomes("firstblood", {})
  T.eq(out, nil); T.ok(why:find("two fighters", 1, true))
  out = Ext.BuildOutcomes("firstblood", { a = "Alice-Realm", b = "Bob-Realm" })
  T.eq(out[1].label, "Alice first"); T.eq(out[2].ref, "Bob-Realm")
  local market = { outcomes = out }
  T.eq(Ext.Settle("firstblood", market, { type = "fight_end", firstBlood = "Bob-Realm" }), 2)
  T.eq(Ext.Settle("firstblood", market, { type = "fight_end" }), nil)
end)

T.test("example addon does nothing without MetaKit", function()
  local saved = _G.MetaKit
  _G.MetaKit = nil
  local chunk = assert(loadfile(root .. "/examples/WomExampleMarket/WomExampleMarket.lua"))
  chunk("WomExampleMarket", {})
  _G.MetaKit = saved
end)

T.noErrors()
T.done()
