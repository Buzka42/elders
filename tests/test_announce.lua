-- Elders/Announce.lua: level-up and bracket-sealed lines routed through MK.Chat to say / group / nothing, plus the
-- settings entries that drive them.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc", { login = false })
local MK, A = MetaKit, ns.A
local settings
do
  local orig = MK.UI.Settings
  MK.UI.Settings = function(o) settings = o; return orig(o) end
end
T.Fire("PLAYER_LOGIN")
T.Fire("PLAYER_ENTERING_WORLD", true, false)
local cfg = A.db.config

local function reset(mode)
  T.Advance(60)
  T.chat = {}
  T.chatLocked = false
  T.group = { size = 0, raid = false }
  cfg.eldersAnnounce, cfg.announceLevel, cfg.announceBracket = mode or "say", true, true
  cfg.chat.cats.elders.on = true
  cfg.chat.interval = 2.5
end

local function levelUp(level)
  T.Fire("PLAYER_LEVEL_UP", level)
  T.Advance(4)
end

T.test("defaults: announcing to /say, both lines on, category configured on the shared sink", function()
  T.eq(cfg.eldersAnnounce, "say"); T.eq(cfg.announceLevel, true); T.eq(cfg.announceBracket, true)
  T.eq(cfg.chat.cats.elders.on, true); T.eq(cfg.chat.interval, 2.5)
  T.ok(MK.Chat.Cat("elders") == cfg.chat.cats.elders, "Announce configured MK.Chat with the live table")
end)

T.test("level-up goes to /say with the finished level's time and deaths", function()
  reset("say")
  T.played.level = 724           -- Pace stores the finished level's time from /played
  ns.char.levels[10] = { sec = 0, deaths = 1 }
  levelUp(11)
  T.eq(#T.chat, 1)
  T.eq(T.chat[1].chatType, "SAY")
  T.eq(T.chat[1].text, "Tester hit level 11! Level 10: 12m 04s, 1 death. [Elders]")
  T.noErrors()
end)

T.test("a tenth level adds the bracket-done wording", function()
  reset("say")
  T.played.level = 3600
  ns.char.levels[19] = { sec = 0, deaths = 0 }
  levelUp(20)
  T.eq(T.chat[1].text, "Tester hit level 20! Levels 11 to 20 done. Level 19: 1h 00m, no deaths. [Elders]")
end)

T.test("bracket sealed (ritual submitted) is announced; a skipped ritual is not", function()
  reset("say")
  A:Fire("RITUAL_SKIP", 2); T.Advance(4)
  T.eq(#T.chat, 0)
  A:Fire("RITUAL_SUBMIT", 2, "good", "fine", {}, ""); T.Advance(4)
  T.eq(#T.chat, 1)
  T.eq(T.chat[1].text, "Tester sealed levels 11 to 20 in the Elders' book. [Elders]")
  T.eq(T.chat[1].chatType, "SAY")
end)

T.test("group route: instance group, raid, party; alone it says nothing at all", function()
  reset("group")
  levelUp(12); T.eq(#T.chat, 0, "alone: nothing, and nothing leaks to /say")
  T.Advance(60)
  T.group = { size = 4, raid = false }
  levelUp(13); T.eq(T.chat[#T.chat].chatType, "PARTY")
  T.Advance(60)
  T.group = { size = 12, raid = true }
  levelUp(14); T.eq(T.chat[#T.chat].chatType, "RAID")
  T.Advance(60)
  LE_PARTY_CATEGORY_INSTANCE = 2
  levelUp(15); T.eq(T.chat[#T.chat].chatType, "INSTANCE_CHAT")
  LE_PARTY_CATEGORY_INSTANCE = nil
  T.eq(#T.chat, 3)
end)

T.test("off, per-line toggles and the category master switch are silent; routing changes apply without a reload", function()
  reset("off")
  levelUp(16); A:Fire("RITUAL_SUBMIT", 2); T.Advance(4)
  T.eq(#T.chat, 0)
  cfg.eldersAnnounce = "say"
  cfg.announceLevel = false
  levelUp(17); T.eq(#T.chat, 0, "level line off")
  A:Fire("RITUAL_SUBMIT", 2); T.Advance(4); T.eq(#T.chat, 1, "bracket line still on")
  T.Advance(60)
  cfg.announceBracket = false
  A:Fire("RITUAL_SUBMIT", 3); T.Advance(4); T.eq(#T.chat, 1, "bracket line off")
  cfg.announceLevel = true
  cfg.chat.cats.elders.on = false
  levelUp(18); T.eq(#T.chat, 1, "master switch off")
  cfg.chat.cats.elders.on = true
  cfg.eldersAnnounce = "banana"
  levelUp(19); T.eq(#T.chat, 1, "unknown mode counts as off")
end)

T.test("silent while chat is locked or in an arena", function()
  reset("say")
  T.chatLocked = true
  levelUp(21); T.eq(#T.chat, 0)
  T.chatLocked = false
  T.instance = { inInstance = true, type = "arena" }
  levelUp(22); T.eq(#T.chat, 0)
  T.instance = { inInstance = false, type = "none" }
  levelUp(23); T.eq(#T.chat, 1)
end)

T.test("lines are paced: a burst of level-ups leaves one interval apart, the same line is never repeated", function()
  reset("say")
  T.Fire("PLAYER_LEVEL_UP", 30); T.Fire("PLAYER_LEVEL_UP", 31); T.Fire("PLAYER_LEVEL_UP", 32)
  T.Advance(3.1)
  T.eq(#T.chat, 1)
  T.Advance(2.6); T.eq(#T.chat, 2)
  T.Advance(2.6); T.eq(#T.chat, 3)
  T.Fire("PLAYER_LEVEL_UP", 32); T.Advance(4)
  T.eq(#T.chat, 3, "duplicate inside 30 s dropped")
end)

T.test("settings: announce slider, toggles and the pacing slider write the config", function()
  T.ok(settings, "Settings registered")
  local keys = {}
  for _, o in ipairs(settings.options) do if o.key then keys[o.key] = o end end
  for _, k in ipairs({ "announceChannel", "announceLevel", "announceBracket", "chatInterval" }) do T.ok(keys[k], k) end
  T.eq(keys.announceChannel.min, 0); T.eq(keys.announceChannel.max, 2); T.eq(keys.chatInterval.min, 1)
  local db = settings.db
  cfg.eldersAnnounce = "say"
  T.eq(db.announceChannel, 1)
  db.announceChannel = 2; T.eq(cfg.eldersAnnounce, "group"); T.eq(db.announceChannel, 2)
  db.announceChannel = 0; T.eq(cfg.eldersAnnounce, "off")
  db.announceChannel = 1; T.eq(cfg.eldersAnnounce, "say")
  db.chatInterval = 4; T.eq(cfg.chat.interval, 4); T.eq(db.chatInterval, 4)
  db.announceLevel = false; T.eq(cfg.announceLevel, false)
  T.eq(db.minimapHide, false, "existing keys unaffected")
end)

T.done()
