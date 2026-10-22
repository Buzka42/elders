-- WoW API stub for offline tests under lua5.1. Each test file runs in its own process:
--
--   local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
--   T.LoadAddon("Elders/Elders.toc")            -- loads every file listed in the TOC, fires ADDON_LOADED + PLAYER_LOGIN
--   T.test("xp gain counts", function()
--     T.units.player.xp = 500; T.Fire("PLAYER_XP_UPDATE", "player")
--     T.eq(EldersDB.chars[...].brackets[1].xp, 500)
--   end)
--   T.done()
--
-- State you can drive: T.clock (GetTime), T.units, T.money, T.map, T.instance, T.group, T.combat,
-- T.meter, T.auras, T.talents, T.skills, T.trade, T.repairCost, T.played, T.chatLocked, T.sent (captured addon msgs),
-- T.printed (captured print lines). Secrets: T.Secret(v) makes a value issecretvalue() reports as secret.

local T = { clock = 1000, serverBase = 1760000000, printed = {}, sent = {}, failures = 0, passes = 0 }
_G.T_STUB = T

local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Test helpers

function T.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    T.passes = T.passes + 1
    io.write("  ok   " .. name .. "\n")
  else
    T.failures = T.failures + 1
    io.write("  FAIL " .. name .. "\n    " .. tostring(err):gsub("\n", "\n    ") .. "\n")
  end
end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function T.eq(a, b, msg)
  if a ~= b then error((msg and (msg .. ": ") or "") .. "expected " .. fmt(b) .. ", got " .. fmt(a), 2) end
end

function T.ok(v, msg)
  if not v then error(msg or "expected truthy value", 2) end
end

