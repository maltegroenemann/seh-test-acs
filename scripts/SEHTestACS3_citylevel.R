################################################################################
### Testing the Housing Market Model using ACS and PUMS Data
### Segregation Indices and City-Level Controls
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Computes city-level (CBSA × year) variables for use as controls and key
# predictors in the PUMS individual-level analyses.
#
# Inputs:
#   acs_top100.parquet  (produced by SEHTestACS2a_dataprepACS.R)  — tract-level ACS aggregates
#   pums_hh.parquet     (produced by SEHTestACS2b_dataprepPUMS.R) — household-level PUMS
#
# Variables computed:
#   From ACS tract data (acs_top100.parquet):
#   H_inc             rank-order income segregation H^R (Reardon & Bischoff 2011; all HH)
#   H_inc_p50         binary Theil H at median income cutpoint (below vs. above median HH income)
#   H_inc_nhw         within-NH-White rank-order income segregation H^R (B19001H)
#   H_inc_nhb         within-NH-Black rank-order income segregation H^R (B19001B)
#   H_inc_his         within-Hispanic rank-order income segregation H^R (B19001I)
#   H_inc_nhw_p50     NH-White binary H at within-group median income cutpoint
#   H_inc_nhb_p50     NH-Black binary H at within-group median income cutpoint
#   H_inc_his_p50     Hispanic binary H at within-group median income cutpoint
#   H_inc_within      within-race H^R (pop.-weighted avg. of H_inc_nhw/nhb/his)
#   H_inc_between     between-race H^R (H_inc − H_inc_within; residual)
#   pct_owner_nhw_cbsa NH-White homeownership rate (B25003H)
#   pct_owner_nhb_cbsa NH-Black homeownership rate (B25003B)
#   pct_owner_his_cbsa Hispanic homeownership rate (B25003I)
#   owner_gap_bw_cbsa  NH-White minus NH-Black homeownership rate gap
#   owner_gap_hw_cbsa  NH-White minus Hispanic homeownership rate gap
#   H_tenure_nhw      NH-White owner vs. NH-White renter binary Theil H (B25003H)
#   H_tenure_nhb      NH-Black owner vs. NH-Black renter binary Theil H (B25003B)
#   H_tenure_his      Hispanic owner vs. Hispanic renter binary Theil H (B25003I)
#   H_bw              NH-Black vs. NH-White binary Theil H
#   H_tenure          owner vs. renter binary Theil H (tenure segregation)
#   H_race_multi      four-group racial Theil H (NH White / NH Black / Hispanic / NH Other)
#   H_rent            rank-order gross rent segregation H^R (B25063 cash-rent brackets)
#   H_val             rank-order home-value segregation H^R (B25075 value brackets)
#   pop_cbsa          total CBSA population
#   pop_growth_cbsa   period-over-period population growth rate (NA for 2009 due to lag)
#   pct_renter_cbsa   renter share of occupied units (B25003)
#   pct_nhwhite_cbsa  NH-White share of population (B03002)
#   pct_nhblack_cbsa  NH-Black share of population (B03002)
#   pct_hispanic_cbsa Hispanic share of population (B03002)
#   pct_college_cbsa  share of population 25+ with BA or higher (B15003; NA for 2009)
#   rent_burden_cbsa  share of renters paying ≥ 30 % of income on rent (B25070)
#   H_vac             binary Theil H: vacant vs. occupied units (B25002)
#   vacancy_rate_cbsa housing vacancy rate (units_vac / units_tot, B25002)
#
#   From PUMS microdata (pums_hh.parquet):
#   gini_inc_cbsa     weighted Gini of equivalised household income
#   unemp_rate_cbsa   unemployment rate among household heads in the labour force
#   gini_rent_cbsa         weighted Gini of gross rent in 1999 USD (renters only; HHWT)
#   gini_val_cbsa          weighted Gini of home value in 1999 USD (owners only; HHWT)
#   gini_housing_cbsa      pooled Gini of housing cost (rent | imputed rent); metro×year cap rate
#   gini_housing_cbsa_5pct pooled Gini; fixed 5 % p.a. cap rate (robustness)
#   gini_housing_cbsa_7pct pooled Gini; fixed 7 % p.a. cap rate (robustness)
#   gini_housing_cbsa_natl pooled Gini; year-specific national cap rate (robustness)
#
# Outputs:
#   data/cbsa_vars.parquet       one row per CBSA × year
#   data/pums_analysis.parquet   pums_hh joined with cbsa_controls, plus:
#     cap_rate_metro   metro × year cap rate (12 × med_rent / med_val; from PUMS)
#     cost_to_inc      valueh_real × cap_rate_metro / hhincome_real
#                      annualised imputed cost-to-income ratio [owners, hhincome_real > 0]
#                      flow/flow analog to rent_to_inc; CPI99 cancels


