# pep_migration.R ----
# What:   Annual population estimates and components of change -- births,
#         deaths, natural change, international and domestic migration -- for the
#         17 localities of the Richmond region (`rr`), the pooled core, ring, and
#         region, and Virginia. The demographics page reads this to show how much
#         of the region's growth is migration versus natural increase.
# Source: U.S. Census Bureau, Population Estimates Program (PEP), county
#         "alldata" files, from two vintages:
#           2010-2019  Vintage 2019  co-est2019-alldata.csv
#           2020-2025  Vintage 2025  co-est2025-alldata.csv
#         https://www2.census.gov/programs-surveys/popest/datasets/
#         Direct census.gov file fetches are pre-approved (CLAUDE.md data-fetch
#         rule); the FTP files are used instead of tidycensus::get_estimates()
#         because the API returns only a vintage's single latest year, so a
#         multi-year series from it would mix revised and unrevised vintages.
#         tidycensus is still used for a same-vintage benchmark (section 8).
# Format: One wide row per county, one column per measure-year
#         (POPESTIMATE2021, NETMIG2021, ...). The 2010-2019 file calls natural
#         change NATURALINC; the 2020-2025 file calls it NATURALCHG -- harmonised
#         to `natural_change` below.
# Notes:  * Components are for July 1 - June 30 periods labelled by the ending
#           year. The 2010 and 2020 components cover only April 1 - June 30 (the
#           bridge from the census base to the July 1 estimate), so they are
#           partial and set to NA; population is kept for every year.
#         * The two vintages do not join. Vintage 2020+ is built on the 2020
#           Census base, so the 2019 -> 2020 population step spans a methodology
#           break and is never computed. Era totals (2010-2019 and 2020-2025) are
#           each internal to one vintage.
#         * Rates are per 1,000 residents, over the average of the start- and
#           end-of-year population (the Census Bureau's own convention).
#         * Ashland (a sub-county place) is not here: PEP publishes place-level
#           population but no components of change. Comparison metros are left out
#           for the same reason METHODOLOGY.md keeps this page regional -- the
#           CBSA files carry different delineations across the two vintages.
# Output: data/pep_migration.rds  -- named list of 2 frames (annual, era)
#         data-out/pep_migration.csv      -- the annual frame
#         data-out/pep_migration_era.csv  -- the era-total frame

## 1. Setup ----
library(tidyverse)
library(tidycensus)
library(janitor)
source("_common.R") # rr, bhc, secondary, virginia, export_csv()

# .Renviron fallback -- R's HOME may not be ~/Documents (CLAUDE.md API-keys
# gotcha). Only the section 8 benchmark uses the key.
if (Sys.getenv("CENSUS_API_KEY") == "") {
  renviron_path <- file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}
message("CENSUS_API_KEY present: ", Sys.getenv("CENSUS_API_KEY") != "")

dir.create("data", showWarnings = FALSE, recursive = TRUE)
dir.create("data/cache/pep", showWarnings = FALSE, recursive = TRUE)

pep_files <- tribble(
  ~vintage, ~file,                    ~url,
  2019,     "co-est2019-alldata.csv", "https://www2.census.gov/programs-surveys/popest/datasets/2010-2019/counties/totals/co-est2019-alldata.csv",
  2025,     "co-est2025-alldata.csv", "https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties/totals/co-est2025-alldata.csv"
)

# Years whose components cover only April 1 - June 30 (the census-base bridge).
partial_years <- c(2010, 2020)

## 2. Fetch (cached) ----
# Cache each file under data/cache/pep/ so a re-run is cheap and idempotent.
# data/ is gitignored, so the cache never lands in the repo. Manual fallback per
# CLAUDE.md's data-fetch rule: if a download fails, save the file by hand into
# data/cache/pep/ under the name above and re-run -- the cached copy is read and
# the download skipped.
fetch_pep <- function(file, url) {
  dest <- file.path("data", "cache", "pep", file)
  if (!file.exists(dest)) {
    message("  downloading ", file, "...")
    try(download.file(url, dest, quiet = TRUE, mode = "wb"), silent = TRUE)
  }
  if (!file.exists(dest) || file.size(dest) < 100000) {
    stop("PEP file unavailable: ", file, " -- download it from ", url, " into ", dest)
  }
  dest
}