function T.near(a, b, eps, msg)
  eps = eps or 1e-6
  if type(a) ~= "number" or math.abs(a - b) > eps then
    error((msg and (msg .. ": ") or "") .. "expected ~" .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

-- Fails if any addon printed an "error in" line (MetaKit reports handler errors that way).
function T.noErrors()
  for _, line in ipairs(T.printed) do
    if line:find("error in", 1, true) then error("addon error: " .. line, 2) end
  end
end

function T.done()
  io.write(string.format("%d passed, %d failed\n", T.passes, T.failures))
  os.exit(T.failures == 0 and 0 or 1)
end

---------------------------------------------------------------------------
-- Secrets

local SecretMT = { __tostring = function() return "<secret>" end }
function T.Secret(v) return setmetatable({ value = v }, SecretMT) end
function issecretvalue(v) return getmetatable(v) == SecretMT end
function canaccessvalue(v) return getmetatable(v) ~= SecretMT end

---------------------------------------------------------------------------
-- Clock and timers

function GetTime() return T.clock end
function GetServerTime() return T.serverBase + math.floor(T.clock) end
_G.time = function(t) if t then return os.time(t) end return GetServerTime() end
_G.date = os.date

local timers = {}
local function addTimer(delay, fn, interval, iterations)
  local t = { at = T.clock + delay, fn = fn, interval = interval, left = iterations, cancelled = false }
  function t:Cancel() self.cancelled = true end
  function t:IsCancelled() return self.cancelled end
  table.insert(timers, t)
  return t
end

C_Timer = {
  After = function(delay, fn) addTimer(delay, fn) end,
  NewTimer = function(delay, fn) return addTimer(delay, fn) end,
  NewTicker = function(delay, fn, iterations) return addTimer(delay, fn, delay, iterations) end,
}

-- Advances the clock, running due timers in order (tickers re-arm).
function T.Advance(sec)
  local target = T.clock + sec
  while true do
    local nextT
    for _, t in ipairs(timers) do
      if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then nextT = t end
    end
    if not nextT then break end
    T.clock = math.max(T.clock, nextT.at)
    if nextT.interval then
      nextT.at = nextT.at + nextT.interval
      if nextT.left then
        nextT.left = nextT.left - 1
        if nextT.left <= 0 then nextT.cancelled = true end
      end
    else
      nextT.cancelled = true
    end
    nextT.fn(nextT)
  end
  T.clock = target
  for i = #timers, 1, -1 do if timers[i].cancelled then table.remove(timers, i) end end
end

---------------------------------------------------------------------------
-- Frames and widgets (permissive: unknown methods are no-ops returning nil)

local frames = {}
T.unknownEvents = { COMBAT_LOG_EVENT_UNFILTERED = "forbidden" }

local Widget = {}
local WidgetMT = {
  __index = function(t, k)
    local m = Widget[k]
    if m then return m end
    -- internal "_field" state and lowercase data fields read as nil; only unknown Methods are no-ops
    if type(k) ~= "string" or k:sub(1, 1) == "_" or k:sub(1, 1):lower() == k:sub(1, 1) then return nil end
    return function() end
  end,
}

local function newWidget(kind, name, parent)
  local w = setmetatable({ _kind = kind, _scripts = {}, _events = {}, _unitEvents = {}, _shown = true,
    _w = 0, _h = 0, _text = nil, _parent = parent, _points = {}, _children = {} }, WidgetMT)
  if name then _G[name] = w end
  if parent and type(parent) == "table" and parent._children then table.insert(parent._children, w) end
  return w
end

function Widget:SetScript(s, fn) self._scripts[s] = fn end
function Widget:GetScript(s) return self._scripts[s] end
function Widget:HookScript(s, fn)
  local prev = self._scripts[s]
  self._scripts[s] = function(...) if prev then prev(...) end fn(...) end
end
function Widget:HasScript() return true end
function Widget:RegisterEvent(e)
  if T.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
  self._events[e] = true
  frames[self] = true
end
function Widget:RegisterUnitEvent(e, ...)
  self:RegisterEvent(e)
  self._unitEvents[e] = { ... }
end
function Widget:UnregisterEvent(e) self._events[e] = nil end
function Widget:UnregisterAllEvents() self._events = {} end
function Widget:IsEventRegistered(e) return self._events[e] == true end
function Widget:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget:Hide() self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:GetSize() return self._w, self._h end
function Widget:SetPoint(...) table.insert(self._points, { ... }) end
function Widget:ClearAllPoints() self._points = {} end
function Widget:GetNumPoints() return #self._points end
function Widget:GetPoint(i) return unpack(self._points[i or 1] or {}) end
function Widget:GetCenter() return 500, 400 end
function Widget:GetLeft() return 0 end
function Widget:GetTop() return 0 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetScale() return 1 end
function Widget:GetParent() return self._parent end
function Widget:GetChildren() return unpack(self._children) end
function Widget:GetName() return nil end
function Widget:GetObjectType() return self._kind end
function Widget:IsObjectType(k) return self._kind == k end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFormattedText(f, ...) self._text = string.format(f, ...) end
function Widget:GetStringWidth() return #(self._text or "") * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:GetNumLines() return 1 end
function Widget:SetTexture(p) self._texture = p; return true end
function Widget:GetTexture() return self._texture end
function Widget:GetTextureFileID() return self._texture and 1 or nil end
function Widget:SetAtlas(a) self._atlas = a; return true end
function Widget:GetAtlas() return self._atlas end
function Widget:SetValue(v) self._value = v end
function Widget:GetValue() return self._value or 0 end
function Widget:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Widget:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Widget:SetChecked(v) self._checked = v end
function Widget:GetChecked() return self._checked end
function Widget:SetAlpha(a) self._alpha = a end
function Widget:GetAlpha() return self._alpha or 1 end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Widget:GetFrameLevel() return self._level or 1 end
function Widget:SetFrameLevel(l) self._level = l end
function Widget:GetFrameStrata() return self._strata or "MEDIUM" end
function Widget:SetFrameStrata(s) self._strata = s end
function Widget:GetVerticalScroll() return self._vscroll or 0 end
function Widget:SetVerticalScroll(v) self._vscroll = v end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:SetMaxLetters(n) self._maxLetters = n end
function Widget:GetNumLetters() return #(self._text or "") end
function Widget:HasFocus() return false end
function Widget:IsMouseOver() return false end
function Widget:IsEnabled() return self._enabled ~= false end
function Widget:Enable() self._enabled = true end
function Widget:Disable() self._enabled = false end
function Widget:SetEnabled(v) self._enabled = v and true or false end
function Widget:CreateTexture(name) return newWidget("Texture", name, self) end
function Widget:CreateFontString(name) return newWidget("FontString", name, self) end
function Widget:CreateMaskTexture(name) return newWidget("MaskTexture", name, self) end
function Widget:CreateLine(name) return newWidget("Line", name, self) end
function Widget:CreateAnimationGroup()
  local g = newWidget("AnimationGroup", nil, self)
  function g:CreateAnimation(kind) return newWidget(kind or "Animation", nil, g) end
  function g:Play() if self._scripts.OnFinished then self._scripts.OnFinished(self) end end
  function g:IsPlaying() return false end
  return g
end
function Widget:Click(button)
  if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton", true) end
end

function CreateFrame(kind, name, parent, template)
  local f = newWidget(kind or "Frame", name, parent)
  f._template = template
  if template and template:find("BackdropTemplate") then
    function f:SetBackdrop(b) self._backdrop = b end
  end
  return f
end

-- Fires a WoW event to every frame that registered it (unit events filter on the first arg).
function T.Fire(event, ...)
  local list = {}
  for f in pairs(frames) do
    if f._events[event] then table.insert(list, f) end
  end
  for _, f in ipairs(list) do
    local units = f._unitEvents[event]
    local pass = true
    if units and #units > 0 then
      pass = false
      for _, u in ipairs(units) do if u == (...) then pass = true end end
    end
    if pass and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
Minimap = CreateFrame("Frame", "Minimap")
Minimap._w, Minimap._h = 140, 140
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
function GameTooltip:AddDoubleLine(a, b) table.insert(self.lines, tostring(a) .. " | " .. tostring(b)) end
function GameTooltip_Hide() GameTooltip:Hide() end
DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1")
UISpecialFrames = {}
for _, f in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall",
    "Fancy24Font", "NumberFontNormal", "ChatFontNormal", "SystemFont_Shadow_Med1" }) do
  _G[f] = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BackdropTemplateMixin = {}
