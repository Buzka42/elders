-- The Elders stats panel: bracket tabs (1-10 ... 51-60, All) over StatRows sections computed from the raw bracket sums.
-- Pure math lives in UI.Sections (no frames), the window is created lazily on first TOGGLE_PANEL.
--
-- CONTRACT NOTE: "All" sums every bracket; rates always divide by bracket `sec` (hours = sec / 3600) and show "—" under 60 s.

local ADDON, ns = ...
local MK = MetaKit
local U = MK.Util
local UI = ns.UI
local A = ns.A
local DASH = UI.DASH

local MAX_BRACKET = 6
local PANEL_W = 460
local ACT_COPPER_IN = { "loot", "vendor", "quest", "mail", "trade", "ah", "otherIn" }
local ACT_COPPER_OUT = { "repair", "buy", "taxi", "train", "otherOut" }

---------------------------------------------------------------------------
-- Data

local function sumInto(dst, src)
  for k, v in pairs(src) do
    if k ~= "ritual" then
      if type(v) == "number" then
        dst[k] = (type(dst[k]) == "number" and dst[k] or 0) + v
      elseif type(v) == "table" then
        if type(dst[k]) ~= "table" then dst[k] = {} end
        sumInto(dst[k], v)
      end
    end
  end
  return dst
end

-- Bracket data for tab 1..MAX_BRACKET, or MAX_BRACKET + 1 for "All": shaped table + the level rows it covers.
function UI.BracketData(tab)
  local char = ns.char
  local out = U.EnsureShape({}, ns.BRACKET_DEFAULTS)
  local levels = {}
  if not char then return out, levels end
  if tab > MAX_BRACKET then
    for _, b in pairs(char.brackets or {}) do sumInto(out, b) end
    for lvl, row in pairs(char.levels or {}) do levels[lvl] = row end
  else
    local b = char.brackets and char.brackets[tab]
    if b then sumInto(out, b) end
    for lvl = (tab - 1) * 10 + 1, tab * 10 do
      local row = char.levels and char.levels[lvl]
      if row then levels[lvl] = row end
    end
  end
  return out, levels
end

local function zoneName(mapID)
  local ok, info = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) end)
  if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
  return "Zone " .. tostring(mapID)
end

local function total(t, keys)
  local s = 0
  for _, k in ipairs(keys) do s = s + (t[k] or 0) end
  return s
end

local function row(label, value, sub, tooltip)
  return { label = label, value = value, sub = sub, tooltip = tooltip }
end

