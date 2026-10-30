# pums_profiles.R ----
# What:   Households and residents of the Richmond-area PUMS region by AMI band
#         and housing tenure, plus a profile of each income band by tenure
#         (household makeup, householder age and race, earners, disability,
#         structure type, cost burden, and resident age / education /
#         employment). profiles.qmd reads the result; the page never touches
#         the replicate weights.
# Source: ACS 2020-2024 5-year PUMS (data/pums_raw.rds, data/pums_wgt.rds) and
#         the AMI band assigned per household in r/pums/pums_ami.R
#         (data/rva_ami_pums.rds; FY2026 HUD income limits, incomes inflated to
#         2026 dollars with the same CPI factor).
# Geo:    The 9 PUMAs in r/pums/rva_puma.R -- the "PUMS region". It is NOT the
#         17-locality `rr`: the two outer PUMAs mix localities (Goochland,
#         Powhatan, western Hanover; King William, New Kent, Charles City,
#         eastern Hanover) and the southern localities (Petersburg, Hopewell,
#         Colonial Heights, Dinwiddie, Prince George, Sussex, Amelia,
#         King & Queen) are outside it. Chesterfield, Henrico, and Richmond
#         city tile cleanly into whole PUMAs, so those three are exact.
# Method: Standard errors use the 80 Census replicate weights,
#         SE = sqrt(4/80 * sum((replicate - estimate)^2)). Reliability reuses
#         flag_reliability() on the CV of each estimate (share or count).
#         Vacant units and group quarters (TEN == "b") are excluded -- their
#         missing income would otherwise fall into the top AMI band.
# Output: data/pums_profiles.rds  -- named list (see section 8)
#         data-out/pums_ami_dist.csv, data-out/pums_profile.csv

## 1. Setup ----
library(tidyverse)
source("_common.R") # puma_core3, puma_locality, flag_reliability(), export_csv()

dir.create("data", showWarnings = FALSE, recursive = TRUE)

# Same constant as pums_ami.R / pums_prep.R: CPI-U (NSA) avg Jan-Sep 2026 / avg 2024
cpi_factor <- 332.243 / 313.689

ami_levels <- c(
  "Zero or negative income", "Below 30% AMI", "31-50% AMI", "51-60% AMI",
  "61-80% AMI", "81-100% AMI", "101-120% AMI", "121%+ AMI"
)
ami5_levels <- c(
  "30% AMI or less", "31-50% AMI", "51-80% AMI", "81-120% AMI", "Above 120% AMI"
)
all_ami <- "All income levels"
all_ten <- "All households"
all_geo <- "PUMS region"

## 2. Inputs ----
for (f in c("data/pums_raw.rds", "data/pums_wgt.rds", "data/rva_ami_pums.rds")) {
  if (!file.exists(f)) stop("Missing ", f, " -- run r/pums/pums_collect.R and pums_ami.R first.")
}
raw <- read_rds("data/pums_raw.rds")
wgt <- read_rds("data/pums_wgt.rds")
ami <- read_rds("data/rva_ami_pums.rds")

hud <- read.csv("data/summary_county_5176099999.csv", header = FALSE, stringsAsFactors = FALSE)
mfi_area <- as.numeric(gsub("[$,]", "", hud[2, 2]))

limits <- ami |>
  distinct(np = np_capped, ami_30, ami_50, ami_60, ami_80, ami_100, ami_120) |>
  arrange(np)

geo_of <- c(
  puma_locality,
  "08501" = "Outer-ring PUMAs",
  "14501" = "Outer-ring PUMAs"
)
stopifnot("Unmapped PUMA" = all(raw$PUMA %in% names(geo_of)))

## 3. Person and household base frames ----
# Weight columns: `wt` plus `rep1`..`rep80`, built per unit (household or person)
wc <- c("wt", paste0("rep", 1:80))
set_weights <- function(df, prefix) {
  df |>
    rename(wt = all_of(prefix)) |>
    rename_with(\(x) sub(paste0("^", prefix), "rep", x), matches(paste0("^", prefix, "[0-9]+$")))
}

