-- Elders UI: pure stat math always; frame flows run against the real MetaKit UI kit, or a recording mock when the kit is absent.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local A = ns.A
local UI = ns.UI

local realKit = MetaKit.UI.Window ~= nil
local rec = { toasts = {}, exports = {}, heads = {}, sections = nil, minimap = nil }

if not realKit then
  io.write("  (MetaKit.UI.Window missing: running frame flows against a recording mock kit)\n")
  local K = MetaKit.UI
  local function frame(parent) return CreateFrame("Frame", nil, parent) end
  K.Art = function(n, name) return n.Media.has[name] and (n.Media.path .. name) or nil end
  K.Skin = function() return {} end
  K.RegisterSkin = function(name, t) rec.skin = t end
  K.Window = function(o) local w = frame(); w.content = frame(w); w.Toggle = function(self) self:SetShown(not self:IsShown()) end
    w._shown = false; rec.window = o; return w end
  K.StatRows = function() local f = frame(); f.SetSections = function(_, s) rec.sections = s end; return f end
  K.Tabs = function(_, o) local f = frame(); f.Select = function(self, i) o.onSelect(i) end; rec.tabs = f; return f end
  K.Label = function() return frame() end
  K.Icon = function() local f = frame(); f.SetIcon = function() end; return f end
  K.ClassIcon = function() local f = frame(); f.SetClass = function() end; return f end
  K.Button = function(_, o) local f = frame(); f.SetActive = function() end; f.SetEnabledState = function() end
    f._scripts.OnClick = function() o.onClick() end; return f end
  K.Rating = function(_, o) local f = frame(); f.SetValue = function(self, n) self._v = n; o.onChange(n) end
    f.GetValue = function(self) return self._v or 0 end; return f end
  K.EditBox = function(_, o) local f = frame(); rec.edit = o; return f end
  K.TalkingHead = function(o) local f = frame(); f.body = frame(f); f.Close = function() o.onClose() end
    table.insert(rec.heads, o); rec.head = f; return f end
  K.Toast = function(o) table.insert(rec.toasts, o) end
  K.ExportBox = function(o) table.insert(rec.exports, o) end
  K.MinimapButton = function(o) rec.minimap = o; return frame() end
  K.Settings = function(o) rec.settings = o; return {} end
  ns.A.modules.Minimap:OnLogin()
end

-- seed bracket 1 (levels 1-10): one hour of play
local function seed()
  local b = ns.Agg.Bracket(5)
  b.sec = 7200; b.xp = 36000; b.xpQuest = 18000; b.xpKill = 15000; b.killsXP = 300; b.quests = 40; b.kills = 320
  b.fights = 100; b.fightSec = 2000; b.dmg = 50000; b.meterSec = 1000; b.taken = 14000; b.heal = 3600
  b.act.combat = 1800; b.act.moving = 3600; b.act.idle = 1800
  b.deaths = 4; b.ghostSec = 240; b.rested.sec = 1800
  b.copper.loot = 30000; b.copper.vendor = 20000; b.copper.repair = 10000
  b.mobDelta[7] = 3; b.mobDelta[5] = 1
  b.prof.Herbalism = 40
  b.dungeons[389] = { runs = 2, clears = 1, clearSec = 1800, wipes = 1, deaths = 2 }
  b.lfg.n = 2; b.lfg.formSec = 600
  b.zones[1411] = { sec = 3600, xp = 10000, copper = 40000 }
  ns.char.levels[5] = { sec = 600, deaths = 1, talents = "05/00/0" }
  ns.char.levels[6] = { sec = 1200, deaths = 0 }
end
seed()

local function find(sections, title, label)
  for _, s in ipairs(sections) do
    if s.title == title then
      for _, r in ipairs(s.rows) do if r.label == label then return r end end
    end
  end
  error("no row " .. title .. "/" .. label)
end

