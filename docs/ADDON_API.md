# World of Meta addon API (MK.Ext v1)

Elders and Bloodsports are MIT licensed and each embeds **MetaKit**. `MetaKit/Ext.lua` is the public surface other
addons use to add to them without patching them: new Ring market types, panes in the shared window, outbox row kinds
and narration lines. This file is the contract. Code: `MetaKit/Ext.lua`. Tests: `tests/test_ext.lua`. A runnable
example: `examples/WomExampleMarket/`.

## 1. What each host consumes

| Kind | Registry | Consumed by the host |
|---|---|---|
| `section` | validated, forwarded to `MK.UI.RegisterSharedSection` | **yes**: the pane shows in the shared window |
| `row` | validated, `MK.Ext.PushRow` pushes to the outbox | **yes**: the row lands in your addon's outbox. The site backend ships rows only for kinds it knows; an unknown kind sits in the outbox until acked or compacted |
| `market` | validated, `MK.Ext.BuildOutcomes` / `MK.Ext.Settle` are the host-side entry points | **yes** (Bloodsports): `Ring.AddMarket{ kind = "<your id>" }` builds the outcomes with `BuildOutcomes`, and the settle hook is offered every fight, series and manual event. A kind the Ring does not know and no extension registered still becomes a `winner` market. Elders has no Ring and never consumes `market` |
| `narrator` | validated, `MK.Ext.NarratorLines(category, ctx)` collects lines | **yes** (Bloodsports): the Narrator says your lines right after its own line for the same event, through the same chat sink. Elders has no narrator and never calls providers |

Hosts tolerate a MetaKit copy without `MK.Ext` (nothing is consumed, nothing errors) and a provider or hook that
raises (that call is skipped). The Ring UI market picker still lists only the four built-in kinds; an extension market is
created from code with `Bloodsports.Ring.AddMarket{ kind = "<id>", open = true }` (host session required) and then shows in the Ring UI list like any market.

## 2. Writing an extension addon

```
Interface/AddOns/MyExtension/
  MyExtension.toc
  MyExtension.lua
```

```
## Interface: 16001, 120100
## Title: My Extension
## OptionalDeps: Elders, Bloodsports
## Version: 1.0.0

MyExtension.lua
```

**Load order.** MetaKit is not a standalone addon: it is embedded in `Elders/Libs/MetaKit` and
`Bloodsports/Libs/MetaKit`, and the global `MetaKit` exists once either has loaded. List both in `OptionalDeps`
(not `Dependencies`, so your addon still loads when only one is installed) and the client loads them first. Always
guard at the top of the file:

```lua
local ADDON = ...
local MK = _G.MetaKit
if not (MK and MK.Ext and MK.Ext.Compatible(1)) then return end   -- nothing installed, or older than Ext v1
```

When both addons are installed they each carry a copy of MetaKit and the newest `MINOR` wins; there is one `MK.Ext`
registry either way. `MK.Ext` first shipped in MetaKit MINOR 2.

**API.**

```lua
MK.Ext.VERSION                    -- integer, 1
MK.Ext.Compatible(minVersion)     -- boolean
MK.Ext.Register(kind, id, def)    -- true | false, message. Never raises.
MK.Ext.List(kind)                 -- sorted array of ids; nil, message for an unknown kind
MK.Ext.Get(kind, id)              -- { kind, id, owner, def } or nil
MK.Ext.Kinds()                    -- { "market", "narrator", "row", "section" }
MK.Ext.LIMITS                     -- ID_MAX 24, MAX_OUTCOMES 8, LABEL_MAX 24, STRING_MAX 200, LINE_MAX 255, LINES_PER_PROVIDER 8
```

Rules for every kind:

- `id`: lowercase letters, digits, underscore, starting with a letter, at most 24 characters. Prefix it with your addon
  (`myext_ring`). An id is unique per kind: registering it twice returns `false, "<kind> '<id>' is already registered by <owner>"`
  and keeps the first. An unknown kind returns `false, "unknown kind '<kind>'"`.
- Always check the result and print or log the message; a failed `Register` changes nothing.
- Set `owner = "MyExtension"` (your addon name) so conflicts name the culprit.
- Your functions are called under `pcall`. An error disables that call for that moment, never the host.

### 2.1 Kind `market`: a Ring market type

