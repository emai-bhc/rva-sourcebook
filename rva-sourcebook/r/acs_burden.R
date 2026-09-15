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

# Pull one ACS table across four geography tiers: the 17 rr counties, the
# Virginia state row, 4 comparison metro regions, and Census tracts within
# the BHC service area, tagging the pull year and each row's geo_level. No
# Ashland place pull, because burden shares for a sub-county place would ride
# on cells too small to survive the CV-30 suppression rule anyway.
pull_acs <- function(table, yr) {
  tracts <- get_acs(
    geography = "tract",
    state = "VA",
    county = str_sub(unname(bhc), 3, 5),
    table = table,
    year = yr,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    clean_names() |>
    mutate(geo_level = "tract")

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

  bind_rows(tracts, county, state, region) |>
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
    summarise(
      estimate = sum(estimate),
      moe = moe_sum(moe, estimate),
      .by = c(geoid, name, geo_level, year, burden)
    ) |>
    mutate(tenure = tenure, .after = year)
}

## 3. Pull B25070 (renters) and B25091 (owners), 2014/2019/2024 ----
# Three non-overlapping 5-year windows, matching r/acs_income.R: overlapping
# 5-year ACS samples are not independent.
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

# Table totals ("_001" rows), kept aside as the validation benchmark.
totals <- bind_rows(
  b25070_raw |> filter(str_ends(variable, "_001")) |> mutate(tenure = "Renter"),
  b25091_raw |> filter(str_ends(variable, "_001")) |> mutate(tenure = "Owner")
) |>
  select(geoid, year, tenure, total = estimate)

## 5. Shares, CV, reliability ----
# Share is of *computed* households -- the three burden categories sum to the
# denominator; "Not computed" is excluded and carries an NA share. At tract
# level some BHC-core tracts have zero owner- or zero renter-occupied units
# (an all-apartment tract has no owner rows, an all-single-family tract has
# no renter rows), so computed_total can be legitimately 0 -- guard that case
# to an explicit NA rather than a 0/0 NaN.
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
    # Same CV guard as r/acs_income.R: a zero/absent MOE on a positive estimate
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
d <- read_rds("data/acs_burden.rds")

# Structure: 4 categories per geoid x year x tenure, shares in [0,1], and
# category sums matching the pulled table totals (same vintage, same pull --
# a structural identity, not a cross-source benchmark). Checked per
# geography tier below because the within-BHC tract geoid set is not stable
# across years -- 2014/2019 ACS5 sit on 2010-vintage tract boundaries and
# 2024 ACS5 sits on 2020-vintage boundaries, so only the named tiers
# (county/state/region) have a fixed, known geoid set to assert against.
check <- d |>
  summarise(
    n_cat = n(),
    cat_sum = sum(estimate),
    .by = c(geoid, year, tenure)
  ) |>
  left_join(totals, by = c("geoid", "year", "tenure"))

named <- d |> filter(geo_level != "tract")
tract_rows <- d |> filter(geo_level == "tract")

# Reproduce computed_total from d itself (not carried in the output schema)
# to check the share/NA invariant, which is legitimately NA either for the
# "Not computed" band or for a zero-computed-total geoid/year/tenure group.
computed_total <- d |>
  mutate(
    computed_total = sum(estimate[burden != "Not computed"]),
    .by = c(geoid, year, tenure)
  ) |>
  pull(computed_total)

stopifnot(
  setequal(d$geo_level, c("tract", "county", "state", "region")),
  # Named tiers: 17 rr counties + 1 state + 4 regions = 22 geographies x
  # 3 years x 2 tenures x 4 categories.
  nrow(named) == 22 * length(years) * 2 * 4,
  setequal(named$geoid[named$geo_level == "county"], unname(rr)),
  setequal(named$geoid[named$geo_level == "state"], virginia),
  setequal(named$geoid[named$geo_level == "region"], unname(regions)),
  # Tract tier: present every year, every tract within the 3 BHC counties.
  setequal(tract_rows$year, years),
  all(str_sub(tract_rows$geoid, 1, 5) %in% unname(bhc)),
  setequal(d$year, years),
  setequal(d$tenure, c("Renter", "Owner")),
  all(check$n_cat == 4),
  all(check$cat_sum == check$total),
  all(d$share >= 0 & d$share <= 1, na.rm = TRUE),
  all(is.na(d$share) == (d$burden == "Not computed" | computed_total == 0))
)

# Regional 30%+ burden shares, 2024 window -- chapter sanity numbers, logged.
reg <- d |>
  filter(geoid %in% rr, year == 2024, burden != "Not computed") |>
  summarise(estimate = sum(estimate), .by = c(tenure, burden)) |>
  mutate(share = estimate / sum(estimate), .by = tenure)

reg_30 <- reg |>
  filter(burden != "Not cost-burdened") |>
  summarise(share = sum(share), .by = tenure)

message(
  "Regional 30%+ burden share, 2020-2024 ACS: renter ",
  scales::percent(reg_30$share[reg_30$tenure == "Renter"], accuracy = 0.1),
  " | owner ",
  scales::percent(reg_30$share[reg_30$tenure == "Owner"], accuracy = 0.1)
)

# 2022 baseline: baseline_2022 comparison logged if available, never gated
# (2016-2020 and 2020-2024 ACS differ by construction).
baseline_path <- "data/baseline_2022.rds"
if (file.exists(baseline_path)) {
  b22 <- read_rds(baseline_path)
  key_col <- intersect(c("metric", "measure", "label"), names(b22))[1]
  if (!is.na(key_col)) {
    burden_rows <- b22 |>
      filter(str_detect(.data[[key_col]], regex("burden", ignore_case = TRUE)))
    message(
      "baseline_2022 burden-keyed rows found: ",
      nrow(burden_rows),
      " -- compare against the regional shares above in the session log."
    )
  } else {
    message(
      "baseline_2022 loaded but no metric-like key column found; ",
      "compare shares manually in the session log."
    )
  }
} else {
  message("data/baseline_2022.rds not found -- skipping 2022 baseline note.")
}

message("acs_burden.R validation passed.")