T.test("stat math from raw sums", function()
  local s = UI.Sections(1)
  T.eq(#s, 7)
  T.eq(find(s, "Pace", "XP per hour").value, "18.0k")
  T.eq(find(s, "Pace", "XP per kill").value, "50.0")
  T.eq(find(s, "Pace", "XP from quests").value, "50%")
  T.eq(find(s, "Pace", "Time per level").value, "15m 00s")
  T.eq(find(s, "Pace", "Time rested").value, "25%")
  T.eq(find(s, "Downtime", "In combat").value, "25%")
  T.eq(find(s, "Downtime", "Corpse run, average").value, "1m 00s")
  T.eq(find(s, "Downtime", "Deaths per hour").value, "2.00")
  T.eq(find(s, "Combat", "Average fight").value, "20s")
  T.eq(find(s, "Combat", "Damage per second").value, "50.0")
  T.eq(find(s, "Combat", "Mob level vs. yours").value, "+0.5")
  T.eq(find(s, "Economy", "Gold per hour (gross)").value, MetaKit.Util.Money(25000))
  T.eq(find(s, "Economy", "Gold per hour (after repairs)").value, MetaKit.Util.Money(20000))
  T.eq(find(s, "Dungeons", "Average clear time").value, "30m 00s")
  T.eq(find(s, "Dungeons", "Time to form a group").value, "5m 00s")
  T.eq(find(s, "Professions", "Herbalism").value, "20.0 per hour")
  T.eq(find(s, "Talents", "Level 5").value, "05/00/0")
end)

T.test("too little data shows a dash, All sums brackets", function()
  local s = UI.Sections(2)
  T.eq(find(s, "Pace", "XP per hour").value, UI.DASH)
  T.eq(find(s, "Combat", "Average fight").value, UI.DASH)
  T.eq(find(s, "Professions", "No skill gained yet").value, UI.DASH)
  ns.char.brackets[2] = nil
  local all = UI.Sections(7)
  T.eq(find(all, "Pace", "XP from quests").value, "50%")
end)

T.test("export text falls back to plain when Codec is missing", function()
  local keep = MetaKit.ExportString
  MetaKit.ExportString = nil
  T.ok(UI.ExportText():find("^ELDERS%-PLAIN:"))
  MetaKit.ExportString = keep
end)

T.test("quick rates for the minimap", function()
  local xp, gold = UI.Quick(1)
  T.eq(xp, "18.0k")
  T.eq(gold, MetaKit.Util.Money(25000))
end)

T.test("panel opens, closes and switches every tab", function()
  SlashCmdList.ELDERS("")
  local w = EldersPanel or UI.Panel()
  T.ok(w, "panel exists")
  T.ok(w:IsShown())
  if not realKit then T.eq(#rec.sections, 7, "sections rendered on open") end
  local tabs = realKit and nil or rec.tabs
  for i = 1, 7 do
    if tabs then tabs:Select(i) end
    if not realKit then T.eq(#rec.sections, 7) end
  end
  SlashCmdList.ELDERS("")
  T.ok(not w:IsShown())
  T.noErrors()
end)

T.test("ritual: deferred in combat, then rated and submitted", function()
  local fired
  A:Listen("RITUAL_SUBMIT", function(...) fired = { ... } end)
  T.combat = true
  A:Fire("RITUAL_DUE", 1)
  T.eq(UI.Ritual.cur, nil, "deferred while in combat")
  T.combat = false
  T.Fire("PLAYER_REGEN_ENABLED"); T.Advance(2)
  local s = UI.Ritual.cur
  T.ok(s, "ritual opened after combat")
  s.rPve:SetValue(4); s.rPvp:SetValue(2)
  s.pve, s.pvp = 4, 2
  UI.Ritual.Show(s, 3)
  s.text = "Barrens chat is a hazard."
  UI.Ritual.Submit(s)
  T.ok(fired, "RITUAL_SUBMIT fired")
  T.eq(fired[1], 1); T.eq(fired[2], 4); T.eq(fired[3], 2)
  T.eq(type(fired[4]), "table"); T.eq(fired[5], "Barrens chat is a hazard.")
  T.eq(UI.Ritual.cur, nil)
  T.noErrors()
end)

T.test("ritual: skip fires RITUAL_SKIP; instance defers; rated bracket is not asked again", function()
  local skipped
  A:Listen("RITUAL_SKIP", function(b) skipped = b end)
  T.instance.inInstance = true; T.instance.type = "party"
  A:Fire("RITUAL_OPEN", 1, true)
  T.eq(UI.Ritual.cur, nil, "deferred in instance")
  T.instance.inInstance = false; T.instance.type = "none"
  T.Fire("PLAYER_ENTERING_WORLD"); T.Advance(3)
  local s = UI.Ritual.cur
  T.ok(s, "opened after leaving the instance")
  UI.Ritual.Skip(s)
  T.eq(skipped, 1)
  ns.char.brackets[1].ritual = { pve = 5, pvp = 5 }
  A:Fire("RITUAL_DUE", 1)
  T.eq(UI.Ritual.cur, nil, "already rated")
  A:Fire("RITUAL_OPEN", 1, true)
  T.ok(UI.Ritual.cur, "forced")
  UI.Ritual.Skip(UI.Ritual.cur)
  T.noErrors()
end)

T.test("ritual works without ns.Insights and with insights", function()
  ns.char.brackets[1].ritual = {}
  local keep = ns.Insights
  ns.Insights = nil
  A:Fire("RITUAL_OPEN", 1, true)
  T.eq(#UI.Ritual.cur.insights, 0)
  UI.Ritual.Skip(UI.Ritual.cur)
  ns.Insights = function() return { { id = "a", text = "Pull to the wall." } } end
  A:Fire("RITUAL_OPEN", 1, true)
  T.eq(#UI.Ritual.cur.insights, 1)
  UI.Ritual.Skip(UI.Ritual.cur)
  ns.Insights = keep
  T.noErrors()
end)

T.test("toasts and export box and minimap", function()
  if realKit then T.eq(1, 1); return end
  local n = #rec.toasts
  A:Fire("RITUAL_SUBMIT", 2, 3, 3, {}, "")
  T.eq(#rec.toasts, n + 1); T.eq(rec.toasts[n + 1].title, "Bracket sealed")
  A:Fire("LEVEL_UP", 20); T.Advance(4)
  T.eq(#rec.toasts, n + 2)
  A.db.config.toasts = false
  A:Fire("LEVEL_UP", 21); T.Advance(4)
  T.eq(#rec.toasts, n + 2)
  A.db.config.toasts = true
  SlashCmdList.ELDERS("export")
  T.eq(#rec.exports, 1); T.ok(#rec.exports[1].text > 10)
  T.ok(rec.minimap and rec.minimap.name == "EldersMinimapButton")
  local opened
  A:Listen("TOGGLE_PANEL", function() opened = true end)
  rec.minimap.onClick("LeftButton")
  T.ok(opened)
  rec.minimap.onClick("RightButton")
  rec.minimap.tooltip(GameTooltip)
  T.ok(#GameTooltip.lines >= 4)
  T.noErrors()
end)

T.done()
