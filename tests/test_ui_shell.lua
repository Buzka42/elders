-- MetaKit UI Shell: chrome fallback chain, tabs gated on loaded addons, lazy one-time section builds, cover art,
-- position/size persistence, Display font fallback, plates, /mkchrome, and the older widgets still working after it.
local stubPath = os.getenv("WOW_STUB") or "tests/wow_stub.lua"
local T = dofile(stubPath)
local root = stubPath:match("^(.*)/tests/wow_stub.lua$") or "."

for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Data/GlobalStringsFallback", "Strings", "Codec", "Comm",
    "Lobby", "Venue", "UI/Theme", "UI/Widgets", "UI/List", "UI/StatRows", "UI/Rating", "UI/Toast", "UI/TalkingHead",
    "UI/Minimap", "UI/Settings", "UI/ExportBox", "UI/Demo", "UI/Shell" }) do
  dofile(root .. "/MetaKit/" .. f .. ".lua")
end
local MK, UI = MetaKit, MetaKit.UI

-- The stub accepts any template; the real client raises on unknown ones. `missing` lists the templates to refuse.
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
local NO_PORTRAIT = { PortraitFrameTemplate = true, PortraitFrameFlatTemplate = true }

local realLoaded = C_AddOns.IsAddOnLoaded
local function loadedSet(set)
  C_AddOns.IsAddOnLoaded = function(name) return set[name] and true or false end
end
local function restoreLoaded() C_AddOns.IsAddOnLoaded = realLoaded end

local function inSpecial(name)
  for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
  return false
end

