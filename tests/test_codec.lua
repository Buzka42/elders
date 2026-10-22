local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Codec" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local sample = {
  name = "Tester", n = -12.5, big = 1234567890123, tiny = 1e-9, third = 1 / 3, neg = -7, zero = 0,
  flag = true, off = false, ["key with spaces"] = "v", [5] = "sparse", [-2] = "neg",
  list = { 1, 2, { a = 1, b = { c = { "deep" } } }, "x" },
  uni = "h\195\169llo \226\130\172 \0 nul \n newline \"quoted\" ; } { #", empty = {}, emptyStr = "",
}

T.test("round trip nested values", function()
  local text = MK.Serialize(sample)
  local back, err = MK.Deserialize(text)
  T.ok(back, err)
  T.ok(deepEq(sample, back), "deep equal")
  T.eq(back.third, 1 / 3)
end)

T.test("serialization is deterministic", function()
  local a = MK.Serialize({ z = 1, a = 2, m = { y = 1, x = 2 } })
  local b = MK.Serialize({ m = { x = 2, y = 1 }, a = 2, z = 1 })
  T.eq(a, b)
end)

T.test("scalars and inf", function()
  T.eq(MK.Deserialize(MK.Serialize(42)), 42)
  T.eq(MK.Deserialize(MK.Serialize("s")), "s")
  T.eq(MK.Deserialize(MK.Serialize(false)), false)
  T.eq(MK.Deserialize(MK.Serialize(math.huge)), math.huge)
  T.eq(MK.Deserialize(MK.Serialize(-math.huge)), -math.huge)
end)

T.test("unsupported values dropped, deep nesting rejected", function()
  local back = MK.Deserialize(MK.Serialize({ f = print, ok = 1 }))
  T.eq(back.f, nil); T.eq(back.ok, 1)
  local t = {}
  local cur = t
  for _ = 1, 40 do cur.n = {}; cur = cur.n end
  local text, err = MK.Serialize(t)
  T.eq(text, nil); T.ok(err)
  local cyc = {}; cyc.self = cyc
  T.eq((MK.Serialize(cyc)), nil)
end)

T.test("parser rejects garbage without erroring", function()
  for _, bad in ipairs({ "", "{", "{;", "#abc;", '"99:short', "{;}x", "os.exit()", "{#1;}", "@", '"x:1', "{;{;}1}" }) do
    local v, err = MK.Deserialize(bad)
    T.eq(v, nil, bad); T.ok(err, "err for " .. bad)
  end
  local v, err = MK.Deserialize(nil)
  T.eq(v, nil); T.ok(err)
end)

T.test("base64 known vectors and binary", function()
  T.eq(MK.Base64Encode(""), "")
  T.eq(MK.Base64Encode("f"), "Zg==")
  T.eq(MK.Base64Encode("fo"), "Zm8=")
  T.eq(MK.Base64Encode("foo"), "Zm9v")
  T.eq(MK.Base64Encode("foobar"), "Zm9vYmFy")
  T.eq(MK.Base64Decode("Zm9vYmFy"), "foobar")
  T.eq(MK.Base64Decode("Zg=="), "f")
  local bin = {}
  for i = 0, 255 do bin[#bin + 1] = string.char(i) end
  bin = table.concat(bin)
  T.eq(MK.Base64Decode(MK.Base64Encode(bin)), bin)
  T.eq(MK.Base64Decode("Zm9v!mFy"), nil)
  T.eq(MK.Base64Decode("Zm9"), nil)
end)

T.test("adler32 known value", function()
  T.eq(MK.Adler32("Wikipedia"), 0x11E60398)
  T.eq(MK.Adler32(""), 1)
end)

T.test("export / import round trip", function()
  local s = MK.ExportString("elders", sample)
  T.ok(s:match("^WOM1:elders:[%w%+/=]+:%x%x%x%x%x%x%x%x$"), s)
  local tag, v = MK.ImportString("  " .. s .. "\n")
  T.eq(tag, "elders")
  T.ok(deepEq(sample, v))
  T.eq(MK.ExportString("bad tag", {}), nil)
end)

T.test("corrupted checksum / payload rejected", function()
  local s = MK.ExportString("x", { a = 1 })
  local bad = s:sub(1, -2) .. (s:sub(-1) == "0" and "1" or "0")
  local tag, err = MK.ImportString(bad)
  T.eq(tag, nil); T.eq(err, "checksum mismatch")
  local body = s:match("^WOM1:x:([^:]+):")
  local flipped = s:gsub(body, (body:sub(1, 2) == "ey" and "ez" or "ey") .. body:sub(3), 1)
  tag = MK.ImportString(flipped)
  T.eq(tag, nil)
  T.eq((MK.ImportString("hello")), nil)
  T.eq((MK.ImportString(42)), nil)
end)

T.done()
