-- Social: data path of the level ritual (rating, insight votes, free-text insight) and ns.Insights().
-- Messages come from the UI: RITUAL_SUBMIT(bracket, pve, pvp, votes, text) / RITUAL_SKIP(bracket).

local ADDON, ns = ...
local A = ns.A
local MK = MetaKit
local M = A:NewModule("Social")
local Agg = ns.Agg

local MAX_TEXT = 280

local function stars(v)
  v = tonumber(v)
  if not v then return nil end
  return MK.Util.Clamp(math.floor(v + 0.5), 0, 5)
end

local function cleanText(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("|", ""):gsub("%c", " "):gsub("%s+", " ")
  text = strtrim(text)
  return MK.Util.Truncate(text, MAX_TEXT)
end

local function bracketTable(bracket)
  return (Agg.Bracket((bracket - 1) * 10 + 1))
end

local function onSubmit(bracket, pve, pvp, votes, text)
  bracket = tonumber(bracket)
  if not bracket or bracket < 1 then return end
  local b = bracketTable(bracket)
  local class = ns.char and ns.char.class
  local rated = b.ritual.pve ~= nil or b.ritual.pvp ~= nil
  if not rated then
    b.ritual.pve, b.ritual.pvp, b.ritual.at = stars(pve), stars(pvp), MK.Util.ServerTime()
    b.ritual.skipped = nil
    A:Push("rating", { bracket = bracket, pve = b.ritual.pve, pvp = b.ritual.pvp, class = class,
      race = ns.char and ns.char.race, faction = ns.char and ns.char.faction })
  end
  local seen = A.db.votes
  if type(votes) == "table" then
    for _, vote in ipairs(votes) do
      local id, v = vote.id, tonumber(vote.v)
      if id ~= nil and (v == 1 or v == -1) and seen[id] == nil then
        seen[id] = v
        A:Push("vote", { insight = id, v = v, class = class })
      end
    end
  end
  text = cleanText(text)
  if text ~= "" and not rated then
    A:Push("insight", { bracket = bracket, class = class, text = text })
  end
end

local function onSkip(bracket)
  bracket = tonumber(bracket)
  if not bracket or bracket < 1 then return end
  bracketTable(bracket).ritual.skipped = true
end

-- Up to n insights for `class` that this account has not voted on, in random order.
function ns.Insights(class, n)
  local src = MK.Wom("elders", "insights", class)
  local pool = {}
  if type(src) == "table" then
    for _, ins in ipairs(src) do
      if type(ins) == "table" and ins.id ~= nil and type(ins.text) == "string" and A.db.votes[ins.id] == nil then
        pool[#pool + 1] = ins
      end
    end
  end
  local out = {}
  for _ = 1, math.min(n or 3, #pool) do
    local i = math.random(#pool)
    out[#out + 1] = table.remove(pool, i)
  end
  return out
end

A:Listen("RITUAL_SUBMIT", onSubmit)
A:Listen("RITUAL_SKIP", onSkip)
