# =============================================================================
# CANONICAL reference script for /new-data-script. This IS the shape the skill
# should emit: purrr 1.2.2 idiom (map()/imap() + list_rbind(), NOT map_dfr()),
# recode_values() value maps (dplyr 1.2.0; case_when() only for conditional logic),
# source("_common.R"), write_rds() paired with export_csv(),
# a 0-100 CV column, an .Renviron fallback, and a validation block that hard-
# fails only on structure + same-vintage benchmarks while LOGGING the 2022 delta.
# Subject matter (Fauquier County + towns + benchmarks, ACS 2020-2024) is carried
# over from an fhfh pull; the code models current best practice, not fhfh's older
# idioms. Adapt the geographies/tables/vintage to the target project's inventory row.
# =============================================================================

# acs_demographics.R ----
# What:   ACS 5-year demographic tables for Fauquier County, its towns, benchmark
#         counties, and Virginia — tidy long frame for the demographics chapter.
# Source: tidycensus ACS 5-year 2020-2024 (2024 endpoint)
# Tables: B01003 (total population), B01001 (sex by age → 5 bands),
#         B03002 (race/ethnicity, with an Other/Multiracial remainder)
# Output: data/acs_demographics.rds  (+ data-out/acs_demographics.csv)

## 1. Setup ----
library(tidyverse)
library(tidycensus)
library(janitor)
source("_common.R") # export_csv(), flag_reliability(), caption + palette helpers

# .Renviron fallback — R's HOME may not be ~/Documents, so the key file isn't
# always auto-loaded (CLAUDE.md API-keys gotcha). Load it only if the key is unset.
if (Sys.getenv("CENSUS_API_KEY") == "") {
  renviron_path <- file.path(
    Sys.getenv("USERPROFILE"),
    "Documents",
    ".Renviron"
  )
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}

dir.create("data", showWarnings = FALSE, recursive = TRUE)

# Geographies. In a project whose _common.R defines these (e.g. pha's rr / pha /
# secondary / ashland), source them from there instead of redefining here.
fauquier <- "51061"
towns <- c(warrenton = "5183136", bealeton = "5105336")
benchmarks <- c(culpeper = "51047", prince_william = "51153", loudoun = "51107")

## 2. ACS pull helper ----
# Pull one ACS table across a set of geography levels, tag geo_type, and carry a
# 0-100 CV for downstream flag_reliability(). `geos` is a named list keyed by
# tidycensus geography level; each value is the GEOIDs to keep (NULL = keep all,
# e.g. the whole state row). imap() + list_rbind() is the purrr 1.2.2 idiom —
# map_dfr() is superseded and avoided project-wide.
pull_acs <- function(table, geos, yr = 2024) {
  geos |>
    imap(\(ids, level) {
      d <- get_acs(
        geography = level,
        state = "VA",
        table = table,
        year = yr,
        survey = "acs5",
        cache_table = TRUE
      ) |>
        clean_names() |> # janitor on raw import: GEOID -> geoid, etc.
        mutate(geo_type = level)
      if (is.null(ids)) d else filter(d, geoid %in% ids)
    }) |>
    list_rbind() |>
    mutate(
      year = yr,
      cv = if_else(estimate > 0, (moe / 1.645) / estimate * 100, NA_real_)
    )
}

## 3. B01003 – Total population ----
# Benchmark counties included at the county level for comparison; towns + VA too.
message("Pulling B01003...")
b01003 <- pull_acs(
  "B01003",
  list(
    county = c(fauquier, unname(benchmarks)),
    place = unname(towns),
    state = NULL
  )
)
message("B01003 pulled: ", nrow(b01003), " rows")

## 4. B01001 – Sex by age, collapsed to 5 bands ----
# Fauquier + towns + VA only (benchmarks not needed for age structure).
# Male var 003-025, female 027-049; band by variable suffix number.
message("Pulling B01001...")
b01001 <- pull_acs(
  "B01001",
  list(
    county = fauquier,
    place = unname(towns),
    state = NULL
  )
) |>
  mutate(
    var_num = as.integer(str_extract(variable, "\\d+$")),
    # recode_values() is dplyr 1.2.0's value-mapping idiom and the named
    # replacement for the soft-deprecated case_match(). Use it for value->label
    # maps like this; reserve case_when() for genuine conditional logic. c() on
    # the LHS maps a set of values to one label; `default` catches the rest.
    age_band = recode_values(
      var_num,
      c(3:6, 27:30) ~ "Under 18",
      c(7:11, 31:35) ~ "18-34",
      c(12:19, 36:43) ~ "35-64",
      c(20:22, 44:46) ~ "65-74",
      c(23:25, 47:49) ~ "75+",
      default = NA_character_
    )
  ) |>
  filter(!is.na(age_band)) |>
  # .by for one-off grouping; recompute a combined MOE for the summed band.
  summarize(
    estimate = sum(estimate, na.rm = TRUE),
    moe = sqrt(sum(moe^2, na.rm = TRUE)),
    year = unique(year),
    .by = c(geoid, name, geo_type, age_band)
  ) |>
  mutate(cv = if_else(estimate > 0, (moe / 1.645) / estimate * 100, NA_real_))