function Mixin(obj, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do obj[k] = v end end return obj end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
function hooksecurefunc(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  local orig = tbl[name]
  tbl[name] = function(...)
    local r = { orig(...) }
    fn(...)
    return unpack(r)
  end
end
function securecall(fn, ...)
  if type(fn) == "string" then fn = _G[fn] end
  return fn(...)
end
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  table.insert(T.printed, line)
  if os.getenv("STUB_VERBOSE") then io.write("[print] " .. line .. "\n") end
end
SlashCmdList = {}
SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
function PlaySound() end
function PlaySoundFile() end
function StopSound() end
function ReloadUI() T.reloaded = (T.reloaded or 0) + 1 end
C_UI = { Reload = ReloadUI }
function InCombatLockdown() return T.combat or false end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "70338", "Oct 1 2026", 16001 end
function GetRealmName() return T.realm or "Normal" end
function GetNormalizedRealmName() return (T.realm or "Normal"):gsub("%s", "") end
function GetCurrentRegion() return 3 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 18, 1, 2, 18

-- string/table helpers WoW provides as globals
strsplit = function(sep, s, limit)
  local out, start, n = {}, 1, 0
  while true do
    n = n + 1
    local i, j = s:find(sep, start, true)
    if not i or (limit and n >= limit) then table.insert(out, s:sub(start)) break end
    table.insert(out, s:sub(start, i - 1))
    start = j + 1
  end
  return unpack(out)
end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, strlen, strsub, strfind, strmatch, gsub, format = string.lower, string.upper, string.len,
  string.sub, string.find, string.match, string.gsub, string.format
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
Round = function(x) return math.floor(x + 0.5) end
bit = bit or { band = function(a, b) return a % (b + 1) end }

RAID_CLASS_COLORS = {}
CLASS_ICON_TCOORDS = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
  RAID_CLASS_COLORS[c] = { r = 1, g = 1, b = 1, colorStr = "ffffffff", GetRGB = function() return 1, 1, 1 end }
  CLASS_ICON_TCOORDS[c] = { 0, 0.25, 0, 0.25 }
end

---------------------------------------------------------------------------
-- Units

T.units = {
  player = { name = "Tester", realm = nil, class = "WARRIOR", race = "Orc", level = 10, xp = 0, xpMax = 1000,
    health = 100, healthMax = 100, faction = "Horde", guid = "Player-1-00000001", isPlayer = true },
}
local function U(unit) return T.units[unit] end

function UnitExists(u) return U(u) ~= nil end
function UnitName(u) local x = U(u) if x then return x.name, x.realm end end
function UnitFullName(u) local x = U(u) if x then return x.name, x.realm or (u == "player" and "Normal" or nil) end end
function GetUnitName(u, showRealm) local x = U(u) if x then return x.realm and showRealm and (x.name .. "-" .. x.realm) or x.name end end
function UnitClass(u) local x = U(u) if x then return x.class and (x.class:sub(1, 1) .. x.class:sub(2):lower()), x.class, 1 end end
function UnitRace(u) local x = U(u) if x then return x.race, x.race end end
function UnitLevel(u) local x = U(u) return x and x.level or 0 end
function UnitXP(u) return U(u) and U(u).xp or 0 end
function UnitXPMax(u) return U(u) and U(u).xpMax or 1 end
function UnitHealth(u) return U(u) and U(u).health or 0 end
function UnitHealthMax(u) return U(u) and U(u).healthMax or 0 end
function UnitHealthPercent(u)
  local x = U(u)
  if not x then return nil end
  if issecretvalue(x.health) then return x.health end
  return x.health / x.healthMax -- 0..1 like the 12.x API (MetaKit.healthPctScale = 1)
end
function UnitGUID(u) return U(u) and U(u).guid end
function UnitIsPlayer(u) return U(u) and U(u).isPlayer or false end
function UnitFactionGroup(u) return U(u) and U(u).faction end
function UnitClassification(u) return U(u) and U(u).classification or "normal" end
function UnitCreatureType(u) return U(u) and U(u).creatureType end
function UnitIsDead(u) return U(u) and U(u).dead or false end
function UnitIsGhost(u) return U(u) and U(u).ghost or false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) or UnitIsGhost(u) end
function UnitAffectingCombat(u) return u == "player" and (T.combat or false) or (U(u) and U(u).combat or false) end
function UnitOnTaxi(u) return T.taxi or false end
function IsMounted() return T.mounted or false end
function IsFlying() return false end
function GetUnitSpeed(u) return T.speed or 0 end
function UnitInRaid(u) return T.group.raid and 1 or nil end
function UnitInParty(u) return T.group.size > 1 end
function UnitIsUnit(a, b) return a == b or (U(a) ~= nil and U(a) == U(b)) end
function UnitIsEnemy(a, b) return U(b) and U(b).enemy or false end
function UnitCanAttack(a, b) return U(b) and U(b).enemy or false end
function UnitSex(u) return 2 end
function GetXPExhaustion() return T.rested end
function GetMoney() return T.money end
function GetInventoryItemID(u, slot) return T.inventory and T.inventory[slot] end
function GetDodgeChance() return 5 end
function GetParryChance() return 5 end
function GetBlockChance() return 0 end
function GetCritChance() return 5 end
function GetAverageItemLevel() return 10, 10 end
function GetSpecialization() return nil end
function GetShapeshiftFormID() return T.form end
function GetShapeshiftForm() return 0 end

T.money = 0
-- Sets money and fires PLAYER_MONEY.
function T.SetMoney(copper) T.money = copper; T.Fire("PLAYER_MONEY") end

---------------------------------------------------------------------------
-- World / group / instance

T.map = { id = 1413, x = 0.5, y = 0.5, zone = "The Barrens", sub = "", name = "The Barrens" }
T.instance = { inInstance = false, type = "none", name = nil, id = nil }
T.group = { size = 0, raid = false }

C_Map = {
  GetBestMapForUnit = function(u) return T.map.id end,
  GetPlayerMapPosition = function(id, u)
    if T.map.x == nil then return nil end
    return CreateVector2D(T.map.x, T.map.y)
  end,
  GetMapInfo = function(id) return { mapID = id, name = T.map.name, mapType = 3, parentMapID = 0 } end,
  GetWorldPosFromMapPos = function(id, v) return 0, CreateVector2D(v.x * 1000, v.y * 1000) end,
}
function GetZoneText() return T.map.zone end
function GetRealZoneText() return T.map.zone end
function GetSubZoneText() return T.map.sub end
function GetMinimapZoneText() return T.map.sub ~= "" and T.map.sub or T.map.zone end
function IsInInstance() return T.instance.inInstance, T.instance.type end
function GetInstanceInfo()
  local i = T.instance
  return i.name or T.map.zone, i.type, 0, "", 5, 0, false, i.id or T.map.id
end
function IsInGroup() return T.group.size > 1 end
function IsInRaid() return T.group.raid end
function GetNumGroupMembers() return T.group.size end
function UnitPosition(u) return 0, 0, 0, T.map.id end

---------------------------------------------------------------------------
-- Chat / addon messages

T.chatLocked = false
Enum = Enum or {}
Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5, ChannelThrottle = 8,
  GeneralError = 9, AddOnMessageLockdown = 11, TargetOffline = 12 }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) T.prefixes = T.prefixes or {}; T.prefixes[p] = true; return true end,
  IsAddonMessagePrefixRegistered = function(p) return T.prefixes and T.prefixes[p] or false end,
  SendAddonMessage = function(prefix, msg, channel, target)
    if T.chatLocked then return Enum.SendAddonMessageResult.AddOnMessageLockdown end
    assert(#msg <= 255, "addon message over 255 bytes")
    table.insert(T.sent, { prefix = prefix, msg = msg, channel = channel, target = target, t = T.clock })
    return T.sendResult or 0
  end,
  InChatMessagingLockdown = function() return T.chatLocked end,
}
-- Delivers an addon message as if `sender` sent it.
function T.Deliver(prefix, msg, channel, sender)
  T.Fire("CHAT_MSG_ADDON", prefix, msg, channel, sender, sender, 0, 0, "", 0)
