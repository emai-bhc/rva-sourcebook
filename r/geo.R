# geo.R ----
# What:   County/independent-city boundaries for the 17-locality Richmond
#         region (`rr` in _common.R), for mapgl choropleths across the site.
# Source: tigris::counties(), cartographic boundary (500k), transformed to
#         WGS84 for mapgl/GeoJSON.
# Output: data/geo.rds        (sf object, one row per rr locality)
#         data-out/geo.csv    (attributes only — geometry dropped, CSV isn't
#                              a sane spatial format; use the .rds for mapping)

## 1. Setup ----
library(tidyverse)
library(tigris)
library(sf)
library(janitor)
source("_common.R") # rr, export_csv()

options(tigris_use_cache = TRUE)
sf::sf_use_s2(TRUE)

dir.create("data", showWarnings = FALSE, recursive = TRUE)

## 2. Pull county/independent-city boundaries ----
# cb = TRUE (cartographic boundary, 500k resolution) — plenty of detail for a
# regional-scale map, far smaller than full TIGER/Line. Virginia's independent
# cities are county-equivalents, so a single counties() pull covers all 17.
message("Pulling VA county/independent-city boundaries...")
va_counties <- counties(state = "VA", cb = TRUE, year = 2023) |>
  clean_names()

geo <- va_counties |>
  filter(geoid %in% rr) |>
  mutate(locality = names(rr)[match(geoid, rr)]) |>
  select(geoid, name, locality, aland, awater, geometry) |>
  st_transform(4326)

message("Pulled ", nrow(geo), " of ", length(rr), " expected rr localities")

## 3. Write output ----
write_rds(geo, "data/geo.rds")
export_csv(st_drop_geometry(geo), "geo") # -> data-out/geo.csv, attributes only
message("Wrote data/geo.rds + data-out/geo.csv")

## 4. Validate ----
g <- read_rds("data/geo.rds")

stopifnot(
  inherits(g, "sf"),
  nrow(g) == length(rr), # every rr locality present, no dupes
  all(rr %in% g$geoid),
  !any(st_is_empty(g)), # no empty geometries
  st_crs(g)$epsg == 4326
)

message("geo.R validation passed.")
message("  Localities: ", nrow(g))
