################################################################################
### Testing Hypotheses from the ABM
### Download ACS 5-Year PUMS via IPUMS USA
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Four non-overlapping ACS 5-year PUMS samples, matching the NHGIS tract waves:
#   2005-2009 (us2009e) | 2010-2014 (us2014c) | 2015-2019 (us2019c) | 2020-2024 (us2024c)
#
# Note on sample ID suffixes: the 2009 wave uses "e"; later 5-year waves use "c".
#
# PUMA vintage differs across waves — relevant for the CBSA crosswalk in
# dataprep_PUMS.R:
#   us2009e  →  2000-vintage PUMAs
#   us2014c  →  2010-vintage PUMAs (2012+ obs dominate the 5-year window)
#   us2019c  →  2010-vintage PUMAs
#   us2024c  →  2020-vintage PUMAs
#
# Variables requested (IPUMS harmonised names throughout):
#
# GEOGRAPHY & SURVEY DESIGN
#   STATEFIP    State FIPS code
#   PUMA        PUMA code (→ linked to CBSA via vintage-specific crosswalk)
#   HHWT        Household weight
#   PERWT       Person weight
#   CLUSTER     Variance estimation cluster (for clustered SEs)
#   STRATA      Variance estimation stratum
#   CPI99       CPI multiplier to 1999 USD (apply to RENTGRS, HHINCOME, VALUEH)
#
# HOUSING UNIT
#   GQ          Group quarters type  (keep: 1 = housing unit)
#   OWNERSHP    Tenure  (1 = owned/buying, 2 = rented)
#   HHINCOME    Total household income past 12 months
#   RENTGRS     Gross monthly rent incl. utilities  (renters only)
#               → rent-to-income ratio and expenditure measures use gross rent
#   RENT        Contract monthly rent excl. utilities  (renters only)
#               → quality proxy and quality-based Gini use contract rent, which
#                 reflects the market price of the unit itself without the ambiguous
#                 utility cost signal (larger unit → higher utilities, but also
#                 poorly maintained unit → higher utilities)
#   ROOMS       Number of rooms
#   BEDROOMS    Number of bedrooms
#   NUMPREC     Number of person records in housing unit  (→ crowding: NUMPREC / ROOMS)
#   UNITSSTR    Units in structure  (building type)
#   BUILTYR2    Year structure built  (decade categories; proxy for quality/age)
#   KITCHEN     Kitchen or cooking facilities  (2 = lacking complete kitchen)
#   PLUMBING    Plumbing facilities             (3 = lacking complete plumbing)
#   VALUEH      Property value  (owners only; quality proxy complementing RENTGRS)
#   COSTELEC    Monthly electricity cost  (owners; 0 = NIU, 1 = no charge/in fees)
#   COSTGAS     Monthly gas cost          (owners; 0 = NIU, 1 = no charge/in fees)
#   COSTWATR    Monthly water/sewer cost  (owners; 0 = NIU, 1 = no charge/in fees)
#   COSTFUEL    Annual fuel/oil cost      (owners; 0 = NIU, 1 = no charge/in fees)
#               → util_monthly_real = (COSTELEC + COSTGAS + COSTWATR + COSTFUEL/12) × CPI99
#               Added to imputed rent for owners in pooled housing cost measures so
#               that owner costs are comparable to gross rent (RENTGRS includes utilities).
#
# PERSON  (used for household head: PERNUM == 1)
#   PERNUM      Person number within household
#   RELATE      Relationship to household head
#   AGE         Age
#   SEX         Sex
#   RACE        Race
#   HISPAN      Hispanic origin
#   EDUC        Educational attainment  (IPUMS harmonised; status proxy)
#   OCC2010     Occupation, harmonised 2010 SOC codes  (→ ISEI prestige score)
#   EMPSTAT     Employment status
#   INCTOT      Total personal income past 12 months
#   POVERTY     Income-to-poverty ratio in %  (inflation-stable income measure)
#   MIGRATE1    Residence 1 year ago  (1=same house, 2=same county, 3=same state,
#               4=different state, 5=abroad)  → residential mobility H17–H21
#               Note: voluntary vs. involuntary distinction not available in ACS
#   MOVEDIN     Year householder moved into unit  (tenure duration)


## ── SETUP ────────────────────────────────────────────────────────────────────

library(ipumsr)

# Requires an IPUMS API key: https://account.ipums.org/api_keys
# TODO If not yet saved, run once interactively:
#   set_ipums_api_key("your-key", save = TRUE)

data_dir <- "./data/PUMS/" # TODO for replication: change path
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)


## ── DEFINE AND SUBMIT EXTRACT ────────────────────────────────────────────────

pums_vars <- c(
  # geography & survey design
  "STATEFIP", "PUMA", "HHWT", "PERWT", "CLUSTER", "STRATA", "CPI99",
  # housing unit
  "GQ", "OWNERSHP", "HHINCOME", "RENTGRS", "RENT",
  "ROOMS", "BEDROOMS", "NUMPREC", "UNITSSTR", "BUILTYR2", "KITCHEN", "PLUMBING",
  "VALUEH", "COSTELEC", "COSTGAS", "COSTWATR", "COSTFUEL",
  # person (head of household)
  "PERNUM", "RELATE", "AGE", "SEX", "RACE", "HISPAN",
  "EDUC", "OCC2010", "EMPSTAT", "INCTOT", "POVERTY", "MIGRATE1", "MOVEDIN"
)

extract_pums <- define_extract_micro(
  collection  = "usa",
  description = "ACS 5-year PUMS 2009-2024 for individual-level housing outcomes (ABM test)",
  samples     = c("us2009e", "us2014c", "us2019c", "us2024c"),
  variables   = pums_vars
)

submitted <- submit_extract(extract_pums)
completed <- wait_for_extract(submitted, verbose = TRUE)
download_extract(completed, download_dir = data_dir, progress = TRUE, overwrite = TRUE)

remove(completed, submitted, extract_pums)
