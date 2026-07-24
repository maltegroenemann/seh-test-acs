################################################################################
### Testing the Housing Market Model using ACS and PUMS Data
### Data Preparation: ACS Tract-Level Data via IPUMS NHGIS
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Source: IPUMS NHGIS extract nhgis0004_csv.zip (4 ACS 5-year waves, tract level)
#   NHGIS codes: 2005_2009_ACS5a, 2010_2014_ACS5a, 2015_2019_ACS5a, 2020_2024_ACS5a
#
# Tables:
#   B01003  Total population
#   B03002  Hispanic or Latino by race          → pct_nhwhite
#   B15003  Educational attainment (25+)        → pct_college  [2014–2024 only]
#   B19001  Household income brackets (16)      → H^R income segregation (all HH)
#   B19001B Household income brackets × NH-Black householder
#   B19001H Household income brackets × NH-White householder
#   B19001I Household income brackets × Hispanic/Latino householder
#   B19013  Median household income
#   B25002  Occupancy status                    → vacancy rate
#   B25003  Tenure                              → pct_renter
#   B25063  Gross rent dollar brackets          → H^R rent segregation
#   B25064  Median gross rent
#   B25070  Gross rent as % of income           → rent burden
#   B25075  Home value dollar brackets          → H^R home-value segregation
#   B25077  Median home value


## ── SETUP ────────────────────────────────────────────────────────────────────

# script requires ipumsr 0.10.0 but it is not available on the HPC via conda -> manual installation
if (!requireNamespace("ipumsr", quietly = TRUE) ||
    packageVersion("ipumsr") < "0.10.0") {
  install.packages("ipumsr", repos = "https://cloud.r-project.org")
}

library(ipumsr)
library(tigris)
library(nanoparquet)
library(dplyr)

data_dir    <- "./data/ACS/"
output_dir <- "./data/"
zip_path    <- list.files(data_dir, pattern = "nhgis.*csv.*\\.zip$", full.names = TRUE)
folder_name <- sub("_csv\\.zip$", "", basename(zip_path))


## ── 1. READ AND STANDARDISE ──────────────────────────────────────────────────

# Each year uses different NHGIS column prefixes. I rename to a common scheme
# immediately after reading so all downstream code is year-agnostic.
#
# Common names used throughout:
#   pop          B01003 E001
#   nhwhite      B03002 E003 (not Hispanic or Latino: white alone)
#   nhwhite_tot  B03002 E001 (denominator)
#   nhispanic    B03002 E012 (Hispanic or Latino)
#   inc_01–16    B19001 E002–E017 (income brackets, all households)
#   inc_tot      B19001 E001
#   inc_nhw_01–16  B19001H E002–E017 (income brackets, NH-White householders)
#   inc_nhw_tot    B19001H E001
#   inc_nhb_01–16  B19001B E002–E017 (income brackets, NH-Black householders)
#   inc_nhb_tot    B19001B E001
#   inc_his_01–16  B19001I E002–E017 (income brackets, Hispanic/Latino householders)
#   inc_his_tot    B19001I E001
#   median_inc   B19013 E001
#   units_tot    B25002 E001
#   units_vac    B25002 E003
#   own          B25003 E002
#   rent         B25003 E003
#   rent_01–21   B25063 E003–E023 [2009, 2014; top = "$2,000 or more"]
#   rent_01–24   B25063 E003–E026 [2019, 2024; top = "$3,500 or more"]
#                (trailing brackets NA-padded to 24 columns after bind_rows)
#   median_rent  B25064 E001
#   rb_tot       B25070 E001 (rent burden denominator)
#   rb_30_35     B25070 E007
#   rb_35_40     B25070 E008
#   rb_40_50     B25070 E009
#   rb_50plus    B25070 E010
#   val_01–24    B25075 E002–E025 [2009, 2014; top = "$1,000,000 or more"]
#   val_01–26    B25075 E002–E027 [2019, 2024; adds $1.5M–$2M and $2M+ brackets]
#                (trailing brackets NA-padded to 26 columns after bind_rows)
#   median_val   B25077 E001
#   edu_tot      B15003 E001  [NA in 2009]
#   edu_ba_plus  B15003 E022+E023+E024+E025  [NA in 2009]
#   own_nhw      B25003H E002 (owner-occupied, NH-White householder)
#   rent_nhw     B25003H E003 (renter-occupied, NH-White householder)
#   own_nhb      B25003B E002 (owner-occupied, NH-Black householder)
#   rent_nhb     B25003B E003 (renter-occupied, NH-Black householder)
#   own_his      B25003I E002 (owner-occupied, Hispanic householder)
#   rent_his     B25003I E003 (renter-occupied, Hispanic householder)