message("Fetching PEP county files...")
pep_files <- pep_files |> mutate(path = map2_chr(file, url, fetch_pep))

## 3. Read and reshape ----
# Wide measure-year columns -> one row per county-year, one column per measure.
# Virginia counties and independent cities only (SUMLEV 050, state FIPS 51).
read_pep <- function(path, yr_vintage) {
  raw <- read_csv(
    path,
    col_types = cols(.default = col_character()),
    locale = locale(encoding = "latin1"),
    progress = FALSE
  ) |>
    clean_names() |>
    filter(sumlev == "050", state == "51") |>
    mutate(
      geoid = paste0(str_pad(state, 2, "left", "0"), str_pad(county, 3, "left", "0")),
      name = paste(ctyname, stname, sep = ", ")
    ) |>
    # harmonise the 2010-2019 file's naming to the 2020-2025 file's
    rename_with(\(x) str_replace(x, "^naturalinc", "naturalchg"))

  raw |>
    select(
      geoid, name,
      matches("^(popestimate|births|deaths|naturalchg|internationalmig|domesticmig|netmig|residual)_?\\d{4}$")
    ) |>
    pivot_longer(
      -c(geoid, name),
      names_to = c("measure", "year"),
      names_pattern = "^([a-z]+)_?(\\d{4})$",
      values_to = "value"
    ) |>
    mutate(year = as.numeric(year), value = as.numeric(value)) |>
    pivot_wider(names_from = measure, values_from = value) |>
    mutate(vintage = yr_vintage)
}

raw <- pmap(pep_files, \(vintage, path, ...) read_pep(path, vintage)) |> list_rbind() |>
  rename(
    pop = popestimate,
    natural_change = naturalchg,
    international_mig = internationalmig,
    domestic_mig = domesticmig,
    net_mig = netmig
  ) |>
  # Partial-period components are not annual figures -- blank them, keep population.
  mutate(across(
    c(births, deaths, natural_change, international_mig, domestic_mig, net_mig, residual),
    \(x) if_else(year %in% partial_years, NA_real_, x)
  ))
message("Read ", nrow(raw), " county-year rows across ", n_distinct(raw$year), " years")

## 4. Pooled geographies ----
# Every PEP count is additive, so pooled rows are plain sums (no MOE -- these are
# estimates from administrative data, not a survey). Virginia is the sum of all
# 133 of its counties and independent cities.
count_cols <- c("pop", "births", "deaths", "natural_change", "international_mig", "domestic_mig", "net_mig", "residual")

pool_pep <- function(df, geos, out_geoid, out_name) {
  df |>
    filter(geoid %in% geos) |>
    summarise(
      across(all_of(count_cols), \(x) if (anyNA(x)) NA_real_ else sum(x)),
      .by = c(year, vintage)
    ) |>
    mutate(geoid = out_geoid, name = out_name)
}

pooled <- bind_rows(
  raw |> filter(geoid %in% rr),
  pool_pep(raw, unname(bhc), "bhc3", "Richmond core (3 localities)"),
  pool_pep(raw, unname(secondary), "secondary4", "Expansion ring (4 localities)"),
  pool_pep(raw, unname(rr), "rr17", "Richmond region (17 localities)"),
  pool_pep(raw, raw$geoid, virginia, "Virginia")
)

## 5. Annual frame: change, rates ----
# Population change and the rate denominator use the prior year's population
# *within the same vintage*, so the first year of each vintage (2010, 2020) gets
# NA rather than a change that straddles the methodology break.
annual <- pooled |>
  arrange(geoid, year) |>
  mutate(
    prev_pop = lag(pop),
    pop_change = pop - prev_pop,
    avg_pop = (pop + prev_pop) / 2,
    across(
      c(natural_change, international_mig, domestic_mig, net_mig),
      \(x) x / avg_pop * 1000,
      .names = "{.col}_rate"
    ),
    pct_change = pop_change / prev_pop,
    partial_components = year %in% partial_years,
    .by = c(geoid, vintage)
  ) |>
  select(-prev_pop) |>
  arrange(geoid, year)

