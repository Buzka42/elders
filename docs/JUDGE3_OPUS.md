# JUDGE3: Opus visual QA, round 2

Sources: `docs/baseline/judge3/01_duels … 05_ring.png` (taken 23:53–23:56) and `docs/baseline/judge2/elders.png` (taken 21:23).
Window rect ≈ x476–1440, y212–860 on a 1920×1080 frame. The main-pane list inset is x737–1411, 674 px wide.
Method: full-frame look, 2–5× nearest-neighbour crops, then measurements. Contrast is the WCAG ratio of the 1st-percentile (dark ink) or 99.5th-percentile (light ink) glyph pixel against the median local background. Header column extents come from a pixel-run scan of each header strip. All coordinates are full-resolution screen pixels.

## 0. Capture notes
- **Shots 01–05 are valid and distinct pages**, and the cursor is parked off the window. Good.
- `judge3/06_elders.png` shows **Bloodsports › The Ring** again because the Elders tab click didn't take. That's why Elders is judged from judge2.
- **`judge2/elders.png` predates this round's shell fixes.** It still has the old dark parchment, the old flat close button, the flat "Sync now" button and the bottom corner ornaments. Shell fixes therefore **can't be verified on Elders**. The Elders score below applies to the shot as captured. Recapture Elders (fix list item F-7).
- Empty lists are judged on how the empty state is handled, not on the missing data.

---

## 1. Did the previous fixes land?

| JUDGE1 item | status | evidence (this round) |
|---|---|---|
| R-2 Sidebar contrast | **Fixed** | Nav 8.3–9.3:1 (was 2.9–3.4). Stats labels and values 7.4–7.9:1 (was 2.4–3.6). Ink (33,19,3) on parchment ≈(202,172,118). |
| R-3 Sidebar header | **Improved, passes** | "BLOODSPORTS" in (105,22,13) gives 4.8:1 (was 2.8). That's acceptable for 15 px bold Cinzel. |
| R-7 Selected row | **Fixed** | Cream wash (214,192,146) + dark-red left strip + gold rules top and bottom; text 10.4:1 (was 3.75). The selection now raises contrast. |
| Medallion at 80% | **Mostly fixed** | Top points are now intact. The feet and the right leg's outer edge still touch the inner rim, with no visible margin. Taste only. |
| R-4 Bettors/Stakes gap | **Fixed** | Bettors ends at 1231 and Stakes starts at 1290, a 59 px gap (was 9). Markets→Bettors is 36 px. |
| R-6 Ring empty collapse + footer | **Fixed** | Both lists collapse to two rows (line + grey hint). Footer "0 referees · 0 rings nearby · venue Crossroads Duel Practice" at y≈821, 8.5:1. |
| R-5 Native inset + header strip | **Fixed** | Every list sits in a bordered inset with a black header strip and gold-dim headers (10.6:1). This is the biggest "web page" signal from round 1, and it's gone. |
| R-12 Close button | **Fixed** | Red Blizzard-style X button. |
| R-13 Sync now | **Fixed** | Gold plate, ink 7.8:1. |
| R-14 Nav icons | **Fixed** | Uniform bordered squares, consistent size. |
| R-15 Tabs seat / ornaments / section rules | **Fixed** | The active tab overlaps the pane top border. The strip's left edge (744) now sits on the content edge. Gold rules under section headers. Bottom corner ornaments removed. |
| Helper apostrophe | **Fixed** | Copy now reads "That puts ya in the ring layer." |
| R-8 Sidebar dead zone | **Not fixed, only moved** | Stats moved under the nav, but now there's ≈215 px of empty parchment (y≈585–800) between the stats and "Sync now". |
| R-11 Triple "Bloodsports" | **Not fixed** | Logo ribbon + active tab + sidebar header. Now readable, but still redundant. Taste. |
| R-10 Become referee | **Not fixed** | Still a flat dark square, floating 130 px short of the pane's right edge, and its centre sits ≈3 px below the "Referees on duty" baseline. |
| Win-rate placeholder | **Improved, still faint** | Sidebar "—" is 3.2:1 (was 2.1). Everything around it is 7.4–7.9. |

---

## 2. Per-page scores

| page | score | headline |
|---|---|---|
| 01 My Duels | **7.0** | Solid primary-list page. Truncated headers and stats that duplicate the sidebar. |
| 02 Matches | **6.0** | Clean structure, but **no empty state in either table**. |
| 03 Finder | **4.5** | **Header labels overlap each other** (blocker), no empty state, controls float. |
| 04 Clubs | **5.5** | Club dropdown text **wraps and overflows its box**, and there are no empty states. |
| 05 The Ring | **7.5** (was 6.0) | Most of round 1 landed. What's left is alignment and the void below the lists. |
| Elders (judge2, stale) | **6.0 as captured** | The main pane is strong (~8). The pre-fix sidebar drags it down (header 1.9:1, selected row 3.2:1, stats 3.1:1). Duplicate Sync control. |