pers_w <- wgt |> select(SERIALNO, SPORDER, PWGTP1:PWGTP80)
hh_w <- wgt |> filter(SPORDER == 1) |> select(SERIALNO, WGTP1:WGTP80)

pp <- raw |>
  filter(TEN != "b") |>
  left_join(ami |> select(SERIALNO, ami_band, HINCP_2026), by = "SERIALNO") |>
  left_join(pers_w, by = c("SERIALNO", "SPORDER")) |>
  mutate(
    adjinc = as.numeric(ADJINC),
    adjhsg = as.numeric(ADJHSG) / 1e6,
    geo = unname(geo_of[PUMA]),
    tenure = recode_values(TEN, c("1", "2") ~ "Owner", c("3", "4") ~ "Renter"),
    ami5 = recode_values(
      as.character(ami_band),
      c("Zero or negative income", "Below 30% AMI") ~ ami5_levels[1],
      "31-50% AMI" ~ ami5_levels[2],
      c("51-60% AMI", "61-80% AMI") ~ ami5_levels[3],
      c("81-100% AMI", "101-120% AMI") ~ ami5_levels[4],
      "121%+ AMI" ~ ami5_levels[5]
    ),
    le80 = if_else(
      as.character(ami_band) %in% c("81-100% AMI", "101-120% AMI", "121%+ AMI"),
      "Above 80% AMI", "At or below 80% AMI"
    ),
    earner = (pmax(WAGP, 0) + SEMP) * adjinc * cpi_factor >= 5000
  ) |>
  mutate(
    hh_earners = sum(earner, na.rm = TRUE),
    hh_disability = any(DIS == "1"),
    .by = SERIALNO
  )

stopifnot(
  "Occupied person without AMI band" = !anyNA(pp$ami_band),
  "Person without tenure" = !anyNA(pp$tenure),
  "Person without replicate weights" = !anyNA(pp$PWGTP1)
)

# Household frame: one row per occupied household (the reference person)
hh <- pp |>
  filter(SPORDER == 1) |>
  select(-matches("^PWGTP[0-9]+$"), -SPORDER) |>
  left_join(hh_w, by = "SERIALNO") |>
  mutate(
    cost = case_when(
      tenure == "Owner" & SMOCP > 0 ~ SMOCP * adjhsg * cpi_factor,
      TEN == "3" & GRNTP > 0 ~ GRNTP * adjhsg * cpi_factor
    ),
    cost_ratio = if_else(HINCP_2026 > 0, cost / (HINCP_2026 / 12), NA_real_),
    hh_size_grp = cut(NP, c(0, 1, 2, 4, Inf), labels = c("1 person", "2 people", "3-4 people", "5+ people")),
    hh_type = recode_values(
      HHT2,
      c("01", "03") ~ "Couple with children",
      c("02", "04") ~ "Couple, no children",
      c("06", "10") ~ "Single parent",
      c("05", "09") ~ "Living alone",
      c("07", "08", "11", "12") ~ "Other (relatives or roommates)"
    ),
    householder_age = cut(AGEP, c(-Inf, 34, 54, 64, Inf), labels = c("Under 35", "35-54", "55-64", "65 and over")),
    householder_race = case_when(
      HHLDRHISP != "01" ~ "Hispanic or Latino",
      HHLDRRAC1P == "1" ~ "White non-Hispanic",
      HHLDRRAC1P == "2" ~ "Black",
      HHLDRRAC1P == "6" ~ "Asian",
      TRUE ~ "Another race or multiracial"
    ),
    children = if_else(pmax(NOC, 0) > 0, "Children under 18", "No children under 18"),
    earners = cut(hh_earners, c(-Inf, 0, 1, Inf), labels = c("No earners", "1 earner", "2+ earners")),
    disability = if_else(hh_disability, "Member with a disability", "No member with a disability"),
    structure = recode_values(
      BLD,
      "02" ~ "Single-family detached",
      "03" ~ "Single-family attached",
      c("04", "05", "06") ~ "2-9 units",
      c("07", "08", "09") ~ "10+ units",
      c("01", "10") ~ "Mobile home or other"
    ),
    burden = case_when(
      is.na(cost_ratio) ~ NA_character_,
      cost_ratio < 0.30 ~ "Not cost-burdened",
      cost_ratio < 0.50 ~ "Cost-burdened (30-49%)",
      TRUE ~ "Severely cost-burdened (50%+)"
    )
  ) |>
  mutate(across(c(hh_size_grp, householder_age, earners), as.character)) |>
  set_weights("WGTP")

