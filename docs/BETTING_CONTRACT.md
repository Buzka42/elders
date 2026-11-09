# Betting v2 contract (Ring v2) — Bloodsports 1.1

Status: CONTRACT v1, 2026-11-09. Lane P3 (engine) and P4 (backend) build against this file; neither re-decides it.
Inputs: `Bloodsports/Ring.lua` (v1: 2-way parimutuel, RB/RS/RL/RF/RQ), `Core.lua`, `tests/test_ring.lua`,
`tests/test_bands.lua`, `wom-backend/src/logic.ts` + `tests/bookies.test.ts`, `BLOODSPORTS_V2_PLAN.md` §1, §3.2, §3.4.
Locked (§1): public feature, ON by default; 50 g ceiling (200 g with 1.2 tournaments); 2-way + multi-outcome markets;
parimutuel + bookie fixed odds; gold + site points (points first for QA); the referee holds the pot through trades and the
ledger records **debt only** (no credit betting); 1-fight grace, then a site "owes" flag; `WoMRing` channel + bookie raid
with auto-invite; one bet per market; the referee has the final say; bo1/bo3/bo5 series come from `Series.lua`; `Ledger.lua`
books trades; stake and payout are **two separate trades** (`ERR_CANT_TRADE_GOLD`).
Invariant kept from v1: the addon never moves gold. It records trades, computes payouts and prints instructions.

## 1. Data model

### 1.1 Constants (named in `Ring.lua`, mirrored in `logic.ts`)

| Name | Value | Note |
|---|---|---|
| `GAMBLE_MIN_COPPER` / `BET_MIN_COPPER` | 10000 (1 g) | unchanged |
| `GAMBLE_MAX_COPPER` / `BET_CEILING_COPPER` | 500000 (50 g) | becomes 2000000 in 1.2; the math stays exact to 2e6 (§3.2) |
| `DEFAULT_CAP_POINTS` | 1000 | per bet |
| band | `10 × level` g, level 1..5 | `Ring.Band` / `betBandCopper`, unchanged |
| `MAX_MARKETS` | 8 per session | |
| `MAX_OUTCOMES` | 8 per market (min 2) | |
| `MAX_BETTORS` | 30 distinct per session | replaces v1 `MAX_BETS = 40` |
| bets per market | ≤ 1 per bettor, so ≤ 30 | one bet per market, no hedging |
| `PRICE_MIN..PRICE_MAX` | 101..1000 | fixed odds ×100 (1.01–10.00) |
| `BANK_MAX(level)` | `10 × band(level)` | level 1 = 100 g, level 5 = 500 g |
| `APPEAL_SEC` | 600 | 10 min dispute window after a verdict |
| `DISPUTE_TIMEOUT_SEC` | 1800 | unresolved dispute auto-voids |
| `OPEN_MAX_SEC` | 3600 | an open market auto-locks after this |
| `STALE_SEC` | 7200 | host resume limit after reload/logout; also idle auto-close |
| `OWES_BACKSTOP_SEC` | 86400 | owes flag even with no further fights |

### 1.2 Session (one live per character; host or mirror)

| Field | Type | Cap / rule |
|---|---|---|
| `id` | hex string | 8–16 chars (`validId`), `U.RandomHex(8)` as in v1 |
| `host` | `Name-Realm` | referee = bookie = host (one role in 1.1) |
| `isHost` | bool | local only |
| `venue` | string | `^[%w_]*$`, ≤ 24 |
| `currency` | `"gold"` \| `"points"` | fixed for the session |
| `cap` | int | gold: `hostCap()` clamp 1 g..50 g; points 1000 |
| `public` | bool | default true: spectators outside the group may bet (§4.1) |
| `status` | `open` \| `closing` \| `closed` \| `stale` | §2.1 |
| `series` | `{ id, bo = 1\|3\|5, champion = bool }` \| nil | from `Series.lua`; champion forces bo 5 |
| `markets` | array of Market | ≤ 8, `mid` = `"m1".."m8"`, never reused within a session |
| `rev` | int | +1 on every host mutation; mirrors resync on gaps |
| `watchers` | array of names | host, ≤ 30: whisper-fallback audience (§4.1) |
| `createdAt`, `lastActivity`, `closedAt` | server time (s) | `U.ServerTime()` |
| `totals`, `lastHeard` | mirror only | the host's numbers as received |

### 1.3 Market

