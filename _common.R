# _common.R — global setup sourced by every chapter and (optionally) by r/ scripts.
# Palettes, geography constants, caption helpers, reliability tiering, CSV export helper.
# One-way data flow: r/ scripts write data/*.rds; chapters read_rds() only, never call APIs.

# ---- Global knitr chunk options -------------------------------------------

knitr::opts_chunk$set(
  echo = FALSE,
  warning = FALSE,
  error = FALSE,
  message = FALSE,
  fig.show = "hold",
  fig.asp = 0.618,
  fig.align = "left"
)

# ---- Core packages --------------------------------------------------------

library(tidyverse)
library(scales)
library(kableExtra)
library(formattable)
library(ggtext)


# ---- Geography constants --------------------------------------------------
# County/city GEOIDs are standard FIPS (confirmed against the SOH deck's working code).
# Place + PUMA codes were resolved via tigris in Task 1 — never hardcoded from memory.

# Region: 17 localities in the Richmond Metro Region.

rr <- c(
  hanover = "51085",
  richmond = "51760",
  goochland = "51075",
  powhatan = "51145",
  henrico = "51087",
  new_kent = "51127",
  charles_city = "51036",
  chesterfield = "51041",
  petersburg = "51730",
  hopewell = "51670",
  cheights = "51570",
  amelia = '51007',
  dinwiddie = "51053",
  kingqueen = "51097",
  kingwilliam = "51101",
  princegeorge = "51149",
  sussex = "51183"
)

# Primary localities: the 3 core localities wherein BHC operates.
bhc <- c(
  richmond = "51760",
  henrico = "51087",
  chesterfield = "51041"
)

# Secondary localities: Localities wherein BHC would like to expand in the near future.
secondary <- c(
  hanover = "51085",
  goochland = "51075",
  new_kent = "51127",
  powhatan = "51145"
)

# Ashland is a town (Census place, summary level 160) inside Hanover County.
# ACS scripts keep place-level (sumlev 160) pulls for Ashland.
ashland <- c(ashland = "5103368")

virginia <- "51"

# Regions: for comparative analysis

regions <- c(
  cville = "16820",
  rva = "40060",
  hrds = "47260",
  dc = "47900"
)


# PUMS geographies (2020-vintage PUMAs, for 2020-2024 ACS PUMS).
# Core-3 is the regional PUMS default (EXECUTION-PLAN §7): Chesterfield, Henrico, and
# Richmond city each tile cleanly into whole PUMAs. Hanover cannot be isolated — it is
# split across two multi-county PUMAs (08501 east, 14501 west) — so it is excluded from
# regional PUMS estimates and only enters via the county-level ACS tables.
puma_core3 <- c(
  "04101",
  "04102",
  "04103", # Chesterfield County (E / Central / W)
  "08701",
  "08702", # Henrico County (S&E / W)
  "76001",
  "76002" # Richmond city (N&W / S&E)
)

# Full-region PUMA set: core-3 plus the two mixed outer PUMAs. Use only for region-wide
# totals where the extra counties are acceptable; note 08501 also includes King William.
puma_region <- c(
  puma_core3,
  "08501", # King William, New Kent, Charles City & Eastern Hanover Counties
  "14501" # Goochland, Powhatan & Western Hanover Counties
)

# PUMA -> locality label lookup for the clean-tiling core-3 (recode in PUMS prep).
puma_locality <- c(
  "04101" = "Chesterfield County",
  "04102" = "Chesterfield County",
  "04103" = "Chesterfield County",
  "08701" = "Henrico County",
  "08702" = "Henrico County",
  "76001" = "Richmond city",
  "76002" = "Richmond city"
)

# ---- Caption helpers ------------------------------------------------------
# Bold-markdown source lines for chart/table captions. Vintages default to this project's.

acs_cap <- function(table, year = "2020-2024") {
  paste0(
    "**Source:** U.S. Census Bureau, ",
    year,
    " American Community Survey 5-year estimates, Table ",
    table,
    "."
  )
}

pums_cap <- function(year = "2020-2024") {
  paste0(
    "**Source:** U.S. Census Bureau, ",
    year,
    " American Community Survey 5-year Public Use Microdata Sample (PUMS)."
  )
}

chas_cap <- function(table, year = "2018-2022") {
  paste0(
    "**Source:** HUD Comprehensive Housing Affordability Strategy (CHAS), ",
    year,
    " estimates, Table ",
    table,
    "."
  )
}

dec_cap <- function(years = "2000-2020") {
  paste0("**Source:** U.S. Census Bureau, Decennial Census, ", years, ".")
}

