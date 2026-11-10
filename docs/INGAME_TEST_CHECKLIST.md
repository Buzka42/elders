# In-game test checklist — Bloodsports v1.1.0 (feat/wom-1.1)

Owner involvement needed for steps marked 👤. Everything else is done/verified headless + by screenshots.
Build installed: v1.1.0 zips + client copy current as of last push. Reset referee off before start: `/bs referee off`.

## Before you log in
- [ ] Machine healthy? GPU cap 130W + core underclock are in `game-mode.sh`; if it hard-resets again, PSU swap is the fix, not the addons.

## Solo (5 min, any venue)
- [ ] 👤 `/console scriptErrors 1`, `/reload` → no Lua error popups.
- [ ] `/bs` → all 5 Bloodsports sections render; `/elders` → Overview renders with RECENT LEVELS card.
- [ ] Corner icon: template portrait (no M medallion); sidebar: no watermark.
- [ ] `/bs venue` prints the venue you're standing in (Crossroads = "Crossroads Duel Practice" expected).

## Ring stress test — needs a ring venue 👤
Venues: **Ratchet** (Crossroads zeppelin), Everlook, Gadgetzan, Booty Bay.
- [ ] 👤 Stand inside the Ratchet ring box; `/bs venue` → "Ratchet Goblin Ring".
- [ ] 👤 Become referee → Open the ring → session opens, HUD appears.
- [ ] 👤 Create `winner` market (pari) + `winner` fixed-odds market + `series` market (Best of 3 → Series winner).
- [ ] 👤 Second toon bets 10g on A, 5g on B (pari) and 5g fixed on A.
- [ ] 👤 Settle winner A → payouts: pari your 10g wins its share; fixed pays per odds; check Ledger "owes" rows + Narrator chat lines.
- [ ] 👤 Dispute the verdict (dispute action) → payout blocked → uphold → payout completes. Watch Narrator: disputed/upheld lines.
- [ ] 👤 Void a market → stakes refunded.
- [ ] 👤 Trade payouts; Ledger auto-books; unmatched list empty (or Assign works for a stray trade).
- [ ] Series: start bo3, play/void rounds → series market settles once at series end; voiding twice voids the series AND refunds its markets.
- [ ] Referee non-fighter: second account referees, fighters fight a series → referee's Ring tracks score via relay.

## Ship decisions (yours)
- [ ] Merge `feat/wom-1.1` → master (elders, bloodsports, wom-backend).
- [ ] Deploy backend: run `schema_betting_v2.sql`, then deploy Worker.
- [ ] Flip site `bloodsports.json` from `coming_soon`.
- [ ] Rules calls: series streak per-round vs per-series; keep m1 bet-id (`sid`) or fix to `sid.m1`.