message(
  "B01001 banded: ",
  nrow(b01001),
  " rows (5 bands x ",
  n_distinct(b01001$geoid),
  " geographies)"
)

## 5. B03002 – Race/ethnicity ----
# Key groups + a derived Other/Multiracial remainder (Total minus the named groups).
message("Pulling B03002...")
b03002_key <- pull_acs(
  "B03002",
  list(
    county = fauquier,
    place = unname(towns),
    state = NULL
  )
) |>
  mutate(
    race_group = recode_values(
      variable,
      "B03002_001" ~ "Total",
      "B03002_003" ~ "Non-Hispanic White",
      "B03002_004" ~ "Non-Hispanic Black",
      "B03002_006" ~ "Non-Hispanic Asian",
      "B03002_012" ~ "Hispanic or Latino",
      default = NA_character_
    )
  ) |>
  filter(!is.na(race_group))

# Other/Multiracial = Total − (named groups). MOE of a remainder: sqrt(sum of
# constituent MOEs squared).
b03002_other <- b03002_key |>
  summarize(
    estimate = estimate[race_group == "Total"] -
      sum(estimate[race_group != "Total"], na.rm = TRUE),
    moe = sqrt(sum(moe^2, na.rm = TRUE)),
    year = unique(year),
    .by = c(geoid, name, geo_type)
  ) |>
  mutate(variable = "B03002_other", race_group = "Other/Multiracial")

b03002 <- bind_rows(b03002_key, b03002_other) |>
  mutate(cv = if_else(estimate > 0, (moe / 1.645) / estimate * 100, NA_real_))
message(
  "B03002 pulled: ",
  nrow(b03002),
  " rows (",
  n_distinct(b03002$race_group),
  " groups)"
)

## 6. Combine into one tidy long frame ----
# Stack the tables with a shared shape (table + group label) so chapters can
# read_rds() a single frame. Keep geoid/name/geo_type/year/estimate/moe/cv.
acs_demographics <- bind_rows(
  b01003 |>
    transmute(
      geoid,
      name,
      geo_type,
      year,
      table = "B01003",
      group = "Total population",
      estimate,
      moe,
      cv
    ),
  b01001 |>
    transmute(
      geoid,
      name,
      geo_type,
      year,
      table = "B01001",
      group = age_band,
      estimate,
      moe,
      cv
    ),
  b03002 |>
    transmute(
      geoid,
      name,
      geo_type,
      year,
      table = "B03002",
      group = race_group,
      estimate,
      moe,
      cv
    )
)

## 7. Write output ----
write_rds(acs_demographics, "data/acs_demographics.rds")
export_csv(acs_demographics, "acs_demographics") # -> data-out/acs_demographics.csv
message("Wrote data/acs_demographics.rds + data-out/acs_demographics.csv")

## 8. Validate ----
dem <- read_rds("data/acs_demographics.rds")

# Structure — hard-fail on shape only.
stopifnot(
  nrow(dem) > 0,
  all(c(fauquier, unname(towns)) %in% dem$geoid), # expected geographies present
  !anyNA(dem$estimate) # no all-NA estimate column
)

# Same-vintage benchmark (2020-2024 ACS): Fauquier total pop ~75,900 (QuickFacts,
# current vintage). A same-vintage published total may be a stopifnot() gate.
pop <- dem |> filter(geoid == fauquier, table == "B01003") |> pull(estimate)
stopifnot(between(pop, 70000, 82000))

# 2022 baseline: LOG the % change, NEVER stopifnot() it — the 2016-2020 baseline
# and the 2020-2024 estimate differ by construction. Flag implausible swings for
# human review in the session log; don't fail the build.
baseline_path <- "data/baseline_2022.rds"
if (file.exists(baseline_path)) {
  pop_2022 <- read_rds(baseline_path) |>
    filter(geography == fauquier, metric == "total_pop") |>
    pull(value)
  if (length(pop_2022) == 1) {
    message(sprintf(
      "Fauquier pop vs 2022 baseline: %+.1f%% (log it; flag if implausible)",
      (pop - pop_2022) / pop_2022 * 100
    ))
  }
}

message("acs_demographics.R validation passed.")
message("  Fauquier pop: ", format(pop, big.mark = ","))
