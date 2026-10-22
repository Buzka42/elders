-- Economy: classifies every PLAYER_MONEY delta by the window that is open or the event that fired within 2 s
-- (merchant, mail, trade, auction house, taxi, trainer, loot, quest), tracks repairs, vendor trips and bag fullness.

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Economy")
local Agg = ns.Agg

local RECENT = 2
local lastMoney
local repairCost = 0
local repairHookAt = -100
local open = {}                -- window name -> true while open
local recent = { tag = nil, t = -100 }
local queue = {}               -- unclassified deltas waiting for a late tag event
local ORDER = { "merchant", "trade", "mail", "ah", "train", "taxi" }

local IN_KEYS = { loot = "loot", merchant = "vendor", quest = "quest", mail = "mail", trade = "trade", ah = "ah" }

local function cacheRepair()
  local cost = MK.Call(GetRepairAllCost)
  if type(cost) == "number" then repairCost = cost end
end

-- Returns the bracket key under "copper" for a delta in the given context.
local function bucket(tag, delta)
  if delta > 0 then return IN_KEYS[tag] or "otherIn" end
  if tag == "merchant" then
    local amount = -delta
    if (repairCost > 0 and amount == repairCost) or GetTime() - repairHookAt < 1 then return "repair" end
    return "buy"
  end
  if tag == "taxi" then return "taxi" end
  if tag == "train" then return "train" end
  return "otherOut"
end

local function credit(tag, delta)
  local key = bucket(tag, delta)
  Agg.Add("copper", math.abs(delta), key)
  if delta > 0 then
    local map = ns.MapID and ns.MapID()
    if map then
      local z = Agg.Rec("zones", map, { sec = 0, xp = 0, copper = 0 })
      z.copper = z.copper + delta
    end
  end
  if key == "repair" then repairCost = 0 end
end

local function currentTag()
  for _, name in ipairs(ORDER) do if open[name] then return name end end
  if recent.tag and GetTime() - recent.t <= RECENT then return recent.tag end
end

local function drain(tag)
  for i = 1, #queue do credit(tag, queue[i]) end
  queue = {}
end

local function setTag(tag)
  recent.tag, recent.t = tag, GetTime()
  if #queue > 0 then drain(tag) end
end

local function onMoney()
  local now = MK.Call(GetMoney)
  if type(now) ~= "number" then return end
  if not lastMoney then lastMoney = now return end
  local delta = now - lastMoney
  lastMoney = now
  if delta == 0 then return end
  local tag = currentTag()
  if tag then
    credit(tag, delta)
  else
    -- a CHAT_MSG_MONEY / QUEST_TURNED_IN may arrive just after PLAYER_MONEY
    queue[#queue + 1] = delta
    A:After(0.3, function()
      if #queue > 0 then drain(nil) end
    end)
  end
end

local function window(name, shown)
  return function()
    open[name] = shown or nil
    recent.tag, recent.t = name, GetTime()
    if shown and name == "merchant" then
      Agg.Add("vendorTrips", 1)
      cacheRepair()
      M.BagSnapshot()
    end
  end
end

-- Fraction of bag slots in use (0..1) added to bagFullSum; skipped when the container API is missing.
function M.BagSnapshot()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerNumFreeSlots) then return end
  local total, free = 0, 0
  for bag = 0, 4 do
    local n = MK.Call(C.GetContainerNumSlots, bag)
    local f = MK.Call(C.GetContainerNumFreeSlots, bag)
    if type(n) == "number" and type(f) == "number" then total, free = total + n, free + f end
  end
  if total > 0 then Agg.Add("bagFullSum", (total - free) / total) end
end

function M:OnLogin()
  lastMoney = MK.Call(GetMoney)
  pcall(hooksecurefunc, "RepairAllItems", function() repairHookAt = GetTime() end)
end

A:On("PLAYER_MONEY", onMoney)
A:On("CHAT_MSG_MONEY", function() setTag("loot") end)
A:On("QUEST_TURNED_IN", function() setTag("quest") end)
for _, w in ipairs({ { "merchant", "MERCHANT_SHOW", "MERCHANT_CLOSED" }, { "mail", "MAIL_SHOW", "MAIL_CLOSED" },
    { "trade", "TRADE_SHOW", "TRADE_CLOSED" }, { "ah", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
    { "taxi", "TAXIMAP_OPENED", "TAXIMAP_CLOSED" }, { "train", "TRAINER_SHOW", "TRAINER_CLOSED" } }) do
  A:On(w[2], window(w[1], true))
  A:On(w[3], window(w[1], false))
end
A:On("MERCHANT_UPDATE", cacheRepair)
A:On("UPDATE_INVENTORY_DURABILITY", cacheRepair)
