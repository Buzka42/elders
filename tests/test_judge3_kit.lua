-- JUDGE3 fix lane, kit side: two button tiers (F-8), native checks + dropdown arrows (F-10), the List header assert
-- and first-text-column empty inset (F-1 / F-11), the shell's sidebar context card (F-6), the summary dash (S6), the
-- medallion scale (S8; v18: the medallion is removed) and currentSection-before-onShow (the F-1 refresh race). Stub limits: no rendering; text is
-- measured at 6 px/char; colours are the values handed to the API, never sampled pixels.
local stubPath = os.getenv("WOW_STUB") or "tests/wow_stub.lua"
local T = dofile(stubPath)
local root = stubPath:match("^(.*)/tests/wow_stub.lua$") or "."
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Data/GlobalStringsFallback", "Strings", "Codec", "Comm",
    "Lobby", "Venue", "UI/Theme", "UI/Widgets", "UI/List", "UI/StatRows", "UI/Rating", "UI/Toast", "UI/TalkingHead",
    "UI/Minimap", "UI/Settings", "UI/ExportBox", "UI/Demo", "UI/Shell" }) do
  dofile(root .. "/MetaKit/" .. f .. ".lua")
end
local MK, UI = MetaKit, MetaKit.UI
local S = UI.SiteTokens

local function withTemplates(missing, fn)
  local prev = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    if template and missing[template] then error("Couldn't find inherited node \"" .. template .. "\"") end
    return prev(kind, name, parent, template)
  end
  local ok, err = pcall(fn)
  CreateFrame = prev
  if not ok then error(err, 0) end
end
local function same(a, b, msg)
  for i = 1, 3 do T.near(a[i], b[i], 1e-6, msg) end
end

T.test("F-8 buttons: primary = gold plate, default/secondary = dark plate + 1 px gold-dim edge, 22 px", function()
  local p = CreateFrame("Frame")
  local pri = UI.Button(p, { text = "Scan", variant = "primary", height = 22 })
  local acc = UI.Button(p, { text = "Challenge", variant = "accent", height = 22 })
  local sec = UI.Button(p, { text = "Export", variant = "secondary", height = 22 })
  local def = UI.Button(p, { text = "Settings", height = 22 })
  for _, b in ipairs({ pri, acc }) do
    T.eq(b.tier, "primary"); T.eq(b:GetHeight(), 22)
    T.eq(b.goldFill:IsShown(), true, "gold gradient fill"); T.eq(b.goldHi:IsShown(), true, "1 px top highlight")
    same(b.borderColor, S.plateGoldEdge, "gold edge"); same(b.labelColor, S.plateGoldLabel, "dark label on gold")
  end
  for _, b in ipairs({ sec, def }) do
    T.eq(b.tier, "secondary"); T.eq(b:GetHeight(), 22)
    T.eq(b.goldFill:IsShown(), false)
    same(b.borderColor, { 138 / 255, 106 / 255, 46 / 255 }, "1 px gold-dim (138,106,46) edge")
    same(b.labelColor, S.plateDarkLabel)
  end
  -- hover = a wash, never a re-tint into another tier; disabled = half alpha
  pri._scripts.OnEnter(pri); T.eq(pri.wash:IsShown(), true); T.eq(pri.tier, "primary"); pri._scripts.OnLeave(pri)
  T.eq(pri.wash:IsShown(), false)
  sec:SetEnabledState(false); T.eq(sec:GetAlpha(), 0.5); sec:SetEnabledState(true); T.eq(sec:GetAlpha(), 1)
  -- danger / active keep the flat look
  T.eq(UI.Button(p, { text = "x", variant = "danger" }).tier, "flat")
  local a = UI.Button(p, { text = "y" }); a:SetActive(true); T.eq(a.tier, "flat")
end)

