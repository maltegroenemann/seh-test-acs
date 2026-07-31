################################################################################
### Testing the Housing Market Model using ACS and PUMS Data
### Data Preparation: ACS PUMS Individual-Level Data via IPUMS USA
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Source: IPUMS USA extract usa_00002.dat (4 non-overlapping ACS 5-year samples)
#   2005-2009 (us2009e) | 2010-2014 (us2014c) | 2015-2019 (us2019c) | 2020-2024 (us2024c)
#
# Unit of analysis: one record per housing unit, restricted to the household
#   head (PERNUM == 1) in standard housing units (GQ == 1).
#
# PUMA vintage differs by wave (see SEHTestACS1b_downloadPUMS.R). Vintage-specific crosswalks
# from MABLE/Geocorr assign each PUMA to the county with the largest population
# share (afact), then county is joined to the 2020-definition CBSA via tigris:
#   YEAR == 2009  →  2000-vintage PUMAs  (geocorr2000_CrosswalkPUMA2County.csv)
#   YEAR == 2014  →  2010-vintage PUMAs  (geocorr2014_CrosswalkPUMA2County.csv)
#   YEAR == 2019  →  2010-vintage PUMAs  (geocorr2014_CrosswalkPUMA2County.csv)
#   YEAR == 2024  →  2020-vintage PUMAs  (geocorr2022_CrosswalkPUMA2County.csv)
#
# The same top-100 CBSA set is used as in dataprep_ACS.R (2020 boundaries,
# ranked by 2024 ACS population).
#
# Derived variables (monetary values in 1999 USD via CPI99):
#   hhincome_real   HHINCOME * CPI99
#   rentgrs_real    RENTGRS  * CPI99   (monthly gross rent; NA for owners)
#   valueh_real     VALUEH   * CPI99   (property value;    NA for renters / topcoded)
#   inctot_real     INCTOT   * CPI99
#   rent_to_inc     (RENTGRS * 12) / HHINCOME  [renters, HHINCOME > 0 only]
#                   RENTGRS is monthly; ×12 annualises it to match HHINCOME (annual).
#                   CPI99 cancels — result is already deflator-invariant.
#   val_to_inc      valueh_real / hhincome_real  [owners, hhincome_real > 0 only]
#                   Property value-to-income ratio; stock/flow but deflator-invariant.
#   crowding        NUMPREC / ROOMS
#   deficient       1 if KITCHEN == 2 OR PLUMBING == 3
#   renter          1 if OWNERSHP == 2
#   race_eth        4-category: "nhwhite" / "nhblack" / "hispanic" / "nhother"
#   moved_pastyear  1 if MIGRATE1 >= 2 (moved within or between states, or from abroad)
#   hhincome_real   top-coded at within-CBSA × year p99 (extreme values ~$2.2M 1999 USD)
#   equiv_income    hhincome_real / sqrt(NUMPREC), bottom-coded at 1 (OECD sqrt scale)
#   log_equiv_inc   log(equiv_income)
#   college         1 if EDUC >= 10 (BA or higher, IPUMS harmonised coding)
#   quality         z-score of rentgrs_real (renters) / valueh_real (owners)
#                   standardised within YEAR × CBSA × tenure
#   recent_mover    1 if renter and MOVEDIN >= YEAR - 2
#   quality_rc      robustness version of quality: renters standardised using
#                   recent movers only to mitigate rent control distortions
#
# Note on OCC2010 → ISEI: ISEI prestige scores require an OCC2010-to-ISCO
#   crosswalk (see Ganzeboom 2010). That step is deferred to the analysis
#   script; OCC2010 is retained here in its raw form.
#
# Output:
#   data/pums_hh.parquet   one row per housing unit / household head


## ── SETUP ────────────────────────────────────────────────────────────────────

library(ipumsr)
library(tigris)
library(nanoparquet)
library(dplyr)

options(tigris_use_cache = TRUE)

data_dir <- "./data/PUMS/"
ddi_file <- list.files(data_dir, pattern = "usa_.*\\.xml$", full.names = TRUE)

acs <- read_parquet("./data/acs_top100.parquet")

output_dir <- "./data/"


## ── 1. READ AND FILTER ───────────────────────────────────────────────────────
# The full extract spans ~28M person records across 4 waves; reading it at once
# exhausts RAM on most workstations. read_ipums_micro_chunked() processes the
# fixed-width .dat file in batches: the callback filters each chunk immediately,
# so only the ~4M qualifying rows accumulate in memory.
#
# chunk_size = 20000 ≈ 15–25 MB per batch (including R overhead); tune down to
# 5000 if memory is still tight, or up to 100000 on machines with ≥ 32 GB RAM.

pums <- read_ipums_micro_chunked(
  ddi_file,
  callback   = IpumsDataFrameCallback$new(function(x, pos) {
    x |> filter(as.integer(GQ) == 1L, as.integer(PERNUM) == 1L)
  }),
  chunk_size = 20000, # TODO adapt chunk size to available memory
  verbose    = TRUE
)

gc()


