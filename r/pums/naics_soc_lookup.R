## Setup --------------------------------------------------

library(tidyverse)
library(tidycensus)

## Get NAICSP and SOCP variable codes and labels ---------

pums_vars_naics <- pums_variables |>
  filter(year == 2022, survey == "acs5") |>
  filter(
    var_code == "NAICSP"
  ) |>
  select(3, 7, val = val_min, 9)

pums_vars_soc <- pums_variables |>
  filter(year == 2022, survey == "acs5") |>
  filter(
    var_code == "SOCP"
  ) |>
  select(3, 7, val = val_min, 9)

## NAICS code groupings -----------------------------------

naics_recode <- pums_vars_naics |>
  mutate(
    naics_group = case_when(
      str_detect(val, "^42|^44|^45|4MS") ~ "Retail and Wholesale",
      str_detect(val, "^31|^32|^33|3MS") ~ "Manufacturing",
      str_detect(val, "^54|^55|^56") ~ "Professional Services",
      str_detect(val, "^62") ~ "Healthcare and Social Assistance",
      str_detect(val, "^61") ~ "Education",
      str_detect(val, "^52|^53") ~ "Finance and Insurance",
      str_detect(val, "^51") ~ "Information and Communication",
      str_detect(val, "^48|^49") ~ "Transportation and Warehousing",
      str_detect(val, "^92") ~ "Public Administration and Military",
      str_detect(val, "^71|^72") ~ "Entertainment and Accommodation",
      str_detect(val, "^81") ~ "Other Services",
      str_detect(
        val,
        "^11|^21|^22|23"
      ) ~ "Construction, Utilities, and Natural Resources",
      .default = NA
    )
  )

write_rds(naics_recode, "data/naics_recode.rds")


## SOC code regroupings -----------------------------------

soc_recode <- pums_vars_soc |>
  mutate(
    soc_group = case_when(
      str_detect(val_label, "^MGR-") ~ "Leadership and Management",
      str_detect(val_label, "^BUS-|^FIN-") ~ "Analysis, Strategy, and Planning",
      str_detect(
        val_label,
        "^CMM-"
      ) ~ "Information Technology and Software Development",
      str_detect(val_label, "^ENG-") ~ "Engineering and Technical Design",
      str_detect(val_label, "^SCI-") ~ "Scientific Research and Development",
      str_detect(val_label, "^EDU-") ~ "Education and Training",
      str_detect(val_label, "^MED-|^HLS-") ~ "Healthcare and Medical Services",
      str_detect(
        val_label,
        "^PRT-|^FIR-"
      ) ~ "Protective and Emergency Services",
      str_detect(val_label, "^EAT-|^HOS-") ~ "Food and Hospitality Services",
      str_detect(
        val_label,
        "^CLN-|^RPR-"
      ) ~ "Maintenance, Cleaning, and Repair",
      str_detect(val_label, "^PRS-") ~ "Personal Care and Services",
      str_detect(
        val_label,
        "^SAL-|^MKT-"
      ) ~ "Sales, Marketing, and Customer Service",
      str_detect(
        val_label,
        "^OFF-|^ADM-"
      ) ~ "Administrative and Clerical Support",
      str_detect(
        val_label,
        "^FIN-|^ACC-"
      ) ~ "Financial Services and Accounting",
      str_detect(val_label, "^ART-|^ENT-") ~ "Creative and Artistic Production",
      str_detect(val_label, "^PRD-|^MFG-") ~ "Manufacturing and Production",
      str_detect(val_label, "^TRN-|^LOG-") ~ "Transportation and Logistics",
      str_detect(
        val_label,
        "^CON-|^TRD-|^EXT-"
      ) ~ "Construction and Skilled Trades",
      str_detect(
        val_label,
        "^AGR-|^FFF-|^ENV-"
      ) ~ "Agriculture and Environmental Services",
      str_detect(val_label, "^LGL-") ~ "Legal and Compliance Services",
      str_detect(val_label, "^HRM-") ~ "Human Resources and Talent Management",
      str_detect(val_label, "^CMS-|^SOC-") ~ "Social and Community Services",
      str_detect(val_label, "^COM-|^MED-") ~ "Media and Communications",
      str_detect(
        val_label,
        "^INS-|^OPR-"
      ) ~ "Installation and Equipment Operation",
      str_detect(val_label, "^MIL-") ~ "Military and Defense Operations",
      .default = NA
    )
  )