# Person frame (residents). Education is adults 25+, employment is 16+ (ESR is
# "b" under 16). Age groups follow the Demographics page where possible.
pp <- pp |>
  mutate(
    age_grp = cut(AGEP, c(-Inf, 17, 34, 64, Inf), labels = c("Under 18", "18-34", "35-64", "65 and over")),
    schl_n = suppressWarnings(as.integer(SCHL)),
    education = case_when(
      AGEP < 25 ~ NA_character_,
      schl_n <= 15 ~ "Less than high school",
      schl_n <= 17 ~ "High school or GED",
      schl_n <= 20 ~ "Some college or associate's",
      TRUE ~ "Bachelor's or higher"
    ),
    employment = recode_values(
      ESR,
      c("1", "2", "4", "5") ~ "Employed",
      "3" ~ "Unemployed",
      "6" ~ "Not in labor force"
    ),
    resident_disability = if_else(DIS == "1", "With a disability", "Without a disability"),
    age_grp = as.character(age_grp)
  ) |>
  set_weights("PWGTP")

## 4. Replicate-weight estimators ----
tidy_rep <- function(tab) {
  reps <- as.matrix(tab[paste0("rep", 1:80)])
  tab |>
    mutate(est = wt, se = sqrt(4 / 80 * rowSums((reps - wt)^2))) |>
    select(-all_of(wc))
}

# Append an "All" copy of each dimension so totals ride through the same code
add_all <- function(df, col, label) {
  bind_rows(df, df |> mutate("{col}" := label))
}

rep_total <- function(df, by) {
  df |>
    summarise(across(all_of(wc), sum), n_obs = n(), .by = all_of(by)) |>
    tidy_rep()
}

rep_share <- function(df, by, cat) {
  df |>
    filter(!is.na(.data[[cat]])) |>
    summarise(across(all_of(wc), sum), n_obs = n(), .by = all_of(c(by, cat))) |>
    mutate(
      across(all_of(wc), \(x) x / sum(x)),
      denom_obs = sum(n_obs),
      .by = all_of(by)
    ) |>
    tidy_rep() |>
    rename(category = all_of(cat))
}

wmedian <- function(x, w) {
  o <- order(x)
  x <- x[o]
  w <- w[o]
  x[which(cumsum(w) >= sum(w) / 2)[1]]
}

rep_median <- function(df, by, var) {
  df |>
    filter(!is.na(.data[[var]])) |>
    group_by(across(all_of(by))) |>
    group_modify(\(d, k) {
      est <- wmedian(d[[var]], d$wt)
      reps <- map_dbl(1:80, \(i) wmedian(d[[var]], d[[paste0("rep", i)]]))
      tibble(est = est, se = sqrt(4 / 80 * sum((reps - est)^2)), n_obs = nrow(d))
    }) |>
    ungroup()
}

# CV is a 0-100 percentage (flag_reliability() contract); undefined at est == 0
finish <- function(df) {
  df |>
    mutate(cv = if_else(est > 0, se / est * 100, NA_real_), moe90 = 1.645 * se) |>
    flag_reliability()
}

## 5. Distribution by AMI band, tenure, and geography ----
# Households and residents; the distribution is each tenure's own share, so a
# column of bars sums to 1. "All" copies give region / all-tenure rows.
expand_units <- function(df) {
  df |>
    add_all("geo", all_geo) |>
    add_all("tenure", all_ten)
}