read_and_rename <- function(zip, ACS5a_file, ACS5b_file, year,
                            pop, nhwhite, nhwhite_tot, nhblack, nhispanic,
                            inc_prefix, inc_nhw_prefix, inc_nhb_prefix, inc_his_prefix,
                            median_inc,
                            units_tot, units_vac,
                            own, rent,
                            own_nhw, rent_nhw,       # B25003H E002, E003
                            own_nhb, rent_nhb,       # B25003B E002, E003
                            own_his, rent_his,       # B25003I E002, E003
                            rent_prefix, rent_E_end, # B25063: prefix + last E-number (incl. "no cash rent")
                            median_rent,
                            rb_tot, rb_07, rb_08, rb_09, rb_10,
                            val_prefix, val_E_end,   # B25075: prefix + last E-number
                            median_val,
                            edu_tot = NULL, edu_22 = NULL,
                            edu_23 = NULL, edu_24 = NULL, edu_25 = NULL) {
  # B25063 bracket counts differ by vintage:
  #   2009, 2014: E003–E023 (21 cash-rent brackets; rent_E_end = 24, i.e. E024 = "no cash rent")
  #   2019, 2024: E003–E026 (24 cash-rent brackets; rent_E_end = 27, i.e. E027 = "no cash rent")
  # B25075 bracket counts differ by vintage:
  #   2009, 2014: E002–E025 (24 value brackets; val_E_end = 25)
  #   2019, 2024: E002–E027 (26 value brackets; val_E_end = 27)

  d <- read_ipums_agg(zip, file_select = ACS5a_file)
  # 2020-vintage data (2020-2024 ACS) uses GEO_ID instead of GEOID
  if ("GEO_ID" %in% names(d) && !"GEOID" %in% names(d))
    d <- rename(d, GEOID = GEO_ID)

  # ACS5b file contains race-specific income tables (B19001H/B/I); join by GEOID.
  # Select only GEOID plus columns not already in d (NHGIS prefix codes are unique per dataset).
  d_b <- read_ipums_agg(zip, file_select = ACS5b_file)
  if ("GEO_ID" %in% names(d_b) && !"GEOID" %in% names(d_b))
    d_b <- rename(d_b, GEOID = GEO_ID)
  d <- left_join(d, select(d_b, GEOID, !any_of(names(d))), by = "GEOID")

  d$year <- year

  # income bracket columns: prefix + "E002" .. "E017"
  inc_cols <- paste0(inc_prefix, "E", sprintf("%03d", 2:17))
  names(inc_cols) <- paste0("inc_", sprintf("%02d", 1:16))

  # race-specific income bracket columns: B19001H/B/I E002–E017
  inc_nhw_cols <- paste0(inc_nhw_prefix, "E", sprintf("%03d", 2:17))
  names(inc_nhw_cols) <- paste0("inc_nhw_", sprintf("%02d", 1:16))
  inc_nhb_cols <- paste0(inc_nhb_prefix, "E", sprintf("%03d", 2:17))
  names(inc_nhb_cols) <- paste0("inc_nhb_", sprintf("%02d", 1:16))
  inc_his_cols <- paste0(inc_his_prefix, "E", sprintf("%03d", 2:17))
  names(inc_his_cols) <- paste0("inc_his_", sprintf("%02d", 1:16))

  # cash rent bracket columns: B25063 E003 through (rent_E_end - 1)
  # E001 = total, E002 = "with cash rent" subtotal, rent_E_end = "no cash rent" — all excluded
  rent_br_cols <- paste0(rent_prefix, "E", sprintf("%03d", 3:(rent_E_end - 1L)))
  names(rent_br_cols) <- paste0("rent_", sprintf("%02d", seq_along(rent_br_cols)))

  # home value bracket columns: B25075 E002 through val_E_end
  # E001 = total (owner-occupied housing units) — excluded
  val_br_cols <- paste0(val_prefix, "E", sprintf("%03d", 2:val_E_end))
  names(val_br_cols) <- paste0("val_", sprintf("%02d", seq_along(val_br_cols)))

  d <- d |> rename(
    pop         = !!pop,
    nhwhite     = !!nhwhite,
    nhwhite_tot = !!nhwhite_tot,
    nhblack     = !!nhblack,
    nhispanic   = !!nhispanic,
    inc_tot     = !!paste0(inc_prefix, "E001"),
    median_inc  = !!median_inc,
    units_tot   = !!units_tot,
    units_vac   = !!units_vac,
    own         = !!own,
    rent        = !!rent,
    median_rent = !!median_rent,
    rb_tot      = !!rb_tot,
    rb_30_35    = !!rb_07,
    rb_35_40    = !!rb_08,
    rb_40_50    = !!rb_09,
    rb_50plus   = !!rb_10,
    median_val  = !!median_val,
    own_nhw     = !!own_nhw,
    rent_nhw    = !!rent_nhw,
    own_nhb     = !!own_nhb,
    rent_nhb    = !!rent_nhb,
    own_his     = !!own_his,
    rent_his    = !!rent_his
  ) |>
    rename(!!!setNames(inc_cols,     names(inc_cols))) |>
    rename(!!!setNames(rent_br_cols, names(rent_br_cols))) |>
    rename(!!!setNames(val_br_cols,  names(val_br_cols))) |>
    rename(
      inc_nhw_tot = !!paste0(inc_nhw_prefix, "E001"),
      inc_nhb_tot = !!paste0(inc_nhb_prefix, "E001"),
      inc_his_tot = !!paste0(inc_his_prefix, "E001")
    ) |>
    rename(!!!setNames(inc_nhw_cols,      names(inc_nhw_cols)))      |>
    rename(!!!setNames(inc_nhb_cols,      names(inc_nhb_cols)))      |>
    rename(!!!setNames(inc_his_cols,      names(inc_his_cols)))

  # Median columns are sometimes read as character due to NHGIS suppression codes
  d <- d |> mutate(across(c(median_inc, median_rent, median_val), as.numeric))

  # education: add as NA columns if not in this year's data
  if (!is.null(edu_tot)) {
    d <- d |> rename(
      edu_tot    = !!edu_tot,
      edu_ba_22  = !!edu_22,
      edu_ba_23  = !!edu_23,
      edu_ba_24  = !!edu_24,
      edu_ba_25  = !!edu_25
    )
  } else {
    d$edu_tot   <- NA_real_
    d$edu_ba_22 <- NA_real_
    d$edu_ba_23 <- NA_real_
    d$edu_ba_24 <- NA_real_
    d$edu_ba_25 <- NA_real_
  }

  # Drop all original NHGIS columns; keep only renamed variables + GEOID
  d |> select(
    GEOID, NAME_E, STUSAB, STATE, COUNTY, year,
    pop, nhwhite, nhwhite_tot, nhblack, nhispanic,
    inc_tot, inc_01:inc_16,
    inc_nhw_tot, inc_nhw_01:inc_nhw_16,
    inc_nhb_tot, inc_nhb_01:inc_nhb_16,
    inc_his_tot, inc_his_01:inc_his_16,
    median_inc,
    units_tot, units_vac,
    own, rent,
    own_nhw, rent_nhw, own_nhb, rent_nhb, own_his, rent_his,
    starts_with("rent_"),
    median_rent,
    rb_tot, rb_30_35, rb_35_40, rb_40_50, rb_50plus,
    starts_with("val_"),
    median_val,
    edu_tot, edu_ba_22, edu_ba_23, edu_ba_24, edu_ba_25
  )
}

