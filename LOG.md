# LOG.md — dev log

Append-only. Newest entry first.

---

## 2026-09-15 — Repo cleanup and re-plan

**What changed:** The repo was in a confused, mid-restructure state — `CLAUDE.md` and `TODO.md` had been copy-pasted from an unrelated sibling engagement (a much larger Richmond-nonprofit report with PUMS/CHAS/MLS pipelines that don't exist here), `PLAN.md` was for a wholly different Fauquier County study, and `_quarto.yml`/`index.qmd`/`about.qmd` were generic un-customized `quarto create` scaffold. `_common.R` and `r/acs_tenure.R`/`r/acs_burden.R` were confirmed real and Richmond-specific, and kept as-is.

Rewrote `PLAN.md`, `CLAUDE.md`, and `TODO.md` to match this project's actual scope (personal/portfolio site, inventory/demographics/market pages, public data only, Quarto **website** not book, `mapgl` for interactive maps). Added `README.md` and `METHODOLOGY.md`, both previously referenced but never written. Reconciled `_quarto.yml` (website type, real navbar, `output-dir: docs`, `freeze: auto`) and gave every page (`index.qmd`, `about.qmd`, `inventory.qmd`, `demographics.qmd`, new `market.qmd`, new `data-notes.qmd`) enough stub content to render cleanly. Removed the empty nested `rva-sourcebook/` subfolder and stale scaffold files (`rva-sourcebook.qmd`, `app.R`, `_site/`).

**Data surprises:** None — no data scripts ran this session, this was pure repo hygiene.

**Left open:** Phase 1 (renv setup, palette/theme, `r/geo.R`, mapgl basemap choice) is next. No page has real chart/table content yet. See TODO.md.
