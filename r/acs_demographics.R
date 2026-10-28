# acs_demographics.R ----
# What:   Population and household characteristics for the Richmond region --
#         total population, age and sex, race and ethnicity, household
#         composition, household income, and tenure by income. The
#         demographics page reads this.
# Source: tidycensus ACS 5-year, three non-overlapping windows ending 2014,
#         2019, and 2024 (overlapping 5-year samples are not independent --
#         same trend convention as r/acs_tenure.R and r/acs_stock.R).
# Tables: B01001 sex by age (also supplies total population)
#         B03002 Hispanic or Latino origin by race
#         B11001 household type (families, living alone)
#         B19001 household income, 16 bands
#         B19013 median household income (a median: no pooled rows)
#         B25118 tenure by household income, 11 bands per tenure
# Groups: age -> Under 18 / 18-34 / 35-54 / 55-64 / 65+. Race -> the six groups
#         r/acs_tenure.R uses (White non-Hispanic, Black, Hispanic or Latino,
#         Asian, Multiracial, Another race), here all non-Hispanic except
#         Hispanic or Latino, so the six sum to the B03002 total. Income -> six
#         bands on fixed NOMINAL thresholds (<$25k ... $150k+); bands are not
#         inflation-adjusted, so a share-in-top-band trend partly reflects
#         inflation. B19013 carries both the published nominal value and a
#         real-dollar value (see section 7).
# Geos:   the 17 rr localities, the Town of Ashland (place, sumlev 160), the 4
#         comparison metros, Virginia, plus three pooled rows -- "bhc3" (3
#         core localities), "secondary4" (4 expansion localities), "rr17" (the
#         whole region). Ashland is inside Hanover and never part of a pool.
# Output: data/acs_demographics.rds   -- named list of 7 frames (see section 8)
#         data-out/acs_demographics.csv  -- the long, all-frames tidy export

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
# One table across all five geography grains, for one year. Ashland is a place
# (sumlev 160) inside Hanover, so it needs its own `geography = "place"` call.
pull_demo <- function(table, yr) {
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
  out <- map(years, \(yr) pull_demo(table, yr)) |> list_rbind()
  message("  ", table, ": ", nrow(out), " rows")
  out
}

## 3. Resolve variable labels from load_variables() ----
# Never assume a table's variable numbering -- read the published label.
# `path` is the label with "Estimate!!" and the trailing colons removed
# (e.g. "Total!!Male!!Under 5 years"), `leaf` its last segment, `depth` the
# number of "!!" in the path (Total = 0).
label_lookup <- function(yr, pattern) {
  load_variables(year = yr, dataset = "acs5", cache = TRUE) |>
    clean_names() |>
    filter(str_detect(name, pattern)) |>
    mutate(
      path = label |>
        str_remove("^Estimate!!") |>
        str_replace_all(":(?=!!|$)", ""),
      leaf = path |> str_split("!!") |> map_chr(last),
      depth = str_count(path, "!!"),
      year = yr
    ) |>
    select(variable = name, path, leaf, depth, year)
}

var_pattern <- "^B01001_|^B03002_|^B11001_|^B19001_|^B25118_"
message("Resolving variable labels from load_variables()...")
var_map <- map(years, \(yr) label_lookup(yr, var_pattern)) |> list_rbind()
message("Resolved ", nrow(var_map), " variable-label pairs")

# Shared CV formula -- one definition, used by every frame below. A zero or
# absent MOE on a positive estimate is a controlled estimate (CV 0 -> High).
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
b01001_raw <- pull_table("B01001") # sex by age
b03002_raw <- pull_table("B03002") # Hispanic origin by race
b11001_raw <- pull_table("B11001") # household type
b19001_raw <- pull_table("B19001") # household income bands
b19013_raw <- pull_table("B19013") # median household income
b25118_raw <- pull_table("B25118") # tenure by household income

## 5. Pooled-geography helper ----
# Counts add; MOEs of a sum combine in quadrature (the math lives here, not in
# the page -- CLAUDE.md data-flow rule). Ashland is never pooled.
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

add_pooled <- function(df, group_cols) {
  bind_rows(
    df,
    pool_geos(df, unname(bhc), "bhc3", "Richmond core (3 localities)", group_cols),
    pool_geos(df, unname(secondary), "secondary4", "Expansion ring (4 localities)", group_cols),
    pool_geos(df, unname(rr), "rr17", "Richmond region (17 localities)", group_cols)
  ) |>
    add_cv() |>
    flag_reliability()
}