# `band_col` is the AMI grouping to distribute over (8 HUD-style bands or the 5
# profile bands); output carries it as `band`.
dist_one <- function(df, unit, band_col, band_levels) {
  d <- df |>
    mutate(band = factor(as.character(.data[[band_col]]), levels = band_levels)) |>
    expand_units()
  bind_rows(
    rep_total(d, c("geo", "tenure", "band")) |>
      mutate(measure = "count"),
    rep_share(d |> mutate(band = as.character(band)), c("geo", "tenure"), "band") |>
      mutate(measure = "share", band = factor(category, levels = band_levels)) |>
      select(-category)
  ) |>
    mutate(unit = unit)
}

dist_both <- function(band_col, band_levels) {
  bind_rows(
    dist_one(hh, "Households", band_col, band_levels),
    dist_one(pp, "Residents", band_col, band_levels)
  ) |>
    mutate(band = factor(as.character(band), levels = band_levels)) |>
    select(unit, geo, tenure, band, measure, est, se, n_obs, any_of("denom_obs")) |>
    finish()
}

ami_dist <- dist_both("ami_band", ami_levels)
dist5 <- dist_both("ami5", ami5_levels)

# Share of each geography x tenure at or below 80% AMI
le80 <- bind_rows(
  rep_share(expand_units(hh), c("geo", "tenure"), "le80") |> mutate(unit = "Households"),
  rep_share(expand_units(pp), c("geo", "tenure"), "le80") |> mutate(unit = "Residents")
) |>
  filter(category == "At or below 80% AMI") |>
  select(unit, geo, tenure, est, se, n_obs, denom_obs) |>
  finish()

# Tenure mix within each AMI band (region only)
tenure_mix <- bind_rows(
  rep_share(hh |> add_all("ami5", all_ami), "ami5", "tenure") |> mutate(unit = "Households"),
  rep_share(pp |> add_all("ami5", all_ami), "ami5", "tenure") |> mutate(unit = "Residents")
) |>
  rename(tenure = category) |>
  select(unit, ami5, tenure, est, se, n_obs, denom_obs) |>
  finish()

# Counts for the five profile bands x tenure (region)
band_counts <- bind_rows(
  rep_total(hh |> add_all("ami5", all_ami) |> add_all("tenure", all_ten), c("ami5", "tenure")) |>
    mutate(unit = "Households"),
  rep_total(pp |> add_all("ami5", all_ami) |> add_all("tenure", all_ten), c("ami5", "tenure")) |>
    mutate(unit = "Residents")
) |>
  finish()

## 6. Profiles by AMI band and tenure ----
# One call per topic; the band x tenure grid includes "All" margins.
prof_one <- function(df, topic, cat, unit) {
  df |>
    add_all("ami5", all_ami) |>
    add_all("tenure", all_ten) |>
    rep_share(c("ami5", "tenure"), cat) |>
    mutate(unit = unit, topic = topic)
}

profile <- bind_rows(
  prof_one(hh, "Household size", "hh_size_grp", "Households"),
  prof_one(hh, "Household type", "hh_type", "Households"),
  prof_one(hh, "Householder age", "householder_age", "Households"),
  prof_one(hh, "Householder race and ethnicity", "householder_race", "Households"),
  prof_one(hh, "Children", "children", "Households"),
  prof_one(hh, "Earners", "earners", "Households"),
  prof_one(hh, "Disability", "disability", "Households"),
  prof_one(hh, "Structure type", "structure", "Households"),
  prof_one(hh, "Cost burden", "burden", "Households"),
  prof_one(pp, "Resident age", "age_grp", "Residents"),
  prof_one(pp, "Education (25 and over)", "education", "Residents"),
  prof_one(pp, "Employment (16 and over)", "employment", "Residents"),
  prof_one(pp, "Resident disability", "resident_disability", "Residents")
) |>
  select(unit, topic, ami5, tenure, category, est, se, n_obs, denom_obs) |>
  finish()

