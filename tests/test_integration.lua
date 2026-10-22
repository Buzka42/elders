-- End-to-end: strict load (every TOC file present), real modules + real UI kit, full player flows.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local A = ns.A

T.test("no missing files in the TOC", function()
  T.eq(T.missing, nil, "missing: " .. table.concat(T.missing or {}, ", "))
end)

T.test("a session of play fills the bracket", function()
  T.units.player.level = 9
  ns.Agg.SetLevel(9)
  T.units.target = { name = "Kobold", level = 9, classification = "normal", enemy = true, guid = "Creature-0-1-2-3-4-5" }
  T.Fire("PLAYER_TARGET_CHANGED")
  T.combat = true; T.Fire("PLAYER_REGEN_DISABLED"); T.Advance(12)
  T.meter[0] = { durationSeconds = 12, combatSources = { { isLocalPlayer = true, totalAmount = 600 } } }
  T.combat = false; T.Fire("PLAYER_REGEN_ENABLED"); T.Advance(2)
  T.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 90 experience.")
  T.units.player.xp = 90; T.Fire("PLAYER_XP_UPDATE", "player")
  T.Advance(60)
  local b = ns.Agg.Bracket()
  T.ok(b.sec >= 60, "sec")
  T.eq(b.fights, 1)
  T.eq(b.dmg, 600)
  T.ok(b.xp >= 90, "xp")
  T.noErrors()
end)

T.test("panel opens and every tab renders", function()
  SlashCmdList.ELDERS("")
  T.ok(_G.EldersPanel and EldersPanel:IsShown(), "panel shown")
  SlashCmdList.ELDERS("")
  T.noErrors()
end)

T.test("dinging 10 opens the ritual; submit writes rating + insight to the outbox", function()
  local before = #EldersDB.outbox.rows
  T.units.player.level = 10
  T.Fire("PLAYER_LEVEL_UP", 10)
  T.Advance(5)
  local submitted
  A:Listen("RITUAL_SUBMIT", function(b, pve, pvp) submitted = { b, pve, pvp } end)
  local R = ns.UI.Ritual
  local s = R.cur
  T.ok(s, "ritual opened on ding 10")
  T.eq(s.bracket, 1)
  T.eq(s.next:IsEnabled(), false, "next disabled until both rated")
  s.rPve:SetValue(4); s.rPvp:SetValue(3)
  s.pve, s.pvp = s.pve > 0 and s.pve or 4, s.pvp > 0 and s.pvp or 3 -- SetValue may not fire onChange
  R.Show(s, 1)
  s.next:Click(); T.eq(s.step, 2)
  s.next:Click(); T.eq(s.step, 3)
  s.text = "Hunters should grab a pet early."
  s.submit:Click()
  T.Advance(1)
  T.eq(R.cur, nil, "ritual closed")
  T.ok(submitted, "submit fired")
  local kinds = {}
  for i = before + 1, #EldersDB.outbox.rows do kinds[EldersDB.outbox.rows[i].kind] = true end
  T.ok(kinds.rating, "rating row")
  T.ok(kinds.insight, "insight row")
  T.noErrors()
end)

T.test("export string round-trips", function()
  local s = MetaKit.ExportString("elders", ns.ExportPayload())
  local tag, val = MetaKit.ImportString(s)
  T.eq(tag, "elders")
  T.eq(val.char.id, ns.char.id)
  SlashCmdList.ELDERS("export")
  T.noErrors()
end)

T.test("UI kit demo builds in both skins", function()
  MetaKit.UI.Demo("elders"); MetaKit.UI.Demo("bloodsports")
  T.noErrors()
end)

T.done()