# Collapse published rows into report categories, then pool, then add the share
# of the geography-year total (or of a sub-total via `share_by`).
collapse_pool <- function(df, cat_col, share_by = c("geoid", "year")) {
  df |>
    summarise(
      estimate = sum(estimate),
      moe = sqrt(sum(moe^2)),
      .by = c(geoid, name, year, table, all_of(cat_col))
    ) |>
    mutate(variable = NA_character_) |>
    add_pooled(c("year", "table", cat_col, "variable")) |>
    mutate(
      total = sum(estimate),
      share = estimate / sum(estimate),
      .by = all_of(share_by)
    )
}

## 6. Shape each frame ----

# Population -- B01001's Total row.
population <- b01001_raw |>
  label_join() |>
  filter(depth == 0) |>
  select(geoid, name, year, table, variable, estimate, moe) |>
  add_pooled(c("year", "table", "variable")) |>
  arrange(year, geoid)

# Age x sex -- depth-2 rows are the published age bins under each sex. The
# report age group comes from the first number in the bin ("Under 5 years" has
# none -> 0), which sorts every vintage's bins identically.
age_levels <- c("Under 18", "18-34", "35-54", "55-64", "65 and over")

age_from_leaf <- function(leaf) {
  start <- str_extract(leaf, "\\d+") |> as.integer() |> replace_na(0L)
  case_when(
    start < 18 ~ "Under 18",
    start < 35 ~ "18-34",
    start < 55 ~ "35-54",
    start < 65 ~ "55-64",
    .default = "65 and over"
  )
}

age_sex <- b01001_raw |>
  label_join() |>
  filter(depth == 2) |>
  mutate(
    sex = str_extract(path, "Male|Female"),
    age_group = age_from_leaf(leaf)
  ) |>
  summarise(
    estimate = sum(estimate),
    moe = sqrt(sum(moe^2)),
    .by = c(geoid, name, year, table, sex, age_group)
  ) |>
  mutate(variable = NA_character_) |>
  add_pooled(c("year", "table", "sex", "age_group", "variable")) |>
  mutate(
    total = sum(estimate),
    share = estimate / sum(estimate),
    .by = c(geoid, year)
  ) |>
  mutate(age_group = factor(age_group, levels = age_levels)) |>
  arrange(year, geoid, sex, age_group)

# Race and ethnicity -- Hispanic or Latino (any race) plus the six
# non-Hispanic race rows at depth 2. Two-or-more's depth-3 children and the
# Hispanic-by-race rows are dropped so the groups sum to the table total.
race_groups <- c(
  "White alone" = "White non-Hispanic",
  "Black or African American alone" = "Black",
  "Asian alone" = "Asian",
  "Two or more races" = "Multiracial",
  "American Indian and Alaska Native alone" = "Another race",
  "Native Hawaiian and Other Pacific Islander alone" = "Another race",
  "Some other race alone" = "Another race",
  "Hispanic or Latino" = "Hispanic or Latino"
)
race_levels <- c(
  "White non-Hispanic", "Black", "Hispanic or Latino", "Asian", "Multiracial", "Another race"
)

race_ethnicity <- b03002_raw |>
  label_join() |>
  filter(
    (depth == 2 & str_starts(path, fixed("Total!!Not Hispanic or Latino!!"))) |
      path == "Total!!Hispanic or Latino"
  ) |>
  mutate(race = unname(race_groups[leaf])) |>
  collapse_pool("race") |>
  mutate(race = factor(race, levels = race_levels)) |>
  arrange(year, geoid, race)
stopifnot(!anyNA(race_ethnicity$race))

# Household composition -- depth-2 rows: married-couple, other family, living
# alone, not living alone. Sum to B11001's total households.
hh_labels <- c(
  "Married-couple family" = "Married-couple family",
  "Other family" = "Other family",
  "Householder living alone" = "Living alone",
  "Householder not living alone" = "Nonfamily, not alone"
)
hh_levels <- unname(hh_labels)

household_type <- b11001_raw |>
  label_join() |>
  filter(depth == 2) |>
  mutate(household_type = unname(hh_labels[leaf])) |>
  collapse_pool("household_type") |>
  mutate(household_type = factor(household_type, levels = hh_levels)) |>
  arrange(year, geoid, household_type)
stopifnot(!anyNA(household_type$household_type))

# Income bands -- one grouping function shared by B19001 and B25118. The first
# dollar figure in a band's label is its lower bound; "Less than $X" parses to X
# (< every break), so it lands in the lowest band.
income_levels <- c(
  "Under $25k", "$25k-$49k", "$50k-$74k", "$75k-$99k", "$100k-$149k", "$150k or more"
)

income_from_leaf <- function(leaf) {
  start <- parse_number(leaf)
  case_when(
    str_starts(leaf, "Less than") ~ "Under $25k",
    start < 25000 ~ "Under $25k",
    start < 50000 ~ "$25k-$49k",
    start < 75000 ~ "$50k-$74k",
    start < 100000 ~ "$75k-$99k",
    start < 150000 ~ "$100k-$149k",
    .default = "$150k or more"
  )
}

