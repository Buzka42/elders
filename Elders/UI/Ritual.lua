-- The Elders ritual: after each finished bracket, three short steps (rate PvE and PvP, judge class insights, add your own).
-- Fires RITUAL_SUBMIT / RITUAL_SKIP; Social.lua stores the result. Deferred while in combat or inside an instance.
--
-- CONTRACT NOTE: votes are passed as an array of { id = insightId, v = 1 | -1 } (skipped insights are omitted); the text is
-- always a string ("" when empty). The dialog is a flat MK.UI.Window that stays open until sealed or skipped;
-- closing it with the X only closes the window, nothing is fired, and the ritual is offered again at next login.

local ADDON, ns = ...
local MK = MetaKit
local U = MK.Util
local UI = ns.UI
local A = ns.A

local MAX_TEXT = 280
local R = { queue = {} } -- queue: [bracket] = force ; R.cur = active ritual state

local function bracketRow(b) return ns.char and ns.char.brackets and ns.char.brackets[b] end

local function wanted(b, force)
  if force then return true end
  if not A.db.config.ritual then return false end
  local r = bracketRow(b) and bracketRow(b).ritual
  return not (r and (r.pve or r.skipped))
end

local function safeToShow()
  if MK.InCombat() then return false end
  local inInstance = MK.InstanceState()
  return not inInstance
end

local function insightsFor(class)
  if type(ns.Insights) ~= "function" then return {} end
  local ok, list = pcall(ns.Insights, class, 3)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for i = 1, math.min(3, #list) do
    if type(list[i]) == "table" and list[i].id and type(list[i].text) == "string" then out[#out + 1] = list[i] end
  end
  return out
end

local function finish(s)
  s.done = true
  R.cur = nil
  if s.head and s.head.Hide then pcall(s.head.Hide, s.head) end
end

local function submit(s)
  local votes = {}
  for _, ins in ipairs(s.insights) do
    local v = s.votes[ins.id]
    if v then votes[#votes + 1] = { id = ins.id, v = v } end
  end
  local text = (s.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  A:Fire("RITUAL_SUBMIT", s.bracket, s.pve, s.pvp, votes, U.Truncate(text, MAX_TEXT))
  finish(s)
end

local function skip(s)
  A:Fire("RITUAL_SKIP", s.bracket)
  finish(s)
end

local function showStep(s, n)
  s.step = n
  for i, f in ipairs(s.steps) do f:SetShown(i == n) end
  s.back:SetShown(n > 1)
  s.next:SetShown(n < 3)
  s.submit:SetShown(n == 3)
  if s.next.SetEnabledState then s.next:SetEnabledState(n ~= 1 or (s.pve > 0 and s.pvp > 0)) end
end

-- Five flat squares: filled in the accent colour, empty in the divider colour. Same API as the kit's Rating.
local STAR, STAR_GAP = 20, 6

local function flatRating(parent, onChange)
  local count = 5
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(count * (STAR + STAR_GAP) - STAR_GAP, STAR)
  f.value, f.hover, f.glyphs, f.mkEnabled = 0, false, {}, true
  local function paint()
    local shown = f.hover or f.value
    for i, g in ipairs(f.glyphs) do
      g.tex:SetColorTexture(MK.UI.Color(UI.SKIN, i <= shown and "accent" or "divider"))
    end
  end
  for i = 1, count do
    local g = CreateFrame("Button", nil, f)
    g:SetSize(STAR, STAR)
    g:SetPoint("LEFT", f, "LEFT", (i - 1) * (STAR + STAR_GAP), 0)
    g.tex = g:CreateTexture(nil, "ARTWORK")
    g.tex:SetAllPoints(g)
    g:RegisterForClicks("LeftButtonUp")
    g:SetScript("OnEnter", function() if f.mkEnabled then f.hover = i; paint() end end)
    g:SetScript("OnLeave", function() f.hover = false; paint() end)
    g:SetScript("OnClick", function()
      if not f.mkEnabled then return end
      f:SetValue(i)
      if onChange then onChange(i) end
    end)
    f.glyphs[i] = g
  end
  function f:GetValue() return self.value end
  function f:SetValue(n)
    self.value = U.Clamp(math.floor(tonumber(n) or 0), 0, count)
    paint()
  end
  function f:SetEnabledState(v) self.mkEnabled = v and true or false end
  paint()
  return f
end

local function ratingRow(s, parent, y, label, key)
  local l = MK.UI.Label(parent, { text = label, font = "body", justify = "LEFT" })
  l:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  l:SetWidth(136) -- same column edge for both rows; the rating starts at x = 150
  local rt = flatRating(parent, function(v) s[key] = v or 0; showStep(s, s.step) end)
  rt:SetPoint("TOPLEFT", parent, "TOPLEFT", 150, y + 4)
  return rt
end

local function buildStep1(s, f, lo, hi)
  local t = MK.UI.Label(f, { text = string.format("How did levels %d to %d treat you?", lo, hi), font = "body", justify = "LEFT" })
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
  s.rPve = ratingRow(s, f, -48, "Adventure (PvE)", "pve")
  s.rPvp = ratingRow(s, f, -100, "Battle (PvP)", "pvp")
  local h = MK.UI.Label(f, { text = "One to five. Be honest, the Elders can tell.", font = "small", color = "muted", justify = "LEFT" })
  h:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -146)
end

local function buildStep2(s, f)
  local t = MK.UI.Label(f, { text = "Words from others of your calling. Were they worth hearing?", font = "body", justify = "LEFT" })
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
  if #s.insights == 0 then
    local e = MK.UI.Label(f, { text = "Install the Meta Uploader to see insights from your class.", font = "small", color = "muted", justify = "LEFT" })
    e:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -44)
    return
  end
  for i, ins in ipairs(s.insights) do
    local y = -30 - (i - 1) * 62
    local txt = MK.UI.Label(f, { text = U.Truncate(ins.text, MAX_TEXT), font = "small", justify = "LEFT", wrap = true })
    txt:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
    txt:SetWidth(408)
    local btns = {}
    local function pick(v)
      s.votes[ins.id] = v
      for val, b in pairs(btns) do if b.SetActive then b:SetActive(val == v) end end
    end
    local defs = { { 1, "Useful" }, { -1, "Not useful" } }
    for j, d in ipairs(defs) do
      btns[d[1]] = MK.UI.Button(f, { text = d[2], width = 96, height = 24, skin = UI.SKIN,
        onClick = function() pick(d[1]) end })
      btns[d[1]]:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (j - 1) * 102, y - 32)
    end
    local sk = MK.UI.Button(f, { text = "Skip", width = 70, height = 24, skin = UI.SKIN, onClick = function() pick(nil) end })
    sk:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + 2 * 102, y - 32)
  end
