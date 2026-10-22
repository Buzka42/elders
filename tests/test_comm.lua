local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Codec", "Comm" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit
local A = MK.NewAddon("CommTest")
local comm = MK.Comm.New(A, "TSTP")

local function reset() T.sent = {}; T.chatLocked = false; T.group = { size = 0, raid = false }; T.instance.inInstance = false end

T.test("registers prefix, Clean strips", function()
  T.ok(T.prefixes.TSTP)
  T.eq(MK.Comm.Clean("a\tb\nc|d"), "abcd")
  T.eq(MK.Comm.Clean(nil), "")
end)

T.test("send builds tab-separated messages", function()
  reset()
  T.ok(comm:Send("XY", { "a b", 5, "x\ty" }, "PARTY"))
  T.eq(#T.sent, 1)
  T.eq(T.sent[1].msg, "XY\ta b\t5\txy")
  T.eq(T.sent[1].prefix, "TSTP"); T.eq(T.sent[1].channel, "PARTY")
  T.advanceDone = true
  T.Advance(20)
end)

T.test("255-byte guard", function()
  reset(); T.Advance(20)
  T.eq(comm:Send("BIG", { string.rep("x", 260) }, "PARTY"), false)
  T.ok(comm:Send("BIG", { string.rep("x", 250) }, "PARTY"))
  T.eq(#T.sent[1].msg, 254)
  T.Advance(20)
end)

T.test("token bucket: burst 8 then 1 per second", function()
  reset(); T.Advance(20)
  for i = 1, 20 do T.ok(comm:Send("T", { i }, "RAID")) end
  T.eq(#T.sent, 8)
  T.Advance(3)
  T.eq(#T.sent, 11)
  T.Advance(30)
  T.eq(#T.sent, 20)
  T.eq(T.sent[20].msg, "T\t20")
end)

T.test("whispers bypass bucket but cap at 4/sec outside instances", function()
  reset(); T.Advance(20)
  for i = 1, 8 do comm:Send("W", { i }, "WHISPER", "Bob-Realm") end
  T.eq(#T.sent, 4)
  T.eq(T.sent[1].target, "Bob-Realm")
  T.Advance(1.01)
  T.eq(#T.sent, 8)
  -- inside an instance whispers use the bucket
  reset(); T.Advance(20)
  T.instance.inInstance = true
  for i = 1, 10 do comm:Send("W", { i }, "WHISPER", "Bob-Realm") end
  T.eq(#T.sent, 8)
  T.Advance(30)
  T.instance.inInstance = false
  T.eq(comm:Send("W", {}, "WHISPER", ""), false)
end)

T.test("channel target is numeric, result codes reported", function()
  reset(); T.Advance(20)
  local got
  comm.onResult = function(code, msgType, target) got = { code, msgType, target } end
  comm:Send("C", {}, "CHANNEL", "5")
  T.eq(T.sent[1].target, 5)
  T.eq(got, nil)
  T.sendResult = 3
  comm:Send("C2", {}, "CHANNEL", 5)
  T.sendResult = nil
  T.eq(got[1], 3); T.eq(got[2], "C2"); T.eq(got[3], 5)
  comm.onResult = nil
end)

T.test("lockdown refuses", function()
  reset(); T.Advance(20)
  T.chatLocked = true
  T.eq(comm:Send("L", {}, "PARTY"), false)
  T.eq(#T.sent, 0)
  T.chatLocked = false
  T.ok(comm:Send("L", {}, "PARTY"))
  T.eq(#T.sent, 1)
end)

T.test("lockdown during drain drops queued item with result code", function()
  reset(); T.Advance(20)
  local codes = {}
  comm.onResult = function(code) codes[#codes + 1] = code end
  for i = 1, 10 do comm:Send("Q", { i }, "RAID") end
  T.chatLocked = true
  T.Advance(5)
  T.eq(#T.sent, 8)
  T.ok(#codes >= 1 and codes[1] == 11)
  comm.onResult = nil
  T.chatLocked = false
  T.Advance(30)
end)

T.test("broadcast picks raid, party or nothing", function()
  reset(); T.Advance(20)
  T.eq(comm:Broadcast("B", {}), false)
  T.group = { size = 3, raid = false }
  T.ok(comm:Broadcast("B", {}))
  T.eq(T.sent[1].channel, "PARTY")
  T.group = { size = 10, raid = true }
  comm:Broadcast("B", {})
  T.eq(T.sent[2].channel, "RAID")
end)

T.test("receive dispatch, sender normalized, fields kept (empty too)", function()
  reset()
  local got
  comm:On("HI", function(sender, fields, channel, info) got = { sender, fields, channel, info } end)
  T.Deliver("TSTP", "HI\ta\t\tc", "PARTY", "Alice")
  T.eq(got[1], "Alice-Normal")
  T.eq(#got[2], 3); T.eq(got[2][2], ""); T.eq(got[2][3], "c")
  T.eq(got[3], "PARTY")
  got = nil
  T.Deliver("TSTP", "HI", "WHISPER", "Bob-Other")
  T.eq(got[1], "Bob-Other"); T.eq(#got[2], 0)
  got = nil
  T.Deliver("OTHER", "HI", "PARTY", "Carl")
  T.eq(got, nil)
  T.Deliver("TSTP", "UNKNOWN\tx", "PARTY", "Carl")
end)

T.test("own messages and secrets ignored", function()
  local n = 0
  comm:On("OWN", function() n = n + 1 end)
  T.Deliver("TSTP", "OWN", "PARTY", "Tester")
  T.Deliver("TSTP", "OWN", "PARTY", "Tester-Normal")
  T.eq(n, 0)
  T.Fire("CHAT_MSG_ADDON", "TSTP", T.Secret("OWN"), "PARTY", "Dave", "Dave")
  T.Fire("CHAT_MSG_ADDON", "TSTP", "OWN", "PARTY", T.Secret("Dave"), "Dave")
  T.eq(n, 0)
  T.Deliver("TSTP", "OWN", "PARTY", "Dave")
  T.eq(n, 1)
end)

T.test("handler errors are contained", function()
  comm:On("BOOM", function() error("x") end)
  local ok = false
  comm:On("BOOM", function() ok = true end)
  T.Deliver("TSTP", "BOOM", "PARTY", "Erin")
  T.ok(ok)
  T.eq(#T.printed, 1, "error reported once")
  T.printed = {}
end)

T.test("flood guard quarantines a sender for 120 s", function()
  T.Advance(20)
  local n = 0
  comm:On("F", function() n = n + 1 end)
  for _ = 1, 40 do T.Deliver("TSTP", "F", "PARTY", "Spammer") end
  T.eq(n, 30)
  T.Advance(60)
  T.Deliver("TSTP", "F", "PARTY", "Spammer")
  T.eq(n, 30)
  T.Advance(61)
  T.Deliver("TSTP", "F", "PARTY", "Spammer")
  T.eq(n, 31)
  -- other senders unaffected
  T.Deliver("TSTP", "F", "PARTY", "Polite")
  T.eq(n, 32)
end)

T.test("slow senders are not flagged", function()
  local n = 0
  comm:On("S", function() n = n + 1 end)
  for _ = 1, 50 do T.Deliver("TSTP", "S", "PARTY", "Slow"); T.Advance(1) end
  T.eq(n, 50)
end)

T.test("Off removes a handler", function()
  local n = 0
  local fn = function() n = n + 1 end
  comm:On("OFF", fn); comm:Off("OFF", fn)
  T.Deliver("TSTP", "OFF", "PARTY", "Zed")
  T.eq(n, 0)
  T.noErrors()
end)

T.done()
