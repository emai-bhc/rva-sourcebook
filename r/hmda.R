library(tidyverse)
library(httr)
library(jsonlite)
library(httr)
library(glue)
library(arrow)

# Data collection

#We're using `dplyr::cols_only()` to create a column specification that will only
#return the 35 columns we want, and will format them correctly (allowing us to appropriately
# merge the datasets together over time)

col_spec <- cols_only(
  "activity_year" = col_double(),
  "lei" = col_character(),
  "county_code" = col_character(),
  "census_tract" = col_character(),
  "derived_loan_product_type" = col_character(),
  "derived_dwelling_category" = col_character(),
  "derived_ethnicity" = col_character(),
  "derived_race" = col_character(),
  "applicant_race-1" = col_integer(),
  "applicant_race-2" = col_integer(),
  "applicant_race-3" = col_integer(),
  "applicant_race-4" = col_integer(),
  "applicant_race-5" = col_integer(),
  "co-applicant_race-1" = col_integer(),
  "co-applicant_race-2" = col_integer(),
  "co-applicant_race-3" = col_integer(),
  "co-applicant_race-4" = col_integer(),
  "co-applicant_race-5" = col_integer(),
  "applicant_ethnicity-1" = col_integer(),
  "applicant_ethnicity-2" = col_integer(),
  "applicant_ethnicity-3" = col_integer(),
  "applicant_ethnicity-4" = col_integer(),
  "applicant_ethnicity-5" = col_integer(),
  "co-applicant_ethnicity-1" = col_integer(),
  "co-applicant_ethnicity-2" = col_integer(),
  "co-applicant_ethnicity-3" = col_integer(),
  "co-applicant_ethnicity-4" = col_integer(),
  "co-applicant_ethnicity-5" = col_integer(),
  "derived_sex" = col_character(),
  "action_taken" = col_integer(),
  "purchaser_type" = col_integer(),
  "loan_type" = col_integer(),
  "loan_purpose" = col_integer(),
  "reverse_mortgage" = col_integer(),
  "loan_amount" = col_character(),
  "loan_to_value_ratio" = col_character(),
  "interest_rate" = col_character(),
  "total_loan_costs" = col_character(),
  "loan_term" = col_character(),
  "property_value" = col_character(),
  "construction_method" = col_integer(),
  "occupancy_type" = col_integer(),
  "manufactured_home_secured_property_type" = col_integer(),
  "manufactured_home_land_property_interest" = col_integer(),
  "total_units" = col_character(),
  "applicant_age" = col_character(),
  "income" = col_double(),
  "debt_to_income_ratio" = col_character(),
  "denial_reason-1" = col_integer(),
  "denial_reason-2" = col_integer(),
  "denial_reason-3" = col_integer(),
  "denial_reason-4" = col_integer(),
  "tract_minority_population_percent" = col_double(),
  "ffiec_msa_md_median_family_income" = col_double(),
  "tract_to_msa_income_percentage" = col_double(),
  "tract_owner_occupied_units" = col_double()
)

# HMDA data are available via API in two forms: 1) an aggregated JSON API, and 2) a bulk API
# that returns the raw data in CSV format.  We're more interested in the raw data here in CSV
#  format which we could use to do custom aggregations, so we'll pull that down for 2018 through
# 2022.
#
#  A few notes about the process below:
# - We use `map_dfr()` to iterate through the three years then return the result
# as a combined dataset.  As we are using the formula notation below (`~`), `.x` takes
# on the value of each year on each run of the iterator.
# - The `GET()` function from httr is used to make a GET request to the HMDA API.  It requires
# a base URL to request along with optional queries.
# - We convert the HTTP request result to text then read in the CSV;
# we pass our column specification defined above to `col_types` to align each dataset
# correctly.
#
hmda_pull <- map_dfr(
  2018:2025,
  ~ {
    GET(
      "https://ffiec.cfpb.gov/v2/data-browser-api/view/csv",
      query = list(
        states = "VA",
        years = .x
      ),
      progress()
    ) %>%
      content(as = "text") %>%
      read_csv(col_types = col_spec)
  }
)

write_parquet(hmda_pull, "data/hmda_va.parquet")


# Data prep

hmda_pull <- read_parquet("data/hmda_va.parquet")

