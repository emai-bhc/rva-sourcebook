---
name: new-data-script
description: >
  Scaffold a new r/*.R data-collection or prep script following an BHC Quarto data
  project's script anatomy (header → numbered sections → write_rds + export_csv →
  validation block). Use whenever creating a new data-pull or data-prep script in an
  BHC data project. Trigger on requests like "new data script", "scaffold r/<name>.R",
  "start the ACS/PEP/CHAS/PUMS pull script".
---

# new-data-script

Scaffold a new `r/<name>.R` collection/prep script that matches the target project's
script anatomy and R standards. This skill is **project-agnostic**: it carries the
shared BHC script structure but reads the *specific* project's paths, geographies, and
conventions from that project's own docs at invocation. Nothing project-specific is
hardcoded here — that is what keeps the skill portable across BHC data projects.

## How to use this skill

1. **Populate the project-config block** (below) by reading the target project's docs.
   Do this first — everything downstream depends on it.
2. **Emit the script skeleton**, substituting the config values, adapted to the dataset
   the user named (which tables/API, which geographies, how many pull sections).
3. **Write it to `r/<name>.R`** and remind the user of the run/validation workflow.

Keep `references/conventions.md` (R-standards + validation-semantics digest) and
`references/exemplar-script.R` (the canonical best-practice reference — a filled-in instance
of the skeleton below, safe to copy from) on hand. Read them if you need the full idiom, but
you usually won't need to re-read them each time.

## Step 1 — Populate the project-config block

Read these sources in the target project root and fill the block:

- **`CLAUDE.md`** — quick-start run commands, R version + bin path, data-flow rule,
  script anatomy, validation semantics, `_common.R` provisions, API-key handling,
  Windows R rule, commit style.
- **`METHODOLOGY.md`** (or equivalent internal conventions file) — geography and PUMS
  scope rules, out-of-scope datasets, `data-out/` commit policy. Code style and
  validation semantics may live in `CLAUDE.md` instead; take whichever file states them.
- **`_common.R`** — the actual names of palettes, geography constants, caption helpers,
  `flag_reliability()`, `export_csv()` (source these; don't redefine them).
- **`TODO.md`** (or equivalent punch list) — which dataset this script is meant to cover, if it's not obvious from the ask.

```
### PROJECT CONFIG (fill from CLAUDE.md / METHODOLOGY.md / _common.R before scaffolding)
Project root        : <local clone path, e.g. C:\repos\hda\pha-update-2026>
R version + bin path: <R 4.6.x — your local bin, e.g. C:\Program Files\R\R-4.6.1\bin ; NOT on PATH — prepend first>
Run a script        : <e.g. Rscript r/<name>.R  (from project root; .Rprofile activates renv)>
API keys            : <env vars CENSUS_API_KEY/FRED_API_KEY + user-derived .Renviron fallback:
                       readRenviron(file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")) ; HOME gotcha → include fallback>
Geography constants : <names + where defined, e.g. rr(8)/pha(4)/secondary(4)/ashland(160)/
                       virginia + PUMS puma_core3/puma_region/puma_locality, in _common.R>
_common.R provides  : <palettes, caption helpers, flag_reliability(cv 0-100), export_csv()>
Output dirs + naming: <data/<name>.rds (gitignored) + data-out/<name>.csv ; public-source
                       named plainly, mls_/costar_ prefixes stay private per .gitignore>
Validation semantics: <stopifnot ONLY on structure + same-vintage benchmarks (incl. SOH deck);
                       2022 baseline = logged % change, flagged if implausible, NEVER hard-failed>
Vintages            : <e.g. ACS 2020-2024, PEP Vintage 2025, CHAS 2018-2022, HUD FY2026>
Windows R rule      : <never run R inline; write r/<name>.R, run via Rscript; ad-hoc → scratchpad>
Commit style        : <type(scope): subject — data(task-N) for a new/changed pull script>
```

If a field isn't in the docs, ask the user rather than guessing — a wrong path or a
hardcoded geography defeats the point of the config block.

## Step 2 — Emit the script skeleton

Substitute the config values. Adapt the numbered pull sections to the dataset the user
named. This is the canonical anatomy (see `references/exemplar-script.R` for a full
worked example):

```r
# <name>.R ----
# What:   <one line — what this script collects/prepares>
# Source: <API/package + vintage, e.g. tidycensus ACS 5-year 2020-2024>
# Tables: <if applicable — table IDs + short gloss>
# Output: data/<name>.rds  (+ data-out/<name>.csv)

## 1. Setup ----
library(tidyverse)
library(tidycensus)   # or fredr / other pull package as needed
library(janitor)
source("_common.R")   # geo constants, caption helpers, flag_reliability(), export_csv()

# .Renviron fallback (R's HOME may not be ~/Documents — CLAUDE.md API-keys gotcha)
if (Sys.getenv("<KEY_NAME>") == "") {
  renviron_path <- "<.Renviron path from config>"
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}

dir.create("data", showWarnings = FALSE, recursive = TRUE)

## 2. <ACS pull helper — factor out repeated multi-geography binds> ----
# One helper pulls a table across geography levels, tags geo_type, adds a 0-100 CV.
# imap() + list_rbind() is the purrr 1.2.2 idiom (map_dfr() is superseded — avoid it).
# See pull_acs() in exemplar-script.R for the worked version.
pull_acs <- function(table, geos, yr = <year>) {
  geos |>
    imap(\(ids, level) {
      d <- get_acs(geography = level, state = "VA", table = table,
                   year = yr, survey = "acs5", cache_table = TRUE) |>
        clean_names() |>                  # janitor on raw imports: GEOID -> geoid
        mutate(geo_type = level)
      if (is.null(ids)) d else filter(d, geoid %in% ids)
    }) |>
    list_rbind() |>
    mutate(
      year = yr,
      cv   = if_else(estimate > 0, (moe / 1.645) / estimate * 100, NA_real_)  # 0-100 for flag_reliability()
    )
}

## 3. <First pull — e.g. B01003 total population> ----
message("Pulling <table>...")
<obj> <- pull_acs("<TABLE>", list(
  county = <geo constant>,        # e.g. Ashland place (sumlev 160) as `place = ...`
  state  = NULL                   # NULL keeps all rows (e.g. the whole-state row)
))
message("<table> pulled: ", nrow(<obj>), " rows")

## 4. <Additional pull / recode sections as needed> ----
# For variable→label recoding use recode_values() (dplyr 1.2.0's value-map idiom;
# replaces soft-deprecated case_match — c(...) ~ label, default = NA). Reserve
# case_when() for genuine conditional logic. map() + list_rbind() over year loops
# (never map_dfr()); .by = for one-off grouping; separate_wider_delim(label, "!!").

## N. Write output ----
write_rds(
  list(<obj1> = <obj1>, <obj2> = <obj2>),   # a named list, or a single tibble
  "data/<name>.rds"
)
export_csv(<obj_or_tidy_frame>, "<name>")    # → data-out/<name>.csv (naming = commit policy)
message("Wrote data/<name>.rds + data-out/<name>.csv")

## N+1. Validate ----
d <- read_rds("data/<name>.rds")
# stopifnot() ONLY on structure + same-vintage benchmarks:
stopifnot(
  nrow(d$<obj1>) > 0,
  all(<expected geographies> %in% d$<obj1>$geoid),   # geoid: clean_names() lowercases GEOID
  !anyNA(d$<obj1>$estimate)              # no all-NA columns
)
# stopifnot(between(<current benchmark>, <lo>, <hi>))   # e.g. vs SOH deck (same vintage)
# If no same-vintage published benchmark exists for a metric, structural checks
# (above) are sufficient — don't invent a threshold.

# 2022 baseline: LOG the % change; never stopifnot() it (vintages differ by construction).
# Compute vs baseline_2022 and print it for the session log; flag implausible swings for review.
message("<name>.R validation passed.")
```

## Step 3 — Remind of the workflow

State these back to the user:

- **Run it:** prepend the R bin path, then `Rscript r/<name>.R` from project root. **Never
  run R inline on Windows.** Long pulls (PUMS/CHAS/tigris/full renders) are Jonathan's to
  run — write the script, hand it off, don't babysit.
- **Idempotent** — safe to re-run; no inline `install.packages()`.
- **Reliability boundary:** data scripts only *emit* the 0–100 `cv` column. Tiering with
  `flag_reliability()` (and suppression/footnoting) happens **downstream in chapters** — don't
  tier in the script.
- **2022 baselines** are logged as % change in the progress log, never a `stopifnot()` gate.
- **Commit** per the project's style guide (e.g. `data(task-N): <subject>`), with the
  validated numbers + 2022 deltas in the body.

## Portability note

This skill lives in-repo (`.claude/skills/`) while it proves out. The project-config-block
design is deliberate: the same SKILL.md works for fhfh, pha-update-2026, and future HDA
Quarto data projects because it reads each project's own docs. When elevating to user-level
(`~/.claude/skills/`), nothing here needs rewriting — only the exemplar in `references/`
may be swapped for a more representative one.