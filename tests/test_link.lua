-- /elders link CODE: exactly 8 letters or digits are written as a `link` outbox row; anything else is refused.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")

local function rows() return #EldersDB.outbox.rows end
local function run(arg)
  local before = rows()
  SlashCmdList.ELDERS("link " .. arg)
  return rows() - before
end

T.test("rejects codes that are not exactly 8 letters or digits", function()
  for _, bad in ipairs({ "", "ABC123", "ABCDE12345", "ABCD-234", "ABCD_234", "ABCD\226\128\162234" }) do
    T.eq(run(bad), 0, "refused: '" .. bad .. "'")
  end
  T.noErrors()
end)

T.test("accepts 8 alphanumerics and writes a link row with the uppercased code and char id", function()
  T.eq(run("abcd2345"), 1, "one row")
  local r = EldersDB.outbox.rows[#EldersDB.outbox.rows]
  T.eq(r.kind, "link")
  T.eq(r.data.code, "ABCD2345")
  T.eq(r.data.charId, ns.char.id)
  T.eq(run("ABCD 2345"), 1, "spaces are dropped before the length check")
end)

if T.missing then io.write("  (skipped missing files: " .. #T.missing .. ")\n") end
T.done()