data_2009 <- read_and_rename(
  zip = zip_path,
  ACS5a_file = paste0(folder_name, "_csv/", folder_name, "_ds195_20095_tract.csv"),
  ACS5b_file = paste0(folder_name, "_csv/", folder_name, "_ds196_20095_tract.csv"),
  year = 2009,
  # rename variables
  pop = "RK9E001", nhwhite = "RLIE003", nhwhite_tot = "RLIE001", nhblack = "RLIE004", nhispanic = "RLIE012",
  inc_prefix = "RNG",
  inc_nhw_prefix = "R2Z",
  inc_nhb_prefix = "R2T",
  inc_his_prefix = "R20",
  median_inc = "RNHE001",
  units_tot = "RP8E001", units_vac = "RP8E003",
  own = "RP9E002", rent = "RP9E003",
  own_nhw = "RQHE002", rent_nhw = "RQHE003",
  own_nhb = "RQBE002", rent_nhb = "RQBE003",
  own_his = "RQIE002", rent_his = "RQIE003",
  rent_prefix = "RRT", rent_E_end = 24L, # B25063: 21 cash-rent brackets (E003–E023)
  median_rent = "RRUE001",
  rb_tot = "RR0E001", rb_07 = "RR0E007", rb_08 = "RR0E008",
  rb_09 = "RR0E009", rb_10 = "RR0E010",
  val_prefix = "RR5", val_E_end = 25L,   # B25075: 24 value brackets (E002–E025)
  median_val = "RR7E001"
  # no education in 2009
)