## ── SETUP ────────────────────────────────────────────────────────────────────

library(nanoparquet)
library(dplyr)
library(tidyr)

data_dir <- "./data/" # TODO for replication: change paths in SETUP chunk

acs <- read_parquet("./data/acs_top100.parquet")

pums <- read_parquet("./data/pums_hh.parquet") |>
  mutate(YEAR = as.integer(YEAR))


## ── SEGREGATION INDICES ──────────────────────────────────────────────────────
# see Reardon & Bischoff (2011) and Reardon et al. (2006)
# Adapted from SocEconHousing/abm/SocEconHousing2_dataprep.R for ACS bracket-count data.

entropy <- function(p) {
  ifelse(p == 0 | p == 1,
         0, # 0 * log2(1/0) := 0; see Reardon et al. (2006) p. 11
         p * log2(1 / p) + (1 - p) * log2(1 / (1 - p)))
}

# Binary Theil H for any two count columns (e.g. nhwhite vs non-nhwhite)
# If col2 is omitted, n (a total column) must be supplied and col2 = n - col1.
# notation following Reardon and Bischoff (2011) p. 1111
H_binary <- function(df, col1, col2 = NULL, n = NULL) {
  n1      <- df[[col1]]
  n2      <- if (!is.null(col2)) df[[col2]] else df[[n]] - n1
  t_j     <- n1 + n2
  T_total <- sum(t_j, na.rm = TRUE)
  p       <- sum(n1, na.rm = TRUE) / T_total
  E_total <- entropy(p)
  if (E_total == 0) return(0)
  p_j <- n1 / t_j
  E_j <- entropy(p_j)
  1 - sum(t_j * E_j, na.rm = TRUE) / (T_total * E_total)
}

# Binary Theil H at ordered cutpoint p of cols (households in cols[1..p] vs cols[p+1..K])
H_p_bracket <- function(df, p, cols) {
  below <- rowSums(df[, cols[seq_len(p)],               drop = FALSE], na.rm = TRUE)
  above <- rowSums(df[, cols[seq(p + 1, length(cols))], drop = FALSE], na.rm = TRUE)
  H_binary(data.frame(below = below, above = above), "below", "above")
}

# Reardon rank-order index H^R for one CBSA × year
# cols: ordered bracket column names (e.g. inc_01..inc_16)
H_R_bracket <- function(df, cols) {
  K       <- length(cols)
  cum_p   <- cumsum(colSums(df[, cols], na.rm = TRUE))
  cum_p   <- cum_p / cum_p[K]

  p_i   <- cum_p[seq_len(K - 1)]
  E_p_i <- entropy(p_i)
  H_p_i <- vapply(seq_len(K - 1), function(p) H_p_bracket(df, p, cols), numeric(1))

  E_p_model <- lm(E_p_i ~ p_i + I(p_i^2) + I(p_i^3) + I(p_i^4))
  E_p_fun   <- function(p) {
    E_p_model$coefficients[1] + E_p_model$coefficients[2] * p +
    E_p_model$coefficients[3] * p^2 + E_p_model$coefficients[4] * p^3 +
    E_p_model$coefficients[5] * p^4
  }
  H_p_model <- lm(H_p_i ~ p_i + I(p_i^2) + I(p_i^3) + I(p_i^4))
  H_p_fun   <- function(p) {
    H_p_model$coefficients[1] + H_p_model$coefficients[2] * p +
    H_p_model$coefficients[3] * p^2 + H_p_model$coefficients[4] * p^3 +
    H_p_model$coefficients[5] * p^4
  }

  integral <- integrate(function(p) H_p_fun(p) * E_p_fun(p), 0, 1)
  result   <- 2 * log(2) * integral$value
  # H is bounded [0,1]; negative results are a polynomial-smoothing artifact
  # (the 4th-degree fit can extrapolate below zero near the tails, e.g. when
  # many units are bunched in the top bracket and the CDF plateaus early).
  if (result < 0) NA_real_ else result
}

# Multigroup entropy (log2; 0 * log(0) := 0)
entropy_multi <- function(p) {
  -sum(ifelse(p == 0, 0, p * log2(p)))
}