| Field | Type | Cap / rule |
|---|---|---|
| `mid` | `"m1".."m8"` | |
| `kind` | `winner` \| `method` \| `score` \| `custom` | winner: 2 outcomes (fighter a/b). method: A KO / A flee / B KO / B flee. score: bo3 = 2-0, 2-1, 1-2, 0-2; bo5 = 3-0, 3-1, 3-2, 2-3, 1-3, 0-3. custom: referee labels, manual verdict |
| `scope` | `fight` \| `series` | series scope needs `session.series` |
| `title` | string | ≤ 32 bytes |
| `outcomes` | array `{ label, ref, price }` | 2..8; label ≤ 24 bytes; `ref` = fighter name for winner; `price` fixed only |
| `mode` | `pari` \| `fixed` | one mode per market |
| `bank` | int | fixed only; ≤ `BANK_MAX(level)` and ≤ host `GetMoney()` at open (client check) |
| `status` | `draft` \| `open` \| `locked` \| `resolving` \| `disputed` \| `settled` \| `void` | §2.2 |
| `lockOn` | `fight` \| `manual` \| `time` | default `fight` (custom: `manual`) |
| `lockAt` | server time \| 0 | for `time`; ≤ now + 1800 |
| `result` | int | 0 = none/void, else the winning outcome index |
| `fight` | int | host `fightSeq` when locked (owes grace, §5.5) |
| `openedAt`, `lockedAt`, `verdictAt`, `appealUntil`, `settledAt` | server time | `appealUntil = verdictAt + 600` |
| `auto` | bool | verdict from a duel message / `SERIES_DONE` |
| `dispute` | `{ by, code, note, at, action, resolvedAt }` \| nil | one open dispute per market; later disputes are logged only |
| `voidReason` | `referee` \| `dispute` \| `close` \| `stale` | |
| `dust` | int | remainder kept by the referee (§3.2) |
| `bets` | array of Bet | ≤ 30 |

### 1.4 Bet

| Field | Type | Rule |
|---|---|---|
| `bettor` | `Name-Realm` | not the host, not a fighter in this market |
| `outcome` | int 1..n | v1 `side` a/b = outcome 1/2 |
| `amount` | int | copper or points; `refusal()` rules (§3.4) |
| `price` | int | fixed: locked at acceptance; pari: 0 |
| `t`, `paidAt` | server time | |
| `paid` | bool | gold: stake trade matched; points: true at acceptance |
| `void`, `voidReason` | bool, `unpaid` \| `market` | unpaid gold at verdict becomes void (v1 rule kept) |
| `payout` | int | set at verdict (provisional), final at `settled` |
| `paidOutAmount`, `paidOut` | int, bool | payout trades add up (§6); `paidOut` when the sum equals `payout` |
| `received` | bool | bettor role only: the payout trade arrived |
| `manual` | bool | host assigned a trade by hand |
| `nonce` | 4 hex | from R2B, echoed in R2X |

### 1.5 Debt, unmatched trade

Debt `{ id = sid.."."..mid, bettor, bookie, amount, paid, settledAt, fight, status = due|owes|cleared|contested, clearedAt,
clearedBy = bettor|host|manual }`: one per bet with `payout > 0` in a gold market at `settled`/`void`. Points create no debt.
Trade `{ t, partner, got, gave, confirmed, sid, kind = stake|payout, matched = { "sid.mid.bettor", ... }, reason }`.

### 1.6 Persistence (SavedVariables)

```
BloodsportsDB.dbVersion = 1                         -- MIGRATIONS[1] = ring v2
BloodsportsDB.config.ring = { enabled = true, currency = "gold", channel = true, public = true, autoInvite = false }
BloodsportsDB.chars[key].ring = {
  v = 2, fightSeq = 0,
  session = <Session> | nil,       -- live session: Ring.session points INTO this table (write-through)
  last = <Session> | nil,          -- last closed session (Owed view)
  debts = { <Debt>, ... },         -- cap 100; cleared debts pruned after 30 d
  unmatched = { <Trade>, ... },    -- cap 50, FIFO
}
BloodsportsDB.chars[key].bets      -- history, cap 200 (MAX_RECORDS): v1 records unchanged, v2 records { v = 2, id, t,
                                   --   role, host, venue, currency, series, markets = { [mid] = { kind, mode, result,
                                   --   pools, bets (host) | bet (bettor) } } }
BloodsportsDB.chars[key].trades    -- cap 200, moved to Ledger.lua, shape above
```
- Version: `ring.v = 2`. Readers treat a `bets[]` record with no `v` as v1 (one implicit market `m1`, winner, pari,
  `side` → outcome). `Ring.PointsBalance` sums both shapes.
- Migration: `CHAR_DEFAULTS` gains `ring` (`U.EnsureShape` fills it). `MIGRATIONS[1]` stamps `v = 1` on existing
  `chars[*].bets[*]` and fills the new `config.ring` keys. v1 never persisted a session, so there is nothing in flight to migrate.
- Resume on login: host session with `now − lastActivity ≤ STALE_SEC` resumes: timers are rebuilt from the timestamps,
  `resolving` markets past `appealUntil` settle now, `disputed` markets past timeout void. Older ones go to `stale`: every
  non-final market voids (`voidReason = stale`), then the session closes. A mirror session resumes as "rejoining" and
  sends `R2Q(sid, 0)`; with no reply in 60 s the UI shows "host offline" and keeps the record.
- WoW writes SavedVariables only at reload/logout. A client crash loses changes since the last write (accepted risk).

### 1.7 Series link