---

## 3. Flaws by page

Severity: **blocker** (broken rendering) · **major** (visible to every user) · **minor** · **taste**.

### Shared shell (applies to all Bloodsports pages)
S1. **Sidebar dead zone ≈215 px** (x500–720, y≈585–800), about 40% of the sidebar. **Major.** Fix: add a per-page context card under the stats, with a gold-dim header and the same rule style as the nav. Suggested contents:
   - Duels: last 3 results
   - Matches: best/worst matchup
   - Finder: "Listed: no · last scan —"
   - Clubs: your club standing
   - Ring: venue + referee on duty

   Each card needs its own grey empty line. Alternatively, end the parchment after the stats and run a dark footer band down to "Sync now".

S2. **Four button styles** across the pages. **Major** (consistency). The four:
   - gold plate: "Sync now"
   - gold-outline dark: "Challenge"
   - grey-outline dark: "Export", "Scan"
   - flat dark: Elders "Sync / Export / Settings"

   Fix: two tiers only, both at 22 px height. Primary actions ("Sync now", "Challenge", "Scan") get the gold plate. Secondary actions ("Export", "Settings") get one dark plate with a 1 px gold-dim (138,106,46) border.

S3. **Dropdowns use an 8 px glyph** at the right edge instead of a dropdown arrow button (Duels "All venues", Finder ×2, Clubs). **Minor.** Fix: an 18 px arrow button (UIDropDownMenu arrow art) flush right inside the box, with the text inset 8 px.

S4. **The first-column inset differs between pages.** The first header sits at x750–751 on Duels, Matches and Clubs, but at 777–779 on Ring and Finder (a reserved, unlabelled 26 px icon cell). **Minor.** Fix: if a table has an icon column, the icon cell is 22 px and every text column, the empty-state line included, starts at the same x. On Ring, the empty text sits at 750 while the headers start at 777 (see R2).

S5. **Footer status line only on Ring.** **Minor.** Fix: give every Bloodsports page the same footer at y≈821. For example:
   - Duels: "0 duels · venue: All"
   - Matches: "0 duels analysed"
   - Finder: "Not listed · last scan —"
   - Clubs: "Honor Road Fight Club · 0 champions · 0 open challenges"

S6. Win-rate "—" at 3.2:1. **Minor.** Fix: draw it in full ink (33,19,3), or show "0%".

S7. Triple "Bloodsports" (logo, tab, sidebar header). **Taste.** Fix: change the sidebar header to the player record or rank ("Duelist · 0-0"), or drop the text and keep the gold rule.

S8. Medallion feet and right leg touch the inner rim. **Taste.** Fix: scale the art about 5% further down, or nudge it 1 px up.

### 01 My Duels: 7.0
D1. **Truncated headers "Ve…" (1113–1133) and "1st blo…" (1271–1311)**, even though Opponent→Ve… is a 228 px gap and there are 60 px free right of "Seal". **Major.** Fix: redistribute the 674 px:
   - Result 70
   - Opponent 200
   - Venue 130
   - Time 60 (right-aligned)
   - HP left 60 (right-aligned)
   - First blood 80
   - Seal 50

   Use 16 px gutters and full labels. Rule: a header may truncate only when the column total really exceeds the inset width.

D2. **Duplicated stats.** The pane strip "Record 0-0 · Win rate - · Streak 0 · Best 0" repeats the sidebar block "Record / Win rate / Streak / Best streak" on the same screen. The labels disagree ("Best" vs "Best streak") and so do the dashes ("-" vs "—"). **Major.** Fix: make the strip filter-scoped ("All venues: 0-0 · 0% · streak 0"), so it changes with the venue dropdown and earns its place. Otherwise remove the strip and keep only Export and the dropdown on that row. Use one dash glyph everywhere.

D3. **Control misalignment.** Export is 21 px tall (y349–370) and the dropdown is 23 px (y349–372), so their bottoms are off by 2 px. The 8 px gap between them is tighter than every other gutter on the page (16 px). **Minor.** Fix: both at 22 px, bottoms on one line, 12 px gap.

D4. The empty state is centred in a ≈430 px void. For the page's primary list this is fine and matches the Blizzard pattern. The two-line copy is good, and the hint is in grey at 8.2:1. **No change**, beyond S5 (the footer) anchoring the bottom.

### 02 Matches: 6.0
M1. **No empty state in either table.** "By opponent class" is a 265 px blank inset and "By venue" is a 120 px blank inset, both with only headers. This is the one page where the empty state isn't handled at all. **Major.** Fix: use the Ring pattern, a line plus a grey hint, left-aligned at the first column:
   - "No matchups yet." / "Win or lose a duel and it's tallied here by class."
   - "No venues yet." / "Each venue you duel at gets a row."

