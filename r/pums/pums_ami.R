## Calculate RVA AMI with PUMS Data ----------------------

# 1. Setup ------------------------------------------------

library(tidyverse)
library(tidycensus)
library(srvyr)
library(janitor)

# Load PUMS data
pums_raw <- read_rds("data/pums_raw.rds")
pums_wgt <- read_rds("data/pums_wgt.rds")


# 2. Prepare PUMS data -----------------------------------

# Filter only household records
# Income is reported in each household's survey-year dollars (2020-2024 pooled).
# ADJINC converts to 2024 dollars (tidycensus already returns it as a decimal,
# unlike ADJHSG, which is still the raw 7-digit integer); cpi_factor then inflates 2024 dollars
# to 2026 dollars so incomes match the FY2026 HUD income limits.
# cpi_factor = CPI-U (NSA) avg Jan-Sep 2026 / avg 2024 = 332.243 / 313.689
cpi_factor <- 332.243 / 313.689

adj_file <- "data/pums_adj.rds"
if (!file.exists(adj_file)) {
  stop(
    "Run section 3b of pums_collect.R to create ",
    adj_file,
    " (ADJINC/ADJHSG)."
  )
}
pums_adj <- read_rds(adj_file) |> select(SERIALNO, SPORDER, ADJINC, ADJHSG)

pums_data <- pums_raw |>
  select(1:4, HINCP, NP, PUMA, TEN) |>
  filter(SPORDER == 1) |>
  left_join(pums_wgt) |>
  left_join(pums_adj, by = c("SERIALNO", "SPORDER")) |>
  mutate(HINCP_2024 = HINCP * ADJINC, HINCP_2026 = HINCP_2024 * cpi_factor)

stopifnot(
  "Missing ADJINC for some households" = !any(is.na(pums_data$ADJINC[
    !is.na(pums_data$HINCP)
  ]))
)


# 3. Calculate RVA Median Family Income ------------------

# Read the raw file with base R (avoids the vroom crash) -----

raw <- read.csv(
  "data/summary_county_5176099999.csv",
  header = FALSE,
  stringsAsFactors = FALSE
)

# 2. Pull out Median Family Income from row 2 --------------------

mfi_area <- raw[2, 2] |>
  gsub("[$,]", "", x = _) |>
  as.numeric()

# 3. Pull out the three income limit rows (Very Low, Extremely Low, Low) ----

limit_rows <- raw[4:6, ]

hud_limits <- limit_rows |>
  rename(category = V1) |>
  mutate(across(
    starts_with("V") & !category,
    ~ as.numeric(gsub("[$,]", "", .x))
  )) |>
  rename_with(
    ~ paste0("np_", 1:8),
    .cols = starts_with("V") & !matches("category")
  ) |>
  mutate(
    pct_ami = case_when(
      str_detect(category, "Very Low") ~ "very_low_50",
      str_detect(category, "Extremely Low") ~ "extremely_low_30",
      str_detect(category, "Low \\(80") ~ "low_80"
    )
  ) |>
  select(pct_ami, starts_with("np_"))

# 4. Reshape long, then derive 60% and 100% bands from the 50% limit ----

hud_limits <- hud_limits |>
  pivot_longer(-pct_ami, names_to = "np", values_to = "limit") |>
  mutate(np = parse_number(np)) |>
  pivot_wider(names_from = pct_ami, values_from = limit) |>
  mutate(
    ami_60 = very_low_50 * 1.2,
    ami_100 = very_low_50 * 2.0,
    ami_120 = very_low_50 * 2.4
  ) |>
  rename(ami_30 = extremely_low_30, ami_50 = very_low_50, ami_80 = low_80) |>
  pivot_longer(-np, names_to = "pct_ami", values_to = "limit")

# 5. Categorize households by AMI band --------------------

# Cap household size at 8 to match the HUD table (sizes above 8 use an
# extension rule HUD applies separately, not covered by this file)
pums_data <- pums_data |>
  mutate(np_capped = pmin(NP, 8))

# Widen hud_limits so each household size has all bands in one row
hud_limits_wide <- hud_limits |>
  pivot_wider(names_from = pct_ami, values_from = limit)

ami_levels <- c(
  "Zero or negative income",
  "Below 30% AMI",
  "31-50% AMI",
  "51-60% AMI",
  "61-80% AMI",
  "81-100% AMI",
  "101-120% AMI",
  "121%+ AMI"
)