```lua
MK.Ext.Register("market", "firstblood", {
  owner    = ADDON,
  label    = "First blood",                 -- shown in the market picker
  lockOn   = "fight",                       -- "fight" | "manual" | "time"   (default "manual")
  scope    = "fight",                       -- "fight" | "series"            (default "fight")
  outcomes = function(ctx)                  -- or a plain list: { "Yes", "No" }
    if not (ctx.a and ctx.b) then return nil, "needs two fighters" end
    return {
      { label = "Alice first", ref = ctx.a },
      { label = "Bob first",   ref = ctx.b },
    }
  end,
  settle = function(market, event)          -- optional
    if event.type ~= "fight_end" or not event.firstBlood then return nil end
    for i, o in ipairs(market.outcomes) do
      if o.ref == event.firstBlood then return i end
    end
  end,
})
```

Outcomes builder. `outcomes` is a list of 2 to 8 labels (strings, or `{ label =, ref = }`), or
`function(ctx) -> list | nil, reason`. `ctx` = `{ a, b, bo, series, session }`: `a` and `b` are full `Name-Realm`
fighter names when known, `bo` is 1, 3 or 5 inside a series. Return `nil, reason` to decline. Labels are cut to 24
characters. `ref` is an opaque string you get back on the outcome (use it for a fighter name).

Settle hook. `settle(market, event) -> outcomeIndex | false | nil`: an integer 1..#market.outcomes settles to that
outcome, `false` voids the market, `nil` means "not decided, leave it to the referee". Anything else is treated as
`nil`. `market` = `{ kind, title, outcomes = { {label, ref}, ... } }`. `event` always has `type`:

| `event.type` | extra fields |
|---|---|
| `"fight_end"` | `winner`, `loser` (full names) |
| `"series_done"` | `winner`, `scoreA`, `scoreB` |
| `"manual"` | none |

Bloodsports fires them as follows. `fight_end` when the duel system message names the winner and loser; only
markets whose two fighters (`market.a`, `market.b`) are those two are asked, a market without fighters is asked for
every duel. `series_done` when a best-of series ends, to `scope = "series"` markets. `manual` through
`Bloodsports.Ring.ExtSettle({ type = "manual" })` (host only), to every extension market. Only open and locked markets are
asked. An outcome index becomes an auto verdict (the usual appeal window), `false` voids the market with reason
`"extension"`. `fight_end` also carries `how` (`"ko"` or `"flee"`); `series_done` also carries `bo`. `market` additionally
has `mid`, `scope`, `a`, `b`.

Extra fields beyond these (like `firstBlood` above) are filled by the host only when it knows them. Always handle
their absence. The referee keeps the final say: a settle result is a proposal the host may route through the dispute
window like any other verdict.

Settlement maths (parimutuel, fixed odds, remainders) belongs to Ring and is specified in `BETTING_CONTRACT.md`. A
market definition never touches money, and the addon never moves gold.

### 2.2 Kind `section`: a pane in the shared window

```lua
MK.Ext.Register("section", "myext_stats", {
  owner  = ADDON,
  tab    = "bloodsports",                   -- "bloodsports" or "elders" (the tab ids the two addons register)
  label  = "My stats",
  order  = 90,                              -- sidebar order, default 50
  icon   = "Interface\\Icons\\INV_Misc_Book_09",   -- optional
  build  = function(parent)                 -- called once, lazily, the first time the pane opens
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, -16)
    fs:SetText("Hello from MyExtension")
    return f                                -- or nil to use `parent` itself
  end,
  onShow = function(frame, shell, sec) end, -- optional, every time the pane comes into view
})
```

`build` is called under `pcall` by the shell; if it errors the pane shows "This section could not be built." and
nothing else breaks. The section is queued until the shared window exists. The tab must exist: if the tab's owner
addon is not loaded, your pane is simply not shown. To make your own tab, call `MK.UI.RegisterSharedTab{ id =,
label =, owner =, order = }` before registering the section (that function is plain MetaKit UI, not versioned
by `Ext.VERSION`; see the header of `MetaKit/UI/Shell.lua`). `Register` refuses a section whose `tab` already has a
pane with that id, so an extension cannot replace a core pane.

### 2.3 Kind `row`: an outbox row kind

```lua
MK.Ext.Register("row", "myext_tally", {
  owner  = ADDON,
  fields = { name = "string", count = "number", live = "boolean" },
})

-- later, with your addon object (anything with :Push, i.e. a MetaKit Addon):
local seq, err = MK.Ext.PushRow(MyAddon, "myext_tally", { name = "Alice", count = 3, live = true })
if not seq then print(err) end
```