`Series.lua` (P2b) must fire `SERIES_START { id, bo, a, b, champion }`, `SERIES_ROUND { id, round, winner, how }` and
`SERIES_DONE { id, winner, scoreA, scoreB }`. If P2b uses other names, it writes an adapter; Ring does not change.
Ring stores `session.series` and `market.scope`. Fight-scope markets lock at the RF of their round. Series-scope markets
lock at round 1's RF and resolve on `SERIES_DONE`: winner → outcome of `winner`; score → the index of `scoreA-scoreB`.
Outbox rows carry `series = id` and `bo`.

## 2. State machines

### 2.1 Session

| From → To | Trigger | Who |
|---|---|---|
| — → `open` | `Ring.Open(venue)`: v1 guards (enabled, referee flag, group leader) | host |
| `open` → `closing` | `Ring.Close()` while a market is `resolving`/`disputed`: no new markets or bets | host |
| `open`/`closing` → `closed` | every market final, plus Close, or idle `STALE_SEC` | host / timer |
| any → `stale` → `closed` | resume finds it too old (§1.6) | login |

Close voids every non-final market (`voidReason = close`) and every open dispute. Debts survive in `ring.debts`.

### 2.2 Market

| From → To | Trigger | Who / timeout |
|---|---|---|
| `draft` → `open` | `OpenMarket(mid)`: ≥ 2 outcomes; fixed needs every price plus a bank | host |
| `open` → `locked` | `Lock(mid)`; RF from a fighter (`lockOn = fight`); `lockAt` reached; `OPEN_MAX_SEC` | host / fighter / timer |
| `open`/`locked` → `resolving` | `Verdict(mid, idx)` or auto verdict (duel message, `SERIES_DONE`): compute payouts (§3), void unpaid gold, `appealUntil = now + 600` | host / auto |
| `resolving` → `settled` | `appealUntil` passed with no dispute: outbox `bet` rows written **now**, debts created, payouts unlocked | timer |
| `resolving` → `disputed` | valid R2D before `appealUntil` (§2.3) | bettor with a counted bet in the market, or a fighter |
| `disputed` → `settled` | `uphold` (same result) or `amend(idx)` (recompute; settles at once, no new window) | host (final say) |
| `disputed` → `void` | `void` action, or `DISPUTE_TIMEOUT_SEC` passes with no action | host / timer |
| `draft`/`open`/`locked`/`resolving` → `void` | `Void(mid)`; session close; stale | host / close |

`void` refunds every counted stake (gold: paid stakes only). A void after a verdict sets `afterVerdict = true` on the
ring row: the site counts these per bookie (conflict-of-interest signal, §9). v1 auto verdict settled at once; v2 auto
verdicts also pass through `resolving`.

### 2.3 Dispute / appeal

- Window: `verdictAt ≤ now < appealUntil` (host clock, `U.ServerTime`). Anything later is ignored and answered `R2X late`.
- Codes: `wrong` (wrong winner), `early` (verdict before the end), `foul`, `other`. Note ≤ 80 bytes. One R2D per sender
  per market. The first valid one moves the market to `disputed`; later ones are recorded in `dispute.extra` (cap 5).
- While `disputed`, payouts stay provisional and no payout trade matches the market.
- Resolution actions: `uphold | amend(idx) | void`. The host's choice is final, with no second appeal. The ring row
  `dispute_resolved` records it. If an amend changes a fight winner, the host emits `verdict_amend` (§5.2).

## 3. Odds math (integers only; Lua and TS must agree to the copper)

### 3.1 Counted stakes

A bet counts when `currency == "points"` or `paid == true` at verdict time (v1 `countsInPool`). Pool `P[k]` = Σ counted
stakes on outcome k, `T = Σ P[k]`, winner pool `W = P[r]`, loser pool `L = T − W`.

### 3.2 Parimutuel payout (deterministic, no rake)

```
pari(bets, r):                      -- r = winning index, or nil for void
  if r == nil or W == 0: payout(b) = b.amount for every counted b      -- refund all
  else: q = floor(L / W); rem = L − q*W
        payout(b) = b.amount + q*b.amount + floor(rem*b.amount / W)   if b.outcome == r and counted
                  = 0                                                 otherwise
  dust = T − Σ payout                  -- 0 ≤ dust < (#winning bets); kept by the referee, recorded in market.dust
```
- **Remainder rule: floor per winning bet; the dust stays with the referee.** This is v1's tested behaviour ("dust stays
  with the host"), it does not depend on bet order, and it is bounded below 30 copper.
- Overflow: `rem < W ≤ 30 × 2e6 = 6e7` and `amount ≤ 2e6`, so `rem*amount < 1.2e14 < 2^53`. That is exact in Lua
  doubles and in JS `Number`. The q/rem split is v1 `share()`; keep it, and never compute `L*amount` directly.
- Only one outcome has bets → winners get their stakes back (L = 0). Nobody on the winner → full refund (W = 0).

