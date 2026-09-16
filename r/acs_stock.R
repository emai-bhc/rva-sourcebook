# acs_stock.R ----
# What:   Housing stock for the Richmond region -- total units, occupancy and
#         vacancy status, structure type, and year structure built. The
#         inventory page reads this.
# Source: tidycensus ACS 5-year, three non-overlapping windows ending 2014,
#         2019, and 2024 (overlapping 5-year samples are not independent --
#         same trend convention as r/acs_tenure.R).
# Tables: B25001 total housing units
#         B25002 occupancy status (occupied / vacant)
#         B25004 vacancy status (the reason a vacant unit is vacant)
#         B25024 units in structure (1-unit detached through boat/RV/van)
#         B25034 year structure built
#         B25035 (median year built) and B25036 (year built by tenure) were in
#         the TODO line. B25035 is a median, not a count -- it cannot be summed
#         into the pooled region row every other frame here carries, and its
#         locality-level story is already told by the B25034 distribution, so
#         it is pulled but kept in its own frame with no pooled row. B25036 is
#         not published in the 2014 window, which would break the three-window
#         trend, so it is out of scope for v1 -- noted in METHODOLOGY.md.
# Geos:   the 17 rr localities, the Town of Ashland (place, sumlev 160), the 4
#         comparison metros, Virginia, plus two pooled rows -- "bhc3" (the 3
#         core localities) and "secondary4" (the 4 expansion localities).
# Output: data/acs_stock.rds   -- named list of 5 frames (see section 8)
#         data-out/acs_stock.csv  -- the long, all-frames tidy export

## 1. Setup ----
library(tidyverse)
library(tidycensus)
library(janitor)
source("_common.R") # rr, bhc, secondary, ashland, regions, virginia, export_csv()

# .Renviron fallback -- R's HOME may not be ~/Documents, so the key file isn't
# always auto-loaded (CLAUDE.md API-keys gotcha). Load it only if unset.
if (Sys.getenv("CENSUS_API_KEY") == "") {
  renviron_path <- file.path(
    Sys.getenv("USERPROFILE"),
    "Documents",
    ".Renviron"
  )
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}
message("CENSUS_API_KEY present: ", Sys.getenv("CENSUS_API_KEY") != "")

dir.create("data", showWarnings = FALSE, recursive = TRUE)

years <- c(2014, 2019, 2024)

## 2. Pull helper ----
# One table across all five geography grains, for one year. Ashland is a place
# (sumlev 160) inside Hanover, so it needs its own `geography = "place"` call
# rather than a filter on the county pull. A zero or absent MOE on a positive
# estimate means a controlled estimate with no sampling error (CV 0 -> High);
# only an absent or non-positive estimate leaves the CV genuinely undefined.
pull_stock <- function(table, yr) {
  county <- get_acs(
    geography = "county",
    state = "VA",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% rr)

  place <- get_acs(
    geography = "place",
    state = "VA",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% ashland)

  state <- get_acs(
    geography = "state",
    state = "VA",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% virginia)

  region <- get_acs(
    geography = "cbsa",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% regions)

  bind_rows(county, place, state, region) |>
    mutate(year = yr, table = table)
}

pull_table <- function(table) {
  message("Pulling ", table, " (", paste(years, collapse = ", "), ")...")
  out <- map(years, \(yr) pull_stock(table, yr)) |> list_rbind()
  message("  ", table, ": ", nrow(out), " rows")
  out
}

## 3. Resolve variable labels from load_variables() ----
# Never assume a table's variable numbering -- read the published label and
# take the leaf after the last "!!" (CLAUDE.md tidycensus convention). The
# label text is stable across these three windows for the tables used here,
# so one lookup per year keyed on (variable, year) covers the trend.
label_lookup <- function(yr, pattern) {
  load_variables(year = yr, dataset = "acs5", cache = TRUE) |>
    clean_names() |>
    filter(str_detect(name, pattern)) |>
    mutate(
      leaf = label |>
        str_remove("^Estimate!!") |>
        str_split("!!") |>
        map_chr(last) |>
        str_remove(":$"),
      depth = str_count(str_remove(label, "^Estimate!!"), "!!"),
      year = yr
    ) |>
    select(variable = name, leaf, depth, year)
}