# Multigroup Theil H for k race/ethnicity groups
# see Reardon & Firebaugh (2002)
# cols: character vector of count columns, one per group
H_multi <- function(df, cols) {
  counts  <- as.matrix(df[, cols])
  t_j     <- rowSums(counts, na.rm = TRUE)
  T_tot   <- sum(t_j, na.rm = TRUE)
  pi_g    <- colSums(counts, na.rm = TRUE) / T_tot
  E_city  <- entropy_multi(pi_g)
  if (E_city == 0) return(0)
  p_gj    <- counts / pmax(t_j, 1)
  E_j     <- apply(p_gj, 1, entropy_multi)
  1 - sum(t_j * E_j, na.rm = TRUE) / (T_tot * E_city)
}


## ── INCOME SEGREGATION H^R ───────────────────────────────────────────────────
# Income brackets (B19001) are inflation-adjusted within each wave but not
# across waves. H^R is robust to bracket boundary shifts, so cross-wave
# comparisons are valid without deflating to constant dollars.

inc_cols <- paste0("inc_", sprintf("%02d", 1:16))

seg_income <- acs |>
  select(GEOID, CBSAFP, year, all_of(inc_cols)) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(H_inc = H_R_bracket(.x, inc_cols))) |>
  ungroup()


## ── INCOME SEGREGATION AT MEDIAN CUTPOINT ────────────────────────────────────
# Binary Theil H splitting households at the median income bracket (below vs.
# above median). Directly comparable in form to H_tenure (a single owner/renter
# split), allowing a like-for-like check of whether tenure segregation exceeds
# income segregation when both are measured as binary H at a single cutpoint.
# The median bracket p50 is the first bracket where the CBSA-level cumulative
# income share reaches or exceeds 0.5; it varies across CBSAs and waves.

seg_income_p50 <- acs |>
  select(GEOID, CBSAFP, year, all_of(inc_cols)) |>
  group_by(CBSAFP, year) |>
  group_modify(~ {
    totals <- colSums(.x[inc_cols], na.rm = TRUE)
    cum_p  <- cumsum(totals) / sum(totals)
    p50    <- which(cum_p >= 0.5)[1]
    tibble(H_inc_p50 = H_p_bracket(.x, p50, inc_cols))
  }) |>
  ungroup()


## ── WITHIN-RACE INCOME SEGREGATION H^R ───────────────────────────────────────
# Rank-order H^R computed separately within NH-White, NH-Black, and Hispanic
# households using race-specific income bracket tables (B19001H/B/I).
# Returns NA for CBSA × year cells where a group has zero recorded households
# (avoids division by zero in H_R_bracket's cumulative proportion step).

inc_nhw_cols <- paste0("inc_nhw_", sprintf("%02d", 1:16))
inc_nhb_cols <- paste0("inc_nhb_", sprintf("%02d", 1:16))
inc_his_cols <- paste0("inc_his_", sprintf("%02d", 1:16))

seg_income_race <- acs |>
  select(GEOID, CBSAFP, year,
         all_of(c(inc_nhw_cols, inc_nhb_cols, inc_his_cols))) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(
    H_inc_nhw = if (sum(.x[inc_nhw_cols], na.rm = TRUE) > 0)
                  H_R_bracket(.x, inc_nhw_cols) else NA_real_,
    H_inc_nhb = if (sum(.x[inc_nhb_cols], na.rm = TRUE) > 0)
                  H_R_bracket(.x, inc_nhb_cols) else NA_real_,
    H_inc_his = if (sum(.x[inc_his_cols], na.rm = TRUE) > 0)
                  H_R_bracket(.x, inc_his_cols) else NA_real_
  )) |>
  ungroup()


## ── WITHIN-RACE INCOME SEGREGATION AT MEDIAN CUTPOINT ────────────────────────
# Binary H at the within-group median income bracket for each racial group.
# Directly comparable to H_tenure_nhw/nhb/his since both are single-split H.
# p50 is computed from the group-specific bracket totals, so it reflects the
# median of that group's income distribution, not the overall metro median.

p50_from_cols <- function(df, cols) {
  totals <- colSums(df[cols], na.rm = TRUE)
  cum_p  <- cumsum(totals) / sum(totals)
  which(cum_p >= 0.5)[1]
}