**Worked example** (bo3 score market, gold, all paid). Ann 12 g on o1 "2-0", Bob 5 g on o1, Cid 7.5 g on o2, Dee 3g33s33c
on o3, Eve 21 g on o4. Result o1.
`T = 120000+50000+75000+33333+210000 = 488333`, `W = 170000`, `L = 318333`, `q = 1`, `rem = 148333`.
Ann: `120000 + 1·120000 + floor(148333·120000/170000) = 120000+120000+104705 = 344705` (34g 47s 05c).
Bob: `50000 + 50000 + floor(148333·50000/170000) = 50000+50000+43627 = 143627`.
Σ = 488332, **dust = 1 c** to the referee. Cid, Dee, Eve: 0.

### 3.3 Fixed odds (bookie = host posts a price per outcome)

- `price` is an int ×100 (180 = 1.80), 101..1000. It can change only while the market is `open`. Each change bumps
  `rev` and re-broadcasts R2O. The price locks into the bet when the bet is accepted.
- Payout: win `floor(amount × price / 100)` (stake included); loss 0; void/unpaid → refund the paid stake only.
- **Liability** (worst case for the bookie if outcome k wins, counting unpaid bets safely):
  `Lk = Σ_{accepted bets on k} (payout − amount) − Σ_{paid bets not on k} amount`.
- **Cover rule:** accept a new bet on k (counted as unpaid) only if `Lk_after ≤ bank`. Other outcomes' liabilities cannot
  rise when a bet is added, so only k is checked. Max stake on k: `smax = floor((bank − Lk) × 100 / (price − 100))`,
  then `min(smax, cap, band, ceiling)`. R2X `bank` returns `smax`.
- `bank ≤ BANK_MAX(level)` is checked at OpenMarket. Bank vs `GetMoney()` is a client-side check, shown as "bank 25g
  (self-declared)".

**Worked example** (winner market, o1 = 1.80, o2 = 2.10, bank 25 g; each accepted bet is paid before the next arrives):

| Bet | L1 after (g) | L2 after (g) | Verdict |
|---|---|---|---|
| Ann 20 g on o1 (pays 36) | 16 − 0 = 16 | 0 | accept |
| Bob 30 g on o2 (pays 63) | 16 | 33 − 20 = 13 | accept |
| Cid 50 g on o1 (pays 90) | 16 + 40 − 30 = 26 | 13 | **refuse `bank`, max 487500 c** |
| Cid 45 g on o1 (pays 81) | 16 + 36 − 30 = 22 | 13 | accept |

Check: `smax = (250000 − (160000 − 300000)) × 100 / 80 = 487500`, giving `L1 = 250000` = bank exactly.
If o1 wins: stakes collected 95 g, payouts 36 + 81 = 117 g, so the bookie's net is −22 g = L1.

### 3.4 Acceptance (`refusal()` v2, shared by the slip and the host)

Order of checks; the first failure is the R2X code: `closed` (market not open), `dup` (bettor already in this market),
`fighter`, `full` (30 bettors), `amount` (< min or > cap), `band` (gold, > `Ring.Band(host)`), `price` (fixed: R2B
price ≠ current), `bank` (fixed cover rule), `money` (bettor-side only, `GetMoney`).

### 3.5 Bookie cannot cover

1. Prevented at acceptance by the cover rule and `BANK_MAX`. 2. After `settled`, unpaid payouts are **debts**: partial
payments are allowed (§6), and there is no pro-rata and no netting against new stakes. 3. Debts follow §5.5:
due → owes after grace → visible on the site; bettors keep the existing `up|scam` rating. 4. A referee void after the
verdict is allowed (final say) but is logged with `afterVerdict = true`.

## 4. Wire protocol

### 4.1 Transport

| Path | Carries | Notes |
|---|---|---|
| Group (`PARTY`/`RAID`, `comm:Broadcast`) | R2S, R2M, R2O, R2L (accepted bets), v1 RS/RL | as v1 |
| `WoMRing` hidden channel (`CHANNEL`, MK.Lobby join pattern: `JoinChannelByName`, retry ×4, never required) | R2A, R2S, R2M, R2O | joined when `config.ring.channel`; sender must equal the session host |
| Whisper | R2B, R2X, R2D, R2Q, R2J, RF, own R2L, watcher fan-out | fallback when the channel cannot be joined (slot limit, chat lockdown) |
| Raid | host "Form raid" converts the group; "Invite" invites the queued R2J senders | invites go out from the button click (hardware event); auto-invite **queues**, the HUD shows "Invite 3" |

The host accepts R2B/R2D/R2Q/R2J from outside the group when `session.public`. v1 `inGroup(sender)` stays the rule
for private sessions. Mirrors accept host messages on group, `CHANNEL` (when the channel name is `WoMRing`) or whisper,
but only from `session.host` (the first R2S/R2A seen fixes the host, as v1 does).

### 4.2 Messages (prefix `BSPT`, tab-separated, every field a string, ints as `%.0f`)