The kind is the row's `kind` as written, so it passes through the outbox to the uploader unchanged. The id uses the
common charset. The names `bet challenge duel duel_confirm insight levelup link rating ring vote` belong to the
addons and are refused. `PushRow` rejects unknown fields, wrong types, `NaN` and infinity, and cuts strings to 200
characters; an invalid row never reaches the outbox. Nothing here makes the site accept the kind: the backend decides,
and until it does the row waits in your addon's SavedVariables.

### 2.4 Kind `narrator`: a line provider

```lua
MK.Ext.Register("narrator", "myext_pirate", {
  owner      = ADDON,
  categories = { "kill", "flee" },          -- optional filter; omit to be asked for every category
  lines = function(category, ctx)
    if category == "kill" then
      return { (ctx.winner or "Someone") .. " walks the plank for " .. (ctx.loser or "someone") .. "!" }
    end
    return { "A coward runs." }
  end,
})
-- shorthand: MK.Ext.Register("narrator", "myext_plain", function(category, ctx) return { "..." } end)
```

`lines(category, ctx) -> { string, ... } | nil`. `category` is a short lowercase string chosen by the host
(Bloodsports calls: `fight_start`, `first_blood`, `kill`, `flee`, `series_done`, `ring_verdict`, `ring_dispute`; `hit` is not used yet).
`ctx` always has `source = "bloodsports"` and, best-effort, `a`/`b` (`fight_start`), `winner`/`loser` (`first_blood`,
`kill`, `flee`, `series_done`), `dur`, `comeback`, `bo`, `scoreA`/`scoreB`, and `title`/`outcome`/`ref` (`ring_verdict`), `title`/`kind`/`mid`/`stage` (`disputed`, `upheld` or `amended`)/`by`/`code` (`ring_dispute`).
The category list may grow: ignore categories you do not know by returning `nil`. Your lines are spoken after the
host's own line for that event, at the configured narrator level (nothing at level off), never marked important, and
subject to the shared chat pacing, dedupe and per-duel/series/session caps, so a capped sink drops yours first. Hosts take at most 8 lines
per provider per call, each cut to 255 characters (one chat message), and skip empty or non-string entries.

## 3. Versioning policy

- `MK.Ext.VERSION` is an integer that changes only for **breaking** changes to the stable surface below.
  Additive changes (a new optional `def` field, a new event field, a new kind) keep the number.
- Extensions check `MK.Ext.Compatible(1)` and do nothing otherwise. They must never assume a field they were not
  promised; hosts never assume one a `def` did not provide.
- A breaking change bumps `VERSION`, and the previous version's behaviour is kept for one release where feasible.
- MetaKit's `MINOR` (in `MetaKit/MetaKit.lua`) also changes with any file change to the library, so the newest embedded
  copy wins; it is not an API version.

**Stable (v1)**: `Register` / `List` / `Get` / `Kinds` / `Compatible` signatures and result shapes; the four kinds and
their documented `def` fields; id charset and limits in `MK.Ext.LIMITS`; reserved row names; `outcomes`, `settle` and
`lines` call signatures; the event `type` values and fields in section 2.1.

**Not stable**:

- Everything outside `MK.Ext`: `MK.UI.*` widgets and the Shell (`RegisterSharedTab` and friends included), `MK.Comm`,
  `MK.Lobby`, `MK.Venue`, the Addon framework, `MK.Util`. They may change in any MetaKit release.
- Bloodsports and Elders internals: `Ring`, `Duel`, `Series`, `Ledger` tables, SavedVariables layout, channel and wire
  formats (`WoMRing`, `R2*` messages), the outbox row schemas of the core kinds.
- The narrator category list and `ctx` fields beyond those named in 2.4.
- The `ctx` and `event` fields not listed above, which are best-effort hints.
- Art tokens and theme colours.
- `MK.Ext.BuildOutcomes`, `MK.Ext.Settle` and `MK.Ext.NarratorLines` are for hosts; their return shapes are stable
  but extensions should not call them.

## 4. Try it

`examples/WomExampleMarket/` registers `firstblood` and a section stub. Copy the folder into
`Interface/AddOns/` next to Elders or Bloodsports. It is not part of `tools/build.py` output (the build installs only
`Elders`, `Bloodsports` and the dev probe). The test `tests/test_ext.lua` loads Elders, then the example addon, and
asserts both registrations appear in `MK.Ext.List`. Bloodsports' `tests/test_ext_consume.lua` registers fake
market and narrator extensions and drives the Ring and Narrator through them.

Report problems and send changes through the repository; see `CONTRIBUTING.md`.
