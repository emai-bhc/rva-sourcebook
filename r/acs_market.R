# acs_market.R ----
# What:   Housing-market basics for the Richmond region -- tenure (owner vs.
#         renter households), median home value, and median gross rent. The
#         market page reads this alongside r/acs_burden.R (cost burden) and
#         r/acs_demographics.R (median household income, for affordability
#         ratios computed in the page).
# Source: tidycensus ACS 5-year, three non-overlapping windows ending 2014,
#         2019, and 2024 (overlapping 5-year samples are not independent --
#         same trend convention as the other acs_*.R scripts).
# Tables: B25003 tenure (total occupied, owner-occupied, renter-occupied)
#         B25077 median value of owner-occupied units
#         B25064 median gross rent
#         B25003 is the all-households counterpart to r/acs_tenure.R's
#         race-specific B25003A-I tables, which do not carry a total.
#         B25077 and B25064 are medians: they cannot be pooled, so they carry no
#         bhc3/secondary4/rr17 rows (same rule as B25035 and B19013).
# Geos:   the 17 rr localities, the Town of Ashland (place, sumlev 160), the 4
#         comparison metros, Virginia, plus three pooled rows for the count
#         table -- "bhc3", "secondary4", "rr17". Ashland is inside Hanover and
#         never part of a pool.
# Dollars: ACS medians are published in the window's end-year dollars. Each
#         median carries `estimate` (as published, nominal) and `estimate_real`
#         (latest window's dollars), deflated by national CPI-U annual averages
#         read from data/bls_wage.rds. If that file lacks the CPI, the real
#         columns are NA with a warning -- no deflator is hardcoded.
# Output: data/acs_market.rds   -- named list of 3 frames (tenure, median_value,
#         median_rent)
#         data-out/acs_market.csv  -- the long, all-frames tidy export

## 1. Setup ----
library(tidyverse)
library(tidycensus)
library(janitor)
source("_common.R") # rr, bhc, secondary, ashland, regions, virginia, export_csv(), flag_reliability()

# .Renviron fallback -- R's HOME may not be ~/Documents (CLAUDE.md API-keys
# gotcha). Load it only if unset.
if (Sys.getenv("CENSUS_API_KEY") == "") {
  renviron_path <- file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}
message("CENSUS_API_KEY present: ", Sys.getenv("CENSUS_API_KEY") != "")

dir.create("data", showWarnings = FALSE, recursive = TRUE)

years <- c(2014, 2019, 2024)

## 2. Pull helper ----
pull_market <- function(table, yr) {
  county <- get_acs(
    geography = "county", state = "VA", table = table, year = yr,
    survey = "acs5", cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% rr)

  place <- get_acs(
    geography = "place", state = "VA", table = table, year = yr,
    survey = "acs5", cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% ashland)

  state <- get_acs(
    geography = "state", state = "VA", table = table, year = yr,
    survey = "acs5", cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% virginia)

  region <- get_acs(
    geography = "cbsa", table = table, year = yr,
    survey = "acs5", cache_table = TRUE
  ) |>
    clean_names() |>
    filter(geoid %in% regions)

  bind_rows(county, place, state, region) |>
    mutate(year = yr, table = table)
}

pull_table <- function(table) {
  message("Pulling ", table, " (", paste(years, collapse = ", "), ")...")
  out <- map(years, \(yr) pull_market(table, yr)) |> list_rbind()
  message("  ", table, ": ", nrow(out), " rows")
  out
}

## 3. Pull the tables ----
b25003_raw <- pull_table("B25003") # tenure
b25077_raw <- pull_table("B25077") # median home value
b25064_raw <- pull_table("B25064") # median gross rent

# Resolve B25003's tenure labels from load_variables() rather than assuming
# the _002/_003 numbering (CLAUDE.md tidycensus convention).
tenure_map <- map(years, \(yr) {
  load_variables(year = yr, dataset = "acs5", cache = TRUE) |>
    clean_names() |>
    filter(str_starts(name, "B25003_")) |>
    mutate(
      leaf = label |> str_remove("^Estimate!!") |> str_split("!!") |> map_chr(last) |> str_remove(":$"),
      year = yr
    ) |>
    select(variable = name, leaf, year)
}) |>
  list_rbind()

## 4. Shared helpers ----
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