var_pattern <- "^B2500[124]_|^B2502[4]_|^B2503[45]_"
message("Resolving variable labels from load_variables()...")
var_map <- map(years, \(yr) label_lookup(yr, var_pattern)) |> list_rbind()
message("Resolved ", nrow(var_map), " variable-label pairs")

# Shared CV formula -- one definition, used by every frame below.
add_cv <- function(df) {
  df |>
    mutate(
      cv = case_when(
        is.na(estimate) | estimate <= 0 ~ NA_real_,
        is.na(moe) | moe == 0 ~ 0,
        .default = (moe / 1.645) / estimate * 100
      )
    )
}

# Join labels on equal-named keys only (CLAUDE.md join_by gotcha), then confirm
# nothing lost its label.
label_join <- function(df) {
  out <- df |> left_join(var_map, by = join_by(variable, year))
  stopifnot(!anyNA(out$leaf))
  out
}

## 4. Pull the tables ----
b25001_raw <- pull_table("B25001") # total units
b25002_raw <- pull_table("B25002") # occupancy status
b25004_raw <- pull_table("B25004") # vacancy status
b25024_raw <- pull_table("B25024") # units in structure
b25034_raw <- pull_table("B25034") # year structure built
b25035_raw <- pull_table("B25035") # median year built (own frame, no pooling)

## 5. Pooled-geography helper ----
# Counts add; MOEs of a sum combine in quadrature. Both operations run here
# rather than in the page, so the standard-error math lives in one place
# (CLAUDE.md data-flow rule). Ashland is inside Hanover, so it is never part
# of a pooled row -- pooling it with the counties would double-count.
pool_geos <- function(df, geos, out_geoid, out_name, group_cols) {
  df |>
    filter(geoid %in% geos) |>
    summarise(
      estimate = sum(estimate),
      moe = sqrt(sum(moe^2)),
      .by = all_of(group_cols)
    ) |>
    mutate(geoid = out_geoid, name = out_name)
}

# Every frame below gets the same two pooled rows appended.
add_pooled <- function(df, group_cols) {
  bind_rows(
    df,
    pool_geos(df, unname(bhc), "bhc3", "Richmond core (3 localities)", group_cols),
    pool_geos(
      df,
      unname(secondary),
      "secondary4",
      "Expansion ring (4 localities)",
      group_cols
    )
  ) |>
    add_cv() |>
    flag_reliability()
}

## 6. Shape each frame ----

# B25001 -- one row per geography-year. Single-variable table, no leaf needed.
stock_units <- b25001_raw |>
  select(geoid, name, year, table, variable, estimate, moe) |>
  add_pooled(c("year", "table", "variable")) |>
  arrange(year, geoid)

# B25002 -- occupancy status. Keep the Total row alongside Occupied/Vacant so a
# page can read a vacancy rate off one frame, and carry that rate on every row
# of the geography-year group.
occupancy <- b25002_raw |>
  label_join() |>
  filter(depth <= 1) |>
  mutate(status = leaf) |>
  select(geoid, name, year, table, variable, status, estimate, moe) |>
  add_pooled(c("year", "table", "variable", "status")) |>
  mutate(
    total_units = estimate[status == "Total"],
    vacancy_rate = estimate[status == "Vacant"] / estimate[status == "Total"],
    .by = c(geoid, year)
  ) |>
  arrange(year, geoid, status)

# B25004 -- why a vacant unit is vacant. The Total row here is vacant units,
# not all units, so the share denominator is that table's own total.
vacancy_reason <- b25004_raw |>
  label_join() |>
  mutate(reason = leaf) |>
  select(geoid, name, year, table, variable, reason, estimate, moe) |>
  add_pooled(c("year", "table", "variable", "reason")) |>
  mutate(
    vacant_units = estimate[reason == "Total"],
    share = estimate / estimate[reason == "Total"],
    .by = c(geoid, year)
  ) |>
  arrange(year, geoid, reason)

# B25024 -- units in structure. Collapse the published categories into the five
# the page uses. "2 to 4" and "5 to 19" etc. are separate published rows; the
# report groups them into single-family, small multifamily, large multifamily,
# and manufactured/other, which is the grain a housing-stock chart reads at.
structure_groups <- c(
  "1, detached" = "Single-family detached",
  "1, attached" = "Single-family attached",
  "2" = "2-4 units",
  "3 or 4" = "2-4 units",
  "5 to 9" = "5-19 units",
  "10 to 19" = "5-19 units",
  "20 to 49" = "20+ units",
  "50 or more" = "20+ units",
  "Mobile home" = "Manufactured / other",
  "Boat, RV, van, etc." = "Manufactured / other"
)