| Type | Dir | Fields (in order) |
|---|---|---|
| `R2A` | host → channel, ≤ 1/10 s, every 60 s while open | `v`, `sid`, `venue`, `currency`, `status`, `nMarkets`, `nBettors`, `cap`, `bo`, `raid(0/1)` |
| `R2S` | host → group/channel/watchers | `v`, `sid`, `status`, `venue`, `currency`, `cap`, `seriesId`, `bo`, `nMarkets`, `rev`, `flags` (`public`,`raidOpen`,`autoInvite` as "101") |
| `R2M` | host → same | `sid`, `mid`, `kind`, `scope`, `mode`, `status`, `nOutcomes`, `result`, `fight`, `lockAt`, `appealUntil`, `bank`, `rev`, `title` |
| `R2O` | host → same, one per outcome | `sid`, `mid`, `idx`, `label`, `pool` (counted), `n` (bettors), `price` (0 pari) |
| `R2B` | bettor → host whisper | `sid`, `mid`, `idx`, `amount`, `price` (seen; 0 pari), `nonce` |
| `R2X` | host → bettor whisper | `sid`, `mid`, `nonce`, `code` (§3.4 + `late`, `flood`, `market`, `version`), `max` (0 or allowed max) |
| `R2L` | host → group (accept/paid), whisper (own line at verdict/settle, resync) | `sid`, `mid`, `bettor`, `idx`, `amount`, `price`, `state` (`paid`,`void`,`paidOut` as "100"), `payout`, `paidOutAmount`, `rev` |
| `R2D` | bettor/fighter → host whisper | `sid`, `mid`, `code`, `note` |
| `R2Q` | any → host whisper | `sid`, `sinceRev` (0 = full), `what` (`s` state, `l` all lines) |
| `R2J` | spectator → host whisper | `sid` (becomes a watcher; queued for invite when `autoInvite`) |
| `RF` | fighter → host whisper | `sid` (+ optional `round`): v1, unchanged |

Settle traffic: the host broadcasts R2M + R2O (pools). **Every client recomputes its own payout with §3.2**, and the host
whispers R2L only to bettors with `payout > 0` (4/s). If a client's recompute differs from that R2L, the slip shows
"payout mismatch". That is how deterministic math turns into a client check.

### 4.3 Byte budget (255 per message including the type, `Comm:Send` refuses longer)

Names ≤ 48 bytes, labels ≤ 24, titles ≤ 32, notes ≤ 80; truncate on a UTF-8 boundary before sending.
Worst cases (computed at max widths): R2M 130, R2L 112, R2D 110, R2S 102, R2A 78, R2O 67. Any longer build is a bug: the test asserts each message type
at maximum field widths stays ≤ 255.

### 4.4 Flood guards (on top of the Comm guard: 30 msgs / 10 s per sender → 120 s ban; out: 8-token bucket, 1/s; whispers 4/s)

- Host in: R2B ≤ 1 per sender per 2 s; after 5 refused R2B from one sender, ignore that sender for the session (one R2X `flood`).
  R2Q full ≤ 1 per sender per 15 s (v1 resync was 10 s); R2J ≤ 1 per 30 s; R2D 1 per sender per market.
- Host out: R2S/R2M/R2O after bet changes are debounced to one batch per 2 s; R2A ≤ 1 per 10 s. Watchers get a whisper
  on status changes only and poll totals with R2Q.
- Mirror in: lines for unknown sids, revs older than the stored one, or > 30 lines per market are dropped.

### 4.5 Versioning and v1 compatibility

- `v = 2` is the first field of R2A/R2S. A client seeing `v > 2` shows "update Bloodsports" and stays read-only.
  `ns.VERSION` (comm) is unchanged. Unknown types are ignored by both versions.
- v2 host: when `m1` is `winner` + `pari` it also emits v1 RS/RL for m1 and accepts v1 RB for m1 (same validation).
  Old bettors keep working; v1 RB on a fixed or multi market is refused silently (v1 has no R2X).
- v2 bettor facing a v1 host (only RS seen) runs the v1 single-market mirror path.

## 5. Outbox and backend (backend ships first; old rows stay valid)

### 5.1 `bet` row v2 (one per bet at `settled`/`void`, per role as in v1; **points rows now emitted too**)

| Field | Type | Rule |
|---|---|---|
| `schema` | 2 | its absence means the v1 path, unchanged |
| `id` | `sid.mid` | unique per bettor per market; ratings key on it |
| `bettor`, `bookie`, `amount`, `result` (`win\|loss\|void`), `venue`, `t` | as v1 | `amount` gold 10000..ceiling, points 1..1000 |
| `side` | `a\|b` \| absent | present only when `nOutcomes == 2` (`a` = 1) |
| `currency` | `gold\|points` | |
| `market`, `kind`, `mode` | strings | `pari\|fixed` |
| `outcome`, `outcomeCount`, `marketResult` | ints | 1..8, 2..8, 0..8 |
| `price`, `paid`, `payout` | int, bool, int | price 0 for pari |
| `series`, `bo`, `fight` | string, int, int | optional |

### 5.2 `ring` rows v2 (free-form store `ring_events`; all add `v = 2`, `mid`)

