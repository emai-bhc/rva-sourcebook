# bls_wage.R ----
# What:   Unemployment and wage-growth trends for the Richmond MSA, with the
#         comparison metros in `regions` (Charlottesville, Hampton Roads,
#         Washington) and Virginia statewide for unemployment context. The
#         market page reads this for the "can local wages keep up with housing
#         costs" frame.
# Source: U.S. Bureau of Labor Statistics Public Data API v2 via `blscrapeR`
#         (a package wrapper, so covered by the CLAUDE.md data-fetch rule).
#           - LAUS  (Local Area Unemployment Statistics): unemployment rate and
#                   labor force, monthly, not seasonally adjusted -- MSA-level
#                   LAUS is only published NSA, so Virginia is pulled NSA too
#                   for a like-for-like comparison.
#           - CES   (Current Employment Statistics, state & metro): average
#                   hourly earnings of all employees, total private, monthly.
#           - CPI-U (U.S. city average, all items, NSA): deflator for real wages.
# Series: LAUS  LAUMT<state><cbsa>000000<03|06>   (MSA)
#               LAUST<state>00000000000<03|06>    (state)
#         CES   SMU<state><cbsa>05000000 03
#         CPI   CUUR0000SA0
#         IDs are built from `regions` in section 2, not typed by hand. A
#         comparison metro whose CES wage series BLS doesn't publish is dropped
#         with a warning; Richmond itself is required (see validation).
# Note:   CES metro average hourly earnings is a sample-based, revisable
#         series -- the latest months are preliminary and benchmarked annually.
#         Annual values here are the mean of 12 monthly values; partial years
#         are dropped from the annual and wage frames. Real wages deflate by
#         national CPI-U (no Richmond-area CPI exists), so real growth is
#         "relative to national prices", not a local cost-of-living measure.
# Output: data/bls_wage.rds  -- named list of 3 frames (monthly, annual, wages)
#         data-out/bls_wage.csv          -- the annual frame (long by measure)
#         data-out/bls_wage_monthly.csv  -- the monthly frame

## 1. Setup ----
library(tidyverse)
library(janitor)
library(blscrapeR)
source("_common.R") # regions, virginia, export_csv()

# .Renviron fallback (R's HOME may not be ~/Documents -- CLAUDE.md API-keys
# gotcha). blscrapeR reads the key from BLS_KEY, which is what
# blscrapeR::set_bls_key() writes. Existence check only; never print the value.
if (Sys.getenv("BLS_KEY") == "") {
  renviron_path <- file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")
  if (file.exists(renviron_path)) readRenviron(renviron_path)
}
if (Sys.getenv("BLS_KEY") == "") {
  stop("BLS_KEY is not set. Add BLS_KEY=<your key> to .Renviron (or run blscrapeR::set_bls_key()).")
}

dir.create("data", showWarnings = FALSE, recursive = TRUE)

start_year <- 2006L
end_year <- as.integer(format(Sys.Date(), "%Y"))

## 2. Build the series catalog ----
# State FIPS differs for the Washington MSA (BLS keys it to DC, 11); the
# Virginia-side MSAs all use 51.
msa_names <- c(
  cville = "Charlottesville MSA",
  rva = "Richmond MSA",
  hrds = "Hampton Roads MSA",
  dc = "Washington MSA"
)
msa_state <- c(cville = "51", rva = "51", hrds = "51", dc = "11")

stopifnot(setequal(names(regions), names(msa_names)))

msa_series <- tibble(key = names(regions), cbsa = unname(regions)) |>
  mutate(
    geoid = cbsa,
    name = unname(msa_names[key]),
    state = unname(msa_state[key])
  ) |>
  reframe(
    series_id = c(
      paste0("LAUMT", state, cbsa, "000000", "03"),
      paste0("LAUMT", state, cbsa, "000000", "06"),
      paste0("SMU", state, cbsa, "05000000", "03")
    ),
    measure = c("unemp_rate", "labor_force", "avg_hourly_earnings"),
    .by = c(geoid, name)
  )

state_series <- tibble(
  geoid = virginia,
  name = "Virginia",
  series_id = c(
    paste0("LAUST", virginia, strrep("0", 11), "03"),
    paste0("LAUST", virginia, strrep("0", 11), "06")
  ),
  measure = c("unemp_rate", "labor_force")
)