structure_levels <- c(
  "Single-family detached",
  "Single-family attached",
  "2-4 units",
  "5-19 units",
  "20+ units",
  "Manufactured / other"
)

structure_type <- b25024_raw |>
  label_join() |>
  filter(leaf != "Total") |>
  mutate(structure = unname(structure_groups[leaf])) |>
  filter(!is.na(structure)) |>
  # Collapse the published rows into the report groups before pooling, so the
  # quadrature MOE runs once over the final categories.
  summarise(
    estimate = sum(estimate),
    moe = sqrt(sum(moe^2)),
    .by = c(geoid, name, year, table, structure)
  ) |>
  mutate(variable = NA_character_) |>
  add_pooled(c("year", "table", "structure", "variable")) |>
  mutate(
    total_units = sum(estimate),
    share = estimate / sum(estimate),
    .by = c(geoid, year)
  ) |>
  mutate(structure = factor(structure, levels = structure_levels)) |>
  arrange(year, geoid, structure)

# B25034 -- year structure built. Published bins differ across the three
# windows (2024 adds "Built 2020 to 2023"), so the raw leaf is kept and the
# page reads the era grouping below, which is stable across all three.
era_from_leaf <- function(leaf) {
  # Leaves look like "Built 1939 or earlier", "Built 1940 to 1949", ...
  start <- str_extract(leaf, "\\d{4}") |> as.integer()
  case_when(
    is.na(start) ~ NA_character_,
    start < 1950 ~ "Pre-1950",
    start < 1970 ~ "1950-1969",
    start < 1990 ~ "1970-1989",
    start < 2010 ~ "1990-2009",
    .default = "2010 or later"
  )
}

era_levels <- c("Pre-1950", "1950-1969", "1970-1989", "1990-2009", "2010 or later")

year_built <- b25034_raw |>
  label_join() |>
  filter(leaf != "Total") |>
  mutate(era = era_from_leaf(leaf)) |>
  filter(!is.na(era)) |>
  summarise(
    estimate = sum(estimate),
    moe = sqrt(sum(moe^2)),
    .by = c(geoid, name, year, table, era)
  ) |>
  mutate(variable = NA_character_) |>
  add_pooled(c("year", "table", "era", "variable")) |>
  mutate(
    total_units = sum(estimate),
    share = estimate / sum(estimate),
    .by = c(geoid, year)
  ) |>
  mutate(era = factor(era, levels = era_levels)) |>
  arrange(year, geoid, era)

# B25035 -- median year built. A median cannot be summed, so this frame gets no
# pooled rows; it is per-geography only.
median_year_built <- b25035_raw |>
  select(geoid, name, year, table, variable, estimate, moe) |>
  add_cv() |>
  flag_reliability() |>
  arrange(year, geoid)

## 7. Write output ----
stock <- list(
  units = stock_units,
  occupancy = occupancy,
  vacancy_reason = vacancy_reason,
  structure_type = structure_type,
  year_built = year_built,
  median_year_built = median_year_built
)

write_rds(stock, "data/acs_stock.rds")

# One long CSV covering every frame -- `measure` names which frame a row came
# from, `category` carries that frame's own dimension (status / reason /
# structure / era), NA where the frame has none.
stock_long <- list(
  units = stock_units |> mutate(measure = "units", category = NA_character_),
  occupancy = occupancy |> mutate(measure = "occupancy", category = status),
  vacancy_reason = vacancy_reason |>
    mutate(measure = "vacancy_reason", category = reason),
  structure_type = structure_type |>
    mutate(measure = "structure_type", category = as.character(structure)),
  year_built = year_built |> mutate(measure = "year_built", category = as.character(era)),
  median_year_built = median_year_built |>
    mutate(measure = "median_year_built", category = NA_character_)
) |>
  map(\(d) select(d, geoid, name, year, table, measure, category, estimate, moe, cv, reliability)) |>
  list_rbind()

export_csv(stock_long, "acs_stock")
message("Wrote data/acs_stock.rds + data-out/acs_stock.csv")

## 8. Validate ----
# stopifnot() fires only on structure: expected geographies present, no
# all-NA estimate column, internal totals consistent. Vintage-to-vintage
# comparison is a logged percentage change, never a gate (CLAUDE.md).
d <- read_rds("data/acs_stock.rds")