income_bands <- b19001_raw |>
  label_join() |>
  filter(depth == 1) |>
  mutate(income_band = income_from_leaf(leaf)) |>
  collapse_pool("income_band") |>
  mutate(income_band = factor(income_band, levels = income_levels)) |>
  arrange(year, geoid, income_band)

# Tenure x income -- depth-2 rows under "Owner occupied" / "Renter occupied".
# Share is within tenure, so a reader sees each tenure's own income mix.
tenure_income <- b25118_raw |>
  label_join() |>
  filter(depth == 2) |>
  mutate(
    tenure = if_else(str_detect(path, "^Total!!Owner occupied"), "Owner", "Renter"),
    income_band = income_from_leaf(leaf)
  ) |>
  collapse_pool(c("tenure", "income_band"), share_by = c("geoid", "year", "tenure")) |>
  mutate(income_band = factor(income_band, levels = income_levels)) |>
  arrange(year, geoid, tenure, income_band)

# Median household income -- a median cannot be summed, so no pooled rows.
# Real-dollar columns deflate each window's published (end-year dollar) median
# to the latest window's dollars using national CPI-U annual averages. The CPI
# comes from data/bls_wage.rds when r/bls_wage.R has been run; otherwise the
# real columns are NA and the script says so rather than inventing a deflator.
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
    " -- median_income real-dollar columns will be NA. Run r/bls_wage.R first."
  )
}
cpi_latest <- if (have_cpi) cpi_by_year$cpi[cpi_by_year$year == max(years)] else NA_real_

median_income <- b19013_raw |>
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

## 7. Write output ----
demographics <- list(
  population = population,
  age_sex = age_sex,
  race_ethnicity = race_ethnicity,
  household_type = household_type,
  income_bands = income_bands,
  tenure_income = tenure_income,
  median_income = median_income
)

write_rds(demographics, "data/acs_demographics.rds")

# One long CSV across every frame -- `measure` names the frame, `category`
# carries its dimension (age_sex joins sex and age group), NA where none.
demo_long <- list(
  population = population |> mutate(measure = "population", category = NA_character_),
  age_sex = age_sex |>
    mutate(measure = "age_sex", category = paste(sex, age_group, sep = " / ")),
  race_ethnicity = race_ethnicity |>
    mutate(measure = "race_ethnicity", category = as.character(race)),
  household_type = household_type |>
    mutate(measure = "household_type", category = as.character(household_type)),
  income_bands = income_bands |>
    mutate(measure = "income_bands", category = as.character(income_band)),
  tenure_income = tenure_income |>
    mutate(measure = "tenure_income", category = paste(tenure, income_band, sep = " / ")),
  median_income = median_income |>
    mutate(measure = "median_income", category = NA_character_)
) |>
  map(\(d) select(d, geoid, name, year, table, measure, category, estimate, moe, cv, reliability)) |>
  list_rbind()

export_csv(demo_long, "acs_demographics")
message("Wrote data/acs_demographics.rds + data-out/acs_demographics.csv")

## 8. Validate ----
# stopifnot() fires only on structure and same-vintage identities (category
# sums vs. published table totals; tables that count the same universe agree).
# Vintage-to-vintage change is logged, never gated (CLAUDE.md).
d <- read_rds("data/acs_demographics.rds")

pooled_ids <- c("bhc3", "secondary4", "rr17")
named_ids <- c(unname(rr), unname(ashland), unname(regions), virginia)
expected_geos <- c(named_ids, pooled_ids)

# Published _001 totals, per geography-year, from the raw pulls.
raw_total <- function(raw) {
  raw |>
    filter(str_ends(variable, "_001")) |>
    select(geoid, year, total = estimate)
}

# A frame's categories must sum to the table's own total, every non-pooled cell.
sums_to_total <- function(frame, raw, by = c("geoid", "year")) {
  frame |>
    filter(!geoid %in% pooled_ids) |>
    summarise(parts = sum(estimate), .by = all_of(by)) |>
    summarise(parts = sum(parts), .by = c(geoid, year)) |>
    left_join(raw_total(raw), by = join_by(geoid, year)) |>
    summarise(ok = all(parts == total)) |>
    pull(ok)
}

