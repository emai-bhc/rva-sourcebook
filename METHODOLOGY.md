# METHODOLOGY.md — internal conventions

Internal reference for geography, vintages, and scope decisions. `data-notes.qmd` is the public-facing version of this file — keep the two in sync when a convention here is stable enough to publish.

## Geography

Defined once in `_common.R`, sourced by every script and page.

| Name | Localities | Role |
|---|---|---|
| `rr` | 17 localities (Richmond, Henrico, Chesterfield, Hanover, Goochland, Powhatan, New Kent, Charles City, Petersburg, Hopewell, Colonial Heights, Amelia, Dinwiddie, King & Queen, King William, Prince George, Sussex) | Full Richmond region — use for region-wide boundary pulls and reference framing |
| `bhc` | Richmond city, Henrico, Chesterfield | Core 3 — the default geography for most charts/tables unless a page needs the full region |
| `secondary` | Hanover, Goochland, New Kent, Powhatan | Expansion ring — always carry `flag_reliability()` when plotted, since ACS estimates get noisier here |
| `ashland` | Town of Ashland (place GEOID 5103368, sumlev 160) | Place-level pull inside Hanover County |
| `regions` | Charlottesville, Richmond, Hampton Roads, DC MSAs | Comparison metros for selective benchmarking |
| `virginia` | State FIPS `51` | Statewide reference |

`bhc` is inherited naming from the scripts that first defined this project's core geography — it does not signal a client relationship. If it gets confusing, a future session can rename it (e.g. to `core`), but that's a mechanical rename across `_common.R` and the two existing `r/` scripts, not a priority.

### PUMS geography (defined, not yet used)

`puma_core3`, `puma_region`, and `puma_locality` are already set up for a 2020-vintage PUMS pull covering Chesterfield, Henrico, and Richmond city (which tile cleanly into whole PUMAs) plus two mixed outer PUMAs. This groundwork came along with the geography constants when `_common.R` was first written and is harmless to keep, but no PUMS script exists in this repo yet and none is planned for v1 — see PLAN.md's "future" phase.

## Vintages

| Source | Vintage in use |
|---|---|
| ACS 5-year | Three non-overlapping 5-year windows ending **2014, 2019, 2024** — the trend convention `acs_tenure.R` set and `acs_stock.R` follows. Overlapping 5-year samples are not independent, so the site never plots consecutive windows against each other. Check `acs_burden.R`'s header for its own vintage |
| tigris boundaries | 2023 cartographic boundary (500k), per `r/geo.R` |
| BPS permits | See `r/bps_permits.R`'s header |
| PEP county estimates | **Two vintages that do not join:** Vintage 2019 (2010–2019) and Vintage 2025 (2020–2025), from the Census `co-est*-alldata.csv` files cached under `data/cache/pep/`. See `r/pep_migration.R`'s header |

### Table-level scope notes

- **`acs_stock.R`** covers B25001 (total units), B25002 (occupancy), B25004 (vacancy status), B25024 (units in structure), B25034 (year built), and B25035 (median year built). **B25036 (year built by tenure) is out of scope for v1** — it is not published in the 2014 window, which would break the three-window trend every other frame in that script carries. B25035 is a median and cannot be summed, so unlike the other frames it carries no pooled `bhc3`/`secondary4` rows.
- **Pooled rows.** Frames that hold counts carry two synthetic geographies alongside the published ones: `bhc3` (the 3 core localities) and `secondary4` (the 4 expansion localities). Counts add and MOEs combine in quadrature, both computed in the `r/` script so pages only filter and plot. Ashland sits inside Hanover and is therefore never pooled — doing so would double-count it.
- **`pep_migration.R` (PEP components of change).** Never join the two vintages: Vintage 2020+ is built on the 2020 Census base, so the 2019 → 2020 population step spans a methodology break and is not computed — each of the two eras (2010–2019, 2020–2025) is summarized inside one vintage. The 2010 and 2020 components cover only April 1 – June 30 and are set to NA (population is kept). The files, not `tidycensus::get_estimates()`, are the source because the API returns only a vintage's latest year. Rates are per 1,000 over the average of start- and end-year population. No Ashland (PEP has no sub-county components) and no comparison metros (CBSA delineations differ across the two vintages). Pooled `bhc3`/`secondary4`/`rr17` and Virginia are plain sums — PEP counts are administrative estimates with no MOE. PEP and ACS growth rates measure different periods with different methods and are never compared directly.
- **`cache_table = TRUE`** is now a no-op: current tidycensus deprecates it in favor of Census API groups and warns once per call. Harmless, and CLAUDE.md still prescribes it, so scripts keep passing it; drop it project-wide in a dedicated cleanup rather than piecemeal.

Keep this table current as scripts are added — it's the fastest way for a session to know what year's data is actually on the site without opening every script.

## Scope decisions

- **Public data only.** No MLS, no CoStar, no CHAS, no PUMS-based gap analysis for v1. Everything here comes from a package (`tidycensus`, `tigris`) or a public government file server.
- **Three pages, not five.** The sibling project this repo's early docs were copied from split market data into `ownership.qmd` + `rental.qmd`; this project combines that into one `market.qmd`, matching the simpler three-area scope (inventory / demographics / market).
- **No reliability gate on the `bhc` core.** `flag_reliability()` is reserved for `secondary` and `ashland` estimates, where small populations push CVs up. The 3-locality core is large enough that this isn't usually needed, but check CVs before assuming that on any new table.

## Reference: sibling-project debris

Two prior docs in this repo (an earlier CLAUDE.md/TODO.md pair, and a PLAN.md) described a materially larger project — PUMS gap analysis, CHAS tables, MLS/CoStar pipelines, a 5-chapter book, vulnerable-populations data — that was never actually built here. Those docs were copied from a sibling Richmond-nonprofit engagement and a separate Fauquier County study, respectively, and rewritten on 2026-09-15 to match what actually exists in this repo. If a future session finds a stray reference to `pha`, `puma_core3`-driven chapters, `r/chas.R`, `r/mls_*`, or Fauquier/Better Housing Coalition anywhere, it's leftover — flag it rather than trusting it.
