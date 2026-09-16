# bps_permits.R ----
# What:   Annual residential building permits by structure type for the 17
#         localities of the Richmond region (`rr`), 2000 through the latest
#         published year. The inventory page reads this as the production
#         (new-supply) counterpart to the ACS housing-stock frames.
# Source: U.S. Census Bureau, Building Permits Survey, county annual files at
#         https://www2.census.gov/econ/bps/County/co<YYYY>a.txt
#         Direct census.gov file fetches are pre-approved (CLAUDE.md
#         data-fetch rule). Confirmed 2026-09-16: the `a` suffix is the true
#         annual file; `co<YY><MM>y.txt` is year-to-date-through-month and
#         `...c.txt` is the monthly current file -- neither is what this wants.
# Format: Two header rows (a group row and a field row) plus a blank third
#         line, then CSV. Columns are Survey Date, state FIPS, county FIPS,
#         region, division, county name, then Bldgs/Units/Value triplets for
#         1-unit, 2-units, 3-4 units, and 5+ units, then the same four
#         triplets again as "rep" (reported-only) figures. This script reads
#         the first four triplets -- the imputed-inclusive published series --
#         and ignores the "rep" duplicates. Layout verified stable across the
#         2000 and 2025 files.
# Note:   BPS counts permits *issued*, not units completed, and only covers
#         jurisdictions with a permit system. It is a leading indicator of
#         supply, not a measure of it -- the inventory page carries that
#         caveat in a callout.
# Output: data/bps_permits.rds   -- named list of 2 frames (long, wide)
#         data-out/bps_permits.csv  -- the long frame

## 1. Setup ----
library(tidyverse)
library(janitor)
source("_common.R") # rr, bhc, secondary, export_csv()

# No API key needed -- these are plain files on a public census.gov server.

dir.create("data", showWarnings = FALSE, recursive = TRUE)
dir.create("data/cache/bps", showWarnings = FALSE, recursive = TRUE)

bps_years <- 2000:2025
bps_url <- function(yr) {
  paste0("https://www2.census.gov/econ/bps/County/co", yr, "a.txt")
}

## 2. Fetch (cached) ----
# Cache each year's file under data/cache/ so a re-run is cheap and idempotent
# and doesn't re-hit census.gov 26 times. data/ is gitignored, so the cache
# never lands in the repo. Manual fallback per CLAUDE.md's data-fetch rule: if
# a fetch fails, drop the file into data/cache/bps/co<YYYY>a.txt by hand and
# re-run -- the script will read the cached copy and skip the download.
fetch_bps <- function(yr) {
  dest <- file.path("data", "cache", "bps", paste0("co", yr, "a.txt"))
  if (!file.exists(dest)) {
    message("  downloading ", yr, "...")
    try(download.file(bps_url(yr), dest, quiet = TRUE, mode = "wb"), silent = TRUE)
  }
  if (!file.exists(dest) || file.size(dest) < 1000) {
    warning("BPS ", yr, " unavailable -- skipping (drop the file in ", dest, " to include it)")
    return(NULL)
  }
  dest
}

# The two header rows don't parse as a usable header (the group row is mostly
# blank), so skip all three preamble lines and name the columns explicitly.
bps_cols <- c(
  "survey_date", "state_fips", "county_fips", "region_code", "division_code",
  "county_name",
  "bldgs_1", "units_1", "value_1",
  "bldgs_2", "units_2", "value_2",
  "bldgs_3_4", "units_3_4", "value_3_4",
  "bldgs_5p", "units_5p", "value_5p",
  # "rep" (reported-only) duplicates -- read so the column count matches, then
  # dropped. The published series above already includes imputation for
  # non-responding jurisdictions, which is the series to trend.
  "rep_bldgs_1", "rep_units_1", "rep_value_1",
  "rep_bldgs_2", "rep_units_2", "rep_value_2",
  "rep_bldgs_3_4", "rep_units_3_4", "rep_value_3_4",
  "rep_bldgs_5p", "rep_units_5p", "rep_value_5p"
)

read_bps <- function(path, yr) {
  read_csv(
    path,
    skip = 3,
    col_names = bps_cols,
    col_types = cols(
      state_fips = col_character(),
      county_fips = col_character(),
      county_name = col_character(),
      .default = col_double()
    ),
    progress = FALSE
  ) |>
    mutate(
      year = yr,
      # FIPS arrive zero-padded in the file but parse defensively anyway, then
      # rebuild the 5-digit GEOID the rest of the project keys on.
      geoid = paste0(
        str_pad(state_fips, 2, "left", "0"),
        str_pad(county_fips, 3, "left", "0")
      ),
      county_name = str_squish(county_name)
    ) |>
    filter(geoid %in% rr)
}

message("Fetching BPS county annual files, ", min(bps_years), "-", max(bps_years), "...")
paths <- map(bps_years, fetch_bps)
names(paths) <- bps_years
paths <- compact(paths)

raw <- imap(paths, \(p, yr) read_bps(p, as.integer(yr))) |> list_rbind()
message("Read ", nrow(raw), " locality-year rows across ", n_distinct(raw$year), " years")

## 3. Reshape to long by structure type ----
# The four published size classes collapse to the two the page reads --
# single-family and multifamily -- but both grains are kept: `structure` holds
# the published class, `structure_group` the collapsed one, so a chart can use
# either without re-deriving it.
structure_labels <- c(
  "1" = "Single-family",
  "2" = "2 units",
  "3_4" = "3-4 units",
  "5p" = "5+ units"
)

structure_levels <- unname(structure_labels)

