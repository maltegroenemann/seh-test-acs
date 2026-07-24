################################################################################
### Testing Hypotheses from the ABM
### Download ACS Tract-Level Data via IPUMS NHGIS
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Four non-overlapping ACS 5-year windows, census tract level:
#   2005-2009 | 2010-2014 | 2015-2019 | 2020-2024
#
# Tables:
#   B01003  Total population
#   B03002  Hispanic or Latino by race  → pct_nhwhite, pct_nhblack, pct_hispanic
#   B15003  Educational attainment (25+) [2014–2024 only; not in 2009 ACS5a]
#   B19001  Household income brackets (16) → H^R income segregation (all HH)
#   B19001B Household income brackets × NH-Black householder → within-race H^R
#   B19001H Household income brackets × NH-White householder → within-race H^R
#   B19001I Household income brackets × Hispanic/Latino householder → within-race H^R
#   B19013  Median household income
#   B25002  Occupancy status             → vacancy rate
#   B25003  Tenure                       → pct_renter, H_tenure (tenure segregation)
#   B25003B Tenure × NH-Black householder → racial homeownership rates/gaps  [ACS5a]
#   B25003H Tenure × NH-White householder → racial homeownership rates/gaps  [ACS5a]
#   B25003I Tenure × Hispanic householder → racial homeownership rates/gaps  [ACS5a]
#   B25063  Gross rent (dollar brackets) → H^R rent segregation
#   B25064  Median gross rent
#   B25070  Gross rent as % of income    → rent burden
#   B25075  Home value (dollar brackets) → H^R home-value segregation
#   B25077  Median home value
#

## ── SETUP ────────────────────────────────────────────────────────────────────

library(ipumsr)

# Download with ipumsr requires an IPUMS API key: https://account.ipums.org/api_keys
# TODO set up API key and save the key to .Renviron.
# If not already done, run once interactively:

# set_ipums_api_key("your-key", save = TRUE)

data_dir <- "./data/ACS/"


## ── DOWNLOAD: TABULAR DATA ───────────────────────────────────────────────────

# variables from ACS5a table
acs_tables <- c(
  "B01003",   # total population
  "B03002",   # Hispanic/Latino by race (non-Hispanic white, non-Hispanic Black, Hispanic)
  "B15003",   # educational attainment [excluded from 2009 wave below; not in 2009 ACS5a]
  "B19001",   # household income brackets (16 brackets) → H^R income segregation (all HH)
  "B19013",   # median household income
  "B25002",   # occupancy status (occupied / vacant)
  "B25003",   # tenure (owner / renter)
  "B25003B",  # tenure × NH-Black householder → racial homeownership rates/gaps
  "B25003H",  # tenure × NH-White householder → racial homeownership rates/gaps
  "B25003I",  # tenure × Hispanic householder → racial homeownership rates/gaps
  "B25063",   # gross rent dollar brackets (cash rent only) → H^R rent segregation
  "B25064",   # median gross rent
  "B25070",   # gross rent as % of income
  "B25075",   # home value dollar brackets → H^R home-value segregation
  "B25077"    # median home value
)

# Race-specific income tables are in ACS5b (all other race-specific tables are in ACS5a)
race_tables <- c(
  "B19001B",  # household income × NH-Black householder → within-race H^R
  "B19001H",  # household income × NH-White householder → within-race H^R
  "B19001I"   # household income × Hispanic/Latino householder → within-race H^R
)

extract_tabular <- define_extract_agg(
  collection  = "nhgis",
  description = "ACS 5-year tract data 2009-2024 for test of housing market ABM (4 waves)",
  datasets = list(
    # B15003 (education) not available in 2005-2009 ACS5a; all other tables are
    ds_spec("2005_2009_ACS5a", data_tables = acs_tables[acs_tables != "B15003"], geog_levels = "tract"),
    ds_spec("2010_2014_ACS5a", data_tables = acs_tables, geog_levels = "tract"),
    ds_spec("2015_2019_ACS5a", data_tables = acs_tables, geog_levels = "tract"),
    ds_spec("2020_2024_ACS5a", data_tables = acs_tables, geog_levels = "tract"),
    # Race-specific income tables are in the ACS5b datasets
    ds_spec("2005_2009_ACS5b", data_tables = race_tables, geog_levels = "tract"),
    ds_spec("2010_2014_ACS5b", data_tables = race_tables, geog_levels = "tract"),
    ds_spec("2015_2019_ACS5b", data_tables = race_tables, geog_levels = "tract"),
    ds_spec("2020_2024_ACS5b", data_tables = race_tables, geog_levels = "tract")
  ),
  data_format = "csv_header"
)

submitted <- submit_extract(extract_tabular)
completed <- wait_for_extract(submitted, verbose = TRUE)
download_extract(completed, download_dir = data_dir, progress = TRUE, overwrite = TRUE)


## ── DOWNLOAD: SHAPEFILES ─────────────────────────────────────────────────────
# 2010-vintage boundaries: used for ACS waves 2005-2009, 2010-2014, 2015-2019
# 2020-vintage boundaries: used for ACS wave 2020-2024
# Shapefiles are downloaded separately as they are large and static.

extract_shp <- define_extract_agg(
  collection  = "nhgis",
  description = "Census tract shapefiles 2010 and 2020 for test of housing market ABM",
  shapefiles  = c("us_tract_2010_tl2010", "us_tract_2020_tl2020")
)

submitted <- submit_extract(extract_shp)
completed <- wait_for_extract(submitted, verbose = TRUE)
download_extract(completed, download_dir = data_dir, progress = TRUE, overwrite = TRUE)

remove(completed, submitted, extract_tabular, extract_shp)