M2. **The two stacked tables get fixed heights while empty** (the class table is 2.2× the venue table). **Minor.** Fix: when both are empty, collapse each to header + 2 rows like Ring, then put the S5 footer at the bottom. Restore the heights once data exists.

M3. The numeric columns (Games, W, L, Win %, Avg time) bunch right while Class has 356 px to itself. That's acceptable for a stats table. Check that the numeric columns are right-aligned to their header right edge when data arrives. **Taste.**

### 03 Finder: 4.5
F1. **Header labels overlap and truncate.** They render as "L… · VenueL… · VenueW / Ra… · W./ Ra… · Se…" at x992–1256. At least two labels are drawn on top of others ("Venue" over "L…", "Venue" over "W / Ra…", and a second over "W./ Ra…"). Meanwhile 155 px stay empty right of "Se…". **Blocker.** It looks like column x-offsets are reused or accumulated wrongly, with widths far below label widths. Fix: rebuild the column defs so the offsets are cumulative and the widths sum to ≤674 − gutters. For example:
   - icon 22
   - Name 170
   - Lvl 40 (right-aligned)
   - Venue 150
   - W/L 70 (right-aligned)
   - Rating 70 (right-aligned)
   - Seen 80 (right-aligned)

   Add a debug assert that no header's x-range intersects another's.

F2. **No empty state.** A 400 px blank inset sits under the header. **Major.** Fix: centred, Duels-style: "No duellists listed nearby." / "Tick *List me* to be found, or press Scan to look again."

F3. **The controls float.** **Minor.** The details:
   - The "Note (optional)" input sits mid-row (x≈1046–1265), aligned with nothing.
   - The Scan button's right edge is at 1404, 7 px short of the inset edge (1411).
   - The two dropdowns fill only 263 of 674 px.
   - "Anywhere" has a brighter border than "Duel practice" (a state leak, or inconsistent styling).

   Fix: row 1 is the dropdowns, each 150 px. Row 2: List me, then Note running from 120 px after the checkbox to 8 px before Scan, then Scan flush right at 1411. Use one border colour for all inputs.

F4. "List me" uses the flat dark checkbox, the same issue as Become referee. **Minor.** Fix: use the native gold-rimmed check (UICheckButtonTemplate), 22–26 px.

### 04 Clubs: 5.5
C1. **The club dropdown wraps "Honor Road Fight / Club" onto two lines and overflows the box**, top and bottom (box ≈737–886 × 349–372). **Major.** Fix: widen it to ~230 px, which fits on one line, and make the text single-line with ellipsis (word-wrap off, max lines 1).

C2. **No empty state in "Champions" or "Open challenges".** **Major.** Fix:
   - "No champion holds this club." / "Win a challenge to claim the title."
   - "No open challenges." / "Press Challenge to call out the champion."

C3. Stacked tables at fixed empty heights (Champions ≈235 px, Open challenges ≈120 px). **Minor.** Fix: same collapse rule as M2.

C4. "Challenge" is the only gold-outline button (see S2). Its right edge sits correctly at the inset edge (1411). Keep that anchor.

### 05 The Ring: 7.5
R1. **Void of ≈235 px** between the last list (ends y≈582) and the footer (y≈821). **Minor.** The footer now anchors the pane, so this reads as calm rather than broken. Fix (optional): a "How the ring works" block of 3 grey numbered lines (find referee → accept invite → bet / fight), shown only while both lists are empty.

R2. **The empty text and the column headers don't share a left edge.** The empty lines and helper text start at 750, while "Referee" and "Host" start at 777. **Minor.** Fix: per S4.

R3. **Referee table spacing.** Lvl→Ring is 21 px against Referee→Lvl at 90 px, and 186 px (27%) stays empty right of "Seen". "Ring" sits at a different x in the two stacked tables (936 vs 885). **Minor.** Fix:
   - Referee 180
   - Lvl 40 (right-aligned)
   - Ring 170, starting at the same x as Rings › Ring
   - Rating 80 (right-aligned)
   - Seen 90 (right-aligned)

   Use 16 px minimum gutters.

R4. **"Become referee"** is a flat dark checkbox, 130 px short of the right edge, and ≈3 px below the section header baseline. **Minor.** Fix: native check, anchored TOPRIGHT of the inset (−8, 0) with the label on its left, vertically centred on the "Referees on duty" text.

### Elders (judge2, stale capture): 6.0
E1. **The sidebar shows pre-fix values** in this capture: header "ELDERS" 1.9:1, selected "Overview" 3.2:1, stats 3.1:1. The bottom corner ornaments and the flat close button are still present. **Major, but presumably already fixed by the shared shell.** Fix: recapture and re-judge. The Elders tab click must land (it failed in judge3/06).

