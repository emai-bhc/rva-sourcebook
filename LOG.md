# LOG.md — dev log

Append-only. Newest entry first.



---

## 2026-10-30 (latest) — `profiles.qmd` and its summary section narrowed to the core three

**What changed:** At the user's request (BHC's target population is Richmond city, Henrico, Chesterfield), `r/pums/pums_profiles.R` now keeps only the seven `puma_core3` PUMAs; the geography total is "Core three" (was "PUMS region") and the outer-ring group is gone. Re-ran the script (validation passes; benchmark vs ACS B25003 owners +0.35%, renters -0.59%). Rewrote the geography callout, bullets, fig-geo levels, and the final callout in `profiles.qmd`; updated the matching section, watch item, and caveat in `summary.qmd`. Both render clean (exit 0, no NA text).

**Numbers that moved:** 381,842 households / 924,266 residents; 40.2% at or below 80% AMI (owners 28.7%, renters 60.3%; was 38.4%). Richmond city 50.9%, Henrico 39.1%, Chesterfield 33.4% (unchanged, whole PUMAs). Only 44.6% of the 84,149 lower-income renters live in the city (was 41.7% of 90,166). Re-verified every fig-alt against the data; fixed stale values (owners above 120% AMI 51%, top-band count about 152 thousand, severe burden 67%/81%, Black householders largest in the three lowest renter bands, owner degree attainment 63%).

**Left open:** Not committed. `rva_ami_pums.rds` and the raw pull still hold all nine PUMAs; `data-notes.qmd` PUMS section still to write.

---

## 2026-10-30 (later) — PUMS scripts re-verified after user fixes

**What changed:** The user added `r/pums/naics_soc_lookup.R`, `data-out/puma_pow.csv`, and reworked `pums_prep.R` (now reads lookups from `data/`, writes `data/pums_rva.rds`). Re-ran `rva_puma.R`, `pums_prep.R`, `pums_profiles.R`: all exit 0. `pums_rva.rds` has 48,802 persons x 215 columns, no all-NA columns. `pums_profiles.rds` is identical (`all.equal`) to the version the pages were built on, so no re-render. Fixed a stale path comment in `pums_prep.R`; TODO and METHODOLOGY no longer call it unrunnable.

**Left open:** `pums_prep.R` has no header block and nothing reads its output; `inventory.qmd` permit wording error; `data-notes.qmd` PUMS section. `renv.lock` was modified outside this work and is not in the commit.

---

## 2026-10-30 — `summary.qmd`, then PUMS `profiles.qmd` (ralph loop) and the summary's income-band section

**What changed:** Added `summary.qmd` (executive summary: at-a-glance table, one section per page, "what to watch" box; every number computed from the page `.rds` files). Then, at the user's request, a PUMS profile pipeline and page: `r/pums/pums_profiles.R` → `data/pums_profiles.rds` (+ two CSVs), `profiles.qmd` (households and residents by AMI band; each band profiled by owner/renter: household type, size, householder age and race, earners, disability, structure, cost burden, resident age/education/employment, medians), a "Lower-income renters carry the cost burden" section and sixth watch item in `summary.qmd`, and navbar entries for both pages. Updated METHODOLOGY.md (PUMS is now in use) and CLAUDE.md (PUMA sets, repo map).

**Design decisions:** The user's `r/pums/` scripts left no profile-ready dataset — `pums_prep.R` writes to `data-in/pums/` and needs lookups that don't exist — so `pums_profiles.R` builds from `pums_raw`/`pums_wgt`/`rva_ami_pums` directly. Profiles use five bands (≤30, 31–50, 51–80, 81–120, >120% AMI; zero/negative income folded into the first) because 8 bands × 2 tenures leave thin cells; the 8-band distribution is kept in `ami_dist`. SEs use the 80 replicate weights, computed in the script so the page never touches them. Vacant/group-quarters rows (`TEN == "b"`, 2,516) are excluded — their income is missing and would otherwise land in "121%+".

**Data surprises:**