data_2014 <- read_and_rename(
  zip = zip_path,
  ACS5a_file = paste0(folder_name, "_csv/", folder_name, "_ds206_20145_tract.csv"),
  ACS5b_file = paste0(folder_name, "_csv/", folder_name, "_ds207_20145_tract.csv"),
  year = 2014,
  # rename variables
  pop = "ABA1E001", nhwhite = "ABBAE003", nhwhite_tot = "ABBAE001", nhblack = "ABBAE004", nhispanic = "ABBAE012",
  inc_prefix = "ABDO",
  inc_nhw_prefix = "ABUK",
  inc_nhb_prefix = "ABUE",
  inc_his_prefix = "ABUL",
  median_inc = "ABDPE001",
  units_tot = "ABGWE001", units_vac = "ABGWE003",
  own = "ABGXE002", rent = "ABGXE003",
  own_nhw = "ABG5E002", rent_nhw = "ABG5E003",
  own_nhb = "ABGZE002", rent_nhb = "ABGZE003",
  own_his = "ABG6E002", rent_his = "ABG6E003",
  rent_prefix = "ABIG", rent_E_end = 24L, # B25063: 21 cash-rent brackets (E003–E023)
  median_rent = "ABIHE001",
  rb_tot = "ABINE001", rb_07 = "ABINE007", rb_08 = "ABINE008",
  rb_09 = "ABINE009", rb_10 = "ABINE010",
  val_prefix = "ABIR", val_E_end = 25L,  # B25075: 24 value brackets (E002–E025)
  median_val = "ABITE001",
  edu_tot = "ABC4E001", edu_22 = "ABC4E022",
  edu_23 = "ABC4E023", edu_24 = "ABC4E024", edu_25 = "ABC4E025"
)

data_2019 <- read_and_rename(
  zip = zip_path,
  ACS5a_file = paste0(folder_name, "_csv/", folder_name, "_ds244_20195_tract.csv"),
  ACS5b_file = paste0(folder_name, "_csv/", folder_name, "_ds245_20195_tract.csv"),
  year = 2019,
  # rename variables
  pop = "ALUBE001", nhwhite = "ALUKE003", nhwhite_tot = "ALUKE001", nhblack = "ALUKE004", nhispanic = "ALUKE012",
  inc_prefix = "ALW0",
  inc_nhw_prefix = "AMDY",
  inc_nhb_prefix = "AMDS",
  inc_his_prefix = "AMDZ",
  median_inc = "ALW1E001",
  units_tot = "ALZKE001", units_vac = "ALZKE003",
  own = "ALZLE002", rent = "ALZLE003",
  own_nhw = "ALZTE002", rent_nhw = "ALZTE003",
  own_nhb = "ALZNE002", rent_nhb = "ALZNE003",
  own_his = "ALZUE002", rent_his = "ALZUE003",
  rent_prefix = "AL04", rent_E_end = 27L, # B25063: 24 cash-rent brackets (E003–E026)
  median_rent = "AL05E001",
  rb_tot = "AL1BE001", rb_07 = "AL1BE007", rb_08 = "AL1BE008",
  rb_09 = "AL1BE009", rb_10 = "AL1BE010",
  val_prefix = "AL1F", val_E_end = 27L,  # B25075: 26 value brackets (E002–E027)
  median_val = "AL1HE001",
  edu_tot = "ALWGE001", edu_22 = "ALWGE022",
  edu_23 = "ALWGE023", edu_24 = "ALWGE024", edu_25 = "ALWGE025"
)

