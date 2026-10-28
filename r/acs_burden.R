# acs_burden.R ----
# What:   ACS 5-year housing cost burden by tenure -- gross rent as a share of
#         household income (renters) and selected monthly owner costs as a
#         share of household income (owners, collapsed across mortgage
#         status) -- trended across three non-overlapping 5-year windows,
#         with the percentage bands collapsed into burden categories.
# Source: tidycensus ACS 5-year, survey years 2014/2019/2024.
# Tables: B25070 (gross rent as a percentage of household income, renters),
#         B25091 (mortgage status by selected monthly owner costs as a
#         percentage of household income, owners).
# Geos:   the 17 rr localities, Virginia, the 4 comparison metros, plus three
#         pooled rows -- "bhc3" (3 core localities), "secondary4" (4 expansion
#         localities), and "rr17" (the whole region). No Ashland place pull:
#         burden shares for a sub-county place would ride on cells too small to
#         survive the CV-30 suppression rule anyway. (An earlier tract tier was
#         sibling-project debris and was dropped 2026-10-28.)
# Output: data/acs_burden.rds  (+ data-out/acs_burden.csv)

## 1. Setup ----
library(tidyverse)
library(tidycensus)
library(janitor)
source("_common.R")

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


## 2. Pull + label helpers ----

# Pull one ACS table across three geography tiers: the 17 rr counties, the
# Virginia state row, and the 4 comparison metro regions, tagging the pull year
# and each row's geo_level.
pull_acs <- function(table, yr) {
  county <- get_acs(
    geography = "county",
    state = "VA",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% rr) |>
    mutate(geo_level = "county")

  state <- get_acs(
    geography = "state",
    state = "VA",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% virginia) |>
    mutate(geo_level = "state")

  region <- get_acs(
    geography = "cbsa",
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% regions) |>
    mutate(geo_level = "region")

  bind_rows(county, state, region) |>
    mutate(year = yr, table = table)
}

# Build a variable -> label lookup from load_variables(), stripping the leading
# "Estimate" segment and rejoining the remaining "!!"-delimited parts.
build_labels <- function(table, yr) {
  vars <- load_variables(year = yr, dataset = "acs5", cache = TRUE) |>
    clean_names()

  tvars <- vars |> filter(str_starts(name, paste0(table, "_")))
  n_parts <- max(str_count(tvars$label, "!!")) + 1

  tvars |>
    separate_wider_delim(
      label,
      delim = "!!",
      names = paste0("part", seq_len(n_parts)),
      too_few = "align_start"
    ) |>
    select(-part1) |> # drop the "Estimate" segment
    unite("label", starts_with("part"), sep = "!!", na.rm = TRUE) |>
    transmute(variable = name, label)
}

# Collapse a labeled table pull into burden categories. The band is the final
# "!!" label segment; rows without a percentage band (the table total and the
# B25091 mortgage-status subtotals) are dropped before collapsing, so B25091's
# with-/without-mortgage bands stack into a single owner series. The band's
# lower bound (its first number) sorts every vintage's band set correctly:
# both tables split cleanly at 30 and 50 percent.
collapse_bands <- function(df, tenure) {
  df |>
    mutate(band = str_extract(label, "[^!]+$")) |>
    filter(str_detect(band, "percent|Not computed")) |>
    mutate(
      # "Not computed" has no number to parse; suppress that expected warning.
      lower = suppressWarnings(parse_number(band)),
      burden = case_when(
        str_detect(band, "Not computed") ~ "Not computed",
        lower >= 50 ~ "Severely cost-burdened",
        lower >= 30 ~ "Cost-burdened",
        .default = "Not cost-burdened"
      )
    ) |>
    # Counts add and MOEs of a sum combine in quadrature (same as acs_stock.R).
    # moe is computed alongside estimate in one summarise(), so it must not be
    # fed the already-summed estimate (moe_sum(moe, estimate) would see a scalar).
    summarise(
      estimate = sum(estimate),
      moe = sqrt(sum(moe^2)),
      .by = c(geoid, name, geo_level, year, burden)
    ) |>
    mutate(tenure = tenure, .after = year)
}