`open`(cap, public, series) · `market`(kind, mode, labels[], prices[], bank, fight) · `lock`(fight, count) ·
`verdict` (v1 shape kept: `winner`, `loser`, `auto`, emitted at the verdict so duel verification keeps its 120 s window) ·
`resolve`(result, appealUntil) · `dispute`(by, code) · `dispute_resolved`(action, result) ·
`settle`(result, mode, **pools[]**, prices[], fight, dust, count) · `void`(reason, afterVerdict) ·
`paid`/`payout`(bettor, amount, manual) · `verdict_amend`(winner, loser) · `close`(unpaidOut) ·
bettor side: `received`(bookie, amount), `unpaid`(bookie, amount).

### 5.3 Validation and storage (`logic.ts`, `index.ts`)

- `validateRowData("bet")`: when `d.schema === 2`, branch to a new `validateBetV2`. The v1 branch (amount 100..5e6,
  `side` required) is untouched.
- `screenBets`: gold v2 rows go through **`betRefusal` unchanged** (self bet, non-party reporter, min, ceiling,
  `betBandCopper(level)` from `bookieStates`). Points rows go through a new `betPartyRefusal(reporter, bet)`, which is the
  first two checks of `betRefusal` pulled out; `betRefusal` calls it, so behaviour stays the same.
- Storage: gold v2 bettor-side rows keep the existing `INSERT OR IGNORE INTO bets` (ratings, High Roller and /me/stats
  work unchanged). **New table `bet_lines`** (PK `id, bettor_char`; columns from §5.1 plus `src host|bettor`,
  `account_id`, `check_status`) stores every v2 row, host or bettor, gold or points. This fixes v1's PK `(install, id)`,
  which drops all but one host copy per id. New table `bet_markets` (PK `id`) is filled from `settle` rows:
  bookie, mode, result, pools, prices, fight, settled_at. New table `bet_debts` follows §5.5.
  Points never touch `bets`, `bookie_ratings` or `high_roller`.
- `market` rows: `bankRefusal(bank, level)` (`bank > 10 × betBandCopper(level)`) flags the market `over_bank`. Ring rows
  are never rejected.
- `loadVerdicts` excludes a `verdict` superseded by a later `verdict_amend` with the same `id` + `mid`.

### 5.4 Server recompute (mirror of §3; pure functions in `logic.ts`)

`pariPayout(amount, outcome, result, pools)` (q/rem split, `Math.floor`), `fixedPayout(amount, price)`,
`checkBetLine(line, market) → ok|mismatch|pending|unverified`. Rules: unpaid gold → expect `void`/payout 0; pari → the
expected payout from `bet_markets.pools`; fixed → `fixedPayout` when won. With host lines present, Σ host amounts per
outcome must equal `pools[k]`, else the market is flagged `pool_mismatch`. A line with no market row after 7 days is
`unverified`. A host/bettor disagreement on amount, outcome or payout is `conflict`. Mismatch, conflict and unverified
lines are stored and acked, but kept out of P&L and the bookie board. Vectors: §8.1.

### 5.5 Owes lifecycle (the client shows the same rule locally from `ring.debts`)

| State | Enter when |
|---|---|
| `due` | `settle`/`void` with `payout > 0`, gold, from any `bet` row (host or bettor), deduped `(id, bettor)` |
| `owes` | still open when (a) the bookie settles a later fight (`fight > debt.fight`) **and** `now ≥ settledAt + 600`, or (b) `now ≥ settledAt + 86400` |
| `cleared` | bettor `received` (definitive), or host `payout` rows Σ ≥ amount (`clearedBy = host`), or manual |
| `contested` | the host claims a clear but the bettor sent `unpaid` after the grace ended |

`/data.bloodsports.owes[bookie] = { count, copper, since }`. The site shows the flag, but no level is changed
automatically; levels move only through ratings (`bookieState`, unchanged). The bettor client emits `unpaid` once when
its own copy of the rule reaches `owes` with no receipt. That lets bettor-only uploads surface a debt.

## 6. Ledger integration (`Ledger.lua` owns `TRADE_*` + `PLAYER_MONEY`; Ring exposes `Ring.MatchTrade(tr)`)

Ledger moves v1's recorder into its own module (`TRADE_SHOW` → `TRADE_MONEY_CHANGED` → `TRADE_ACCEPT_UPDATE(1,1)` →
`TRADE_CLOSED` → finalize after 1 s). `confirmed = (PLAYER_MONEY delta == got − gave)`. `CHAT_MSG_MONEY` (loot) inside
the window is subtracted from the delta and never used as evidence. Unconfirmed trades never match.