cpi_series <- tibble(
  geoid = "US",
  name = "U.S. city average",
  series_id = "CUUR0000SA0",
  measure = "cpi"
)

series_catalog <- bind_rows(msa_series, state_series, cpi_series)
message("Series catalog: ", nrow(series_catalog), " series")

## 3. Pull from the BLS API ----
# API v2 caps a request at 20 years and 50 series. 14 series fit one call;
# the year range is chunked.
pull_bls <- function(ids, from, to) {
  chunks <- split(from:to, ceiling(seq_along(from:to) / 20))
  imap(chunks, \(yrs, i) {
    message("  years ", min(yrs), "-", max(yrs), "...")
    tryCatch(
      bls_api(
        seriesid = ids,
        startyear = min(yrs),
        endyear = max(yrs),
        registrationKey = Sys.getenv("BLS_KEY")
      ),
      error = \(e) {
        warning("BLS request failed for ", min(yrs), "-", max(yrs), ": ", conditionMessage(e))
        NULL
      }
    )
  }) |>
    compact() |>
    map(\(d) d |> clean_names() |> select(series_id, year, period, value)) |>
    list_rbind()
}

message("Pulling BLS series, ", start_year, "-", end_year, "...")
raw <- pull_bls(series_catalog$series_id, start_year, end_year)
message("Pulled ", nrow(raw), " series-period rows across ", n_distinct(raw$series_id), " series")

missing_series <- series_catalog |> filter(!series_id %in% raw$series_id)
if (nrow(missing_series) > 0) {
  warning(
    "No data returned for: ",
    paste0(missing_series$name, " / ", missing_series$measure, collapse = "; ")
  )
}

## 4. Monthly frame ----
# M01-M12 only; M13 is the BLS-computed annual average, which the annual frame
# rebuilds itself so the n_months completeness rule applies uniformly.
monthly <- raw |>
  filter(str_detect(period, "^M(0[1-9]|1[0-2])$")) |>
  mutate(
    year = as.integer(year),
    month = as.integer(str_sub(period, 2, 3)),
    date = make_date(year, month, 1),
    value = as.numeric(value)
  ) |>
  inner_join(series_catalog, by = join_by(series_id)) |>
  filter(!is.na(value)) |>
  select(geoid, name, measure, series_id, date, year, month, value) |>
  arrange(measure, geoid, date)
message("Monthly frame: ", nrow(monthly), " rows")

## 5. Annual frame ----
# Complete years only. A partial current year would otherwise read as a
# spurious wage drop or unemployment swing.
annual <- monthly |>
  summarise(value = mean(value), n_months = n(), .by = c(geoid, name, measure, year)) |>
  filter(n_months == 12) |>
  arrange(measure, geoid, year)
message("Annual frame: ", nrow(annual), " rows (complete years only)")

## 6. Wage growth ----
# Real wages deflate to the latest year in which Richmond wages and CPI are
# both complete. The cumulative index starts at the first year every wage
# geography has data, so the lines share a base and are comparable.
cpi_annual <- annual |>
  filter(measure == "cpi") |>
  select(year, cpi = value)

ahe <- annual |>
  filter(measure == "avg_hourly_earnings") |>
  select(geoid, name, year, ahe = value)

base_year <- ahe |>
  filter(geoid == regions[["rva"]]) |>
  semi_join(cpi_annual, by = join_by(year)) |>
  pull(year) |>
  max()

index_start <- ahe |>
  summarise(first_year = min(year), .by = geoid) |>
  pull(first_year) |>
  max()

cpi_base <- cpi_annual |> filter(year == base_year) |> pull(cpi)

wages <- ahe |>
  inner_join(cpi_annual, by = join_by(year)) |>
  filter(year >= index_start, year <= base_year) |>
  arrange(geoid, year) |>
  mutate(
    ahe_real = ahe * cpi_base / cpi, # dollars of base_year purchasing power
    yoy_nominal = ahe / lag(ahe) - 1,
    yoy_real = ahe_real / lag(ahe_real) - 1,
    idx_nominal = ahe / first(ahe) * 100,
    idx_real = ahe_real / first(ahe_real) * 100,
    .by = c(geoid, name)
  ) |>
  mutate(base_year = base_year, index_start = index_start)