stopifnot(
  all(map_lgl(d, \(x) nrow(x) > 0)),
  all(map_lgl(d, \(x) all(years %in% x$year))),
  all(map_lgl(d, \(x) !all(is.na(x$estimate)))),
  # geographies: every frame with pooled rows carries all 25; the median
  # frame carries the 22 named ones and no pooled rows.
  all(expected_geos %in% d$population$geoid),
  all(expected_geos %in% d$age_sex$geoid),
  all(expected_geos %in% d$race_ethnicity$geoid),
  all(expected_geos %in% d$household_type$geoid),
  all(expected_geos %in% d$income_bands$geoid),
  all(expected_geos %in% d$tenure_income$geoid),
  setequal(d$median_income$geoid, named_ids),
  nrow(d$population) == nrow(distinct(d$population, geoid, year)),
  nrow(d$median_income) == nrow(distinct(d$median_income, geoid, year)),
  # every category survived its recode
  setequal(levels(d$age_sex$age_group), age_levels),
  setequal(levels(d$race_ethnicity$race), race_levels),
  setequal(levels(d$household_type$household_type), hh_levels),
  setequal(levels(d$income_bands$income_band), income_levels),
  !anyNA(d$population$estimate),
  # same-vintage identities: collapsed categories sum to the published totals
  sums_to_total(d$age_sex, b01001_raw),
  sums_to_total(d$race_ethnicity, b03002_raw),
  sums_to_total(d$household_type, b11001_raw),
  sums_to_total(d$income_bands, b19001_raw),
  sums_to_total(d$tenure_income, b25118_raw, by = c("geoid", "year", "tenure")),
  # B03002 and B01001 both count total population; B11001, B19001 and B25118
  # all count households. Same survey, same window -- they must agree.
  isTRUE(all.equal(
    raw_total(b01001_raw)$total[order(raw_total(b01001_raw)$geoid, raw_total(b01001_raw)$year)],
    raw_total(b03002_raw)$total[order(raw_total(b03002_raw)$geoid, raw_total(b03002_raw)$year)]
  )),
  isTRUE(all.equal(
    raw_total(b11001_raw)$total[order(raw_total(b11001_raw)$geoid, raw_total(b11001_raw)$year)],
    raw_total(b19001_raw)$total[order(raw_total(b19001_raw)$geoid, raw_total(b19001_raw)$year)]
  )),
  isTRUE(all.equal(
    raw_total(b19001_raw)$total[order(raw_total(b19001_raw)$geoid, raw_total(b19001_raw)$year)],
    raw_total(b25118_raw)$total[order(raw_total(b25118_raw)$geoid, raw_total(b25118_raw)$year)]
  ))
)

# Pooled-row consistency: rr17 must equal the sum of its 17 localities.
pop_check <- d$population |>
  filter(geoid %in% unname(rr)) |>
  summarise(parts = sum(estimate), .by = year) |>
  left_join(d$population |> filter(geoid == "rr17") |> select(year, whole = estimate), by = join_by(year))
stopifnot(all(pop_check$parts == pop_check$whole))
message("  rr17 population reconciles to its 17 members in all ", nrow(pop_check), " windows.")

# Logged, not gated -------------------------------------------------------
fmt_chg <- function(a, b) sprintf("%+.1f%%", (b - a) / a * 100)

message("\n-- Population, 2014 -> 2024 (logged, not gated) --")
d$population |>
  filter(geoid %in% c("rr17", "bhc3", "secondary4", unname(bhc), unname(ashland))) |>
  select(name, year, estimate) |>
  pivot_wider(names_from = year, values_from = estimate, names_prefix = "y") |>
  pwalk(\(name, y2014, y2019, y2024) {
    message(
      "  ", str_pad(str_trunc(name, 34), 34, "right"),
      format(y2014, big.mark = ",", width = 10), " -> ",
      format(y2024, big.mark = ",", width = 10), "  ", fmt_chg(y2014, y2024)
    )
  })

message("\n-- Region (rr17): 65+ share and non-White-non-Hispanic share --")
for (yr in years) {
  s65 <- d$age_sex |>
    filter(geoid == "rr17", year == yr, age_group == "65 and over") |>
    pull(share) |> sum()
  snw <- 1 - d$race_ethnicity |>
    filter(geoid == "rr17", year == yr, race == "White non-Hispanic") |>
    pull(share)
  message("  ", yr, "  65+: ", scales::percent(s65, accuracy = 0.1), "  people of color: ", scales::percent(snw, accuracy = 0.1))
}

message("\n-- Median household income, Richmond MSA ", if (have_cpi) "(nominal | 2024 dollars)" else "(nominal)", " --")
d$median_income |>
  filter(geoid == regions[["rva"]]) |>
  pwalk(\(year, estimate, estimate_real, ...) {
    message(
      "  ", year, "  $", format(estimate, big.mark = ","),
      if (have_cpi) paste0("  |  $", format(round(estimate_real), big.mark = ",")) else ""
    )
  })

low_cells <- d$race_ethnicity |>
  filter(geoid %in% c(unname(secondary), unname(ashland)), year == 2024) |>
  summarise(low = sum(reliability == "Low", na.rm = TRUE), n = n())
message(
  "\n  Low-reliability race cells in secondary+Ashland (2024): ",
  low_cells$low, " of ", low_cells$n
)

message("\nacs_demographics.R validation passed.")
