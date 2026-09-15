# CLAUDE.md — RVA SOURCEBOOK

Conventions for all Claude sessions on this project. **This is a report repo** under the HDA four-type taxonomy, which settles the commit vocabulary below. [**TODO.md**](TODO.md) **is the punch list** — start every session there. [METHODOLOGY.md](METHODOLOGY.md) holds the internal data/geography/scope conventions; `data-notes.qmd` holds the public-facing methodology.

## Start-of-session checklist

1.  Read this file, then [TODO.md](TODO.md), then the top entry of [LOG.md](LOG.md).
2.  Read [METHODOLOGY.md](METHODOLOGY.md) and `_common.R` for the geography/PUMS/scope rules that bear on the task at hand. Do not read the reference repos unless the task sends you there.
3.  Verify that the prerequisite raw files exist under `data/raw/`. If any are missing, do the work that does not need them and record the blocker in the log entry.

## End-of-session checklist

1.  Update [TODO.md](TODO.md) — check off what landed, add anything new that surfaced.
2.  Append a [LOG.md](LOG.md) entry: what changed, data surprises, any 2022 percentage change, what was left open.
3.  Update README.md or this file if a convention changed — same session, not a follow-up.
4.  Commit the work and the log entry together — `hda-git:commit`.

## Commit conventions

`hda-git:commit` owns the full grammar, the staging rules, and the branch-or-main decision. What is specific to this repo:

| Setting | Value |
|------------------------------------|------------------------------------|
| Repo type | Report |
| Commit types | `fix`, `docs`, `chore`, `data`, `content`, `infra` |
| Scope | A component noun (`docs(readme)`, `data(acs-tenure)`, `content(gaps)`). Optional on `docs` and `chore` commits. |
| Versioned | No. Git history plus [LOG.md](LOG.md) is the release record |

## Token efficiency and model policy

- **Start narrow.** Read TODO.md and only the LOG.md/METHODOLOGY.md sections that bear on the task. Do not read whole files when a block will do.
- **Model by session type.** Sonnet for mechanical data pulls, geography swaps, and QA sweeps. Opus for PUMS methodology, gap analysis, and chapter builds. Fable for meta-level investigation and critique only, never for core output.
- **User runs long jobs** — PUMS, CHAS, and tigris pulls, and any full render over roughly two minutes. Claude writes the script; user runs it and pastes back errors and validation output. Never babysit a long `Rscript` run.
- **Manual data drops** for MLS and CoStar go straight into `data/raw/`. User provides them.
- **Skills carry the boilerplate.** Invoke `/new-data-script` before writing a new `r/*.R` pull or prep script, and `/new-chapter` before a new section `.qmd`. Never regenerate the anatomy from scratch in context. Both live in-repo at `.claude/skills/`. Each reads a project-config block from this file, [METHODOLOGY.md](METHODOLOGY.md), and `_common.R` at invocation and creates a pha-shaped scaffold. Full exemplars and a conventions digest are in each skill's `references/`.

## Data flow rule

`r/` scripts write `data/*.rds` and, through `export_csv()`, `data-out/*.csv`. Chapters call `read_rds()` only. **Chapters never call APIs.**

## Code style and script anatomy

Script anatomy: a header comment stating what, source, and output → numbered `## 1. Setup ----` sections → an `.Renviron` fallback for keys → `write_rds()` paired with `export_csv()` → a validation block. Scripts are idempotent and safe to re-run. No inline `install.packages()`.

- Native pipe `|>`, tidyverse style, `janitor::clean_names()` on all imported raw data.
- dplyr 1.2 idioms: `.by=` over `group_by()` for one-off grouping; `across()`; `join_by()`; `reframe()` for multi-row summaries. Use `recode_values()` for value-to-label recodes — the pinned dplyr is 1.2.1 and `case_match()` is soft-deprecated. Reserve `case_when()` for genuine conditional logic.
- `purrr::map()` and `imap()` over `for` loops, bound with `list_rbind()` or `list_cbind()`. The pinned purrr is 1.2.2, in which `map_dfr()` and `map_dfc()` are superseded. Pattern: `map(years, \(yr) get_acs(..., year = yr) |> mutate(year = yr)) |> list_rbind()`.
- tidycensus: `get_acs(geography, state = "VA", table = "BXXXXX", year, survey = "acs5", cache_table = TRUE)`. Pull whole tables and build label lookups from `load_variables()` with `separate_wider_delim(label, "!!")`.

## Validation semantics

