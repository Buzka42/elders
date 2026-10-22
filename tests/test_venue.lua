local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Venue" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit

local rows = {
  { id = "crossroads", kind = "practice", name = "The Crossroads", mapID = 1413, subzone = "The Crossroads", x = 0.52, y = 0.30, r = 0.035 },
  { id = "honorroad", kind = "club", name = "Honor Road", mapID = 1411, subzone = nil, x = 0.455, y = 0.13, r = 0.045 },
  { id = "tram", kind = "club", name = "Deeprun Tram", instanceMapID = 369, subzone = "Deeprun Tram" },
  { id = "ratchet", kind = "ring", name = "Ratchet", mapID = 1413, subzone = "Ratchet", x = 0.625, y = 0.375, r = 0.03 },
  { id = "subonly", kind = "ring", name = "Sub Only", mapID = 1413, subzone = "Hidden Spot" },
}
local reg = MK.Venue.New(rows)

local function at(id, x, y, sub)
  T.map.id, T.map.x, T.map.y, T.map.sub = id, x, y, sub or ""
  T.instance.inInstance = false
  reg:Invalidate()
end

T.test("Get and All", function()
  T.eq(reg:Get("tram").name, "Deeprun Tram")
  T.eq(reg:Get("nope"), nil)
  T.eq(#reg:All(), 5)
  T.eq(#reg:All("club"), 2)
  T.eq(#reg:All("koth"), 0)
end)

T.test("coords radius match", function()
  at(1413, 0.52, 0.30)
  T.eq(reg:Current().id, "crossroads")
  at(1413, 0.54, 0.31)
  T.eq(reg:Current().id, "crossroads")
  at(1413, 0.80, 0.80)
  T.eq(reg:Current(), nil)
  at(1411, 0.46, 0.14)
  T.eq(reg:Current().id, "honorroad")
  at(1429, 0.52, 0.30)
  T.eq(reg:Current(), nil, "wrong map")
end)

T.test("subzone fallback when coords miss", function()
  at(1413, 0.80, 0.80, "Ratchet")
  T.eq(reg:Current().id, "ratchet")
  at(1413, 0.1, 0.1, "Hidden Spot")
  T.eq(reg:Current().id, "subonly")
  at(1411, 0.1, 0.1, "Ratchet")
  T.eq(reg:Current(), nil, "subzone requires same map")
end)

T.test("coords win over subzone; subzone works without position", function()
  at(1413, 0.52, 0.30, "Ratchet")
  T.eq(reg:Current().id, "crossroads")
  at(1413, 0.5, 0.5, "Hidden Spot")
  T.map.x = nil
  reg:Invalidate()
  T.eq(reg:Current().id, "subonly")
  T.map.x = 0.5
end)

T.test("instance match first", function()
  at(1413, 0.52, 0.30)
  T.instance = { inInstance = true, type = "party", id = 369 }
  reg:Invalidate()
  T.eq(reg:Current().id, "tram")
  T.instance = { inInstance = true, type = "party", id = 999 }
  reg:Invalidate()
  T.eq(reg:Current().id, "crossroads", "falls through to coords")
  T.instance = { inInstance = false, type = "none" }
end)

T.test("snapshot", function()
  at(1413, 0.25, 0.75, "Somewhere")
  T.map.zone = "The Barrens"
  local s = reg:Snapshot()
  T.eq(s.mapID, 1413); T.eq(s.x, 0.25); T.eq(s.y, 0.75)
  T.eq(s.zone, "The Barrens"); T.eq(s.sub, "Somewhere"); T.eq(s.instanceID, nil)
  T.instance = { inInstance = true, type = "party", id = 369 }
  T.eq(reg:Snapshot().instanceID, 369)
  T.instance = { inInstance = false, type = "none" }
end)

T.test("1 s cache", function()
  at(1413, 0.52, 0.30)
  T.eq(reg:Current().id, "crossroads")
  T.map.x, T.map.y = 0.9, 0.9
  T.eq(reg:Current().id, "crossroads", "cached")
  T.Advance(1.1)
  T.eq(reg:Current(), nil)
end)

T.done()
