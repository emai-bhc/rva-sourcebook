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
| ACS 5-year | Whatever the two existing scripts (`acs_tenure.R`, `acs_burden.R`) pull — check their header comments; update this table as new scripts land |
| tigris boundaries | Latest available at time of pull — record the year in `r/geo.R`'s header |
| BPS permits | Not yet pulled |

Keep this table current as scripts are added — it's the fastest way for a session to know what year's data is actually on the site without opening every script.

## Scope decisions

- **Public data only.** No MLS, no CoStar, no CHAS, no PUMS-based gap analysis for v1. Everything here comes from a package (`tidycensus`, `tigris`) or a public government file server.
- **Three pages, not five.** The sibling project this repo's early docs were copied from split market data into `ownership.qmd` + `rental.qmd`; this project combines that into one `market.qmd`, matching the simpler three-area scope (inventory / demographics / market).
- **No reliability gate on the `bhc` core.** `flag_reliability()` is reserved for `secondary` and `ashland` estimates, where small populations push CVs up. The 3-locality core is large enough that this isn't usually needed, but check CVs before assuming that on any new table.

## Reference: sibling-project debris

Two prior docs in this repo (an earlier CLAUDE.md/TODO.md pair, and a PLAN.md) described a materially larger project — PUMS gap analysis, CHAS tables, MLS/CoStar pipelines, a 5-chapter book, vulnerable-populations data — that was never actually built here. Those docs were copied from a sibling Richmond-nonprofit engagement and a separate Fauquier County study, respectively, and rewritten on 2026-09-15 to match what actually exists in this repo. If a future session finds a stray reference to `pha`, `puma_core3`-driven chapters, `r/chas.R`, `r/mls_*`, or Fauquier/Better Housing Coalition anywhere, it's leftover — flag it rather than trusting it.