seg_income_race_p50 <- acs |>
  select(GEOID, CBSAFP, year,
         all_of(c(inc_nhw_cols, inc_nhb_cols, inc_his_cols))) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(
    H_inc_nhw_p50 = if (sum(.x[inc_nhw_cols], na.rm = TRUE) > 0)
                      H_p_bracket(.x, p50_from_cols(.x, inc_nhw_cols), inc_nhw_cols) else NA_real_,
    H_inc_nhb_p50 = if (sum(.x[inc_nhb_cols], na.rm = TRUE) > 0)
                      H_p_bracket(.x, p50_from_cols(.x, inc_nhb_cols), inc_nhb_cols) else NA_real_,
    H_inc_his_p50 = if (sum(.x[inc_his_cols], na.rm = TRUE) > 0)
                      H_p_bracket(.x, p50_from_cols(.x, inc_his_cols), inc_his_cols) else NA_real_
  )) |>
  ungroup()


## ── REARDON DECOMPOSITION OF H^R ─────────────────────────────────────────────
# Decomposes H_inc into within-race and between-race components.
#
#   H_inc = H_inc_within + H_inc_between
#
# H_inc_within = Σ_g π_g * H_inc_g, where g ∈ {NH-White, NH-Black, Hispanic}
#   and π_g is the group's household share (from B19001H/B/I totals).
#
# The additive decomposability of the information theory index H (total entropy =
# between-group + weighted sum of within-group entropies) is a property of the
# Theil entropy measure: Theil (1972, Statistical Decomposition Analysis,
# North-Holland). The exact formula with entropy weights π_g * (E_g(p)/E(p)) at
# each income cutpoint p is an analytical extension of that property to the H^R
# integral; it does not appear to have a dedicated published derivation.
# The implementation here uses plain household shares π_g as weights, which is
# an approximation that understates H_inc_within (and overstates H_inc_between)
# to the extent that group income distributions diverge from the overall.
#
# TODO: check Reardon & Bischoff (2011, AJS 116:1092–1153) and Reardon's CEPA
# working papers on income segregation for whether they (a) formally state the
# decomposability of H^R, and (b) apply it — they do run separate analyses by
# race in the AJS paper which may amount to the same thing implicitly. Clarify
# the correct citation and whether the entropy-weighted exact version is needed.
#
# TODO: if exact decomposition is warranted, implement H_R_decompose(df,
# cols_all, cols_list): at each of the K−1 cutpoints compute H_g(p) and E_g(p)
# per group, sum Σ_g π_g * E_g(p) * H_g(p), smooth with the degree-4 polynomial,
# and integrate over [0,1] to obtain H_inc_within; H_inc_between = H_inc − H_inc_within.
#
# NOTE: NH-White + NH-Black + Hispanic do not cover all households. In metros
# with a large NH-Other population (e.g. Pacific metros with many NH-Asian HH),
# π_nhw + π_nhb + π_his < 1, so H_inc_within is a lower bound on the true
# within-race component and H_inc_between is correspondingly overstated.

metro_hh_shares <- acs |>
  group_by(CBSAFP, year) |>
  summarise(
    pi_nhw = sum(inc_nhw_tot, na.rm = TRUE) / sum(inc_tot, na.rm = TRUE),
    pi_nhb = sum(inc_nhb_tot, na.rm = TRUE) / sum(inc_tot, na.rm = TRUE),
    pi_his = sum(inc_his_tot, na.rm = TRUE) / sum(inc_tot, na.rm = TRUE),
    .groups = "drop"
  )

seg_decomp <- seg_income |>
  left_join(seg_income_race, by = c("CBSAFP", "year")) |>
  left_join(metro_hh_shares, by = c("CBSAFP", "year")) |>
  mutate(
    H_inc_within  = pi_nhw * H_inc_nhw + pi_nhb * H_inc_nhb + pi_his * H_inc_his,
    H_inc_between = H_inc - H_inc_within
  ) |>
  select(CBSAFP, year, H_inc_within, H_inc_between)


## ── RACIAL HOMEOWNERSHIP RATES AND GAPS ──────────────────────────────────────
# From B25003H/B/I: tenure (owner/renter) by race of householder.
# Tract counts sum exactly to CBSA totals — no approximation needed.
# Gaps are arithmetic (percentage point) differences, NHW as reference.

