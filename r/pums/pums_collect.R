## Collect PUMS Data for Housing Spectrum -----------------

# 1. Setup ------------------------------------------------

library(tidyverse)
library(tidycensus)
library(srvyr)

# Load PUMS variables to explore
pums_vars_2024 <- pums_variables |>
  filter(year == 2022, survey == "acs5")

rva_2010 <- c("51215", "51224", "51225", "51235", "04101", "04102", "04103") # 2010 PUMA codes
rva_2020 <- c(
  "14501",
  "08501",
  "08701",
  "08702",
  "76001",
  "76002",
  "04101",
  "04102",
  "04103"
) # 2020 PUMA codes


# 2. Variables --------------------------------------------

make_pums_vars <- function() {
  # HOUSING RECORD - BASIC VARIABLES
  vars_hr_basic <- c(
    "PUMA",
    "NP" # Number of persons in household
  )

  # HOUSING RECORD - HOUSING UNIT VARIABLES
  vars_hr_hu <- c(
    "BDSP", # Number of bedrooms
    "BLD", # Units in structure
    "FS", # SNAP status
    "TEN", # Tenure
    "YRBLT" # When structure first built
  )

  # HOUSING RECORD - HOUSEHOLD VARIABLES
  vars_hr_hh <- c(
    "FINCP", # Family income
    "GRNTP", # Gross rent
    "HHLDRHISP", # Hispanic origin
    "HHLDRRAC1P", # Race
    "HHT2", # Household/family type (includes cohabiting)
    "ADJHSG", # Adjustment factor for housing dollar amounts (rent, owner costs)
    "ADJINC", # Adjustment factor for income and earnings dollar amounts
    "HINCP", # Household income
    "MULTG", # Multigenerational household
    "MV", # When moved into home
    "NOC", # Number of own children
    "SMOCP", # Selected monthly owner costs
    "WIF" # Workers in family
  )

  # PERSON RECORD - PERSON VARIABLES
  vars_pr_p <- c(
    "AGEP", # Age
    "COW", # Class of worker
    "HINS3", # Medicare
    "HINS4", # Medicaid
    "INTP", # Interest, dividends, and net rental income
    "JWMNP", # Travel time to work
    "JWRIP", # Carpool status
    "JWTRNS", # Means of transportation to work
    "OIP", # All other income
    "PAP", # Public assistance income
    "RELSHIPP", # Relationship (to householder)
    "RETP", # Retirement income
    "SCHL", # Educational attainment
    "SEMP", # Self-employment income
    "SEX", # Sex
    "SSIP", # Supplemental Security Income amount
    "SSP", # Social Security amount
    "WAGP", # Wages or salary income
    "WKL" # When last worked
  )

  # PERSON RECORD - RECODED PERSON VARIABLES
  vars_pr_rcp <- c(
    "DIS", # Disability
    "ESR", # Employment status recode
    "NAICSP", # NAICS recode (based on 2017 NAICS codes)
    "POWPUMA", # Place of work PUMA (2020 definition)
    "POWSP", # Place of work state
    "SOCP" # SOC codes (based on 2018 SOC codes)
  )

  vars_spectrum <- c(
    vars_hr_basic,
    vars_hr_hu,
    vars_hr_hh,
    vars_pr_p,
    vars_pr_rcp
  )

  vars_spectrum
}

vars_spectrum <- make_pums_vars()

write_rds(vars_spectrum, "data/pums_vars.rds")

# 3. Collect PUMS variables -------------------------------

# Get PUMS variables without weights
pums_raw <- get_pums(
  variables = vars_spectrum,
  year = 2024,
  state = "VA",
  survey = "acs5"
) |>
  filter(PUMA %in% rva_2020)

# Save or load as needed
write_rds(pums_raw, "data/pums_raw.rds")
# pums_raw <- read_rds("data/pums/pums_raw.rds")

# 3b. Collect income / housing adjustment factors ---------

# The 5-year PUMS pools 2020-2024 responses. HINCP, FINCP, WAGP, etc. are in the
# dollars of each household's survey year until multiplied by ADJINC (2024
# dollars; tidycensus returns it already as a decimal, e.g. 1.222017). Rent and
# owner costs use ADJHSG / 1e6 (still the raw integer, e.g. 1214548). This pulls only the
# factors so an existing pums_raw does not need to be re-collected.
# Requires a Census API key: census_api_key("YOUR KEY", install = TRUE)
pums_adj <- get_pums(
  variables = c("PUMA", "ADJINC", "ADJHSG"),
  year = 2024,
  state = "VA",
  survey = "acs5"
) |>
  filter(PUMA %in% rva_2020) |>
  select(SERIALNO, SPORDER, ADJINC, ADJHSG) |>
  mutate(across(c(ADJINC, ADJHSG), as.numeric))

write_rds(pums_adj, "data/pums_adj.rds")

# 4. Collect PUMS weights ---------------------------------

# Get PUMS with weights only
pums_wgt <- get_pums(
  variables = c("PUMA"),
  year = 2024,
  state = "VA",
  survey = "acs5",
  rep_weights = "both"
) |>
  filter(PUMA %in% rva_2020)

# Save or load as needed
write_rds(pums_wgt, "data/pums_wgt.rds")
pums_wgt <- read_rds("data/pums_wgt.rds")
