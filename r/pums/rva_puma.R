## Setup --------------------------------------------------

library(tidyverse)
library(tigris)
library(sf)
library(mapview)

# Define RVA region
rva_2010 <- c(
  "51215",
  "51224",
  "51225",
  "51235",
  "04101",
  "04102",
  "04103"
) # 2010 PUMA codes
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

# State FIPS codes for Virginia
va <- "51"


## Download geographies -----------------------------------

# 2010 PUMA boundaries
puma_2010 <- pumas(cb = TRUE, year = 2019)

# 2020 PUMA boundaries
puma_2020 <- pumas(cb = TRUE, year = 2020)

# Virginia locality boundaries
va_local <- counties(state = "VA", cb = TRUE, year = 2020)


## Save data for mapping ----------------------------------

puma_2020 |>
  filter(STATEFP20 == va) |>
  select(4, 5) |>
  st_transform("EPSG:4326") |>
  write_rds("data/puma_va.rds")

va_local |>
  select(5, 7) |>
  st_transform("EPSG:4326") |>
  write_rds("data/local_va.rds")


## Get PUMAs for PlamRVA region ------------------------------

# Select PUMAs in PlanRVA.
rva <- puma_2020 |>
  subset(PUMACE20 %in% rva_2020)

# View GWRC PUMAs and localities
mapview(va_local) + mapview(rva)


## Make PUMA lookup file for place-of-work ----------------

powpuma_lookup <- read_csv("data-out/puma_pow.csv") |>
  mutate(version = str_sub(version, -2)) |>
  mutate(pow_geoid = paste0(version, "-", st, pow_puma)) |>
  select(1:2, 5:6, 8, 7) |>
  distinct()

# Save file
write_rds(powpuma_lookup, "data/powpuma_lookup.rds")
