# Chat output (MK.Chat, Bloodsports Narrator, Elders Announce)

Plan §3.4 / P3b. Every public chat line from a World of Meta addon goes through **one sink**, `MK.Chat` (`MetaKit/Chat.lua`).
Nothing else calls `SendChatMessage`.

## The sink

```lua
MK.Chat.Configure(db.config.chat)          -- once, at OnInit; the live saved table
MK.Chat.Say("bloodsports", "text", { scope = "duel:7", important = true, route = "group" })  -> true | false, reason
MK.Chat.Reset(cat, scope)  MK.Chat.Clear(cat)  MK.Chat.Stats()  MK.Chat.Pending()
```

| Rule | Default | Where |
|---|---|---|
| min seconds between sent lines, all categories and addons together | 2.5 (clamped 1..30; the largest configured value wins) | `chat.interval` |
| identical line (category + route + text) refused inside | 30 s | `chat.dedupe` |
| hard cap of accepted lines per (category, scope); scope = a duel, a series, a ring session | 30 | `chat.cap` |
| lines waiting at once; an `important` line evicts the oldest ordinary one | 6 | `chat.queue` |
| a queued line older than this is dropped, never sent late | 20 s | `chat.maxAge` |
| silent while `MK.ChatLocked()` (checked when offered **and** when due) or in these instance types | `pvp`, `arena` | `chat.blocked` |
| per-category switch and route | `cats.<cat>.on`, `cats.<cat>.route` | `say yell party raid group channel local off` |

`group` = instance group, then raid, then party; alone it sends nothing (it never falls back to `/say`). `channel` uses
`chat.channelName` (Bloodsports: `WoMRing`). `local` prints to your own chat frame only.
Refusal reasons: `unknown off text locked nogroup nochannel dupe cap full` (delivery adds `stale`, `error`, `evicted`).

**Needs in-game confirmation:** the client may refuse `SAY`/`YELL` from a timer outside instances (hardware-event rule).
The send is `pcall`'d and counted (`Stats().error`); players hit by it should pick `group` or `local`.

## Bloodsports (`Narrator.lua`)

Category `bloodsports`, `cats.bloodsports.level` = `off | headline | full` (default `headline`).
Sources: `DUEL_COUNTDOWN/STARTED/RESOLVED`, a 1 Hz read of `ns.Duel.rec` (the engine's own samples; no new API or combat-log
reads), `SERIES_*` (best-of only), and `RING_UPDATED` diffed against the last look (the host only; a private ring speaks to
the group, never `/say`; a ring already running at load is adopted silently).

| Level | Lines |
|---|---|
| headline | duel start, first blood, a side under 20% HP, result (knockout / flee / comeback / void); series result; ring opened, betting open, locked, verdict, void, payouts summary; champion-challenge series start |
| full | + countdown, half-health beat, my final HP, each series round, series start, pool at lock, disputes, ring closed |

Settings: "Narrate duels and rings in chat", detail 0-2, route 1-5 (say, yell, group, ring channel, only me), seconds between lines.

## Elders (`Announce.lua`)

Category `elders`. `config.eldersAnnounce = say | group | off` (**default `say`**, level-up and bracket-sealed both on),
`announceLevel`, `announceBracket`. Lines: level-up (with the finished level's time and deaths once Pace has them), tenth level
("Levels 11 to 20 done"), and "sealed levels 11 to 20" on `RITUAL_SUBMIT` (a skipped ritual seals nothing).
Settings: announce-to slider (0 off, 1 say, 2 group), the two toggles, seconds between lines.
