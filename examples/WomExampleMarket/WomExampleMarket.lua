-- Example extension for the World of Meta addon API (docs/ADDON_API.md).
-- Registers a "First blood" Ring market and a stub section. Loads after Elders / Bloodsports through OptionalDeps,
-- which is what makes the MetaKit global (embedded in them) exist when this file runs.
local ADDON = ...

local MK = _G.MetaKit
if not (MK and MK.Ext and MK.Ext.Compatible(1)) then return end   -- no host addon, or one older than Ext v1: do nothing

local function short(name) return (tostring(name or ""):match("^([^-]+)")) or "?" end

-- Market: who draws first blood. Two outcomes, named after the fighters the Ring hands us.
local ok, err = MK.Ext.Register("market", "firstblood", {
  owner = ADDON,
  label = "First blood",
  lockOn = "fight",
  outcomes = function(ctx)
    if not (ctx.a and ctx.b) then return nil, "needs two fighters" end
    return {
      { label = short(ctx.a) .. " first", ref = ctx.a },
      { label = short(ctx.b) .. " first", ref = ctx.b },
    }
  end,
  -- Return an outcome index, false to void, or nil to leave it to the referee. The host fills event.firstBlood (a full
  -- fighter name) only when it knows; without it the market is settled by hand.
  settle = function(market, event)
    if event.type ~= "fight_end" or not event.firstBlood then return nil end
    for i, o in ipairs(market.outcomes) do
      if o.ref == event.firstBlood then return i end
    end
    return nil
  end,
})
if not ok then print(ADDON .. ": " .. tostring(err)) end

-- Section stub: one pane in the Bloodsports tab of the shared window, built lazily the first time it is opened.
ok, err = MK.Ext.Register("section", "example_market", {
  owner = ADDON,
  tab = "bloodsports",
  label = "Example",
  order = 90,
  build = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, -16)
    fs:SetText("WoM Example Market is installed. Markets: " .. table.concat(MK.Ext.List("market"), ", "))
    return f
  end,
})
if not ok then print(ADDON .. ": " .. tostring(err)) end
