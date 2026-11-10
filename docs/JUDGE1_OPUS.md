# JUDGE1 — Opus visual QA verdict

Source: `docs/baseline/judge1/01_duels.png … 06_elders.png` (1920×1080, window rect ≈ x480–1440, y215–862, so 960×647).
Reference: Talents Forever (PortraitFrame shell, gold plates, Cinzel title) and Overlord (achievement metal, light parchment sidebar, dense lists).
Method: full-frame look, then 2–4× nearest-neighbour crops of each region. Contrast is WCAG ratio from the darkest or brightest glyph pixel against the sampled local background. Column extents come from a pixel-run scan of the header rows. All coordinates below are full-res game-screen pixels.

---

## 0. Capture validity: 4 of 6 shots show the wrong page

I diffed only the window rect (480,215 → 1428,862) and the sidebar, main-pane and tab sub-rects of each shot against `01_duels.png`:

| shot | expected page | page shown | window-rect diff |
|---|---|---|---|
| 01_duels | Ring idle (per brief) | Bloodsports › The Ring | n/a (base) |
| 02_matches | Matches | **Bloodsports › The Ring** | mean 0.00, no changed pixels |
| 03_finder | Finder | **Bloodsports › The Ring** | mean 0.00, 1 px column at the frame edge (world bleed) |
| 04_clubs | Clubs | **Bloodsports › The Ring** | mean 0.00, 1 px (world bleed) |
| 05_ring | The Ring | Bloodsports › The Ring | mean 0.00, identical |
| 06_elders | Elders tab | **Bloodsports › The Ring, Bloodsports tab active** | mean 0.00, 12×1 px at the top edge (world bleed) |

The whole-image RMSE differences between the shots (bottom band ~28) are the chat log scrolling and NPCs moving. The addon window did not change.

- In all six shots the cursor (gauntlet) sits on the **Elders** tab at ≈(925–945, 330–345), but the Elders tab never activated. Either the clicks were not delivered (focus, or the click fired before the move landed) or the tour ran its clicks somewhere else and parked the cursor here afterwards.
- `TOUR_STEPS` in `tools/uicheck/uicheck.py` is calibrated for a **960×600** window. The window is now **960×647**, so every sidebar step is off. Measured targets from this capture (game-screen px):
  - My Duels (565, 386) · Matches (565, 412) · Finder (565, 438) · Clubs (565, 464) · The Ring (565, 491)
  - Tab Bloodsports (792, 329) · Tab Elders (905, 329)