end

local function buildStep3(s, f)
  local t = MK.UI.Label(f, { text = "Leave a word for those who come after (optional).", font = "body", justify = "LEFT" })
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
  local counter = MK.UI.Label(f, { text = "0 / " .. MAX_TEXT, font = "small", color = "muted", justify = "RIGHT" })
  counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -136)
  local eb = MK.UI.EditBox(f, { width = 408, height = 96, maxLetters = MAX_TEXT, multiline = true,
    placeholder = "A tip, a warning, a favourite spot...",
    onChange = function(text)
      s.text = type(text) == "string" and text or ""
      counter:SetText(#s.text .. " / " .. MAX_TEXT)
    end })
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -34)
end

local function open(b, force)
  if R.cur then return end
  if not (MK.UI and MK.UI.Window and MK.UI.Button and MK.UI.EditBox and MK.UI.Label) then
    A:Debug("ritual: UI kit missing")
    return
  end
  UI.ApplyTheme()
  local lo, hi = (b - 1) * 10 + 1, b * 10
  local class = ns.char and ns.char.class
  local s = { bracket = b, pve = 0, pvp = 0, votes = {}, text = "", step = 1, steps = {}, insights = insightsFor(class) }
  R.cur = s
  local head = MK.UI.Window{ skin = UI.SKIN, width = 440, height = 340, title = "The Elders ask",
    subtitle = string.format("Levels %d to %d", lo, hi),
    onClose = function() if s.shown and not s.done then s.done = true; R.cur = nil end end }
  s.head = head
  s.shown = true -- the kit window hides itself once while it is built; only a later hide counts as a close
  head:Show()
  local body = head.content
  for i = 1, 3 do
    local f = CreateFrame("Frame", nil, body)
    f:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 32)
    s.steps[i] = f
  end
  buildStep1(s, s.steps[1], lo, hi)
  buildStep2(s, s.steps[2])
  buildStep3(s, s.steps[3])

  -- buttons along the bottom of the content: Skip at the left, Back and Next / Seal it at the right, 8 px apart
  local function btn(text, variant, point, x, onClick)
    local bt = MK.UI.Button(body, { text = text, width = 90, height = 24, variant = variant, skin = UI.SKIN, onClick = onClick })
    bt:SetPoint(point, body, point, x, 0)
    return bt
  end
  s.skip = btn("Skip", "default", "BOTTOMLEFT", 0, function() skip(s) end)
  s.back = btn("Back", "default", "BOTTOMRIGHT", -98, function() showStep(s, s.step - 1) end)
  s.next = btn("Next", "accent", "BOTTOMRIGHT", 0, function() showStep(s, s.step + 1) end)
  s.submit = btn("Seal it", "accent", "BOTTOMRIGHT", 0, function() submit(s) end)
  showStep(s, 1)
  R.last = s
end

local function flush()
  if R.cur or not safeToShow() then return end
  for b, force in pairs(R.queue) do
    R.queue[b] = nil
    if wanted(b, force) then open(b, force); return end
  end
end

local function request(b, force)
  if type(b) ~= "number" or b < 1 then return end
  if not wanted(b, force) then return end
  R.queue[b] = force and true or R.queue[b] or false
  if safeToShow() then flush() else A:Debug("ritual deferred for bracket " .. b) end
end

A:Listen("RITUAL_DUE", function(b) request(b, false) end)
A:Listen("RITUAL_OPEN", function(b, force) request(b, force) end)

-- Combat ended or zoned out of an instance: show what was waiting.
A:On("PLAYER_REGEN_ENABLED", function() A:After(1, flush) end)
A:On("PLAYER_ENTERING_WORLD", function() A:After(2, flush) end)

-- Catch-up at login: the last finished bracket still unrated and not skipped.
local M = A:NewModule("Ritual")
function M:OnLogin()
  A:After(15, function()
    local b = U.BracketOf(ns.Agg.Level()) - 1
    local row = b >= 1 and bracketRow(b)
    if row and row.sec > 0 then request(b, false) end
  end)
end

R.Show, R.Submit, R.Skip = showStep, submit, skip
ns.UI.Ritual = R -- also used by tests