# Pooled geographies: sum the collapsed burden counts of member localities.
pool_burden <- function(df, geos, out_geoid, out_name) {
  df |>
    filter(geo_level == "county", geoid %in% geos) |>
    summarise(
      estimate = sum(estimate),
      moe = sqrt(sum(moe^2)),
      .by = c(year, tenure, burden)
    ) |>
    mutate(geoid = out_geoid, name = out_name, geo_level = "pooled")
}

## 3. Pull B25070 (renters) and B25091 (owners), 2014/2019/2024 ----
# Three non-overlapping 5-year windows, matching r/acs_stock.R and
# r/acs_tenure.R: overlapping 5-year ACS samples are not independent.
years <- c(2014, 2019, 2024)

message("Pulling B25070 (renters)...")
b25070_raw <- map(years, \(yr) {
  pull_acs("B25070", yr) |>
    left_join(build_labels("B25070", yr), by = "variable")
}) |>
  list_rbind()
message("B25070 pulled: ", nrow(b25070_raw), " rows")

message("Pulling B25091 (owners)...")
b25091_raw <- map(years, \(yr) {
  pull_acs("B25091", yr) |>
    left_join(build_labels("B25091", yr), by = "variable")
}) |>
  list_rbind()
message("B25091 pulled: ", nrow(b25091_raw), " rows")

## 4. Collapse bands into burden categories ----
renter <- collapse_bands(b25070_raw, "Renter")
owner <- collapse_bands(b25091_raw, "Owner")

# Append the pooled rows to each tenure frame. Pooling happens on the collapsed
# counts, so shares are recomputed from the pooled counts in section 5.
add_pooled_burden <- function(df) {
  bind_rows(
    df,
    pool_burden(df, unname(bhc), "bhc3", "Richmond core (3 localities)"),
    pool_burden(df, unname(secondary), "secondary4", "Expansion ring (4 localities)"),
    pool_burden(df, unname(rr), "rr17", "Richmond region (17 localities)")
  )
}
renter <- add_pooled_burden(renter)
owner <- add_pooled_burden(owner)

# Table totals ("_001" rows), kept aside as the validation benchmark. Pooled
# rows have no published total, so the benchmark check skips them.
totals <- bind_rows(
  b25070_raw |> filter(str_ends(variable, "_001")) |> mutate(tenure = "Renter"),
  b25091_raw |> filter(str_ends(variable, "_001")) |> mutate(tenure = "Owner")
) |>
  select(geoid, year, tenure, total = estimate)

## 5. Shares, CV, reliability ----
# Share is of *computed* households -- the three burden categories sum to the
# denominator; "Not computed" is excluded and carries an NA share. A small
# locality can have zero computed households for a tenure, so computed_total
# can be legitimately 0 -- guard that case to an explicit NA rather than a 0/0
# NaN.
acs_burden <- bind_rows(renter, owner) |>
  mutate(
    computed_total = sum(estimate[burden != "Not computed"]),
    share = if_else(
      burden == "Not computed" | computed_total == 0,
      NA_real_,
      estimate / computed_total
    ),
    .by = c(geoid, year, tenure)
  ) |>
  mutate(
    # Same CV guard as r/acs_stock.R: a zero/absent MOE on a positive estimate
    # is a controlled total (CV 0 -> High); only a zero/absent estimate leaves
    # the CV undefined.
    cv = case_when(
      is.na(estimate) | estimate <= 0 ~ NA_real_,
      is.na(moe) | moe == 0 ~ 0,
      .default = (moe / 1.645) / estimate * 100
    )
  ) |>
  flag_reliability() |>
  mutate(
    burden = factor(
      burden,
      levels = c(
        "Not cost-burdened",
        "Cost-burdened",
        "Severely cost-burdened",
        "Not computed"
      )
    )
  ) |>
  arrange(year, tenure, geoid, burden) |>
  select(
    geoid,
    name,
    geo_level,
    year,
    tenure,
    burden,
    estimate,
    moe,
    share,
    cv,
    reliability
  )

## 6. Write output ----
write_rds(acs_burden, "data/acs_burden.rds")
export_csv(acs_burden, "acs_burden")
message(
  "Wrote data/acs_burden.rds + data-out/acs_burden.csv (",
  nrow(acs_burden),
  " rows)"
)

