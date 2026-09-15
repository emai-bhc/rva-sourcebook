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
- [ ] Commit the cleanup.

## Phase 1 — foundations

- [ ] `renv::init()` + `renv::snapshot()` — **user runs**, package installs are a long job. Pin R + tidyverse/tidycensus/tigris/sf/mapgl/kableExtra/ggtext/formattable/janitor.
- [ ] Add `.Rprofile` (`source("renv/activate.R")`) once renv exists.
- [x] Define a palette + light theme in `_common.R` — `rva_pal` (8-hue categorical), `rva_seq` (sequential blue ramp), `rva_ink` (chart chrome), `theme_rva()`. Values from the dataviz skill's validated reference palette.
- [x] Decide the `mapgl` basemap style — `rva_map_style` in `_common.R`, Carto's free Positron MapLibre style, no token.
- [x] `r/geo.R` written — tigris county/independent-city boundaries for the `rr` region → `data/geo.rds` + `data-out/geo.csv`.
- [ ] **Run `Rscript r/geo.R`** — user runs (tigris pull is a long job). Confirms `data/geo.rds` writes clean and the validation block passes (17 localities, valid geometry, EPSG:4326).
- [ ] Confirm `CENSUS_API_KEY` is visible (`Sys.getenv("CENSUS_API_KEY") != ""`) — TRUE/FALSE check only, never print the value. Not needed by `geo.R` (tigris doesn't require a key) but will be for every ACS script from Phase 2 on.
- [ ] Once `mapgl` is in `renv.lock`, build one small proof-of-concept map (e.g. `rr` region colored by `aland`) to confirm `rva_map_style` + `data/geo.rds` actually render before wiring real data into it.

## Phase 2 — inventory page

- [ ] `r/acs_stock.R` — ACS B25001 (units), B25002/B25004 (occupancy/vacancy), B25024 (structure type), B25034–36 (year built).
- [ ] BPS building permits (census.gov text files) — annual permits by structure type for the `rr` region.
- [ ] Build out `inventory.qmd` (currently an empty stub).

## Phase 3 — demographics page

- [ ] Extend the `acs_tenure.R` pattern: population, age/sex (B01001), race/ethnicity (already partly covered by `acs_tenure.R`'s B25003 letter tables — add B01001/B03002 for the population side), household composition (B11001), income (B19013/B19001).
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
- [ ] Every `#| label: fig-` chunk has a matching `#| fig-alt:` line.
- [ ] GitHub Pages live from `docs/` on `main`.

## Future — not in scope right now

- [ ] PUMS gap analysis, CHAS, MLS/CoStar, vulnerable-populations data. The PUMA geography groundwork (`puma_core3`/`puma_region`/`puma_locality`) already exists in `_common.R` if this ever gets picked up — see METHODOLOGY.md.
