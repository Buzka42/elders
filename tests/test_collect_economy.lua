-- Economy collector: money delta classification, repairs, vendor trips, zone copper.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local Agg = ns.Agg

local function c() return Agg.Bracket().copper end

T.test("loot: CHAT_MSG_MONEY before or after PLAYER_MONEY", function()
  T.Fire("CHAT_MSG_MONEY", "You loot 12 Copper")
  T.SetMoney(12)
  T.eq(c().loot, 12)
  T.Advance(5)
  T.SetMoney(30)           -- money event first, loot text after
  T.Fire("CHAT_MSG_MONEY", "You loot 18 Copper")
  T.eq(c().loot, 30)
  T.Advance(5)
end)

T.test("unattributed income / spending falls into other", function()
  T.SetMoney(30 + 100)
  T.Advance(1)
  T.eq(c().otherIn, 100)
  T.SetMoney(130 - 40)
  T.Advance(1)
  T.eq(c().otherOut, 40)
end)

T.test("vendor sale, purchase and repair", function()
  local b = Agg.Bracket()
  local trips = b.vendorTrips
  T.repairCost = 250
  T.Fire("MERCHANT_SHOW")
  T.eq(b.vendorTrips, trips + 1)
  T.SetMoney(T.money + 500)
  T.eq(c().vendor, 500)
  T.SetMoney(T.money - 90)
  T.eq(c().buy, 90)
  T.SetMoney(T.money - 250)
  T.eq(c().repair, 250, "delta equals cached repair cost")
  T.repairCost = 0
  T.Fire("MERCHANT_CLOSED")
  T.SetMoney(T.money + 7)      -- late sale still inside the 2 s window
  T.eq(c().vendor, 507)
  T.Advance(5)
end)

T.test("quest, mail, trade, auction house, taxi, trainer", function()
  local m = T.money
  T.Fire("QUEST_TURNED_IN", 1, 100, 300); T.SetMoney(m + 300); T.eq(c().quest, 300); T.Advance(5); m = T.money
  T.Fire("MAIL_SHOW"); T.SetMoney(m + 1000); T.eq(c().mail, 1000); T.SetMoney(T.money - 30); T.eq(c().otherOut, 40 + 30)
  T.Fire("MAIL_CLOSED"); T.Advance(5); m = T.money
  T.Fire("TRADE_SHOW"); T.SetMoney(m + 5000); T.eq(c().trade, 5000); T.Fire("TRADE_CLOSED"); T.Advance(5); m = T.money
  T.Fire("AUCTION_HOUSE_SHOW"); T.SetMoney(m + 800); T.eq(c().ah, 800); T.Fire("AUCTION_HOUSE_CLOSED"); T.Advance(5); m = T.money
  T.Fire("TAXIMAP_OPENED"); T.Fire("TAXIMAP_CLOSED"); T.SetMoney(m - 120); T.eq(c().taxi, 120); T.Advance(5); m = T.money
  T.Fire("TRAINER_SHOW"); T.SetMoney(m - 400); T.eq(c().train, 400); T.Fire("TRAINER_CLOSED"); T.Advance(5)
end)

T.test("zone copper counts gross income only", function()
  local z = Agg.Bracket().zones[T.map.id]
  T.ok(z, "zone record")
  T.eq(z.copper, 12 + 18 + 100 + 500 + 7 + 300 + 1000 + 5000 + 800)
end)

T.test("bag fullness snapshot at the vendor (when the container API exists)", function()
  local b = Agg.Bracket()
  C_Container = {
    GetContainerNumSlots = function() return 10 end,
    GetContainerNumFreeSlots = function(bag) return bag < 2 and 0 or 10 end,
  }
  local s0 = b.bagFullSum
  T.Fire("MERCHANT_SHOW")
  T.near(b.bagFullSum, s0 + 0.4, 1e-9)
  T.Fire("MERCHANT_CLOSED")
  C_Container = nil
  T.noErrors()
end)

T.done()
