-- Export payload for the website paste box: whole "First Surname-Realm" key, identity, brackets, levels, played.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
T.units.player.realm = "Gippity"
local ns = T.LoadAddon("Elders/Elders.toc")
local MK = MetaKit

T.test("payload carries the whole character key and the stats tables", function()
  local p = ns.ExportPayload()
  T.eq(p.v, 1)
  T.eq(p.addon, "Elders")
  T.eq(p.install, ns.A.db.installId)
  T.eq(p.char.key, "Tester Gippity-Normal")
  T.eq(p.char.name, "Tester Gippity")
  T.eq(p.char.realm, "Normal")
  T.eq(p.char.id, ns.char.id)
  T.ok(type(p.brackets) == "table" and type(p.levels) == "table" and type(p.played) == "table", "stats tables")
end)

T.test("WOM1 string round-trips with the elders tag and keeps the key whole", function()
  local tag, v = MK.ImportString(ns.UI.ExportText())
  T.eq(tag, "elders")
  T.eq(v.char.key, "Tester Gippity-Normal")
end)

T.test("/elders export opens the export box", function()
  local shown, keep = {}, MK.UI.ExportBox
  MK.UI.ExportBox = function(o) shown[#shown + 1] = o end
  SlashCmdList.ELDERS("export")
  MK.UI.ExportBox = keep
  T.eq(#shown, 1)
  T.ok(shown[1].text:find("^WOM1:elders:"))
  T.noErrors()
end)

T.done()
