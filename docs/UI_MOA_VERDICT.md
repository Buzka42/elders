# UI MoA verdict — it1 judged against Overlord (Leaderboard + Hall of Fame) and Talents Forever

Date: 2026-11-09. Automatic aggregation, no owner input.

## Voices

| Voice | Channel | Status | Score |
|---|---|---|---|
| Kimi K3.1 | opencode-go, `--image` ×4 | **counts** (12,850 chars, `DONE-UI-MOA` present, no fallback strings) | 5.4 |
| Qwen 3.8 Max | opencode-go, `--image` ×4 | advisory (9,212 chars, full format, marker omitted) | 5.5 |
| Gemini Argon 4 | Gemini API ×3 keys → 429 (shared pool); Argon web bridge ×2 → client timeout | **failed, no vote** | — |
| Parent (vision, it1) | local | reference point | 5.0 |

Median of counting/advisory scores: **5.45**. Parent's it2 re-score after iteration 2: 6.5 (sidebar void, flat tabs, flat frame, unnormalized demo money, heading/data hierarchy).

## Converged fixes (agreement ≥2 voices, constraints-clean), ranked

1. **Native nine-slice frame depth** (Kimi #1, Qwen #1 + big bet, Kimi big bet). The flat rectangle is the dominant
   "custom demo" tell. Probe `UI-DialogBox-Border` + Achievement textures; 12–14 px outer band, inset content well,
   18–24 px corners, `UIPanelCloseButton`. Fallback = current chrome. Effort M.
2. **Attached native tabs** (Kimi #3, Qwen #3, parent it2). 30 px tabs overlapping the pane edge, active raised 2 px with
   bottom seam hidden, inactive darker. Probe `OptionsFrameTabButtonTemplate`. Effort M.
3. **Sidebar material + density** (Kimi #4, Qwen #4, parent it2: >50% void). Subdued parchment (probe Achievement
   parchment texture, darken 15–20%), 26 px rows, 16 px icons, 3 px gold selection strip, plus a per-tab summary block
   to kill the void. Effort M.
4. **List grid rhythm** (Kimi #5, Qwen #6, parent it2). 24 px rows, 1 px separators ~55%, zebra fills, 18 px icons,
   3 px selected strip, native scrollbar probe (`UIPanelScrollFrameTemplate`) inside the inset. Effort M.
5. **Spacing grid 4/8/12/16 only** (Kimi #8, Qwen #8). Kill incidental 5/10/18/20 offsets. Effort S.
6. **Stat row discipline** (Kimi #6, Qwen #7/#9). 22 px rows, fixed 60–90 px right-aligned value fields, gold only for
   focal/changed, emerald/ink-red semantic. Effort S.
7. **Button plate system** (Kimi #7, Qwen #5, parent it2). One primary per region (gold), secondaries brown-grey,
   26 px high, pressed state nudges text 1 px. Probe `UIPanelButtonTemplate`. Effort S.
8. **Title compression** (Kimi #2, parent it2). Cinzel ~20–21 px inside the header band, 1 px shadow, native close
   button 24×24 at 4 px inset. Effort S.
9. **Material distribution** (Kimi #9). ~70% near-black stone, ~20% raised brown/parchment, <8% muted gold, <2% bright
   accents; optional 3–4% noise tile only if 11 px text contrast survives. Effort M.

## Kill list (considered, rejected)

- Qwen fixes referencing `Interface\AddOns\Overlord\textures\...` or Talents Forever texture files — ARR violation;
  re-implement from Blizzard assets or original art only.
- Qwen "global textureKit / silent attribute overhaul" (effort L, high risk, unverified API) — dropped.
- Sidebar at 184 px (Kimi) vs current 220/340 — not adopted wholesale; keep compact 220, revisit after the frame lands.
- Any fix needing a texture whose existence is unverified ships "probe first" and keeps the current renderer as fallback.

## Big bet (Kimi's, adopted)

Replace only the outer shell + top tabs + sidebar with the native nine-slice frame and subdued parchment navigation,
leave central content widgets unchanged: in a blind 5-second test at real scale with data masked, ≥8/10 players should
classify the window as Overlord's family. Fewer falsifies it.
