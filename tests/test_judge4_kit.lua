-- judge4 fix lane, kit side: the sidebar watermark (shown / hidden by the parchment left between the card and Sync,
-- alpha recorded), the card's ink colours on parchment (#1a1006 lines, #4a3418 soft line, never grey) and the native
-- checkbox size pass-through. Stub limits: no rendering, so "faint" is the alpha handed to SetAlpha and colours are
-- the values handed to the API, never sampled pixels; the stub accepts every template and every SetSize, so the
-- "template ignores SetSize" case is only covered by the holder anchors (two corners pinned to a 26 px frame).
local stubPath = os.getenv("WOW_STUB") or "tests/wow_stub.lua"
local T = dofile(stubPath)
local root = stubPath:match("^(.*)/tests/wow_stub.lua$") or "."
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Data/GlobalStringsFallback", "Strings", "Codec", "Comm",
    "Lobby", "Venue", "UI/Theme", "UI/Widgets", "UI/List", "UI/StatRows", "UI/Rating", "UI/Toast", "UI/TalkingHead",
    "UI/Minimap", "UI/Settings", "UI/ExportBox", "UI/Demo", "UI/Shell" }) do
  dofile(root .. "/MetaKit/" .. f .. ".lua")
end
local UI = MetaKit.UI

local function same(a, b, msg)
  for i = 1, 3 do T.near(a[i], b[i], 1e-6, msg) end
end
local function hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end

local ART = { logo_m = "Interface\\AddOns\\Elders\\Media\\logo_m" }
local function shell(name, extra)
  local o = { name = name, title = "x", db = {}, sidebar = "parchment", footerText = "Sync now",
    art = function(token) return ART[token] end }
  for k, v in pairs(extra or {}) do o[k] = v end
  local s = UI.Shell(o)
  s.sidebar:SetHeight(560)
  s:AddTab({ id = "t", label = "T", summary = { { "Record", "0-0" }, { "Win rate", "50%" } } })
  s:AddSection({ tab = "t", id = "a", label = "A", build = function(f) return f end,
    card = { title = "THIS RING", lines = { "Ratchet", { text = "No referee on duty.", soft = true } } } })
  s:AddSection({ tab = "t", id = "b", label = "B", build = function(f) return f end })
  s:Show(); s:Select("t", "a")
  return s, s.tabById.t
end

T.test("watermark: logo_m centred between the card and Sync at 10% alpha when the gap is > 140 px", function()
  local s, tab = shell("TestJ4Wm", { sidebarWatermark = true })
  local wm = tab.watermark
  local syncTop = 560 - 8 - s.footerHeight
  T.eq(wm.top, tab.cardBottom, "the gap starts at the card's bottom")
  T.eq(wm.space, syncTop - tab.cardBottom, "and ends at the Sync plate's top")
  T.ok(wm.space > UI.ShellWatermark.minSpace, "560 px sidebar leaves " .. wm.space .. " px")
  T.eq(wm.shown, true); T.eq(wm.alpha, 0.10); T.eq(wm.size, 120); T.eq(wm.path, ART.logo_m)
  local tex = tab.wmTex
  T.eq(tex:IsShown(), true); T.eq(tex:GetAlpha(), 0.10, "alpha handed to the texture")
  T.eq(tex:GetTexture(), ART.logo_m); T.eq(tex:GetWidth(), 120); T.eq(tex:GetHeight(), 120)
  local pt, rel, rp, x, y = tex:GetPoint(1)
  T.eq(pt, "CENTER"); T.eq(rel, tab.side); T.eq(rp, "TOP"); T.eq(x, 0)
  T.eq(y, -math.floor(tab.cardBottom + wm.space / 2 + 0.5), "vertically centred in the gap")
  -- a short sidebar: the gap drops to <= 140 px and the watermark hides
  s.sidebar:SetHeight(tab.cardBottom + 140 + 8 + s.footerHeight)
  s:Refresh()
  T.eq(tab.watermark.space, 140); T.eq(tab.watermark.shown, false); T.eq(tab.wmTex:IsShown(), false)
  s.sidebar:SetHeight(tab.cardBottom + 141 + 8 + s.footerHeight)
  s:Refresh()
  T.eq(tab.watermark.space, 141); T.eq(tab.watermark.shown, true); T.eq(tab.wmTex:IsShown(), true)
  -- a section without a card: the gap starts under the summary instead
  s.sidebar:SetHeight(560); s:Select("t", "b")
  T.eq(tab.cardBottom, nil); T.eq(tab.watermark.top, tab.summaryBottom + 8); T.eq(tab.watermark.shown, true)
end)

