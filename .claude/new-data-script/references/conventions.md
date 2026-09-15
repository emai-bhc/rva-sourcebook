# R-standards & validation digest (data scripts)

Condensed from the HDA project conventions (CLAUDE.md, plus the PLAN). Read this when you
need the full idiom; the SKILL.md body covers the common path. `references/exemplar-script.R`
is the canonical best-practice reference script demonstrating all of it — it reads as a
filled-in instance of the SKILL.md skeleton, so treat it as a copy source, not just an anatomy.

## Code style

- **Native pipe `|>`**; tidyverse style. `janitor::clean_names()` on all imported raw data.
- **dplyr 1.2.0 idioms** (pinned **1.2.1**, so all of these are available): `.by=` over
  `group_by()` for one-off grouping (now stable); `across()`; `join_by()`; `reframe()` for
  multi-row summaries (now stable). Also new in 1.2.0 and fair game: `when_any()` / `when_all()`
  (elementwise OR / AND inside a condition), `replace_values()` (update *some* values, keep the
  rest), `filter_out()` (companion to `filter()` naming rows to drop).
- **Variable→label recoding uses `recode_values()`** — dplyr 1.2.0's value-mapping function and
  the named replacement for the soft-deprecated `case_match()`. Formula interface `old ~ new`
  (group values with `c()`, e.g. `c(3:6, 27:30) ~ "Under 18"`), unmatched handled by `default =`
  (note: `default`/`unmatched`, no dot prefix). Reserve **`case_when()`** for genuine conditional
  logic (comparisons, compound predicates) — not value lookups.
- `purrr::map()` / `imap()` over `for` loops, combined with **`list_rbind()` / `list_cbind()`**
  to bind the results. The pinned purrr is **1.2.2**, where `map_dfr()` / `map_dfc()` are
  **superseded** — use the split form. Year-trend pattern:
  `map(years, \(yr) get_acs(..., year = yr) |> mutate(year = yr)) |> list_rbind()`.
  Multi-geography pull: an `imap()` helper keyed by geography level, then `list_rbind()`
  (see `pull_acs()` in the exemplar).
- **tidycensus:** `get_acs(geography, state = "VA", table = "BXXXXX", year, survey =
  "acs5", cache_table = TRUE)`. Pull whole tables; build label lookups from
  `load_variables()` + `separate_wider_delim(label, "!!")`.

## Script anatomy (mandatory order)

1. **Header comment** — what / source (+ vintage) / tables / output.
2. `## 1. Setup ----` — libraries, `source("_common.R")`, `.Renviron` fallback for keys,
   `dir.create("data")`.
3. **Numbered pull sections** (`## 2.`, `## 3.`, …), one per table/source, each with a
   `message()` progress line and a `nrow()` confirmation.
4. `write_rds()` to `data/<name>.rds` **paired with** `export_csv()` to `data-out/`.
5. **Validation block** (see below).

Idempotent — safe to re-run. **No inline `install.packages()`.**

## Reliability CV convention

Carry a **0–100** CV column: `cv = if_else(estimate > 0, (moe / 1.645) / estimate * 100,
NA_real_)`. Chapters tier it with `_common.R`'s `flag_reliability()` (High ≤15 / Medium ≤30
/ Low >30). **Not** `hdatools::add_reliability()` — that assumes a 0–1 scale and mislabels
small-geography cells. Secondary-locality + Ashland (place, sumlev 160) estimates always
get reliability treatment downstream, so always emit the `cv` column for them.

## Validation semantics (locked)

- `stopifnot()` fires **only** on: (a) **structure** — row counts > 0, all expected
  geographies present, no all-NA columns; and (b) **same-vintage** published benchmarks —
  a Census-published table total, HUD-published MFI, or the **SOH deck** numbers (current,
  Jan 2026).
- **2022 baselines** (transcribed from the predecessor's rendered site) are compared as a
  **logged % change** in the progress log — **never** a `stopifnot()` gate. 2020-2024 ACS
  vs 2016-2020 ACS differ by construction; implausible swings get flagged for human review,
  not a failed build.
- Every data task logs its benchmark results (pass + variance + 2022 deltas) to the session log.

## API keys

Env vars (`CENSUS_API_KEY`, `FRED_API_KEY`) live in a `.Renviron` outside the project,
under the current user's `Documents`. **HOME gotcha:** R's HOME may be `C:\Users\<you>`
rather than `…\Documents`, so `~/Documents/.Renviron` isn't always auto-loaded — every
script includes a user-derived fallback (never a hard-coded username):
`if (Sys.getenv("KEY") == "") readRenviron(file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron"))`.
Never print or commit key values; verify visibility with a TRUE/FALSE check only.

## Data-fetch rule

tidycensus / tigris / fredr package downloads are approved. Census file servers (BPS, PEP
FTP) and huduser.gov (CHAS, Income Limits) are approved **with manual fallback** — huduser
soft-blocks bare user-agents (send a full browser UA + Referer). Anything else on a
government host (esp. BLS OEWS) needs the user's OK or a manual download.

## Known gotchas

- **PEP:** post-2020 API needs an explicit `vintage=` arg (`year=` alone misbehaves); FTP
  fallback if the API lags.
- **huduser.gov:** browser User-Agent + Referer or returns 202/empty. CHAS data dictionary
  is a **separate** download.
- **Windows:** never run R inline; write the script, run via `Rscript`. Ad-hoc checks →
  scratchpad, not the repo.

## data-out/ commit policy

`export_csv(df, name)` writes `data-out/<name>.csv`. **Naming enforces commit policy via
.gitignore:** name public-source exports plainly (`acs_tenure`); prefix MLS/CoStar-derived
ones `mls_` / `costar_` so they stay out of the public repo and are delivered privately.