## ── 2. PUMA → 2020 CBSA CROSSWALK ───────────────────────────────────────────
#
# Source: Missouri Census Data Center MABLE/Geocorr tool
#   Source geography: PUMA | Target: County | Weighting: Population
#   geocorr2000_CrosswalkPUMA2County.csv  →  2000-vintage PUMAs (YEAR == 2009)
#   geocorr2014_CrosswalkPUMA2County.csv  →  2010-vintage PUMAs (YEAR == 2014, 2019)
#   geocorr2022_CrosswalkPUMA2County.csv  →  2020-vintage PUMAs (YEAR == 2024)
#
# All three files share the same structure: state (2-digit FIPS), a PUMA
# column (named puma5/puma12/puma22), county (5-digit FIPS), and afact
# (share of PUMA population falling in that county). Row 2 is a label row.
# For each PUMA, the county with the largest afact is selected, then joined
# to the county-to-2020-CBSA table from tigris.

# County → 2020 CBSA
county_cbsa <- counties(year = 2020) |>
  as_tibble() |>
  select(county_fips = GEOID, CBSAFP)

# 2020 CBSA names
cbsa_names <- core_based_statistical_areas(year = 2020, cb = TRUE) |>
  as_tibble() |>
  select(CBSAFP = GEOID, CBSA_name = NAME) |>
  mutate(cbsa_name_short = sub("^([^-/]+?)(?:[-/][^,]*)?,\\s*([A-Z]{2}).*$",
                                "\\1, \\2", CBSA_name))

# Helper: read one Geocorr file and return a PUMA → CBSA table
read_geocorr <- function(file, puma_col, vintage) {
  raw <- read.csv(file, colClasses = "character")
  raw <- raw[grepl("^[0-9]{2}$", raw$state), ]   # drop label row
  raw |>
    mutate(afact = as.numeric(afact)) |>
    group_by(state, .data[[puma_col]]) |>
    slice_max(afact, n = 1, with_ties = FALSE) |>
    ungroup() |>
    rename(STATEFIP = state, PUMA = all_of(puma_col), county_fips = county) |>
    left_join(county_cbsa, by = "county_fips") |>
    select(STATEFIP, PUMA, CBSAFP) |>
    mutate(puma_vintage = vintage)
}

# TODO for replication adapt name of crosswalk tables
xwalk_2000 <- read_geocorr(file.path(data_dir, "geocorr2000_CrosswalkPUMA2County.csv"), "puma5",  2000L)
xwalk_2010 <- read_geocorr(file.path(data_dir, "geocorr2014_CrosswalkPUMA2County.csv"), "puma12", 2010L)
xwalk_2020 <- read_geocorr(file.path(data_dir, "geocorr2022_CrosswalkPUMA2County.csv"), "puma22", 2020L)

xwalk_all <- bind_rows(xwalk_2000, xwalk_2010, xwalk_2020)
rm(xwalk_2000, xwalk_2010, xwalk_2020, county_cbsa)


## 2b. Join crosswalk to PUMS ─────────────────────────────────────────────────

# IPUMS PUMA codes are integers; pad to character with leading zeros to match
# the Geocorr files
pums <- pums |>
  mutate(
    puma_vintage = case_when(
      as.integer(YEAR) == 2009L              ~ 2000L,
      as.integer(YEAR) %in% c(2014L, 2019L) ~ 2010L,
      as.integer(YEAR) == 2024L              ~ 2020L
    ),
    STATEFIP_chr = sprintf("%02d", as.integer(STATEFIP)),
    PUMA_chr     = sprintf("%05d", as.integer(PUMA)),
    PUMA_id      = paste0(PUMA_chr, "_", puma_vintage) # create PUMA identifier unique over years
  ) |>
  left_join(xwalk_all,
            by = c("STATEFIP_chr" = "STATEFIP",
                   "PUMA_chr"     = "PUMA",
                   "puma_vintage"))

rm(xwalk_all)
gc()


## ── 3. TOP 100 CBSAs ─────────────────────────────────────────────────────────
# Identical CBSA set as in SEHTestACS2s_dataprepACS.R (2020 boundaries, 2024 population).

top100_cbsa <- unique(acs$CBSAFP)

pums <- pums |>
  filter(!is.na(CBSAFP), CBSAFP %in% top100_cbsa) |>
  left_join(cbsa_names, by = "CBSAFP")

rm(top100_cbsa, cbsa_names)


## ── 4. MISSING-VALUE RECODING ────────────────────────────────────────────────
# IPUMS preserves original numeric sentinel codes (not converted to NA).
# Values below are from IPUMS USA variable documentation.

pums <- pums |>
  mutate(
    # HHINCOME: 9999999 = N/A
    HHINCOME = if_else(as.integer(HHINCOME) == 9999999L,
                       NA_real_, as.double(HHINCOME)),
    # VALUEH: 9999998 = N/A, 9999999 = missing
    VALUEH   = if_else(as.integer(VALUEH) >= 9999998L,
                       NA_real_, as.double(VALUEH)),
    # POVERTY: 000 = not in universe (e.g. institutional GQ, already excluded)
    POVERTY  = if_else(as.integer(POVERTY) == 0L,
                       NA_real_, as.double(POVERTY)),
    # RENTGRS: 0 = owner / not applicable
    RENTGRS  = if_else(as.integer(OWNERSHP) != 2L,
                       NA_real_, as.double(RENTGRS))
  )


