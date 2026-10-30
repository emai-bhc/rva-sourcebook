## Prepare PUMS Data for Housing Spectrum -----------------

## 1. Setup -----------------------------------------------

library(tidyverse)
library(tidycensus)
library(srvyr)


pums_raw <- read_rds("data/pums_raw.rds")
pums_wgt <- read_rds("data/pums_wgt.rds")
pums_labels <- read_rds("data/pums_labels.rds")
rva_ami <- read_rds("data/rva_ami_pums.rds") |>
  select(SERIALNO, ami_band)

fct_case_when <- function(..., dir = 1) {
  # Capture all arguments passed to the function
  args <- list(...)

  # Extract the right-hand side (RHS) of each formula in the arguments
  # This will be used as the levels for the factor
  levels <- sapply(args, function(f) as.character(f[[3]]))

  # Remove any NA values from the levels
  levels <- levels[!is.na(levels)]

  # Remove duplicates while preserving order
  levels <- unique(levels)

  # Reverse the order of levels if dir is -1
  if (dir == -1) {
    levels <- rev(levels)
  }

  # Create a factor using case_when for the values and the extracted levels
  # This ensures the factor levels are in the order specified by the user
  factor(dplyr::case_when(...), levels = levels)
}
## 2. Join AMI limits to PUMS data ------------------------

# Adjust dollar amounts to 2026 dollars so they match the FY2026 HUD income limits.
# The 5-year PUMS pools 2020-2024 responses, each in its own survey-year dollars.
# - Income: ADJINC converts to 2024 dollars (tidycensus returns it as a decimal)
# - Housing costs: ADJHSG / 1e6 converts to 2024 dollars (still the raw integer)
# - cpi_factor inflates 2024 dollars to 2026 (same constant as pums_ami.R):
#   CPI-U (NSA) avg Jan-Sep 2026 / avg 2024 = 332.243 / 313.689
cpi_factor <- 332.243 / 313.689

# Income variables use -1 / -10001 as not-applicable codes; leave those untouched
adj_inc <- function(x, adj) {
  if_else(x %in% c(-1, -10001), x, x * adj * cpi_factor)
}
# Housing costs: only scale real (positive) amounts; 0 / -1 are not-applicable codes
adj_hsg <- function(x, adj) if_else(x > 0, x * adj * cpi_factor, x)

pums_raw <- pums_raw |>
  mutate(
    adjinc = as.numeric(ADJINC),
    adjhsg = as.numeric(ADJHSG) / 1e6,
    across(
      c(HINCP, FINCP, INTP, OIP, PAP, RETP, SEMP, SSIP, SSP, WAGP),
      ~ adj_inc(.x, adjinc)
    ),
    across(c(GRNTP, SMOCP), ~ adj_hsg(.x, adjhsg))
  ) |>
  select(-ADJINC, -ADJHSG, -adjinc, -adjhsg)

# Join AMI limits and categorize
rva_pums_ami <- pums_raw |>
  filter(!TEN == "b") |>
  mutate(NP = pmin(NP, 8)) |>
  left_join(rva_ami, by = "SERIALNO")


## 3. Calculate number of earners in household ------------

# Identify persons with wages or salary at least $5000 in last 12 months
rva_pums_earners <- rva_pums_ami |>
  group_by(SERIALNO) |>
  mutate(
    hh_earners = sum((WAGP + SEMP) >= 5000) # Include self-employment income
  ) |>
  ungroup()


## 4. Add place of work labels ----------------------------

powpuma_lookup <- read_rds("data/powpuma_lookup.rds") |>
  select(5:6)

rva_pums_pow <- rva_pums_earners |>
  # Clean state POW column
  mutate(
    POWSP = case_when(
      POWSP == "00N" ~ NA,
      str_starts(POWSP, "0") ~ str_sub(POWSP, start = 2, end = 3),
      .default = POWSP
    )
  ) |>
  # Create POW GEOID column
  mutate(
    pow_geoid = case_when(
      is.na(POWSP) ~ NA,
      POWPUMA != "-0009" ~ paste0("20-", POWSP, POWPUMA)
    )
  ) |>
  # Join POW lookup data
  left_join(powpuma_lookup) |>
  # Retain Virginia region labels and add DC/MD labels
  mutate(
    pow_label = case_when(
      POWSP == "51" ~ pow_label,
      POWSP == "11" ~ "Washington, DC",
      POWSP == "24" ~ "Maryland",
      !is.na(POWSP) ~ "Another state",
      .default = NA
    )
  ) |>
  # Add 'core_workforce' field to flag HHs with at least 1 worker with POW in rva region
  group_by(SERIALNO) |>
  mutate(
    core_workforce = if_else(
      SPORDER == 1,
      any(pow_label == "Richmond area", na.rm = TRUE),
      NA
    )
  ) |>
  fill(core_workforce, .direction = "downup") |>
  ungroup()