- **Consequence:** Matches, Finder, Clubs and the Elders tab (including the owner's "per-tab logo swap" request) are **unjudged**. No score is given for 02/03/04/06. Recapture with the cursor parked off-window (for example at (1700, 1000)) before the final shot of each step.

The only page judged below is **Bloodsports › The Ring (idle)**, which appears in 01 and 05.

---

## 1. Verification of the owner complaints believed fixed

| complaint | verdict | evidence |
|---|---|---|
| Medallion fit | **Fixed (fit). One minor leftover.** | The "M" art is masked inside the gold ring, centred, with a clean circular edge and no overrun into the ring. Leftover: the glyph is scaled to 100% of the socket, so the M's top points and feet are cut by the mask. |
| Sidebar header | **Present but not acceptable.** | "BLOODSPORTS" renders in dark-red Cinzel with a gold rule under it, but measures **2.8:1** on the parchment (fg ≈ (65,29,8), bg ≈ (137,100,40)). It also repeats the logo and the active tab (see R-8). |
| Crest badges removed | **Confirmed.** | No crest badges anywhere on the Ring page. |
| Per-tab logos | **Unverifiable.** | The Elders shot shows the Bloodsports tab (§0). The Bloodsports logo itself is excellent. |
| Referee/open clipping | **Referee not clipped. Open control absent.** | "Become referee" box and label are fully visible: box ≈(1157–1175, 357–375), label 1184–1277, with 141 px clear to the pane edge. No "Open ring" or host control appears anywhere on the page. This may be correct venue gating (The Barrens is not a ring venue). Confirm at a venue before calling it fixed. |

---

## 2. Per-shot scores and flaws

### 01_duels.png: Ring idle (valid as Ring). **Score 6.0 / 10**
Sidebar-only score: **4.5 / 10**. Main pane: **6.0**. Chrome and title: **8.5**.

**Title band and chrome**
1. **Close button (≈1418–1436, 222–240):** a flat 18 px dark square with a gold X and a 1 px gold border. It reads as a web modal, not Blizzard. Severity: **minor**. Fix: use the template's own `CloseButton` (PortraitFrameTemplate) or `UIPanelCloseButton`, anchored TOPRIGHT (+4, +5) on the frame border.
2. **Medallion:** the M glyph is cropped top and bottom by the circular mask because the art fills the socket edge to edge. Severity: **taste**. Fix: draw the art at ~82% of the socket's measured width, keep the mask and centring.
3. **Title band (y≈222–315, about 93 px):** the logo is centred. The 260 px to its left and the 270 px to its right are bare dark band, and the band is nearly twice the reference title height of ~50. Severity: **taste**. Fix: leave the logo alone. Optionally put a gold-dim subtitle or version line right-aligned at (-40, -40) so the band isn't dead.
4. **Bottom-left corner ornament (≈480–535, 800–860):** the gold filigree is dim, half-buried under the frame border, and bleeds onto the parchment corner beside "Sync now". It reads as a clipping accident. The top corners have no ornament (medallion and close button sit there). Severity: **minor**. Fix: draw on OVERLAY at 48 px, inset +2/+2, brighten its vertex colour to ~1.15; otherwise remove both bottom ornaments.

**Tabs (Bloodsports 738–847, Elders 850–960, y≈318–340)**
5. Active gold plate measures **10.5:1** and inactive **9.7:1**, both good. But the tabs float in the title band: the active tab doesn't merge into the pane's top border, and there's a ~6 px dark seam. Severity: **minor**. Fix: drop the tabs 4–6 px so their bottom edge overlaps the pane border, and hide the pane border under the active tab (Blizzard tab behaviour).
6. The tab strip's left edge (738) lines up with nothing: not the sidebar (495), not the pane content (746), not the logo centre. Severity: **taste**. Fix: anchor the strip's left to the pane content edge (746) or centre it under the logo.

**Sidebar (x≈495–720)**
7. **Nav label contrast fails.** Ink (71,50,19) on parchment ≈(153–169,118–130,46–65) gives My Duels **2.9**, Matches **3.0**, Finder **3.2**, Clubs **3.4**. Severity: **major**. Fix: darker ink alone can't solve it, because this parchment has a luminance of only ~0.21 and pure black caps out at ~5.3:1. Raise the parchment vertex colour about 1.25× (target bg ≈ (205,175,120), as Overlord's `UI-Achievement-Parchment` is), **and** set ink to ≈ (26,16,6). Expected result: ≈8–9:1.
8. **Header "BLOODSPORTS" at 2.8:1.** Severity: **major**. Fix: on the lighter parchment use ink-red #5a120c (darker than token #7a1a12), and set Cinzel Bold at 15 px with a (0.5, -0.5) light highlight shadow (255,235,190,0.35), not a black one.
9. **Selected row "The Ring" (≈498–718, 480–503):** a darker brown band (131,103,56) with a 3 px gold left strip and black text gives **3.75:1**. The selection *reduces* contrast, and the gold strip is near the parchment's own luminance, so it nearly vanishes. Severity: **major**. Fix: make the selected band a lighter cream wash (255,240,200,0.35) with a 1 px dark-gold border top and bottom, ink unchanged, and a dark-red (#5a120c) left strip 3 px wide. Alternative: Overlord-style gold-bordered highlight.
10. **Dead zone of ~216 px (y≈503–716):** 42% of the sidebar height is empty parchment between the last nav row and the stats rule. Severity: **major**. Fix: move the stats block up under the nav with a 12 px gap, and put a "Ring status" summary in the freed space (current venue, referee on duty yes/no, rings nearby count). Or let the parchment end and fill the rest with a footer.
11. **Stats labels at 2.4–3.6:1, the "-" value at 2.1:1** (fg (81,55,23)). Severity: **major**, covered by fix 7. Also show Win rate as "—" in full ink, or "0%", not a faint hyphen.
12. **Nav icons are inconsistent.** Three sit on black squares (My Duels, Finder, The Ring), one on blue (Clubs), one on tan (Matches), none bordered, at 16 px. Severity: **minor**. Fix: 18 px icons, texcoords 0.08–0.92 (Blizzard trim), 1 px dark (40,28,12) border, or a round mask for all five.
13. **"Sync now" button (≈512–708, 812–834):** a flat (36,30,21) bar with a 1 px gold border reads as a web button. The text itself is fine at 12.3:1. Severity: **minor**. Fix: the Talents Forever gold plate recipe (top (1,.86,.42) → bottom (.74,.55,.08), ink (.13,.09,.01)) or `UIPanelButtonTemplate`, at 24 px height.