- `stopifnot()` fires only on structural expectations (row counts, all geographies present, no all-NA columns) and on **same-vintage** published benchmarks — a HUD-published MFI, a Census-published table total, or the State of Housing deck numbers, which are current as of January 2026.
- 2022 baselines are compared as a **logged percentage change in the session's log entry**, never as a `stopifnot()` gate. Implausible swings are flagged for human review. They never fail a build, because 2020-2024 ACS and 2016-2020 ACS differ by construction.
- Every data phase logs its benchmark results, both passes and variances.

## What `_common.R` provides

- **Palettes:** `pha_pal`, the 6 brand hexes, and `cb_pal` for cost-burden fills.
- **Geography:** `rr` (8), `pha` (4 primary), `secondary` (4), `ashland` (place 5103368, sumlev 160), `virginia`; and the PUMS sets `puma_core3`, `puma_region`, `puma_locality`.
- **Regional chapter geography rule:** Regional findings chapters (`demand.qmd`, `ownership.qmd`, `rental.qmd`, `gaps.qmd`, `burden.qmd`) filter all chart data and inline scalars with `pha` (or `c(pha, "51")` when Virginia appears as a reference). Use `rr` only in `r/` data-collection scripts and in `index.qmd` / `data-notes.qmd` scope statements. Secondary localities are never plotted or named as findings in regional chapters.
- **Caption helpers:** `acs_cap`, `pums_cap`, `chas_cap`, `dec_cap`, `pep_cap`, `wc_cap`, `bps_cap`, `mls_cap`, `costar_cap`, `fmr_cap`, `ami_cap`, `nhpd_cap`, `posh_cap`, `lihtc_cap`, `oews_cap`, `pit_cap`, `eviction_cap`, `vdoe_cap`, `cpi_cap`, `pmms_cap`.
- **`flag_reliability(df, cv_col = cv)`** — High at or below 15, Medium at or below 30, Low above 30, from a **0 to 100** CV. Use it for secondary-locality and Ashland ACS estimates. Do not use `hdatools::add_reliability()`, which assumes a 0 to 1 scale and mislabels small cells as Low.
- **`export_csv(df, name)`** — writes `data-out/<name>.csv`. **Naming is commit policy:** name public-source exports plainly, and prefix MLS and CoStar derivatives `mls_` or `costar_` so `.gitignore` keeps them private.
- **`fct_wrap(f, width)`** — applies `str_wrap()` to a factor's levels.

## Chart and table conventions

- `theme_pha()` with `pha_pal`, plus `add_zero_line()`.
- Titles are takeaway sentences. The subtitle carries geography, units, and years. Captions come from a `_common.R` source helper.
- For 2 or 3 series, prefer color-coded bold words in the subtitle, as ggtext spans using `pha_pal` hexes, over a legend.
- Keep subtitle length to 50 characters to avoid wrapping text onto a new row.
- Currency uses `scales::label_dollar()`, and the subtitle notes whether a series is nominal or inflation-adjusted. Percentages use `label_percent(accuracy = 1)` unless precision matters.
- Tables use `kbl() |> kable_styling(c("condensed","striped"))` with `formattable::comma` and `percent`.
- Secondary-locality and Ashland ACS estimates always carry reliability treatment through `flag_reliability()`. Suppress cells with a CV above 30 and footnote the Medium cells.
- Every figure gets `#| fig-alt:` alt text.

## Narrative rule

Chapters ship with takeaway H2s, 2 to 5 bullet findings per section (plain statements traceable to a figure or table), and callout boxes for the "Since 2022" change and for data caveats. **No drafted paragraphs.** The bullets must be specific enough that a human expands them into prose without reopening the data.

## Execution on Windows

**Never run R inline.** Write `r/<name>.R` and run `Rscript r/<name>.R` from the project root. Ad hoc checks go in a temp script in the scratchpad, run through `Rscript`, never in the repo.

R and Quarto are usually not on PATH. See the quick start in [README.md](README.md) for the prepend and the render commands; the install paths are machine-specific and are documented there and nowhere else.

Use forward slashes in R paths, and keep every path relative to the project root.

## API keys

`CENSUS_API_KEY`, `FRED_API_KEY`, and `GEOCODIO_API_KEY` are all required (the last for MLS geocoding, `r/mls_geocode.R`). They live in your user `.Renviron` at `%USERPROFILE%\Documents\.Renviron`. Never print or commit their values.

R's HOME on Windows may be `C:\Users\<you>` rather than the Documents folder, so that file is not always loaded automatically. Scripts include an `.Renviron` fallback derived from the current user — `readRenviron(file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron"))` when the key is empty — never a hardcoded username. Verify visibility with a TRUE or FALSE check only.