## 5. Add cost burden data and labels ---------------------

rva_pums_cb <- rva_pums_pow |>
  mutate(
    cb = case_when(
      HINCP == 0 ~ NA,
      SMOCP > GRNTP ~ SMOCP / (HINCP / 12),
      GRNTP > SMOCP ~ GRNTP / (HINCP / 12)
    ),
    cb = case_when(
      cb > 1.0 ~ 1.0,
      .default = cb
    )
  ) |>
  mutate(
    cb_label = fct_case_when(
      cb < 0.30 ~ "Not cost-burdened",
      cb < 0.50 ~ "Cost-burdened",
      cb >= 0.50 ~ "Severely cost-burdened"
    )
  )


## 6. Add household-level age and disability labels -------

rva_pums_agedis <- rva_pums_cb |>
  group_by(SERIALNO) |>
  mutate(
    hh_age = fct_case_when(
      mean(
        AGEP[RELSHIPP %in% c("20", "21", "22", "23", "24", "34")],
        na.rm = TRUE
      ) <
        35 ~ "Young",
      mean(
        AGEP[RELSHIPP %in% c("20", "21", "22", "23", "24", "34")],
        na.rm = TRUE
      ) <
        65 ~ "Middle-age",
      mean(
        AGEP[RELSHIPP %in% c("20", "21", "22", "23", "24", "34")],
        na.rm = TRUE
      ) <
        80 ~ "Senior",
      TRUE ~ "Elderly"
    ),
  ) |>
  mutate(
    hh_disability = if_else(
      SPORDER == 1,
      any(DIS == 1, na.rm = TRUE), # DIS: 1 = with a disability, 2 = without
      NA
    )
  ) |>
  ungroup()

## 7. Add number of minors --------------------------------

# Children under 18 in household

rva_pums_minors <- rva_pums_agedis |>
  group_by(SERIALNO) |>
  mutate(
    minors = sum(str_detect(RELSHIPP, "25|26|27|30|35") & AGEP < 18)
  ) |>
  ungroup()


## 8. Recode PUMS data as needed --------------------------

# Use custom function from pums_labels.R
pums_recode <- function(data, vars) {
  recoded_data <- data

  for (var_name in vars) {
    recoded_data <- recoded_data %>%
      left_join(
        pums_labels %>%
          filter(var_code == var_name) %>%
          select(val, val_label),
        by = setNames("val", var_name)
      ) %>%
      mutate(
        !!var_name := coalesce(val_label, as.character(.data[[var_name]]))
      ) %>%
      select(-val_label)
  }

  return(recoded_data)
}

# Create list of variables to recode
vars_recode <- c(
  "BLD",
  "FS",
  "TEN",
  "YRBLT",
  "HHLDRHISP",
  "HHLDRRAC1P",
  "HHT2",
  "MV",
  "WIF",
  "COW",
  "HINS3",
  "HINS4",
  "RELSHIPP",
  "SCHL",
  "SEX",
  "DIS",
  "ESR",
  "NAICSP",
  "SOCP"
)

rva_pums_recode <- pums_recode(rva_pums_minors, vars_recode)


## 8. Rename PUMS variables as needed ---------------------

pums_rename <- function(data) {
  data |>
    rename(
      hh_size = NP,
      bedrooms = BDSP,
      fam_income = FINCP,
      cost_rent = GRNTP,
      hh_income = HINCP,
      children = NOC,
      cost_own = SMOCP,
      age = AGEP,
      inc_int = INTP,
      inc_other = OIP,
      inc_public = PAP,
      inc_ret = RETP,
      inc_selfemp = SEMP,
      inc_ssi = SSIP,
      inc_ss = SSP,
      inc_wages = WAGP,
      str_type = BLD,
      snap = FS,
      tenure = TEN,
      str_yrblt = YRBLT,
      ethnicity = HHLDRHISP,
      race = HHLDRRAC1P,
      hh_type = HHT2,
      multigen = MULTG,
      moved = MV,
      workers = WIF,
      wkr_class = COW,
      medicare = HINS3,
      medicaid = HINS4,
      relationship = RELSHIPP,
      edu = SCHL,
      sex = SEX,
      disability = DIS,
      emp_status = ESR,
      last_work = WKL,
      jtw = JWTRNS,
      naics = NAICSP,
      soc = SOCP
    )
}

rva_pums_rename <- pums_rename(rva_pums_recode)


