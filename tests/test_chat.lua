-- MK.Chat: the paced public-chat sink. Pacing, dedupe, per-scope cap, lockdown / blocked-instance silence, routes,
-- category toggles, queue limits, text hygiene, and two addons sharing one sink.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Chat" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit
local Chat = MK.Chat

local function setup(over)
  Chat.Wipe()
  T.chat = {}
  T.chatLocked = false
  T.instance = { inInstance = false, type = "none" }
  T.group = { size = 0, raid = false }
  LE_PARTY_CATEGORY_INSTANCE = nil
  local cfg = Chat.Defaults("bloodsports")
  for k, v in pairs(over or {}) do cfg[k] = v end
  Chat.Configure(cfg)
  T.Advance(60) -- previous test's dedupe window and queue are long gone
  return cfg
end

local function texts() local o = {} for i, c in ipairs(T.chat) do o[i] = c.text end return table.concat(o, "|") end

T.test("Defaults / Configure fill the shape in place and keep existing values", function()
  Chat.Wipe()
  local live = { interval = 4, cats = { elders = { route = "group" } } }
  T.ok(Chat.Configure(live) == live, "returns the live table")
  T.eq(live.interval, 4); T.eq(live.dedupe, 30); T.eq(live.cap, 30); T.eq(live.blocked.arena, true)
  T.eq(live.cats.elders.route, "group")
  local d = Chat.Defaults("x", { level = "headline" })
  T.eq(d.cats.x.on, true); T.eq(d.cats.x.route, "say"); T.eq(d.cats.x.level, "headline"); T.eq(d.interval, 2.5)
  T.eq(Chat.Configure(nil), nil)
  local ok, why = Chat.Say("nope", "hello")
  T.eq(ok, false); T.eq(why, "unknown")
end)

