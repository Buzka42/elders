-- Integration: the whole Elders addon loads from its TOC, survives login, a few events and a 30 s tick without errors.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")

T.test("loads and creates the DB + character record", function()
  T.ok(EldersDB, "EldersDB")
  T.ok(EldersDB.installId, "installId")
  T.ok(ns.char and ns.char.id, "char id")
  T.eq(ns.Agg.Bracket().sec ~= nil, true)
end)

T.test("survives common events and time passing", function()
  T.units.player.xp = 300; T.Fire("PLAYER_XP_UPDATE", "player")
  T.SetMoney(1500)
  T.combat = true; T.Fire("PLAYER_REGEN_DISABLED"); T.Advance(5)
  T.combat = false; T.Fire("PLAYER_REGEN_ENABLED"); T.Advance(30)
  T.Fire("PLAYER_LEVEL_UP", 11); T.Advance(5)
  T.noErrors()
end)

T.test("slash commands", function()
  SlashCmdList.ELDERS("link ABCD2345")
  T.eq(EldersDB.outbox.rows[#EldersDB.outbox.rows].kind, "link")
  SlashCmdList.ELDERS("help")
  T.noErrors()
end)

if T.missing then io.write("  (skipped missing files: " .. #T.missing .. ")\n") end
T.done()