## 6. Era frame ----
# Two eras, each inside one vintage: 2010-2019 (July 2010 -> July 2019, nine
# years of components) and 2020-2025 (July 2020 -> July 2025, five years).
era_levels <- c("2010-2019", "2020-2025")

era <- annual |>
  mutate(era = if_else(vintage == 2019, era_levels[1], era_levels[2])) |>
  summarise(
    pop_start = pop[year == min(year)],
    pop_end = pop[year == max(year)],
    n_years = sum(!partial_components),
    births = sum(births, na.rm = TRUE),
    deaths = sum(deaths, na.rm = TRUE),
    natural_change = sum(natural_change, na.rm = TRUE),
    international_mig = sum(international_mig, na.rm = TRUE),
    domestic_mig = sum(domestic_mig, na.rm = TRUE),
    net_mig = sum(net_mig, na.rm = TRUE),
    residual = sum(residual, na.rm = TRUE),
    avg_pop_sum = sum(avg_pop[!partial_components], na.rm = TRUE),
    .by = c(geoid, name, era)
  ) |>
  mutate(
    pop_change = pop_end - pop_start,
    pct_change = pop_change / pop_start,
    # Share of the era's growth that came from migration. Undefined when the
    # locality lost population (a negative share would read as nonsense).
    mig_share_of_growth = if_else(pop_change > 0, net_mig / pop_change, NA_real_),
    # Annual-average rates per 1,000 residents over the era.
    net_mig_rate = net_mig / avg_pop_sum * 1000,
    international_rate = international_mig / avg_pop_sum * 1000,
    domestic_rate = domestic_mig / avg_pop_sum * 1000,
    natural_rate = natural_change / avg_pop_sum * 1000,
    era = factor(era, levels = era_levels)
  ) |>
  select(-avg_pop_sum) |>
  arrange(geoid, era)

## 7. Write output ----
pep_migration <- list(annual = annual, era = era)
write_rds(pep_migration, "data/pep_migration.rds")
export_csv(annual, "pep_migration")
export_csv(era, "pep_migration_era")
message("Wrote data/pep_migration.rds + data-out/pep_migration.csv + data-out/pep_migration_era.csv")

## 8. Validate ----
# stopifnot() fires only on structure and same-vintage identities / benchmarks.
# Era-to-era comparison (2010s vs 2020s) is a logged contrast, never a gate --
# the two vintages differ by construction.
d <- read_rds("data/pep_migration.rds")

expected_geos <- c(unname(rr), "bhc3", "secondary4", "rr17", virginia)
all_years <- c(2010:2019, 2020:2025)
full_years <- setdiff(all_years, partial_years)

a <- d$annual
full <- a |> filter(!partial_components)
yr_rows <- a |> filter(!is.na(pop_change))

stopifnot(
  nrow(a) > 0,
  nrow(d$era) > 0,
  all(expected_geos %in% a$geoid),
  all(expected_geos %in% d$era$geoid),
  setequal(a$year, all_years),
  nrow(a) == nrow(distinct(a, geoid, year)),
  nrow(d$era) == length(expected_geos) * length(era_levels),
  !anyNA(a$pop),
  # annual components are present exactly for the full years, absent for partial
  !anyNA(full$net_mig),
  all(is.na(a$net_mig[a$partial_components])),
  # population is a positive level; births and deaths are non-negative counts
  all(a$pop > 0),
  all(full$births >= 0),
  all(full$deaths >= 0),
  # no change is computed across the 2019 -> 2020 vintage break
  all(is.na(a$pop_change[a$year %in% partial_years])),
  # same-vintage published identities (Census components add up exactly):
  #   population change = natural change + net migration + residual
  #   net migration     = international + domestic
  all(full$pop_change == full$natural_change + full$net_mig + full$residual),
  all(full$net_mig == full$international_mig + full$domestic_mig),
  all(full$natural_change == full$births - full$deaths),
  # the same identity must hold over each era in total
  all(d$era$pop_change == d$era$natural_change + d$era$net_mig + d$era$residual)
)