- **Geography is not `rr`.** The nine PUMAs cover 465,726 households / 1,140,000 residents; southern localities are out and two PUMAs mix localities. Called out at the top of the page and in the summary. Benchmark vs. ACS B25003 for the core-3 PUMAs (same 2020–2024 window): owners +0.35%, renters −0.59%.
- **38.4% of households are at or below 80% AMI** — 59.8% of renters, 28.2% of owners. Richmond city is 50.9%, but only 41.7% of the region's ≤80% AMI renter households live there.
- **Burden is steep and tenure-split:** 80.3% of ≤30% AMI renters pay half or more of income on housing (owners: 64.4%); the renter–owner gap in 30%+ burden is widest at 31–50% AMI (87.0% vs 54.7%) and closes by 81–120% (16.9% vs 15.2%).
- **Reliability:** counts and medians are all High; of 460 band × tenure shares, 50 are Medium and 9 Low, all small categories (<9.8% of a band; Low <2.5%).
- **Inventory page error found:** its "peak … 76% collapse" line treats 2022's 10,414 (the series high) as the pre-crash peak (~8,400 in 2005). Not fixed (out of scope); logged in TODO. The summary words permits as "bottomed in 2011, series high in 2022".
- **Bugs caught before they shipped:** I had written several alt-text and bullet claims ahead of the numbers and checked them afterward; seven were wrong (e.g. "57% of owners above 120% AMI" is 51.6%; "renters outnumber owners at 51–80%" is 42.6%; "White largest group in every band" fails for the two lowest renter bands; Hispanic renter share peaks at 31–50%, not 51–80%). `geom_text` + `position_stack` labels stacked in the wrong order until an explicit `group` was set; "100%" collided with the next panel's "0%" until `panel.spacing.x` was widened. `p_fmt(x, 0)` NA gotcha hit again in `summary.qmd` (second argument is accuracy).

**Left open:** see TODO "Phase 4b" — inventory.qmd permit wording, dead `pums_prep.R`, `r/pums` script anatomy and hardcoded HUD path/CPI factor, `data-notes.qmd` PUMS section, optional PUMA choropleth. `market.qmd`'s provisional H2s/`fig-alt` and the unrun `bls_wage.R` are untouched. Nothing committed; `r/pums/`, `profiles.qmd`, `summary.qmd`, and `data-out/pums_*.csv` are untracked.

---

## 2026-10-28 — `r/pep_migration.R` and a migration section on the demographics page

**What changed:** Added `r/pep_migration.R` (user request): PEP births, deaths, natural change, international and domestic migration for the 17 `rr` localities, pooled `bhc3`/`secondary4`/`rr17`, and Virginia. Source is the Census `co-est2019-alldata.csv` (2010–2019) and `co-est2025-alldata.csv` (2020–2025) files, cached under `data/cache/pep/`. Outputs `data/pep_migration.rds` (annual + era frames) and two CSVs. Added three H2 sections to `demographics.qmd` after the population-growth section (4 figures, 1 table, a callout), plus a migration bullet in the closing summary. Documented the vintage and partial-year rules in METHODOLOGY.md.

**Design decisions:** The files are used instead of `tidycensus::get_estimates()` because the API returns only a vintage's latest year (probed: vintage 2025 → `year` 2025 only), so a series from it would mix revised and unrevised vintages. The two vintages don't join — the 2019 → 2020 regional step (1,291,900 → 1,316,683) spans the 2020 Census rebase — so annual change is never computed across it and the page compares eras. The 2010 and 2020 components are April–June only (Richmond city births: 765 in 2020 vs. 2,872 in 2021) and are NA. Ran the script myself (two cached CSVs plus one tiny API call, ~7 s) since it isn't a long pull.

**Data surprises:**