seg_tenure_race <- acs |>
  group_by(CBSAFP, year) |>
  summarise(
    pct_owner_nhw_cbsa = sum(own_nhw, na.rm = TRUE) /
                         sum(own_nhw + rent_nhw, na.rm = TRUE),
    pct_owner_nhb_cbsa = sum(own_nhb, na.rm = TRUE) /
                         sum(own_nhb + rent_nhb, na.rm = TRUE),
    pct_owner_his_cbsa = sum(own_his, na.rm = TRUE) /
                         sum(own_his + rent_his, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    owner_gap_bw_cbsa = pct_owner_nhw_cbsa - pct_owner_nhb_cbsa,
    owner_gap_hw_cbsa = pct_owner_nhw_cbsa - pct_owner_his_cbsa
  )


## ── RACIAL SEGREGATION H ─────────────────────────────────────────────────────
# Binary Theil H for NH Black vs. NH White only. Black-white segregation is the
# most persistent and theoretically relevant form for housing inequality in the US.
# nhblack and nhwhite are tract counts from B03002 E004 and E003 respectively.

seg_race <- acs |>
  select(GEOID, CBSAFP, year, nhblack, nhwhite) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(H_bw = H_binary(.x, "nhblack", "nhwhite"))) |>
  ungroup()

# Four-group Theil H: NH White / NH Black / Hispanic / NH Other.
# NH Other is the residual of nhwhite_tot minus the three named groups;
# pmax(..., 0) guards against rare suppression-induced small negatives.

race_cols <- c("nhwhite", "nhblack", "nhispanic", "nhother")

seg_race_multi <- acs |>
  mutate(nhother = pmax(nhwhite_tot - nhwhite - nhblack - nhispanic, 0)) |>
  select(GEOID, CBSAFP, year, all_of(race_cols)) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(H_race_multi = H_multi(.x, race_cols))) |>
  ungroup()


## ── TENURE SEGREGATION H ─────────────────────────────────────────────────────
# Binary Theil H for renter-occupied vs. owner-occupied units across tracts.
# Captures how spatially separated renters and owners are within a metro.
# own and rent are tract counts from B25003 E002 and E003 respectively.

seg_tenure <- acs |>
  select(GEOID, CBSAFP, year, own, rent) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(H_tenure = H_binary(.x, "rent", "own"))) |>
  ungroup()


## ── WITHIN-RACE TENURE SEGREGATION H ─────────────────────────────────────────
# Binary Theil H for owners vs. renters within each racial group across tracts.
# Captures how spatially separated owners and renters of the same race are —
# the closest available housing-inequality-in-space analog to H_inc_nhw/nhb/his
# (within-race rent/value H^R is not feasible: B25063/B25075 by race are not
# published at tract level).

seg_tenure_within <- acs |>
  select(GEOID, CBSAFP, year, own_nhw, rent_nhw, own_nhb, rent_nhb, own_his, rent_his) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(
    H_tenure_nhw = H_binary(.x, "rent_nhw", "own_nhw"),
    H_tenure_nhb = H_binary(.x, "rent_nhb", "own_nhb"),
    H_tenure_his = H_binary(.x, "rent_his", "own_his")
  )) |>
  ungroup()


## ── RENT SEGREGATION H^R ─────────────────────────────────────────────────────
# Rank-order Theil H^R for gross rent using B25063 cash-rent dollar brackets.
# 2009/2014: rent_01–rent_21 (E003–E023); 2019/2024: rent_01–rent_24 (E003–E026).
# "No cash rent" units are excluded. Trailing NA columns (2009/2014) are dropped
# per CBSA×year before the polynomial fit to avoid corrupting cum_p at p=1.
# Cross-wave comparisons are valid: H^R is robust to bracket boundary shifts
# across vintages (same logic as H_inc; see Reardon & Bischoff 2011 p. 1112).

rent_cols <- paste0("rent_", sprintf("%02d", 1:24))

seg_rent <- acs |>
  select(GEOID, CBSAFP, year, all_of(rent_cols)) |>
  group_by(CBSAFP, year) |>
  group_modify(~ {
    active <- rent_cols[colSums(!is.na(.x[rent_cols])) > 0]
    tibble(H_rent = H_R_bracket(.x, active))
  }) |>
  ungroup()


## ── HOME VALUE SEGREGATION H^R ───────────────────────────────────────────────
# Rank-order Theil H^R for home value using B25075 dollar brackets.
# 2009/2014: val_01–val_24 (E002–E025); 2019/2024: val_01–val_26 (E002–E027).
# Universe: owner-occupied housing units. Trailing NA columns (2009/2014) are
# dropped per CBSA×year before the polynomial fit.
# Cross-wave comparability holds by the same rank-order robustness argument.

val_cols <- paste0("val_", sprintf("%02d", 1:26))