-- Returns the StatRows sections for a tab.
function UI.Sections(tab)
  local b, levels = UI.BracketData(tab)
  local hours = b.sec / 3600
  local enough = b.sec >= 60
  local function rate(x) return enough and UI.Num(x / hours) or DASH end
  local function money(c) return U.Money(c) end
  local function moneyRate(c) return enough and U.Money(c / hours) or DASH end

  -- Pace
  local lvlSec, lvlN = 0, 0
  for _, r in pairs(levels) do
    if (r.sec or 0) > 0 then lvlSec = lvlSec + r.sec; lvlN = lvlN + 1 end
  end
  local pace = { title = "Pace", rows = {
    row("XP per hour", rate(b.xp), enough and (UI.Num(b.xp) .. " XP total") or nil),
    row("XP per kill", b.killsXP > 0 and UI.Num(b.xpKill / b.killsXP) or DASH, b.killsXP .. " kills with XP"),
    row("XP from quests", b.xp > 0 and UI.Pct(b.xpQuest / b.xp) or DASH, b.quests .. " quests turned in"),
    row("Time per level", lvlN > 0 and U.Duration(lvlSec / lvlN) or DASH, lvlN > 0 and (lvlN .. " levels timed") or nil),
    row("Time rested", enough and UI.Pct(b.rested.sec / b.sec) or DASH,
      b.xpRested > 0 and (UI.Num(b.xpRested) .. " bonus XP") or nil),
  } }

  -- Downtime
  local actTotal = 0
  for _, v in pairs(b.act) do actTotal = actTotal + v end
  local function share(n) return actTotal >= 60 and UI.Pct(n / actTotal) or DASH end
  local down = { title = "Downtime", rows = {
    row("In combat", share(b.act.combat)),
    row("On foot", share(b.act.moving)),
    row("Mounted", share(b.act.mounted)),
    row("Standing idle", share(b.act.idle)),
    row("Eating and drinking", share(b.act.eat + b.act.drink)),
    row("Dead or ghost", share(b.act.dead + b.act.ghost)),
    row("On flight paths", share(b.act.taxi)),
    row("Corpse run, average", (b.deaths > 0 and b.ghostSec > 0) and U.Duration(b.ghostSec / b.deaths) or DASH,
      b.spiritRes > 0 and (b.spiritRes .. " spirit healer visits") or nil),
    row("Deaths", tostring(b.deaths)),
    row("Deaths per hour", rate(b.deaths)),
  } }

  -- Combat
  local mobN, mobSum = 0, 0
  for i, n in ipairs(b.mobDelta) do mobN = mobN + n; mobSum = mobSum + n * (i - 6) end
  local combat = { title = "Combat", rows = {
    row("Fights", tostring(b.fights)),
    row("Average fight", b.fights > 0 and U.Duration(b.fightSec / b.fights) or DASH),
    row("Damage per second", b.meterSec >= 5 and UI.Num(b.dmg / b.meterSec) or DASH,
      b.meterSec >= 5 and ("over " .. U.Duration(b.meterSec) .. " of fights") or nil),
    row("Damage taken per hour", rate(b.taken)),
    row("Healing per hour", rate(b.heal)),
    row("Interrupts", tostring(b.interrupts), b.interruptCasts > 0 and (b.interruptCasts .. " casts") or nil),
    row("Dispels", tostring(b.dispels), b.dispelCasts > 0 and (b.dispelCasts .. " casts") or nil),
    row("Crowd control casts", tostring(b.ccCasts)),
    row("Elites slain alone", tostring(b.eliteSolo)),
    row("Kills per hour", rate(b.kills), b.kills .. " kills"),
    row("Mob level vs. yours", mobN > 0 and string.format("%+.1f", mobSum / mobN) or DASH),
  } }

  -- Economy
  local gross, repair = total(b.copper, ACT_COPPER_IN), b.copper.repair or 0
  local spent = total(b.copper, ACT_COPPER_OUT)
  local bestName, bestRate
  for id, z in pairs(b.zones) do
    if (z.sec or 0) >= 60 and (z.copper or 0) > 0 then
      local r = z.copper / (z.sec / 3600)
      if not bestRate or r > bestRate then bestRate = r; bestName = zoneName(id) end
    end
  end
  local econ = { title = "Economy", rows = {
    row("Gold per hour (gross)", moneyRate(gross), money(gross) .. " earned"),
    row("Gold per hour (after repairs)", moneyRate(gross - repair), nil,
      "Gross income minus repair bills. Other spending is shown below."),
    row("Repairs", money(repair)),
    row("Spent in all", money(spent)),
    row("Vendor trips per hour", rate(b.vendorTrips), b.vendorTrips .. " trips"),
    row("Best zone for gold", bestName or DASH, bestRate and (U.Money(bestRate) .. " per hour") or nil),
  } }

  -- Dungeons
  local runs, clears, clearSec, wipes = 0, 0, 0, 0
  for _, d in pairs(b.dungeons) do
    runs = runs + (d.runs or 0); clears = clears + (d.clears or 0)
    clearSec = clearSec + (d.clearSec or 0); wipes = wipes + (d.wipes or 0)
  end
  local dung = { title = "Dungeons", rows = {
    row("Runs", tostring(runs)),
    row("Clears", tostring(clears)),
    row("Average clear time", clears > 0 and U.Duration(clearSec / clears) or DASH),
    row("Wipes per run", runs > 0 and UI.Num(wipes / runs) or DASH, wipes .. " wipes"),
    row("Time to form a group", b.lfg.n > 0 and U.Duration(b.lfg.formSec / b.lfg.n) or DASH,
      b.lfg.n > 0 and (b.lfg.n .. " groups") or nil),
  } }

  -- Professions
  local profNames = {}
  for name in pairs(b.prof) do profNames[#profNames + 1] = name end
  table.sort(profNames)
  local prof = { title = "Professions", rows = {} }
  for _, name in ipairs(profNames) do
    prof.rows[#prof.rows + 1] = row(name, enough and (UI.Num(b.prof[name] / hours) .. " per hour") or DASH,
      "+" .. b.prof[name] .. " points")
  end
  if #prof.rows == 0 then prof.rows[1] = row("No skill gained yet", DASH) end

  -- Talents
  local lvls = {}
  for lvl, r in pairs(levels) do
    if type(r.talents) == "string" and r.talents ~= "" then lvls[#lvls + 1] = lvl end
  end
  table.sort(lvls)
  local tal = { title = "Talents", rows = {} }
  for _, lvl in ipairs(lvls) do
    local s = levels[lvl].talents
    tal.rows[#tal.rows + 1] = row("Level " .. lvl, U.Truncate(s, 26), nil, s)
  end
  if #tal.rows == 0 then tal.rows[1] = row("No snapshot yet", DASH) end

  return { pace, down, combat, econ, dung, prof, tal }
end

-- One-line numbers for the minimap tooltip: xp/h text, gold/h text for the tab.
function UI.Quick(tab)
  local b = UI.BracketData(tab)
  if b.sec < 60 then return DASH, DASH end
  local h = b.sec / 3600
  return UI.Num(b.xp / h), U.Money(total(b.copper, ACT_COPPER_IN) / h)
end

function UI.CurrentTab()
  local l = ns.Agg and ns.Agg.Level() or 1
  return U.Clamp(U.BracketOf(l), 1, MAX_BRACKET)
end

---------------------------------------------------------------------------
-- Window

local win, rows, tabs, tab
local hdr = {}

local function header()
  local c = ns.char
  if not (c and hdr.name) then return end
  if hdr.class then pcall(hdr.class.SetClass, hdr.class, c.class) end
  hdr.name:SetText((c.name or UnitName and UnitName("player") or "?") .. ", level " .. (ns.Agg.Level() or 1))
  local rank = UI.Rank(c.id)
  hdr.rank:SetText(UI.RankName(rank))
  if hdr.icon then
    local tex = UI.Art(string.format("elder_rank_%02d", rank))
    if tex then pcall(hdr.icon.SetIcon, hdr.icon, tex) end
  end
  local n = A:PendingCount() or 0
  hdr.pending:SetText(n > 0 and (n .. " rows waiting to sync") or "Everything is synced")
end

local function refresh()
  if not (win and rows) then return end
  header()
  rows:SetSections(UI.Sections(tab))
end
UI.RefreshPanel = refresh

local function build()
  if win then return win end
  if not (MK.UI and MK.UI.Window and MK.UI.StatRows and MK.UI.Tabs) then
    A:Print("The interface kit is not loaded, so the panel cannot open.")
    return nil
  end
  UI.ApplyTheme()
  local cfg = A.db.config
  cfg.panel = cfg.panel or {}
  win = MK.UI.Window{ name = "EldersPanel", skin = UI.SKIN, width = PANEL_W, height = 560,
    title = "The Elders", subtitle = "What the road has taught you", db = cfg.panel }
  local c = win.content
  local inner = PANEL_W - 16 -- window gutter 8 on each side

  -- character row (32 px): rank badge left, name and rank beside it, sync status right
  if MK.UI.Icon then
    hdr.icon = MK.UI.Icon(c, { size = 32, texture = UI.Art("elder_rank_01") })
    hdr.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
  end
  hdr.name = MK.UI.Label(c, { text = "", font = "body", justify = "LEFT" })
  hdr.name:SetPoint("TOPLEFT", c, "TOPLEFT", 40, -2)
  hdr.rank = MK.UI.Label(c, { text = "", font = "small", color = "muted", justify = "LEFT" })
  hdr.rank:SetPoint("TOPLEFT", c, "TOPLEFT", 40, -20)
  hdr.pending = MK.UI.Label(c, { text = "", font = "small", color = "muted", justify = "RIGHT" })
  hdr.pending:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -2)
  if MK.UI.ClassIcon then
    hdr.class = MK.UI.ClassIcon(c, 16)
    hdr.class:SetPoint("BOTTOMRIGHT", c, "TOPRIGHT", 0, -32)
  end

  tab = tab or UI.CurrentTab()
  local labels = {}
  for i = 1, MAX_BRACKET do labels[i] = U.BracketLabel(i) end
  labels[MAX_BRACKET + 1] = "All"
  tabs = MK.UI.Tabs(c, { labels = labels, skin = UI.SKIN, width = inner, onSelect = function(i)
    if type(i) == "number" and i ~= tab then tab = i; refresh() end
  end })
  tabs:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -40)

  rows = MK.UI.StatRows(c, { skin = UI.SKIN })
  rows:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -72)
  rows:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 32)

  -- three equal buttons across the content, 8 px apart, flush with the content bottom (8 px above the window edge)
  local bw = (inner - 16) / 3
  local function button(text, slot, onClick, tip)
    local btn = MK.UI.Button(c, { text = text, width = bw, height = 24, onClick = onClick, tooltip = tip, skin = UI.SKIN })
    btn:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", (slot - 1) * (bw + 8), 0)
    return btn
  end
  button("Sync", 1, function() ReloadUI() end, "Reload the interface so the Meta Uploader can pick up new data.")
  button("Export", 2, function() A:Fire("SHOW_EXPORT") end, "Copy your stats as a string for the website.")
  button("Settings", 3, function() UI.OpenSettings() end)

  pcall(tabs.Select, tabs, tab)
  win:HookScript("OnShow", refresh)
  A:Every(5, function() if win:IsShown() then refresh() end end)
  return win
end

A:Listen("TOGGLE_PANEL", function()
  if not build() then return end
  win:Toggle()
  if win:IsShown() then refresh() end
end)

UI.Panel = function() return win end
