# LOG.md — dev log

Append-only. Newest entry first.

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