end
function SendChatMessage() end
function JoinChannelByName() end
function GetChannelName() return 0 end
ChatFrame_AddMessageEventFilter = function() end

---------------------------------------------------------------------------
-- Combat data / auras / spells

Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
  DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 }
Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
-- T.meter[meterType] = { durationSeconds = 12, combatSources = { { isLocalPlayer = true, totalAmount = 500 } } }
T.meter = {}
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetCombatSessionFromType = function(sessionType, meterType) return T.meter[meterType] end,
  GetAvailableCombatSessions = function() return {} end,
}
T.auras = { player = {} }
C_UnitAuras = {
  GetAuraDataByIndex = function(u, i, filter) return T.auras[u] and T.auras[u][i] end,
  GetPlayerAuraBySpellID = function(id)
    for _, a in ipairs(T.auras.player) do if a.spellId == id then return a end end
  end,
}
T.spellNames = {}
C_Spell = {
  GetSpellInfo = function(id) return { name = T.spellNames[id] or ("Spell" .. id), spellID = id, iconID = 136243 } end,
  GetSpellName = function(id) return T.spellNames[id] or ("Spell" .. id) end,
}
function GetSpellInfo(id) return T.spellNames[id] or ("Spell" .. id), nil, 136243 end
C_Item = {
  GetItemInfo = function() return nil end,
  GetItemInfoInstant = function(id) return id, "", "", "", 0, 4, 6 end,
  GetCurrentItemLevel = function() return 10 end,
}
C_Texture = { GetAtlasInfo = function(a) return { width = 64, height = 64, file = 1 } end }
C_AddOns = {
  GetAddOnMetadata = function(a, k) return k == "Version" and "dev" or nil end,
  IsAddOnLoaded = function() return false end,
  LoadAddOn = function() return true end,
}
C_Secrets = { HasSecretRestrictions = function() return false end, ShouldAurasBeSecret = function() return T.combat end }
C_PvP = { IsWarModeFeatureEnabled = function() return false end }
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 86400 end }