| Role | Trade | Match (tolerance 0 c, partner = full name, case-insensitive) | Effect |
|---|---|---|---|
| host | got > 0, gave = 0 | the partner's unpaid accepted bets in `open`/`locked` markets of the live session: (1) one bet with `amount == got`, oldest first; else (2) Σ of all of them `== got` | `paid = true`, R2L, ring `paid` |
| host | stake trade with no bet yet | kept unmatched with `kind = stake`; re-tried when a bet from that partner is accepted within 120 s | late match |
| host | gave > 0, got = 0 | the partner's outstanding payouts in `settled`/`void` markets (live session, `last`, `debts`): (1) one bet's outstanding `== gave`, oldest settled first; (2) Σ outstanding `== gave`; (3) `gave <` Σ → partial, oldest first; (4) `gave >` Σ → cover all, excess unmatched | `paidOutAmount +=`, `paidOut` when full, R2L, ring `payout`, debt updated |
| host | got > 0 and gave > 0 | impossible (`ERR_CANT_TRADE_GOLD`) | unmatched `reason = both` |
| bettor | gave == own unpaid stake, partner = host | display only (`stakeSent`); the host's R2L is the truth | slip "sent, awaiting host" |
| bettor | got from host == own outstanding payout (or partial) | as the host rule, own bets only | `received`, ring `received` |

Windows: a stake matches from 120 s before acceptance until the verdict. A payout matches only once a market is
`settled` (not `resolving`/`disputed`), with no end until the debt clears. Stake and payout are never netted into one
trade. Unmatched trades go to `ring.unmatched` (with `reason amount|nobet|late|both|excess`). The host's RingTab
"Unmatched" list can **Assign** one to a bet, which sets `manual = true` and adds `manual = true` to the ring row.
Nothing is ever auto-assigned except through the late-match rule.

## 7. UI surface (for the engine/UI lane; not built here)

- **RingTab, host:** session header (status, currency, cap, band `Lv3 · 30g`, channel joined dot, bettors n/30,
  watchers, `Form raid`, `Invite (n)`, `Auto-invite` toggle, `Public` toggle); market list + "Add market" form (kind,
  scope, labels, mode, prices, bank with `max 100g` hint, lockOn/lockAt); per-market buttons `Open`, `Lock`, `Verdict ▸
  outcome`, `Void`, dispute panel `Uphold / Amend ▸ / Void` with the countdown; bets table (bettor, outcome, amount,
  price, paid, payout, paid out, flags); **Owed** (debts with grace state `due 7:12` / `OWES`); **Unmatched** with Assign;
  trade instructions ("Trade Ann 34g 47s 05c").
- **RingTab, bettor:** ring browser (group + `R2A` list: host, venue, level, markets, currency); bet slip; my bets;
  `Dispute` (only while `resolving`, countdown `9:41`); "Host owes you 34g 47s 05c".
- **Bet slip fields:** market, outcome buttons with odds pills, amount (gold `g/s` inputs, or points), live prospective
  payout, refusal line from the R2X code (`max 48g 75s` for band/bank), `Place` (disabled while pending), pending nonce state.
- **Odds formats:** pari pill `×2.87 est · 34%`: decimal `T'/W'` and implied `floor(100·W'/T')`, where T' and W' include
  the slip's stake; `—` with "first bet sets the odds" when W = 0. The estimate uses §3.2 on the hypothetical pool and
  is labelled `est` until lock. Fixed pill `1.80 · 55%` (`price/100`, implied `floor(10000/price)`). Money `34g 47s 05c`
  (copper shown only when non-zero); points `350 pts`.
- **RingHUD:** current market, pills per outcome (max 4 shown + `+n`), lock or appeal countdown, my bet + payout, an
  owed alert, `Invite (n)` for hosts.

## 8. Test plan (`tests/run.sh` + `npm test`; existing `test_ring.lua` / `test_bands.lua` must stay green unchanged)

### 8.1 Mirror vectors (canonical here; copied verbatim to `bloodsports/tests/fixtures/payout_vectors.lua` and `wom-backend/tests/fixtures/payout_vectors.json`)

| Id | Counted stakes `name:outcome:amount` | Result | Expected payouts | Dust |
|---|---|---|---|---|
| V1 | A:1:100000, B:2:300000 | 1 | A 400000, B 0 | 0 |
| V2 | A:1:7, B:1:13, C:2:29 | 1 | A 17, B 31, C 0 | 1 |
| V3 | A:1:3, B:1:3, C:2:1 | 1 | A 3, B 3, C 0 | 1 |
| V4 | A:2:100, B:2:250 | 1 | refund A 100, B 250 | 0 |
| V5 | Ann:1:120000, Bob:1:50000, Cid:2:75000, Dee:3:33333, Eve:4:210000 | 1 | Ann 344705, Bob 143627, others 0 | 1 |
| V6 | A:1:10000, B:2:10001, C:3:20000, D:3:33333, E:5:499999, F:6:12345, G:3:7 | 3 | C 219604, D 366003, G 76, others 0 | 2 |
| V7 | A:1:10000, B:2:20000 | void | refund A 10000, B 20000 | 0 |
| V8 | P0..P10 on 1, P11..P29 on 2, each 500000 | 1 | P0..P10 1363636 each, others 0 | 4 |
| V9 | A:1:10000, B:1:10000, C:1:10000, D:2:10000 | 1 | A/B/C 13333, D 0 | 1 |
| F1 | fixed: 12345 at price 215, won | — | 26541 | — |

### 8.2 New Lua files

