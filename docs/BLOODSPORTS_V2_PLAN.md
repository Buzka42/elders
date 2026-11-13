# Bloodsports v1.1 → v2 — betting engine + unified Elders/Bloodsports UI

Status: DRAFT v1, 2026-11-09. Owner: Patryk. Written after reading both repos, both reference addons on disk,
and the live test suites. Companion decisions live in §1 (20 questions with defaults).

Repos:
- `~/Projects/bloodsports` — addon (`Bloodsports/`), tests (`tests/`), plan docs (`docs/`)
- `~/Projects/elders` — canonical `MetaKit/`, `Elders/`, `tools/build.py`, `tools/art/`, uploader, server
- `~/Projects/wom-backend` — Cloudflare Worker ingest + `/data` payload (`src/logic.ts`, `src/index.ts`)
- `~/Projects/world-of-meta` — site (`site/src/data/bloodsports.json`, status `coming_soon`)

---

## 0. Baseline (measured 2026-11-09, not remembered)

| Fact | Evidence |
|---|---|
| Bloodsports suite green | `tests/run.sh` → 14 files, 113 assertions, 0 failed |
| Elders suite green | `tests/run.sh` → 14 files, 162 assertions, 0 failed |
| Bloodsports version | `Bloodsports.toc` → 1.0.0, Interface 16001, 120100 |
| Betting exists | `Ring.lua` 679 lines: referee-hosted 2-way **parimutuel**, 1–50 g ceiling, band `10×level` g, 40 bets/session, whispers only |
| Betting transport | `GROUP_CHANNELS = PARTY, RAID, INSTANCE_CHAT, WHISPER` → **spectators outside the group cannot bet** |
| Betting persistence | `Ring.session` is memory-only — a reload kills a live ring |
| Backend already ingests bets | `ROW_KINDS` includes `bet`, `RESULT = win|loss|void`, bookie levels 1–5, bands, 5 scam reports strip levels, High Roller ≥41 g |
| Ring enabled by default | `Core.lua` → `ring = { enabled = true, currency = "gold" }` — contradicts the ToS verdict in `docs/REPORT.md` §5 ("ship feature-flagged OFF until answered") |
| UI is flat | `docs/UI_REBUILD_SPEC.md` (2026-10-22) stripped all art; `UI/Theme.lua` says "the window is flat; no skin art is registered" |
| Art exists but unused | `Bloodsports/Media/` = 33 TGA (crests, badges, glyphs, seals, banners, tile, header, footer, logo, bookie portrait) — wired in `Media.lua`, drawn nowhere |
| R5 chrome set unused | `elders/docs/ART_STATUS.md`: 11 chrome sets × 8 variants generated **and reviewed**, approved picks, "not wired — UI rebuild draws no art" |
| Site | `world-of-meta/site/src/data/bloodsports.json` → `"status": "coming_soon"` |

---

## 1. Decisions — LOCKED 2026-11-09 (owner answers; unanswered questions take the stated default)

| # | Decision |
|---|---|
| 1 | Betting is a **public, growth** feature — public ring nights, not just regulars |
| 2 | Betting ships **flagged ON** (owner accepts the ToS exposure; keep the "addon never moves gold" line) |
| 3 | **Two addons**, one integrated window: **tabs switch Bloodsports / Elders** when both are installed |
| 4 | **Both in 1.1** (UI + betting); tournaments land in **1.2** |
| 5 | **Brand + community.** Fully open source, MIT, with a documented extension API so others can build addons on it or keep the duelling alive if the owner steps away |
| 6–8 | default: 2-way + multi-outcome markets; parimutuel + bookie fixed odds; gold + site points (points first for QA) |
| 9 | **50 g ceiling now**; 200 g arrives with tournaments |
| 10–11 | default: referee holds the pot via trade; 1-fight grace then site-visible "owes" flag |
| 12 | Custom `WoMRing` channel **plus**: the bookie can form a raid and auto-invite spectators (channel stays for those outside it) |
| 13 | default: one bet per market, no hedging |
| 14 | **Referee has the final say** when players disagree |
| 15 | **Hybrid: worldofmeta.win site look + the two screenshots** (site `DESIGN.md` tokens + `PortraitFrameTemplate` + Cinzel + dark 9-slice) |
| 16 | **Tabs at the top switch addons; sidebars inside hold that addon's data** |
| 17–19 | default: every Elders section present; keep existing art unless it fails at 66 %; design at 66 % + large-mode toggle |
| 20 | **Reuse the game's own assets first**, the way Overlord and Talents Forever do (PortraitFrameTemplate, `UI-DialogBox-Border`, `UI-Panel-Button-Highlight`, `TempPortraitAlphaMask`, WHITE8X8 plates); commission only what cannot be tiled from stock |