-- The stub's font strings ignore shadow / colour calls; inside fn, frames make font strings that record them.
local function recordingFonts(fn)
  local prev = CreateFrame
  CreateFrame = function(...)
    local f = prev(...)
    local make = f.CreateFontString
    f.CreateFontString = function(frame, ...)
      local fs = make(frame, ...)
      fs.SetShadowOffset = function(self, x, y) self._shadow = { x, y } end
      fs.GetShadowOffset = function(self) return unpack(self._shadow or {}) end
      fs.SetTextColor = function(self, r, g, b, a) self._color = { r, g, b, a } end
      fs.GetTextColor = function(self) return unpack(self._color or {}) end
      -- v7: font size / object are recorded too. Pessimistic: a font object change drops the recorded colour (the
      -- client may apply the object's own colour), so a colour that survives is one set AFTER the last font change.
      fs.SetFont = function(self, file, size, flags) self._font = { file, size, flags } end
      fs.GetFontSize = function(self) return self._font and self._font[2] end
      fs.SetFontObject = function(self, obj) self._fontObj = obj; self._font = nil; self._color = nil end
      return fs
    end
    return f
  end
  local ok, err = pcall(fn)
  CreateFrame = prev
  if not ok then error(err, 0) end
end

T.test("Theme: site tokens and shell metrics are additive", function()
  for _, key in ipairs({ "stone0", "stone1", "stone2", "stone3", "stoneEdge", "gold", "goldDeep", "goldDim", "parch",
      "inkRed", "emerald", "silver" }) do
    T.eq(#UI.SiteTokens[key], 4, key)
  end
  T.near(UI.SiteTokens.stone1[1], 0x14 / 255, 1e-6)
  T.near(UI.SiteTokens.stoneEdge[3], 0x20 / 255, 1e-6)
  T.near(UI.SiteTokens.gold[2], 0xd1 / 255, 1e-6)
  T.eq(UI.ShellMetrics.sidebar, 340); T.eq(UI.ShellMetrics.titleBand, 50); T.eq(UI.ShellMetrics.tabStrip, 25)
  -- the widget tokens are untouched
  T.near(UI.Tokens.accent[1], 0.973, 1e-6)
  T.eq(UI.Tokens.stone1, nil)
end)

T.test("Shell: constructs with no PortraitFrameTemplate (fallback chain to a plain frame)", function()
  local shell
  withTemplates(NO_PORTRAIT, function()
    shell = UI.Shell({ name = "TestShellPlain", title = "World of Meta", subtitle = "sub", db = {} })
  end)
  T.eq(shell.chrome, "plain")
  T.eq(shell.template, nil)
  T.eq(shell.frame._template, nil)
  T.eq(_G.TestShellPlain, shell.frame, "global name")
  T.ok(inSpecial("TestShellPlain"), "UISpecialFrames")
  T.eq(shell.title:GetText(), "World of Meta")
  T.eq(shell.subtitle:GetText(), "sub")
  T.ok(shell.cover and shell.cover.flat and shell.cover.flat.fill, "flat cover fill on plain chrome")
  T.ok(shell.cover.flat.top and shell.cover.flat.left, "1px border")
  T.eq(shell.cover.hasArt, false)
  T.eq(shell.frame:GetWidth(), 900); T.eq(shell.frame:GetHeight(), 600)
  T.eq(shell:IsShown(), false)
  T.ok(shell.closeButton, "close button")
  shell:Show(); T.eq(shell:IsShown(), true)
  shell.closeButton:Click(); T.eq(shell:IsShown(), false)
end)

T.test("Shell: falls back to PortraitFrameFlatTemplate, then uses the native template when present", function()
  local flat
  withTemplates({ PortraitFrameTemplate = true }, function()
    flat = UI.Shell({ name = "TestShellFlat", title = "x" })
  end)
  T.eq(flat.template, "PortraitFrameFlatTemplate")
  T.eq(flat.chrome, "portrait")
  local native = UI.Shell({ name = "TestShellNative", title = "x" })
  T.eq(native.template, "PortraitFrameTemplate")
  T.eq(native.cover, nil, "native body shows when no cover art is registered")
  -- a template that provides its own title string, portrait and close button
  local saved = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    local f = saved(kind, name, parent, template)
    if template == "PortraitFrameTemplate" then
      f.TitleContainer = saved("Frame", nil, f)
      f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
      f.TitleContainer.TitleText:SetText("Template title")
      local portrait = f:CreateTexture()
      f.GetPortrait = function() return portrait end
      f.CloseButton = saved("Button", nil, f)
    end
    return f
  end
  local ok, err = pcall(function()
    local s = UI.Shell({ name = "TestShellTemplateParts", title = "Ours", portrait = "Interface\\Icons\\X" })
    T.eq(s.frame.TitleContainer.TitleText:GetText(), "", "template title cleared")
    T.eq(s.title:GetText(), "Ours")
    T.eq(s.portrait:GetTexture(), "Interface\\Icons\\X")
    T.eq(s.closeButton, s.frame.CloseButton, "uses the template close")
    s:Show(); s.closeButton:Click(); T.eq(s:IsShown(), false)
  end)
  CreateFrame = saved
  if not ok then error(err, 0) end
end)

T.test("Shell: AddTab / AddSection / Select / Toggle / Refresh, tabs only for loaded addons", function()
  loadedSet({ Bloodsports = true })
  local ok, err = pcall(function()
    local shell = UI.Shell({ name = "TestShellTabs", title = "World of Meta", db = {} })
    shell:AddTab({ id = "bloodsports", label = "Bloodsports", owner = "Bloodsports", order = 1 })
    shell:AddTab({ id = "elders", label = "Elders", owner = "Elders", order = 2 })
    shell:AddSection({ tab = "bloodsports", id = "ring", label = "The Ring", order = 1, icon = "Interface\\Icons\\X",
      build = function(p) return CreateFrame("Frame", nil, p) end })
    shell:AddSection({ tab = "elders", id = "stats", label = "Stats", build = function(p) return CreateFrame("Frame", nil, p) end })
    local vis = shell:VisibleTabs()
    T.eq(#vis, 1); T.eq(vis[1].id, "bloodsports")
    T.eq(shell:Select("elders"), false, "unloaded tab cannot be selected")
    T.eq(shell:Select("bloodsports", "ring"), true)
    T.eq(shell.current, "bloodsports")
    T.eq(shell:Toggle(), true); T.eq(shell:IsShown(), true)
    T.eq(shell.tabById.bloodsports.plate.kind, "gold")
    T.ok(not shell.tabById.elders.plate or not shell.tabById.elders.plate:IsShown(), "elders tab hidden")
    T.eq(shell.currentSection, "ring")
    T.eq(shell.tabById.bloodsports.rows[1]:GetText(), "The Ring")
    T.eq(shell.tabById.bloodsports.rows[1].kind, "gold")
    shell:Refresh()
    -- Elders loads later: Refresh brings its tab in
    loadedSet({ Bloodsports = true, Elders = true })
    shell:Refresh()
    T.eq(#shell:VisibleTabs(), 2)
    T.eq(shell.tabById.elders.plate:IsShown(), true)
    shell.tabById.elders.plate:Click()
    T.eq(shell.current, "elders"); T.eq(shell.currentSection, "stats")
    T.eq(shell.tabById.elders.plate.kind, "gold"); T.eq(shell.tabById.bloodsports.plate.kind, "dark")
    T.eq(shell.tabById.bloodsports.side:IsShown(), false)
    T.eq(shell:Toggle("bloodsports"), true, "toggle to another tab keeps it open")
    T.eq(shell.current, "bloodsports"); T.eq(shell:IsShown(), true)
    T.eq(shell:Toggle("bloodsports"), false); T.eq(shell:IsShown(), false)
    -- probe unavailable / erroring: every registered tab shows
    C_AddOns.IsAddOnLoaded = nil
    T.eq(#shell:VisibleTabs(), 2)
    C_AddOns.IsAddOnLoaded = function() error("boom") end
    T.eq(#shell:VisibleTabs(), 2)
    -- nothing loaded: empty state, no error
    loadedSet({})
    shell:Show()
    T.eq(shell.current, nil)
    T.eq(shell.emptyText:IsShown(), true)
    -- bad input is ignored
    T.eq(shell:AddTab({}), nil); T.eq(shell:AddSection({ tab = "x" }), nil); T.eq(shell:Select("nope"), false)
  end)
  restoreLoaded()
  if not ok then error(err, 0) end
end)

T.test("Shell: a section builds lazily and exactly once across repeated Select calls", function()
  local builds = { a = 0, b = 0 }
  local frames = {}
  local db = {}
  local shell = UI.Shell({ name = "TestShellLazy", title = "x", db = db })
  shell:AddTab({ id = "t1", label = "One" })
  shell:AddTab({ id = "t2", label = "Two" })
  shell:AddSection({ tab = "t1", id = "a", label = "A", order = 1, build = function(p)
    builds.a = builds.a + 1
    frames.a = CreateFrame("Frame", nil, p)
    return frames.a
  end })
  shell:AddSection({ tab = "t1", id = "b", label = "B", order = 2, build = function(p)
    builds.b = builds.b + 1
    frames.b = CreateFrame("Frame", nil, p)
    return frames.b
  end })
  shell:AddSection({ tab = "t2", id = "c", label = "C", build = function(p) return CreateFrame("Frame", nil, p) end })
  shell:Select("t1", "a")
  T.eq(builds.a, 0, "nothing builds while the window is hidden")
  shell:Toggle("t1")
  T.eq(builds.a, 1); T.eq(builds.b, 0, "B not built until selected")
  for _ = 1, 5 do shell:Select("t1", "a"); shell:Refresh() end
  T.eq(builds.a, 1)
  shell:Select("t1", "b")
  T.eq(builds.b, 1)
  T.eq(frames.a:IsShown(), false); T.eq(frames.b:IsShown(), true)
  shell:Select("t2")
  shell:Select("t1")
  T.eq(shell.currentSection, "b", "tab remembers its last section")
  T.eq(db.sections.t1, "b"); T.eq(db.tab, "t1")
  shell.tabById.t1.rows[1]:Click()
  T.eq(shell.currentSection, "a")
  for _ = 1, 3 do shell:Toggle(); shell:Toggle("t1") end
  T.eq(builds.a, 1); T.eq(builds.b, 1)
  T.eq(frames.a:IsShown(), true); T.eq(frames.b:IsShown(), false)
  -- a build that errors is caught, noted once, not retried
  local bad = 0
  shell:AddSection({ tab = "t2", id = "bad", label = "Bad", order = -1, build = function() bad = bad + 1; error("kaput") end })
  shell:Select("t2", "bad")
  shell:Select("t2", "c"); shell:Select("t2", "bad")
  T.eq(bad, 1)
  T.ok(tostring(shell.lastError):find("kaput"), "lastError kept")
  -- a build returning nothing still gets a host frame
  shell:AddSection({ tab = "t2", id = "nil", label = "Nil", build = function() end })
  shell:Select("t2", "nil")
  T.eq(shell.currentSection, "nil")
  -- RemoveTab drops the tab and its sections; the shell moves to the remaining tab
  T.eq(shell:RemoveTab("t2"), true)
  T.eq(shell.current, "t1")
  T.eq(shell.tabById.t2, nil)
  T.eq(shell:RemoveTab("t2"), false)
  T.noErrors()
end)

T.test("Shell: missing art does not error; registered art draws the 9-slice", function()
  local noArt = { Media = { path = "Interface\\AddOns\\X\\Media\\", has = {} } }
  withTemplates(NO_PORTRAIT, function()
    T.ok(UI.Shell({ name = "TestShellArt1", ns = noArt }).cover.flat.fill)
    T.ok(UI.Shell({ name = "TestShellArt2", ns = nil }).cover.flat.fill)
    T.ok(UI.Shell({ name = "TestShellArt3", ns = { Media = "broken" } }).cover.flat.fill)
    T.ok(UI.Shell({ name = "TestShellArt4", art = function() error("resolver down") end }).cover.flat.fill)
  end)
  local has = {}
  for _, t in ipairs(UI.ShellCoverTokens) do has[t] = true end
  local full = { Media = { path = "Interface\\AddOns\\X\\Media\\", has = has } }
  local s
  withTemplates(NO_PORTRAIT, function() s = UI.Shell({ name = "TestShellArt5", ns = full }) end)
  T.eq(s.cover.hasArt, true)
  T.eq(s.cover.art["cover-tl"]:GetWidth(), 64)
  T.eq(s.cover.art["cover-page"]:GetTexture(), "Interface\\AddOns\\X\\Media\\cover-page")
  T.eq(s.cover.flat.fill, nil, "page art replaces the flat fill")
  T.eq(s.cover.flat.top, nil, "edge art replaces the 1px border")
  -- native chrome draws the cover only when art exists
  T.ok(UI.Shell({ name = "TestShellArt6", ns = full }).cover.hasArt)
  -- partial art: corners only, page missing -> flat fill stays under them
  local partial = { Media = { path = "p\\", has = { ["cover-tl"] = true, ["cover-br"] = true } } }
  withTemplates(NO_PORTRAIT, function() s = UI.Shell({ name = "TestShellArt7", ns = partial }) end)
  T.ok(s.cover.art["cover-tl"] and not s.cover.art["cover-top"])
  T.ok(s.cover.flat.fill, "fill under partial art")
  -- texture loads that fail (SetTexture -> false or raising) are skipped, never fatal
  local realSetTexture = UIParent:CreateTexture().SetTexture
  local realCreateTexture = UIParent.CreateTexture
  for _, mode in ipairs({ "false", "error" }) do
    local function badSetTexture(self, path, ...)
      if type(path) == "string" and path:find("cover%-") then
        if mode == "false" then return false end
        error("bad texture")
      end
      return realSetTexture(self, path, ...)
    end
    local savedCF = CreateFrame
    CreateFrame = function(...)
      local f = savedCF(...)
      f.CreateTexture = function(frame, ...)
        local t = realCreateTexture(frame, ...)
        t.SetTexture = badSetTexture
        return t
      end
      return f
    end
    local ok, err = pcall(function()
      withTemplates(NO_PORTRAIT, function() s = UI.Shell({ name = "TestShellArtBad" .. mode, ns = full }) end)
    end)
    CreateFrame = savedCF
    if not ok then error(err, 0) end
    T.eq(s.cover.hasArt, false, mode)
    T.ok(s.cover.flat.fill, "flat fallback when every art load fails (" .. mode .. ")")
  end
end)

T.test("Shell: position and size persist in db", function()
  local db = {}
  local shell = UI.Shell({ name = "TestShellPos", title = "x", db = db })
  shell.titleBand._scripts.OnDragStart(shell.titleBand)
  shell.titleBand._scripts.OnDragStop(shell.titleBand)
  T.eq(type(db.pos), "table")
  T.eq(db.pos[1], "CENTER"); T.eq(db.pos[2], "CENTER"); T.eq(db.pos[3], 0); T.eq(db.pos[4], 0)
  db.pos = { "TOPLEFT", "TOPLEFT", 40, -60 }
  local again = UI.Shell({ name = "TestShellPos2", db = db })
  local p = again.frame._points[1]
  T.eq(p[1], "TOPLEFT"); T.eq(p[3], "TOPLEFT"); T.eq(p[4], 40); T.eq(p[5], -60)
  again:SetSize(1000, 700)
  T.eq(db.width, 1000); T.eq(db.height, 700)
  again:SetSize(100, 100)
  T.eq(db.width, 760); T.eq(db.height, 480, "clamped to the minimum")
  db.width, db.height = 1100, 720
  local sized = UI.Shell({ name = "TestShellPos3", db = db })
  T.eq(sized.frame:GetWidth(), 1100); T.eq(sized.frame:GetHeight(), 720)
  sized.grip._scripts.OnDragStart(sized.grip)
  sized.grip._scripts.OnDragStop(sized.grip)
  T.eq(db.width, 1100)
  -- no db given: works, keeps state in its own table
  local nodb = UI.Shell({ name = "TestShellPos4" })
  nodb.titleBand._scripts.OnDragStop(nodb.titleBand)
  T.eq(nodb.db.pos[1], "CENTER")
end)

T.test("Display: Cinzel when it loads, the game's face otherwise", function()
  local fs = UIParent:CreateFontString()
  local calls = {}
  fs.SetFont = function(self, path, size) calls[#calls + 1] = { path, size }; return true end
  fs.SetFontObject = function(self, obj) self.obj = obj end
  T.eq(UI.Display(fs, 16, true), true)
  T.ok(calls[1][1]:find("Fonts\\Cinzel%-Bold%.ttf$"), calls[1][1])
  T.eq(calls[1][2], 16)
  UI.Display(fs, 6, false)
  T.eq(calls[#calls][2], 10, "minimum size 10")
  T.ok(calls[#calls][1]:find("Cinzel%-Regular"), "regular when not bold")
  -- load fails: every candidate is tried, then the font object
  calls = {}
  fs.SetFont = function(self, path) calls[#calls + 1] = path; return false end
  T.eq(UI.Display(fs, 16, true), false)
  T.eq(#calls, #UI.DisplayFontCandidates(true))
  T.eq(fs.obj, GameFontNormalLarge)
  fs.SetFont = function() error("no font") end
  T.eq(UI.Display(fs, 12, true), false)
  T.eq(fs.obj, GameFontNormal)
  -- non-Latin clients never try Cinzel
  local realLocale = GetLocale
  for _, loc in ipairs({ "ruRU", "zhCN", "zhTW", "koKR" }) do
    GetLocale = function() return loc end
    calls = {}
    fs.SetFont = function(self, path) calls[#calls + 1] = path; return true end
    T.eq(UI.Display(fs, 16, true), false, loc)
    T.eq(#calls, 0, loc)
  end
  GetLocale = nil
  T.eq(UI.Display(fs, 16, true), true, "no GetLocale: Latin assumed")
  GetLocale = realLocale
  T.eq(UI.Display(nil, 16), false)
end)

T.test("Plate: gold and dark, hover, click, disabled", function()
  local clicks = 0
  local p = UI.Plate(UIParent, { kind = "gold", text = "Seal", icon = "Interface\\Icons\\X", onClick = function() clicks = clicks + 1 end,
    tooltip = "tip" })
  T.eq(p.kind, "gold")
  T.eq(p.label:GetText(), "Seal")
  T.ok(p:GetWidth() >= 60, "auto width")
  p._scripts.OnEnter(p); T.eq(p.wash:IsShown(), true)
  p._scripts.OnLeave(p); T.eq(p.wash:IsShown(), false)
  p:Click(); T.eq(clicks, 1)
  p:SetKind("dark"); T.eq(p.kind, "dark")
  p:SetSelected(true); T.eq(p.kind, "gold")
  p:SetEnabledState(false); p:Click(); T.eq(clicks, 1)
  p:SetEnabledState(true)
  p:SetIcon(nil); T.eq(p.icon:IsShown(), false)
  local fixed = UI.Plate(UIParent, { width = 300, height = 24, justify = "LEFT", text = "Row" })
  T.eq(fixed:GetWidth(), 300)
  T.eq(fixed.kind, "dark")
end)

T.test("/mkchrome opens the shell demo; registers once; no-op without a slash host", function()
  T.eq(SLASH_METAKITCHROME1, "/mkchrome")
  local fn = SlashCmdList.METAKITCHROME
  T.eq(type(fn), "function")
  fn("")
  local demo = _G.MetaKitChromeDemo
  T.ok(demo and demo:IsShown(), "demo window shown")
  local shell = UI.ChromeDemo()
  T.eq(#shell:VisibleTabs(), 2)
  T.eq(shell.current, "bloodsports")
  T.eq(shell.currentSection, "ring", "first view is The Ring")
  T.ok(#shell.demoList:GetData() >= 14, "ring list filled")
  T.eq(shell.demoList:GetSelected(), 3, "one selected row")
  T.ok(shell.demoList.zebraColors, "zebra on")
  T.eq(shell.subtitle:IsShown(), false, "window subtitle collapsed")
  T.eq(shell.frame:GetWidth(), 960); T.eq(shell.frame:GetHeight(), 640, "v9: 640 high")
  T.eq(shell.sidebar:GetWidth(), UI.ShellMetrics.compactSidebar)
  T.ok(shell.footer and shell.footer:GetText() == "Sync now", "sidebar footer plate")
  shell.footer:Click()
  -- Season Stats is one click away: the second sidebar row
  T.eq(shell.tabById.bloodsports.rows[2]:GetText(), "Season Stats")
  shell.tabById.bloodsports.rows[2]:Click()
  T.eq(shell.currentSection, "stats"); T.ok(shell.demoStats, "stat rows section")
  local want = { bloodsports = { "ring", "stats", "clubs", "finder", "duels" }, elders = { "overview", "pace", "combat" } }
  for tab, ids in pairs(want) do
    local got = shell:SortedSections(tab)
    T.eq(#got, #ids, tab)
    for i, id in ipairs(ids) do
      T.eq(got[i].id, id)
      shell:Select(tab, id)
      T.eq(got[i].error, nil, id .. " built cleanly")
    end
  end
  for id, list in pairs(shell.demoLists) do
    local minRows = id == "finder" and 12 or 14 -- v7: the Finder duelist list has 12
    T.ok(#list:GetData() >= minRows, id .. " has >= " .. minRows .. " rows")
    T.ok(list:GetSelected(), id .. " has a selected row")
    for _, row in ipairs(list:GetData()) do
      T.ok(not tostring(row.name):find("%d$"), "no numbered fake names: " .. tostring(row.name))
    end
  end
  for id, stats in pairs(shell.demoStatPages) do
    local n, good, bad = 0, 0, 0
    for _, item in ipairs(stats.items) do
      if item.row then
        n = n + 1
        if item.row.color == "good" then good = good + 1 elseif item.row.color == "bad" then bad = bad + 1 end
      end
    end
    T.ok(n >= 8, id .. " shows >= 8 stat rows")
    T.ok(good > 0 and bad > 0, id .. " has positive and negative values")
  end
  T.eq(UI.ChromeDemo(), shell, "reused")
  dofile(root .. "/MetaKit/UI/Demo.lua")
  T.eq(SlashCmdList.METAKITCHROME, fn, "registered once")
  -- the /mkchrome registration block alone, run with no slash host: it must do nothing and raise nothing
  local src = io.open(root .. "/MetaKit/UI/Demo.lua"):read("*a")
  local block = src:match("\n(if type%(SlashCmdList%) == \"table\" and not SlashCmdList%.METAKITCHROME then.-\nend)")
  T.ok(block, "guard block found")
  local host, slash = SlashCmdList, SLASH_METAKITCHROME1
  SlashCmdList, SLASH_METAKITCHROME1 = nil, nil
  local ok, err = pcall(assert(loadstring(block)))
  local leaked = SLASH_METAKITCHROME1
  SlashCmdList, SLASH_METAKITCHROME1 = host, slash
  T.ok(ok, tostring(err))
  T.eq(leaked, nil, "nothing registered without a slash host")
  T.noErrors()
end)

T.test("Shell v2: compact size, title 20 with a 2,-2 shadow, subtitle collapses, sidebar footer", function()
  local plain = UI.Shell({ name = "TestShellV2Default", title = "x" })
  T.eq(plain.frame:GetWidth(), 900); T.eq(plain.frame:GetHeight(), 600)
  T.eq(plain.sidebar:GetWidth(), 340)
  local c
  recordingFonts(function() c = UI.Shell({ name = "TestShellV2Compact", title = "x", compact = true, db = {} }) end)
  T.eq(c.frame:GetWidth(), 820); T.eq(c.frame:GetHeight(), 520)
  T.eq(c.sidebar:GetWidth(), UI.ShellMetrics.compactSidebar)
  c:SetSize(nil, nil)
  T.eq(c.db.width, 820, "SetSize default follows compact")
  -- a saved size still wins over compact
  local saved = UI.Shell({ name = "TestShellV2Saved", compact = true, db = { width = 1000, height = 700 } })
  T.eq(saved.frame:GetWidth(), 1000)
  -- title
  T.eq(UI.ShellMetrics.titleSize, 20)
  local sx, sy = c.title:GetShadowOffset()
  T.eq(sx, 2); T.eq(sy, -2)
  T.near(UI.SiteTokens.titleShadow[4], 0.85, 1e-6)
  -- subtitle nil collapses its row; setting one pushes the body down
  local bare = UI.Shell({ name = "TestShellV2Sub", title = "x" })
  T.eq(bare.subtitle:IsShown(), false)
  local top0 = bare.bodyTop
  bare:SetSubtitle("Duels, clubs and the ring")
  T.eq(bare.subtitle:IsShown(), true)
  T.ok(bare.bodyTop > top0, "subtitle row adds space")
  bare:SetSubtitle(nil)
  T.eq(bare.bodyTop, top0, "and collapses again")
  -- footer plate
  local hits = 0
  local f = UI.Shell({ name = "TestShellV2Foot", footerText = "Sync now", onFooter = function(s) hits = hits + 1; T.eq(s.name, "TestShellV2Foot") end })
  T.eq(f.footer:GetText(), "Sync now")
  f.footer:Click(); T.eq(hits, 1)
  T.eq(UI.Shell({ name = "TestShellV2NoFoot" }).footer, nil, "no footer unless asked")
  T.noErrors()
end)

T.test("Shell v2/v4: tabs are label-driven (min 110), 28 / 24 high, attached to the pane top", function()
  local m = UI.ShellMetrics
  local shell = UI.Shell({ name = "TestShellV2Tabs", title = "x", db = {} })
  shell:AddTab({ id = "a", label = "Elders", order = 1 })
  shell:AddTab({ id = "b", label = "A considerably longer tab label", order = 2 })
  shell:Select("a"); shell:Show()
  local a, b = shell.tabById.a.plate, shell.tabById.b.plate
  T.ok(a:GetWidth() >= 110, "min width")
  T.eq(a:GetWidth(), 110, "short label -> minimum")
  local sw = math.ceil(b.label:GetStringWidth())
  T.ok(b:GetWidth() > 110, "long label grows the tab")
  T.eq(b:GetWidth(), sw + 2 * m.tabPad, "width = label + padding")
  T.eq(m.tab, 28); T.eq(m.tabInactive, 24)
  T.eq(a:GetHeight(), 28); T.eq(a.kind, "gold"); T.eq(a.openBottom, true)
  T.eq(b.kind, "dark"); T.eq(b.openBottom, false); T.eq(b:GetHeight(), 24)
  -- 12 px labels; the active tab's joint (pane colour, m.tabOverlap high) covers the pane border under it
  T.eq(a.labelSize, 12); T.eq(b.labelSize, 12)
  T.eq(a.joint:IsShown(), true); T.eq(b.joint:IsShown(), false)
  T.eq(a.joint:GetHeight(), m.tabOverlap)
  T.eq(a.joint._points[1][1], "BOTTOMLEFT"); T.eq(a.joint._points[1][5], 0)
  -- the strip hangs off the content pane's top edge, overlapping it
  local p = shell.tabStrip._points[1]
  T.eq(p[1], "BOTTOMLEFT"); T.eq(p[2], shell.content); T.eq(p[3], "TOPLEFT"); T.eq(p[5], -m.tabOverlap)
  T.eq(shell.tabStrip:GetHeight(), 28)
  shell:Select("b")
  T.eq(b.kind, "gold"); T.eq(b:GetHeight(), 28); T.eq(a.kind, "dark"); T.eq(a.openBottom, false)
  T.eq(a:GetHeight(), 24); T.eq(b.joint:IsShown(), true); T.eq(a.joint:IsShown(), false)
  T.noErrors()
end)

T.test("Plate v2: gold bevel lines and the raised dark label", function()
  local k = UI.SiteTokens
  T.eq(k.plateDarkLabel[1], 1); T.near(k.plateDarkLabel[2], 0.90, 1e-6); T.near(k.plateDarkLabel[3], 0.55, 1e-6)
  T.eq(k.plateGoldHighlight[1], 1); T.eq(k.plateGoldHighlight[2], 1); T.near(k.plateGoldHighlight[3], 0.86, 1e-6)
  T.near(k.plateGoldHighlight[4], 0.5, 1e-6)
  T.ok(k.plateGoldShade[1] < k.plateGoldBottom[1] and k.plateGoldShade[2] < k.plateGoldBottom[2], "shade darker than the gradient bottom")
  -- reference gold plate colours unchanged
  T.near(k.plateGoldTop[2], 0.86, 1e-6); T.near(k.plateGoldBottom[1], 0.74, 1e-6); T.near(k.plateGoldLabel[1], 0.13, 1e-6)
  local g
  recordingFonts(function() g = UI.Plate(UIParent, { kind = "gold", text = "Seal" }) end)
  local r0, g0, b0 = g.label:GetTextColor()
  T.near(r0, 0.13, 1e-6); T.near(g0, 0.09, 1e-6); T.near(b0, 0.01, 1e-6)
  T.eq(g.hi:IsShown(), true); T.eq(g.shade:IsShown(), true)
  g:SetOpenBottom(true); T.eq(g.shade:IsShown(), false, "open bottom drops the shade")
  g:SetKind("dark"); T.eq(g.hi:IsShown(), false); T.eq(g.shade:IsShown(), false)
  local r, gg, bb = g.label:GetTextColor()
  T.eq(r, 1); T.near(gg, 0.90, 1e-6); T.near(bb, 0.55, 1e-6)
end)

T.test("List v2: zebra and selectable are opt-in and do not error", function()
  local cols = { { key = "name", title = "Name" }, { key = "n", width = 40 } }
  local rows = {}
  for i = 1, 30 do rows[i] = { name = "r" .. i, n = i } end
  local plain = UI.List(UIParent, { columns = cols, height = 240 })
  plain:SetData(rows)
  T.eq(plain.zebraColors, nil, "zebra off by default")
  T.eq(plain.rows[1].zebra:IsShown(), false)
  plain.rows[2]:Click()
  T.eq(plain:GetSelected(), false, "not selectable by default")
  local z = UI.List(UIParent, { columns = cols, height = 240, zebra = true, selectable = true })
  z:SetData(rows)
  T.eq(z.zebraColors[1], UI.SiteTokens.rowEven); T.eq(z.zebraColors[2], UI.SiteTokens.rowOdd)
  T.ok(UI.SiteTokens.rowEven[4] <= 0.5 and UI.SiteTokens.rowOdd[4] <= 0.5, "low alpha")
  T.eq(z.rows[1].zebra:IsShown(), true); T.eq(z.rows[2].zebra:IsShown(), true)
  z.rows[2]:Click()
  T.eq(z:GetSelected(), 2)
  T.eq(z.rows[2].selTex:IsShown(), true); T.eq(z.rows[2].selBar:IsShown(), true)
  T.eq(z.rows[2].zebra:IsShown(), false, "selection replaces the band")
  T.eq(z.rows[1].selTex:IsShown(), false)
  z:SetOffset(5); z:SetOffset(0)
  local custom = UI.List(UIParent, { columns = cols, zebra = { { 1, 0, 0, 0.1 }, { 0, 1, 0, 0.1 } } })
  custom:SetData(rows)
  T.eq(custom.zebraColors[1][1], 1)
  T.noErrors()
end)

T.test("Existing widgets still work with the shell up", function()
  local shell = UI.Shell({ name = "TestShellWidgets", title = "x" })
  shell:AddTab({ id = "t", label = "T" })
  local list
  shell:AddSection({ tab = "t", id = "s", label = "S", build = function(p)
    list = UI.List(p, { columns = { { key = "name", title = "Name" } } })
    return list
  end })
  shell:Toggle("t")
  local clicks = 0
  local b = UI.Button(shell.content, { text = "Go", onClick = function() clicks = clicks + 1 end })
  b:Click(); T.eq(clicks, 1)
  local l2 = UI.List(UIParent, { columns = { { key = "name", title = "Name" }, { key = "n", width = 40 } } })
  l2:SetData({ { name = "a", n = 1 }, { name = "b", n = 2 } })
  T.eq(#l2:GetData(), 2)
  list:SetData({ { name = "x" } })
  T.eq(list:GetData()[1].name, "x")
  local w = UI.Window({ name = "TestShellOldWindow", title = "old" })
  w:Toggle(); T.eq(w:IsShown(), true)
  T.noErrors()
end)

-- v3 ----------------------------------------------------------------------------------------------------------------

-- Runs fn with UI.ProbeTexture answering `false` for every path in `missing` (or for every path when missing == true).
local function withMissingTextures(missing, fn)
  local prev = UI.ProbeTexture
  UI.ProbeTexture = function(path)
    if missing == true or missing[path] then return false end
    return prev(path)
  end
  local ok, err = pcall(fn)
  UI.ProbeTexture = prev
  if not ok then error(err, 0) end
end

T.test("Shell v3: chrome option values build depth over the fallback chain", function()
  local m = UI.ShellMetrics
  T.eq(m.gap, 8, "spacing grid: gap 10 -> 8")
  -- no option: v2 chrome exactly (no depth, template kept)
  local v2 = UI.Shell({ name = "TestShellV3None" })
  T.eq(v2.chromeKind, nil); T.eq(v2.depth, nil); T.eq(v2.template, "PortraitFrameTemplate"); T.eq(v2.inset, 4)
  T.eq(UI.Shell({ name = "TestShellV3Bogus", chrome = "bogus" }).depth, nil, "unknown value ignored")
  -- dialog: plain frame, probed dialog border on a backdrop host, well, own text host
  local d = UI.Shell({ name = "TestShellV3Dialog", title = "World of Meta", chrome = "dialog" })
  T.eq(d.chromeKind, "dialog"); T.eq(d.template, nil, "dialog skips the portrait templates"); T.eq(d.chrome, "plain")
  T.eq(d.depth.dialogBorder, true)
  T.eq(d.depth.host._template, "BackdropTemplate")
  T.eq(d.depth.host._backdrop.edgeFile, UI.ShellTextures.dialogBorder)
  T.eq(d.depth.host._backdrop.edgeSize, 32)
  T.eq(d.depth.bands, nil, "art border replaces the code bands")
  T.ok(d.depth.well and d.depth.wellParts.shadeTop and d.depth.wellParts.lightBottom, "inset well")
  T.ok(d.textHost ~= d.frame, "title above the depth layer")
  T.eq(d.title:GetParent(), d.textHost)
  T.eq(d.inset, m.depthInset)
  T.eq(d.bodyTop, (m.band + 4 + m.titleSize + 4) + m.gap + m.tab - m.tabOverlap)
  local wp = d.depth.well._points
  T.eq(wp[1][2], d.sidebar); T.eq(wp[1][4], -m.wellPad); T.eq(wp[2][2], d.content)
  T.ok(d.closeButton, "close button")
  -- dialog border missing: the code band + brackets take over, still constructs
  local fb
  withMissingTextures({ [UI.ShellTextures.dialogBorder] = true }, function()
    fb = UI.Shell({ name = "TestShellV3DialogNoArt", chrome = "dialog" })
  end)
  T.eq(fb.depth.dialogBorder, false)
  T.eq(#fb.depth.bands, 24, "6 bands x 4 sides")
  T.eq(fb.depth.thickness, 12)
  T.eq(#fb.depth.brackets, 4)
  -- BackdropTemplate refused as well: still constructs
  withMissingTextures(true, function()
    withTemplates({ BackdropTemplate = true }, function()
      fb = UI.Shell({ name = "TestShellV3DialogBare", chrome = "dialog" })
    end)
  end)
  T.eq(fb.depth.dialogBorder, false); T.ok(fb.depth.well)
  -- flat: plain frame, code band; portrait: the template chain stays, band inside its edge
  local fl = UI.Shell({ name = "TestShellV3Flat", chrome = "flat" })
  T.eq(fl.template, nil); T.eq(fl.depth.thickness, 12); T.eq(fl.depth.dialogBorder, false)
  local po = UI.Shell({ name = "TestShellV3Portrait", chrome = "portrait", compact = true })
  T.eq(po.template, "PortraitFrameTemplate"); T.eq(po.chromeKind, "portrait")
  local hp = po.depth.host._points
  T.eq(hp[1][4], 2); T.eq(hp[1][5], -21, "band starts under the template title bar")
  T.eq(po.textHost, po.frame, "native chrome keeps its title host")
  -- portrait requested with no portrait template: plain fallback, still depth
  local pp
  withTemplates(NO_PORTRAIT, function() pp = UI.Shell({ name = "TestShellV3PortraitPlain", chrome = "portrait" }) end)
  T.eq(pp.chrome, "plain"); T.ok(pp.depth and pp.depth.well)
  -- every kind survives tabs, sections and a refresh
  for _, s in ipairs({ d, fb, fl, po, pp }) do
    s:AddTab({ id = "t", label = "T" })
    s:AddSection({ tab = "t", id = "a", label = "A", build = function(p) return CreateFrame("Frame", nil, p) end })
    s:Toggle("t"); s:SetSize(900, 600); s:SetSubtitle("x"); s:SetSubtitle(nil)
    T.eq(s.currentSection, "a")
  end
  T.noErrors()
end)

T.test("Shell v3: probes are cached, degrade on raise / false / missing file id", function()
  UI.ResetProbes()
  T.eq(UI.ProbeTexture(UI.ShellTextures.dialogBorder), true, "stub texture takes")
  T.eq(UI.ProbeTexture(nil), false); T.eq(UI.ProbeTexture(""), false)
  local savedFn = GetFileIDFromPath
  GetFileIDFromPath = function(p) if p:find("Parchment") then return 12345 end return nil end
  UI.ResetProbes()
  T.eq(UI.ProbeTexture(UI.ShellTextures.achParchment), true, "path API names the file")
  -- path API says no and the probe texture has no file id: missing
  local realCreate = UIParent.CreateTexture
  UIParent.CreateTexture = function(self, ...)
    local t = realCreate(self, ...)
    t.GetTextureFileID = function() return nil end
    return t
  end
  UI.ResetProbes()
  T.eq(UI.ProbeTexture(UI.ShellTextures.dialogBorder), false)
  UIParent.CreateTexture = function(self, ...)
    local t = realCreate(self, ...)
    t.SetTexture = function() error("no such file") end
    return t
  end
  UI.ResetProbes()
  T.eq(UI.ProbeTexture(UI.ShellTextures.achMetal), false, "raising SetTexture")
  UIParent.CreateTexture = realCreate
  GetFileIDFromPath = savedFn
  UI.ResetProbes()
  -- template probe: unknown without C_XMLUtil, yes / no with it
  local savedX = C_XMLUtil
  C_XMLUtil = nil
  T.eq(UI.HasTemplate("UIPanelButtonTemplate"), nil)
  C_XMLUtil = { GetTemplateInfo = function(n) if n == "UIPanelButtonTemplate" then return { type = "Button" } end end }
  T.eq(UI.HasTemplate("UIPanelButtonTemplate"), true)
  T.eq(UI.HasTemplate("UIPanelScrollBarTemplate"), false)
  C_XMLUtil = savedX
  UI.ResetProbes()
  local probe = UI.ShellProbe()
  T.eq(probe.dialogBorder, true); T.eq(probe.achParchment, true)
  T.noErrors()
end)

T.test("Shell v3: material sidebar (parchment / flat), 26 px nav rows, summary block", function()
  local m = UI.ShellMetrics
  local s = UI.Shell({ name = "TestShellV3Parch", sidebar = "parchment", footerText = "Sync now",
    summary = { { "Record", "41-17" }, { "Streak", "W5", "good" }, "Plain line", { label = "Best", value = 9, color = "gold" } } })
  T.eq(s.sidebarMaterial, "parchment"); T.eq(s.navRows, true)
  T.eq(s.sidebarTexture:GetTexture(), UI.ShellTextures.achParchment)
  T.eq(s.footerHeight, 26); T.eq(s.footer:GetHeight(), 26)
  s:AddTab({ id = "bs", label = "Bloodsports" })
  for i, id in ipairs({ "a", "b", "c" }) do
    s:AddSection({ tab = "bs", id = id, label = id:upper(), order = i, icon = "Interface\\Icons\\X",
      build = function(p) return CreateFrame("Frame", nil, p) end })
  end
  s:Toggle("bs")
  local tab = s.tabById.bs
  local r1, r2 = tab.rows[1], tab.rows[2]
  T.eq(r1:GetHeight(), m.navRow); T.eq(r1.icon:GetWidth(), m.navIcon)
  T.eq(r1.strip:GetWidth(), m.navStrip)
  T.eq(r1.kind, "gold"); T.eq(r1.strip:IsShown(), true); T.eq(r2.strip:IsShown(), false)
  T.eq(r1.plate, nil); T.eq(r1.label:GetText(), "A")
  -- rows stack with no gap from the 32 px heading block
  T.eq(r2._points[1][5], -(32 + 26))
  r2:Click()
  T.eq(s.currentSection, "b"); T.eq(r2.kind, "gold"); T.eq(r1.kind, "dark")
  -- pressed nudge on a nav row
  r2._scripts.OnMouseDown(r2)
  local lp = r2.label._points[1]; T.eq(lp[4], 8 + 16 + 8 + 1); T.eq(lp[5], -1)
  r2._scripts.OnMouseUp(r2)
  lp = r2.label._points[1]; T.eq(lp[4], 8 + 16 + 8); T.eq(lp[5], 0)
  -- summary: 4 lines anchored to the sidebar bottom, 8 px above the footer rule (8 pad + 26 plate + 8 + 1 rule + 8)
  local sm = tab.summaryUI
  T.eq(tab.summaryShown, 4)
  local bo = 8 + 26 + 8 + 1 + 8
  T.eq(s:SummaryBottomOffset(), bo)
  T.eq(sm.rule._points[1][1], "BOTTOMLEFT"); T.eq(sm.rule._points[1][5], bo + 4 * 16 + 8)
  T.eq(sm.rows[1].label:GetText(), "Record"); T.eq(sm.rows[1].value:GetText(), "41-17")
  T.eq(sm.rows[3].label:GetText(), "Plain line"); T.eq(sm.rows[3].value:IsShown(), false)
  T.eq(sm.rows[4].value:GetText(), "9")
  -- a tab-level summary wins; a function gets the tab id; an erroring one is noted, not fatal
  local seen
  s:AddTab({ id = "el", label = "Elders", summary = function(_, id) seen = id; return { { "Level", "24" } } end })
  s:AddSection({ tab = "el", id = "o", label = "O", build = function(p) return CreateFrame("Frame", nil, p) end })
  s:Select("el")
  T.eq(seen, "el"); T.eq(s.tabById.el.summaryShown, 1)
  s:AddTab({ id = "el", label = "Elders", summary = function() error("summary down") end })
  s:Select("el")
  T.ok(tostring(s.lastError):find("summary down"), "lastError kept")
  T.eq(s.tabById.el.summaryShown, 0)
  -- a real sidebar height: lines that would run into the footer are hidden
  s.sidebar:SetHeight(32 + 3 * 26 + 12 + 9 + 16 * 2 + 8 + 26 + 8 + 1 + 8)
  s:Select("bs")
  T.eq(tab.summaryShown, 2, "only the lines that fit")
  T.eq(tab.summaryFirst, 3, "dropped from the top of the block")
  T.eq(sm.rows[1].label:IsShown(), false); T.eq(sm.rows[3].label:IsShown(), true)
  T.ok(tab.summaryTop >= 32 + 3 * 26 + 12, "never over the sections")
  T.noErrors()
end)

T.test("Shell v3: parchment without the texture falls back to flat; plates keep summary too", function()
  local s
  withMissingTextures(true, function()
    s = UI.Shell({ name = "TestShellV3NoParch", sidebar = "parchment", summary = { { "Record", "1-0" } } })
  end)
  T.eq(s.sidebarMaterial, "flat"); T.eq(s.navRows, true); T.eq(s.sidebarTexture, nil)
  s:AddTab({ id = "t", label = "T" })
  s:AddSection({ tab = "t", id = "a", label = "A", build = function(p) return CreateFrame("Frame", nil, p) end })
  s:Toggle("t")
  T.eq(s.tabById.t.rows[1].ink, false); T.eq(s.tabById.t.summaryShown, 1)
  local f = UI.Shell({ name = "TestShellV3FlatSide", sidebar = "flat" })
  T.eq(f.sidebarMaterial, "flat")
  -- default sidebar (plates) with a summary
  local p = UI.Shell({ name = "TestShellV3PlateSummary", summary = { { "A", "1" }, { "B", "2" } } })
  p:AddTab({ id = "t", label = "T" })
  p:AddSection({ tab = "t", id = "a", label = "A", build = function(pp) return CreateFrame("Frame", nil, pp) end })
  p:Toggle("t")
  T.eq(p.navRows, false); T.ok(p.tabById.t.rows[1].fill, "plate rows by default")
  T.eq(p.tabById.t.summaryShown, 2)
  T.eq(UI.Shell({ name = "TestShellV3NoSummary" }).opts.summary, nil)
  T.noErrors()
end)

T.test("Shell v3: native footer button probe, plate fallback, pressed nudge on plates", function()
  local hits = 0
  local n = UI.Shell({ name = "TestShellV3Native", footerText = "Sync now", nativeButtons = true,
    footerTooltip = "tip", onFooter = function() hits = hits + 1 end })
  T.eq(n.footerNative, true); T.eq(n.footer._template, "UIPanelButtonTemplate")
  T.eq(n.footer:GetText(), "Sync now")
  n.footer:Click(); T.eq(hits, 1)
  -- template refused -> plate, still clickable
  local p
  withTemplates({ UIPanelButtonTemplate = true }, function()
    p = UI.Shell({ name = "TestShellV3NativeGone", footerText = "Sync now", nativeButtons = true,
      onFooter = function() hits = hits + 1 end })
  end)
  T.eq(p.footerNative, false); T.ok(p.footer.fill, "plate")
  p.footer:Click(); T.eq(hits, 2)
  -- client says the template does not exist -> never created
  local savedX = C_XMLUtil
  C_XMLUtil = { GetTemplateInfo = function() return nil end }
  UI.ResetProbes()
  local q = UI.Shell({ name = "TestShellV3NativeProbe", footerText = "Go", nativeButtons = true })
  C_XMLUtil = savedX
  UI.ResetProbes()
  T.eq(q.footerNative, false)
  -- pressed: label nudges 1 px down-right, back on release; disabled plates do not nudge
  local b = UI.Plate(UIParent, { width = 120, text = "Seal" })
  b._scripts.OnMouseDown(b)
  local lp = b.label._points[1]; T.eq(lp[4], 8 + 1); T.eq(lp[5], -1)
  b._scripts.OnMouseUp(b)
  lp = b.label._points[1]; T.eq(lp[4], 8); T.eq(lp[5], 0)
  b:SetEnabledState(false); b._scripts.OnMouseDown(b); T.eq(b.pressed, false)
  T.noErrors()
end)

T.test("List v3: separators, selected strip, icon size, native scrollbar probe", function()
  local cols = { { key = "name", title = "Name" }, { key = "ic", kind = "icon", width = 24 }, { key = "n", width = 40 } }
  local rows = {}
  for i = 1, 30 do rows[i] = { name = "r" .. i, n = i, ic = "Interface\\Icons\\X" } end
  local plain = UI.List(UIParent, { columns = cols, height = 240 })
  plain:SetData(rows)
  T.eq(plain.separators, false); T.eq(plain.selectedStrip, false); T.eq(plain.nativeScroll, false)
  T.eq(plain.rows[1].selBar:GetWidth(), 2, "v2 selection bar")
  local z = UI.List(UIParent, { columns = cols, height = 240, zebra = true })
  T.eq(z.separators, true, "separators default on with zebra")
  T.eq(UI.List(UIParent, { columns = cols, zebra = true, separators = false }).separators, false)
  T.eq(#UI.SiteTokens.listSep, 4); T.near(UI.SiteTokens.listSep[4], 0.55, 1e-6)
  T.near(UI.SiteTokens.listSep[1], 0x4a / 255, 1e-6)
  local s = UI.List(UIParent, { columns = cols, height = 240, rowHeight = 24, headerHeight = 22, iconSize = 18,
    selectable = true, selectedStrip = true, separators = true, nativeScrollbar = true })
  s:SetData(rows)
  T.eq(s.selectedStrip, 3); T.eq(s.rows[1].selBar:GetWidth(), 3)
  T.eq(s.rows[1].cells[2]:GetWidth(), 18, "18 px row icons")
  T.eq(s.body._points[1][5], -22, "22 px header")
  s.rows[2]:Click(); T.eq(s:GetSelected(), 2); T.eq(s.rows[2].selBar:IsShown(), true)
  -- native slider stands in for the rail
  T.eq(s.nativeScroll, true); T.eq(s.rail:IsShown(), false)
  T.eq(s.scrollbar.template, "UIPanelScrollBarTemplate")
  T.eq(s.scrollbar.needed, true)
  local bar = s.scrollbar.bar
  bar._scripts.OnValueChanged(bar, 7)
  T.eq(s:GetOffset(), 7, "slider drives the list")
  s:SetOffset(3); T.eq(bar:GetValue(), 3, "list drives the slider")
  bar._scripts.OnMouseWheel(bar, -1); T.eq(s:GetOffset(), 6)
  s:SetData({ rows[1] }); T.eq(s.scrollbar.needed, false); T.eq(bar:IsShown(), false)
  -- no scroll bar template: the rail stays
  local r
  withTemplates({ UIPanelScrollBarTemplate = true, UIPanelScrollBarTemplateLightBorder = true }, function()
    r = UI.List(UIParent, { columns = cols, height = 240, nativeScrollbar = true })
  end)
  r:SetData(rows)
  T.eq(r.nativeScroll, false); T.eq(r.scrollbar, nil); T.eq(r.rail.needed, true)
  T.noErrors()
end)

T.test("StatRows v3: fixed right-aligned value column, focal gold", function()
  local sr = UI.StatRows(UIParent, { valueWidth = 90, rowHeight = 22 })
  sr:SetSize(400, 300)
  sr:SetSections({ { title = "S", rows = { { label = "Net", value = "+1g 00s 00c", color = "focal" }, { label = "Plain", value = "3" } } } })
  T.eq(sr.valueWidth, 90)
  local valueRow
  for _, row in ipairs(sr.rows) do if row.entry and row.entry.label == "Net" then valueRow = row end end
  T.ok(valueRow, "row bound")
  T.eq(valueRow.value:GetWidth(), 90)
  T.eq(valueRow.value._points[1][1], "RIGHT")
  local legacy = UI.StatRows(UIParent, {})
  T.eq(legacy.valueWidth, false, "38% column unless asked")
  T.noErrors()
end)

T.test("/mkchrome v3: best chrome, parchment + summary, money normalised, honest footers", function()
  local shell = UI.ChromeDemo()
  T.eq(shell.chromeKind, "portrait", "v5: the demo defaults to portrait even with the dialog border")
  T.eq(UI.ChromeDemoBestChrome(), "dialog", "stub has the dialog border")
  T.eq(shell.sidebarMaterial, "parchment")
  T.eq(shell.footer.kind, "dark", "v7: the demo footer is a dark plate (footerVariant = \"dark\")")
  shell:Select("bloodsports", "ring")
  local sm = shell.tabById.bloodsports.summaryUI
  T.eq(shell.tabById.bloodsports.summaryShown, #UI.ChromeDemoSummary.bloodsports)
  T.eq(sm.rows[1].label:GetText(), "Record")
  -- every money string is the compact demo money (v6: g / ss, copper dropped when 0)
  -- v7: trailing zero units dropped too ("412g", "50s", "+361g 85s")
  local function isMoney(v)
    if type(v) ~= "string" then return false end
    v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return v:match("^[+-]?%d+g %d%ds$") ~= nil or v:match("^[+-]?%d+g$") ~= nil or v:match("^[+-]?%d+s$") ~= nil
  end
  local data = shell.demoData
  for _, sec in ipairs(data.season) do
    if sec.title == "Purse" then
      for _, r in ipairs(sec.rows) do T.ok(isMoney(r.value), "purse value normalised: " .. tostring(r.value)) end
    end
  end
  T.eq(data.season[2].rows[5].value, "+361g 85s")
  for _, d in ipairs(data.duels) do T.ok(isMoney(d.purse), "duel purse normalised: " .. tostring(d.purse)) end
  T.ok(isMoney(UI.ChromeDemoSummary.bloodsports[5][2]))
  for _, sec in ipairs(data.pace) do
    for _, r in ipairs(sec.rows) do if r.label == "Gold per hour" then T.ok(isMoney(r.value)); T.ok(isMoney(r.sub:gsub("^median ", ""))) end end
  end
  -- footers: the row count equals the rows on screen, or says how many show and to scroll
  for id in pairs({ ring = 1, clubs = 1, duels = 1, combat = 1 }) do
    local tabId = id == "combat" and "elders" or "bloodsports"
    shell:Select(tabId, id)
    local list, pg = shell.demoLists[id], shell.demoPages[id]
    local n, vis = #list:GetData(), list:VisibleCount()
    local txt = pg.foot:GetText()
    if n > vis then
      T.eq(txt, string.format("%d rows - %d shown, scroll for more", n, vis), id)
    else
      T.eq(txt, string.format("%d rows - updated just now", n), id)
    end
    T.eq(list.selectedStrip, 3); T.eq(list.separators, true)
  end
  T.eq(UI.ChromeDemoFooter(18, "rows", 18), "18 rows - updated just now")
  T.eq(UI.ChromeDemoFooter(18, "rows", 16), "18 rows - 16 shown, scroll for more")
  -- stat pages use the fixed value column (v6: 110 px) and one focal value
  for id, stats in pairs(shell.demoStatPages) do
    T.eq(stats.valueWidth, 110, id)
    local focal = 0
    for _, item in ipairs(stats.items) do if item.row and item.row.color == "focal" then focal = focal + 1 end end
    T.ok(focal >= 1, id .. " has a focal value")
  end
  -- other chrome kinds open as separate windows and hide the rest
  local flat = UI.ChromeDemo("flat buttons")
  T.ok(flat ~= shell); T.eq(flat.chromeKind, "flat"); T.eq(flat.footerNative, true)
  T.eq(shell:IsShown(), false); T.eq(flat:IsShown(), true)
  T.eq(UI.ChromeDemo("flat buttons"), flat, "reused per key")
  local po = UI.ChromeDemo("portrait")
  T.eq(po.chromeKind, "portrait"); T.eq(flat:IsShown(), false)
  T.eq(UI.ChromeDemo(), shell); T.eq(po:IsShown(), false)
  -- best chrome without the dialog border is portrait
  withMissingTextures({ [UI.ShellTextures.dialogBorder] = true }, function()
    T.eq(UI.ChromeDemoBestChrome(), "portrait")
  end)
  T.noErrors()
end)

-- v4 ----------------------------------------------------------------------------------------------------------------

local function hexc(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
local function sameColor(got, want, msg)
  T.ok(got and got[1], (msg or "") .. ": colour set")
  for i = 1, 3 do T.near(got[i], want[i], 1e-6, msg) end
end

T.test("Shell v4: parchment sidebar text is dark ink; flat keeps light text", function()
  local ink = UI.SiteTokens.sidebarInk
  sameColor(ink.label, hexc("21150d"), "label"); sameColor(ink.labelSoft, hexc("3a2810"), "labelSoft")
  sameColor(ink.summaryLabel, hexc("21150d"), "summaryLabel (v7)"); sameColor(ink.value, hexc("21150d"), "value")
  sameColor(ink.good, hexc("14550c"), "good (v6)"); sameColor(ink.bad, hexc("8c1d10"), "bad")
  for key, c in pairs(ink) do
    if key ~= "rule" then T.eq(c[4], 1, key .. " full alpha") end
    T.ok(c[1] + c[2] + c[3] < 0.9, key .. " is dark ink")
  end
  local s
  recordingFonts(function()
    s = UI.Shell({ name = "TestShellV4Ink", sidebar = "parchment", footerText = "Sync now",
      summary = { { "Record", "41-17" }, { "Win rate", "70.7%", "good" }, { "Losses", "17", "bad" }, { "Net", "+1g", "gold" } } })
    s:AddTab({ id = "t", label = "T" })
    s:AddSection({ tab = "t", id = "a", label = "A", order = 1, build = function(p) return CreateFrame("Frame", nil, p) end })
    s:AddSection({ tab = "t", id = "b", label = "B", order = 2, build = function(p) return CreateFrame("Frame", nil, p) end })
    s:Toggle("t")
  end)
  T.eq(s.sidebarMaterial, "parchment"); T.ok(s.ink, "ink selected on parchment")
  T.eq(s.ink.labelSoft, ink.labelSoft)
  local tab = s.tabById.t
  T.eq(tab.rows[1].ink, s.ink)
  sameColor({ tab.rows[1].label:GetTextColor() }, ink.selected, "selected row")
  sameColor({ tab.rows[2].label:GetTextColor() }, ink.labelSoft, "unselected row")
  local sm = tab.summaryUI
  for i = 1, 4 do sameColor({ sm.rows[i].label:GetTextColor() }, ink.summaryLabel, "summary label " .. i) end
  sameColor({ sm.rows[1].value:GetTextColor() }, ink.value, "plain value")
  sameColor({ sm.rows[2].value:GetTextColor() }, ink.good, "good value")
  sameColor({ sm.rows[3].value:GetTextColor() }, ink.bad, "bad value")
  sameColor({ sm.rows[4].value:GetTextColor() }, ink.focal, "focal value")
  T.eq(sm.rows[1].label:GetShadowOffset(), 0, "no shadow on parchment")
  -- o.sidebarInk overrides single keys
  local o = UI.Shell({ name = "TestShellV4InkOverride", sidebar = "parchment", sidebarInk = { labelSoft = { 0, 0, 0, 1 }, bad = "x" } })
  T.eq(o.ink.labelSoft[1], 0); T.eq(o.ink.bad, ink.bad, "non-table override ignored")
  -- flat sidebar: no ink, light text as before
  local f
  recordingFonts(function()
    f = UI.Shell({ name = "TestShellV4Flat", sidebar = "flat", summary = { { "Record", "1-0" } } })
    f:AddTab({ id = "t", label = "T" })
    f:AddSection({ tab = "t", id = "a", label = "A", build = function(p) return CreateFrame("Frame", nil, p) end })
    f:AddSection({ tab = "t", id = "b", label = "B", order = 2, build = function(p) return CreateFrame("Frame", nil, p) end })
    f:Toggle("t")
  end)
  T.eq(f.ink, nil); T.eq(f.tabById.t.rows[1].ink, false)
  sameColor({ f.tabById.t.rows[2].label:GetTextColor() }, UI.SiteTokens.parch, "flat unselected stays light")
  sameColor({ f.tabById.t.summaryUI.rows[1].value:GetTextColor() }, UI.SiteTokens.parch, "flat value stays light")
  -- v3 callers passing `true` to the nav row still get ink
  T.ok(UI.ShellNavRow(UIParent, true).ink.labelSoft, "boolean ink upgraded")
  T.noErrors()
end)

T.test("Shell v4: summary anchors to the sidebar bottom and drops lines from the top", function()
  local m = UI.ShellMetrics
  local lines = { { "Record", "41-17" }, { "Win rate", "70.7%" }, { "Streak", "W5" }, { "Best streak", "9" }, { "Net", "+1g" } }
  local s = UI.Shell({ name = "TestShellV4Bottom", sidebar = "parchment", footerText = "Sync now", summary = lines })
  s:AddTab({ id = "t", label = "T" })
  for i = 1, 5 do
    s:AddSection({ tab = "t", id = "s" .. i, label = "S" .. i, order = i, build = function(p) return CreateFrame("Frame", nil, p) end })
  end
  s.sidebar:SetHeight(500)
  s:Toggle("t")
  local tab, sm = s.tabById.t, s.tabById.t.summaryUI
  local bo = s:SummaryBottomOffset()
  T.eq(bo, 8 + 26 + 8 + 1 + m.summaryGap, "8 px above the footer rule")
  T.eq(tab.summaryShown, 5, "all 5 fit at 500 px")
  -- the last line sits on the block bottom, each line above it one summaryLine higher; rule 8 px over the first
  local last = sm.rows[5].label._points[1]
  T.eq(last[1], "BOTTOMLEFT"); T.eq(last[5], bo)
  T.eq(sm.rows[1].label._points[1][5], bo + 4 * m.summaryLine)
  T.eq(sm.rule._points[1][5], bo + 5 * m.summaryLine + 8)
  T.eq(sm.rule:IsShown(), true)
  local sectionsEnd = 32 + 5 * 26
  T.eq(tab.summaryTop, 500 - (bo + 5 * 16 + 8) - 1)
  T.ok(tab.summaryTop > sectionsEnd + 12, "void sits between sections and summary, not under it")
  -- shrink: lines drop from the TOP, the bottom line stays put, never over the sections
  local h = sectionsEnd + 12 + 9 + 2 * 16 + bo + 3
  s.sidebar:SetHeight(h)
  s:Refresh()
  T.eq(tab.summaryShown, 2); T.eq(tab.summaryFirst, 4)
  T.eq(sm.rows[1].label:IsShown(), false); T.eq(sm.rows[3].label:IsShown(), false)
  T.eq(sm.rows[4].label:IsShown(), true); T.eq(sm.rows[5].label:IsShown(), true)
  T.eq(sm.rows[5].label._points[1][5], bo, "bottom line unmoved")
  T.ok(tab.summaryTop >= sectionsEnd + 12, "no overlap with the sections")
  -- no room at all: block hidden, rule too
  s.sidebar:SetHeight(sectionsEnd + bo + 10)
  s:Refresh()
  T.eq(tab.summaryShown, 0); T.eq(sm.rule:IsShown(), false)
  -- no footer: the block sits SIDE_PAD (8) above the sidebar edge
  local nf = UI.Shell({ name = "TestShellV4NoFoot", sidebar = "parchment", summary = lines })
  T.eq(nf:SummaryBottomOffset(), 8)
  -- the chrome demo keeps 5 bloodsports summary lines
  T.eq(#UI.ChromeDemoSummary.bloodsports, 5)
  T.noErrors()
end)

T.test("Shell v4: drop shadow under dialog / flat chrome, skipped safely; brighter band, 24 px brackets", function()
  local m = UI.ShellMetrics
  for _, kind in ipairs({ "dialog", "flat" }) do
    local s = UI.Shell({ name = "TestShellV4Shadow" .. kind, chrome = kind })
    local sh = s.shadow
    T.ok(sh, kind .. " has a shadow")
    T.eq(sh:GetParent(), s.frame, "on the window itself, under every child frame")
    T.eq(sh._points[1][1], "TOPLEFT"); T.eq(sh._points[1][4], -m.shadowGrow); T.eq(sh._points[1][5], m.shadowGrow - m.shadowDrop)
    T.eq(sh._points[2][1], "BOTTOMRIGHT"); T.eq(sh._points[2][4], m.shadowGrow); T.eq(sh._points[2][5], -m.shadowGrow - m.shadowDrop)
    T.eq(sh.mkShadow.alpha, 0.45); T.eq(sh:GetTexture(), "Interface\\Buttons\\WHITE8X8")
    T.eq(#s.depth.brackets, 4, kind .. " brackets")
    T.eq(s.depth.brackets[1].h:GetWidth(), 24); T.eq(s.depth.brackets[1].v:GetHeight(), 24)
  end
  -- dialog border: brackets sit inside the metal (band px in)
  local d = UI.Shell({ name = "TestShellV4Brackets", chrome = "dialog" })
  T.eq(d.depth.dialogBorder, true); T.eq(d.depth.brackets[1].h._points[1][4], m.band)
  T.near(UI.ShellDialogTint[1], 0.85, 1e-6); T.near(UI.ShellDialogTint[2], 0.68, 1e-6); T.near(UI.ShellDialogTint[3], 0.38, 1e-6)
  -- v5: portrait casts the shadow too; the default (v2) chrome still does not
  local ps = UI.Shell({ name = "TestShellV4NoShadowP", chrome = "portrait" }).shadow
  T.ok(ps, "portrait has a shadow"); T.eq(ps.mkShadow.alpha, 0.45)
  T.eq(UI.Shell({ name = "TestShellV4NoShadowN" }).shadow, nil)
  saved = m.shadowGrow
  m.shadowGrow = "broken"
  local okP, sp = pcall(UI.Shell, { name = "TestShellV5ShadowBadP", chrome = "portrait" })
  m.shadowGrow = saved
  T.ok(okP, tostring(sp)); T.eq(sp.shadow, nil, "portrait skips a failing shadow too")
  -- a failing call skips the shadow, the window still builds
  local saved
  saved = m.shadowGrow
  m.shadowGrow = "broken"
  local ok, s = pcall(UI.Shell, { name = "TestShellV4ShadowBad", chrome = "dialog" })
  m.shadowGrow = saved
  T.ok(ok, tostring(s)); T.eq(s.shadow, nil); T.ok(s.depth.well, "rest of the chrome intact")
  T.eq(UI.ShellBuildShadow({ CreateTexture = function() error("no textures") end }), nil, "CreateTexture raising")
  T.noErrors()
end)

T.test("List v4: proportional thumb, full-height track, resize / scroll updates, VisibleCount", function()
  local m = UI.ShellMetrics
  T.near(UI.ScrollThumbSize(300, 14, 18, 24), 300 * 14 / 18, 1e-9)
  T.eq(UI.ScrollThumbSize(300, 1, 500, 24), 24, "never under the minimum")
  T.eq(UI.ScrollThumbSize(100, 20, 10, 24), 100, "never over the track")
  T.eq(UI.ScrollThumbSize(0, 5, 10, 24), 0); T.eq(UI.ScrollThumbSize(20, 1, 100, 24), 20, "short track caps the minimum")
  local cols = { { key = "name", title = "Name" } }
  local rows = {}
  for i = 1, 18 do rows[i] = { name = "r" .. i } end
  -- 13 full rows + 14 px of a 14th: v10 snaps to full rows, the partial 14th is hidden (not drawn half)
  local l = UI.List(UIParent, { columns = cols, rowHeight = 24, headerHeight = 22, thumbScrollbar = true })
  l:SetSize(400, 22 + 13 * 24 + 14)
  l:SetData(rows)
  T.eq(l.thumbScroll, true); T.eq(l.nativeScroll, false)
  local rail = l.rail
  T.eq(rail:GetWidth(), m.thumbTrack); T.eq(rail.minThumb, m.thumbMin)
  T.eq(rail._points[1][5], -22, "track starts at the header bottom"); T.eq(rail._points[2][5], 0, "and runs to the bottom")
  T.eq(l.body._points[2][4], -(m.thumbTrack + 2 + 2), "body leaves room for the track")
  T.eq(l:VisibleRows(), 13); T.eq(l:VisibleCount(), 13, "v10: only the 13 full rows count")
  T.ok(l:GetPoolSize() > 14, "pool has a spare row that is not counted")
  -- stub frames report no anchored height: give the track one and check the thumb math
  rail.track:SetHeight(300)
  l:Refresh()
  T.near(rail.thumb:GetHeight(), 300 * 13 / 18, 1e-9)
  l:SetOffset(l:MaxOffset())
  T.eq(l:GetOffset(), 5)
  T.near(rail.thumb._points[1][5], -(300 - 300 * 13 / 18), 1e-9, "thumb at the bottom")
  T.eq(l:VisibleCount(), 13, "at the end only 13 data rows remain")
  -- resize: the track shrinks, the thumb follows (rail OnSizeChanged)
  rail.track:SetHeight(150)
  rail._scripts.OnSizeChanged(rail)
  T.near(rail.thumb:GetHeight(), 150 * 13 / 18, 1e-9)
  -- fewer rows than space: everything shows, no rail
  l:SetData({ rows[1], rows[2], rows[3] })
  T.eq(l:VisibleCount(), 3); T.eq(rail:IsShown(), false)
  -- onRefresh fires on every Refresh; an erroring one is kept, not fatal
  local calls = 0
  local cb = UI.List(UIParent, { columns = cols, thumbScrollbar = true, onRefresh = function() calls = calls + 1 end })
  local base = calls
  cb:SetData(rows); cb:SetOffset(3)
  T.eq(calls, base + 2)
  local bad = UI.List(UIParent, { columns = cols, onRefresh = function() error("cb down") end })
  bad:SetData(rows)
  T.ok(tostring(bad.lastError):find("cb down"))
  -- nativeScrollbar with no template: the proportional thumb, not the old 6 px rail
  local r
  withTemplates({ UIPanelScrollBarTemplate = true, UIPanelScrollBarTemplateLightBorder = true }, function()
    r = UI.List(UIParent, { columns = cols, nativeScrollbar = true })
  end)
  T.eq(r.thumbScroll, true); T.eq(r.rail:GetWidth(), m.thumbTrack)
  -- a working native slider still wins; the default list keeps the v2 rail
  local n = UI.List(UIParent, { columns = cols, nativeScrollbar = true, thumbScrollbar = true })
  T.eq(n.nativeScroll, true); T.eq(n.thumbScroll, false)
  local v2 = UI.List(UIParent, { columns = cols })
  T.eq(v2.thumbScroll, false); T.eq(v2.rail:GetWidth(), UI.RailWidth); T.eq(v2.rail.minThumb, 18)
  T.noErrors()
end)

T.test("/mkchrome v4: 960 x 640 (v9), thumb lists, footer = VisibleCount and follows scrolling", function()
  local shell = UI.ChromeDemo()
  T.eq(shell.frame:GetWidth(), 960); T.eq(shell.frame:GetHeight(), 640)
  -- other callers keep the 900 x 600 default and compact 820 x 520
  T.eq(UI.Shell({ name = "TestShellV4Default" }).frame:GetWidth(), 900)
  local c = UI.Shell({ name = "TestShellV4Compact", compact = true })
  T.eq(c.frame:GetWidth(), 820); T.eq(c.frame:GetHeight(), 520)
  shell:Select("bloodsports", "ring")
  local list, pg = shell.demoLists.ring, shell.demoPages.ring
  T.eq(list.thumbScroll, true); T.eq(list.nativeScroll, false)
  local n = #list:GetData()
  T.eq(pg.foot:GetText(), string.format("%d rows - %d shown, scroll for more", n, list:VisibleCount()))
  list:SetOffset(list:MaxOffset())
  T.eq(pg.foot:GetText(), string.format("%d rows - %d shown, scroll for more", n, list:VisibleCount()), "follows scroll")
  list:SetOffset(0)
  T.noErrors()
end)

-- v5 ----------------------------------------------------------------------------------------------------------------

-- Ink regression: the colour a sidebar row's label ENDS with after Select + hover in / out (+ a refresh) on parchment
-- must be the fixed ink, never the plate default (light gold) nor the it4 labelSoft (4a3418, which the it4 crop showed
-- blending to light taupe). The stub records every SetTextColor; the last call wins, as in the client.
T.test("Shell v5: final sidebar label colours after Select + hover-out on parchment are the fixed ink", function()
  local want = { unselected = hexc("3a2810"), selected = hexc("0e0904"), summaryLabel = hexc("21150d"), -- v7
    value = hexc("21150d"), good = hexc("14550c"), bad = hexc("8c1d10"), heading = hexc("6e130c") }
  local s
  recordingFonts(function()
    s = UI.Shell({ name = "TestShellV5Ink", sidebar = "parchment", chrome = "portrait", footerText = "Sync now",
      summary = { { "Record", "41-17" }, { "Win rate", "70.7%", "good" }, { "Losses", "17", "bad" } } })
    s:AddTab({ id = "t", label = "Bloodsports" })
    for i, id in ipairs({ "ring", "stats", "clubs", "finder", "duels" }) do
      s:AddSection({ tab = "t", id = id, label = id, order = i, build = function(p) return CreateFrame("Frame", nil, p) end })
    end
    s:Toggle("t")
    s:Select("t", "clubs")
    -- hover every row in and out (the it4 hypothesis: a hover / refresh repaint overwriting the ink)
    for _, row in ipairs(s.tabById.t.rows) do
      T.ok(row._scripts.OnEnter and row._scripts.OnLeave, "row repaints on hover")
      row._scripts.OnEnter(row); row._scripts.OnLeave(row)
    end
  end)
  local tab = s.tabById.t
  local plateDark = UI.SiteTokens.plateDarkLabel
  -- straight after hover-out (no refresh to mask an overwrite), then again after a refresh
  local afterHover = {}
  for i, row in ipairs(tab.rows) do afterHover[i] = { row.label:GetTextColor() } end
  s:Refresh()
  for i, row in ipairs(tab.rows) do
    sameColor(afterHover[i], row.sectionId == "clubs" and want.selected or want.unselected, "row " .. i .. " after hover-out")
  end
  for i, row in ipairs(tab.rows) do
    local got = { row.label:GetTextColor() }
    local exp = row.sectionId == "clubs" and want.selected or want.unselected
    sameColor(got, exp, "row " .. i .. " final colour")
    T.ok(math.abs(got[1] - plateDark[1]) > 0.5, "row " .. i .. " is not the plate's light label")
    T.ok(math.abs(got[1] - 0x4a / 255) > 1e-3, "row " .. i .. " is not the it4 labelSoft")
    T.eq(got[4], 1, "full alpha")
  end
  local sm = tab.summaryUI
  for i = 1, 3 do sameColor({ sm.rows[i].label:GetTextColor() }, want.summaryLabel, "summary label " .. i) end
  sameColor({ sm.rows[1].value:GetTextColor() }, want.value, "summary value")
  sameColor({ sm.rows[2].value:GetTextColor() }, want.good, "summary good")
  sameColor({ sm.rows[3].value:GetTextColor() }, want.bad, "summary bad")
  sameColor({ tab.heading:GetTextColor() }, want.heading, "heading ink-red")
  -- the parchment is lighter than it4 (0.82) so the ink has a ground to read on; v9 settles it at 0.87 (it8: 0.92
  -- read brighter than the main pane)
  T.ok(UI.SiteTokens.parchTint[1] > 0.82, "parchment tint lifted over it4")
  T.noErrors()
end)

T.test("Shell v5: sidebarExtra fills the gap between sections and the bottom summary", function()
  local lines = { { "Record", "41-17" }, { "Win rate", "70.7%" }, { "Streak", "W5" } }
  local calls, got = 0, {}
  local s = UI.Shell({ name = "TestShellV5Extra", sidebar = "parchment", footerText = "Sync now", summary = lines,
    sidebarExtra = function(parent, shell, tabId)
      calls = calls + 1
      got.parent, got.shell, got.tab = parent, shell, tabId
      local f = CreateFrame("Frame", nil, parent)
      f.minHeight = 60
      f.SetAllPoints = function(self, rel) self._filled = rel end -- the stub's SetAllPoints records nothing
      return f
    end })
  s:AddTab({ id = "t", label = "T" })
  for i = 1, 5 do
    s:AddSection({ tab = "t", id = "s" .. i, label = "S" .. i, order = i, build = function(p) return CreateFrame("Frame", nil, p) end })
  end
  s.sidebar:SetHeight(500)
  s:Toggle("t")
  s:Refresh(); s:Refresh()
  local tab = s.tabById.t
  T.eq(calls, 1, "built once per tab"); T.eq(got.shell, s); T.eq(got.tab, "t"); T.eq(got.parent, tab.extraHost)
  local host = tab.extraHost
  local top = 32 + 5 * 26 + 12
  T.eq(host._points[1][1], "TOPLEFT"); T.eq(host._points[1][5], -top, "12 px under the last row")
  T.eq(host._points[2][1], "BOTTOMRIGHT")
  T.eq(host._points[2][5], tab.summaryRuleY + 1 + 8, "8 px over the summary rule")
  T.eq(tab.summaryRuleY, s:SummaryBottomOffset() + 3 * 16 + 8)
  T.eq(host:IsShown(), true)
  T.eq(tab.extraAvail, 500 - top - (tab.summaryRuleY + 9))
  T.eq(tab.extraFrame._filled, host, "an unanchored frame fills the host")
  -- summary unmoved: still bottom-anchored
  T.eq(tab.summaryUI.rows[3].label._points[1][5], s:SummaryBottomOffset())
  -- too short for frame.minHeight: hidden, never over the summary
  s.sidebar:SetHeight(top + tab.summaryRuleY + 9 + 59)
  s:Refresh()
  T.eq(host:IsShown(), false)
  -- per-tab override wins; an erroring builder is kept, the shell still works
  local ok2
  s:AddTab({ id = "u", label = "U", extra = function() ok2 = true; error("extra down") end })
  s:AddSection({ tab = "u", id = "a", label = "A", build = function(p) return CreateFrame("Frame", nil, p) end })
  s:Select("u")
  T.ok(ok2); T.ok(tostring(s.tabById.u.extraError):find("extra down")); T.eq(s.tabById.u.extraHost:IsShown(), false)
  T.ok(tostring(s.lastError):find("extra down"))
  -- no extra: nothing built
  local n = UI.Shell({ name = "TestShellV5NoExtra", sidebar = "parchment" })
  n:AddTab({ id = "t", label = "T" }); n:Toggle("t")
  T.eq(n.tabById.t.extraHost, nil)
  T.noErrors()
end)

T.test("/mkchrome v5: portrait default, RECENT mini-list per tab in ink, 960 wide kept", function()
  local shell = UI.ChromeDemo()
  T.eq(shell.chromeKind, "portrait"); T.ok(shell.shadow, "portrait shadow")
  T.eq(shell.frame:GetWidth(), 960); T.eq(shell.frame:GetHeight(), 640)
  T.eq(UI.ShellMetrics.tab, 28); T.eq(UI.ShellMetrics.tabInactive, 24)
  T.eq(UI.ChromeDemo("dialog").chromeKind, "dialog", "dialog stays opt-in")
  shell = UI.ChromeDemo()
  local ink = shell.ink
  for _, tabId in ipairs({ "bloodsports", "elders" }) do
    shell:Select(tabId)
    local tab = shell.tabById[tabId]
    local f = tab.extraFrame
    T.ok(f and f.rows, tabId .. " has a RECENT block")
    T.eq(f.head:GetText(), "RECENT")
    T.eq(#f.rows, 5, tabId .. " five rows")
    T.eq(f.minHeight, 22 + 4 + 5 * 18)
    T.eq(tab.extraError, nil)
  end
  local rows = shell.tabById.bloodsports.extraFrame.rows
  T.eq(rows[1].left:GetText(), "Thornwick"); T.eq(rows[1].result:GetText(), "W"); T.eq(rows[1].right:GetText(), "+18g 50s")
  T.eq(rows[2].result:GetText(), "L"); T.eq(rows[2].right:GetText(), "-12g") -- v7
  T.eq(UI.ChromeDemoRecent.bloodsports[2][3], "bad"); T.eq(UI.ChromeDemoRecent.bloodsports[1][3], "good")
  T.ok(ink and ink.heading, "parchment ink in the demo")
  T.noErrors()
end)

T.test("/mkchrome v5: RECENT rows record ink colours (W green, L red, names ink)", function()
  local f
  recordingFonts(function()
    local s = UI.Shell({ name = "TestShellV5RecentInk", sidebar = "parchment" })
    s:AddTab({ id = "bloodsports", label = "B", extra = UI.ChromeDemoRecentExtra("bloodsports") })
    s:Toggle("bloodsports")
    f = s.tabById.bloodsports.extraFrame
  end)
  local ink = UI.SiteTokens.sidebarInk
  sameColor({ f.head:GetTextColor() }, ink.label, "RECENT heading ink")
  sameColor({ f.rows[1].left:GetTextColor() }, ink.label, "opponent ink")
  sameColor({ f.rows[1].result:GetTextColor() }, ink.good, "W good")
  sameColor({ f.rows[2].result:GetTextColor() }, ink.bad, "L bad")
  sameColor({ f.rows[2].right:GetTextColor() }, ink.bad, "lost purse bad")
  T.noErrors()
end)

-- v6 ----------------------------------------------------------------------------------------------------------------

T.test("Shell v6: parchment summary records final dark ink (labels, values, good, bad, money)", function()
  local want = { label = hexc("21150d"), value = hexc("21150d"), good = hexc("14550c"), bad = hexc("8c1d10") } -- v7 label
  local s
  recordingFonts(function()
    s = UI.Shell({ name = "TestShellV6SummaryInk", sidebar = "parchment", chrome = "portrait", footerText = "Sync now",
      summary = function(_, tabId) return UI.ChromeDemoSummary[tabId] end })
    s:AddTab({ id = "bloodsports", label = "Bloodsports", extra = UI.ChromeDemoRecentExtra("bloodsports") })
    s:AddTab({ id = "elders", label = "Elders", extra = UI.ChromeDemoRecentExtra("elders") })
    for _, t in ipairs({ "bloodsports", "elders" }) do
      for i = 1, 3 do
        s:AddSection({ tab = t, id = t .. i, label = "S" .. i, order = i, build = function(p) return CreateFrame("Frame", nil, p) end })
      end
    end
    s:Toggle("bloodsports")
    s:Select("elders"); s:Select("bloodsports") -- repaint after a tab round trip: the final colour is what counts
  end)
  local sm, lines = s.tabById.bloodsports.summaryUI, UI.ChromeDemoSummary.bloodsports
  for i, line in ipairs(lines) do
    local got = { sm.rows[i].label:GetTextColor() }
    sameColor(got, want.label, "summary label " .. line[1])
    T.eq(got[4], 1, "full alpha")
    local exp = line[3] == "good" and want.good or line[3] == "bad" and want.bad or want.value -- "gold" = value ink
    sameColor({ sm.rows[i].value:GetTextColor() }, exp, "summary value " .. line[1])
  end
  T.eq(lines[5][1], "Net purse"); T.eq(lines[5][2], "+361g 85s")
  sameColor({ sm.rows[5].value:GetTextColor() }, want.value, "Net purse money in value ink, not pale gold")
  -- elders summary too (Level is the "gold" line)
  local esm = s.tabById.elders.summaryUI
  for i = 1, #UI.ChromeDemoSummary.elders do sameColor({ esm.rows[i].label:GetTextColor() }, want.label, "elders label " .. i) end
  sameColor({ esm.rows[1].value:GetTextColor() }, want.value, "elders gold line")
  -- RECENT W / L on parchment: the darker semantic ink
  local f = s.tabById.bloodsports.extraFrame
  sameColor({ f.rows[1].result:GetTextColor() }, want.good, "W darker green")
  sameColor({ f.rows[2].result:GetTextColor() }, want.bad, "L dark red")
  -- the dark pane keeps the bright semantic colours
  local flat
  recordingFonts(function()
    flat = UI.Shell({ name = "TestShellV6FlatSummary", sidebar = "flat", summary = { { "W", "1", "good" }, { "L", "2", "bad" } } })
    flat:AddTab({ id = "t", label = "T", extra = UI.ChromeDemoRecentExtra("bloodsports") }); flat:Toggle("t")
  end)
  sameColor({ flat.tabById.t.summaryUI.rows[1].value:GetTextColor() }, UI.SiteTokens.emerald, "flat good stays bright")
  sameColor({ flat.tabById.t.summaryUI.rows[2].value:GetTextColor() }, UI.Tokens.bad, "flat bad stays bright")
  sameColor({ flat.tabById.t.extraFrame.rows[1].result:GetTextColor() }, UI.SiteTokens.emerald, "flat RECENT W bright")
  T.noErrors()
end)

T.test("/mkchrome v6: compact money (no copper when 0), every purse / treasury <= 12 chars, wider columns", function()
  local money = UI.ChromeDemoMoney
  T.eq(money(4123500), "412g 35s"); T.eq(money(1842000, true), "+184g 20s"); T.eq(money(28400000), "2840g")
  T.eq(money(-120000, true), "-12g"); T.eq(money(5000), "50s"); T.eq(money(0), "0s") -- v7: 0s dropped too
  T.eq(money(4120000), "412g"); T.eq(money(3618500, true), "+361g 85s"); T.eq(money(10500), "1g 05s")
  T.eq(money(12345), MK.Util.Money(12345), "non-zero copper keeps the full form")
  T.eq(MK.Util.Money(4123500), "412g 35s 00c", "MK.Util.Money unchanged for other callers")
  local shell = UI.ChromeDemo()
  local function plain(v) return (tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local checked = 0
  local function short(v, what)
    v = plain(v)
    T.ok(#v <= 12, what .. " <= 12 chars: '" .. v .. "' (" .. #v .. ")")
    T.ok(not v:find("%d%dc$"), what .. " has no 00c tail: " .. v)
    checked = checked + 1
  end
  -- list cells: the money columns run through the column format, exactly as the List binds them
  for _, id in ipairs({ "ring", "clubs", "duels" }) do
    shell:Select("bloodsports", id)
    local list = shell.demoLists[id]
    local col
    for _, c in ipairs(list.columns or {}) do if c.title == "Purse" or c.title == "Treasury" then col = c end end
    T.ok(col, id .. " money column")
    for _, row in ipairs(list:GetData()) do
      local v = col.format and col.format(row) or row[col.key]
      short(v, id .. " " .. tostring(row.name))
    end
    -- the bound cell text is the short string too
    local cell = list.rows[1].cells[#list.rows[1].cells]
    short(cell:GetText(), id .. " bound cell")
    if id == "clubs" then T.eq(col.width, 120, "Treasury +24 px") end
  end
  T.eq(UI.ChromeDemoData().clubs[1].copper, 28400000, "data stays numeric copper")
  for _, sec in ipairs(shell.demoData.season) do
    if sec.title == "Purse" then for _, r in ipairs(sec.rows) do short(r.value, "season " .. r.label) end end
  end
  for _, r in ipairs(UI.ChromeDemoRecent.bloodsports) do short(r[4], "recent " .. r[1]) end
  short(UI.ChromeDemoSummary.bloodsports[5][2], "Net purse")
  T.eq(shell.demoData.overview[1].rows[3].value, "+184g 20s")
  T.ok(checked >= 18 + 14 + 16, "every ring / club / duel row checked (" .. checked .. ")")
  T.noErrors()
end)

T.test("StatRows v6: o.rowHeight option (default unchanged); demo stat pages 28 px rows, two sections", function()
  T.eq(UI.StatRows(UIParent, {}).rowHeight, UI.Metrics.row, "default unchanged")
  local sr = UI.StatRows(UIParent, { rowHeight = 28 })
  sr:SetSize(400, 600)
  sr:SetSections({ { title = "A", rows = { { label = "x", value = "1" }, { label = "y", value = "2", sub = "s" } } } })
  T.eq(sr.rowHeight, 28)
  T.eq(sr.items[2].h, 28, "plain row 28"); T.eq(sr.items[3].h, 30, "sub row keeps its 30 px minimum")
  T.eq(sr:GetContentHeight(), UI.Metrics.section + UI.Metrics.sectionGap + 28 + 30)
  local shell = UI.ChromeDemo()
  for _, id in ipairs({ "overview", "pace" }) do
    shell:Select("elders", id)
    local stats = shell.demoStatPages[id]
    T.eq(stats.rowHeight, 28, id); T.eq(stats.valueWidth, 110, id)
    local secs = shell.demoData[id]
    T.eq(#secs, 2, id .. " has two sections"); T.eq(secs[2].title, "This week"); T.eq(#secs[2].rows, 4)
  end
  for _, id in ipairs({ "stats", "finder" }) do T.eq(shell.demoStatPages[id] and shell.demoStatPages[id].rowHeight or 28, 28) end
  T.noErrors()
end)

T.test("Shell v6: nav selection strip + darker wash on parchment, on BOTH tabs' sidebars", function()
  local shell = UI.ChromeDemo()
  local ink = shell.ink
  sameColor(ink.strip, hexc("6a4708"), "strip ink")
  T.near(UI.SiteTokens.parchSelWash[4], 0.22, 1e-6)
  for _, case in ipairs({ { "bloodsports", "clubs" }, { "elders", "pace" }, { "elders", "overview" } }) do
    local tabId, secId = case[1], case[2]
    shell:Select(tabId, secId)
    local tab = shell.tabById[tabId]
    T.eq(tab.side:IsShown(), true, tabId .. " sidebar shown")
    local selected = 0
    for _, row in ipairs(tab.rows) do
      local sel = row.sectionId == secId
      T.eq(row.strip:IsShown(), sel, tabId .. "/" .. row.sectionId .. " strip")
      T.eq(row.wash:IsShown(), sel, tabId .. "/" .. row.sectionId .. " wash")
      if sel then
        selected = selected + 1
        T.eq(row.strip:GetWidth(), UI.ShellMetrics.navStrip)
        T.eq(row.stripColor, ink.strip, tabId .. " strip is the parchment strip colour")
        T.near(row.washColor[4], 0.22, 1e-6, tabId .. " darker wash")
        for i = 1, 3 do T.near(row.washColor[i], 0, 1e-6) end
      end
    end
    T.eq(selected, 1, tabId .. " exactly one selected row")
  end
  -- flat sidebars keep the bright gold strip and gold wash
  local fr = UI.ShellNavRow(UIParent, nil)
  T.eq(fr.stripColor, UI.SiteTokens.gold); T.near(fr.washColor[4], 0.12, 1e-6)
  T.noErrors()
end)

-- v7 ----------------------------------------------------------------------------------------------------------------

local function lum(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end

-- it6: summary labels photographed lighter than the green values. The recorder keeps the LAST colour per font string
-- (a font-object change after it would wipe it), read after build + Select + hover + Refresh.
T.test("Shell v7: summary labels record final #21150d at 12 px after build + refresh (own parchment palette)", function()
  local want = { label = hexc("21150d"), value = hexc("21150d"), good = hexc("14550c"), bad = hexc("8c1d10") }
  local s
  recordingFonts(function()
    s = UI.Shell({ name = "TestShellV7Summary", sidebar = "parchment", chrome = "portrait", footerText = "Sync now",
      footerVariant = "dark",
      summary = function(_, tabId) return UI.ChromeDemoSummary[tabId] end })
    s:AddTab({ id = "bloodsports", label = "Bloodsports", extra = UI.ChromeDemoRecentExtra("bloodsports") })
    s:AddTab({ id = "elders", label = "Elders", extra = UI.ChromeDemoRecentExtra("elders") })
    for _, t in ipairs({ "bloodsports", "elders" }) do
      for i = 1, 3 do
        s:AddSection({ tab = t, id = t .. i, label = "S" .. i, order = i, build = function(p) return CreateFrame("Frame", nil, p) end })
      end
    end
    s:Toggle("bloodsports")
    s:Select("elders"); s:Select("bloodsports", "bloodsports2")
    for _, row in ipairs(s.tabById.bloodsports.rows) do row._scripts.OnEnter(row); row._scripts.OnLeave(row) end
    s:Refresh()
  end)
  -- the summary has its own palette, separate from the dark-pane tokens
  T.ok(s.summaryInk, "shell.summaryInk on parchment")
  for key, c in pairs(UI.SiteTokens.summaryInk) do sameColor(s.summaryInk[key], c, "summaryInk." .. key) end
  sameColor(UI.SiteTokens.summaryInk.label, want.label, "token label")
  for _, key in ipairs({ "label", "value", "good", "bad", "focal" }) do
    for _, dark in ipairs({ UI.Tokens.muted, UI.SiteTokens.parch, UI.SiteTokens.emerald, UI.Tokens.bad }) do
      T.ok(math.abs(s.summaryInk[key][1] - dark[1]) + math.abs(s.summaryInk[key][2] - dark[2]) > 0.1,
        key .. " is not a dark-pane token")
    end
  end
  local sm, lines = s.tabById.bloodsports.summaryUI, UI.ChromeDemoSummary.bloodsports
  T.eq(s.tabById.bloodsports.summaryShown, #lines)
  local goodLum
  for i, line in ipairs(lines) do
    local lab, val = sm.rows[i].label, sm.rows[i].value
    local got = { lab:GetTextColor() }
    sameColor(got, want.label, "final label colour " .. line[1])
    T.eq(got[4], 1, line[1] .. " full alpha")
    T.eq(lab:GetFontSize(), 12, line[1] .. " label 12 px"); T.eq(val:GetFontSize(), 12, line[1] .. " value 12 px")
    T.eq(lab.mkSize, 12)
    local exp = line[3] == "good" and want.good or line[3] == "bad" and want.bad or want.value
    local vc = { val:GetTextColor() }
    sameColor(vc, exp, "final value colour " .. line[1])
    if line[3] == "good" then goodLum = lum(vc) end
  end
  T.ok(goodLum, "a good value is in the block")
  -- the it6 symptom, as an invariant: no label is lighter than the green value text
  for i = 1, #lines do T.ok(lum({ sm.rows[i].label:GetTextColor() }) <= goodLum, "label " .. i .. " not lighter than green") end
  -- elders block too, and a text line takes the label ink
  for i = 1, #UI.ChromeDemoSummary.elders do
    sameColor({ s.tabById.elders.summaryUI.rows[i].label:GetTextColor() }, want.label, "elders label " .. i)
  end
  local t
  recordingFonts(function()
    t = UI.Shell({ name = "TestShellV7SummaryText", sidebar = "parchment", summary = { "Just a line", { "A", "1" } },
      sidebarInk = { summaryLabel = { 0, 0, 0, 1 } } })
    t:AddTab({ id = "t", label = "T" }); t:Toggle("t")
  end)
  sameColor({ t.tabById.t.summaryUI.rows[2].label:GetTextColor() }, { 0, 0, 0 }, "o.sidebarInk.summaryLabel still overrides")
  sameColor({ t.tabById.t.summaryUI.rows[2].value:GetTextColor() }, want.value, "value from the summary palette")
  -- flat sidebar: no summary palette, light text as before
  local f = UI.Shell({ name = "TestShellV7Flat", sidebar = "flat" })
  T.eq(f.summaryInk, nil)
  T.noErrors()
end)

T.test("/mkchrome v7: money drops trailing zero units (0c and 0s) everywhere in the demo", function()
  local money = UI.ChromeDemoMoney
  T.eq(money(4120000), "412g"); T.eq(money(5000), "50s"); T.eq(money(3618500, true), "+361g 85s")
  T.eq(money(-120000, true), "-12g"); T.eq(money(28400000), "2840g")
  local shell = UI.ChromeDemo()
  local function plain(v) return (tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local n = 0
  local function check(v, what)
    v = plain(v)
    T.ok(not v:find(" 00s") and not v:find("00c") and not v:find(" 0c"), what .. " has no zero unit: " .. v)
    n = n + 1
  end
  for _, id in ipairs({ "ring", "clubs" }) do
    for _, row in ipairs(shell.demoData[id]) do check(money(row.copper), id .. " " .. row.name) end
  end
  for _, d in ipairs(shell.demoData.duels) do check(d.purse, "duel " .. d.name) end
  for _, r in ipairs(UI.ChromeDemoRecent.bloodsports) do check(r[4], "recent " .. r[1]) end
  T.eq(plain(shell.demoData.clubs[1].copper and money(shell.demoData.clubs[1].copper)), "2840g")
  T.ok(n >= 18 + 14 + 16, "checked " .. n)
  T.noErrors()
end)

T.test("/mkchrome v7: Finder is a duelist LIST (Name / Class / Lvl / Dist / Note), zebra + selected, footer", function()
  local shell = UI.ChromeDemo()
  shell:Select("bloodsports", "finder")
  local list, pg = shell.demoLists.finder, shell.demoPages.finder
  T.ok(list, "finder is a list page"); T.eq(shell.demoStatPages.finder, nil, "no stat rows on the Finder")
  local titles = {}
  for _, c in ipairs(list.columns) do titles[c.title] = true end
  for _, t in ipairs({ "Name", "Class", "Lvl", "Dist", "Note" }) do T.ok(titles[t], "column " .. t) end
  local data = list:GetData()
  T.ok(#data >= 12, ">= 12 duelists (" .. #data .. ")")
  for _, r in ipairs(data) do
    T.ok(r.name and r.className and r.level and r.dist and r.note, "row fields: " .. tostring(r.name))
    T.ok(tostring(r.dist):match("^%d+ yd$"), "distance in yards")
  end
  T.ok(list.zebraColors, "zebra"); T.ok(list:GetSelected(), "a selected row"); T.eq(list.selectedStrip, 3)
  T.eq(UI.ChromeDemoFinderFooter(12, 12), "12 duelists nearby")
  T.eq(UI.ChromeDemoFinderFooter(12, 9), "12 duelists nearby - 9 shown, scroll for more")
  T.eq(pg.foot:GetText(), UI.ChromeDemoFinderFooter(#data, list:VisibleCount()))
  T.eq(#UI.ChromeDemoDuelists, 12)
  T.ok(UI.ChromeDemoData().finderStats, "the old stat sections stay exported")
  T.noErrors()
end)

T.test("Shell v7: footerVariant = dark is a dark plate with a gold label; footerKind / default unchanged", function()
  local s
  recordingFonts(function()
    s = UI.Shell({ name = "TestShellV7FootDark", sidebar = "parchment", footerText = "Sync now", footerVariant = "dark",
      footerKind = "gold" })
  end)
  T.eq(s.footer.kind, "dark"); T.eq(s.footerVariant, "dark")
  local foot = s.footer
  foot._scripts.OnEnter(foot); foot._scripts.OnLeave(foot)
  sameColor({ foot.label:GetTextColor() }, UI.SiteTokens.gold, "gold label after hover in / out")
  T.eq(UI.Shell({ name = "TestShellV7FootGold", footerText = "x", footerKind = "gold" }).footer.kind, "gold", "gold callers")
  local d = UI.Shell({ name = "TestShellV7FootDefault", footerText = "x" })
  T.eq(d.footer.kind, "dark", "default unchanged"); T.eq(d.footer.labelColor, nil, "default label colour unchanged")
  T.eq(UI.ChromeDemo().footer.kind, "dark", "demo Sync now is dark")
  T.eq(UI.ChromeDemo().footerVariant, "dark")
  T.noErrors()
end)

T.test("StatRows v7: o.subColor paints the sub-lines (final colour); default and the muted token unchanged", function()
  T.near(UI.Tokens.muted[1], 0.68, 1e-6, "global muted untouched")
  local sr, plain
  local sub = { 0xb9 / 255, 0xa9 / 255, 0x8a / 255, 1 }
  recordingFonts(function()
    sr = UI.StatRows(UIParent, { rowHeight = 28, subColor = sub })
    sr:SetSize(400, 600)
    sr:SetSections({ { title = "A", rows = { { label = "x", value = "1", sub = "first" }, { label = "y", value = "2", sub = "s" } } } })
    sr:Refresh()
    plain = UI.StatRows(UIParent, {})
    plain:SetSize(400, 600)
    plain:SetSections({ { rows = { { label = "x", value = "1", sub = "first" } } } })
  end)
  T.eq(sr.subColor, sub)
  local seen = 0
  for _, row in ipairs(sr.rows) do
    if row.entry and row.entry.sub then
      sameColor({ row.sub:GetTextColor() }, sub, "sub-line " .. row.entry.label); seen = seen + 1
    end
  end
  T.eq(seen, 2)
  T.eq(plain.subColor, false)
  sameColor({ plain.rows[1].sub:GetTextColor() }, UI.Tokens.muted, "default sub stays muted")
  T.ok(lum(sub) > lum(UI.Tokens.muted), "demo sub grey is a step lighter than muted")
  local shell = UI.ChromeDemo()
  for _, id in ipairs({ "stats", "overview", "pace" }) do
    shell:Select(id == "stats" and "bloodsports" or "elders", id)
    T.eq(shell.demoStatPages[id].subColor, UI.ChromeDemoSubColor, id .. " passes the sub colour")
  end
  sameColor(UI.ChromeDemoSubColor, hexc("b9a98a"), "demo sub colour")
  T.noErrors()
end)

-- v8 art: titleArt / portraitArt / corners. Inside fn, textures record SetTexCoord and refuse SetTexture on `bad`
-- paths (error), and the native template carries a portrait socket.
local ART_NS = { Media = { path = "Interface\\AddOns\\Elders\\Media\\",
  has = { logo_main = true, logo_m = true, ornament_corner = true } } }
local function artStubs(bad, fn)
  local prev = CreateFrame
  local function wrapTex(owner)
    local make = owner.CreateTexture
    owner.CreateTexture = function(frame, ...)
      local t = make(frame, ...)
      t.SetTexCoord = function(self, ...) self._texCoord = { ... } end
      local set = t.SetTexture
      t.SetTexture = function(self, path, ...)
        if bad and path and bad[path] then error("missing texture " .. tostring(path)) end
        return set(self, path, ...)
      end
      return t
    end
  end
  CreateFrame = function(kind, name, parent, template)
    local f = prev(kind, name, parent, template)
    wrapTex(f)
    if template == "PortraitFrameTemplate" then
      local portrait = f:CreateTexture()
      f.GetPortrait = function() return portrait end
    end
    return f
  end
  local ok, err = pcall(fn)
  CreateFrame = prev
  if not ok then error(err, 0) end
end
local function sameList(a, b, msg)
  T.eq(type(a), "table", msg)
  T.eq(#a, #b, msg .. " length")
  for i = 1, #b do T.near(a[i], b[i], 1e-9, msg .. " [" .. i .. "]") end
end

T.test("Shell v8: titleArt draws the wordmark, hides the Cinzel title, clears the tab strip; falls back to text", function()
  local base = ART_NS.Media.path
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV8Title", title = "World of Meta", chrome = "portrait", ns = ART_NS, titleArt = true })
    T.ok(s.titleArt, "title art drawn")
    T.eq(s.titleArt.path, base .. "logo_main")
    local t = s.titleArt.texture
    T.eq(t:GetTexture(), base .. "logo_main")
    T.eq(t:GetWidth(), 240); T.eq(t:GetHeight(), 103, "v9: 240 wide, height by the 800:344 aspect")
    local pt, rel, rp, x, y = t:GetPoint(1)
    T.eq(pt, "TOP"); T.eq(rel, s.frame); T.eq(rp, "TOP"); T.eq(x, 0); T.eq(y, 10, "10 px over the top edge")
    sameList(t._texCoord, { 0, 1, 18 / 256, 238 / 256 }, "pow2 padding cropped")
    T.eq(s.title:IsShown(), false, "Cinzel title hidden")
    T.eq(s.title:GetText(), "World of Meta", "text kept for the fallback")
    T.eq(s.titleArt.bottom, 103 - 10 - UI.ShellArt.titleTuck)
    T.ok(s.tabTop >= s.titleArt.bottom + UI.ShellMetrics.gap, "tab strip clears the art (tabTop " .. tostring(s.tabTop) .. ")")
    -- an explicit path: drawn as given, no crop
    local e = UI.Shell({ name = "TestShellV8TitlePath", title = "x", titleArt = "Interface\\Custom\\Logo" })
    T.eq(e.titleArt.texture:GetTexture(), "Interface\\Custom\\Logo"); T.eq(e.titleArt.texture._texCoord, nil)
    -- fallbacks: no Media entry, no ns, a texture that errors -> text title, v7 layout
    local plain = UI.Shell({ name = "TestShellV8TitleNone", title = "World of Meta", chrome = "portrait" })
    for _, o in ipairs({
        { name = "TestShellV8TitleNoMedia", ns = { Media = { path = base, has = {} } } },
        { name = "TestShellV8TitleNoNs" } }) do
      o.title, o.chrome, o.titleArt = "World of Meta", "portrait", true
      local f = UI.Shell(o)
      T.eq(f.titleArt, nil, o.name); T.eq(f.title:IsShown(), true, o.name)
      T.eq(f.tabTop, plain.tabTop, o.name .. " layout unchanged")
    end
  end)
  artStubs({ ["Interface\\AddOns\\Elders\\Media\\logo_main"] = true }, function()
    local f = UI.Shell({ name = "TestShellV8TitleBad", title = "World of Meta", ns = ART_NS, titleArt = true })
    T.eq(f.titleArt, nil, "erroring texture -> off"); T.eq(f.title:IsShown(), true)
  end)
  T.noErrors()
end)

T.test("Shell v8: portraitArt fills the native portrait socket; falls back to o.portrait", function()
  local base = ART_NS.Media.path
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV8Portrait", title = "x", ns = ART_NS, portraitArt = true,
      portrait = "Interface\\Icons\\X" })
    T.ok(s.hasPortrait, "socket found")
    T.eq(s.portrait:GetTexture(), base .. "logo_m"); T.eq(s.portraitArt, base .. "logo_m")
    sameList(s.portrait._texCoord, { 0, 1, 0, 1 }, "full texture in the socket")
    local p = UI.Shell({ name = "TestShellV8PortraitPath", title = "x", portraitArt = "Interface\\Custom\\M" })
    T.eq(p.portrait:GetTexture(), "Interface\\Custom\\M")
    local n = UI.Shell({ name = "TestShellV8PortraitNone", title = "x", portraitArt = true, portrait = "Interface\\Icons\\X" })
    T.eq(n.portrait:GetTexture(), "Interface\\Icons\\X", "no art -> o.portrait"); T.eq(n.portraitArt, nil)
  end)
  artStubs({ ["Interface\\AddOns\\Elders\\Media\\logo_m"] = true }, function()
    local b = UI.Shell({ name = "TestShellV8PortraitBad", title = "x", ns = ART_NS, portraitArt = true,
      portrait = "Interface\\Icons\\X" })
    T.eq(b.portrait:GetTexture(), "Interface\\Icons\\X", "erroring art -> o.portrait"); T.eq(b.portraitArt, nil)
  end)
  T.noErrors()
end)

T.test("Shell v8: corners draw 4 mirrored 72 px ornaments between the border and the title art", function()
  local base = ART_NS.Media.path
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV8Corners", title = "x", chrome = "portrait", ns = ART_NS, corners = true,
      titleArt = true })
    T.ok(s.corners, "corners drawn"); T.eq(s.corners.path, base .. "ornament_corner")
    T.eq(#s.corners.textures, 4)
    local want = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 },
      BOTTOMRIGHT = { 1, 0, 1, 0 } }
    local seen = {}
    for _, t in ipairs(s.corners.textures) do
      local pt, rel, rp, x, y = t:GetPoint(1)
      T.eq(rel, s.frame); T.eq(rp, pt); T.eq(x, 0); T.eq(y, 0)
      T.eq(t:GetWidth(), 72); T.eq(t:GetHeight(), 72)
      T.eq(t:GetTexture(), base .. "ornament_corner")
      sameList(t._texCoord, want[pt], pt .. " texcoords")
      seen[pt] = true
    end
    for pt in pairs(want) do T.ok(seen[pt], pt .. " placed") end
    local fl = s.frame:GetFrameLevel()
    local cl, tl = s.corners.host:GetFrameLevel(), s.titleArt.host:GetFrameLevel()
    T.ok(cl > s.depth.host:GetFrameLevel(), "corners above the border band")
    T.ok(cl >= fl + 500, "corners above the template edge art (~500 up)")
    T.ok(tl > cl, "title art above the corners")
    T.ok(s.closeButton:GetFrameLevel() > tl, "close stays clickable on top")
    -- explicit path; off by default; erroring texture -> off
    T.eq(UI.Shell({ name = "TestShellV8CornersPath", corners = "Interface\\Custom\\C" }).corners.path, "Interface\\Custom\\C")
    T.eq(UI.Shell({ name = "TestShellV8CornersOff", ns = ART_NS }).corners, nil, "off unless set")
    T.eq(UI.Shell({ name = "TestShellV8CornersNoArt", corners = true }).corners, nil, "missing art -> off")
  end)
  artStubs({ ["Interface\\AddOns\\Elders\\Media\\ornament_corner"] = true }, function()
    local b = UI.Shell({ name = "TestShellV8CornersBad", ns = ART_NS, corners = true })
    T.eq(b.corners, nil, "erroring texture -> off")
  end)
  T.noErrors()
end)

T.test("/mkchrome v8: the demo asks for title art, the M portrait and corners (off without Media in the stub)", function()
  local shell = UI.ChromeDemo()
  T.eq(shell.opts.titleArt, true); T.eq(shell.opts.portraitArt, true); T.eq(shell.opts.corners, "bottom", "v9")
  -- the stub loads Demo.lua with no addon ns, so every piece falls back to the v7 look
  T.eq(shell.titleArt, nil); T.eq(shell.corners, nil); T.eq(shell.title:IsShown(), true)
  T.noErrors()
end)

T.test("Art pipeline v8: manifest and both addons' Media.lua list logo_main, logo_m, ornament_corner", function()
  local function read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a"); fh:close(); return s
  end
  local manifest = read(root .. "/tools/art/manifest.json")
  T.ok(manifest, "manifest readable")
  for _, n in ipairs({ "logo_main", "logo_m", "ornament_corner" }) do
    T.ok(manifest:find('"name": "' .. n .. '"', 1, true), "manifest has " .. n)
  end
  -- Media.lua / TGAs are build outputs (tools/build.py); Bloodsports lives in the sibling repo
  local checked = 0
  for _, dir in ipairs({ root .. "/Elders", root .. "/../bloodsports/Bloodsports" }) do
    local media = read(dir .. "/Media.lua")
    if media then
      checked = checked + 1
      for _, n in ipairs({ "logo_main", "logo_m", "ornament_corner" }) do
        T.ok(media:find("\n  " .. n .. " = true,", 1, true), dir .. "/Media.lua lists " .. n)
        T.ok(read(dir .. "/Media/" .. n .. ".tga"), dir .. "/Media/" .. n .. ".tga exists")
      end
    end
  end
  T.ok(checked >= 1, "at least the Elders Media.lua is readable")
end)

-- v9 ----------------------------------------------------------------------------------------------------------------

T.test("Shell v9: ShellArt title 240 wide (tunable), content starts ~20 px higher than the 280 art", function()
  T.eq(UI.ShellArt.titleWidth, 240)
  artStubs(nil, function()
    local o = function(n) return { name = n, title = "World of Meta", chrome = "portrait", ns = ART_NS, titleArt = true } end
    local s = UI.Shell(o("TestShellV9Title"))
    T.eq(s.titleArt.width, 240); T.eq(s.titleArt.height, 103)
    local A = UI.ShellArt
    local prevW, prevT = A.titleWidth, A.titleTuck
    A.titleWidth, A.titleTuck = 280, 0 -- the it8 geometry
    local old = UI.Shell(o("TestShellV9TitleOld"))
    A.titleWidth, A.titleTuck = prevW, prevT
    T.eq(old.titleArt.width, 280, "width tunable through UI.ShellArt")
    local won = old.bodyTop - s.bodyTop
    -- v10: titleTuck 3 -> 6, so 17 px (art height) + the 6 px tuck
    T.eq(won, old.titleArt.height - s.titleArt.height + A.titleTuck, "content height recovered (got " .. tostring(won) .. ")")
    T.ok(won >= 18 and won <= 24, "about 20 px of content height recovered (got " .. tostring(won) .. ")")
    T.eq(old.tabTop - s.tabTop, won, "tab strip moves up with the panels")
  end)
  T.noErrors()
end)

T.test("Shell v9: corners = 'bottom' draws only BL / BR; 'all' keeps four", function()
  local base = ART_NS.Media.path
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV9CornersBottom", title = "x", chrome = "portrait", ns = ART_NS, corners = "bottom" })
    T.ok(s.corners, "corners drawn"); T.eq(s.corners.mode, "bottom"); T.eq(s.corners.path, base .. "ornament_corner")
    T.eq(#s.corners.textures, 2)
    local seen = {}
    for _, t in ipairs(s.corners.textures) do seen[(t:GetPoint(1))] = true end
    T.ok(seen.BOTTOMLEFT and seen.BOTTOMRIGHT, "bottom pair placed")
    T.ok(not seen.TOPLEFT and not seen.TOPRIGHT, "no top pair")
    local a = UI.Shell({ name = "TestShellV9CornersAll", title = "x", ns = ART_NS, corners = "all" })
    T.eq(a.corners.mode, "all"); T.eq(#a.corners.textures, 4)
    T.eq(UI.Shell({ name = "TestShellV9CornersTrue", ns = ART_NS, corners = true }).corners.mode, "all")
    T.eq(UI.Shell({ name = "TestShellV9CornersBottomNoArt", corners = "bottom" }).corners, nil, "missing art -> off")
  end)
  T.noErrors()
end)

T.test("Shell v9: closeStyle = 'plate' swaps the stock close for a gold-X plate; text X when rotation fails", function()
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV9Plate", title = "x", chrome = "portrait", closeStyle = "plate", corners = true,
      ns = ART_NS, titleArt = true })
    local c = s.closeButton
    T.eq(s.closeStyle, "plate"); T.eq(c.mkGlyph, "strokes")
    T.eq(c:GetWidth(), 24); T.eq(c:GetHeight(), 24)
    T.eq(#c.strokes, 2)
    for _, t in ipairs(c.strokes) do T.eq(t:GetWidth(), 14); T.eq(t:GetHeight(), 1.5) end
    T.ok(s.nativeClose and not s.nativeClose:IsShown(), "stock close hidden")
    T.ok(c:GetFrameLevel() > s.titleArt.host:GetFrameLevel(), "plate above the title art")
    s.frame:Show(); c:Click(); T.eq(s.frame:IsShown(), false, "plate closes the window")
    T.eq(UI.Shell({ name = "TestShellV9Native", title = "x" }).closeStyle, "native", "native stays default")
  end)
  -- no rotation API: the bars go, a gold X font string is drawn
  local prev = CreateFrame
  CreateFrame = function(...)
    local f = prev(...)
    local make = f.CreateTexture
    f.CreateTexture = function(frame, ...)
      local t = make(frame, ...)
      t.SetRotation = function() error("no rotation") end
      return t
    end
    return f
  end
  local ok, err = pcall(function()
    local s = UI.Shell({ name = "TestShellV9PlateText", title = "x", closeStyle = "plate" })
    T.eq(s.closeStyle, "plate"); T.eq(s.closeButton.mkGlyph, "text")
    T.eq(s.closeButton.glyph:GetText(), "X")
    T.eq(s.closeButton.strokes, nil, "no bars")
  end)
  CreateFrame = prev
  if not ok then error(err, 0) end
  -- a plate that cannot build (the first untemplated Button on the window after the stock close errors) keeps the
  -- native close
  local win, armed
  CreateFrame = function(kind, name, parent, template)
    if armed and kind == "Button" and parent == win and template == nil then armed = false; error("no plate") end
    local f = prev(kind, name, parent, template)
    if name == "TestShellV9PlateFail" then win = f end
    if win and parent == win and template == "UIPanelCloseButton" then armed = true end
    return f
  end
  ok, err = pcall(function()
    local s = UI.Shell({ name = "TestShellV9PlateFail", title = "x", closeStyle = "plate" })
    T.eq(armed, false, "the plate's Button call was the one refused")
    T.eq(s.closeStyle, "native"); T.ok(s.closeButton, "a close button remains"); T.eq(s.closeButton.mkGlyph, nil)
    T.ok(s.closeButton:IsShown(), "native close shown")
  end)
  CreateFrame = prev
  if not ok then error(err, 0) end
  T.noErrors()
end)

T.test("Theme v9: parchment tint 0.87; /mkchrome v9: 960 x 640, plate close, bottom corners asked", function()
  for i = 1, 3 do T.near(UI.SiteTokens.parchTint[i], 0.87, 1e-9, "parchTint " .. i) end
  local shell = UI.ChromeDemo()
  T.eq(shell.frame:GetWidth(), 960); T.eq(shell.frame:GetHeight(), 640)
  T.eq(shell.opts.closeStyle, "plate"); T.eq(shell.closeStyle, "plate", "the plate constructs in the stub")
  T.eq(shell.opts.corners, "bottom")
  T.noErrors()
end)

-- v10 ---------------------------------------------------------------------------------------------------------------

T.test("List v10: full-row snapping - a partial row is hidden, VisibleCount counts only full rows, scroll range kept", function()
  local cols = { { key = "name", title = "Name" } }
  local rows = {}
  for i = 1, 30 do rows[i] = { name = "r" .. i } end
  local l = UI.List(UIParent, { columns = cols, rowHeight = 24, headerHeight = 22, thumbScrollbar = true })
  -- stub frames have no anchored height: SetSize is the height hook the List reads (f:GetHeight())
  l:SetData(rows)
  local function fit(bodyPx) l:SetSize(400, 22 + bodyPx); l:Refresh() end
  local function shownRows()
    local n, last = 0, 0
    for k, row in ipairs(l.rows) do if row:IsShown() and row.data then n = n + 1; last = k end end
    return n, last
  end
  -- 16 full rows + 12 px (half of row 17): row 17 hidden, not drawn half, and not counted
  fit(16 * 24 + 12)
  T.eq(l:VisibleRows(), 16); T.eq(l:VisibleCount(), 16, "half row not counted")
  local n, last = shownRows()
  T.eq(n, 16); T.eq(last, 16, "pool slot 17 is empty")
  T.ok(l:GetPoolSize() >= 17, "the pool still covers the partial slot")
  T.eq(l.rows[17]:IsShown(), false); T.eq(l.rows[17].data, false, "hidden slot is unbound (no clicks)")
  for k = 1, last do T.ok(k * 24 <= 16 * 24 + 12, "row " .. k .. " fits wholly") end
  -- 1 px short of a full row: still hidden
  fit(17 * 24 - 1)
  T.eq(l:VisibleCount(), 16, "23/24 of a row is not a row"); T.eq(l.rows[17]:IsShown(), false)
  -- exact fit and float heights: the row shows
  fit(17 * 24)
  T.eq(l:VisibleCount(), 17, "exact fit")
  fit(17 * 24 - 1e-9)
  T.eq(l:VisibleCount(), 17, "float rounding does not drop a full row")
  -- scroll: range is total - full rows, the last page shows full rows only
  fit(16 * 24 + 12)
  T.eq(l:MaxOffset(), 30 - 16)
  l:SetOffset(l:MaxOffset())
  T.eq(l:GetOffset(), 14); T.eq(l:VisibleCount(), 16)
  T.eq(l.rows[16].data, rows[30], "last data row in the last full slot"); T.eq(l.rows[17]:IsShown(), false)
  T.eq(l.rail.total, 30); T.eq(l.rail.visible, 16, "thumb proportion uses full rows")
  l:SetOffset(999); T.eq(l:GetOffset(), 14, "clamped")
  -- fewer rows than full slots: all show, last page may show fewer
  l:SetOffset(0)
  l:SetData({ rows[1], rows[2], rows[3] })
  T.eq(l:VisibleCount(), 3); T.eq(l:MaxOffset(), 0)
  -- shorter than one row: the List's fallback height (10 rows) applies, never 0 full rows
  l:SetData(rows); fit(10)
  T.ok(l:VisibleCount() >= 1)
  T.noErrors()
end)

T.test("List v10: /mkchrome Ring footer = full rows on screen (no '17 shown' with a half 17th)", function()
  local shell = UI.ChromeDemo()
  shell:Select("bloodsports", "ring")
  local list, pg = shell.demoLists.ring, shell.demoPages.ring
  local n = #list:GetData()
  T.ok(n > 17, "the Ring has more rows than fit (" .. n .. ")")
  list:SetSize(600, 22 + 16 * 24 + 12) -- it9 geometry: 16 full rows + half of the 17th
  list:Refresh()
  T.eq(list:VisibleCount(), 16)
  T.eq(pg.foot:GetText(), string.format("%d rows - 16 shown, scroll for more", n))
  list:SetOffset(list:MaxOffset())
  T.eq(pg.foot:GetText(), string.format("%d rows - 16 shown, scroll for more", n), "last page: still 16 full rows")
  list:SetOffset(0)
  T.noErrors()
end)

local FLANK_BASE = "Interface\\AddOns\\Bloodsports\\Media\\"
local FLANK_NS = { Media = { path = FLANK_BASE, has = { logo_main = true, logo_m = true, crest_bloodsports = true,
  crest_tournament = true } } }

T.test("Shell v10: titleTuck 6; flankArt crests resolve, sit centred in the title band (v11: 52 px, logo-anchored)", function()
  local A = UI.ShellArt
  T.eq(A.titleTuck, 6); T.eq(A.flankSize, 52); T.eq(A.flankInset, 64)
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV10Flank", title = "World of Meta", chrome = "portrait", ns = FLANK_NS,
      titleArt = true, portraitArt = true, closeStyle = "plate",
      flankArt = { left = "crest_bloodsports", right = { "crest_elders", "crest_tournament" } } })
    T.ok(s.flanks, "flanks built")
    T.eq(s.titleArt.bottom, 103 - 10 - 6)
    local L, R = s.flanks.left, s.flanks.right
    T.eq(L.path, FLANK_BASE .. "crest_bloodsports"); T.eq(L.token, "crest_bloodsports")
    T.eq(R.path, FLANK_BASE .. "crest_tournament", "no crest_elders in this Media: falls to crest_tournament")
    T.eq(R.token, "crest_tournament")
    for _, side in ipairs({ L, R }) do
      T.eq(side.texture:GetWidth(), 52); T.eq(side.texture:GetHeight(), 52)
      T.eq(side.texture:GetTexture(), side.path)
      T.eq(side.texture:GetNumPoints(), 1, "re-anchored, not stacked")
    end
    local cy = s.tabTop / 2
    local pt, rel, rp, x, y = L.texture:GetPoint(1)
    T.eq(pt, "RIGHT"); T.eq(rel, s.titleArt.texture); T.eq(rp, "TOPLEFT"); T.eq(x, -18)
    T.eq(y, -(cy + A.titleLift), "centred in the band")
    pt, rel, rp, x, y = R.texture:GetPoint(1)
    T.eq(pt, "LEFT"); T.eq(rel, s.titleArt.texture); T.eq(rp, "TOPRIGHT"); T.eq(x, 18); T.eq(y, -(cy + A.titleLift))
    -- the crests stay inside the band (frame top -> tab strip); x < 0 / > 0 keeps them off the wordmark
    T.ok(cy - 26 >= 0 and cy + 26 <= s.tabTop, "inside the title band")
    -- crests draw under the wordmark, the close plate stays on top
    T.ok(s.flanks.host:GetFrameLevel() < s.titleArt.host:GetFrameLevel())
    T.ok(s.closeButton:GetFrameLevel() > s.flanks.host:GetFrameLevel())
    -- a re-layout keeps one anchor per crest and follows tabTop
    s:LayoutBody()
    T.eq(L.texture:GetNumPoints(), 1); T.eq(select(5, L.texture:GetPoint(1)), -(s.tabTop / 2 + A.titleLift))
    -- crest_elders present: the right flank takes it first; true uses the per-side default tokens
    local ns2 = { Media = { path = FLANK_BASE, has = { crest_bloodsports = true, crest_elders = true, crest_tournament = true } } }
    local d = UI.Shell({ name = "TestShellV10FlankTrue", title = "x", ns = ns2, flankArt = { left = true, right = true } })
    T.eq(d.flanks.left.token, "crest_bloodsports"); T.eq(d.flanks.right.token, "crest_elders")
    -- an explicit path is used as given
    local e = UI.Shell({ name = "TestShellV10FlankPath", title = "x", flankArt = { left = "Interface\\Custom\\Crest" } })
    T.eq(e.flanks.left.path, "Interface\\Custom\\Crest"); T.eq(e.flanks.right, nil, "unset side hidden")
    -- missing art: that side hidden; none at all: no flanks, layout unchanged
    local m1 = UI.Shell({ name = "TestShellV10FlankHalf", title = "x", ns = FLANK_NS, flankArt = { left = true, right = "crest_elders" } })
    T.ok(m1.flanks.left); T.eq(m1.flanks.right, nil, "crest_elders absent -> right hidden")
    local plain = UI.Shell({ name = "TestShellV10FlankPlain", title = "x", ns = FLANK_NS })
    local none = UI.Shell({ name = "TestShellV10FlankNone", title = "x", flankArt = { left = true, right = true } })
    T.eq(none.flanks, nil, "no ns -> no flanks"); T.eq(plain.flanks, nil, "off unless asked")
    T.eq(none.tabTop, plain.tabTop, "flanks never move the layout")
    T.eq(UI.Shell({ name = "TestShellV10FlankJunk", title = "x", ns = FLANK_NS, flankArt = "yes" }).flanks, nil, "non-table ignored")
  end)
  -- an erroring texture hides that side only
  artStubs({ [FLANK_BASE .. "crest_bloodsports"] = true }, function()
    local b = UI.Shell({ name = "TestShellV10FlankBad", title = "x", ns = FLANK_NS, flankArt = { left = true, right = true } })
    T.eq(b.flanks.left, nil, "erroring art -> left hidden"); T.eq(b.flanks.right.token, "crest_tournament")
  end)
  -- the demo asks for both crests (crest_elders first on the right, crest_tournament as the fallback)
  local demo = UI.ChromeDemo()
  T.eq(demo.opts.flankArt.left, "crest_bloodsports")
  T.eq(demo.opts.flankArt.right[1], "crest_elders"); T.eq(demo.opts.flankArt.right[2], "crest_tournament")
  T.noErrors()
end)

T.test("Shell v11: flank crests 52 px, anchored 18 px outside the wordmark, each with a 60 px 0.25 halo", function()
  local A = UI.ShellArt
  T.eq(A.flankSize, 52); T.eq(A.flankGap, 18); T.eq(A.flankHalo, 60); T.eq(A.flankHaloAlpha, 0.25)
  T.eq(A.flankInset, 64, "edge inset kept for the no-logo case")
  artStubs(nil, function()
    local s = UI.Shell({ name = "TestShellV11Flank", title = "World of Meta", chrome = "portrait", ns = FLANK_NS,
      titleArt = true, portraitArt = true, closeStyle = "plate",
      flankArt = { left = "crest_bloodsports", right = { "crest_elders", "crest_tournament" } } })
    local logo, L, R = s.titleArt.texture, s.flanks.left, s.flanks.right
    local cy = s.tabTop / 2
    for _, side in ipairs({ L, R }) do
      T.eq(side.texture:GetWidth(), 52); T.eq(side.texture:GetHeight(), 52)
      T.eq(side.texture:GetNumPoints(), 1)
      local h = side.halo
      T.ok(h, "halo built")
      T.eq(h:GetTexture(), side.path, "halo is the same crest")
      T.eq(h:GetWidth(), 60); T.eq(h:GetHeight(), 60); T.eq(h:GetAlpha(), 0.25)
      local pt, rel, rp, x, y = h:GetPoint(1)
      T.eq(pt, "CENTER"); T.eq(rel, side.texture); T.eq(rp, "CENTER"); T.eq(x, 0); T.eq(y, 0)
      T.ok(h ~= side.texture)
    end
    -- left crest: its RIGHT edge 18 px left of the logo's left edge; right crest mirrored
    local pt, rel, rp, x, y = L.texture:GetPoint(1)
    T.eq(pt, "RIGHT"); T.eq(rel, logo); T.eq(rp, "TOPLEFT"); T.eq(x, -18)
    T.eq(y, -(cy + A.titleLift), "still centred in the title band (logo top is titleLift above the frame)")
    pt, rel, rp, x, y = R.texture:GetPoint(1)
    T.eq(pt, "LEFT"); T.eq(rel, logo); T.eq(rp, "TOPRIGHT"); T.eq(x, 18); T.eq(y, -(cy + A.titleLift))
    -- band fit with the halo, and the left crest still clears the frame edge inset
    T.ok(cy - 30 >= 0 and cy + 30 <= s.tabTop, "halo inside the title band")
    local frameW = s.frame:GetWidth()
    T.ok((frameW - s.titleArt.width) / 2 - 18 - 52 >= 64, "left crest clears the portrait side")
    -- re-layout keeps one anchor per crest; the halo stays on its crest
    s:LayoutBody()
    T.eq(L.texture:GetNumPoints(), 1); T.eq(select(2, L.texture:GetPoint(1)), logo)
    T.eq(L.halo:GetNumPoints(), 1)
    -- no title art (text title): the v10 frame-edge anchoring at +-64
    local t = UI.Shell({ name = "TestShellV11FlankText", title = "x", ns = FLANK_NS,
      flankArt = { left = true, right = "crest_tournament" } })
    T.eq(t.titleArt, nil)
    local tcy = t.tabTop / 2
    pt, rel, rp, x, y = t.flanks.left.texture:GetPoint(1)
    T.eq(pt, "LEFT"); T.eq(rel, t.frame); T.eq(rp, "TOPLEFT"); T.eq(x, 64); T.eq(y, -tcy)
    pt, rel, rp, x, y = t.flanks.right.texture:GetPoint(1)
    T.eq(pt, "RIGHT"); T.eq(rel, t.frame); T.eq(rp, "TOPRIGHT"); T.eq(x, -64); T.eq(y, -tcy)
    T.ok(t.flanks.left.halo and t.flanks.right.halo, "halos without a logo too")
  end)
  -- a halo whose texture fails is skipped; the crest itself stays
  local CREST = FLANK_BASE .. "crest_bloodsports"
  local prev, n = CreateFrame, 0
  artStubs(nil, function()
    local inner = CreateFrame
    CreateFrame = function(...)
      local f = inner(...)
      local make = f.CreateTexture
      f.CreateTexture = function(frame, ...)
        local tx = make(frame, ...)
        local set = tx.SetTexture
        tx.SetTexture = function(self, path, ...)
          if path == CREST then n = n + 1; if n == 2 then error("halo boom") end end
          return set(self, path, ...)
        end
        return tx
      end
      return f
    end
    local ok, err = pcall(function()
      local b = UI.Shell({ name = "TestShellV11HaloBad", title = "x", ns = FLANK_NS,
        flankArt = { left = "crest_bloodsports", right = "crest_tournament" } })
      T.ok(b.flanks.left, "crest kept"); T.eq(b.flanks.left.texture:GetTexture(), CREST)
      T.eq(b.flanks.left.halo, nil, "failed halo skipped")
      T.ok(b.flanks.right.halo, "other side unaffected")
    end)
    CreateFrame = inner
    if not ok then error(err, 0) end
  end)
  T.eq(CreateFrame, prev)
  T.eq(n, 2, "crest set once, halo attempted once")
  T.noErrors()
end)

T.test("SharedShell: singleton, queued tabs / sections drain on creation, ns art lookup, Toggle(tab, section), onShow", function()
  loadedSet({ Alpha = true, Beta = true })
  local ok, err = pcall(function()
    T.eq(UI._sharedShell, nil, "lazy: nothing built yet")
    local builds, shows = 0, {}
    T.eq(UI.RegisterSharedTab({ id = "alpha", label = "Alpha", owner = "Alpha", order = 1 }), true)
    T.eq(UI.RegisterSharedSection({ tab = "alpha", id = "one", label = "One", order = 1,
      build = function(p) builds = builds + 1; return CreateFrame("Frame", nil, p) end,
      onShow = function(_, _, sec) shows[#shows + 1] = sec.id end }), true)
    UI.RegisterSharedSection({ tab = "alpha", id = "two", label = "Two", order = 2,
      build = function(p) return CreateFrame("Frame", nil, p) end,
      onShow = function(_, _, sec) shows[#shows + 1] = sec.id end })
    T.eq(UI.RegisterSharedTab({}), false); T.eq(UI.RegisterSharedSection({ tab = "x" }), false)
    T.eq(UI._sharedShell, nil, "registering does not create the shell")
    local db1, db2 = {}, {}
    local shell = UI.SharedShell(db1, { Media = { path = "Interface\\\\AddOns\\\\A\\\\", has = { logo_main = true } } })
    T.ok(shell, "created")
    T.eq(UI.SharedShell(db2), shell, "second call returns the same shell")
    T.eq(UI._sharedShell, shell); T.eq(shell.db, db1, "first caller's db wins")
    T.eq(shell.name, "WorldOfMetaShell"); T.eq(_G.WorldOfMetaShell, shell.frame)
    T.eq(shell.chromeKind, "portrait"); T.eq(shell.sidebarMaterial == "parchment" or shell.sidebarMaterial == "flat", true)
    T.eq(shell.footerVariant, "dark"); T.ok(shell.titleArt, "wordmark from the registered ns")
    T.eq(#shell.tabs, 1); T.eq(#shell.sections.alpha, 2)
    -- after creation registrations apply directly
    UI.RegisterSharedTab({ id = "beta", label = "Beta", owner = "Beta", order = 2 })
    UI.RegisterSharedSection({ tab = "beta", id = "b1", label = "B1", build = function(p) return CreateFrame("Frame", nil, p) end })
    T.eq(#shell.tabs, 2)
    T.eq(builds, 0, "no build before the window shows")
    T.eq(shell:Toggle("alpha", "two"), true); T.eq(shell:IsShown(), true); T.eq(shell.currentSection, "two")
    T.eq(shell:Toggle("alpha", "one"), true, "other section: switches, stays open"); T.eq(shell.currentSection, "one")
    T.eq(shell:Toggle("alpha", "one"), false, "same tab + section: closes")
    T.eq(shell:Toggle("alpha"), true); T.eq(shell:Toggle("alpha"), false)
    shell:Show(); shell:Refresh(); shell:Refresh(); shell:Select("alpha", "two"); shell:Select("alpha", "one")
    T.eq(builds, 1, "section built exactly once")
    local trail = table.concat(shows, ",")
    T.ok(trail:find("one", 1, true) and trail:find("two", 1, true), "onShow fired on switches: " .. trail)
    local before = #shows
    shell:Refresh(); shell:Refresh()
    T.eq(#shows, before, "no onShow on plain refreshes")
    shell:Hide(); shell:Show()
    T.eq(#shows, before + 1, "onShow again when the window re-opens")
    T.eq(UI.SharedShellOpen(nil, nil, "beta", "b1"), true); T.eq(shell.current, "beta")
  end)
  restoreLoaded()
  if not ok then error(err, 0) end
end)

T.done()