seg_val <- acs |>
  select(GEOID, CBSAFP, year, all_of(val_cols)) |>
  group_by(CBSAFP, year) |>
  group_modify(~ {
    active <- val_cols[colSums(!is.na(.x[val_cols])) > 0]
    tibble(H_val = H_R_bracket(.x, active))
  }) |>
  ungroup()


## ── VACANCY SEGREGATION H ────────────────────────────────────────────────────
# Binary Theil H for vacant vs. occupied units across tracts (B25002).
# Captures how unevenly vacancy is distributed across neighbourhoods within a metro.
# units_occ = units_tot - units_vac; pmax guards against suppression-induced negatives.

seg_vacancy <- acs |>
  mutate(units_occ = pmax(units_tot - units_vac, 0L)) |>
  select(GEOID, CBSAFP, year, units_vac, units_occ) |>
  group_by(CBSAFP, year) |>
  group_modify(~ tibble(H_vac = H_binary(.x, "units_vac", "units_occ"))) |>
  ungroup()


## ── CITY-LEVEL ACS AGGREGATES ────────────────────────────────────────────────
# All variables aggregated from tract counts to CBSA × year.
# pct_college_cbsa is NA for 2009 (B15003 not in 2005-2009 ACS5a); the {…}
# block returns NA when the denominator sums to zero (all edu_tot are NA).