T.test("watermark: off by default, a path option, unresolved token hides, the shared shell turns it on", function()
  local _, tab = shell("TestJ4WmOff")
  T.eq(tab.watermark.shown, false); T.eq(tab.wmTex, nil, "nothing created when off")
  local _, tab2 = shell("TestJ4WmPath", { sidebarWatermark = "Interface\\Custom\\WM" })
  T.eq(tab2.watermark.shown, true); T.eq(tab2.wmTex:GetTexture(), "Interface\\Custom\\WM")
  local _, tab3 = shell("TestJ4WmMissing", { sidebarWatermark = "no_such_art" })
  T.eq(tab3.watermark.shown, false)
  local ns = { Media = { path = "Interface\\AddOns\\Bloodsports\\Media\\", has = { logo_m = true } } }
  local sh = UI.SharedShell({}, ns)
  T.eq(sh.opts.sidebarWatermark, true)
  T.eq(sh:WatermarkPath(), "Interface\\AddOns\\Bloodsports\\Media\\logo_m", "logo_m through the registered ns")
end)

T.test("card ink on parchment: lines #1a1006, the soft empty line #4a3418 (not grey), title unchanged", function()
  local _, tab = shell("TestJ4Card")
  same(UI.ShellCard.parchLine, hex("1a1006")); same(UI.ShellCard.parchSoft, hex("4a3418"))
  same(tab.cardUI.rows[1].mkColor, hex("1a1006"), "body line in full ink")
  same(tab.cardUI.rows[2].mkColor, hex("4a3418"), "soft line dark brown")
  local c = tab.cardUI.rows[2].mkColor
  T.ok(math.abs(c[1] - c[3]) > 0.1, "soft line carries hue (brown), not a neutral grey")
  same(tab.cardUI.titleColor, UI.ShellCard.parchTitle)
  -- an explicit line colour still wins
  local s2 = UI.Shell({ name = "TestJ4CardColor", title = "x", db = {}, sidebar = "parchment" })
  s2.sidebar:SetHeight(560)
  s2:AddTab({ id = "t", label = "T" })
  s2:AddSection({ tab = "t", id = "a", label = "A", build = function(f) return f end,
    card = { title = "X", lines = { { text = "Win", color = { 0.1, 0.4, 0.1, 1 } } } } })
  s2:Show(); s2:Select("t", "a")
  same(s2.tabById.t.cardUI.rows[1].mkColor, { 0.1, 0.4, 0.1 })
end)

T.test("checkbox: native size passes through (26 px holder + pinned template), default stays 24", function()
  local p = CreateFrame("Frame")
  local c = UI.Checkbox(p, { label = "Become referee", native = true, size = 26, labelLeft = true })
  T.eq(c.native, true); T.eq(c.boxSize, 26)
  T.eq(c.boxHolder:GetWidth(), 26); T.eq(c.boxHolder:GetHeight(), 26)
  T.eq(c.box:GetWidth(), 26); T.eq(c.box:GetHeight(), 26)
  T.eq(c.box:GetNumPoints(), 2, "pinned by two corners, so the holder's size wins over the template's")
  T.eq(select(2, c.box:GetPoint(1)), c.boxHolder)
  T.eq(c:GetHeight(), 26, "the wrapper is as tall as the box")
  T.eq(c:MeasuredWidth(), 26 + 4 + #"Become referee" * 6 + 2)
  T.eq(select(1, c.boxHolder:GetPoint(1)), "RIGHT"); T.eq(select(2, c.text:GetPoint(1)), c.boxHolder)
  local d = UI.Checkbox(p, { label = "List me", native = true })
  T.eq(d.boxSize, UI.CheckNativeSize); T.eq(d:GetHeight(), 24)
  c:Click(); T.eq(c.box:GetChecked(), true)
end)

T.done()
