# PLAN.md — RVA Sourcebook build plan

**This is a personal/portfolio project**, not a client deliverable. It's a public Quarto website covering basic Richmond-region housing data — inventory, demographics, and market — sourced entirely from public data (Census/ACS, BLS), with ggplot2 static charts and `mapgl` interactive maps. See [CLAUDE.md](CLAUDE.md) for session conventions, [TODO.md](TODO.md) for the punch list, and [METHODOLOGY.md](METHODOLOGY.md) for geography/scope details.

## How this repo got here

Earlier drafts of this repo's docs (CLAUDE.md, TODO.md, and a prior PLAN.md) were copy-pasted from two unrelated sibling engagements — a Richmond-nonprofit regional report with a much larger scope (PUMS gap analysis, CHAS, MLS/CoStar pipelines) and a wholly separate Fauquier County study — and never reconciled to this project's actual geography or scope. `_common.R` and `r/acs_tenure.R` / `r/acs_burden.R` are the real, working foundation; everything else was rebuilt from scratch on 2026-09-15 to match. If you find a stray reference to PHA, BHC-as-client, Fauquier, or a script under `r/pums/`, `r/chas.R`, `r/mls_*` that doesn't exist in this repo — it's leftover from that history. Flag it.

## Scope

**In scope (v1):**
- **Inventory** — housing stock, occupancy/vacancy, structure type, year built, building permits.
- **Demographics** — population, age/sex, race/ethnicity, household composition, income.
- **Market** — tenure, home values, rents, cost burden.

All from public sources: tidycensus (ACS, decennial, PEP), tigris (boundaries), BLS (OEWS/QCEW where useful), Census BPS permits.

**Out of scope for now:** PUMS gap analysis, CHAS, MLS/CoStar, vulnerable-populations data. The PUMA geography groundwork (`puma_core3`, `puma_region`, `puma_locality` in `_common.R`) already exists from the earlier copy-paste and is harmless to keep, but nothing is built toward it yet.

## Geography

Defined once in `_common.R`:

| Name | What |
|---|---|
| `rr` | 17-locality Richmond region |
| `bhc` | 3-locality core: Richmond city, Henrico, Chesterfield |
| `secondary` | 4 expansion localities: Hanover, Goochland, New Kent, Powhatan |
| `ashland` | Town of Ashland (place, sumlev 160) |
| `regions` | Comparison MSAs: Charlottesville, Richmond, Hampton Roads, DC |

`bhc` is just a variable name inherited from the scripts that first defined it (Richmond's 3-locality development core) — it doesn't imply any client relationship for this project.

## Format

Quarto **website** (not book) — `_quarto.yml` type `website`, output to `docs/` for GitHub Pages, `freeze: auto`, `execute-dir: project`. Pages: Home (`index.qmd`), About (`about.qmd`), Inventory (`inventory.qmd`), Demographics (`demographics.qmd`), Market (`market.qmd`), Data Notes (`data-notes.qmd`).

## Maps

`mapgl` for interactive choropleths and point maps, backed by a free MapLibre basemap style (Carto or ESRI — no Mapbox token needed). Boundary data comes from `r/geo.R` → `data/geo.rds`, joined to whatever ACS/permit table a given map needs. Static ggplot2 remains the default for everything that isn't inherently spatial.

## Target repo shape

```
rva-sourcebook/
├── _quarto.yml          # type: website, output-dir: docs, freeze: auto
├── _common.R            # geography, caption helpers, flag_reliability(), export_csv()
│                         #   + a palette/theme (rva_pal / theme_rva) — not yet defined, Phase 1
├── CLAUDE.md             # session conventions
├── PLAN.md               # this file
├── TODO.md               # punch list — start here each session
├── LOG.md                # append-only dev log
├── README.md             # quick start, renv guide, status
├── METHODOLOGY.md        # internal geography/scope conventions
├── data-notes.qmd        # public-facing methodology page
├── index.qmd / about.qmd
├── inventory.qmd / demographics.qmd / market.qmd
├── r/                     # collection/prep scripts, committed
│   ├── acs_tenure.R       # existing
│   ├── acs_burden.R       # existing
│   └── geo.R              # NEW — tigris boundaries for maps
├── data/                  # .rds outputs — gitignored
├── data-out/              # tidy CSV exports — committed
├── docs/                  # rendered site — committed, GitHub Pages serves this
└── .claude/new-data-script/  # skill for scaffolding new r/ scripts
```

## Phased build order

0. **Repo cleanup** (2026-09-15) — remove stale/duplicate files, rewrite CLAUDE.md/TODO.md/PLAN.md, add README.md/METHODOLOGY.md, reconcile `_quarto.yml`. *Done this session.*
1. **Foundations** — renv init + snapshot (user runs — package installs are a long job), palette/theme in `_common.R`, `r/geo.R`, confirm `CENSUS_API_KEY` visibility.
2. **Inventory page** — ACS B25001/B25002/B25024/B25034-36 + BPS permits.
3. **Demographics page** — population, age/sex, race/ethnicity, household composition, income (extends `acs_tenure.R`'s pattern).
4. **Market page** — tenure, values, rents, burden (`acs_burden.R` already covers part of this).
5. **Interactive maps** — one `mapgl` choropleth per page.
6. **Polish & publish** — `data-notes.qmd`, full `quarto render`, GitHub Pages live.
7. **Future, not now** — PUMS gap analysis, CHAS, MLS/CoStar, vulnerable populations.

## Verification

- Every `r/*.R` script runs clean via `Rscript r/<name>.R` (user runs) with a passing validation block and produces `data/*.rds` + `data-out/*.csv`.
- `quarto preview` confirms each page renders and any `mapgl` widget loads and pans/zooms.