## 8. Group NAICS and SOC codes into categories -----------

# Load lookup tables created in naics_soc_lookup.rds

naics_recode <- read_rds("data/naics_recode.rds") |>
  select(naics = val_label, naics_group)

soc_recode <- read_rds("data/soc_recode.rds") |>
  select(soc = val_label, soc_group)

rva_pums_occ <- rva_pums_rename |>
  left_join(naics_recode) |>
  left_join(soc_recode)

## 9. Clean up and reorder columns ------------------------

rva_pums_clean <- rva_pums_occ |>
  select(
    1:4,
    # Household info
    "PUMA",
    "hh_size",
    "hh_type",
    "hh_age",
    "multigen",
    "children",
    "minors",
    "race",
    "ethnicity",
    # Person info
    "relationship",
    "age",
    "sex",
    "edu",
    # Income and wages
    "ami_band",
    "hh_income",
    "fam_income",
    "inc_wages",
    "inc_selfemp",
    "inc_ret",
    "inc_int",
    "inc_ss",
    "inc_ssi",
    "inc_public",
    "inc_other",
    # Housing
    "tenure",
    "str_type",
    "bedrooms",
    "str_yrblt",
    "moved",
    "cost_own",
    "cost_rent",
    "cb",
    "cb_label",
    # Disability and assistance
    "hh_disability",
    "disability",
    "snap",
    "medicare",
    "medicaid",
    # Economic
    "workers",
    "hh_earners",
    "emp_status",
    "last_work",
    "wkr_class",
    "jtw",
    "pow_label",
    "core_workforce",
    "naics",
    "soc",
    "naics_group",
    "soc_group"
  )


## 10. Simplify variable labels ---------------------------