---------------------------------------------------------------------------
-- Character progression

T.played = { total = 3600, level = 600 }
function RequestTimePlayed()
  C_Timer.After(0.1, function() T.Fire("TIME_PLAYED_MSG", T.played.total, T.played.level) end)
end
-- T.talents[tab] = { name = "Arms", points = 5, talents = { { name = "Deflection", rank = 5, maxRank = 5, tier = 1, column = 2 } } }
T.talents = {
  { name = "Arms", points = 0, talents = { { name = "Improved Heroic Strike", rank = 0, maxRank = 3, tier = 1, column = 1 } } },
  { name = "Fury", points = 0, talents = {} },
  { name = "Protection", points = 0, talents = {} },
}
function GetNumTalentTabs() return #T.talents end
function GetTalentTabInfo(tab) local x = T.talents[tab] if x then return x.name, "", x.points, "" end end
function GetNumTalents(tab) return T.talents[tab] and #T.talents[tab].talents or 0 end
function GetTalentInfo(tab, i)
  local x = T.talents[tab] and T.talents[tab].talents[i]
  if x then return x.name, 0, x.tier, x.column, x.rank, x.maxRank end
end
-- T.skills = { { name = "Mining", rank = 50, max = 75, header = false } }
T.skills = {}
function GetNumSkillLines() return #T.skills end
function GetSkillLineInfo(i)
  local s = T.skills[i]
  if s then return s.name, s.header or false, false, s.rank or 0, 0, 0, s.max or 0 end