data_2024 <- read_and_rename(
  zip = zip_path,
  ACS5a_file = paste0(folder_name, "_csv/", folder_name, "_ds272_20245_tract.csv"),
  ACS5b_file = paste0(folder_name, "_csv/", folder_name, "_ds273_20245_tract.csv"),
  year = 2024,
  # rename variables
  pop = "AUO6E001", nhwhite = "AUPFE003", nhwhite_tot = "AUPFE001", nhblack = "AUPFE004", nhispanic = "AUPFE012",
  inc_prefix = "AURT",
  inc_nhw_prefix = "AVAD",
  inc_nhb_prefix = "AU97",
  inc_his_prefix = "AVAE",
  median_inc = "AURUE001",
  units_tot = "AUUDE001", units_vac = "AUUDE003",
  own = "AUUEE002", rent = "AUUEE003",
  own_nhw = "AUUME002", rent_nhw = "AUUME003",
  own_nhb = "AUUGE002", rent_nhb = "AUUGE003",
  own_his = "AUUNE002", rent_his = "AUUNE003",
  rent_prefix = "AUWF", rent_E_end = 27L, # B25063: 24 cash-rent brackets (E003–E026)
  median_rent = "AUWGE001",
  rb_tot = "AUWME001", rb_07 = "AUWME007", rb_08 = "AUWME008",
  rb_09 = "AUWME009", rb_10 = "AUWME010",
  val_prefix = "AUWQ", val_E_end = 27L,  # B25075: 26 value brackets (E002–E027)
  median_val = "AUWSE001",
  edu_tot = "AUQ8E001", edu_22 = "AUQ8E022",
  edu_23 = "AUQ8E023", edu_24 = "AUQ8E024", edu_25 = "AUQ8E025"
)

# Stack all years; drop per-year objects to free memory
acs_raw <- bind_rows(data_2009, data_2014, data_2019, data_2024)
rm(data_2009, data_2014, data_2019, data_2024)


## ── 2. TOP 100 CBSAs ─────────────────────────────────────────────────────────
# NHGIS does not populate the CBSAA context column in tract CSV extracts.
# I construct county FIPS by stripping the NHGIS GEOID prefix (which varies
# by vintage: "14000US" for 2010-era, "1400000US" for 2020-era tracts) and
# taking the first 5 characters of the remaining 11-digit FIPS. Then join
# the 2020 county-to-CBSA crosswalk from TIGER/Line via tigris.
# A single fixed boundary definition (2020) is used for all four waves.
# Alaska, Hawaii, and Puerto Rico are excluded; the CBSAs are ranked by 
# 2024 population within the contiguous US and the top 100 are kept for analysis.

county_cbsa <- counties(year = 2020) |>
  as_tibble() |>
  select(county_fips = GEOID, CBSAFP)

cbsa_names <- core_based_statistical_areas(year = 2020) |>
  as_tibble() |>
  select(CBSAFP = GEOID, CBSA_name = NAME)

acs_raw <- acs_raw |>
  mutate(county_fips = substr(sub("^.*US", "", GEOID), 1, 5)) |>
  left_join(county_cbsa, by = "county_fips")

# Rank CBSAs by 2024 population and keep top 100 in the contiguous US.
# Tracts outside any CBSA (rural) have CBSAFP == NA; excluded here.
top100_cbsa <- acs_raw |>
  filter(year == 2024, !is.na(CBSAFP), !STUSAB %in% c("AK", "HI", "PR")) |>
  group_by(CBSAFP) |>
  summarise(pop_2024 = sum(pop, na.rm = TRUE), .groups = "drop") |>
  slice_max(pop_2024, n = 100) |>
  pull(CBSAFP)

acs <- acs_raw |>
  filter(CBSAFP %in% top100_cbsa) |>
  left_join(cbsa_names, by = "CBSAFP")
rm(acs_raw, county_cbsa, cbsa_names, top100_cbsa)
gc()


## ── 3. SAVE ──────────────────────────────────────────────────────────────────

acs <- acs |>
  mutate(vac_rate = units_vac / units_tot)

write_parquet(acs, file.path(output_dir, "acs_top100.parquet"))