expected_geos <- c(unname(rr), unname(ashland), unname(regions), virginia, "bhc3", "secondary4")

stopifnot(
  # every frame non-empty and covering all three windows
  all(map_lgl(d, \(x) nrow(x) > 0)),
  all(map_lgl(d, \(x) all(years %in% x$year))),
  # every expected geography present in the frames that carry pooled rows
  all(expected_geos %in% d$units$geoid),
  all(expected_geos %in% d$occupancy$geoid),
  all(expected_geos %in% d$structure_type$geoid),
  all(expected_geos %in% d$year_built$geoid),
  # one row per geography-year in the single-value frame
  nrow(d$units) == nrow(distinct(d$units, geoid, year)),
  # no all-NA estimate columns
  all(map_lgl(d, \(x) !all(is.na(x$estimate)))),
  !anyNA(d$units$estimate),
  # every structure/era category present, none dropped by the recode
  setequal(levels(d$structure_type$structure), structure_levels),
  setequal(levels(d$year_built$era), era_levels)
)

# Internal consistency: B25002's Occupied + Vacant must equal its own Total,
# and B25024/B25034 must each sum to roughly B25001's total for the same
# geography-year. Same vintage, same survey -- a real structural check, so it
# gates. Tolerance is 0.5% for the B25024/B25034 comparison: those are
# separately-tabulated universes and can differ by a handful of units.
occ_check <- d$occupancy |>
  summarise(
    parts = sum(estimate[status %in% c("Occupied", "Vacant")]),
    total = first(estimate[status == "Total"]),
    .by = c(geoid, year)
  )
stopifnot(all(occ_check$parts == occ_check$total))

units_total <- d$units |> select(geoid, year, b25001 = estimate)

for (nm in c("structure_type", "year_built")) {
  cmp <- d[[nm]] |>
    summarise(total = first(total_units), .by = c(geoid, year)) |>
    left_join(units_total, by = join_by(geoid, year)) |>
    mutate(pct_diff = abs(total - b25001) / b25001 * 100)
  message(
    "  ",
    nm,
    " vs B25001 -- max abs diff: ",
    round(max(cmp$pct_diff, na.rm = TRUE), 3),
    "%"
  )
  stopifnot(max(cmp$pct_diff, na.rm = TRUE) < 0.5)
}

# Vintage-to-vintage change -- LOGGED, never gated. Different 5-year windows
# differ by construction; an implausible swing is a flag for review.
message("\n-- Total housing units, 2014 -> 2024 (logged, not gated) --")
d$units |>
  filter(geoid %in% c(unname(bhc), "bhc3", "secondary4", unname(ashland))) |>
  select(geoid, name, year, estimate) |>
  pivot_wider(names_from = year, values_from = estimate, names_prefix = "y") |>
  mutate(pct_change = (y2024 - y2014) / y2014 * 100) |>
  arrange(desc(estimate = y2024)) |>
  pwalk(\(geoid, name, y2014, y2019, y2024, pct_change) {
    message(
      "  ",
      str_pad(str_trunc(name, 34), 34, "right"),
      " ",
      format(y2014, big.mark = ",", width = 9),
      " -> ",
      format(y2024, big.mark = ",", width = 9),
      "  ",
      sprintf("%+.1f%%", pct_change)
    )
  })

message("\n-- Vacancy rate by geography, 2024 (logged) --")
d$occupancy |>
  filter(year == 2024, status == "Vacant", geoid %in% c(unname(bhc), "bhc3", "secondary4")) |>
  pwalk(\(name, vacancy_rate, ...) {
    message("  ", str_pad(str_trunc(name, 34), 34, "right"), " ", sprintf("%.1f%%", vacancy_rate * 100))
  })

# Reliability: how many cells land Low (CV > 30) in the small geographies the
# METHODOLOGY notes run noisier. Logged, not gated.
low_cells <- d$structure_type |>
  filter(geoid %in% c(unname(secondary), unname(ashland)), year == 2024) |>
  summarise(low = sum(reliability == "Low", na.rm = TRUE), n = n())
message(
  "\n  Low-reliability structure_type cells in secondary+Ashland (2024): ",
  low_cells$low,
  " of ",
  low_cells$n
)

message("\nacs_stock.R validation passed.")