# Medians: income of all households; monthly housing cost (owner costs for
# owners, gross rent for renters) among households that pay one.
med_in <- hh |> add_all("ami5", all_ami) |> add_all("tenure", all_ten)
medians <- bind_rows(
  rep_median(med_in, c("ami5", "tenure"), "HINCP_2026") |> mutate(measure = "Household income"),
  rep_median(med_in, c("ami5", "tenure"), "cost") |> mutate(measure = "Monthly housing cost"),
  rep_median(med_in, c("ami5", "tenure"), "AGEP") |> mutate(measure = "Householder age")
) |>
  finish()

## 7. Validation ----
# Structural expectations (stopifnot) and a same-vintage published benchmark;
# the benchmark variance is logged.
n_hh <- sum(hh$wt)
n_res <- sum(pp$wt)
message("PUMS region: ", format(round(n_hh), big.mark = ","), " households, ",
        format(round(n_res), big.mark = ","), " residents in households")

tot_check <- ami_dist |>
  filter(unit == "Households", geo == all_geo, tenure == all_ten, measure == "count")
stopifnot(
  "Band counts do not sum to total households" = abs(sum(tot_check$est) - n_hh) < 1,
  "Replicate SEs missing or non-positive" = !anyNA(ami_dist$se) && all(ami_dist$se >= 0),
  "All eight AMI bands present" = n_distinct(tot_check$band) == length(ami_levels),
  "Profile shares must sum to 1" = profile |>
    summarise(s = sum(est), .by = c(unit, topic, ami5, tenure)) |>
    pull(s) |>
    (\(s) all(abs(s - 1) < 1e-8))(),
  "A profile topic is all NA" = !anyNA(profile$est),
  "Owner + renter must equal all households" = {
    t <- band_counts |> filter(unit == "Households", ami5 == all_ami)
    abs(sum(t$est[t$tenure != all_ten]) - t$est[t$tenure == all_ten]) < 1
  }
)

# Benchmark: Chesterfield, Henrico, and Richmond city tile into whole PUMAs, so
# PUMS weighted households should track ACS B25003 for those three localities
# (same 2020-2024 window) -- PUMS weights are controlled to ACS, so the
# difference is small by construction. 3% tolerance per tenure.
market <- read_rds("data/acs_market.rds")
acs_ten <- market$tenure |>
  filter(geoid %in% unname(bhc), year == max(year), tenure %in% c("Owner", "Renter")) |>
  summarise(acs = sum(estimate), .by = tenure)
pums_ten <- hh |>
  filter(PUMA %in% puma_core3) |>
  summarise(pums = sum(wt), .by = tenure)
bench <- inner_join(acs_ten, pums_ten, by = "tenure") |> mutate(pct_diff = pums / acs - 1)
print(bench)
stopifnot(
  "Benchmark lost a tenure" = nrow(bench) == 2,
  "PUMS vs ACS B25003 households differ by more than 3%" = all(abs(bench$pct_diff) <= 0.03)
)

low_share <- profile |> filter(tenure != all_ten, ami5 != all_ami) |> count(reliability) |> mutate(p = n / sum(n))
message("Profile cells (band x tenure): ", paste0(low_share$reliability, " ", round(low_share$p * 100), "%", collapse = ", "))

## 8. Output ----
out <- list(
  mfi = mfi_area,
  limits = limits,
  levels = list(ami = ami_levels, ami5 = ami5_levels),
  n = list(households = n_hh, residents = n_res, hh_records = nrow(hh), res_records = nrow(pp)),
  ami_dist = ami_dist,
  dist5 = dist5,
  le80 = le80,
  tenure_mix = tenure_mix,
  band_counts = band_counts,
  profile = profile,
  medians = medians,
  benchmark = bench
)
write_rds(out, "data/pums_profiles.rds")
export_csv(ami_dist, "pums_ami_dist")
export_csv(profile, "pums_profile")
message("Wrote data/pums_profiles.rds")