### Owner ideas folded into scope

| Idea | Where it lands |
|---|---|
| More chat output: Elders prints to local or group (player's choice) | `Elders/Announce.lua` + a settings option; paced queue |
| Public betting duels announced in local chat, combat narrated live | `Bloodsports/Narrator.lua` — 1 Hz health/spellcast sampler → headline lines, paced (see §4 P3b) |
| Tournament organisers manage fights and brackets | 1.2 `Bloodsports/Bracket.lua` + organiser controls; designed as an extension surface from day one |
| bo1 / bo3 / bo5 duels; champion fights always bo5 | `Duel.lua` → series state machine (`Series.lua`), champion path forced to bo5 |
| Auto-register traded gold to keep the books | `Bloodsports/Ledger.lua`: `TRADE_SHOW` → `TRADE_MONEY_CHANGED` → `TRADE_ACCEPT_UPDATE` → `TRADE_CLOSED` + `PLAYER_MONEY` delta + `CHAT_MSG_MONEY`; **no uploader needed**, local reconciliation; two separate trades required because `ERR_CANT_TRADE_GOLD` forbids a mutual gold swap |


The 20-question list is retired; the table above is the record. Unanswered numbers keep the defaults noted there.

---

## 2. Target look — decoded from the two reference addons on disk

**Talents Forever** (`AddOns/TalentsForeverBook/`, the owner's chosen reference). Read from its source, not guessed:

| Layer | How it is actually built | File/line |
|---|---|---|
| Window chrome | `CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")`, fallback `PortraitFrameFlatTemplate` — Blizzard's own character-frame: round portrait socket, carved title bar, gold border | `UI.lua:4158`, `OWN` table line 99 |
| Title | Native title string goes clear, own string drawn over it in **Cinzel Bold 16**, gold `(1, 0.82, 0)` with (1,-1) shadow | `UI.lua:4166-4200` |
| Headings | **Cinzel** TTF shipped in `Fonts/` (Latin-only: non-Latin clients keep the game face) | `UI.lua:25, 74-76` |
| Body | `STANDARD_TEXT_FONT` (FRIZQT__) at 10/12/15, never a custom face for body | `UI.lua:27` |
| Cover | Dark leather **9-slice**: 4 corners 64 px (`cover-tl/tr/bl/br`), edges tiled (`cover-top/bottom` REPEAT/CLAMP, `cover-left/right` CLAMP/REPEAT), page grain `page.png` 128² REPEAT underneath, `vignette.png` over it; `inset = size × 0.3`; 40 px corners on cards, 32 fallback | `UI.lua:382-415` |
| Panels | Achievement-style "plates" drawn from `WHITE8X8` + vertex colours — gold plate: top `(1.00,0.86,0.42)`, bottom `(0.74,0.55,0.08)`, edge `(0.34,0.24,0.02)`, hover wash `(1,0.86,0.42)`; label ink `(0.13,0.09,0.01)` on gold, `(1,0.86,0.45)` on dark | `UI.lua:159-213, 259-269` |
| Pixel evidence of the assets | `cover-tl` mean RGBA ≈ (22,20,15,235), centre (11,11,12,244); `page` (11,11,13,244); `vignette` black, corner alpha 76 → 0 centre; `card` corner gold (92,68,24) | measured 2026-11-09 |
| Metrics | margin 12, gap 10, title band 50, tab strip 25, sidebar 340, tiles 40 with gap 14/12, rows ~22 | `UI.lua:29-42` |
| Portraits | masked with `Interface\CharacterFrame\TempPortraitAlphaMask`, ring `seal-ring.png`, glow `slot-glow.png` | `UI.lua:1070, 968` |

That is the whole "fitted together" trick: **the frame is literally the game's frame**, one display font (Cinzel) carries every heading, the cover is a tiling dark 9-slice instead of flat black, and every button is a gold plate drawn in code — no mismatched art panels.

**Overlord** (`AddOns/Overlord/`, Troma, ARR) is the second recipe: achievement-window chrome
(`UI-Achievement-AchievementBackground` + `MetalBorder-Left/Top` + joints + `UI-Achievement-Parchment` sidebar,
768×500, `Fancy24Font` title, `UI-DialogBox-Border` edge 32 for wood dialogs). Useful for list cards, not for our shell.

**Site look merged in** (`world-of-meta/DESIGN.md`, the "worldofmeta.win" identity): stone ramp `#0b0806 -> #140f0b ->
#1f1710 -> #2c2117`, edge `#3d2e20`, gold `#f8d16b` / gold-deep `#b8862b` / gold-dim `#8a6a2e`, parch `#e8d5a8`,
ink `#2a1a0c`, ink-red `#7a1a12`, emerald `#3fbf6a`, silver `#c9ccd3`, tooltip glass `rgba(8,9,24,0.94)` with edge
`#6b6b80`. The site's display face is already **Cinzel** (headline Marcellus, body Verdana). In game: Cinzel for
display and headings, FRIZQT__ for body (Verdana breaks at 10 pt and in non-Latin clients), stone ramp for fills, gold
for accents, emerald = Elders-positive, ink-red = Bloodsports-negative. The addon and the site then share one palette and
one display font instead of merely echoing each other.

Decision: **PortraitFrameTemplate shell + Cinzel + dark 9-slice cover + gold plates**, i.e. Talents Forever's system with
Bloodsports/Elders art. Cinzel is SIL OFL (shippable with attribution), so the font costs nothing and is the single
highest-leverage piece. Both addons ship it in their own `Fonts/` (no shared install).

Legal rule: Talents Forever and Overlord are ARR — we re-implement from Blizzard's own templates/textures and the OFL
font. Never copy or reskin their PNG/TGA files.


---

## 3. Architecture

### 3.1 Shared UI: `MetaKit/UI/Shell.lua` (new)

```
MK.UI.Shell{ name, title, subtitle, width=768, height=500, skin, db }
  :AddSection{ id, label, icon, build(parent) -> frame, order, owner }   -- owner = "Elders" | "Bloodsports"
  :Select(id) / :Toggle() / :Refresh()
```
- Chrome: `CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")` (fallback `PortraitFrameFlatTemplate`) drawn
  once in MetaKit; native title hidden and replaced by a Cinzel Bold 16 string; the dark 9-slice cover + `page.png` grain
  + `vignette.png` on top; gold plates for every button and tab. Content sections sit inside `InsetFrameTemplate`.
- Fonts: MetaKit ships `Fonts/Cinzel.ttf` + `Cinzel-Bold.ttf` (SIL OFL, attribution in README + TOC `## X-*` note); a
  `MK.UI.Display(fs, size)` helper falls back to `GameFontNormal` on non-Latin clients, exactly the guard Talents Forever
  uses (`CINZEL:SetFont` inside pcall, Latin-only face).
- Layout: a **top tab strip switches addons** (`Bloodsports` | `Elders`, only the loaded ones), and each tab owns its
  own **left sidebar of sections** plus the content pane. Spacing follows Talents Forever: margin 12, gap 10, title band
  50, tab strip 25, sidebar 340.
- Sections are plain frames built by the addons into the content pane; existing `MK.UI.List`, `StatRows`, `Tabs`,
  `Button` keep their API but gain a `chrome="native"` look (gold edge, stone row tint, medal plates).
- Addon detection: `C_AddOns.IsAddOnLoaded`. With one addon installed the sidebar shows only its sections; with both,
  cross-links appear. Slash commands `/elders` and `/bs` both open the shell on the right section.
- Fallback: if `Blizzard_AchievementUI` cannot load (or textures 404), the shell falls back to `UI-DialogBox-Border`
  edge 32 + `CollectionsBackgroundTile` — degrade, never error. Every `SetTexture`/`SetAtlas` stays pcall'd.

### 3.2 Betting: `Ring` v2

State machine: `IDLE → OPEN (betting window) → LOCKED → RESOLVING → SETTLED → PAID | VOID`, plus `DISPUTED`.
Session table (persisted, versioned, resumable after `/reload`):

```
session = { id, venue, host, currency, cap, markets = { [mid] = {
  kind = "winner"|"outcome"|"prop", outcomeCount, fighters = {...}, odds = "pari"|"fixed",
  fixed = {a=1.5,b=2.1}, status = "open"|"locked"|"settled"|"void"|"disputed",
  result = 1..n, bets = { [bettor] = { side, amount, paid, payout, paidOut, t } },
  pool = {...}, createdAt, lockAt, settledAt } } }
```
- Bet slip: side buttons, amount (typed, gold/points), implied odds + prospective payout live from the pool.
- Odds display: parimutuel implied % + fixed decimal odds; both rendered in a "pill" widget.
- Settlement math: parimutuel payout = `stake × poolTotal / poolWinning` (integer copper, remainder to the house pool
  or the first bettor by time — decide in the architect lane, it must be deterministic and mirrored server-side).
- Transport: `WoMRing` custom channel join (reuse `MK.Lobby` pattern) with whisper fallback; 30-bettor cap; flood guards.
- Outbox: `bet` row extended (`market`, `odds`, `outcomeCount`, `schema=2`); **backend ships first**, old addon rows stay valid.
- Gold never moves by code: the addon prints exact trade instructions and records `TRADE_*` refs; the human trades.

### 3.3 Backend (wom-backend) and site

- `bet` v2: `market`, `oddsMode`, `outcomeCount`, `result` as outcome index (1..n) plus `win|loss|void` mapping.
- New site surfaces: bookie board (volume, odds history, scam reports), bettor P&L, market history, "owes" flags.
- `/data.bloodsports`: bookies + level bands (exists), add `markets` templates and `odds` history slice for the addon.
- `bloodsports.json` on the site flips from `coming_soon` only when betting has a ToS answer.

---

### 3.4 Modules added by the owner's decisions

| Module | Job | Phase |
|---|---|---|
| `Bloodsports/Series.lua` | bo1 / bo3 / bo5 state machine over `Duel.lua`: per-round results, resets, series score; champion path forced to bo5 | P2b |
| `Bloodsports/Ledger.lua` | auto-books traded gold: `TRADE_SHOW` -> `TRADE_MONEY_CHANGED` -> `TRADE_ACCEPT_UPDATE` -> `TRADE_CLOSED`, `PLAYER_MONEY` delta, `CHAT_MSG_MONEY` for incoming; matches a trade to an open bet or stake; no uploader involved. Two trades per settlement, because `ERR_CANT_TRADE_GOLD` ("Gold may only be offered by one trader") makes a mutual gold swap impossible | P3 |
| `Bloodsports/Narrator.lua` | live fight narration for /say and the ring channel: 1 Hz health sampler, `UNIT_SPELLCAST_SUCCEEDED`, `PARTY_KILL` / `PLAYER_DEAD`; headline / beat / full levels; paced queue with a hard cap per fight; silent in instances where chat is locked | P3b |
| `MK.Chat` (MetaKit) | one paced chat sink for both addons: say / yell / party / raid / channel / off, per-event toggles, dedupe, throttle budget | P3b |
| `Elders/Announce.lua` | Elders prints to local or group, player's choice, same `MK.Chat` sink | P3b |
| `Bloodsports/Bracket.lua` | 1.2: organiser controls, bracket tree, fight queue, per-match bo setting, results board | 1.2 |
| `MetaKit/Ext.lua` | public extension API: `MK.Ext.Register(kind, id, def)` for market types, section panes, narrators and row kinds, plus a version stamp and docs, so "someone else can maintain it" is real | P2 |

## 4. Execution — OHM lanes with the model chain

Chain heads (live, `~/.omh/routing/model-chains.json`, all anthropic OAuth):
`architect`/`deep-work`/`ultrabrain` → **opus-5.5** (xhigh/max/high), `visual-engineering` → **opus-5.5 high**,
`capable`/`artistry`/`writing` → **sonnet-5.5 medium**, `quick`/`simple-work` → **haiku-5.5 low**.

Rules that make the chain work here:
1. Route is set **in the same turn as the dispatch** (`omh_delegate_route(action="set", category=...)` then
   `delegate_task`), one lane per call; children keep the model they started with.
2. A child that reports "completed" but burned no usage = provider 400 → `omh_delegate_route(action="fallback")` and re-dispatch.
3. Children cannot close tracked work; the parent applies every transition and every verification verdict.
4. Every unit carries a `check:` command that OMH runs itself (`omh_team`), so "done" is an exit code, not a claim.
5. Long repo sessions that need tmux + a real harness go through `~/agent-brain/hdev` (`--harness codex|agy|opencode`),
   not a child agent.

| Phase | What | Lane (category → model, effort) | check: |
|---|---|---|---|
| **P0** Baseline + decisions | answer §1, freeze scope, capture baseline shots (`/bs`, `/elders`, 66 % scale), record art inventory | parent (me) | `check: ls docs/baseline/*.png | wc -l` |
| **P1** Native chrome | `MetaKit/UI/Theme.lua` + `Widgets.lua` + new `Shell.lua`: `PortraitFrameTemplate` shell, Cinzel display font, dark 9-slice cover, gold-plate buttons/tabs, Achievement-style list cards, `/mkchrome` demo; legal = re-implement from Blizzard templates + OFL font | **visual-engineering → opus-5.5 high** (contract first: `architect → opus-5.5 xhigh` writes the widget contract) | `check: cd ~/Projects/elders && bash tests/run.sh` and `luac5.1 -p MetaKit/UI/Shell.lua` |
| **P1b** Pixel gate loop | the only way a UI phase counts as done: capture → judged against the reference → flaw list → fix → recapture, until the score hits 9.5+/10 with no open flaws. Harness: `tools/uicheck/uicheck.py` (`geo`, `shot`, `diff`, `reload`, `say`). Driving agents use `computer_use` for clicks/window moves and this script for captures; the parent owns the verdict | parent drives pixels; **visual-engineering → opus-5.5** fixes | `check: python3 ~/Projects/elders/tools/uicheck/uicheck.py geo` |
| **P2** Unified window | Elders `Panel.lua`/`Ritual.lua` and Bloodsports `Main.lua` + 5 tabs become shell sections; `/elders` and `/bs` open one window; each addon alone still works | **capable → sonnet-5.5 medium**, one child per addon | `check: cd ~/Projects/bloodsports && bash tests/run.sh` + `cd ~/Projects/elders && bash tests/run.sh` |
| **P2b** Series + bo | `Duel.lua` -> `Series.lua` (bo1/3/5, champion forced bo5), duel card shows the score, tests per format | **capable -> sonnet-5.5 medium** | `check: cd ~/Projects/bloodsports && bash tests/run.sh` |
| **P3** Betting engine v2 | markets model, odds, bet slip, persistence, spectator channel, settlement/void/dispute, `bet` schema v2 rows | **deep-work → opus-5.5 max**; contract lane first: **architect → opus-5.5 xhigh** (`docs/BETTING_CONTRACT.md`) | `check: cd ~/Projects/bloodsports && bash tests/run.sh && luac5.1 -p Bloodsports/Ring.lua` |
| **P3b** Chat + narration | `MK.Chat` sink, `Narrator.lua`, `Elders/Announce.lua`: public ring announcements, live fight beats, pacing budget, settings toggles | **capable -> sonnet-5.5 medium** (narration copy: **writing -> sonnet-5.5**) | `check: cd ~/Projects/bloodsports && bash tests/run.sh` |
| **P4** Backend + site | bet v2 ingest, bookie board, bettor P&L, `/data` markets, site page | **capable → sonnet-5.5 medium** (contract from P3) | `check: cd ~/Projects/wom-backend && npm test` |
| **P5** Art | wire the 11 reviewed R5 chrome sets + `tile_bloodsports` seam check + `seal_vote_up` re-pick; commission ~12 new pieces via `nano-assets` (`studio_gen.py --backend gemini`), triage, `tools/art/convert.py`, `build.py` | **artistry → sonnet-5.5 medium** writes prompt sheets; generation is scripted, not a child agent | `check: python3 tools/build.py && ls Bloodsports/Media/*.tga | wc -l` |
| **P7** Open source surface | `MK.Ext` docs, `docs/ADDON_API.md`, CONTRIBUTING, LICENSE check, a tiny example extension (a custom market), CurseForge description rewrite | **writing -> sonnet-5.5 medium** | `check: ls docs/ADDON_API.md && cd ~/Projects/elders && bash tests/run.sh` |
| **P6** Live verify + release | `/console scriptErrors 1`, `/reload`, screenshots at 66 %, 4–6 player ring test, version 1.1.0/1.2.0 both TOCs, GitHub release, CurseForge (owner manual) | parent drives the client; **quick → haiku-5.5 low** for packaging checks | `check: bash tests/run.sh && git status --porcelain | wc -l` (0 after commit) |

Dispatch shape per phase (parent-side, no quoting errors):

```
omh_delegate_route(action="set", category="architect")        # same turn
delegate_task(tasks=[{goal: "...", context: "..."}])
omh_delegate_route(action="set", category="visual-engineering")
delegate_task(tasks=[{goal: "...", context: "..."}])
omh_team(action="team_start", plan_ref="docs/BLOODSPORTS_V2_PLAN.md", units=[...])   # parallel, check-gated
omh_team(action="team_reconcile", team_id=..., since_seq=0)
```

Stop-rules: P1 ships nothing until the chrome demo is screenshot-approved at 66 %; P3 does not start until P2's window
is in game and approved; betting v2 does not ship ON while the ToS gate (Q2) is unanswered; any lane that returns no
usage is a dead child — fallback and re-dispatch, never re-prompt the same dead route.

---

### 4.1 Pixel gate loop — how "10/10 like Overlord" is decided

Verified working 2026-11-09 on this box: the client is a 1920×1080 XWayland window at `(1920,0)` on `HDMI-A-1`,
`grim -g` captures it 1:1, and `vision_analyze` reads the result well enough to list flaws.

```
python3 tools/uicheck/uicheck.py geo                     # rect, monitor, drift (JSON) — pin before judging
python3 tools/uicheck/uicheck.py shot --out docs/baseline/it3.png
                                                          # writes it3.png + it3.png.json (geometry + time)
python3 tools/uicheck/uicheck.py diff it2.png it3.png     # RMSE + per-band deltas: did the fix move pixels?
```

Rules that make the loop honest:
1. **Pin first.** `shot` resizes then moves the window back onto its monitor before capturing (resize re-centres under
   Hyprland), so a moved window can never read as a layout bug. `--no-pin` exists only for reference shots.
2. **Judge against the reference, not against the last iteration.** Every verdict names the two reference addons
   (Talents Forever window, Overlord Hall of Fame) and lists flaws with regions and measurements, never adjectives.
3. **Score 0–10 with a flaw list.** 10/10 = no flaw survives: frame chrome, title face, plate weights, row rhythm,
   text truncation, alignment at 66 % scale, and "would a player think this shipped with the game". A score below 9.5 or
   any open flaw means the phase is not done, regardless of green tests.
4. **Fixes go to one lane at a time**, with the previous capture path plus the flaw list in the brief. Never "make it
   nicer" — each iteration targets named flaws.
5. **Keystrokes need a hands-off window.** `reload` and `say` type into the game's chat box; never run them while the
   owner is at the keyboard (keystrokes interleave and go out as public SAY). Captures are always safe.
6. Every iteration records `docs/baseline/it<N>.png` + its json, so improvement is a diff, not a memory.

## 5. Art batch

Free / already paid for:
- **Font**: Cinzel + Cinzel-Bold, SIL OFL — download from Google Fonts, `Fonts/` in both addons, attribution in README.
  This alone is ~40 % of the perceived upgrade.
- 33 existing TGAs: crests ×10, badges ×7, seals ×3, glyphs ×2, banners ×2, tile, header, footer, logo, bookie portrait —
  all 64 px keyed, they drop straight into the new slot/ring system.
- 11 R5 chrome sets (88 variants, reviewed, picks made) — mostly superseded by code-drawn gold plates; wire only
  `chrome_rule`, `chrome_close`, `chrome_scroll_thumb`, `chrome_empty_*` **if** they beat the plate version in game.
- Open checks: `tile_bloodsports` seam is unverified in game; `seal_vote_up` shipped pick has two leaves (re-pick from
  R5 a/e/f/g, no generation).

Commission — the 9-slice cover set, one per identity (Elders + Bloodsports), ~13 pieces each at 64–256 px.
This is the only art that has to be new, because nothing we own tiles:

| File | Size | Look |
|---|---|---|
| `cover-tl/tr/bl/br` | 64² | dark leather corner, gold tooling filigree in Bloodsports iron-red / Elders oak-green, 8 px inner bevel |
| `cover-top/bottom` | 64², tiles horizontally | thin gold rule over leather, seamless left-right |
| `cover-left/right` | 64², tiles vertically | chain-link / vine motif, seamless top-bottom |
| `page` | 128², seamless | dark grain (value 10–15 %, like Talents Forever's (11,11,13)) |
| `vignette` | 256² | black, alpha 76 at corner → 0 at centre |
| `card` | 64² | small card chrome for duel card, toast, bet slip |
| `slot` / `slot-rim` / `slot-glow` | 64² / 64² / 128² | icon socket for crests/badges, gold rim, additive glow |
| `seal-ring` | 128² | portrait ring around the `PortraitFrameTemplate` socket |
| `pill` / `pill-line` | 128×32 | odds / status pill (3 tints supplied in code, one shape) |
| `ribbon` | 64² | "LIVE" ribbon for the ring header |

Betting-specific (after the engine lands): `ring_ledger`, `ring_pot` (both were gated in the original commission and never
generated), `icon_market_winner/outcome/prop` (64², one silhouette each).
Rules: generate the first of each set, owner approves, then reference-chain the rest; judged at 20/32 px and at 66 % scale;
`convert.py` keys magenta → TGA, `build.py` rewrites `Media.lua`.


---

## 6. Risks

| Risk | Fact | Mitigation |
|---|---|---|
| ToS: promoted gold gambling | `REPORT.md` §5 verdict medium-high; no Forever-specific rule found; today's default is `enabled = true` | flip default OFF, gate on Q2, keep the addon a *bookkeeping* tool (never moves gold), site page stays `coming_soon` until answered |
| Scope: betting v2 is 2–3× the UI work | current ring is 679 lines and single-market | markets model first (architect), UI consumes it; no odds math in the UI layer |
| Backend/schema break | `RESULT = win|loss|void`, `side = a|b` are hard-coded | ship `schema=2` additively, server first, old rows keep validating |
| Unified window regressions | Elders and Bloodsports both embed MetaKit; two copies must not fight | Shell lives in MetaKit, version-guarded (`MetaKit_Register`), tested in both suites |
| Children over-report | subagent "done" is a self-report | `omh_team` check commands + parent screenshot verification |
| Art looks stacked again (why the rebuild happened) | `UI_REBUILD_SPEC.md` §"Why" | native chrome carries the decoration; our art is confined to crowns, tabs, rules and market icons — never behind text |

---

## 7. Acceptance

P1: `/mkchrome` shows the shell at 66 % scale, no truncation, no overlap; both suites green; the pixel gate scores it
9.5+/10 against Talents Forever's window and Overlord's Hall of Fame with an empty flaw list.
P2: one window holds Elders sections + Bloodsports sections; `/bs` and `/elders` both open it; each addon alone still
opens its own sections; 0 Lua errors.
P3: a 3-market session survives `/reload`, settles with deterministic integer payouts matching the server's recompute,
spectator bets accepted from outside the group, disputed row flagged.
P4: `npm test` green; `/data` carries markets; site page renders books and P&L.
P5: every wired texture loads in game (`/probe art bloodsports`), tile seam invisible.
P6: 1.1.0/1.2.0 tags, release artifacts, in-game ring test recorded.

## 9. Future — after tournaments (owner, 2026-11-10)

**Guild league (Bloodsports, post-1.2):** guild BG + arena events — Gurubashi Arena (venue row already registered, `dormant`, needs activation) or a normal arena once the client has one. Guilds field teams, guild-vs-guild brackets, guild rankings. Builds on Bracket.lua (1.2).

**World of Meta: Warbands (new addon, later):**
- Groups world-PvP players into warbands (same-goal or private), guild warbands included.
- Auto-invites warband members onto one layer; defined paths/routes (staged waypoints, waypoint previews).
- Full story narration: Immersion-style talking heads — Alliance/Horde generals address players and call them to battle.
- Players form public warbands around shared goals or private ones.

## 8. UI iteration scoreboard (pixel gate, live captures in docs/baseline/)

| Iteration | Score | What moved it |
|---|---|---|
| it1 portrait shell | 5.0 | skeleton only: small title, voids, flat tabs |
| it2 filled demo | 6.5 | density, attached tabs, footer |
| it3 dialog + parchment | 5.5 | parchment arrived, sidebar text washed out, frame flat |
| it4 ink attempt | 5.0 | ink too light on tan (2.4-3:1), void persisted |
| it5 contrast + RECENT | 7.0 | parchment brightened, ink darkened, sidebar readable |
| it6 summary/money | 7.0 | summary still faint, Finder became a list |
| it7 summary ink | (crop 9/10) | summary labels near-black confirmed in game |
| it8 logo + corners | 8.0 | WORLD OF META wordmark title, M medallion, corner ornaments |
| it9 logo 240 + plate close | 8.0 | proportion fixed; row 17 half-clipped |
| it10 full rows + flanks | **9.0** | no half rows, honest footer, crest flanks — judged ship-ready |
| it11 crest halo | 8.8 | crests hug logo with halo — "Ship it", minor-only flaws. P1 closed here |

MoA (it1): Kimi 5.4 (vote), Qwen 5.5 (advisory, marker omitted), Gemini Argon failed (API 429 shared pool + bridge timeouts).
Verdict doc: docs/UI_MOA_VERDICT.md. P1 acceptance needs a final >=9 capture with an empty flaw list — it10 is 9.0 with
minor-only notes (dim crests), it11 addresses those.