write_rds(soc_recode, "data/soc_recode.rds")


## GO Virginia Region 6 Priority Industry Clusters --------

# Distribution/Logistics
#
# NAICS 42383 Industrial Machinery and Equipment Merchant Wholesalers ==> 4238 Machinery, equipment, and supplies merchant wholesalers
#   Includes: 42381 Construction and Mining (except Oil Well) Machinery and Equipment Merchant Wholesalers
#             42382 Farm and Garden Machinery and Equipment Merchant Wholesalers
#             42384 Industrial Supplies Merchant Wholesalers
#             42385 Service Establishment Equipment and Supplies Merchant Wholesalers
#             42386 Transportation Equipment and Supplies (except Motor Vehicle) Merchant Wholesalers
# NAICS 42512 Wholesale Trade Agents and Brokers ==> 4251 Wholesale electronic markets and agents and brokers
#   Includes: 42511 Business to Business Electronic Markets
# NAICS 48411 General Freight Trucking, Local ==> 484 Truck transportation
# NAICS 484121 General Freight Trucking, Long-Distance, Truckload ==> 484 Truck transportation
# NAICS 48422 Specialized Freight (except Used Goods) Trucking, Local ==> 484 Truck transportation
#   Includes: 484122 General Freight Trucking, Long-Distance, Less Than Truckload
#             48421 Used Household and Office Goods Moving
#             48423	Specialized Freight (except Used Goods) Trucking, Long-Distance
# NAICS 49311 General Warehousing and Storage ==> 493 Warehousing and storage
#   Includes: 49312	Refrigerated Warehousing and Storage
#             49313	Farm Product Warehousing and Storage
#             49319	Other Warehousing and Storage

gova6_dist <- tibble(
  priority_cluster = "Distribution/Logistics",
  naics = c("4238", "4251", "484", "493")
)

# Forestry/Wood Products
#
# NAICS 111421 Nursery and Tree Production ==> 111 Crop production
#   Includes: 1111 Oilseed and Grain Farming
#             1112 Vegetable and Melon Farming
#             1113 Fruit and Tree Nut Farming
#             11141	Food Crops Grown Under Cover
#             111422 Floriculture Production
#             1119 Other Crop Farming
# NAICS 11331 Logging ==> 1133 Logging
# NAICS 321113 Sawmills ==> 3211 Sawmills and wood preservation
#   Includes: 321114 Wood Preservation
# NAICS 322121 Paper (except Newsprint) Mills ==> 3221 Pulp, paper, and paperboard mills
#   Includes: 32211	Pulp Mills
#             322122 Newsprint Mills
#             32213	Paperboard Mills

gova6_forest <- tibble(
  priority_cluster = "Forestry/Wood Products",
  naics = c("111", "1133", "3211", "3221")
)

# Manufacturing
#
# NAICS 31-33 Manufacturing ==> Starts with 31, 32, or 33

mfg_vars <- pums_vars_naics |>
  filter(str_starts(val_label, "MFG")) |>
  pull(2)

gova6_mfg <- tibble(
  priority_cluster = "Manufacturing",
  naics = mfg_vars
)

# Professional, Technical, and Scientific Services
#
# NAICS 54133 Engineering Services ==> 5413 Architectural, engineering, and related services
#   Includes: 54131	Architectural Services
#             54132	Landscape Architectural Services
#             54134	Drafting Services
#             54135	Building Inspection Services
#             54136	Geophysical Surveying and Mapping Services
#             54137	Surveying and Mapping (except Geophysical) Services
#             54138	Testing Laboratories
# NAICS 541512 Computer Systems Design Services ==> 5415 Computer systems design and related services
# NAICS 541519 Other Computer Related Services ==> 5415 Computer systems design and related services
#   Includes: 541511	Custom Computer Programming Services
#             541513	Computer Facilities Management Services

gova6_srv <- tibble(
  priority_cluster = "Professional, Technical, and Scientific Services",
  naics = c("5413", "5415")
)

# Information/Data Centers
#
# NAICS 51821 Data Processing, Hosting, and Related Services ==> 5182 Data processing, hosting, and related services

gova6_info <- tibble(
  priority_cluster = "Information/Data Centers",
  naics = "5182"
)

# Combine all priority clusters into lookup table

gova6_lookup <- bind_rows(
  gova6_dist,
  gova6_forest,
  gova6_mfg,
  gova6_srv,
  gova6_info
)