| File | Cases |
|---|---|
| `test_payout_vectors.lua` | V1–V9 through `Ring.ComputePayouts` v2 (and v1's 2-way path for V1–V4) |
| `test_ring_markets.lua` | 3 markets in one session; a multi-outcome settle (V5 via wire bets); one bet per market (`dup`), the same bettor in 2 markets; 8-outcome cap; method market auto-resolve from `DUEL_WINNER_RETREAT`; score market from `SERIES_DONE` (bo3 and champion bo5); RF locks only `lockOn=fight`; `OPEN_MAX_SEC` auto-lock |
| `test_ring_fixed.lua` | price locks at acceptance; R2B with a stale price → R2X `price`; §3.3 table (Cid 50 g refused `bank` with max 487500; 45 g accepted); bank > `BANK_MAX` refused at Open; settle payouts; bookie short → debts `due` → `owes` after a later fight + 600 s; partial payout |
| `test_ring_persist.lua` | host `/reload` while open: session, bets, rev and timers restored, bets still accepted; reload during `resolving` past `appealUntil` → settles on login, outbox rows once; > `STALE_SEC` → void + close; mirror reload → R2Q resync; v1 `bets` records read by `PointsBalance` alongside v2 |
| `test_ring_channel.lua` | R2A on `CHANNEL` fills the browser; a non-group spectator's R2B accepted on a public session and refused on a private one; whisper fallback with the channel unjoined (watchers get R2S); 31st bettor `full`; flood: the 6th refused R2B silences the sender; a v1 RB on winner/pari m1 is accepted and RS/RL still emitted; every message type at max widths ≤ 255 bytes; `v=3` R2S → read-only |
| `test_ring_dispute.lua` | R2D in the window → `disputed`; after the window → R2X `late`; second disputer logged only; uphold → settled; amend → recompute + `verdict_amend`; void → refunds, `afterVerdict`; 30 min with no action → auto-void; no outbox `bet` rows before `settled`; no payout matching while disputed |
| `test_ledger_match.lua` | stake exact single; stake = Σ two bets; ±1 c → unmatched `amount`; pre-bet trade late-matched within 120 s, not at 121 s; payout exact / Σ / partial / excess; unconfirmed delta never matches; got+gave both → `both`; Assign sets `manual`; bettor-side `received` row; loot `CHAT_MSG_MONEY` inside the window does not break `confirmed` |

### 8.3 Backend (`wom-backend/tests/bets_v2.test.ts`)

v2 row accepted and v1 rows still accepted with identical results; bad v2 fields rejected (outcome 9, outcomeCount 1,
price 100, schema-2 points amount 1001); `pariPayout` = V1–V9 and `fixedPayout` = F1 from the JSON fixture; gold v2 band
refusal through `betRefusal` (level 1, 15 g refused); points rows skip bands, never reach `bets`/ratings/High Roller;
`bet_lines` keeps every host line (30 lines, 1 id); `mismatch` / `pool_mismatch` / `conflict` flags; owes:
due → owes via a later fight + 600 s, via the 24 h backstop, cleared by `received`, cleared by host `payout`, `contested`;
`verdict_amend` supersedes in `loadVerdicts`; `/data.bloodsports.owes` shape.

## 9. Risks and open questions (default chosen; change only by owner decision)

| # | Question / risk | Default |
|---|---|---|
| 1 | Who keeps the remainder? | the referee keeps the dust (< 1 c per winning bet), recorded per market. Matches v1 tests |
| 2 | House rake? | none |
| 3 | Separate bookie vs referee roles | one role (host) in 1.1; a split bookie role is a 1.2 extension (`MK.Ext` market type) |
| 4 | Bank is self-declared (`GetMoney` is client-side) | shown as "self-declared"; cover rule + `BANK_MAX` + owes flag + scam ratings |
| 5 | Referee conflict of interest (final say, can void after a verdict) | allowed; `afterVerdict` voids counted on the bookie board |
| 6 | Host offline during the appeal window | settles at the next login (≤ 2 h), else stale-void; debts persist; owes backstop 24 h |
| 7 | `InviteUnit` may need a hardware event | auto-invite queues; invites go out from the host's click (`Invite (n)`) |
| 8 | Channel slot limit / chat lockdown | whisper fallback (R2J watchers); the channel is never required |
| 9 | Points balance authority | the site owns the balance (`/data` snapshot); the client caps at min(1000, the known balance); the server floors at 0 and flags overspend, never rejects in QA |
| 10 | Release default currency | `gold` (current `Core.lua`); QA builds set `points` first |
| 11 | Payouts wait 10 min (window) | intended: 1-fight grace runs from `settled`, the next fight fills the wait |
| 12 | 200 g ceiling (1.2) | constants are named; §3.2 overflow bound holds to 2e6 c stakes |
| 13 | Clock trust | host `GetServerTime` for every deadline; mirrors display the host's values |
| 14 | Crash between reloads | a live session's changes since the last SV write are lost; accepted |
| 15 | `Series.lua` event names unknown yet | §1.7 names are the contract; P2b adapts |