- **Natural increase collapsed; migration didn't.** Region: natural change 38,050 over 2011–2019 (4,228/yr) vs. 7,254 over 2021–2025 (1,451/yr); net migration 65,684 (7,298/yr) vs. 65,176 (13,035/yr). Migration share of growth 63% → 90%. 10 of 17 localities had more deaths than births in 2020–2025.
- **Region outgrew Virginia in 13 of 14 years** (all but 2011). 2024 was the peak at +1.47% (19,910 people), driven by a record 10,787 international migrants.
- **Richmond city flipped.** Domestic net migration +5.3 → −1.1 per 1,000/yr; international 2.8 → 6.8. Henrico's domestic is negative in both eras (−0.5, −3.1). Chesterfield and the expansion ring are domestic-driven; the ring's net rate is 18.8/1,000/yr with negative natural change (migration share 106%).
- **14 of 17 localities** had a higher net migration rate in the 2020s; Henrico, Prince George, and Richmond city did not. New Kent (36.6) and Goochland (35.2) lead.
- **Validation:** all component identities hold exactly in both files (Δpop = natural + net migration + residual; net = international + domestic); `rr17` reconciles to its 17 members in all 16 years; 2025 population and net migration match the Census API (Vintage 2025) for all 17 localities.
- **Bugs caught:** `p_fmt(x, 0)` — its second argument is *accuracy*, not digits — rendered a title as "Migration supplied NA of growth" (fixed to `1`); `formattable::percent()` can't mix with a character in `if_else()`. The shell also choked on a long heredoc, so the page patch ran from a script file.

**Left open:** `acs_market.rds` now exists (the user rendered all pages), so the Phase 4 loop's real `market.qmd` verification can proceed. `bls_wage.R` TODO items (blscrapeR install) untouched. Not committed.

---

## 2026-10-28 — Phase 4 loop, iteration 1: `market.qmd` drafted (render blocked on `acs_market.R`)

**What changed:** Replaced the `market.qmd` stub with a full page: ownership by geography and window (`fig-ownership`, `tbl-tenure`), real-dollar median home value and rent (`fig-value`, `fig-rent`, `tbl-medians`), price-to-income and rent-to-income ratios (`fig-pti`, `fig-rent-share`), and cost burden by tenure (`fig-burden-trend`, `tbl-burden`, `fig-burden-locality`), plus reliability, ratio-caveat, burden-definition, and summary callouts. Titles and bullets for the home-value, rent, and ratio sections are built from computed values (`chg_phrase()` picks "rose"/"fell" from the data), so they can't contradict the numbers while the real data is unseen.