## ── 5. DERIVED VARIABLES ─────────────────────────────────────────────────────

pums <- pums |>
  mutate(
    # Inflation-adjusted monetary variables (1999 USD)
    hhincome_real = HHINCOME * CPI99,
    rentgrs_real  = RENTGRS  * CPI99,
    valueh_real   = VALUEH   * CPI99,
    inctot_real   = INCTOT   * CPI99,

    # Annual rent-to-income ratio (CPI99 cancels; renters with positive income)
    rent_to_inc = if_else(
      as.integer(OWNERSHP) == 2L & HHINCOME > 0,
      (RENTGRS * 12) / HHINCOME,
      NA_real_
    ),

    # Property value-to-income ratio (CPI99 cancels; owners with positive income)
    val_to_inc = if_else(
      as.integer(OWNERSHP) == 1L & HHINCOME > 0,
      (VALUEH * CPI99) / (HHINCOME * CPI99),
      NA_real_
    ),

    # Persons per room (crowding)
    crowding = as.double(NUMPREC) / as.double(ROOMS),

    # Deficient housing: lacking complete kitchen or plumbing
    deficient = as.integer(as.integer(KITCHEN) == 2L | as.integer(PLUMBING) == 3L),

    # Tenure
    renter = as.integer(as.integer(OWNERSHP) == 2L),

    # Race / ethnicity (4 categories following Reardon & Bischoff 2011)
    race_eth = case_when(
      as.integer(HISPAN) %in% 1:4 ~ "hispanic",
      as.integer(RACE) == 1L      ~ "nhwhite",
      as.integer(RACE) == 2L      ~ "nhblack",
      TRUE                        ~ "nhother"
    ),

    # Residential mobility: any move in past year
    moved_pastyear = as.integer(as.integer(MIGRATE1) >= 2L)
  )

# Income top-coding within YEAR × CBSA at p99
pums <- pums |>
  group_by(YEAR, CBSAFP) |>
  mutate(
    hhincome_real = pmin(hhincome_real,
                         quantile(hhincome_real, 0.99, na.rm = TRUE))
  ) |>
  ungroup()

# Equivalised income and college indicator
pums <- pums |>
  mutate(
    equiv_income  = pmax(hhincome_real / sqrt(NUMPREC), 1),
    log_equiv_inc = log(equiv_income),
    college       = as.integer(as.integer(EDUC) >= 10L)
  )

# Housing quality: z-score within YEAR × CBSA × tenure
# Renters: gross rent; owners: home value.
pums <- pums |>
  group_by(YEAR, CBSAFP, renter) |>
  mutate(quality = if_else(
    renter == 1L,
    as.numeric(scale(rentgrs_real)),
    as.numeric(scale(valueh_real))
  )) |>
  ungroup()

# Robustness quality: renters standardised using recent movers only
# (MOVEDIN >= YEAR - 2) to mitigate rent control distortions.
pums <- pums |>
  group_by(YEAR, CBSAFP) |>
  mutate(
    recent_mover = renter == 1L & as.integer(MOVEDIN) >= YEAR - 2L,
    quality_rc   = if_else(
      renter == 0L,
      quality,
      if_else(
        recent_mover,
        (rentgrs_real - mean(rentgrs_real[recent_mover], na.rm = TRUE)) /
          sd(rentgrs_real[recent_mover], na.rm = TRUE),
        NA_real_
      )
    )
  ) |>
  ungroup()


## ── 6. SELECT AND SAVE ───────────────────────────────────────────────────────

pums <- pums |>
  select(
    # Identifiers
    YEAR, SERIAL, CBSAFP, CBSA_name, cbsa_name_short, STATEFIP, PUMA, PUMA_id, puma_vintage,
    # Survey design weights
    HHWT, PERWT, CLUSTER, STRATA,
    # Housing unit
    renter, ROOMS, BEDROOMS, NUMPREC, UNITSSTR, BUILTYR2,
    crowding, deficient, KITCHEN, PLUMBING,
    # Income & rent (raw and 1999 USD; hhincome_real is top-coded at CBSA × year p99)
    # CPI99 retained so city-level scripts can deflate raw HHINCOME without top-coding
    HHINCOME, CPI99, hhincome_real, equiv_income, log_equiv_inc,
    RENTGRS,  rentgrs_real, rent_to_inc,
    VALUEH,   valueh_real,  val_to_inc,
    # Housing quality proxies
    quality, quality_rc, recent_mover,
    # Household head (person-level)
    AGE, SEX, RELATE, race_eth, RACE, HISPAN, EDUC, college,
    OCC2010, EMPSTAT,
    INCTOT, inctot_real, POVERTY,
    moved_pastyear, MIGRATE1, MOVEDIN
  )

write_parquet(pums, file.path(output_dir, "pums_hh.parquet"))