T.test("pacing: first line goes out at once, the rest one per interval, in order", function()
  setup()
  T.ok(Chat.Say("bloodsports", "one"))
  T.eq(texts(), "one"); T.eq(T.chat[1].chatType, "SAY")
  T.ok(Chat.Say("bloodsports", "two")); T.ok(Chat.Say("bloodsports", "three"))
  T.eq(#T.chat, 1); T.eq(Chat.Pending(), 2)
  T.Advance(2.3); T.eq(#T.chat, 1, "not before 2.5 s")
  T.Advance(0.3); T.eq(texts(), "one|two")
  T.Advance(2.1); T.eq(#T.chat, 2)
  T.Advance(0.4); T.eq(texts(), "one|two|three")
  T.eq(Chat.Pending(), 0)
  T.near(T.chat[2].t - T.chat[1].t, 2.5, 0.01); T.near(T.chat[3].t - T.chat[2].t, 2.5, 0.01)
end)

T.test("interval is configurable (clamped to 1..30 s) and the largest configured value wins", function()
  setup({ interval = 5 })
  Chat.Say("bloodsports", "a"); Chat.Say("bloodsports", "b")
  T.Advance(4.5); T.eq(#T.chat, 1)
  T.Advance(0.6); T.eq(#T.chat, 2)
  local cfg = setup({ interval = 0.01 })
  Chat.Say("bloodsports", "a"); Chat.Say("bloodsports", "b")
  T.Advance(0.9); T.eq(#T.chat, 1, "floor is 1 s")
  T.Advance(0.3); T.eq(#T.chat, 2)
  -- a second addon with a slower interval slows the shared sink
  setup()
  Chat.Configure({ interval = 6, cats = { elders = { on = true, route = "say" } } })
  Chat.Say("bloodsports", "x"); Chat.Say("elders", "y")
  T.Advance(5.5); T.eq(#T.chat, 1)
  T.Advance(1); T.eq(texts(), "x|y")
end)

T.test("dedupe: an identical line inside 30 s is refused, a different one is not, after the window it is fine", function()
  setup()
  T.ok(Chat.Say("bloodsports", "Betting is open"))
  local ok, why = Chat.Say("bloodsports", "Betting is open")
  T.eq(ok, false); T.eq(why, "dupe")
  T.ok(Chat.Say("bloodsports", "Betting is closed"))
  T.Advance(20)
  T.eq((Chat.Say("bloodsports", "Betting is open")), false, "still inside the window")
  T.Advance(11)
  T.ok(Chat.Say("bloodsports", "Betting is open"), "window over")
  -- whitespace-only differences are the same line
  T.eq((Chat.Say("bloodsports", "  Betting   is open ")), false)
  -- a refused duplicate does not eat the cap
  setup({ cap = 2 })
  Chat.Say("bloodsports", "a"); Chat.Say("bloodsports", "a"); Chat.Say("bloodsports", "a")
  T.ok(Chat.Say("bloodsports", "b"), "second distinct line still fits")
end)

T.test("hard cap per scope; Reset gives the scope a fresh budget; scopes are independent", function()
  setup({ cap = 3 })
  for i = 1, 3 do T.ok(Chat.Say("bloodsports", "line " .. i, { scope = "fight1" })) end
  local ok, why = Chat.Say("bloodsports", "line 4", { scope = "fight1" })
  T.eq(ok, false); T.eq(why, "cap")
  T.ok(Chat.Say("bloodsports", "other fight", { scope = "fight2" }), "another scope has its own budget")
  Chat.Reset("bloodsports", "fight1")
  T.ok(Chat.Say("bloodsports", "line 5", { scope = "fight1" }))
  T.Advance(30)
  T.eq(#T.chat, 5, "everything accepted was sent, nothing else")
  T.eq(Chat.Stats().dropped.cap, 1)
end)

T.test("never sends while chat is locked: refused on offer, and a queued line is dropped when it falls due", function()
  setup()
  T.chatLocked = true
  local ok, why = Chat.Say("bloodsports", "locked line")
  T.eq(ok, false); T.eq(why, "locked")
  T.Advance(10); T.eq(#T.chat, 0)
  T.chatLocked = false
  Chat.Say("bloodsports", "first"); Chat.Say("bloodsports", "queued behind")
  T.eq(#T.chat, 1)
  T.chatLocked = true      -- lockdown starts while a line waits
  T.Advance(10)
  T.eq(#T.chat, 1, "the waiting line is not sent")
  T.eq(Chat.Pending(), 0); T.eq(Chat.Stats().dropped.locked, 2)
  T.chatLocked = false
  T.Advance(5)
  T.eq(#T.chat, 1, "and it does not come back after the lockdown ends")
end)

T.test("blocked instance types (arena, pvp) are silent; dungeons and the open world are not", function()
  setup()
  T.instance = { inInstance = true, type = "arena" }
  T.eq((Chat.Say("bloodsports", "a")), false)
  T.instance = { inInstance = true, type = "pvp" }
  T.eq((Chat.Say("bloodsports", "b")), false)
  T.eq(#T.chat, 0)
  T.instance = { inInstance = true, type = "party" }
  T.ok(Chat.Say("bloodsports", "c"))
  T.instance = { inInstance = false, type = "none" }
  T.ok(Chat.Say("bloodsports", "d"))
  -- the blocked list is config
  local cfg = setup()
  cfg.blocked = { raid = true }
  T.instance = { inInstance = true, type = "raid" }
  T.eq((Chat.Say("bloodsports", "e")), false)
  T.instance = { inInstance = true, type = "arena" }
  T.ok(Chat.Say("bloodsports", "f"))
end)

T.test("a secret value is never sent, and a send that raises is counted, not fatal", function()
  setup()
  local ok, why = Chat.Say("bloodsports", T.Secret("hidden"))
  T.eq(ok, false); T.eq(why, "text")
  T.eq((Chat.Say("bloodsports", 42)), false)
  T.eq((Chat.Say("bloodsports", "   ")), false)
  local real = SendChatMessage
  SendChatMessage = function() error("ADDON_ACTION_FORBIDDEN") end
  local ok2 = Chat.Say("bloodsports", "boom")
  SendChatMessage = real
  T.ok(ok2, "accepted; the failure happens at delivery")
  T.eq(Chat.Stats().error, 1); T.eq(Chat.Stats().sent, 0)
  T.Advance(3)
  T.ok(Chat.Say("bloodsports", "after"), "the sink keeps working")
  T.eq(#T.chat, 1)
end)

T.test("text hygiene: pipes and control characters removed, whitespace collapsed, 255 bytes max (UTF-8 safe)", function()
  setup()
  Chat.Say("bloodsports", "|cffff0000red|r\tand\nnew   line |Hitem:1|h")
  T.eq(T.chat[1].text, "cffff0000red r and new line Hitem:1 h")
  T.Advance(3)
  Chat.Say("bloodsports", string.rep("x", 300))
  T.eq(#T.chat[2].text, 255)
  T.Advance(3)
  Chat.Say("bloodsports", string.rep("a", 254) .. "\195\169")   -- é straddles the limit
  T.eq(#T.chat[3].text, 254)
end)

T.test("routes: say yell party raid group channel local off, per-line override, no group -> refused", function()
  local cfg = setup()
  local c = cfg.cats.bloodsports
  local function one(route, text, opts)
    c.route = route
    T.Advance(3)
    return Chat.Say("bloodsports", text, opts)
  end
  T.ok(one("yell", "y")); T.eq(T.chat[#T.chat].chatType, "YELL")
  local ok, why = one("party", "p")
  T.eq(ok, false); T.eq(why, "nogroup")
  ok, why = one("group", "g"); T.eq(ok, false); T.eq(why, "nogroup")
  T.group = { size = 3, raid = false }
  T.ok(one("party", "p2")); T.eq(T.chat[#T.chat].chatType, "PARTY")
  T.ok(one("group", "g2")); T.eq(T.chat[#T.chat].chatType, "PARTY")
  ok, why = one("raid", "r"); T.eq(ok, false); T.eq(why, "nogroup")
  T.group = { size = 8, raid = true }
  T.ok(one("raid", "r2")); T.eq(T.chat[#T.chat].chatType, "RAID")
  T.ok(one("group", "g3")); T.eq(T.chat[#T.chat].chatType, "RAID")
  LE_PARTY_CATEGORY_INSTANCE = 2
  T.ok(one("group", "g4")); T.eq(T.chat[#T.chat].chatType, "INSTANCE_CHAT")
  LE_PARTY_CATEGORY_INSTANCE = nil
  -- per-line override beats the category route
  T.ok(one("say", "ov", { route = "yell" })); T.eq(T.chat[#T.chat].chatType, "YELL")
  -- off, and an unknown route, send nothing
  local n = #T.chat
  ok, why = one("off", "o"); T.eq(ok, false); T.eq(why, "off")
  ok, why = one("shout", "s"); T.eq(ok, false); T.eq(why, "off")
  T.eq(#T.chat, n)
end)

T.test("channel route needs a joined custom channel; local prints to your own chat, unpaced and unsent", function()
  local cfg = setup()
  cfg.cats.bloodsports.route = "channel"
  local ok, why = Chat.Say("bloodsports", "c1")
  T.eq(ok, false); T.eq(why, "nochannel")
  cfg.channelName = "WoMRing"
  local realGet = GetChannelName
  GetChannelName = function(name) return name == "WoMRing" and 7 or 0 end
  T.ok(Chat.Say("bloodsports", "c2"))
  GetChannelName = realGet
  T.eq(T.chat[1].chatType, "CHANNEL"); T.eq(T.chat[1].target, 7)
  -- local
  cfg.cats.bloodsports.route = "local"
  T.printed = {}
  T.ok(Chat.Say("bloodsports", "l1")); T.ok(Chat.Say("bloodsports", "l2"))
  T.eq(#T.chat, 1, "nothing public sent"); T.eq(#T.printed, 2); T.eq(T.printed[1], "l1")
  T.chatLocked = true
  T.ok(Chat.Say("bloodsports", "l3"), "local output is not chat, so a lockdown does not mute it")
  T.chatLocked = false
end)

T.test("category toggle: off refuses new lines and drops queued ones", function()
  local cfg = setup()
  Chat.Say("bloodsports", "first"); Chat.Say("bloodsports", "second")
  cfg.cats.bloodsports.on = false
  local ok, why = Chat.Say("bloodsports", "third")
  T.eq(ok, false); T.eq(why, "off")
  T.Advance(5)
  T.eq(texts(), "first", "second was queued before the toggle and is dropped at delivery")
  cfg.cats.bloodsports.on = true
  T.ok(Chat.Say("bloodsports", "fourth"))
  Chat.Say("bloodsports", "fifth")
  Chat.Clear("bloodsports")
  T.eq(Chat.Pending(), 0)
end)

T.test("queue limit: ordinary lines are refused when full, an important line evicts the oldest ordinary one", function()
  setup({ queue = 3 })
  Chat.Say("bloodsports", "sent now")
  for i = 1, 3 do T.ok(Chat.Say("bloodsports", "q" .. i)) end
  local ok, why = Chat.Say("bloodsports", "q4")
  T.eq(ok, false); T.eq(why, "full")
  T.ok(Chat.Say("bloodsports", "VERDICT", { important = true }))
  T.eq(Chat.Pending(), 3)
  T.Advance(20)
  T.eq(texts(), "sent now|q2|q3|VERDICT")
end)

T.test("a queued line that waited past maxAge is stale and never sent", function()
  setup({ maxAge = 5, interval = 30 })
  Chat.Say("bloodsports", "now"); Chat.Say("bloodsports", "late")
  T.Advance(31)
  T.eq(texts(), "now")
  T.eq(Chat.Stats().dropped.stale, 1)
end)

T.test("two addons share one sink: one interval across categories, each cap and toggle is its own", function()
  setup()
  local elders = Chat.Configure({ cap = 1, cats = { elders = { on = true, route = "say" } } })
  Chat.Say("bloodsports", "duel!"); Chat.Say("elders", "ding 12")
  T.eq(texts(), "duel!")
  T.Advance(2.6); T.eq(texts(), "duel!|ding 12")
  local ok, why = Chat.Say("elders", "ding 13")
  T.eq(ok, false); T.eq(why, "cap")
  T.ok(Chat.Say("bloodsports", "still fine"))
  elders.cats.elders.on = false
  T.eq((Chat.Say("elders", "ding 14")), false)
  T.noErrors()
end)

T.done()