## Data-fetch rule

tidycensus, tigris, and fredr package downloads are approved. Direct fetches from census.gov file servers (BPS, the PEP FTP) and from huduser.gov (CHAS zips, Income Limits) are approved with a manual fallback. Geocodio via `tidygeocoder` (`r/mls_geocode.R`) is approved for MLS address geocoding only. Anything else on a government host, especially BLS OEWS, requires Jonathan's approval or a manual download.

## Publishing status

Public repo, with GitHub Pages live from the start on `main`/`docs` at `https://hdadvisors.github.io/pha-update-2026/`, carrying a **noindex** robots meta tag set in `_quarto.yml` until the report is final. Phase 7 removes it. PHA reviewers comment through a **private** Hypothesis group, because Hypothesis annotations are public by default.

## Known gotchas

- **PEP** — the post-2020 API requires an explicit `vintage=` argument; `year=` alone misbehaves silently. Use Vintage 2025 and fall back to the FTP tables if the API lags.
- **huduser.gov** — send a browser User-Agent and Referer or the server returns 202 or an empty body. The CHAS data dictionary is a separate download from the table zips.
- **gridtext and `theme_pha`** — an `@fig`, `@tbl`, or `@sec` cross-reference inside `labs(caption=)` or a kbl `footnote()` throws a gridtext `<a>`-tag error. Keep cross-references in markdown bullets.
- **ggplot2 4.0 (S7)** — override strip text with `ggtext::element_markdown()`, never a raw `element_text()`. `theme_pha`'s strip element is a ggtext markdown element and ggplot2 4.0 only merges theme elements of the same class, so an `element_text()` override is the thing that clashes. Faceting is fine; the override just has to match the class. Documented at `hdatools/R/themes.R`, `theme_pha`'s `@details`.
- **PUMS `RNTP` is 0, not NA, outside the cash-renter universe.** It arrives as a hard 0 on every owner-occupied row (15,558 on the core-3 file) and on every no-cash-rent renter row (221). A 0 there means no rent is charged, not a rent of zero. An affordability test that reads `RNTP` ungated scores all of them as the cheapest units in the file, clearing every rent ceiling at every AMI threshold. Gate on `tenure_detail == "Renter"` before using it. `r/pums/pums_prep.R`'s `contract_rent_nominal` does this, and its section 10a asserts the gate. Found while switching `r/pums/pums_gap.R` to a contract-to-contract rent comparison.
- **`dplyr::join_by(a == b)` on differently-named columns** — the joined result keeps only `a`, silently dropping `b`. A downstream `mutate()` or `select()` that expects `b` to survive gets a column-not-found error, or worse, an `NA` after a `bind_rows()` masks the missing column with a same-named one from another frame. Join on the equal-named keys only and enforce the cross-name equality with a `filter()` immediately after, so both columns survive. Found while building `r/mls_clean.R`'s cross-MLS price-tolerance match.
- **5-year PUMS dollars** — `HINCP`, `GRNTP`, and `SMOCP` are reported in each record's own survey-year dollars, and `ADJINC`/`ADJHSG` are the only thing in the file encoding which year a record came from. Omit them and AMI banding against a current-year income limit pushes early-year households one tier too low; on the 2020-2024 sample the median household income moves 11.6%. Ratios like cost burden are unaffected — compute those on nominal dollars, where the two factors cancel. Found while building `r/pums/pums_prep.R`.
- **tidycensus scales `ADJINC` but not `ADJHSG`** — both arrive as character, but `ADJINC` comes back already divided (`"1.015250"`) while `ADJHSG` stays a raw 7-digit integer (`"1000000"`). A single `/1e6` is wrong for one of them. `adj_factor()` in `r/pums/pums_prep.R` rescales only values still in integer form.
- **`get_pums()` + `return_vacant`: unconditional `VACS` append duplicates a user-supplied `VACS`, crashing on an unrelated `WGTP` mutate.** Confirmed 2026-09-09 by reading tidycensus 1.8.1 source (`R/pums.R`): `if (return_vacant) variables <- c(variables, "VACS")` never checks whether `"VACS"` is already in `variables`. Passing `return_vacant = TRUE` alongside an explicit `"VACS"` in `variables` — the natural way to request the vacancy-status code as an output column — duplicates it, the Census API returns two identically named `VACS` columns, and the very next step, `mutate(across(contains("WGTP"), as.numeric))`, fails with "Can't transform a data frame with duplicate names." dplyr's duplicate-name guard fires on the whole data frame, not just the targeted `WGTP` columns, which is why the error names `WGTP` instead of the actual duplicate. Fix: don't pass `return_vacant = TRUE` at all. `get_pums()` has a second, independent check — `if ("VACS" %in% variables) return_vacant <- TRUE` — that runs *after* the duplicating append and fires whenever `"VACS"` is already listed, regardless of the argument. Listing `"VACS"` explicitly is enough; tidycensus infers `return_vacant` on its own without duplicating it. Confirmed live: identical row counts and full `VACS` population on vacant rows whether `return_vacant` is passed explicitly (with `"VACS"` omitted, so no duplicate) or omitted entirely (with `"VACS"` left in `variables`, inferred instead). Separately, `get_pums()` also splits variable lists over 45 into batches of 45, and `VACS` anywhere in a batch infers `return_vacant` for that batch alone — a batch made up entirely of person-record variables can then fail at the Census API with a blank error message; this is why `r/pums/pums_collect.R` keeps its vacant supplement call (5 variables — `PUMA`, `TEN`, `RNTP`, `VACS`, `BDSP` — well under the batch threshold) separate from the 48-variable person+housing main call. `RNTP` sits in the main call as well and is safe there: neither of the two `return_vacant` checks reads it, so a person-only trailing batch stays harmless. Found and corrected while building `r/pums/pums_collect.R`; two earlier, incorrect diagnoses of this same crash are superseded — see LOG.md.