E2. **Sidebar dead zone ≈330 px.** There's one nav row ("Overview") and then empty parchment down to the Level/Played/Rank block (y≈400–745). Elders is worse than Bloodsports here. **Major.** Fix: S1. For Elders, the card could hold the bracket summary (current bracket, XP/h, time to next level) or recent level-up times.

E3. **Duplicated control: Sync appears twice**, as the sidebar "Sync now" and the pane-bottom "Sync", next to "Everything is synced" at the top right. **Major.** Fix: remove the pane "Sync" and keep the sidebar gold plate. The bottom row then holds Export and Settings (secondary style, S2), right-aligned to the inset edge.

E4. **Duplicated identity info.** The pane header reads "Aleister Krowley, level 18 · Initiate" and the sidebar reads "Level 18 · Rank Initiate". **Minor.** Fix: keep the pane header, and turn the sidebar block into Played time plus the Elders rank progress ("Initiate → next rank at …").

E5. **The bottom button row is left-packed** (three 150 px buttons ending at x≈1202), leaving ≈210 px empty on the right. **Minor.** Fix: per E3, right-align it.

E6. The "ELDERS" sidebar header repeats the logo and the tab (same as S7). **Taste.**

---

## 4. Consolidated ranked fix list (max 12)

| # | sev | fix | where |
|---|---|---|---|
| F-1 | **blocker** | Finder header overlap: cumulative x-offsets, widths that sum to the inset width, no overlap or truncation, and an overlap assert (F1). | Finder column defs |
| F-2 | major | Empty states for Matches ×2, Clubs ×2 and Finder, using the Ring/Duels line + grey hint pattern with the copy in M1/C2/F2. | Matches, Clubs, Finder sections |
| F-3 | major | Duels column widths: Opponent 200, Venue 130, First blood 80. Full labels, no "Ve…"/"1st blo…" (D1). | Duels column defs |
| F-4 | major | Clubs dropdown ~230 px, single line with ellipsis (C1). | Clubs selector |
| F-5 | major | Remove the stat duplication: Duels strip filter-scoped or removed; one dash glyph; "—" in full ink (D2, S6). | Duels header strip + sidebar stats |
| F-6 | major | Sidebar context card to fill the ≈215 px (Bloodsports) and ≈330 px (Elders) dead zones (S1, E2). | shell sidebar |
| F-7 | major | Recapture Elders after the shell fixes (the tab click must land). Remove the pane "Sync" duplicate, right-align Export/Settings (E1, E3, E5). | uicheck tour + Elders section |
| F-8 | major | Two-tier button system (gold primary, dark secondary), all at 22 px (S2). | shared button factory |
| F-9 | minor | Control row alignment: Duels Export/dropdown heights and gap; Finder Scan flush to 1411 with the Note box spanning the row; Become referee anchored TOPRIGHT and baseline-centred (D3, F3, R4). | Duels, Finder, Ring |
| F-10 | minor | Native check buttons for "List me" and "Become referee"; native dropdown arrows (F4, R4, S3). | shared widgets |
| F-11 | minor | One first-column inset rule, so empty-state text aligns with the first header text (S4, R2). Ring referee column re-spread with a shared "Ring" x (R3). | list builder, Ring defs |
| F-12 | minor | Footer status line on every Bloodsports page; collapse stacked empty tables like Ring (S5, M2, C3). | shell pane footer, Matches/Clubs |

Taste, not in the 12: medallion art 5% smaller (S8), triple Bloodsports/Elders header (S7/E6), "How the ring works" block (R1), numeric right-alignment check (M3).

---

## 5. Do not touch
- **Both logos and the per-tab swap.** World of Meta Bloodsports (red/fire) and Elders (green/gold) are crisp, centred and break the frame deliberately.
- **Tab plates and seating.** Active gold plate with dark ink, inactive dark plate with cream ink, the active tab overlapping the pane border, the strip on the content edge.
- **Sidebar material and ink.** Cream parchment ≈(202,172,118) with ink (33,19,3), 7.4–9.3:1.
- **Selected nav row.** Cream wash, dark-red strip, gold rules, 10.4:1.
- **The "Sync now" gold plate and the red close button.**
- **The list inset and header strip.** Black header band, gold-dim labels at 10.6:1, bordered inset.
- **The Ring empty-state pattern.** Voice line (9.2:1) plus grey action hint, collapsed to two rows. It's the template for F-2.
- **Section headers.** Gold 13.6:1 with the gold-dim rule under them.
- **Ring footer.** Copy and position.
- **Elders stat list and bracket tabs.** Label + grey sub-label, right-aligned values, gold section headers, underline bracket selector, thin gold scrollbar. Overlord-grade density.
- **Main pane fill and type colours on dark.** Helper/footer text 8.5:1, empty text 9.2:1, "Everything is synced" green 8.8:1.