hmda_clean <- hmda_pull %>%
  subset(county_code %in% rr) |>
  select(
    activity_year,
    lei,
    county_code,
    census_tract,
    loan_product = derived_loan_product_type,
    dwelling_category = derived_dwelling_category,
    ethnicity = derived_ethnicity,
    race = derived_race,
    sex = derived_sex,
    action_taken,
    purchaser_type,
    loan_purpose,
    loan_amount,
    loan_to_value_ratio,
    interest_rate,
    property_value,
    construction_method,
    occupancy_type,
    income,
    debt_to_income_ratio,
    applicant_age,
    `denial_reason-1`,
    `denial_reason-2`,
    `denial_reason-3`,
    `denial_reason-4`
  ) %>%
  mutate(
    action_taken = case_when(
      action_taken == 1 ~ "Loan originated",
      action_taken == 2 ~ "Application approved but not accepted",
      action_taken == 3 ~ "Application denied",
      action_taken == 4 ~ "Application withdrawn by applicant",
      action_taken == 5 ~ "File closed for incompleteness",
      action_taken == 6 ~ "Purchased loan",
      action_taken == 7 ~ "Preapproval request denied",
      action_taken == 8 ~ "Preapproval request approved but not accepted"
    )
  ) %>%
  mutate(
    purchaser_type = case_when(
      purchaser_type == 0 ~ "Not applicable",
      purchaser_type == 1 ~ "Fannie Mae",
      purchaser_type == 2 ~ "Ginnie Mae",
      purchaser_type == 3 ~ "Freddie Mac",
      purchaser_type == 4 ~ "Farmer Mac",
      purchaser_type == 5 ~ "Private securitizer",
      purchaser_type ==
        6 ~ "Commercial bank, savings bank, or savings association",
      purchaser_type ==
        71 ~ "Credit union, mortgage company, or finance company",
      purchaser_type == 72 ~ "Life insurance company",
      purchaser_type == 8 ~ "Affiliate institution",
      purchaser_type == 9 ~ "Other type of purchaser"
    )
  ) %>%
  mutate(
    loan_purpose = case_when(
      loan_purpose == 1 ~ "Home purchase",
      loan_purpose == 2 ~ "Home improvement",
      loan_purpose == 31 ~ "Refinancing",
      loan_purpose == 32 ~ "Cash-out refinancing",
      loan_purpose == 4 ~ "Other purpose",
      loan_purpose == 5 ~ "Not applicable"
    )
  ) %>%
  mutate(
    race_ethnicity = case_when(
      ethnicity == "Hispanic or Latino" &
        race == "Joint" ~ "White Co-Applicant",
      race == "American Indian or Alaska Native" &
        ethnicity == "Not Hispanic or Latino" ~ "Other Minority",
      race == "Asian" & ethnicity == "Not Hispanic or Latino" ~ "Asian",
      race == "Black or African American" &
        ethnicity == "Not Hispanic or Latino" ~ "Black",
      race == "Native Hawaiian or Other Pacific Islander" &
        ethnicity == "Not Hispanic or Latino" ~ "Other Minority",
      race == "White" &
        ethnicity == "Not Hispanic or Latino" ~ "White, non-Hispanic",
      race == "2 or more minority races" &
        ethnicity == "Not Hispanic or Latino" ~ "Other Minority",
      race == "Race Not Available" &
        ethnicity == "Ethnicity Not Available" ~ "Incomplete/No Data",
      race == "Joint" &
        ethnicity == "Not Hispanic or Latino" ~ "White Co-Applicant",
      ethnicity == "Free Form Text Only" ~ "Hispanic or Latino",
      ethnicity == "Not Hispanic or Latino" &
        race == "Race Not Available" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "White" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "American Indian or Alaska Native" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "Asian" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "Black or African American" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race ==
          "Native Hawaiian or Other Pacific Islander" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "2 or more minority races" ~ "Incomplete/No Data",
      ethnicity == "Not Hispanic or Latino" &
        race == "Free Form Text Only" ~ "Incomplete/No Data",
      ethnicity == "Free Form Text Only" &
        race == "Race Not Available" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "Free Form Text Only" ~ "Incomplete/No Data",
      ethnicity == "Ethnicity Not Available" &
        race == "Joint" ~ "White Co-Applicant",
      ethnicity == "Joint" & race == "Joint" ~ "White Co-Applicant",
      TRUE ~ "Hispanic or Latino"
    )
  ) |>
  mutate(
    occupancy_type = case_when(
      occupancy_type == 1 ~ "Principal residence",
      occupancy_type == 2 ~ "Second residence",
      occupancy_type == 3 ~ "Investment property"
    )
  ) |>
  mutate(
    construction_method = case_when(
      construction_method == 1 ~ "Site Built",
      TRUE ~ "Manufactured Home"
    )
  )

all(is.na(hmda_clean$`co-applicant_ethnicity-5`))
all(is.na(hmda_clean$`co-applicant_ethnicity-4`))
all(is.na(hmda_clean$`applicant_ethnicity-5`))
all(is.na(hmda_clean$`applicant_ethnicity-4`))
all(is.na(hmda_clean$`applicant_race-5`))


write_parquet(hmda_clean, "data/hmda_data.parquet")
