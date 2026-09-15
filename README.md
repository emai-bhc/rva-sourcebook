# rva-sourcebook

A personal Quarto website of basic Richmond-region housing data — inventory, demographics, and market — built from public sources (Census/ACS, BLS) with ggplot2 charts and `mapgl` interactive maps.

**Status:** in progress. Repo cleanup done 2026-09-15; no pages have real content yet. See [TODO.md](TODO.md) for what's next and [PLAN.md](PLAN.md) for the full build order.

## Quick start (Windows)

R and Quarto are usually not on `PATH` by default. If a command below isn't found, prepend the install directory for this session:

```powershell
$env:Path = "C:\Program Files\R\R-<version>\bin;" + $env:Path
$env:Path = "C:\Program Files\Quarto\bin;" + $env:Path
```

Adjust the paths to match where R and Quarto are actually installed on this machine — check `where.exe R` / `where.exe quarto` first, or the install location noted the first time this section gets filled in for real.

### First-time setup

1. Install R and Quarto if not already present.
2. Set `CENSUS_API_KEY` in `%USERPROFILE%\Documents\.Renviron` (get a free key at [api.census.gov](https://api.census.gov/data/key_signup.html)).
3. Once `renv.lock` exists (Phase 1 — not yet committed), run `renv::restore()` from the project root in R to install pinned packages. Until then, the two existing scripts assume `tidyverse`, `tidycensus`, and `janitor` are available.

### Running things

- **Data scripts:** `Rscript r/<name>.R` from the project root. Never run R inline — see [CLAUDE.md](CLAUDE.md)'s Execution section.
- **Render the site:** `quarto render` from the project root, or `quarto preview` to view it live while editing. Renders can take a couple of minutes once maps and multiple pages are in place — let it run rather than interrupting.

## Repo layout

See [CLAUDE.md](CLAUDE.md)'s repo map for the full picture. Short version: `r/` scripts pull public data and write `data/*.rds` + `data-out/*.csv`; `.qmd` pages read those `.rds` files and never call an API directly; `_common.R` holds shared geography constants, caption helpers, and (once written) the site's color palette.

## Conventions

Session conventions, commit grammar, and data/validation rules live in [CLAUDE.md](CLAUDE.md). Geography definitions and data vintages live in [METHODOLOGY.md](METHODOLOGY.md).
