# TODO.md — punch list

**Always check TODO.md before starting work.** Update it as tasks land (`[x]`), start (`[~]`), or get skipped (`[-]`). See [LOG.md](LOG.md) for the history behind any line, [METHODOLOGY.md](METHODOLOGY.md) for the data/scope rules, and [PLAN.md](PLAN.md) for the full phased build order.

## Session 0 — repo cleanup (2026-09-15)

- [x] Remove the nested `rva-sourcebook/` duplicate subfolder (superseded by root files).
- [x] Remove stale generic scaffold: `rva-sourcebook.qmd`, `app.R`, `_site/`.
- [x] Rewrite `PLAN.md` — was a Fauquier County/Better Housing Coalition plan for an unrelated engagement.
- [x] Rewrite `CLAUDE.md` — fix geography section (`rr`/`bhc`/`secondary`/`ashland`/`regions`, not `pha`/4-primary), switch book → website language, drop PHA/BHC client-review conventions, add `mapgl` section, trim "Known gotchas" to what's real.
- [x] Reset this file to a real, accurate punch list.
- [x] Write `README.md` (quick start, renv guide, status).
- [x] Write `METHODOLOGY.md` (geography/scope conventions, referenced by CLAUDE.md but never written).
- [x] Reconcile `_quarto.yml` — real navbar (Home/About/Inventory/Demographics/Market/Data Notes), `output-dir: docs`, `freeze: auto`, `execute-dir: project`. Added stub content to `inventory.qmd`/`demographics.qmd`/`market.qmd`/`data-notes.qmd`/`index.qmd`/`about.qmd` so the site renders end-to-end even before real data lands.
- [x] First `LOG.md` entry for this session.
- [x] Commit the cleanup (including removing the leftover `rva-sourcebook/` folder that survived the first pass).

## Phase 1 — foundations

- [x] `renv::init()` + `renv::snapshot()` — **user runs**, package installs are a long job. Pin R + tidyverse/tidycensus/tigris/sf/mapgl/kableExtra/ggtext/formattable/janitor.
- [x] Add `.Rprofile` (`source("renv/activate.R")`) once renv exists.
- [x] Define a palette + light theme in `_common.R` — `rva_pal` (8-hue categorical), `rva_seq` (sequential blue ramp), `rva_ink` (chart chrome), `theme_rva()`. Values from the dataviz skill's validated reference palette.
- [x] Decide the `mapgl` basemap style — `rva_map_style` in `_common.R`, Carto's free Positron MapLibre style, no token.
- [x] `r/geo.R` written — tigris county/independent-city boundaries for the `rr` region → `data/geo.rds` + `data-out/geo.csv`.
- [x] **Run `Rscript r/geo.R`** — user runs (tigris pull is a long job). Confirms `data/geo.rds` writes clean and the validation block passes (17 localities, valid geometry, EPSG:4326). Verified 2026-09-16: `data/geo.rds` is an `sf` frame, 17 rows, all `rr` GEOIDs, EPSG:4326, zero empty geometries.
- [x] Confirm `CENSUS_API_KEY` is visible (`Sys.getenv("CENSUS_API_KEY") != ""`) — TRUE/FALSE check only, never print the value. Not needed by `geo.R` (tigris doesn't require a key) but will be for every ACS script from Phase 2 on. Verified TRUE 2026-09-16 via the `.Renviron` fallback.
- [-] Once `mapgl` is in `renv.lock`, build one small proof-of-concept map (e.g. `rr` region colored by `aland`) to confirm `rva_map_style` + `data/geo.rds` actually render before wiring real data into it. **Blocked:** `mapgl` is not in `renv.lock` — needs a user-run `renv::install("mapgl")` + `renv::snapshot()`.

## Phase 2 — inventory page

- [x] `r/acs_stock.R` — ACS B25001 (units), B25002/B25004 (occupancy/vacancy), B25024 (structure type), B25034–36 (year built). Ran clean; validation passes. **B25036 dropped from scope** — not published in the 2014 window, which would break the three-window trend (recorded in METHODOLOGY.md). B25035 is pulled but carries no pooled rows, since a median can't be summed.
- [x] BPS building permits (census.gov text files) — annual permits by structure type for the `rr` region. `r/bps_permits.R`, 2000–2025, cached under `data/cache/bps/`. Ran clean; the `rr17` pooled row reconciles to its 17 members in all 26 years.
- [x] Build out `inventory.qmd` (currently an empty stub). 6 figures, 3 tables, takeaway H2s, bullets, callouts; renders standalone in ~10s.

## Phase 3 — demographics page

- [ ] Extend the `acs_tenure.R` pattern: population, age/sex (B01001), race/ethnicity (already partly covered by `acs_tenure.R`'s B25003 letter tables — add B01001/B03002 for the population side), household composition (B11001), income (B19013/B19001/B25118).
- [ ] Build out `demographics.qmd` (currently an empty stub).

## Phase 4 — market page

- [ ] `acs_burden.R` already covers cost burden — confirm its output is current and review its validation block.
- [ ] Add home values (B25077), rents (B25064), tenure trend if not already covered.
- [ ] New `market.qmd` (replaces the old book's split `ownership.qmd`/`rental.qmd` — one page for v1).

## Phase 5 — interactive maps

- [ ] One `mapgl` choropleth per page (e.g. inventory: vacancy rate by locality; demographics: median household income; market: median rent or home value).

## Phase 6 — polish & publish

- [ ] `data-notes.qmd` — public-facing methodology, derived from `METHODOLOGY.md`.
- [ ] `about.qmd` — real content (currently a one-line stub).
- [ ] Full `quarto render` completes with no errors.
- [ ] Every `#| label: fig-` chunk has a matching `#| fig-alt:` line. (`inventory.qmd` is done — 6 of 6.)
- [ ] GitHub Pages live from `docs/` on `main`.

## Surfaced during Phase 2 — not blocking

- [ ] `cache_table = TRUE` is deprecated in current tidycensus (one warning per `get_acs()` call, ignored). CLAUDE.md still prescribes it. Drop it project-wide in one pass — `acs_stock.R`, `acs_tenure.R`, `acs_burden.R`, and the CLAUDE.md line together — rather than piecemeal.
- [ ] `theme_rva()`'s caption switched to `element_textbox_simple()` so long source lines wrap instead of clipping. The other pages' charts haven't been re-rendered against it yet; check them when Phases 3–4 land.
- [ ] `formattable::comma()`/`percent()` mask the `scales` versions (`_common.R` loads formattable last) and take `digits`, not `accuracy`. `inventory.qmd` works around it with local `n_fmt()`/`p_fmt()` wrappers — consider promoting those to `_common.R` before the next page repeats the workaround.

## Future — not in scope right now

- [ ] PUMS gap analysis, CHAS, MLS/CoStar, vulnerable-populations data. The PUMA geography groundwork (`puma_core3`/`puma_region`/`puma_locality`) already exists in `_common.R` if this ever gets picked up — see METHODOLOGY.md.
