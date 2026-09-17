# LOG.md — dev log

Append-only. Newest entry first.

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