# Pooled-row consistency: rr17 must equal the sum of its 17 members, every year.
pool_check <- a |>
  filter(geoid %in% unname(rr)) |>
  summarise(parts = sum(pop), parts_net = sum(net_mig), .by = year) |>
  left_join(
    a |> filter(geoid == "rr17") |> select(year, whole = pop, whole_net = net_mig),
    by = join_by(year)
  )
stopifnot(
  all(pool_check$parts == pool_check$whole),
  isTRUE(all.equal(pool_check$parts_net, pool_check$whole_net))
)
message("  rr17 pooled row reconciles to its 17 members in all ", nrow(pool_check), " years.")

# Same-vintage published benchmark: the Census API's Vintage 2025 latest-year
# population and net migration must equal this file's 2025 values. Skipped (with
# a message) if the API is unreachable -- the identities above still gate.
latest_vintage <- max(pep_files$vintage)
latest_year <- max(all_years)
bench <- tryCatch(
  {
    pop_api <- get_estimates("county", product = "population", vintage = latest_vintage, state = "VA") |>
      clean_names() |>
      filter(variable == "POPESTIMATE", geoid %in% rr) |>
      select(geoid, api_pop = value)
    mig_api <- get_estimates("county", product = "components", vintage = latest_vintage, state = "VA") |>
      clean_names() |>
      filter(variable == "NETMIG", geoid %in% rr) |>
      select(geoid, api_net = value)
    full_join(pop_api, mig_api, by = join_by(geoid))
  },
  error = \(e) {
    message("  API benchmark skipped: ", conditionMessage(e))
    NULL
  }
)

if (!is.null(bench) && nrow(bench) == length(rr)) {
  cmp <- a |>
    filter(geoid %in% unname(rr), year == latest_year) |>
    select(geoid, pop, net_mig) |>
    left_join(bench, by = join_by(geoid))
  stopifnot(all(cmp$pop == cmp$api_pop), all(cmp$net_mig == cmp$api_net))
  message("  Vintage ", latest_vintage, " ", latest_year, " population and net migration match the Census API for all ", nrow(cmp), " localities.")
}

# Logged, not gated -------------------------------------------------------
message("\n-- Growth and where it came from, by era (logged, not gated) --")
d$era |>
  filter(geoid %in% c("rr17", "bhc3", "secondary4", unname(bhc), virginia)) |>
  arrange(geoid, era) |>
  pwalk(\(name, era, pop_start, pop_end, pct_change, natural_change, net_mig, international_mig, domestic_mig, mig_share_of_growth, net_mig_rate, ...) {
    message(
      "  ", str_pad(str_trunc(name, 30), 30, "right"), " ", era,
      "  pop ", format(pop_start, big.mark = ",", width = 9), " -> ", format(pop_end, big.mark = ",", width = 9),
      sprintf(" (%+.1f%%)", pct_change * 100),
      "  natural ", format(natural_change, big.mark = ",", width = 7),
      "  net mig ", format(net_mig, big.mark = ",", width = 7),
      " (intl ", format(international_mig, big.mark = ","), ", dom ", format(domestic_mig, big.mark = ","), ")",
      "  mig share ", if (is.na(mig_share_of_growth)) "n/a" else sprintf("%.0f%%", mig_share_of_growth * 100),
      "  rate ", sprintf("%+.1f", net_mig_rate), "/1,000/yr"
    )
  })

message("\n-- Region (rr17) annual net migration --")
a |>
  filter(geoid == "rr17", !partial_components) |>
  pwalk(\(year, natural_change, international_mig, domestic_mig, net_mig, ...) {
    message(
      "  ", year,
      "  natural ", format(natural_change, big.mark = ",", width = 7),
      "  intl ", format(international_mig, big.mark = ",", width = 7),
      "  dom ", format(domestic_mig, big.mark = ",", width = 7),
      "  net ", format(net_mig, big.mark = ",", width = 7)
    )
  })

# Localities that lost population over the 2020s era, for review.
losers <- d$era |> filter(geoid %in% unname(rr), era == "2020-2025", pop_change < 0)
message("\n  Localities with a population decline, 2020-2025: ", if (nrow(losers) == 0) "none" else paste(losers$name, collapse = "; "))

message("\npep_migration.R validation passed.")