message("Wage frame: ", nrow(wages), " rows | index ", index_start, " = 100, dollars in ", base_year)

## 7. Write output ----
write_rds(
  list(monthly = monthly, annual = annual, wages = wages),
  "data/bls_wage.rds"
)
export_csv(annual, "bls_wage")
export_csv(monthly, "bls_wage_monthly")
message("Wrote data/bls_wage.rds + data-out/bls_wage.csv + data-out/bls_wage_monthly.csv")

## 8. Validate ----
# stopifnot() only on structure. BLS publishes no same-vintage benchmark to
# check these against, and the series are revisable, so nothing here gates on
# a level or a swing -- those are logged below.
d <- read_rds("data/bls_wage.rds")
rva_id <- regions[["rva"]]

has_rva <- function(m) any(d$annual$geoid == rva_id & d$annual$measure == m)

stopifnot(
  nrow(d$monthly) > 0,
  nrow(d$annual) > 0,
  nrow(d$wages) > 0,
  # Richmond must have every measure; comparison metros may legitimately lack CES
  has_rva("unemp_rate"),
  has_rva("labor_force"),
  has_rva("avg_hourly_earnings"),
  "US" %in% d$annual$geoid, # CPI deflator present
  virginia %in% d$annual$geoid,
  !anyNA(d$monthly$value),
  !anyNA(d$wages$ahe_real),
  # unemployment is a percentage, earnings and labor force are positive levels
  all(d$monthly$value[d$monthly$measure == "unemp_rate"] >= 0 &
    d$monthly$value[d$monthly$measure == "unemp_rate"] < 100),
  all(d$monthly$value[d$monthly$measure != "unemp_rate"] > 0),
  # one row per series-month and per geography-measure-year
  nrow(d$monthly) == nrow(distinct(d$monthly, series_id, date)),
  nrow(d$annual) == nrow(distinct(d$annual, geoid, measure, year)),
  all(d$annual$n_months == 12),
  nrow(d$wages) == nrow(distinct(d$wages, geoid, year)),
  # the index base year equals 100 for every wage geography
  all(d$wages$idx_nominal[d$wages$year == index_start] == 100)
)

# Logged, not gated.
message("\n-- Unemployment rate, annual average (%) --")
d$annual |>
  filter(measure == "unemp_rate") |>
  select(name, year, value) |>
  pivot_wider(names_from = name, values_from = value) |>
  arrange(year) |>
  mutate(across(where(is.numeric) & !year, \(x) round(x, 1))) |>
  print(n = Inf)

rva_ur <- d$annual |> filter(measure == "unemp_rate", geoid == rva_id)
ur_peak <- rva_ur |> slice_max(value, n = 1, with_ties = FALSE)
ur_low <- rva_ur |> slice_min(value, n = 1, with_ties = FALSE)
message(
  "\n  Richmond MSA unemployment: peak ", round(ur_peak$value, 1), "% (", ur_peak$year,
  ") | low ", round(ur_low$value, 1), "% (", ur_low$year, ")"
)

latest_m <- d$monthly |>
  filter(measure == "unemp_rate", geoid == rva_id) |>
  slice_max(date, n = 1)
message("  Latest monthly Richmond MSA rate: ", latest_m$value, "% (", format(latest_m$date, "%Y-%m"), ", preliminary)")

message("\n-- Average hourly earnings growth, ", index_start, "-", base_year, " --")
d$wages |>
  summarise(
    start = first(ahe),
    end = last(ahe),
    nominal_growth = last(idx_nominal) / 100 - 1,
    real_growth = last(idx_real) / 100 - 1,
    .by = c(geoid, name)
  ) |>
  pwalk(\(geoid, name, start, end, nominal_growth, real_growth) {
    message(
      "  ", format(name, width = 20),
      "  $", sprintf("%.2f", start), " -> $", sprintf("%.2f", end),
      "  nominal ", sprintf("%+6.1f%%", nominal_growth * 100),
      "  real (", base_year, " $) ", sprintf("%+6.1f%%", real_growth * 100)
    )
  })

message("\nbls_wage.R validation passed.")
