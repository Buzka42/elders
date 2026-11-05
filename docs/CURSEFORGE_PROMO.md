# Elders — CurseForge + Twitter promo (DRAFT, owner approves)

## CurseForge short description (≤250 chars)
Elders passively tracks your leveling: XP/hour, downtime, deaths and more per level bracket, with a quick ritual review every 10 levels. Your stats feed World of Meta rankings. Lightweight, private, free.

## CurseForge long description
**The Elders watch your road.**

Elders is a lightweight leveling companion for WoW Forever. It sits quietly in the
background and records how you level — then shows it back to you in one clean panel.

**What it tracks (per 1–10 … 51–60 bracket):**
- Pace: XP per hour, XP per kill, quest share, time per level, rested value
- Downtime: combat, travel, idle, eating, deaths, corpse runs
- Combat, economy, dungeons, talents — snapshots as you play

**The ritual:** every 10 levels the Elders ask three things — rate your last bracket,
judge class insights from other players, optionally leave one of your own (280 chars).
Your votes feed the World of Meta Hall of Fame and the R1–R14 elder ranks.

**Your data, your control:**
- Random character IDs — no RealID, no chat scraping, no memory reading
- Syncs through the tiny Meta Uploader app (or a copy-paste export string)
- Everything visible on your World of Meta account page

**Commands:** `/elders` (panel) · `/elders ritual` · `/elders export` · `/elders sync`
**Requires:** Meta Uploader (linked on this page) for automatic sync.
**Supports:** WoW Forever. Bloodsports (duels, fight clubs, goblin-ring betting) is its
sister addon — same account, same uploader.

**Syncing: the Meta Uploader (open source).** The addon itself never touches the
network. The Meta Uploader is a tiny desktop app that reads the SavedVariables files the
game already wrote to disk, uploads only new rows to World of Meta, and writes ranks,
insights and acknowledgements back into your AddOns folder as the WorldOfMeta_Data addon.
It never reads game memory, never sends keystrokes, never touches chat. Python 3.10+,
standard library only.
- Windows: https://github.com/Buzka42/elders/releases/download/v1.0.0/MetaUploaderSetup-1.0.0.exe
- Linux: https://github.com/Buzka42/elders/releases/download/v1.0.0/meta-uploader-1.0.0-linux-x86_64.tar.gz
- Source (verify it yourself): https://github.com/Buzka42/elders/tree/v1.0.0/uploader
  (full README, unit tests, SHA256SUMS, build scripts — build the binaries yourself
  instead of trusting ours)
- Paste-ready HTML for the CF editor: `docs/CURSEFORGE_DESCRIPTION.html`

## Screenshots (ship these 4)
1. `elders-nocursor.png` — panel with live data (in-game, baseline proven)
2. `elders-final.png` — panel, green synced state
3. Ritual dialog — PENDING (never captured; capture after ritual renders in-game)
4. `elders-banner-g.png` — promo banner SHIP (Goodmountain + stroke, compact left block, badges under text on-image)

## Tweet (≤280 chars) — option A
Elders is live on CurseForge. It tracks how you level — XP/h, downtime, deaths per bracket — and every 10 levels asks for your wisdom. Ranks, insights, Hall of Fame: worldofmeta.win 🌿 [link]

## Twitter card
`world-of-meta/assets/raw/promo/elders-twitter.png` (1200x675, tagline + URL, scrim-backed)

## Tweet — option B
How fast do YOU level? Elders for WoW Forever records XP/h, downtime and deaths per bracket, then lets you judge class insights every 10 levels. Free, lightweight, private. [link]