## 5. Tenure ----
# Owner and renter counts, with the ownership rate carried on every row of the
# geography-year. Total is kept so a page can read the denominator off one frame.
tenure <- b25003_raw |>
  left_join(tenure_map, by = join_by(variable, year)) |>
  mutate(tenure = recode_values(
    leaf,
    "Total" ~ "Total",
    "Owner occupied" ~ "Owner",
    "Renter occupied" ~ "Renter",
    default = NA_character_
  ))
stopifnot(!anyNA(tenure$tenure))

tenure <- tenure |>
  select(geoid, name, year, table, variable, tenure, estimate, moe)

tenure <- bind_rows(
  tenure,
  pool_geos(tenure, unname(bhc), "bhc3", "Richmond core (3 localities)", c("year", "table", "tenure")),
  pool_geos(tenure, unname(secondary), "secondary4", "Expansion ring (4 localities)", c("year", "table", "tenure")),
  pool_geos(tenure, unname(rr), "rr17", "Richmond region (17 localities)", c("year", "table", "tenure"))
) |>
  add_cv() |>
  flag_reliability() |>
  mutate(
    total_households = estimate[tenure == "Total"],
    ownership_rate = estimate[tenure == "Owner"] / estimate[tenure == "Total"],
    .by = c(geoid, year)
  ) |>
  mutate(tenure = factor(tenure, levels = c("Owner", "Renter", "Total"))) |>
  arrange(year, geoid, tenure)

## 6. Medians (value and rent), nominal and real ----
cpi_path <- "data/bls_wage.rds"
cpi_by_year <- if (file.exists(cpi_path)) {
  read_rds(cpi_path)$annual |>
    filter(measure == "cpi", year %in% years) |>
    select(year, cpi = value)
} else {
  tibble(year = numeric(), cpi = numeric())
}
have_cpi <- setequal(cpi_by_year$year, years)
if (!have_cpi) {
  warning(
    "CPI for ", paste(years, collapse = "/"), " not found in ", cpi_path,
    " -- real-dollar columns will be NA. Run r/bls_wage.R first."
  )
}
cpi_latest <- if (have_cpi) cpi_by_year$cpi[cpi_by_year$year == max(years)] else NA_real_

shape_median <- function(raw) {
  raw |>
    select(geoid, name, year, table, variable, estimate, moe) |>
    add_cv() |>
    flag_reliability() |>
    left_join(cpi_by_year, by = join_by(year)) |>
    mutate(
      real_factor = cpi_latest / cpi,
      estimate_real = estimate * real_factor,
      moe_real = moe * real_factor,
      dollar_year = max(years)
    ) |>
    select(-cpi, -real_factor) |>
    arrange(year, geoid)
}

median_value <- shape_median(b25077_raw)
median_rent <- shape_median(b25064_raw)

## 7. Write output ----
market <- list(tenure = tenure, median_value = median_value, median_rent = median_rent)
write_rds(market, "data/acs_market.rds")

market_long <- list(
  tenure = tenure |> mutate(measure = "tenure", category = as.character(tenure)),
  median_value = median_value |> mutate(measure = "median_value", category = NA_character_),
  median_rent = median_rent |> mutate(measure = "median_rent", category = NA_character_)
) |>
  map(\(d) select(d, geoid, name, year, table, measure, category, estimate, moe, cv, reliability)) |>
  list_rbind()

export_csv(market_long, "acs_market")
message("Wrote data/acs_market.rds + data-out/acs_market.csv")

## 8. Validate ----
# stopifnot() fires only on structure and same-vintage identities. Vintage-to-
# vintage change is logged, never gated (CLAUDE.md).
d <- read_rds("data/acs_market.rds")

pooled_ids <- c("bhc3", "secondary4", "rr17")
named_ids <- c(unname(rr), unname(ashland), unname(regions), virginia)