## 7. Validate ----
# stopifnot() fires only on structure and on same-vintage identities (category
# sums vs. the published table totals). Vintage-to-vintage change is logged,
# never gated (CLAUDE.md).
d <- read_rds("data/acs_burden.rds")

pooled_ids <- c("bhc3", "secondary4", "rr17")
named_ids <- c(unname(rr), virginia, unname(regions))

# Published-total identity: the burden categories must sum to the pulled
# table's own _001 total for every non-pooled geography-year-tenure.
check <- d |>
  filter(geo_level != "pooled") |>
  summarise(n_cat = n(), cat_sum = sum(estimate), .by = c(geoid, year, tenure)) |>
  left_join(totals, by = join_by(geoid, year, tenure))

# Reproduce computed_total from d itself (it isn't carried in the output
# schema) to check the share/NA invariant: a share is NA exactly for the
# "Not computed" band or a zero-computed-total geography-year-tenure.
computed_total <- d |>
  mutate(
    computed_total = sum(estimate[burden != "Not computed"]),
    .by = c(geoid, year, tenure)
  ) |>
  pull(computed_total)

stopifnot(
  setequal(d$geo_level, c("county", "state", "region", "pooled")),
  setequal(d$geoid, c(named_ids, pooled_ids)),
  setequal(d$year, years),
  setequal(d$tenure, c("Renter", "Owner")),
  # 25 geographies (22 named + 3 pooled) x years x 2 tenures x 4 categories
  nrow(d) == (length(named_ids) + length(pooled_ids)) * length(years) * 2 * 4,
  all(check$n_cat == 4),
  !anyNA(check$total),
  all(check$cat_sum == check$total),
  all(d$share >= 0 & d$share <= 1, na.rm = TRUE),
  all(is.na(d$share) == (d$burden == "Not computed" | computed_total == 0)),
  !all(is.na(d$estimate))
)

# Pooled-row consistency: rr17 must equal the sum of its 17 localities in every
# year-tenure-category cell.
pool_check <- d |>
  filter(geoid %in% unname(rr)) |>
  summarise(parts = sum(estimate), .by = c(year, tenure, burden)) |>
  left_join(
    d |> filter(geoid == "rr17") |> select(year, tenure, burden, whole = estimate),
    by = join_by(year, tenure, burden)
  )
stopifnot(all(pool_check$parts == pool_check$whole))
message("  rr17 pooled row reconciles to its 17 members in all ", nrow(pool_check), " cells.")

# Logged, not gated: share of computed households paying 30%+ of income, by
# tenure, for the region and the core, across the three windows.
message("\n-- Share of households cost-burdened (30%+ of income), logged --")
d |>
  filter(geoid %in% c("rr17", "bhc3", "secondary4"), burden %in% c("Cost-burdened", "Severely cost-burdened")) |>
  summarise(share = sum(share), .by = c(geoid, name, year, tenure)) |>
  arrange(tenure, geoid, year) |>
  pwalk(\(geoid, name, year, tenure, share) {
    message(
      "  ", str_pad(tenure, 6, "right"), " ", year, "  ",
      str_pad(str_trunc(name, 30), 30, "right"), " ", scales::percent(share, accuracy = 0.1)
    )
  })

reg_chg <- d |>
  filter(geoid == "rr17", burden %in% c("Cost-burdened", "Severely cost-burdened")) |>
  summarise(share = sum(share), .by = c(year, tenure)) |>
  pivot_wider(names_from = year, values_from = share, names_prefix = "y") |>
  mutate(pts_change = (y2024 - y2014) * 100)
message("\n  Region 30%+ burden, 2014 -> 2024 (percentage points):")
reg_chg |>
  pwalk(\(tenure, pts_change, ...) message("    ", tenure, ": ", sprintf("%+.1f", pts_change), " pts"))

# Reliability: low-CV cells in the smallest localities, logged.
low_cells <- d |>
  filter(geoid %in% unname(secondary), year == 2024) |>
  summarise(low = sum(reliability == "Low", na.rm = TRUE), n = n())
message("\n  Low-reliability cells in the 4 expansion localities (2024): ", low_cells$low, " of ", low_cells$n)

message("\nacs_burden.R validation passed.")