**Verification:** `data/acs_market.rds` does not exist yet, so the real render did not run. The page code was exercised end to end against a **mock** `acs_market.rds` kept in the scratchpad only (real B25118 owner/renter counts; synthetic medians = multiples of median income), and every figure was read for clipping. That caught: `!!!` used outside a tidy-eval context in `rel_worst()`; a stray double comma and clipped subtitle in the ratio charts; and three bullets I had written from memory that the data contradicted (Richmond city's renter-household growth is not the largest — Chesterfield's +21.0% exceeds its +19.7% — and "only the expansion ring's renter burden fell" is wrong, since Richmond city's fell 4.0 points).

**Data surprises (from the validated frames, not the mock):** Ownership rate region-wide 66.2% → 67.0%; Richmond city 42.7% → 43.5%, the only core locality where renters outnumber owners (58,914 vs 45,407). Renter 30%+ burden region-wide 51.4% → 50.0% → 51.2%; owner burden 26.1% → 21.1% → 20.0%. Richmond city's renter burden eased 56.0% → 52.0% while Henrico (48.4% → 51.6%) and Chesterfield (48.7% → 52.2%) rose, so the three are now nearly identical. Richmond MSA renter burden (51.2%) sits between Virginia (48.5%) and Hampton Roads (54.5%). In 2024, 9,537 renter and 2,706 owner households region-wide have no computed burden.

**Left open:** User runs `Rscript r/acs_market.R` and pastes back validation output. Then: real `quarto render market.qmd`, re-read every figure, confirm or rewrite the two provisional H2s and the `fig-alt` text on the four home-value/rent/ratio figures. Not committed.

---

## 2026-10-28 — Ralph iteration 2: `acs_market.R` written, `demographics.qmd` built

**What changed:** User confirmed `acs_burden.R` and `acs_demographics.R` validation passed. Wrote `r/acs_market.R` (B25003 tenure with pooled `bhc3`/`secondary4`/`rr17`; B25077 median home value and B25064 median gross rent, each with nominal and real-dollar columns; validation gates on owner + renter = total, `rr17` reconciling to its members, and B25003 occupied units = B19001 households from `acs_demographics.rds`). Built out `demographics.qmd` (7 figures, 3 tables) and rendered it standalone.

**Data surprises:**

- **Population growth, 2014 → 2024 windows:** region +10.7% (+129k), Chesterfield +16.5%, expansion ring +15.5%, Richmond city +8.7%, Henrico +6.6%. New Kent was the fastest locality (+30.8%); Sussex (-9.7%), Charles City (-7.4%), and King and Queen (-5.3%) lost population.
- **Richmond city's White non-Hispanic share rose** (39.7% → 41.4%) while its Black share fell (48.6% → 40.6%); the region's White share fell 58.7% → 54.7%. The "Multiracial" share roughly doubled region-wide, which is partly the 2020 Census race-coding revision rather than demographic change — the page carries a callout.
- **Real median household income** (2024 dollars, deflated by the CPI in `bls_wage.rds`): Richmond MSA $79,075 → $86,679 (+9.6%), Richmond city $54,766 → $64,587 (+17.9%), Henrico +9.1%, Chesterfield +6.1%. Charlottesville MSA (+19.3%) outpaced everything.
- **Renter households under $50k:** 45.9% region-wide vs. 18.9% of owners.
- **Cost burden (acs_burden.rds, logged):** 30%+ burden among renters held between 50.0% and 51.4% region-wide across all three windows; among owners it fell from 26.1% to 20.0%.
- **Rendering bugs the exit code didn't show:** `theme_rva()`'s `strip.text` is a ggtext element, so a plain `element_text()` override fails to merge (needs `ggtext::element_markdown()`); titles over ~65 characters clip on the right because `element_markdown()` doesn't wrap; a 6-item legend in one row, and 6 long x-axis labels, both overran. Found by reading the PNGs.

**Left open:** User runs `Rscript r/acs_market.R` and pastes back validation output. `market.qmd` is next; it needs `acs_market.rds`. Not committed.

---

## 2026-10-28 — Ralph iteration 1: `acs_burden.R` review, `acs_demographics.R` written

**What changed:** (1) Reviewed `r/acs_burden.R` for Phase 4. `data/acs_burden.rds` never existed, so the script had never run in this repo. It carried sibling-project debris: a tract tier for the "BHC service area" (long pull, tract geoids unstable across the 2010/2020 boundary change, no page needs it), a reference to a nonexistent `r/acs_income.R`, and a dead `baseline_2022.rds` block. Removed all three. Also fixed a latent bug: `summarise(estimate = sum(estimate), moe = moe_sum(moe, estimate))` fed `moe_sum` the already-summed scalar; now `sqrt(sum(moe^2))`, matching `acs_stock.R`. Added pooled `bhc3`/`secondary4`/`rr17` rows and rewrote validation (category sums vs. published `_001` totals; `rr17` reconciles to its 17 members; 25 × 3 × 2 × 4 rows). (2) Wrote `r/acs_demographics.R`: B01001, B03002, B11001, B19001, B19013, B25118 across 2014/2019/2024, 5 geography grains plus 3 pooled rows, 7 frames. Validation gates on same-vintage identities (collapsed categories = published totals; B01001 = B03002 population; B11001 = B19001 = B25118 households).

**Data surprises:** None — neither script has run. Design calls to review: income bands use fixed *nominal* thresholds (noted in the header — a rising top-band share partly reflects inflation); median household income can't be pooled, so it carries only the 22 named geographies; its real-dollar columns read national CPI-U from `data/bls_wage.rds` (exists from the BLS run) and go NA with a warning if absent rather than hardcoding a deflator. `acs_tenure.R` covers tenure by race only (B25003A–I), so total tenure (B25003) goes into the upcoming `acs_market.R`.

**Left open:** User runs `Rscript r/acs_burden.R` and `Rscript r/acs_demographics.R` and pastes back validation output. Still to do: `r/acs_market.R` (B25077, B25064, B25003), `demographics.qmd`, `market.qmd`. Not committed.

---

## 2026-10-28 — Add `r/bls_wage.R` (unemployment + wage growth)

**What changed:** New `r/bls_wage.R`, pulling from the BLS API through `blscrapeR`: LAUS unemployment rate and labor force, CES average hourly earnings (total private), and national CPI-U, for the Richmond MSA, the three other `regions` metros, and Virginia (unemployment only). Series IDs are built from `regions`/`virginia` rather than typed. Outputs `data/bls_wage.rds` (monthly, annual, wages frames), `data-out/bls_wage.csv` (annual) and `data-out/bls_wage_monthly.csv`. The wages frame carries YoY and cumulative-index growth, nominal and real (deflated to the latest year with complete Richmond wages and CPI). Key is read from `BLS_KEY` with the `.Renviron` fallback.

**Data surprises:** None yet — **the script has not been run.** Decisions to review: (1) wage measure is CES metro average hourly earnings, not QCEW weekly wages or OEWS — QCEW was left out per the existing `oews_cap` note and the data-fetch rule; (2) real wages use national CPI-U because no Richmond-area CPI exists, so "real" means relative to national prices; (3) MSA-level LAUS is NSA only, so Virginia is pulled NSA too; (4) partial years are dropped from annual/wage frames; (5) the DC-MSA and other comparison CES series IDs follow BLS's documented pattern but are unverified — a missing one warns and drops, Richmond missing fails validation.

**Left open:** `blscrapeR` is not in `renv.lock` (user: `renv::install("blscrapeR")` + `renv::snapshot()`). Run `Rscript r/bls_wage.R` and log the benchmark/validation output here. No page consumes the data yet; a `bls_cap()` helper is needed in `_common.R` first. Not committed.

---

## 2026-09-16 — Phase 1 closed out; Phase 2 complete (inventory page live)

**What changed:** Closed the three open Phase 1 lines and built all of Phase 2.

*Phase 1.* `data/geo.rds` already existed from a user run and validates clean — `sf`, 17 rows, all `rr` GEOIDs, EPSG:4326, zero empty geometries — so the tigris pull was not re-run. `CENSUS_API_KEY` visibility confirmed TRUE via the `.Renviron` fallback (existence check only; the value was never printed). The `mapgl` POC map is marked `[-]`: `mapgl` is absent from `renv.lock` and installing it is a user-run job.

*Phase 2.* Added `r/acs_stock.R` (B25001, B25002, B25004, B25024, B25034, B25035 across the 2014/2019/2024 non-overlapping ACS windows; 17 `rr` localities + Ashland + 4 comparison metros + Virginia, plus pooled `bhc3`/`secondary4` rows) and `r/bps_permits.R` (Census BPS county annual files, 2000–2025). Both ran clean and passed validation on the first attempt. Replaced the `inventory.qmd` stub with a real page: 6 figures, 3 tables, takeaway H2s, 2–4 bullets per section, a reliability callout, and a closing summary. Renders standalone in ~10 seconds.

**Data surprises:**

- **B25036 is not published in the 2014 window.** The TODO line asked for B25034–36; including B25036 would have broken the three-window trend every other frame carries, so it is out of scope for v1 and recorded as such in METHODOLOGY.md. B25035 is a median and cannot be summed, so it is pulled but carries no pooled rows.
- **BPS file naming is a trap.** `co<YY><MM>y.txt` is year-to-date-through-month and `...c.txt` is the monthly current file; only `co<YYYY>a.txt` is the true annual file. Confirmed the layout against both the 2000 and 2025 files before writing the parser. The files also carry each size class twice — a published imputation-inclusive figure and a "rep" reported-only duplicate. This script reads the former.
- **Both cross-table checks reconciled exactly.** B25024 and B25034 each sum to B25001 at 0.000% max difference across every geography-year, and B25002's Occupied + Vacant equals its own Total everywhere. Tighter than the 0.5% tolerance allowed for.
- **The regional permit story is compositional, not volumetric.** Permitted units ran 6,110 (2000) → 8,912 (2002) → a 2,520 trough in 2011 → a 10,414 peak in 2022 → 9,091 in 2025. Multifamily went from 3.6% of permitted units in 2000 to 56.8% in 2022, first exceeding single-family that year. Richmond city is now at 86.3% multifamily while Chesterfield fell back to 28.2% — the three core localities diverged sharply after 2021.
- **Housing-unit growth, 2014 → 2024** (logged, not gated): Richmond core +13.3% (357,302 → 404,918), Chesterfield +17.1%, Richmond city +15.3%, Henrico +8.3%, expansion ring +18.4%, Ashland +14.3%.
- **`theme_rva()` was clipping every caption.** `element_markdown()` does not wrap, so the ~95-character ACS source line ran off the right edge of every chart — a latent bug in the shared theme, not this page. Switched `plot.caption` to `element_textbox_simple()` with `width = unit(1, "npc")`. Found by reading the rendered PNGs; the render exit code was clean throughout.
- **`formattable` masks `scales`.** `_common.R` loads formattable after scales, so `comma()`/`percent()` resolve to formattable's, which take `digits` rather than `accuracy` — this killed two renders outright and silently produced "357,302.00" unit counts in a table. `inventory.qmd` uses local `n_fmt()`/`p_fmt()` wrappers for inline prose and passes `digits = 0` to the `kbl()` cells.
- **12 of 30 Ashland structure-type and year-built cells fall below CV-30.** The page computes that count rather than hardcoding it, and suppresses Low cells while marking Medium ones.

**Left open:** `mapgl` install (blocks the Phase 1 POC map and all of Phase 5). Three non-blocking items surfaced and are now in TODO.md: retire the deprecated `cache_table = TRUE` project-wide in one pass, re-check the other pages' captions against the new theme when Phases 3–4 land, and consider promoting `n_fmt()`/`p_fmt()` into `_common.R` before another page repeats the workaround. Phases 3–6 are untouched.

---

## 2026-09-17 — Fix `r/acs_tenure.R` runtime error: leftover `pha` reference

**What changed:** `Rscript r/acs_tenure.R` failed with `object 'pha' not found` (two `filter(geoid %in% pha, ...)` calls, lines 521 and 585). `pha` is a geography constant from the sibling project this script was copied from; it was never defined in this project's `_common.R` and never got swapped for the equivalent `bhc` (3-locality core) during the earlier cleanup pass. Replaced both occurrences with `bhc`, which matches the surrounding "3 primary localities" comments and the `region3` pooling used elsewhere in the same script.

**Data surprises:** The script's own header comment (lines 18–21) still describes "the 8 `rr` localities" and "the 4 primary localities" / a `region4` pooling — none of which match this project's real geography (`rr` = 17, `bhc` = 3, code pools into `region3`). Didn't rewrite it as part of this fix (out of scope for the reported error), but it's the same sibling-project debris class flagged in METHODOLOGY.md/PLAN.md — flagging here rather than trusting it. Added a TODO line.

**Left open:** Re-run `Rscript r/acs_tenure.R` end to end to confirm the rest of the script is clean now that it gets past line 521/585. Consider a pass to reconcile every `r/*.R` header comment against `_common.R`'s actual constants while this class of bug is fresh.

---

## 2026-09-16 — Phase 1: renv pinned, `.Rprofile` added

**What changed:** Ran `renv::init()` + `renv::snapshot()` (user-run, per CLAUDE.md — package installs are a long job) and committed the result: `renv.lock` (168 packages), `renv/.gitignore`, `renv/activate.R`, `renv/settings.json`, and a new `.Rprofile` that sources `renv/activate.R`. `renv/library/` stays untracked via renv's own `.gitignore`. R 4.6.1. Pinned the packages CLAUDE.md's Phase 1 line calls for — tidyverse, tidycensus, tigris, sf, kableExtra, ggtext, formattable, janitor — confirmed present in the lockfile. **`mapgl` is not in `renv.lock`** — it never got installed in this pass, so the Phase 1 POC map and any Phase 2/5 interactive map work stay blocked until a follow-up `renv::install("mapgl")` + `renv::snapshot()`.

**Data surprises:** None — this is package pinning, not a data pull.

**Left open:** `mapgl` still needs installing (blocks TODO's POC-map line). `Rscript r/geo.R` and the `CENSUS_API_KEY` visibility check are still open — both are next per TODO.md's Phase 1 list.

---

## 2026-09-16 — Finish Session 0 cleanup: remove leftover `rva-sourcebook/` folder

**What changed:** The 2026-09-15 cleanup entry claimed the nested `rva-sourcebook/` subfolder was removed, but it wasn't — it still held a `.quarto/` build cache and a live `.Renviron`. Deleted it for real. Also fixed `.gitignore`: the `.quarto/` rule was anchored to the repo root (`/.quarto/`), so it never covered that nested copy — a real gap, since a stray `git add -A` could have staged cache files or (worse) an `.Renviron` sitting somewhere the anchored rule didn't reach. Unanchored the rule so it covers `.quarto/` at any depth. Committed the Session 0 cleanup, which had been sitting unstaged.

**Data surprises:** None — repo hygiene only.

**Left open:** Phase 1 still needs `renv::init()`/`renv::snapshot()`, `Rscript r/geo.R`, and a `CENSUS_API_KEY` visibility check — all user-run long jobs per CLAUDE.md.

---

## 2026-09-15 — Phase 1 foundations: palette, theme, map basemap, geo script

**What changed:** Defined the site's palette and theme in `_common.R` — `rva_pal` (8-hue categorical, fixed order), `rva_seq` (sequential blue ramp for choropleths/magnitude), `rva_ink` (chart chrome tokens), and `theme_rva()` (ggplot2 theme, `legend.position = "none"` by default per the bold-subtitle-span convention). Values are the dataviz skill's validated reference palette (CVD-safe adjacent pairs), not hand-picked. Chose `rva_map_style` — Carto's free Positron MapLibre style — as the `mapgl` basemap, avoiding a Mapbox token. Wrote `r/geo.R`: pulls cartographic-boundary (500k) county/independent-city geometry for the 17-locality `rr` region via `tigris::counties()`, transforms to EPSG:4326, writes `data/geo.rds` + `data-out/geo.csv` (attributes only — CSV can't hold geometry sensibly).

**Data surprises:** None yet — `r/geo.R` hasn't been run. tigris pulls are a user-run long job per CLAUDE.md.

**Left open:** User needs to (1) run `renv::init()`/`renv::snapshot()` to pin the package set (tidyverse/tidycensus/tigris/sf/mapgl/kableExtra/ggtext/formattable/janitor), (2) run `Rscript r/geo.R` and confirm the validation block passes, (3) confirm `CENSUS_API_KEY` is visible. Once `mapgl` is installed, build one proof-of-concept map before wiring real data into Phase 2.

---

## 2026-09-15 — Repo cleanup and re-plan

**What changed:** The repo was in a confused, mid-restructure state — `CLAUDE.md` and `TODO.md` had been copy-pasted from an unrelated sibling engagement (a much larger Richmond-nonprofit report with PUMS/CHAS/MLS pipelines that don't exist here), `PLAN.md` was for a wholly different Fauquier County study, and `_quarto.yml`/`index.qmd`/`about.qmd` were generic un-customized `quarto create` scaffold. `_common.R` and `r/acs_tenure.R`/`r/acs_burden.R` were confirmed real and Richmond-specific, and kept as-is.

Rewrote `PLAN.md`, `CLAUDE.md`, and `TODO.md` to match this project's actual scope (personal/portfolio site, inventory/demographics/market pages, public data only, Quarto **website** not book, `mapgl` for interactive maps). Added `README.md` and `METHODOLOGY.md`, both previously referenced but never written. Reconciled `_quarto.yml` (website type, real navbar, `output-dir: docs`, `freeze: auto`) and gave every page (`index.qmd`, `about.qmd`, `inventory.qmd`, `demographics.qmd`, new `market.qmd`, new `data-notes.qmd`) enough stub content to render cleanly. Removed the empty nested `rva-sourcebook/` subfolder and stale scaffold files (`rva-sourcebook.qmd`, `app.R`, `_site/`).

**Data surprises:** None — no data scripts ran this session, this was pure repo hygiene.

**Left open:** Phase 1 (renv setup, palette/theme, `r/geo.R`, mapgl basemap choice) is next. No page has real chart/table content yet. See TODO.md.
