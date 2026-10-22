-- MetaKit UI kit: builds every widget in both skins under the stub, exercises every method, asserts no errors.
local stubPath = os.getenv("WOW_STUB") or "tests/wow_stub.lua"
local T = dofile(stubPath)
local root = stubPath:match("^(.*)/tests/wow_stub.lua$") or "."

local function exists(path) local f = io.open(path) if f then f:close() return true end return false end
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Data/GlobalStringsFallback", "Strings", "Codec", "Comm",
    "Lobby", "Venue", "UI/Theme", "UI/Widgets", "UI/List", "UI/StatRows", "UI/Rating", "UI/Toast", "UI/TalkingHead",
    "UI/Minimap", "UI/Settings", "UI/ExportBox", "UI/Demo" }) do
  local path = root .. "/MetaKit/" .. f .. ".lua"
  if exists(path) then dofile(path) elseif f:match("^UI/") then error("missing " .. path) end
end
local MK, UI = MetaKit, MetaKit.UI
local SKINS = { "elders", "bloodsports" }

local function eachSkin(fn) for _, s in ipairs(SKINS) do fn(s) end end

T.test("skins: tokens, art merge, Color, Art", function()
  eachSkin(function(name)
    local s = UI.Skin(name)
    for _, k in ipairs({ "bg", "panel", "edge", "accent", "title", "text", "muted", "good", "bad", "rowEven", "rowOdd", "divider" }) do
      T.eq(#s[k], 4, name .. "." .. k)
    end
    T.eq(s.tile, nil)
  end)
  -- flat rebuild: both built-in skins share the single accent token (was green / red)
  T.near(UI.Skin("elders").accent[1], UI.Tokens.accent[1], 1e-3)
  T.near(UI.Skin("bloodsports").accent[1], UI.Tokens.accent[1], 1e-3)
  for _, k in ipairs({ "bg", "border", "text", "muted", "accent", "accentFill", "divider", "good", "bad" }) do
    T.eq(#UI.Tokens[k], 4, "token " .. k)
  end
  T.eq(UI.Skin("nope"), UI.Skin("elders"))
  local custom = UI.RegisterSkin("custom", { accent = { 1, 0, 0 }, tile = "x\\tile", logo = "x\\logo" })
  T.eq(custom.accent[4], 1)
  T.eq(#custom.bg, 4)
  UI.RegisterSkin("custom", { header = "x\\header" })
  T.eq(UI.Skin("custom").tile, "x\\tile")
  T.eq(UI.Skin("custom").header, "x\\header")
  UI.RegisterSkin("custom", { tile = false })
  T.eq(UI.Skin("custom").tile, nil)
  local r, g, b, a = UI.Color("elders", "title")
  T.ok(r > 0.9 and a == 1)
  local r2 = UI.Color("elders", { 0.5, 0.5, 0.5 })
  T.eq(r2, 0.5)
  local ns = { Media = { path = "Interface\\AddOns\\X\\Media\\", has = { logo = true } } }
  T.eq(UI.Art(ns, "logo"), "Interface\\AddOns\\X\\Media\\logo")
  T.eq(UI.Art(ns, "missing"), nil)
  T.eq(UI.Art({}, "logo"), nil)
end)

T.test("Window: content, title, toggle, ESC, position save/restore, onClose, art", function()
  local closed = 0
  local db = {}
  eachSkin(function(name)
    local w = UI.Window({ name = "TestWin_" .. name, skin = name, width = 460, height = 560, title = "Hello", subtitle = "sub",
      db = db, onClose = function() closed = closed + 1 end })
    T.ok(w.content, "content")
    T.eq(w:GetWidth(), 460)
    w:SetTitle("Changed")
    T.eq(w.title:GetText(), "Changed")
    T.eq(w:IsShown(), false)
    w:Toggle(); T.eq(w:IsShown(), true)
    w:Toggle(); T.eq(w:IsShown(), false)
    T.ok(closed >= 1)
    local found
    for _, n in ipairs(UISpecialFrames) do if n == "TestWin_" .. name then found = true end end
    T.ok(found, "UISpecialFrames")
    w._scripts.OnDragStart(w)
    w._scripts.OnDragStop(w)
    T.eq(db.pos[1], "CENTER")
    w.closeButton:Click()
  end)
  db.pos = { "TOPLEFT", "TOPLEFT", 12, -34 }
  local w2 = UI.Window({ name = "TestWin_restore", db = db, title = "x" })
  local p = w2._points[1]
  T.eq(p[1], "TOPLEFT"); T.eq(p[4], 12); T.eq(p[5], -34)
  -- skin art is still accepted but the flat kit never draws it (header/footer/logo removed)
  UI.RegisterSkin("arty", { tile = "t", header = "h", footer = "f", logo = "l" })
  local w3 = UI.Window({ name = "TestWin_art", skin = "arty", title = "Art" })
  T.ok(not w3.headerArt and not w3.footerArt and not w3.logoArt)
  T.eq(w3._backdrop.bgFile, UI.Tex.white)
  T.eq(w3._backdrop.edgeSize, 1)
  T.ok(UI.Window({ title = "anon" }), "unnamed window")
end)

T.test("Label, Divider, Panel, Icon, ClassIcon", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    for _, kind in ipairs({ "title", "big", "large", "body", "small", "number" }) do
      local l = UI.Label(parent, { skin = name, font = kind, text = "x", color = "accent", justify = "RIGHT", width = 100, wrap = true })
      T.eq(l:GetText(), "x")
      l:SetColorKey("bad")
    end
    UI.Divider(parent, name)
    local p = UI.Panel(parent, name)
    T.ok(p._backdrop, "panel backdrop")
    local i = UI.Icon(parent, { size = 30, circle = true, ring = "accent", texture = "Interface\\Icons\\X", skin = name })
    i:SetIcon("Interface\\Icons\\Y", { 0, 1, 0, 1 })
    i:SetIcon(nil)
    i:SetDesaturated(true)
    local c = UI.ClassIcon(parent, 20, name)
    c:SetClass("WARRIOR"); T.eq(c.class, "WARRIOR")
    c:SetClass("NOPE")
    c:SetClass(nil)
  end)
end)

T.test("Button: click, variants, active, disabled, tooltip, icon", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local clicks = 0
    for _, v in ipairs({ "default", "accent", "danger" }) do
      local b = UI.Button(parent, { skin = name, text = "Go", variant = v, onClick = function() clicks = clicks + 1 end,
        tooltip = { "Title", { "line one", { "left", "right" } } }, icon = "Interface\\Icons\\X" })
      b:Click()
      b:SetActive(true); b:SetActive(false)
      b._scripts.OnEnter(b); b._scripts.OnMouseDown(b); b._scripts.OnMouseUp(b); b._scripts.OnLeave(b)
      T.ok(#GameTooltip.lines >= 0)
      b:SetEnabledState(false); b:Click()
      b:SetEnabledState(true)
      b:SetText("New"); T.eq(b:GetText(), "New")
      b:SetIcon(nil); b:SetVariant("danger")
    end
    T.eq(clicks, 3)
    local ft = UI.Button(parent, { skin = name, text = "fn tip", tooltip = function(tt) tt:AddLine("hi") end })
    ft._scripts.OnEnter(ft)
  end)
end)

T.test("Tabs: Select fires onSelect, highlights", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local got = {}
    local tabs = UI.Tabs(parent, { skin = name, labels = { "1-10", "11-20", "All" }, onSelect = function(i, l) got[#got + 1] = i .. l end })
    tabs:Select(2)
    tabs.buttons[3]:Click()
    tabs:Select(9)
    T.eq(got[1], "211-20"); T.eq(got[2], "3All"); T.eq(#got, 2)
    T.eq(tabs:GetSelected(), 3)
    tabs:Select(1, true); T.eq(#got, 2)
    UI.Tabs(parent, { skin = name, labels = { "a", "b", "c" }, width = 300, selected = 2 })
  end)
end)

T.test("EditBox: change, placeholder, readOnly, multiline", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local seen
    local e = UI.EditBox(parent, { skin = name, width = 200, maxLetters = 20, placeholder = "type", onChange = function(t, u) seen = { t, u } end })
    e:SetText("abc"); T.eq(e:GetText(), "abc")
    e._text = "abcd"
    e._scripts.OnTextChanged(e, true)
    T.eq(seen[1], "abcd"); T.eq(seen[2], true)
    e._scripts.OnEditFocusGained(e); e._scripts.OnEditFocusLost(e); e._scripts.OnEscapePressed(e); e._scripts.OnEnterPressed(e)
    e:SetPlaceholder("other"); e:SetEnabledState(false); e:SetEnabledState(true)
    local ro = UI.EditBox(parent, { skin = name, readOnly = true, multiline = true, bare = true })
    ro:SetText("fixed")
    ro._text = "hacked"
    ro._scripts.OnTextChanged(ro, true)
    T.eq(ro:GetText(), "fixed")
    T.ok(UI.EditBox(parent, { skin = name, multiline = true, maxLetters = 280 }))
  end)
end)

T.test("Checkbox", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local last
    local c = UI.Checkbox(parent, { skin = name, label = "Opt", checked = true, onChange = function(v) last = v end, tooltip = "tip" })
    T.eq(c:GetChecked(), true)
    c:Click(); T.eq(c:GetChecked(), false); T.eq(last, false)
    c:Click(); T.eq(last, true)
    c:SetChecked(false); c:SetLabel("Renamed"); c._scripts.OnEnter(c); c._scripts.OnLeave(c)
    c:SetEnabledState(false); c:Click(); T.eq(c:GetChecked(), false)
  end)
end)

T.test("Dropdown: open, select, SetValue, scroll", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local picked
    local d = UI.Dropdown(parent, { skin = name, width = 160, items = { { value = "a", text = "Alpha" }, { "b", "Beta" } },
      onSelect = function(v) picked = v end })
    d:SetValue("a"); T.eq(d:GetText(), "Alpha")
    d:Click()
    T.eq(d:IsMenuShown(), true)
    d.menuRows[2]:Click()
    T.eq(picked, "b"); T.eq(d:GetValue(), "b"); T.eq(d:GetText(), "Beta")
    T.eq(d:IsMenuShown(), false)
    d:Click(); d:Click()
    local items = {}
    for i = 1, 30 do items[i] = { value = i, text = "Item " .. i } end
    d:SetItems(items)
    d:OpenMenu()
    d.menu._scripts.OnMouseWheel(d.menu, -1)
    d.menu._scripts.OnMouseWheel(d.menu, -5)
    d:CloseMenu()
    d:SetValue(7); T.eq(d:GetText(), "Item 7")
  end)
end)

T.test("Tooltip helper", function()
  UI.Tooltip(CreateFrame("Frame"), "Title", { "plain", { "colored", 1, 0, 0 }, { left = "L", right = "R" } })
  T.eq(GameTooltip.lines[1], "Title")
  T.eq(#GameTooltip.lines, 4)
  UI.ShowTip(CreateFrame("Frame"), "just a title")
  UI.HideTip()
end)

T.test("Confirm: accept, cancel, ESC, replacement", function()
  eachSkin(function(name)
    local log = {}
    local c = UI.Confirm({ skin = name, title = "Sure?", text = "Really?", accept = "Yes", cancel = "No",
      onAccept = function() log[#log + 1] = "accept" end, onCancel = function() log[#log + 1] = "cancel" end })
    T.eq(c:IsShown(), true)
    c.acceptBtn:Click()
    T.eq(log[1], "accept"); T.eq(c:IsShown(), false)
    UI.Confirm({ skin = name, title = "t", text = "x", onAccept = function() log[#log + 1] = "a2" end,
      onCancel = function() log[#log + 1] = "cancel2" end })
    c.cancelBtn:Click()
    T.eq(log[2], "cancel2")
    UI.Confirm({ skin = name, title = "t", text = "x", onCancel = function() log[#log + 1] = "esc" end })
    c:Hide()
    T.eq(log[3], "esc")
    UI.Confirm({ skin = name, title = "t", text = "x", onCancel = function() log[#log + 1] = "first" end })
    UI.Confirm({ skin = name, title = "t2", text = "y", cancel = false })
    T.eq(log[4], "first")
    T.eq(c.cancelBtn:IsShown(), false)
    c.acceptBtn:Click()
    T.eq(c:IsShown(), false)
    T.eq(UI.Confirm({ skin = name, title = "again", text = "z" }), c, "frame reused")
    c:Close()
  end)
end)

local function sampleRows(n)
  local rows = {}
  for i = 1, n do rows[i] = { n = i, name = "Row" .. i, class = "WARRIOR", copper = i * 100, icon = "Interface\\Icons\\X" } end
  return rows
end

T.test("List: 500 rows, pooled, wheel, rail, clicks, columns", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local clicked, entered, btn
    local list = UI.List(parent, { skin = name, rowHeight = 24, empty = "Nothing", width = 500, height = 300,
      columns = {
        { key = "n", title = "#", width = 40 },
        { key = "class", title = "", width = 30, kind = "class" },
        { key = "name", title = "Name", format = function(r) return "<" .. r.name .. ">" end },
        { key = "icon", width = 30, kind = "icon" },
        { key = "copper", title = "Gold", width = 90, kind = "money", align = "RIGHT" },
        { title = "", width = 70, kind = "button", buttonText = "Go", onClick = function(r) btn = r.name end },
      },
      onRowClick = function(r) clicked = r.name end, onRowEnter = function(r) entered = r.name end })
    local pool0 = list:GetPoolSize()
    T.ok(pool0 > 0 and pool0 <= 14, "pool " .. pool0)
    list:SetData({})
    T.eq(list:GetOffset(), 0)
    list:SetData(sampleRows(500))
    T.eq(list:GetPoolSize(), pool0, "pool unchanged by 500 rows")
    local row1 = list.rows[1]
    T.eq(row1.cells[3]:GetText(), "<Row1>")
    T.eq(row1.cells[5]:GetText(), MK.Util.Money(100))
    row1:Click(); T.eq(clicked, "Row1")
    row1._scripts.OnEnter(row1); T.eq(entered, "Row1")
    row1.cells[6]:Click(); T.eq(btn, "Row1")
    list._scripts.OnMouseWheel(list, -1)
    T.eq(list:GetOffset(), 3)
    T.eq(list.rows[1].cells[3]:GetText(), "<Row4>")
    list._scripts.OnMouseWheel(list, 5)
    T.eq(list:GetOffset(), 0)
    for _ = 1, 400 do list._scripts.OnMouseWheel(list, -1) end
    T.eq(list:GetOffset(), 500 - list:VisibleRows())
    T.eq(list.rows[list:VisibleRows()].data.n, 500)
    T.eq(list:GetPoolSize(), pool0, "pool unchanged after scrolling")
    list:ScrollTo(100); T.eq(list:GetOffset(), 99)
    T.ok(list.rail.needed, "rail needed")
    list.rail:ScrollToFraction(0)
    T.eq(list:GetOffset(), 0)
    list.rail:ScrollToFraction(1)
    T.eq(list:GetOffset(), 500 - list:VisibleRows())
    -- drag math: track top 0, grabbing the thumb top, cursor 50% down the usable range
    local usable = list.rail:TrackHeight() - list.rail.thumb:GetHeight()
    T.near(list.rail:CursorToFraction(-usable / 2, 0), 0.5, 1e-6)
    T.near(list.rail:CursorToFraction(100, 0), 0, 1e-6)
    T.near(list.rail:CursorToFraction(-1e6, 0), 1, 1e-6)
    list.rail.thumb._scripts.OnMouseDown(list.rail.thumb)
    list.rail.thumb._scripts.OnUpdate(list.rail.thumb)
    list.rail.thumb._scripts.OnMouseUp(list.rail.thumb)
    list.rail.track._scripts.OnMouseDown(list.rail.track)
    list.rail.track._scripts.OnMouseUp(list.rail.track)
    list:SetSelected(5)
    list:SetData(sampleRows(3))
    T.eq(list:GetOffset(), 0)
    T.eq(list.rail.needed, false)
    T.eq(list.rows[4]._shown, false, "unused rows hidden")
    list:SetEmptyText("Empty!")
    list:SetData(nil)
    -- resize: pool follows the viewport, never the data
    list:SetSize(500, 500)
    list._scripts.OnSizeChanged(list)
    T.ok(list:GetPoolSize() > pool0 and list:GetPoolSize() <= 25)
    list:SetData(sampleRows(500))
    local pool1 = list:GetPoolSize()
    list:SetData(sampleRows(5000))
    T.eq(list:GetPoolSize(), pool1)
    T.ok(not list.lastError)
  end)
  -- a throwing format must not break rendering
  local bad = UI.List(parent, { columns = { { key = "name", format = function() error("boom") end } } })
  bad:SetData(sampleRows(3))
  T.ok(bad.lastError, "format error captured")
end)

T.test("StatRows: sections, scroll, tooltips", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local sr = UI.StatRows(parent, { skin = name, rowHeight = 30, width = 440, height = 300 })
    local sections = {}
    for s = 1, 6 do
      local rows = {}
      for i = 1, 8 do
        rows[i] = { icon = "Interface\\Icons\\X", label = "L" .. i, value = i * 10, sub = i % 2 == 0 and "sub" or nil,
          tooltip = { "T", { "line" } } }
      end
      sections[s] = { title = "Section " .. s, rows = rows }
    end
    sr:SetSections(sections)
    -- section header is now 22 px + 10 px space above (spec), was 26
    T.eq(sr:GetContentHeight(), 6 * (22 + 10) + 48 * 30)
    local pool = sr:GetPoolSize()
    T.ok(pool > 0 and pool <= 14, "pool " .. pool)
    sr._scripts.OnMouseWheel(sr, -1)
    T.ok(sr:GetOffset() > 0)
    for _ = 1, 100 do sr._scripts.OnMouseWheel(sr, -1) end
    T.eq(sr:GetOffset(), sr:MaxOffset())
    T.ok(sr:GetPoolSize() <= pool + 1)
    sr:ScrollToTop(); T.eq(sr:GetOffset(), 0)
    sr.rail:ScrollToFraction(0.5)
    T.ok(sr:GetOffset() > 0)
    sr.rows[1]._scripts.OnEnter(sr.rows[1]); sr.rows[1]._scripts.OnLeave(sr.rows[1])
    sr.rows[2]._scripts.OnEnter(sr.rows[2])
    sr:SetSections({})
    T.eq(sr:GetContentHeight(), 0)
    sr:SetSections({ { rows = { { label = "no header", value = "x", color = "good" } } } })
    T.eq(sr:GetContentHeight(), 30)
  end)
end)

T.test("Rating: SetValue, clicks, hover", function()
  local parent = CreateFrame("Frame")
  eachSkin(function(name)
    local got
    local r = UI.Rating(parent, { skin = name, count = 5, size = 26, onChange = function(n) got = n end })
    T.eq(r:GetValue(), 0)
    r:SetValue(3); T.eq(r:GetValue(), 3)
    r:SetValue(99); T.eq(r:GetValue(), 5)
    r:SetValue(-2); T.eq(r:GetValue(), 0)
    r.glyphs[4]:Click(); T.eq(got, 4); T.eq(r:GetValue(), 4)
    r.glyphs[2]._scripts.OnEnter(r.glyphs[2]); r.glyphs[2]._scripts.OnLeave(r.glyphs[2])
    r:SetEnabledState(false); r.glyphs[1]:Click(); T.eq(r:GetValue(), 4)
    UI.Rating(parent, { skin = name, count = 3, full = "a", empty = "b", value = 2 })
  end)
end)

T.test("Toast: queue of 5, stack of 3, fade, dismiss, banners", function()
  UI.ToastClear()
  local handles = {}
  for i = 1, 5 do
    handles[i] = UI.Toast({ skin = SKINS[i % 2 + 1], title = "Toast " .. i, text = "body", banner = ({ "good", "bad", nil })[i % 3 + 1],
      icon = "Interface\\Icons\\X", sound = i == 1 and true or nil, duration = 5 })
  end
  local a, q = UI.ToastState()
  T.eq(a, 3); T.eq(q, 2)
  handles[1].frame._scripts.OnEnter(handles[1].frame)
  handles[1].frame._scripts.OnLeave(handles[1].frame)
  local maxActive = 0
  for _ = 1, 40 do
    UI.ToastTick(1)
    local act = UI.ToastState()
    if act > maxActive then maxActive = act end
  end
  T.eq(maxActive, 3)
  a, q = UI.ToastState()
  T.eq(a, 0); T.eq(q, 0)
  -- dismiss active + queued
  local hs = {}
  for i = 1, 5 do hs[i] = UI.Toast({ title = "d" .. i, duration = 30 }) end
  hs[5]:Dismiss()
  a, q = UI.ToastState(); T.eq(q, 1)
  hs[1]:Dismiss()
  hs[2].frame._scripts.OnMouseUp(hs[2].frame)
  for _ = 1, 4 do UI.ToastTick(1) end
  a, q = UI.ToastState()
  T.eq(a, 2, "queued promoted"); T.eq(q, 0)
  UI.ToastClear()
  a, q = UI.ToastState(); T.eq(a, 0)
  for _ = 1, 30 do UI.Toast({ title = "flood" }) end
  a, q = UI.ToastState(); T.eq(a, 3); T.ok(q <= 20)
  UI.ToastClear()
end)

T.test("TalkingHead: queue of 2, fades, close, buttons, dedupe", function()
  local closed = {}
  local h1 = UI.TalkingHead({ skin = "elders", unit = "player", name = "Elders", text = "First", duration = 4,
    onClose = function() closed[#closed + 1] = 1 end })
  local h2 = UI.TalkingHead({ skin = "bloodsports", portrait = "Interface\\Icons\\X", name = "Bookie", text = "Second", duration = 2,
    height = 220, onClose = function() closed[#closed + 1] = 2 end })
  T.ok(h1.body and h2.body, "body frames")
  T.eq(h2:GetHeight(), 220)
  local cur, queued = UI.TalkingHeadState()
  T.eq(cur, h1); T.eq(queued, 1)
  T.eq(h1:IsShown(), true); T.eq(h2:IsShown(), false)
  T.eq(UI.TalkingHead({ key = "k", text = "x", duration = 1 }), UI.TalkingHead({ key = "k" }), "dedupe by key")
  local _, q2 = UI.TalkingHeadState(); T.eq(q2, 2)
  UI.TalkingHeadTick(0.1); T.near(h1:GetAlpha(), 0.4, 1e-6)
  UI.TalkingHeadTick(0.2); T.eq(h1:GetAlpha(), 1)
  UI.TalkingHeadTick(3.9)
  T.eq(h1:IsShown(), true)
  UI.TalkingHeadTick(0.2)   -- hold over: fade out starts
  UI.TalkingHeadTick(0.5)   -- fade out done
  T.eq(h1:IsShown(), false); T.eq(closed[1], 1)
  T.eq(UI.TalkingHeadState(), h2); T.eq(h2:IsShown(), true)
  h2._scripts.OnMouseUp(h2, "RightButton")
  for _ = 1, 3 do UI.TalkingHeadTick(0.5) end
  T.eq(closed[2], 1 + 1)
  -- the keyed head (queued) comes next; close it while queued after re-queue
  local keyed = UI.TalkingHeadState()
  T.ok(keyed and keyed.key == "k")
  local pending = UI.TalkingHead({ text = "pending", duration = 1, onClose = function() closed[#closed + 1] = "p" end })
  pending:Close()
  T.eq(closed[#closed], "p")
  keyed:Close()
  for _ = 1, 3 do UI.TalkingHeadTick(0.5) end
  T.eq(UI.TalkingHeadState(), nil)
  -- buttons + persistent head
  local clicked
  local hb = UI.TalkingHead({ skin = "elders", displayID = 1234, name = "Ask", text = "Pick one", duration = 0, height = 200,
    buttons = { { text = "No" }, { text = "Yes", onClick = function() clicked = true end } } })
  UI.TalkingHeadTick(0.3)
  UI.TalkingHeadTick(100)
  T.eq(hb:IsShown(), true, "duration 0 stays")
  hb.buttons[2]:Click()
  T.eq(clicked, true)
  for _ = 1, 3 do UI.TalkingHeadTick(0.5) end
  T.eq(hb:IsShown(), false)
  hb.closeButton:Click()
  T.noErrors()
end)

T.test("MinimapButton: geometry, drag math, click, hide", function()
  local db = {}
  local clicks = {}
  local b = UI.MinimapButton({ name = "TestKitMinimapButton", icon = "Interface\\Icons\\X", db = db,
    onClick = function(button) clicks[#clicks + 1] = button end, tooltip = function(tt) tt:AddLine("tip") end })
  T.eq(db.angle, 200)
  T.eq(b:GetWidth(), 33)
  local x, y = UI.MinimapPosition(0, 140)
  T.near(x, 80, 1e-6); T.near(y, 0, 1e-6)
  x, y = UI.MinimapPosition(90, 140)
  T.near(x, 0, 1e-6); T.near(y, 80, 1e-6)
  x, y = UI.MinimapPosition(180, 100)
  T.near(x, -60, 1e-6)
  T.near(UI.MinimapAngle(0, 0, 1, 0), 0, 1e-6)
  T.near(UI.MinimapAngle(0, 0, 0, 1), 90, 1e-6)
  T.near(UI.MinimapAngle(0, 0, 0, -1), 270, 1e-6)
  T.near(UI.MinimapAngle(0, 0, -1, 0), 180, 1e-6)
  local realCursor = GetCursorPosition
  GetCursorPosition = function() return 500, 500 end   -- Minimap centre is (500, 400): straight up
  b._scripts.OnDragStart(b)
  T.eq(b.dragging, true)
  b._scripts.OnUpdate(b)
  T.near(db.angle, 90, 1e-6)
  GetCursorPosition = function() return 400, 400 end   -- straight left
  b:DragStep()
  T.near(db.angle, 180, 1e-6)
  b._scripts.OnDragStop(b)
  GetCursorPosition = realCursor
  T.eq(b.dragging, false)
  b:Click("LeftButton"); b:Click("RightButton")
  T.eq(clicks[1], "LeftButton"); T.eq(clicks[2], "RightButton")
  b._scripts.OnEnter(b); b._scripts.OnLeave(b); b._scripts.OnMouseDown(b); b._scripts.OnMouseUp(b)
  b:SetAngle(-30); T.near(db.angle, 330, 1e-6)
  b:SetHidden(true); T.eq(b:IsShown(), false); T.eq(db.hide, true)
  b:SetHidden(false); T.eq(b:IsShown(), true)
  local hidden = UI.MinimapButton({ db = { hide = true } })
  T.eq(hidden:IsShown(), false)
end)

T.test("Settings: registers a category, tolerates a missing API", function()
  local registered = {}
  local origReg = Settings.RegisterAddOnSetting
  Settings.RegisterAddOnSetting = function(cat, var, key, tbl, vtype, name, default)
    registered[#registered + 1] = { var = var, key = key, tbl = tbl, name = name, default = default }
    return origReg(cat, var, key, tbl, vtype, name, default)
  end
  local db = { music = true }
  local cat = UI.Settings({ name = "KitTest", db = db, options = {
    { type = "header", label = "General" },
    { type = "check", key = "music", label = "Music", tooltip = "t" },
    { type = "check", key = "toasts", label = "Toasts", default = true },
    { type = "slider", key = "scale", label = "Scale", min = 50, max = 150, step = 5 },
    { type = "bogus", key = "x" },
  } })
  Settings.RegisterAddOnSetting = origReg
  T.ok(cat, "category")
  T.eq(#registered, 3)
  T.eq(registered[1].var, "KitTest_music"); T.eq(db.music, true)
  T.eq(db.toasts, true); T.eq(db.scale, 50)
  T.eq(UI.OpenSettings(cat), true)
  T.eq(UI.OpenSettings(nil), false)
  local saved = Settings
  _G.Settings = nil
  T.eq(UI.Settings({ name = "none", db = {}, options = {} }), nil)
  T.eq(UI.OpenSettings(cat), false)
  _G.Settings = { RegisterVerticalLayoutCategory = function() error("nope") end }
  T.eq(UI.Settings({ name = "broken", options = {} }), nil)
  _G.Settings = saved
end)

T.test("ExportBox: shows selectable text, reused per skin", function()
  eachSkin(function(name)
    local text = string.rep("WOM1:test:AAAA:", 200)
    local w = UI.ExportBox({ skin = name, title = "Export", text = text })
    T.eq(w:IsShown(), true)
    T.eq(w.edit:GetText(), text)
    w.edit._text = "tampered"
    w.edit._scripts.OnTextChanged(w.edit, true)
    T.eq(w.edit:GetText(), text, "read-only")
    w.scroll._scripts.OnMouseWheel(w.scroll, -1)
    w:SelectAll()
    local w2 = UI.ExportBox({ skin = name, title = "Again", text = "short" })
    T.eq(w2, w); T.eq(w2.edit:GetText(), "short")
    w.edit._scripts.OnEscapePressed(w.edit)
    T.eq(w:IsShown(), false)
  end)
end)

T.test("Demo: /mkdemo builds everything in both skins", function()
  T.eq(SLASH_METAKITDEMO1, "/mkdemo")
  eachSkin(function(name)
    local w = UI.Demo(name)
    T.eq(w:IsShown(), true)
    T.eq(w.list:GetData()[500].rank, 500)
    for i = 1, 3 do w.tabs:Select(i) end
    w.list._scripts.OnMouseWheel(w.list, -2)
    w.stats._scripts.OnMouseWheel(w.stats, -2)
    w.rating.glyphs[2]:Click()
    T.eq(UI.Demo(name), w, "demo reused")
  end)
  SlashCmdList.METAKITDEMO("bloodsports")
  SlashCmdList.METAKITDEMO("")
  SlashCmdList.METAKITDEMO("unknownskin")
  T.ok(_G.MetaKitDemoMinimapButton, "demo minimap button")
  T.ok(_G.MetaKitDemo_elders and _G.MetaKitDemo_bloodsports)
  UI.ToastClear()
  T.noErrors()
end)

T.done()