end
T.repairCost = 0
function GetRepairAllCost() return T.repairCost, T.repairCost > 0 end
function RepairAllItems() end
function CanGuildBankRepair() return false end
T.trade = { player = 0, target = 0 }
function GetPlayerTradeMoney() return T.trade.player end
function GetTargetTradeMoney() return T.trade.target end

---------------------------------------------------------------------------
-- UI systems

Settings = {
  RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 1 end, ID = 1 }, {} end,
  RegisterCanvasLayoutCategory = function(frame, name) return { name = name, GetID = function() return 2 end, ID = 2 } end,
  RegisterAddOnCategory = function() end,
  RegisterProxySetting = function(cat, var, vtype, name, default, get, set)
    return { GetValue = get, SetValue = function(_, v) set(v) end }
  end,
  RegisterAddOnSetting = function(cat, var, key, tbl, vtype, name, default) return { GetValue = function() return tbl[key] end } end,
  CreateCheckbox = function() return {} end,
  CreateSlider = function() return {} end,
  CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
  OpenToCategory = function() end,
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
}
AlertFrame = {
  AddQueuedAlertFrameSubSystem = function(_, template, setUp)
    return { AddAlert = function(_, ...) T.alerts = T.alerts or {}; table.insert(T.alerts, { ... }) end }
  end,
  AddSimpleAlertFrameSubSystem = function(_, template, setUp)
    return { AddAlert = function(_, ...) T.alerts = T.alerts or {}; table.insert(T.alerts, { ... }) end }
  end,
}
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function PanelTemplates_TabResize() end
function PanelTemplates_SelectTab() end
function PanelTemplates_DeselectTab() end
function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCoinTextureString(c) return tostring(c) end

---------------------------------------------------------------------------
-- Global strings: load the client strings fallback so parser patterns behave like the real client.

do
  local here = (debug.getinfo(1, "S").source:match("^@(.*)/tests/wow_stub.lua$")) or "."
  local path = here .. "/MetaKit/Data/GlobalStringsFallback.lua"
  local chunk = loadfile(path)
  if chunk then
    local env = setmetatable({ MetaKit = {} }, { __index = _G })
    setfenv(chunk, env)
    chunk()
    for k, v in pairs(env.MetaKit.GlobalStringsFallback or {}) do _G[k] = v end
  end
end

---------------------------------------------------------------------------
-- Addon loader

-- Loads every Lua file listed in a TOC (paths relative to the TOC), with (addonName, ns) varargs like the client.
-- opts.saved = { EldersDB = {...} } pre-seeds SavedVariables; opts.login = false skips PLAYER_LOGIN.
function T.LoadAddon(tocPath, opts)
  opts = opts or {}
  local dir = tocPath:match("^(.*)/[^/]+$") or "."
  local name = tocPath:match("([^/]+)%.toc$")
  for k, v in pairs(opts.saved or {}) do _G[k] = v end
  local ns = opts.ns or {}
  for line in io.lines(tocPath) do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
      local file = dir .. "/" .. line:gsub("\\", "/")
      if file:match("%.lua$") then
        local chunk, err = loadfile(file)
        if not chunk then
          -- Files of modules not written yet are skipped unless STRICT=1 (the client also just logs a missing file).
          if os.getenv("STRICT") or not tostring(err):find("No such file", 1, true) then
            error("load " .. file .. ": " .. tostring(err))
          end
          T.missing = T.missing or {}
          table.insert(T.missing, file)
        else
          chunk(name, ns)
        end
      end
    end
  end
  T.Fire("ADDON_LOADED", name)
  if opts.login ~= false then
    T.Fire("PLAYER_LOGIN")
    T.Fire("PLAYER_ENTERING_WORLD", true, false)
  end
  return ns
end

return T