T.test("F-10 checkbox: native UICheckButtonTemplate when asked and present, flat box otherwise; label left", function()
  local p = CreateFrame("Frame")
  local got
  local c = UI.Checkbox(p, { label = "List me", native = true, onChange = function(v) got = v end })
  T.eq(c.native, true); T.eq(c.box._template, "UICheckButtonTemplate"); T.eq(c.boxSize, 24)
  T.eq(c:MeasuredWidth(), 24 + 4 + #"List me" * 6 + 2)
  c:Click(); T.eq(got, true); T.eq(c.box:GetChecked(), true, "the template box mirrors the state")
  c._scripts.OnEnter(c); c._scripts.OnLeave(c)
  withTemplates({ UICheckButtonTemplate = true }, function()
    local f = UI.Checkbox(p, { label = "Become referee", native = true, labelLeft = true })
    T.eq(f.native, false, "flat fallback when the template is refused"); T.eq(f.boxSize, 18)
    T.eq(f:MeasuredWidth(), 18 + 8 + #"Become referee" * 6 + 2)
    T.eq(select(1, f.box:GetPoint(1)), "RIGHT", "box on the right edge")
    T.eq(select(1, f.text:GetPoint(1)), "RIGHT"); T.eq(select(3, f.text:GetPoint(1)), "LEFT", "label left of the box")
    f:Click(); T.eq(f:GetChecked(), true)
  end)
  T.eq(UI.Checkbox(p, { label = "plain" }).native, false, "opt-in only")
end)

T.test("F-4 / F-10 dropdown: 18 px native arrow flush right, 8 px text inset, one line", function()
  local d = UI.Dropdown(CreateFrame("Frame"), { width = 230, height = 22, items = { { value = "h", text = "Honor Road Fight Club" } } })
  d:SetValue("h")
  T.eq(d.arrow:GetWidth(), 18); T.eq(d.arrow:GetHeight(), 18)
  T.eq(d.arrow:GetTexture(), UI.Tex.dropArrow)
  local pt, _, rp, x = d.arrow:GetPoint(1)
  T.eq(pt, "RIGHT"); T.eq(rp, "RIGHT"); T.eq(x, -2)
  T.eq(select(4, d.label:GetPoint(1)), 8, "text inset 8 px")
  T.eq(select(4, d.label:GetPoint(2)), -(18 + 4), "text stops before the arrow")
  T.ok(#"Honor Road Fight Club" * 6 <= 230 - 8 - 22, "the club name fits on one line at 230 px")
  d._scripts.OnMouseDown(d); T.eq(d.arrow:GetTexture(), UI.Tex.dropArrowDown)
  d._scripts.OnMouseUp(d); T.eq(d.arrow:GetTexture(), UI.Tex.dropArrow)
  T.eq(d.tier, "secondary", "dropdowns share the secondary plate")
end)

T.test("F-1 List header assert: overlap / fit / overflow are reported; clean columns report nothing", function()
  local p = CreateFrame("Frame")
  local bad = UI.List(p, { width = 674, chrome = "inset", gutter = 16, columns = {
    { key = "a", title = "Name", kind = "text" }, { key = "b", title = "Lvl", width = 32 },
    { key = "c", title = "W / Rating", width = 62 }, { key = "d", title = "Seen", width = 40 } } })
  local kinds = {}
  for _, i in ipairs(bad.headerIssues) do kinds[i.kind .. ":" .. tostring(i.title)] = true end
  T.ok(kinds["fit:Lvl"] and kinds["fit:W / Rating"], "the round-2 Finder widths truncate (L… and W / Ra…)")
  local over = UI.List(p, { width = 300, gutter = 16, columns = { { key = "a", title = "A", width = 200 }, { key = "b", title = "B", width = 200 } } })
  local hasOverflow = false
  for _, i in ipairs(over.headerIssues) do if i.kind == "overflow" then hasOverflow = true end end
  T.ok(hasOverflow, "columns wider than the list are reported")
  local good = UI.List(p, { width = 674, chrome = "inset", gutter = 16, columns = {
    { key = "i", title = "", width = 22, kind = "icon" }, { key = "a", title = "Name", kind = "text" },
    { key = "b", title = "Lvl", width = 40, align = "RIGHT" }, { key = "c", title = "Rating", width = 60, align = "RIGHT" } } })
  T.eq(#good.headerIssues, 0)
  T.ok(good.columns[3].headL >= good.columns[2].headR, "disjoint drawn ranges")
end)

T.test("F-11 List: a LEFT empty state starts at the first TEXT column, past an icon cell", function()
  local p = CreateFrame("Frame")
  local l = UI.List(p, { width = 674, chrome = "inset", gutter = 16, emptyAlign = "LEFT", emptyText = "None.", emptyHint = "Hint.",
    columns = { { key = "i", title = "", width = 22, kind = "class" }, { key = "a", title = "Referee", kind = "text" } } })
  T.eq(l.emptyText:GetText(), "None.", "emptyText alias")
  T.eq(l.emptyInset, l.columns[2].textL); T.eq(l.emptyInset, 4 + 22 + 8)
  T.eq(select(4, l.emptyText:GetPoint(1)), l.emptyInset); T.eq(select(4, l.emptyHintText:GetPoint(1)), l.emptyInset)
  local t = UI.List(p, { width = 674, gutter = 16, emptyAlign = "LEFT", empty = "x", columns = { { key = "a", title = "A" } } })
  T.eq(t.emptyInset, 4 + 8, "text-first table: unchanged")
end)

T.test("S8 medallion gone (v18: template portrait); F-1 race: currentSection set before onShow fires", function()
  T.eq(UI.ShellArt.medallionScale, nil); T.eq(UI.ShellArt.medallionDisc, nil)
  local s = UI.Shell({ name = "TestJ3Race", title = "x", db = {}, sidebar = "parchment" })
  local seen = {}
  s:AddTab({ id = "t", label = "T" })
  for _, id in ipairs({ "a", "b" }) do
    s:AddSection({ tab = "t", id = id, label = id, build = function(f) return f end,
      onShow = function(_, sh) seen[#seen + 1] = id .. "=" .. tostring(sh.currentSection) end })
  end
  s:Show(); s:Select("t", "a"); s:Select("t", "b")
  T.eq(seen[#seen], "b=b", "onShow sees its own section as current")
  for _, v in ipairs(seen) do local a, b = v:match("^(%w)=(%w+)$"); T.eq(a, b, v) end
end)

T.test("F-6 shell card: per-section spec, Cinzel title in dark gold on parchment, ink lines, soft empty line", function()
  local s = UI.Shell({ name = "TestJ3Card", title = "x", db = {}, sidebar = "parchment", footerText = "Sync now" })
  s.sidebar:SetHeight(560)
  s:AddTab({ id = "t", label = "T", summary = { { "Record", "0-0" } },
    card = function(_, tabId, secId) return { title = "TAB " .. tabId, lines = { "tab-level " .. tostring(secId) } } end })
  s:AddSection({ tab = "t", id = "a", label = "A", build = function(f) return f end,
    card = { title = "LAST RESULTS", lines = { { text = "No duels yet.", soft = true } } } })
  s:AddSection({ tab = "t", id = "b", label = "B", build = function(f) return f end })
  s:Show(); s:Select("t", "a")
  local tab = s.tabById.t
  T.eq(tab.cardTitle, "LAST RESULTS"); T.eq(tab.cardShown, 1); T.eq(tab.cardLines[1], "No duels yet.")
  T.eq(tab.cardUI.title:GetText(), "LAST RESULTS"); T.eq(tab.cardUI.title.mkSize, UI.ShellCard.titleSize)
  same(tab.cardUI.titleColor, UI.ShellCard.parchTitle, "dark gold title on parchment")
  same(tab.cardUI.rows[1].mkColor, UI.ShellCard.parchSoft, "soft empty line")
  T.eq(tab.cardUI.rows[1].mkSize, 11, "11 px lines")
  T.ok(tab.cardTop > tab.summaryBottom, "under the summary")
  T.ok(tab.cardBottom <= 560 - s:SummaryBottomOffset(), "above the footer band")
  s:Select("t", "b")
  T.eq(tab.cardTitle, "TAB t"); T.eq(tab.cardLines[1], "tab-level b", "the tab's card function gets the section id")
  same(tab.cardUI.rows[1].mkColor, S.summaryInk.label, "body lines in the summary ink")
  T.eq(s:RefreshSidebar(), true)
  -- a short sidebar drops card lines from the bottom instead of running into the footer
  s.sidebar:SetHeight(tab.cardTop + 9 + UI.ShellCard.titleH + s:SummaryBottomOffset() + 2)
  s:Refresh()
  T.eq(tab.cardShown, 0)
end)

T.test("S6 summary: the lone dash value is full ink and outlined; real values are not", function()
  local s = UI.Shell({ name = "TestJ3Dash", title = "x", db = {}, sidebar = "parchment" })
  s:AddTab({ id = "t", label = "T", summary = { { "Win rate", UI.ShellDash }, { "Record", "0-0" } } })
  s:AddSection({ tab = "t", id = "a", label = "A", build = function(f) return f end })
  s:Show(); s:Select("t", "a")
  local rows = s.tabById.t.summaryUI.rows
  T.eq(rows[1].value.mkOutline, true); T.eq(rows[2].value.mkOutline or false, false)
  same(UI.ShellSummaryColor(nil, s.summaryInk), S.summaryInk.value, "dash value colour = the value ink")
  same(S.summaryInk.value, S.summaryInk.label, "value ink = label ink (full ink)")
end)

T.done()