rva_pums_simple <- rva_pums_clean |>
  mutate(
    hh_type = fct_case_when(
      str_detect(hh_type, "Married|Cohabiting") ~ "Couple",
      str_detect(
        hh_type,
        "no spouse/partner present, with children"
      ) ~ "Single parent",
      str_detect(hh_type, "living alone") ~ "Individual",
      str_detect(hh_type, "with relatives") ~ "Relatives",
      str_detect(hh_type, "nonrelatives") ~ "Roommates"
    )
  ) |>
  mutate(
    race = case_when(
      ethnicity != "Not Spanish/Hispanic/Latino" ~ "Hispanic or Latino",
      ethnicity == "Not Spanish/Hispanic/Latino" ~ str_remove_all(
        race,
        " alone"
      )
    ),
    race = case_when(
      race == "Black or African American" ~ "Black",
      race == "Two or More Races" ~ "Multiracial",
      race == "Some Other Race" ~ "Another race",
      str_detect(race, "American Indian") ~ "American Indian",
      .default = race
    )
  ) |>
  mutate(
    relationship = case_when(
      str_detect(relationship, "spouse") ~ "Spouse",
      str_detect(relationship, "partner") ~ "Partner",
      str_detect(relationship, "Roommate") ~ "Roommate",
      str_detect(
        relationship,
        "Biological|Adopted|Foster|Stepson|Stepdaughter"
      ) ~ "Child",
      str_detect(relationship, "Father or mother") ~ "Parent",
      str_detect(relationship, "Brother or sister") ~ "Sibling",
      str_detect(relationship, "in-law") ~ "In-law",
      .default = relationship
    )
  ) |>
  mutate(
    relationship = case_when(
      relationship == "Child" & age > 18 ~ "Adult child",
      relationship == "Grandchild" & age > 18 ~ "Adult grandchild",
      .default = relationship
    )
  ) |>
  mutate(
    edu = case_when(
      #is.na(edu) ~ "Not reported",
      str_detect(edu, "less than 3|No schooling") ~ "None",
      str_detect(edu, "preschool") ~ "Pre-K",
      str_detect(
        edu,
        paste("Grade", 1:5, collapse = "|")
      ) ~ "Elementary school",
      str_detect(edu, paste("Grade", 6:8, collapse = "|")) ~ "Middle school",
      str_detect(edu, paste("Grade", 9:12, collapse = "|")) ~ "High school",
      str_detect(edu, "12th grade") ~ "High school",
      str_detect(edu, "high|GED") ~ "High school diploma or GED",
      str_detect(edu, "Some college|no degree") ~ "Some college",
      str_detect(
        edu,
        "Professional|Doctorate"
      ) ~ "Professional or doctorate degree",
      .default = edu
    )
  ) |>
  mutate(
    tenure_detail = fct_case_when(
      tenure ==
        "Owned with mortgage or loan (include home equity loans)" ~ "Homeowner",
      tenure == "Owned free and clear" ~ "Homeowner (no mortgage)",
      tenure == "Rented" ~ "Renter",
      tenure == "Occupied without payment of rent" ~ "Renter (no rent)"
    ),
    .after = tenure
  ) |>
  mutate(
    tenure = fct_case_when(
      str_detect(tenure, "Owned") ~ "Homeowner",
      str_detect(tenure, "(?i)rent") ~ "Renter"
    )
  ) |>
  mutate(
    str_type = fct_case_when(
      str_type == "One-family house detached" ~ "Single-family detached",
      str_type == "One-family house attached" ~ "Townhome",
      str_detect(
        str_type,
        "2 Apartments|3-4 Apartments|5-9 Apartments"
      ) ~ "Small multifamily (2-9 units)",
      str_type == "10-19 Apartments" ~ "Medium multifamily (10-19 units)",
      str_detect(
        str_type,
        "20-49 Apartments|50 or more apartments"
      ) ~ "Large multifamily (20+ units)",
      TRUE ~ "Mobile home"
    )
  ) |>
  mutate(
    str_yrblt = case_when(
      str_detect(str_yrblt, "202") ~ "2020 or after",
      str_detect(str_yrblt, "195|196") ~ "1950-1969",
      str_detect(str_yrblt, "193|194") ~ "1949 or before",
      .default = str_yrblt
    ),
    str_yrblt = fct_relevel(str_yrblt, sort)
  ) |>
  mutate(
    moved = fct_case_when(
      moved == "12 months or less" ~ "Within last year",
      moved == "13 to 23 months" ~ "1-4 years ago",
      moved == "2 to 4 years" ~ "1-4 years ago",
      moved == "5 to 9 years" ~ "5-9 years ago",
      moved == "10 to 19 years" ~ "10-19 years ago",
      moved == "20 to 29 years" ~ "20-29 years ago",
      moved == "30 years or more" ~ "30+ years ago"
    )
  ) |>
  mutate(
    workers = fct_case_when(
      workers == "No workers" ~ "None",
      workers == "1 worker" ~ "1",
      workers == "2 workers" ~ "2",
      workers == "3 or more workers" ~ "3 or more",
      TRUE ~ NA
    )
  ) |>
  mutate(
    emp_status = case_when(
      str_detect(emp_status, "Civilian") ~ "Employed",
      str_detect(emp_status, "Armed") ~ "Military",
      str_detect(emp_status, "Unemployed") ~ "Unemployed",
      str_detect(emp_status, "Not in") ~ "Not in labor force",
      .default = NA
    )
  ) |>
  mutate(
    last_work = fct_case_when(
      last_work == "1" ~ "Within year",
      last_work == "2" ~ "1-5 years ago",
      last_work == "3" ~ "Over 5 years ago or never",
      last_work == "b" ~ NA
    )
  ) |>
  mutate(
    wkr_class = case_when(
      str_detect(wkr_class, "last worked") ~ "Non-earner",
      str_detect(wkr_class, "without pay") ~ "Non-earner",
      str_detect(wkr_class, "private for-profit") ~ "For-profit",
      str_detect(wkr_class, "not-for-profit") ~ "Non-profit",
      str_detect(wkr_class, "Local|State") ~ "Local or state government",
      str_detect(wkr_class, "Federal") ~ "Federal government",
      str_detect(wkr_class, "Self-employed") ~ "Self-employed"
    )
  ) |>
  mutate(
    jtw = fct_case_when(
      jtw == "01" ~ "Car or van",
      jtw %in% c("02", "03", "04", "05") ~ "Public transit",
      jtw %in% c("06", "07", "08", "09", "10", "12") ~ "Other",
      jtw == "11" ~ "Work from home",
      jtw == "bb" ~ NA
    )
  ) |>
  mutate(
    across(c(naics, soc), ~ replace(., . %in% c("N", "00000N"), NA))
  ) |>
  mutate(
    across(
      fam_income:inc_other,
      ~ replace(., . %in% c(-1, -10001), NA)
    )
  ) |>
  select(-ethnicity)


## 11. Save final PUMS data -------------------------------

# Join with replicate weights
pums_rva <- rva_pums_simple |>
  left_join(pums_wgt)

# Save RDS file
write_rds(pums_rva, "data/pums_rva.rds")
# read_rds("data/pums_rva.rds")

## EXAMPLE CROSSTAB ---------------------------------------

rent <- pums_rva |>
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
    )
  ) |>
  filter(
    SPORDER == 1,
    tenure == "Renter"
  ) |>
  to_survey(type = "housing", design = "rep_weights") |>
  group_by(ami_band, county) |>
  summarise(
    median = survey_median(cost_rent, vartype = "cv")
  )