group_labels <- c(
  "Single-family" = "Single-family",
  "2 units" = "Multifamily",
  "3-4 units" = "Multifamily",
  "5+ units" = "Multifamily"
)

bps_long <- raw |>
  select(geoid, county_name, year, starts_with("bldgs_"), starts_with("units_"), starts_with("value_")) |>
  pivot_longer(
    cols = -c(geoid, county_name, year),
    names_to = c("metric", "size_class"),
    names_pattern = "^(bldgs|units|value)_(.+)$",
    values_to = "n"
  ) |>
  pivot_wider(names_from = metric, values_from = n) |>
  mutate(
    structure = factor(unname(structure_labels[size_class]), levels = structure_levels),
    structure_group = factor(
      unname(group_labels[as.character(structure)]),
      levels = c("Single-family", "Multifamily")
    )
  ) |>
  select(geoid, name = county_name, year, structure, structure_group, bldgs, units, value) |>
  arrange(year, geoid, structure)

## 4. Pooled geographies ----
# Permit counts are administrative totals, not survey estimates -- they simply
# add, with no MOE to carry. Same two pooled rows the ACS frames use, so a page
# can plot stock and production on the same geography set.
pool_bps <- function(df, geos, out_geoid, out_name) {
  df |>
    filter(geoid %in% geos) |>
    summarise(
      bldgs = sum(bldgs),
      units = sum(units),
      value = sum(value),
      .by = c(year, structure, structure_group)
    ) |>
    mutate(geoid = out_geoid, name = out_name)
}

bps_permits <- bind_rows(
  bps_long,
  pool_bps(bps_long, unname(bhc), "bhc3", "Richmond core (3 localities)"),
  pool_bps(bps_long, unname(secondary), "secondary4", "Expansion ring (4 localities)"),
  pool_bps(bps_long, unname(rr), "rr17", "Richmond region (17 localities)")
) |>
  arrange(year, geoid, structure)

## 5. Annual totals by geography ----
# The grain most of the page's charts read: one row per geography-year, with
# the single-family / multifamily split already computed as a share.
bps_annual <- bps_permits |>
  summarise(
    units = sum(units),
    bldgs = sum(bldgs),
    value = sum(value),
    .by = c(geoid, name, year, structure_group)
  ) |>
  pivot_wider(
    id_cols = c(geoid, name, year),
    names_from = structure_group,
    values_from = units,
    values_fill = 0
  ) |>
  clean_names() |>
  mutate(
    total_units = single_family + multifamily,
    mf_share = if_else(total_units > 0, multifamily / total_units, NA_real_)
  ) |>
  arrange(year, geoid)

## 6. Write output ----
write_rds(
  list(permits = bps_permits, annual = bps_annual),
  "data/bps_permits.rds"
)
export_csv(bps_permits, "bps_permits")
message("Wrote data/bps_permits.rds + data-out/bps_permits.csv")

## 7. Validate ----
# stopifnot() only on structure. BPS is an administrative count, not a survey,
# so there is no MOE/CV here and no same-vintage published benchmark beyond
# the file's own internal consistency.
d <- read_rds("data/bps_permits.rds")

expected_geos <- c(unname(rr), "bhc3", "secondary4", "rr17")
yrs <- sort(unique(d$permits$year))

stopifnot(
  nrow(d$permits) > 0,
  nrow(d$annual) > 0,
  all(expected_geos %in% d$permits$geoid),
  all(expected_geos %in% d$annual$geoid),
  # every locality-year has all four published size classes
  setequal(levels(d$permits$structure), structure_levels),
  !anyNA(d$permits$units),
  !anyNA(d$annual$total_units),
  # permits are counts: never negative
  all(d$permits$units >= 0),
  all(d$permits$bldgs >= 0),
  # one row per geography-year in the annual frame
  nrow(d$annual) == nrow(distinct(d$annual, geoid, year)),
  # the region row must equal the sum of its 17 members, every year
  nrow(d$annual) == length(expected_geos) * length(yrs)
)

# Pooled-row consistency: rr17 must equal the sum of the 17 localities.
pool_check <- d$annual |>
  filter(geoid %in% unname(rr)) |>
  summarise(parts = sum(total_units), .by = year) |>
  left_join(
    d$annual |> filter(geoid == "rr17") |> select(year, whole = total_units),
    by = join_by(year)
  )
stopifnot(all(pool_check$parts == pool_check$whole))
message("  rr17 pooled row reconciles to its 17 members in all ", nrow(pool_check), " years.")

# Logged, not gated -- year-to-year swings in permit volume are real and often
# large (a single 300-unit apartment building moves a small locality's total).
message("\n-- Permitted units by year, Richmond region (rr17) --")
d$annual |>
  filter(geoid == "rr17") |>
  select(year, single_family, multifamily, total_units, mf_share) |>
  pwalk(\(year, single_family, multifamily, total_units, mf_share) {
    message(
      "  ", year,
      "  SF ", format(single_family, big.mark = ",", width = 7),
      "  MF ", format(multifamily, big.mark = ",", width = 7),
      "  total ", format(total_units, big.mark = ",", width = 7),
      "  MF share ", sprintf("%5.1f%%", mf_share * 100)
    )
  })

peak <- d$annual |> filter(geoid == "rr17") |> slice_max(total_units, n = 1)
trough <- d$annual |> filter(geoid == "rr17") |> slice_min(total_units, n = 1)
message(
  "\n  Peak: ", peak$year, " (", format(peak$total_units, big.mark = ","), " units)",
  " | Trough: ", trough$year, " (", format(trough$total_units, big.mark = ","), " units)"
)

message("\nbps_permits.R validation passed.")
