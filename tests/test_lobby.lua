local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Codec", "Comm", "Lobby" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit
local A = MK.NewAddon("LobbyTest")
local comm = MK.Comm.New(A, "TSTP")
local lobby = MK.Lobby.New(comm, { channel = "WoMLobby" })

local updates = 0
A:Listen("LOBBY_UPDATED", function() updates = updates + 1 end)
local chan = 0
local origJoin = JoinChannelByName
local joinCalls, removed = {}, {}
GetChannelName = function() return chan end
JoinChannelByName = function(name) joinCalls[#joinCalls + 1] = name end
ChatFrame_RemoveChannel = function(frame, name) removed[#removed + 1] = name end

local function lastSent() return T.sent[#T.sent] end
local function deliverLA(sender, kind, venue, class)
  T.Deliver("TSTP", table.concat({ "LA", kind, venue or "", class or "MAGE", "20", "Horde", "3", "4.5", "hi", "1.0" }, "\t"), "CHANNEL", sender)
end

T.test("not joined: nothing joins before PEW, nothing errors", function()
  T.Advance(30)
  T.eq(#joinCalls, 0)
  T.eq(lobby:Announce({ kind = "duel", venue = "x" }), false)
  T.eq(lobby:Query("duel", ""), false)
  T.eq(lobby:Unlist(), false)
  T.noErrors()
end)

T.test("joins 5 s after PEW with retries and gives up quietly", function()
  T.Fire("PLAYER_ENTERING_WORLD", true, false)
  T.Advance(4.9)
  T.eq(#joinCalls, 0)
  T.Advance(0.2)
  T.eq(#joinCalls, 1); T.eq(joinCalls[1], "WoMLobby")
  T.Advance(200)
  T.eq(#joinCalls, 4, "4 attempts then stop")
  T.ok(lobby.failed)
  T.eq(lobby:IsJoined(), false)
  T.noErrors()
end)

T.test("no join inside instances or lockdown", function()
  joinCalls = {}
  T.instance.inInstance = true
  T.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.Advance(100)
  T.eq(#joinCalls, 0)
  T.instance.inInstance = false
  T.Advance(31)
  T.eq(#joinCalls, 1)
  T.Advance(200)
end)

T.test("joined channel is hidden from chat windows", function()
  joinCalls, removed = {}, {}
  JoinChannelByName = function(name) joinCalls[#joinCalls + 1] = name; chan = 5 end
  T.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.Advance(8)
  T.ok(lobby:IsJoined())
  T.eq(lobby.channelNumber or lobby:ChannelNumber(), 5)
  T.ok(#removed >= 1 and removed[1] == "WoMLobby")
  -- RemoveChannel errors are contained
  ChatFrame_RemoveChannel = function() error("nope") end
  T.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.Advance(8)
  T.noErrors()
end)

T.test("announce / re-announce / unlist", function()
  T.sent = {}; T.Advance(30)
  T.ok(lobby:Announce({ kind = "duel", venue = "crossroads", note = "gg\tfriendly", streak = 4, rating = 4.5 }))
  local s = lastSent()
  T.eq(s.channel, "CHANNEL"); T.eq(s.target, 5)
  T.eq(s.msg, "LA\tduel\tcrossroads\tWARRIOR\t10\tHorde\t4\t4.5\tggfriendly\tdev")
  local n = #T.sent
  T.Advance(61)
  T.ok(#T.sent >= n + 1, "re-announced")
  T.eq(T.sent[#T.sent].msg:sub(1, 2), "LA")
  T.ok(lobby:Unlist())
  T.eq(lastSent().msg, "LX")
  n = #T.sent
  T.Advance(130)
  T.eq(#T.sent, n, "no more announces")
end)

T.test("receive LA / LX, List filter + order, update events", function()
  local u0 = updates
  deliverLA("Anna-Realm", "duel", "crossroads", "MAGE")
  T.Advance(2)
  deliverLA("Bob-Realm", "club", "tram", "ROGUE")
  T.Advance(2)
  deliverLA("Cy-Realm", "duel", "goldshire", "PRIEST")
  T.eq(updates - u0, 3)
  local all = lobby:List()
  T.eq(#all, 3)
  T.eq(all[1].name, "Cy-Realm"); T.eq(all[3].name, "Anna-Realm")
  local e = all[3]
  T.eq(e.kind, "duel"); T.eq(e.venue, "crossroads"); T.eq(e.class, "MAGE"); T.eq(e.level, 20)
  T.eq(e.faction, "Horde"); T.eq(e.streak, 3); T.eq(e.rating, 4.5); T.eq(e.note, "hi"); T.eq(e.version, "1.0")
  local duels = lobby:List(function(x) return x.kind == "duel" end)
  T.eq(#duels, 2)
  T.Deliver("TSTP", "LX", "CHANNEL", "Bob-Realm")
  T.eq(#lobby:List(), 2)
  T.eq(lobby.entries["Bob-Realm"], nil)
end)

T.test("refresh keeps one entry; bad input ignored", function()
  deliverLA("Anna-Realm", "duel", "crossroads", "MAGE")
  T.eq(#lobby:List(), 2)
  T.Deliver("TSTP", "LA\t\tx", "CHANNEL", "Junk-Realm")
  T.Deliver("TSTP", "LA", "CHANNEL", "Junk2-Realm")
  T.Deliver("TSTP", "LA\tduel", "PARTY", "Junk3-Realm")
  T.eq(#lobby:List(), 2)
end)

T.test("entries expire after 180 s", function()
  T.Advance(100)
  deliverLA("Fresh-Realm", "duel", "x")
  T.Advance(85)
  local names = {}
  for _, e in ipairs(lobby:List()) do names[e.name] = true end
  T.eq(names["Fresh-Realm"], true)
  T.eq(names["Anna-Realm"], nil)
  T.Advance(100)
  T.eq(#lobby:List(), 0)
end)

T.test("expiry via ticker fires LOBBY_UPDATED", function()
  deliverLA("Gone-Realm", "ref", "")
  local u0 = updates
  T.Advance(200)
  T.ok(updates > u0)
  T.eq(lobby.entries["Gone-Realm"], nil)
end)

T.test("query: listed player replies by whisper after jitter, once per 30 s", function()
  lobby:Announce({ kind = "duel", venue = "crossroads" })
  T.sent = {}
  T.Deliver("TSTP", "LQ\tduel\t", "CHANNEL", "Asker-Realm")
  T.eq(#T.sent, 0)
  T.Advance(3.1)
  T.eq(#T.sent, 1)
  T.eq(T.sent[1].channel, "WHISPER"); T.eq(T.sent[1].target, "Asker-Realm")
  T.eq(T.sent[1].msg:sub(1, 8), "LA\tduel\t")
  T.Deliver("TSTP", "LQ\tduel\t", "CHANNEL", "Asker-Realm")
  T.Advance(4)
  T.eq(#T.sent, 1, "cooldown")
  T.Advance(30)
  T.Deliver("TSTP", "LQ\tduel\t", "CHANNEL", "Asker-Realm")
  T.Advance(4)
  T.eq(#T.sent, 2)
  -- non-matching filters get no reply
  T.Deliver("TSTP", "LQ\tclub\t", "CHANNEL", "Other-Realm")
  T.Deliver("TSTP", "LQ\tduel\tgoldshire", "CHANNEL", "Other2-Realm")
  T.Advance(4)
  T.eq(#T.sent, 2)
  -- unlisted players never reply
  lobby:Unlist()
  T.Deliver("TSTP", "LQ\t\t", "CHANNEL", "Third-Realm")
  T.Advance(4)
  T.eq(#T.sent, 3, "only the LX")
  T.eq(T.sent[3].msg, "LX")
end)

T.test("whispered LA reply populates list; Query sends LQ", function()
  T.sent = {}
  T.ok(lobby:Query("duel", "crossroads"))
  T.eq(lastSent().msg, "LQ\tduel\tcrossroads")
  T.Deliver("TSTP", "LA\tduel\tcrossroads\tMAGE\t30\tHorde\t\t\t\t1", "WHISPER", "Replier-Realm")
  local e = lobby.entries["Replier-Realm"]
  T.ok(e); T.eq(e.level, 30); T.eq(e.streak, nil)
end)

T.test("SendTo whispers", function()
  T.sent = {}
  T.ok(lobby:SendTo("Bob-Realm", "LI", { "duel", "x", "come" }))
  T.eq(lastSent().channel, "WHISPER"); T.eq(lastSent().msg, "LI\tduel\tx\tcome")
  T.noErrors()
end)

T.test("lockdown: announce refused without error", function()
  T.chatLocked = true
  T.eq(lobby:Query("duel", ""), false)
  T.chatLocked = false
  T.noErrors()
end)

T.done()