**Main pane (content x≈729–1418, 690 px wide)**
14. **About 75% of the pane is empty.** The referee list void is y≈421–560 (~140 px) and the rings list void is y≈603–840 (~240 px). The two empty-state lines float in the middle of dark nothing, and there's no footer, so the pane "ends in a void". Severity: **major**. Fix: collapse an empty list to 2 row heights (2×22 px) with the empty text left-aligned in row 1 (GameFontDisable, grey 0.6), then give the freed ~300 px to host controls, a "How the ring works" block, or recent ring results. Add a footer status line at the pane bottom ("0 referees · 0 rings · last scan 12 s ago").
15. **Column widths ignore the pane width.** Referee headers end at x=1101, leaving **317 px (46%) empty**. Ring headers end at 1156, leaving **262 px (38%) empty**. Severity: **major**. Fix, with proportional widths that span 690 px:
    - Referees: [icon 22] Referee 200 · Lvl 40 (right) · Ring 200 · Rating 90 (right) · Seen 100 (right)
    - Rings: Host 170 · Ring 170 · Bookie 120 · Markets 70 (right) · Bettors 70 (right) · Stakes 90 (right)
16. **"Bettors" and "Stakes" headers nearly collide:** Bettors ends at 1117 and Stakes starts at 1126, a 9 px gap. Elsewhere the gaps run 20–60 px. "Lvl"→"Ring" is 20 px and also reads cramped next to the 80 px Referee→Lvl gap. Severity: **major** (it's the most visible spacing flaw on the page). Fix: covered by 15, with a minimum gutter of 16 px.
17. **Three different left edges.** The section headers and helper text start at x=746, the "Referee" header at 772 (a 26 px indent, presumably reserved for a class icon), "Host" at 743, and the divider lines at 728. Severity: **minor**. Fix: one content inset of x=746 for everything. If the Referee table reserves an icon column, show its header as an empty 22 px cell so the first text column still aligns with "Host" by design.
18. **Column headers read as a web table.** They're plain grey-beige text (167,158,143). Contrast is fine at 6.9:1, but the font is small (~10 px cap 7 px) and sits over a single 1 px rule. Blizzard lists use header tabs (WhoFrame or Guild-roster style column buttons) or gold-dim headers inside an inset. Severity: **major** (this is the main source of the "web page" feel). Fix: put each list in `InsetFrameTemplate3` (or a dark inset with a 1 px (61,46,32) edge) and render headers as `WhoFrameColumnHeaderTemplate`-style plates, or at least GameFontNormalSmall in gold-dim (0.84,0.66,0.30) with a 22 px header strip at (0,0,0,0.35).
19. **"Become referee" checkbox (≈1157, 357) floats.** It aligns to neither the pane's right edge (141 px short) nor the content inset. The box is a flat dark square, not the native gold-rimmed check. Severity: **minor**. Fix: `UICheckButtonTemplate` (26 px), anchored TOPRIGHT of the pane at (-16, -10) with the label on its left. Or left-align it under the helper text at x=746.
20. **Section headers ("Referees on duty", "Rings nearby")** are gold, 13.5:1, good, but there's no rule or plate, so the sections run together on the flat pane. Severity: **minor**. Fix: a 1 px gold-dim (138,106,46) rule 4 px under each header, spanning the content width. Or the Overlord header bar.
21. **Helper text "…That puts ya in the ring's layer."** The apostrophe renders with visible space either side ("ring ' s"), which is typical of U+2019 or a straight quote in FRIZQT at this size. Severity: **taste**. Fix: use an ASCII `'` and check the glyph, or reword ("the ring layer").
22. **Empty-state copy** "No referee about. Goblins are on lunch." / "No rings announced nearby." The voice is good, but neither line tells the player what to do next. Severity: **taste**. Fix: add a second grey line, e.g. "Tick *Become referee* to host one." / "Rings appear here when a host opens one within range."

**Whole window (this shot)**
23. **"Bloodsports" appears three times in a vertical stack:** the logo ("BLOODSPORTS" ribbon), the active tab, and the sidebar header. Severity: **minor** (duplicate information). Fix: drop the sidebar header text and let the gold rule plus nav stand alone, or change it to the section group name / player rank ("Duelist · 0-0").
24. **Cursor on the Elders tab in the capture.** This is a confound and covers the "Elders" label. Not a UI flaw, but re-shoot with the cursor parked off-window.

### 02_matches.png: **not scored (wrong page)**
Pixel-identical window to 01 (Bloodsports › The Ring). The Matches page was not captured. Every flaw from 01 applies; Matches-specific layout is unjudged.

### 03_finder.png: **not scored (wrong page)**
Pixel-identical window to 01 (The Ring). Finder was not captured.

### 04_clubs.png: **not scored (wrong page)**
Pixel-identical window to 01 (The Ring). Clubs was not captured.

### 05_ring.png: Ring. **Score 6.0 / 10**
Correct page, identical pixels to 01, so the flaw list is the same as 01 (items 1–24). Not repeated.

### 06_elders.png: **not scored (wrong page)**
It shows the **Bloodsports** tab active with the Bloodsports logo, and the cursor resting on the Elders tab. The tab swap, the per-tab Elders logo, and the Elders sidebar/header are all unjudged.

### Whole window across shots
- Consistency can't be judged: one page captured six times. The chrome is stable (no drift, geometry identical across all six sidecars, `at` 1920,0).
- The dark-pane / parchment-sidebar split is the right Overlord pattern. The parchment, though, is a **mid-tone** (L≈0.21) where Overlord's is light (L≈0.45), and that one choice causes most of the sidebar failures.

---

## 3. Consolidated ranked fix list (severity × visibility)

| # | sev | fix | where |
|---|---|---|---|
| R-1 | **blocker** | Recapture the tour. 4 of 6 shots are the Ring page. Recalibrate `TOUR_STEPS` to the 960×647 window: rows at x 565, y 386/412/438/464/491; tabs (792,329)/(905,329). Confirm focus before clicking and park the cursor at (1700,1000) before each shot. Re-judge Matches, Finder, Clubs and Elders, including the logo swap. | `tools/uicheck/uicheck.py` TOUR_STEPS / tour runner |
| R-2 | major | Sidebar contrast: lighten the parchment to ≈(205,175,120) **and** set ink to ≈(26,16,6). Today nav is 2.9–3.4, stats 2.4–3.6, "-" 2.1; target ≥7. | shell sidebar material + nav/stat font colours |
| R-3 | major | Sidebar header "BLOODSPORTS" at 2.8:1: use ink-red #5a120c on the lighter parchment with a light emboss shadow, or replace the text (see R-11). | shell sidebar header |
| R-4 | major | Column widths span the full 690 px pane with right-aligned numeric columns and a minimum 16 px gutter. Fixes Bettors/Stakes (9 px), Lvl/Ring (20 px), and 38–46% empty right side. | Ring section list column defs |
| R-5 | major | Lists in a native inset with header plates instead of bare text on a 1 px rule. This is the largest "web page" signal on the page. | Ring section (and likely every list section) |
| R-6 | major | Empty lists collapse to 2 rows with the empty text left-aligned; reclaim ~300 px; add a pane footer/status line. | Ring section layout |
| R-7 | major | Selected nav row: switch to a lighter wash with a dark-red strip (selection currently *lowers* contrast to 3.75). | shell nav row selected state |
| R-8 | major | Sidebar dead zone (216 px): pull the stats up under the nav and add a section summary block. | shell sidebar layout |
| R-9 | minor | Unify the content left edge at x=746 (now 728/743/746/772). | Ring section anchors |
| R-10 | minor | "Become referee": `UICheckButtonTemplate`, anchored TOPRIGHT (-16,-10) or left at the content inset. | Ring section |
| R-11 | minor | Remove the triple "Bloodsports" (logo + tab + sidebar header); sidebar header → player rank/record or nothing. | shell sidebar header |
| R-12 | minor | Native close button (template CloseButton / UIPanelCloseButton). | shell |
| R-13 | minor | "Sync now" → TF gold plate or UIPanelButtonTemplate, 24 px. | shell sidebar footer |
| R-14 | minor | Nav icons: 18 px, trimmed texcoords, uniform 1 px dark border or round mask. | shell nav rows |
| R-15 | minor | Tabs overlap the pane top border by 4–6 px with the border hidden under the active tab; section headers get a 1 px gold-dim rule; bottom corner ornaments go to OVERLAY 48 px or get removed. | shell tabs / section header / ornaments |

Taste-only, not in the 15: medallion glyph at 82% scale, subtitle in the empty title band, apostrophe spacing in the helper text, action hints in empty-state copy.

---

## 4. Already 10/10: do not touch

- **The World of Meta / Bloodsports logo art:** crisp, legible at size, centred over the pane, and the crest break-out above the frame reads as intentional. Keep the size and position.
- **Tab plate recipe:** active gold plate with dark ink (10.5:1) and inactive dark plate with cream ink (9.7:1). Only the vertical seat changes (R-15), not the plates.
- **Medallion socket treatment:** mask, centring and no ring overrun are correct now. Only the art scale may change.
- **Outer frame chrome:** stone border, double gold hairlines, stable geometry.
- **Main pane typography on dark:** gold section headers 13.5:1, "Become referee" label 14.9:1, helper text 6.9:1, empty states 8.6:1. Keep these colours.
- **Main pane fill:** dark (26,21,18) with subtle grain (σ≈9). Don't flatten it or brighten it.
- **Empty-state voice** ("Goblins are on lunch"). Add a hint line, keep the line itself.
