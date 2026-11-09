-- Elders on the shared World of Meta shell: tab + Overview section queued at login, lazy single build, onShow refresh,
-- /elders and TOGGLE_PANEL routing, Elders-alone and with another tab. (The stub cannot show real layout or art.)
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
local ns = T.LoadAddon("Elders/Elders.toc")
local loaded = { Elders = true }
C_AddOns.IsAddOnLoaded = function(n) return loaded[n] and true or false end -- the stub says nothing is loaded
local MK, A, UI = MetaKit, ns.A, ns.UI

local function overview(shell)
  for _, s in ipairs(shell.sections.elders or {}) do if s.id == "overview" then return s end end
end

T.test("login queues the elders tab and the overview section; the shell is not built yet", function()
  T.eq(MK.UI._sharedShell, nil, "no shell yet")
  local q = MK.UI._sharedState
  T.eq(#q.tabs, 1); T.eq(q.tabs[1].id, "elders"); T.eq(q.tabs[1].label, "Elders"); T.eq(q.tabs[1].owner, "Elders")
  T.eq(type(q.tabs[1].summary), "function")
  T.eq(#q.sections, 1); T.eq(q.sections[1].tab, "elders"); T.eq(q.sections[1].id, "overview")
  T.eq(type(q.sections[1].build), "function"); T.eq(type(q.sections[1].onShow), "function")
end)

T.test("/elders creates the shared shell on the elders tab; Elders alone shows one tab", function()
  SlashCmdList.ELDERS("")
  local shell = MK.UI._sharedShell
  T.ok(shell, "shell created")
  T.ok(shell:IsShown(), "shown")
  T.eq(shell.current, "elders"); T.eq(shell.currentSection, "overview")
  T.eq(#shell.tabs, 1, "only the Elders tab")
  T.eq(#shell.sections.elders, 1)
  T.eq(#MK.UI._sharedState.tabs + #MK.UI._sharedState.sections, 0, "queue drained")
  T.eq(UI.SharedShell(), shell)
  T.eq(shell.db, A.db.config.shell, "Elders' own db table is the shell db (first caller wins)")
  T.noErrors()
end)

T.test("the overview builds once, however often it is selected or refreshed", function()
  local shell = MK.UI._sharedShell
  for _ = 1, 3 do A:Fire("TOGGLE_PANEL", "overview"); shell:Refresh() end
  T.Advance(6)
  local s = overview(shell)
  T.eq(s.buildCount, 1); T.ok(s.built and not s.error, "built without error")
  T.ok(UI.Panel(), "host frame kept for the panel")
  T.eq(shell.lastError, false)
  T.noErrors()
end)

T.test("onShow refreshes the section (header + stat rows) each time it comes into view", function()
  local shell = MK.UI._sharedShell
  local n = 0
  local keep = UI.Sections
  UI.Sections = function(...) n = n + 1; return keep(...) end
  shell.frame:Hide()
  shell.frame:Show()
  T.ok(n >= 1, "stat sections recomputed on re-open (" .. n .. ")")
  UI.Sections = keep
  T.noErrors()
end)

T.test("the 5 s ticker refreshes only while the elders section is in view", function()
  local shell = MK.UI._sharedShell
  local n = 0
  local keep = UI.Sections
  UI.Sections = function(...) n = n + 1; return keep(...) end
  T.Advance(5)
  local shown = n
  T.ok(shown >= 1, "refreshed while shown")
  shell.frame:Hide()
  n = 0; T.Advance(10)
  T.eq(n, 0, "no work while the window is closed")
  UI.Sections = keep
  shell.frame:Show()
  T.noErrors()
end)

T.test("sidebar summary: level, played, rank", function()
  ns.char.played = nil
  local lines = MK.UI._sharedShell:SummaryLines(MK.UI._sharedShell.tabById.elders)
  T.eq(#lines, 3)
  T.eq(lines[1].label, "Level"); T.eq(lines[2].label, "Played"); T.eq(lines[3].label, "Rank")
  T.eq(lines[2].value, UI.DASH, "no /played reading yet")
  ns.char.played = { total = 3600 * 5, level = 100, at = 0 }
  lines = MK.UI._sharedShell:SummaryLines(MK.UI._sharedShell.tabById.elders)
  T.ok(lines[2].value ~= UI.DASH, "played shows once known: " .. tostring(lines[2].value))
  T.eq(lines[3].value, UI.RankName(1))
end)

T.test("/elders and TOGGLE_PANEL select the elders tab from another tab; named section never closes", function()
  local shell = MK.UI._sharedShell
  loaded.Other = true
  MK.UI.RegisterSharedTab({ id = "other", label = "Other", owner = "Other", order = 1 })
  MK.UI.RegisterSharedSection({ tab = "other", id = "x", label = "X", build = function(p) return CreateFrame("Frame", nil, p) end })
  T.eq(#shell.tabs, 2, "two tabs when another addon is installed")
  shell:Select("other")
  T.eq(shell.current, "other")
  SlashCmdList.ELDERS("")
  T.eq(shell.current, "elders"); T.ok(shell:IsShown(), "from another tab: switches, stays open")
  SlashCmdList.ELDERS("")
  T.ok(not shell:IsShown(), "on the elders tab: closes")
  SlashCmdList.ELDERS("show")
  T.ok(shell:IsShown() and shell.current == "elders")
  A:Fire("TOGGLE_PANEL", "overview")
  T.ok(shell:IsShown(), "a named section never closes the window")
  A:Fire("TOGGLE_PANEL", "nonsense")
  T.ok(not shell:IsShown(), "an unknown id just toggles")
  T.noErrors()
end)

T.test("minimap left click opens the shell on the elders tab", function()
  local shell = MK.UI._sharedShell
  shell:Select("other"); shell.frame:Show()
  local btn = UI.minimapButton
  T.ok(btn, "minimap button exists")
  local click = btn.GetScript and btn:GetScript("OnClick")
  T.ok(click, "OnClick handler")
  click(btn, "LeftButton")
  T.eq(shell.current, "elders")
  T.noErrors()
end)

T.done()