stopifnot(
  all(map_lgl(d, \(x) nrow(x) > 0)),
  all(map_lgl(d, \(x) all(years %in% x$year))),
  all(map_lgl(d, \(x) !all(is.na(x$estimate)))),
  all(c(named_ids, pooled_ids) %in% d$tenure$geoid),
  setequal(d$median_value$geoid, named_ids),
  setequal(d$median_rent$geoid, named_ids),
  nrow(d$median_value) == nrow(distinct(d$median_value, geoid, year)),
  nrow(d$median_rent) == nrow(distinct(d$median_rent, geoid, year)),
  setequal(levels(d$tenure$tenure), c("Owner", "Renter", "Total")),
  # Owner + Renter = the table's own Total, every geography-year (pooled too:
  # counts add, so the identity survives pooling)
  d$tenure |>
    summarise(
      ok = sum(estimate[tenure %in% c("Owner", "Renter")]) == estimate[tenure == "Total"],
      .by = c(geoid, year)
    ) |>
    pull(ok) |>
    all(),
  # a rate is a share
  all(d$tenure$ownership_rate >= 0 & d$tenure$ownership_rate <= 1, na.rm = TRUE),
  # medians are positive dollar amounts where published
  all(d$median_value$estimate > 0, na.rm = TRUE),
  all(d$median_rent$estimate > 0, na.rm = TRUE)
)

# rr17 must equal the sum of its 17 members, every year-tenure cell.
pool_check <- d$tenure |>
  filter(geoid %in% unname(rr)) |>
  summarise(parts = sum(estimate), .by = c(year, tenure)) |>
  left_join(
    d$tenure |> filter(geoid == "rr17") |> select(year, tenure, whole = estimate),
    by = join_by(year, tenure)
  )
stopifnot(all(pool_check$parts == pool_check$whole))
message("  rr17 tenure reconciles to its 17 members in all ", nrow(pool_check), " cells.")

# Same-vintage cross-script identity: occupied housing units (B25003_001) equal
# households (B19001_001) in the same window. Runs only if acs_demographics.R
# has been run.
if (file.exists("data/acs_demographics.rds")) {
  hh <- read_rds("data/acs_demographics.rds")$income_bands |>
    filter(!geoid %in% pooled_ids) |>
    summarise(households = sum(estimate), .by = c(geoid, year))
  cmp <- d$tenure |>
    filter(tenure == "Total", !geoid %in% pooled_ids) |>
    select(geoid, year, occupied = estimate) |>
    left_join(hh, by = join_by(geoid, year))
  stopifnot(all(cmp$occupied == cmp$households))
  message("  B25003 occupied units equal B19001 households in all ", nrow(cmp), " geography-years.")
} else {
  message("  data/acs_demographics.rds not found -- skipping the households identity check.")
}

# Logged, not gated -------------------------------------------------------
message("\n-- Ownership rate, 2014 -> 2024 (logged, not gated) --")
d$tenure |>
  filter(tenure == "Owner", geoid %in% c("rr17", "bhc3", "secondary4", unname(bhc), unname(ashland))) |>
  select(name, year, ownership_rate) |>
  pivot_wider(names_from = year, values_from = ownership_rate, names_prefix = "y") |>
  pwalk(\(name, y2014, y2019, y2024) {
    message(
      "  ", str_pad(str_trunc(name, 34), 34, "right"),
      sprintf("%5.1f%% -> %5.1f%%  (%+.1f pts)", y2014 * 100, y2024 * 100, (y2024 - y2014) * 100)
    )
  })

log_median <- function(frame, label) {
  message("\n-- ", label, ", ", if (have_cpi) "nominal | real, " else "nominal, ", "2014 -> 2024 --")
  frame |>
    filter(geoid %in% c(unname(regions), unname(bhc), virginia)) |>
    select(name, year, estimate, estimate_real) |>
    pivot_wider(names_from = year, values_from = c(estimate, estimate_real)) |>
    pwalk(\(name, estimate_2014, estimate_2024, estimate_real_2014, estimate_real_2024, ...) {
      message(
        "  ", str_pad(str_trunc(name, 30), 30, "right"),
        " $", format(estimate_2014, big.mark = ","), " -> $", format(estimate_2024, big.mark = ","),
        "  nominal ", sprintf("%+.1f%%", (estimate_2024 / estimate_2014 - 1) * 100),
        if (have_cpi) sprintf("  real %+.1f%%", (estimate_real_2024 / estimate_real_2014 - 1) * 100) else ""
      )
    })
}
log_median(d$median_value, "Median home value")
log_median(d$median_rent, "Median gross rent")

low_cells <- d$median_value |>
  filter(geoid %in% c(unname(secondary), unname(ashland)), year == 2024) |>
  summarise(low = sum(reliability == "Low", na.rm = TRUE), n = n())
message(
  "\n  Low-reliability median-value cells in secondary+Ashland (2024): ",
  low_cells$low, " of ", low_cells$n
)

message("\nacs_market.R validation passed.")