pep_cap <- function(vintage = 2025) {
  paste0(
    "**Source:** U.S. Census Bureau, Population Estimates Program, Vintage ",
    vintage,
    "."
  )
}

wc_cap <- function(release = 2025) {
  paste0(
    "**Source:** University of Virginia Weldon Cooper Center for Public Service, ",
    "Virginia Population Projections, ",
    release,
    " release."
  )
}

bps_cap <- function(years = "2000-2025") {
  paste0(
    "**Source:** U.S. Census Bureau, Building Permits Survey, ",
    years,
    " annual."
  )
}

mls_cap <- function(year_range = NULL) {
  base <- "**Source:** CVR MLS residential sales and listings data"
  if (!is.null(year_range)) {
    paste0(base, ", ", year_range, ".")
  } else {
    paste0(base, ".")
  }
}

costar_cap <- function() {
  "**Source:** CoStar multifamily market data, quarterly."
}

fmr_cap <- function(year = "FY2026") {
  paste0("**Source:** HUD Fair Market Rents and Small Area FMRs, ", year, ".")
}

ami_cap <- function(year = "FY2026") {
  paste0(
    "**Source:** HUD Section 8 Income Limits, ",
    year,
    "; 100/120% AMI derived from published MFI."
  )
}

nhpd_cap <- function() {
  "**Source:** National Housing Preservation Database (NHPD)."
}

# Subsidized housing / rental assistance sources (assistance.R consolidates these).
posh_cap <- function() {
  paste0(
    "**Source:** HUD Picture of Subsidized Households and Housing Choice Voucher ",
    "administrative data."
  )
}

lihtc_cap <- function() {
  "**Source:** HUD Low-Income Housing Tax Credit (LIHTC) database."
}

# Wage affordability (OEWS only this cycle; QCEW omitted — EXECUTION-PLAN §7).
oews_cap <- function(year = 2024) {
  paste0(
    "**Source:** U.S. Bureau of Labor Statistics, Occupational Employment and Wage ",
    "Statistics (OEWS), ",
    year,
    ", Richmond MSA."
  )
}

pit_cap <- function() {
  paste0(
    "**Source:** Greater Richmond Continuum of Care Point-in-Time Count ",
    "(single-night counts)."
  )
}

eviction_cap <- function() {
  "**Source:** Eviction filing records, general district courts, monthly."
}

vdoe_cap <- function() {
  paste0(
    "**Source:** Virginia Department of Education, McKinney-Vento homeless student ",
    "counts, by school division."
  )
}

cpi_cap <- function() {
  "Inflation-adjusted to the latest period using BLS CPI-U via FRED."
}

pmms_cap <- function() {
  "**Source:** Freddie Mac Primary Mortgage Market Survey (PMMS), 30-year fixed rate, via FRED."
}

# ---- Reliability tiering --------------------------------------------------
# High/Medium/Low from a 0-100 CV column (thresholds 15/30). The .rds frames store `cv`
# on a 0-100 scale; hdatools::add_reliability() expects a *_cv column on a 0-1 scale, so
# this thin wrapper avoids mislabeling small-geography (secondary-locality/Ashland) cells.
flag_reliability <- function(df, cv_col = cv) {
  df |>
    mutate(
      reliability = case_when(
        {{ cv_col }} <= 15 ~ "High",
        {{ cv_col }} <= 30 ~ "Medium",
        {{ cv_col }} > 30 ~ "Low",
        TRUE ~ NA_character_
      )
    )
}

# ---- Utilities ------------------------------------------------------------

# Apply str_wrap() to the levels of an (ordered) factor — for wrapping axis labels.
fct_wrap <- function(f, width) fct_relabel(f, ~ str_wrap(., width = width))

# CSV export helper (EXECUTION-PLAN §4, §5). Write a tidy CSV to data-out/ alongside every
# write_rds(), so processed datasets are Azure/PowerBI-ready. Commit policy is enforced by
# .gitignore via filename, NOT here: name public-source exports plainly (e.g. "acs_tenure");
# name MLS/CoStar-derived exports with an "mls_"/"costar_" prefix so .gitignore keeps them
# out of the public repo (delivered to PHA privately). Returns the path invisibly.
export_csv <- function(df, name) {
  dir.create("data-out", showWarnings = FALSE, recursive = TRUE)
  path <- file.path("data-out", paste0(name, ".csv"))
  readr::write_csv(df, path)
  invisible(path)
}

# ---- Plot rendering options ----------------------------------------------

if (knitr::is_html_output()) {
  knitr::opts_chunk$set(out.width = "100%")
} else {
  knitr::opts_chunk$set(dpi = 150)
}
