-- Elders core: DB schema, character/bracket aggregation helpers, slash commands, link/export.
-- Collectors (Collect/*.lua) only call ns.Agg.* and A:Push; UI (UI/*.lua) only reads ns.Agg / db.

local ADDON, ns = ...
local MK = MetaKit
local U = MK.Util

local A = MK.NewAddon(ADDON, { color = "3fbf6a" })
ns.A = A
Elders = A -- global for debugging (/dump Elders.db)

---------------------------------------------------------------------------
-- Schema

local DEFAULTS = {
  config = { ritual = true, toasts = true, panel = {} },
  votes = {},        -- [insightId] = 1 | -1, dedupe across characters
}

-- One bracket = levels (b-1)*10+1 .. b*10. All values are running sums/counts; means are computed on read.
ns.BRACKET_DEFAULTS = {
  sec = 0,                         -- seconds of play attributed to this bracket (activity ticker)
  xp = 0, xpQuest = 0, xpKill = 0, xpOther = 0, xpRested = 0, quests = 0,
  kills = 0, killsXP = 0, eliteSolo = 0,
  fights = 0, fightSec = 0,
  dmg = 0, meterSec = 0, taken = 0, heal = 0, absorb = 0, interrupts = 0, dispels = 0,
  ccCasts = 0, interruptCasts = 0, dispelCasts = 0, tauntCasts = 0,
  deaths = 0, deadSec = 0, ghostSec = 0, spiritRes = 0,
  act = { combat = 0, eat = 0, drink = 0, dead = 0, ghost = 0, taxi = 0, mounted = 0, moving = 0, idle = 0 },
  copper = { loot = 0, vendor = 0, quest = 0, mail = 0, trade = 0, ah = 0, otherIn = 0,
             repair = 0, buy = 0, taxi = 0, train = 0, otherOut = 0 },
  mobDelta = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },   -- mob level minus player level, -5..+5 (clamped) -> index 1..11
  fightHist = { 0, 0, 0, 0, 0, 0 },                  -- fight length bins: <5, <10, <20, <40, <80, 80+ seconds
  deathCtx = { solo = 0, group = 0, dungeon = 0, pvp = 0 },
  roleCasts = { heal = 0, tank = 0 },
  dungeons = {},     -- [instanceID] = { runs, clears, clearSec, wipes, deaths }
  lfg = { n = 0, formSec = 0, enterSec = 0 },
  prof = {},         -- [skillName] = points gained
  zones = {},        -- [mapID] = { sec, xp, copper }
  groupSec = 0, groupSizeSec = 0,
  vendorTrips = 0, bagFullSum = 0,
  rested = { sec = 0 },
  ritual = {},       -- { pve, pvp, at, skipped }
}

ns.LEVEL_DEFAULTS = {
  -- sec: seconds spent in this level (from TIME_PLAYED_MSG level time at ding), deaths: deaths at this level,
  -- talents: compact talent string at ding, ilvl, dodge/parry/block/crit snapshots
}

local CHAR_DEFAULTS = {
  brackets = {},
  levels = {},
  played = {},       -- { total, level, at }
}

local MIGRATIONS = {}

function A:OnInit()
  self:InitDB("EldersDB", DEFAULTS, MIGRATIONS, CHAR_DEFAULTS)
end

function A:OnLogin()
  ns.char = self:Char()
  local dropped = self:CompactOutbox()
  if dropped > 0 then self:Debug("outbox compacted: " .. dropped) end
  ns.Agg.Refresh()
end

---------------------------------------------------------------------------
-- Aggregation helpers (the only write path for collectors)

local Agg = {}
ns.Agg = Agg
local level = 1

function Agg.Refresh()
  ns.char = A:Char()
  level = ns.char.level or MK.Call(UnitLevel, "player") or 1
end

function Agg.Level() return level end
function Agg.SetLevel(l) level = l; if ns.char then ns.char.level = l end end

-- Bracket table for a level (default: current level), created on demand with full shape.
function Agg.Bracket(lvl)
  if not ns.char then Agg.Refresh() end
  local b = U.BracketOf(lvl or level)
  local t = ns.char.brackets[b]
  if not t then
    t = U.EnsureShape({}, ns.BRACKET_DEFAULTS)
    ns.char.brackets[b] = t
  end
  return t, b
end

-- Per-level row (talents, time, deaths, stat snapshots).
function Agg.LevelRow(lvl)
  if not ns.char then Agg.Refresh() end
  lvl = lvl or level
  local t = ns.char.levels[lvl]
  if not t then
    t = { sec = 0, deaths = 0 }
    ns.char.levels[lvl] = t
  end
  return t
end

-- Agg.Add("kills", 1) or Agg.Add("copper", 120, "loot") for a nested group.
function Agg.Add(key, n, sub)
  local b = Agg.Bracket()
  if sub then
    local g = b[key]
    g[sub] = (g[sub] or 0) + n
  else
    b[key] = (b[key] or 0) + n
  end
end

-- Histogram increment: Agg.Hist("fightHist", 3)
function Agg.Hist(key, index, n)
  local h = Agg.Bracket()[key]
  h[index] = (h[index] or 0) + (n or 1)
end

-- Keyed sub-record: Agg.Rec("dungeons", instanceID, { runs = 0, ... }) returns the record (created with defaults).
function Agg.Rec(key, id, defaults)
  local g = Agg.Bracket()[key]
  local r = g[id]
  if not r then
    r = U.EnsureShape({}, defaults or {})
    g[id] = r
  end
  return r
end

---------------------------------------------------------------------------
-- Slash commands

A:Slash({ "/elders", "/eld" })

A:Command("", "toggle the stats panel", function() A:Fire("TOGGLE_PANEL") end)
A:Command("show", "show - toggle the stats panel", function() A:Fire("TOGGLE_PANEL") end)

A:Command("link", "link CODE - bind this character to your World of Meta account", function(code)
  code = (code or ""):upper():gsub("%s", "")
  if #code ~= 8 or not code:match("^%w+$") then
    A:Print("usage: /elders link CODE (8 letters or digits from the World of Meta site)")
    return
  end
  A:Push("link", { code = code, charId = ns.char.id })
  A:Print("link code stored. It is sent the next time you log out or press Sync.")
end)

A:Command("sync", "sync - reload the UI so the Meta Uploader picks up new data", function() ReloadUI() end)

A:Command("export", "export - copy your stats as a string for the site", function()
  A:Fire("SHOW_EXPORT")
end)

A:Command("ritual", "ritual - open the level ritual for your last finished bracket (testing)", function()
  A:Fire("RITUAL_OPEN", math.max(1, U.BracketOf(level) - 1), true)
end)

A:Command("debug", "debug - toggle debug output", function()
  A.db.config.debug = not A.db.config.debug
  A:Print("debug " .. (A.db.config.debug and "on" or "off"))
end)

-- Export payload shared by the UI and the uploader fallback.
function ns.ExportPayload()
  local c = ns.char
  return {
    v = 1, addon = ADDON, install = A.db.installId, ruleset = c.ruleset,
    char = { id = c.id, name = c.name, realm = c.realm, class = c.class, race = c.race, faction = c.faction, level = c.level },
    brackets = c.brackets, levels = c.levels,
  }
end
