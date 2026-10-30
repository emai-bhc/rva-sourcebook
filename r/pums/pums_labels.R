## Create Dictionary and Function to Label PUMS Variables

# 1. Setup ------------------------------------------------

library(tidyverse)
library(tidycensus)

# Load list of chosen variables
pums_vars <- read_rds("data/pums_vars.rds")

# Load complete PUMS data dictionary
pums_vars_2024 <- pums_variables |>
  filter(year == 2024, survey == "acs5")

# Load raw PUMS dataset for testing
pums_raw <- read_rds("data/pums_raw.rds")


# 2. Filter dictionary to selected variables --------------

pums_vars_label <- pums_vars_2024 |>
  filter(
    var_code %in% pums_vars,
    data_type == "chr" # Don't need to relabel numeric variables
  ) |>
  select(3, 4, val = val_min, 9)

write_rds(pums_vars_label, "data/pums_labels.rds")


# 3. Create function to recode with labels ----------------

pums_recode <- function(survey_data, var_names) {
  recoded_data <- survey_data

  for (var_name in var_names) {
    recoded_data <- recoded_data %>%
      left_join(
        pums_vars_label %>%
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

# Test function
pums_test <- pums_raw |>
  filter(TEN != "b") |>
  pums_recode(c("TEN", "BLD", "FS"))