acs_agg <- acs |>
  group_by(CBSAFP, year) |>
  summarise(
    pop_cbsa          = sum(pop,       na.rm = TRUE),
    pct_renter_cbsa   = sum(rent,      na.rm = TRUE) /
                        sum(rent + own, na.rm = TRUE),
    pct_nhwhite_cbsa  = sum(nhwhite,   na.rm = TRUE) /
                        sum(nhwhite_tot, na.rm = TRUE),
    pct_nhblack_cbsa  = sum(nhblack,   na.rm = TRUE) /
                        sum(nhwhite_tot, na.rm = TRUE),
    pct_hispanic_cbsa = sum(nhispanic, na.rm = TRUE) /
                        sum(nhwhite_tot, na.rm = TRUE),
    pct_college_cbsa  = {
      denom <- sum(edu_tot, na.rm = TRUE)
      if (denom == 0) NA_real_
      else sum(edu_ba_22 + edu_ba_23 + edu_ba_24 + edu_ba_25, na.rm = TRUE) / denom
    },
    rent_burden_cbsa  = sum(rb_30_35 + rb_35_40 + rb_40_50 + rb_50plus, na.rm = TRUE) /
                        sum(rb_tot, na.rm = TRUE),
    vacancy_rate_cbsa      = sum(units_vac, na.rm = TRUE) / sum(units_tot, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(CBSAFP, year) |>
  group_by(CBSAFP) |>
  mutate(pop_growth_cbsa = (pop_cbsa - lag(pop_cbsa)) / lag(pop_cbsa)) |> # pop_growth missing in first wave
  ungroup()


## ── INCOME INEQUALITY AND UNEMPLOYMENT ───────────────────────────────────────
# Calculated from PUMS microdata. hhincome_real is already CPI99-deflated.
# Weighted Gini helper (Brown formula; frequency weights)
# Sorts by x, assigns mid-CDF positions, then applies the standard formula.
wtd_gini <- function(x, w) {
  ord <- order(x)
  x   <- x[ord];  w <- w[ord] / sum(w, na.rm = TRUE)
  F   <- cumsum(w) - w / 2          # mid-CDF of each unit's weight mass
  mu  <- sum(w * x, na.rm = TRUE)
  sum(w * x * (2 * F - 1), na.rm = TRUE) / mu
}

wtd_median <- function(x, w) {
  ord <- order(x)
  x   <- x[ord]; w <- w[ord]
  x[which(cumsum(w) / sum(w) >= 0.5)[1]]
}

# Income inequality: weighted Gini of equivalised household income within CBSA × year.
# Uses HHINCOME * CPI99 (untop-coded) so the full distribution is reflected.
ineq <- pums |>
  mutate(hhincome_raw = HHINCOME * CPI99) |>
  filter(!is.na(hhincome_raw), hhincome_raw > 0) |>
  mutate(equiv_income = pmax(hhincome_raw / sqrt(NUMPREC), 1)) |>
  group_by(CBSAFP, YEAR) |>
  summarise(
    gini_inc_cbsa = wtd_gini(equiv_income, HHWT),
    .groups = "drop"
  ) |>
  rename(year = YEAR)

# Unemployment rate: unemployed / (employed + unemployed) among household heads,
# weighted by PERWT. EMPSTAT: 1 = employed, 2 = unemployed, 3 = not in labour force.
unemp <- pums |>
  filter(as.integer(EMPSTAT) %in% 1:2) |>
  group_by(CBSAFP, YEAR) |>
  summarise(
    unemp_rate_cbsa = sum(PERWT[as.integer(EMPSTAT) == 2L], na.rm = TRUE) / sum(PERWT),
    .groups = "drop"
  ) |>
  rename(year = YEAR)


## ── RENT AND HOME VALUE INEQUALITY ───────────────────────────────────────────
# Weighted Gini of gross rent (renters) and home value (owners), using PUMS
# inflation-adjusted real values (1999 USD). Neither variable is top-coded in
# dataprepPUMS.R (unlike hhincome_real), so the full distribution is reflected.
# RENTGRS is already NA for owners and VALUEH is NA for renters; only strictly
# positive values are included (the GQ == 1 filter excludes institutional units
# where VALUEH == 0 could appear).
#
# Note: the PUMS `quality` variable (z-score of rentgrs_real or valueh_real,
# standardised within YEAR × CBSA × tenure) is not suitable for Gini because
# z-scores take negative values. gini_rent_cbsa and gini_val_cbsa are the
# natural inequality counterparts to quality within each tenure group.

ineq_rent <- pums |>
  filter(renter == 1L, !is.na(rentgrs_real), rentgrs_real > 0) |>
  group_by(CBSAFP, YEAR) |>
  summarise(
    gini_rent_cbsa = wtd_gini(rentgrs_real, HHWT),
    .groups = "drop"
  ) |>
  rename(year = YEAR)

ineq_val <- pums |>
  filter(renter == 0L, !is.na(valueh_real), valueh_real > 0) |>
  group_by(CBSAFP, YEAR) |>
  summarise(
    gini_val_cbsa = wtd_gini(valueh_real, HHWT),
    .groups = "drop"
  ) |>
  rename(year = YEAR)


## ── POOLED HOUSING COST GINI ─────────────────────────────────────────────────
# Combines renter and owner housing costs on a common monthly scale.
# For owners: imputed monthly rent = valueh_real × cap_rate / 12.
# For renters: gross rent (rentgrs_real) is used directly.
# The pooled Gini captures both within-tenure inequality AND the renter/owner gap.
#
# Four cap rate variants (main spec + three robustness checks):
#   metro×year  12 × wtd_median(rentgrs_real) / wtd_median(valueh_real), from PUMS.
#               Reflects each metro's actual rent-to-price relationship per wave.
#   5 % p.a.    Standard housing-economics benchmark (fixed).
#   7 % p.a.    Higher cost-of-capital alternative (fixed).
#   national    HHWT-weighted mean of metro cap rates per wave. Removes cross-metro
#               variation in cap rates; if results hold vs. metro spec, the local
#               rent-to-price ratio is not driving findings.

# Metro×year PUMS weighted medians
med_rent_pums <- pums |>
  filter(renter == 1L, !is.na(rentgrs_real), rentgrs_real > 0) |>
  group_by(CBSAFP, YEAR) |>
  summarise(med_rent = wtd_median(rentgrs_real, HHWT), .groups = "drop")

med_val_pums <- pums |>
  filter(renter == 0L, !is.na(valueh_real), valueh_real > 0) |>
  group_by(CBSAFP, YEAR) |>
  summarise(med_val = wtd_median(valueh_real, HHWT), .groups = "drop")

cap_rates <- med_rent_pums |>
  left_join(med_val_pums, by = c("CBSAFP", "YEAR")) |>
  mutate(cap_rate_metro = 12 * med_rent / med_val)

# Year-specific national cap rate: HHWT-weighted mean across metros
cap_rate_natl <- cap_rates |>
  left_join(
    pums |>
      group_by(CBSAFP, YEAR) |>
      summarise(tot_hhwt = sum(HHWT, na.rm = TRUE), .groups = "drop"),
    by = c("CBSAFP", "YEAR")
  ) |>
  group_by(YEAR) |>
  summarise(
    cap_rate_natl = weighted.mean(cap_rate_metro, tot_hhwt, na.rm = TRUE),
    .groups = "drop"
  )

# Pooled Gini for all four specs
gini_housing <- pums |>
  filter(
    (renter == 1L & !is.na(rentgrs_real) & rentgrs_real > 0) |
    (renter == 0L & !is.na(valueh_real)  & valueh_real  > 0)
  ) |>
  left_join(cap_rates   |> select(CBSAFP, YEAR, cap_rate_metro), by = c("CBSAFP", "YEAR")) |>
  left_join(cap_rate_natl, by = "YEAR") |>
  mutate(
    hcost_metro = if_else(renter == 1L, rentgrs_real, valueh_real * cap_rate_metro / 12),
    hcost_5pct  = if_else(renter == 1L, rentgrs_real, valueh_real * 0.05 / 12),
    hcost_7pct  = if_else(renter == 1L, rentgrs_real, valueh_real * 0.07 / 12),
    hcost_natl  = if_else(renter == 1L, rentgrs_real, valueh_real * cap_rate_natl / 12)
  ) |>
  group_by(CBSAFP, YEAR) |>
  summarise(
    gini_housing_cbsa      = wtd_gini(hcost_metro[!is.na(hcost_metro)], HHWT[!is.na(hcost_metro)]),
    gini_housing_cbsa_5pct = wtd_gini(hcost_5pct,  HHWT),
    gini_housing_cbsa_7pct = wtd_gini(hcost_7pct,  HHWT),
    gini_housing_cbsa_natl = wtd_gini(hcost_natl,  HHWT),
    .groups = "drop"
  ) |>
  rename(year = YEAR)


## ── MERGE AND SAVE ────────────────────────────────────────────────────────────

cbsa_controls <- seg_income |>
  left_join(seg_income_p50,   by = c("CBSAFP", "year")) |>
  left_join(seg_income_race,      by = c("CBSAFP", "year")) |>
  left_join(seg_income_race_p50, by = c("CBSAFP", "year")) |>
  left_join(seg_decomp,       by = c("CBSAFP", "year")) |>
  left_join(seg_tenure_race,  by = c("CBSAFP", "year")) |>
  left_join(seg_race,         by = c("CBSAFP", "year")) |>
  left_join(seg_tenure,        by = c("CBSAFP", "year")) |>
  left_join(seg_tenure_within, by = c("CBSAFP", "year")) |>
  left_join(seg_race_multi,    by = c("CBSAFP", "year")) |>
  left_join(seg_rent,       by = c("CBSAFP", "year")) |>
  left_join(seg_val,        by = c("CBSAFP", "year")) |>
  left_join(seg_vacancy,    by = c("CBSAFP", "year")) |>
  left_join(acs_agg,        by = c("CBSAFP", "year")) |>
  left_join(ineq,           by = c("CBSAFP", "year")) |>
  left_join(unemp,          by = c("CBSAFP", "year")) |>
  left_join(ineq_rent,      by = c("CBSAFP", "year")) |>
  left_join(ineq_val,       by = c("CBSAFP", "year")) |>
  left_join(gini_housing,   by = c("CBSAFP", "year"))


cbsa_controls <- cbsa_controls |>
  left_join(acs |> distinct(CBSAFP, CBSA_name, cbsa_name_short), by = "CBSAFP")

write_parquet(cbsa_controls, file.path(data_dir, "cbsa_vars.parquet"))

pums_analysis <- pums |>
  left_join(cbsa_controls |> select(-CBSA_name, -cbsa_name_short),
            by = c("CBSAFP", "YEAR" = "year")) |>
  left_join(cap_rates |> select(CBSAFP, YEAR, cap_rate_metro), by = c("CBSAFP", "YEAR")) |>
  mutate(
    # Imputed annual cost-to-income ratio for owners (CPI99 cancels; owners with
    # positive income and value). cap_rate_metro = 12 * med_rent / med_val, so
    # valueh_real * cap_rate_metro is the annualised imputed housing cost.
    cost_to_inc = if_else(
      renter == 0L & hhincome_real > 0 & !is.na(valueh_real) & valueh_real > 0,
      valueh_real * cap_rate_metro / hhincome_real,
      NA_real_
    )
  )

write_parquet(pums_analysis, file.path(data_dir, "pums_analysis.parquet"))


## ── MISSING VALUE SUMMARY ────────────────────────────────────────────────────

na_summary <- cbsa_controls |>
  summarise(across(everything(), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") |>
  mutate(pct_missing = round(100 * n_missing / nrow(cbsa_controls), 1)) |>
  filter(n_missing > 0)

print(na_summary, n = Inf)

# pct_college_cbsa and pop_growth_cbsa have missings (n = 100, pct = 25)
# -> they are missing in one ACS period each
# population growth would need population before 2005, NA due to lag
# education missing in 2009 ACS
# all other variables have no missings at all!