## Repo map

```         
pha-update-2026/
├── _quarto.yml            # book config: freeze auto, execute-dir project, output-dir docs, noindex meta, Hypothesis
├── _common.R              # sourced by every chapter: libs, pha_pal/cb_pal, geo+PUMA constants, caption helpers, flag_reliability(), export_csv()
├── .Rprofile              # source("renv/activate.R")
├── renv.lock / renv/      # R pinned 4.6.1; dplyr 1.2.1; hdatools from GitHub hdadvisors/hdatools
├── CLAUDE.md              # this file
├── METHODOLOGY.md         # internal data/geography/scope conventions
├── TODO.md                # the punch list — start here
├── LOG.md                 # append-only dev log
├── README.md              # purpose, quick start, plain-language renv guide, status
├── rrh-framework.scss     # brand styling (Noto Sans; from rrh)
├── img/pha_logo.jpg       # sidebar logo (from rrh)
├── index.qmd              # About this update
├── demand.qmd             # Section 1 Housing demand
├── ownership.qmd          # Section 2 Homeownership market
├── rental.qmd             # Section 3 Rental market
├── gaps.qmd               # Section 4 Housing gap
├── burden.qmd             # Section 5 Cost burden and instability
├── data-notes.qmd         # Appendix: data and methodology (public-facing; doubles as PHA training doc)
├── local-*.qmd            # 9 local summaries — stubs, not yet built
│                          # + tracker.qmd, exec-sum.qmd — not yet started
├── r/                     # collection and prep scripts — committed (r/pums/ not yet built)
├── data/                  # .rds outputs and raw drops — gitignored (except data/raw/README.md)
│   └── raw/{mls,costar}/  # Jonathan's manual drops (spec: data/raw/README.md)
├── data-out/              # tidy CSV exports; public-source committed, mls_*/costar_* gitignored
├── docs/                  # rendered site — committed; GitHub Pages serves this
├── _freeze/               # committed (keeps renders fast and reproducible)
└── archive/soh-2026/      # archived State of Housing deliverables (committed; retained)
```

- Repo: `hdadvisors/pha-update-2026`, public. Pages serves `docs/` on `main`.
- Theming: `hdatools::theme_pha()` and `pha_pal` everywhere. Static ggplot2 and kableExtra tables. No leaflet, no ggiraph — see [METHODOLOGY.md](METHODOLOGY.md).
- Chapter anatomy: `# Title {#sec-slug}` → setup chunk (`source("_common.R")`, `read_rds()` stubs, inline-scalar block) → theme-based takeaway H2s → alternating figure and table blocks with bullets → a per-section "Since 2022" callout → a closing summary callout. The `/new-chapter` skill emits this shape.

## Geography and vintages

Geography and PUMS constants are defined once in `_common.R` (`rr`, `pha`, `secondary`, `ashland`, `virginia`, `puma_core3`, `puma_region`, `puma_locality`). The geography table, vintage table, and dataset inventory that used to live here now live in git history (`.planning/PLAN.md`, removed 2026-08-26) — [METHODOLOGY.md](METHODOLOGY.md) carries forward only the conventions still worth stating explicitly; the rest is legible directly from `_common.R` and the `r/` scripts.