pums_data <- pums_data |>
  left_join(hud_limits_wide, by = c("np_capped" = "np")) |>
  mutate(
    ami_band = case_when(
      HINCP_2026 <= 0 ~ "Zero or negative income",
      HINCP_2026 <= ami_30 ~ "Below 30% AMI",
      HINCP_2026 <= ami_50 ~ "31-50% AMI",
      HINCP_2026 <= ami_60 ~ "51-60% AMI",
      HINCP_2026 <= ami_80 ~ "61-80% AMI",
      HINCP_2026 <= ami_100 ~ "81-100% AMI",
      HINCP_2026 <= ami_120 ~ "101-120% AMI",
      TRUE ~ "121%+ AMI"
    ),
    ami_band = factor(ami_band, levels = ami_levels, ordered = TRUE)
  )

# Saved for pums_prep.R, which joins ami_band by SERIALNO
write_rds(pums_data, "data/rva_ami_pums.rds")

# 6. Weighted summary of households by AMI band ------------

pums_svy <- pums_data |>
  to_survey(type = "housing", design = "rep_weights")

ami_summary <- pums_svy |>
  mutate(
    puma_label = case_when(
      PUMA == "14501" ~ "Goochland, Powhatan, Western Hanover",
      PUMA == "08501" ~ "King William, New Kent, Charles City, Eastern Hanover",
      PUMA ==
        "08701" ~ "Henrico County - Highland Springs, East Highland Park, Glen Allen",
      PUMA == "08702" ~ "Henrico County - Tuckahoe, Short Pump, Wyndham",
      PUMA == "76001" ~ "Richmond City - North / West",
      PUMA == "76002" ~ "Richmond City - South / East",
      PUMA == "04101" ~ "Chesterfield County - James River",
      PUMA == "04102" ~ "Chesterfield County - Chester & Rockwood",
      PUMA == "04103" ~ "Chesterfield County - Brandermill & Woodlake"
    )
  ) |>
  mutate(
    county = case_when(
      str_detect(puma_label, "Richmond") ~ "Richmond City",
      str_detect(puma_label, "Chesterfield") ~ "Chesterfield County",
      str_detect(puma_label, "Henrico") ~ "Henrico County",
      TRUE ~ puma_label
    ),
    # TEN: 1/2 = owned, 3 = rented, 4 = occupied without payment of rent
    # (ACS counts 4 as renter-occupied); "b" = N/A (group quarters/vacant)
    tenure = case_when(
      TEN %in% c("1", "2") ~ "Owner",
      TEN %in% c("3", "4") ~ "Renter"
    )
  ) |>
  filter(!is.na(tenure)) |>
  group_by(ami_band, tenure, PUMA, puma_label, county) |>
  summarise(households = survey_total(vartype = "se"))


county_summary <- ami_summary |>
  group_by(ami_band, tenure, county) |>
  summarise(households = sum(households), .groups = "drop")

# Percent of Chesterfield households at or below 80% AMI (incl. zero/negative income)
chesterfield_pct_80 <- bind_rows(
  county_summary |> mutate(tenure = "All households"),
  county_summary
) |>
  filter(county == "Chesterfield County") |>
  group_by(tenure) |>
  summarise(
    hh_total = sum(households),
    hh_le80 = sum(households[ami_band <= "61-80% AMI"]),
    pct_le80 = hh_le80 / hh_total
  )

# Same estimates (share of each tenure's households) with replicate-weight
# standard errors / confidence intervals
chesterfield_pums <- pums_svy |>
  filter(PUMA %in% c("04101", "04102", "04103")) |>
  mutate(
    tenure = case_when(
      TEN %in% c("1", "2") ~ "Owner",
      TEN %in% c("3", "4") ~ "Renter"
    ),
    le80 = ami_band <= "61-80% AMI"
  ) |>
  filter(!is.na(tenure))

chesterfield_pct_80_ci <- bind_rows(
  chesterfield_pums |>
    summarise(pct_le80 = survey_mean(le80, vartype = c("se", "ci"))) |>
    mutate(tenure = "All households"),
  chesterfield_pums |>
    group_by(tenure) |>
    summarise(pct_le80 = survey_mean(le80, vartype = c("se", "ci")))
)

ggplot(
  county_summary,
  aes(x = reorder(county, households), y = households, fill = ami_band)
) +
  geom_col(position = 'stack') +
  facet_wrap(~tenure)
