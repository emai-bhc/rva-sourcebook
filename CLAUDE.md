# CLAUDE.md — RVA SOURCEBOOK

Conventions for all Claude sessions on this project. **This is a personal/portfolio Quarto website**, not a client deliverable — a public sourcebook of basic Richmond-region housing data (inventory, demographics, market) built from public sources only. [**TODO.md**](TODO.md) **is the punch list** — start every session there. [METHODOLOGY.md](METHODOLOGY.md) holds the internal data/geography/scope conventions; `data-notes.qmd` holds the public-facing methodology. [PLAN.md](PLAN.md) has the target architecture and phased build order.

## Start-of-session checklist

1.  Read this file, then [TODO.md](TODO.md), then the top entry of [LOG.md](LOG.md).
2.  Read [METHODOLOGY.md](METHODOLOGY.md) and `_common.R` for the geography/scope rules that bear on the task at hand.
3.  Verify that any prerequisite raw files exist under `data/raw/` (there aren't many — this project runs almost entirely on API pulls). If any are missing, do the work that doesn't need them and record the blocker in the log entry.

## End-of-session checklist

1.  Update [TODO.md](TODO.md) — check off what landed, add anything new that surfaced.
2.  Append a [LOG.md](LOG.md) entry: what changed, data surprises, what was left open.
3.  Update README.md or this file if a convention changed — same session, not a follow-up.
4.  Commit the work and the log entry together.

## Commit conventions

| Setting | Value |
|------------------------------------|------------------------------------|
| Repo type | Report / personal site |
| Commit types | `fix`, `docs`, `chore`, `data`, `content`, `infra` |
| Scope | A component noun (`docs(readme)`, `data(acs-tenure)`, `content(market)`). Optional on `docs` and `chore` commits. |
| Versioned | No. Git history plus [LOG.md](LOG.md) is the release record |

## Token efficiency and model policy

- **Start narrow.** Read TODO.md and only the LOG.md/METHODOLOGY.md sections that bear on the task. Do not read whole files when a block will do.
- **Model guidance.** Sonnet is fine for mechanical data pulls, geography swaps, and QA sweeps, as well as page/chart builds — this project doesn't carry the methodology weight that would call for Opus by default.
- **User runs long jobs** — `tigris` pulls, `renv` package installs, and any full render over roughly two minutes. Claude writes the script; user runs it and pastes back errors and validation output. Never babysit a long `Rscript` run.
- **Skills carry the boilerplate.** Invoke `/new-data-script` before writing a new `r/*.R` pull or prep script — it lives in-repo at `.claude/new-data-script/`. It reads the project-config block from this file, [METHODOLOGY.md](METHODOLOGY.md), and `_common.R` at invocation.

## Data flow rule

`r/` scripts write `data/*.rds` and, through `export_csv()`, `data-out/*.csv`. Pages call `read_rds()` only. **Pages never call APIs.**

## Code style and script anatomy

Script anatomy: a header comment stating what, source, and output → numbered `## 1. Setup ----` sections → an `.Renviron` fallback for keys → `write_rds()` paired with `export_csv()` → a validation block. Scripts are idempotent and safe to re-run. No inline `install.packages()`.

- Native pipe `|>`, tidyverse style, `janitor::clean_names()` on all imported raw data.
- dplyr 1.2 idioms once pinned via renv: `.by=` over `group_by()` for one-off grouping; `across()`; `join_by()`; `reframe()` for multi-row summaries. Prefer `recode_values()`/`case_match()` for value-to-label recodes over nested `case_when()`; reserve `case_when()` for genuine conditional logic.
- `purrr::map()` and `imap()` over `for` loops, bound with `list_rbind()`/`list_cbind()` (or `map_dfr()`/`map_dfc()` if the pinned purrr predates 1.2). Pattern: `map(years, \(yr) get_acs(..., year = yr) |> mutate(year = yr)) |> list_rbind()`.
- tidycensus: `get_acs(geography, state = "VA", table = "BXXXXX", year, survey = "acs5", cache_table = TRUE)`. Pull whole tables and build label lookups from `load_variables()` with `separate_wider_delim(label, "!!")`.

## Validation semantics

- `stopifnot()` fires only on structural expectations (row counts, all geographies present, no all-NA columns) and on **same-vintage** published benchmarks — a Census-published table total or another public, dated figure.
- Vintage-to-vintage comparisons (e.g. an older ACS window vs. the current one) are a **logged percentage change in the session's log entry**, never a `stopifnot()` gate — different 5-year windows differ by construction, and an implausible swing is a flag for review, not a build failure.
- Every data script logs its benchmark results, both passes and variances.

## What `_common.R` provides

- **Geography:** `rr` (17-locality Richmond region), `bhc` (3-locality core: Richmond city, Henrico, Chesterfield), `secondary` (4 expansion localities: Hanover, Goochland, New Kent, Powhatan), `ashland` (place 5103368, sumlev 160), `regions` (comparison MSAs: Charlottesville, Richmond, Hampton Roads, DC), `virginia`; and PUMS-ready PUMA sets `puma_core3`/`puma_region`/`puma_locality` (defined but not currently used — see METHODOLOGY.md).
- **Palette/theme:** `rva_pal` (8-hue categorical, fixed order — never cycle or reorder), `rva_seq` (7-step blue sequential ramp for choropleths/magnitude), `rva_ink` (chart chrome: primary/muted/gridline/baseline), `theme_rva()` (ggplot2 theme; `legend.position = "none"` by default since 2-3 series use bold ggtext subtitle spans instead of a legend box), and `rva_map_style` (free Carto MapLibre basemap URL, no token). Values come from the dataviz skill's validated reference palette — CVD-safe adjacent pairs. Change values in `_common.R` only, never at the call site.
- **Caption helpers:** `acs_cap`, `pums_cap`, `chas_cap`, `dec_cap`, `pep_cap`, `bps_cap`, `oews_cap` and others — see the file for the full list. Not every helper has a matching script yet; that's fine, they're cheap to keep around.
- **`flag_reliability(df, cv_col = cv)`** — High at or below 15, Medium at or below 30, Low above 30, from a **0 to 100** CV. Use it for secondary-locality and Ashland ACS estimates, which run noisier than the `bhc` core.
- **`export_csv(df, name)`** — writes `data-out/<name>.csv`. All data in this project is public-source, so no filename-prefix privacy convention is needed (unlike sibling reports that mix in licensed MLS/CoStar data).
- **`fct_wrap(f, width)`** — applies `str_wrap()` to a factor's levels.

## Chart and table conventions

- Titles are takeaway sentences. The subtitle carries geography, units, and years. Captions come from a `_common.R` source helper.
- For 2 or 3 series, prefer color-coded bold words in the subtitle (ggtext spans) over a legend.
- Keep subtitle length to roughly 50 characters to avoid wrapping onto a new row.
- Currency uses `scales::label_dollar()`, and the subtitle notes whether a series is nominal or inflation-adjusted. Percentages use `label_percent(accuracy = 1)` unless precision matters.
- Tables use `kbl() |> kable_styling(c("condensed","striped"))` with `formattable::comma` and `percent`.
- Secondary-locality and Ashland ACS estimates always carry reliability treatment through `flag_reliability()`. Suppress cells with a CV above 30 and footnote the Medium cells.
- Every figure gets `#| fig-alt:` alt text.

## Interactive maps (`mapgl`)

- Use `mapgl` for anything inherently spatial (locality choropleths, point maps of permits/listings); keep everything else as static ggplot2.
- Basemap: `rva_map_style` in `_common.R` — Carto's free Positron MapLibre style, no Mapbox token, zero-cost. Revisit only if styling needs genuinely outgrow that.
- Choropleth fills use `rva_seq` (the same sequential ramp as ggplot2 magnitude encodings), so a reader sees one consistent "light = low, dark = high" language across static charts and maps.
- Boundary data comes from `r/geo.R` → `data/geo.rds` (tigris pulls for the `rr` region). Join whatever table a map needs onto that, in the page — don't re-pull boundaries per page.
- Caption maps the same way as charts, via a `_common.R` source helper.

## Narrative rule

Pages ship with takeaway H2s, 2 to 5 bullet findings per section (plain statements traceable to a figure or table), and callout boxes for data caveats. **No drafted paragraphs.** The bullets should be specific enough that they could be expanded into prose without reopening the data, even though this is a personal project and that expansion may never happen.

## Execution on Windows

**Never run R inline.** Write `r/<name>.R` and run `Rscript r/<name>.R` from the project root. Ad hoc checks go in a temp script in the scratchpad, run through `Rscript`, never in the repo.

R and Quarto are usually not on PATH. See README.md for the prepend and render commands once it's written; install paths are machine-specific.

Use forward slashes in R paths, and keep every path relative to the project root.

## API keys

`CENSUS_API_KEY` is required for tidycensus. It lives in the user `.Renviron` at `%USERPROFILE%\Documents\.Renviron`. Never print or commit its value. A `FRED_API_KEY` may be added later if CPI/PMMS series get pulled in.

R's HOME on Windows may be `C:\Users\<you>` rather than the Documents folder, so that file is not always loaded automatically. Scripts include an `.Renviron` fallback derived from the current user — `readRenviron(file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron"))` when the key is empty — never a hardcoded username. Verify visibility with a TRUE or FALSE check only.

## Data-fetch rule

tidycensus, tigris, and (if added) fredr package downloads are approved. Direct fetches from census.gov file servers (e.g. BPS permit text files) are approved with a manual fallback. Anything else on a government host, especially BLS OEWS/QCEW beyond what a package wraps, gets a quick sanity check before scripting — this is a solo project, so "approval" just means pausing to confirm the source and terms of use look right before pulling.

## Publishing status

Not yet published. Intended as a public GitHub Pages site (`docs/` on `main`) once the first three pages (inventory, demographics, market) have real content. No review workflow, no annotation tooling — it's a personal project.

## Known gotchas

- **`dplyr::join_by(a == b)` on differently-named columns** — the joined result keeps only `a`, silently dropping `b`. A downstream `mutate()`/`select()` expecting `b` gets a column-not-found error, or an `NA` after a `bind_rows()` masks the missing column with a same-named one from another frame. Join on equal-named keys only and enforce cross-name equality with a `filter()` immediately after, so both columns survive.
- **PEP** — the post-2020 API requires an explicit `vintage=` argument; `year=` alone misbehaves silently. Fall back to the FTP tables if the API lags.

*(This section previously carried several PUMS/CHAS/MLS-specific gotchas inherited from a sibling project's CLAUDE.md. They referenced scripts that don't exist in this repo and were removed on 2026-09-15. If PUMS or CHAS work ever starts here, re-derive gotchas from this project's own scripts rather than reusing the old list.)*

## Repo map

```
rva-sourcebook/
├── _quarto.yml            # website config: freeze auto, execute-dir project, output-dir docs
├── _common.R              # sourced by every page: libs, geography constants, caption helpers, flag_reliability(), export_csv()
├── CLAUDE.md              # this file
├── PLAN.md                # target architecture and phased build order
├── METHODOLOGY.md         # internal data/geography/scope conventions
├── TODO.md                # the punch list — start here
├── LOG.md                 # append-only dev log
├── README.md              # purpose, quick start, status
├── index.qmd              # Home
├── about.qmd               # About this site
├── inventory.qmd           # Housing stock & production
├── demographics.qmd        # Population & household characteristics
├── market.qmd               # Tenure, values, rents, cost burden
├── data-notes.qmd           # Public-facing methodology
├── r/                      # collection and prep scripts — committed
├── data/                   # .rds outputs — gitignored
├── data-out/               # tidy CSV exports — committed (all public-source)
├── docs/                   # rendered site — committed once publishing starts; GitHub Pages will serve this
└── .claude/new-data-script/  # skill for scaffolding new r/ scripts
```

- Theming: plain ggplot2 + kableExtra for now; `mapgl` for interactive maps only. No leaflet, no ggiraph.
- Page anatomy: `# Title {#sec-slug}` → setup chunk (`source("_common.R")`, `read_rds()` stubs, inline-scalar block) → takeaway H2s → alternating figure and table blocks with bullets → a closing summary callout.

## Geography and vintages

Geography constants are defined once in `_common.R` (`rr`, `bhc`, `secondary`, `ashland`, `regions`, `virginia`, plus the PUMS-ready `puma_*` sets). See [METHODOLOGY.md](METHODOLOGY.md) for the reasoning behind each and the vintages currently in use.
