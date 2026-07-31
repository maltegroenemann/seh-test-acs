# SEHTestACS

Empirical test of a socio-economic agent-based model (ABM) of residential segregation, neighbourhood change, and housing inequality, using US American Community Survey (ACS) data. The analysis covers the top 100 Core-Based Statistical Areas (CBSAs) by 2024 population in the contiguous United States, across four non-overlapping ACS 5-year waves (2005–2009, 2010–2014, 2015–2019, 2020–2024).

## Research Questions

The project tests city- and individual-level hypotheses derived from the ABM:

- Are rents and housing values more unequally distributed across space within cities than household income?
- Does income segregation amplify the relationship between income inequality and housing cost inequality across metros?
- Does income segregation steepen the income–housing quality gradient for individual households?
- Does income segregation moderate the relationship between household income and housing cost burden?

## Pipeline

Scripts must be run in order. Phases 1 and 2 are compute-intensive and are submitted as SLURM batch jobs on the HELIX HPC cluster via `SEHTestACS_dataprep.sh` and `SEHTestACS_analysis.sh`.

```
Phase 1 – Download
  SEHTestACS1a_downloadACS.R    ACS tract-level tables via IPUMS NHGIS API
  SEHTestACS1b_downloadPUMS.R   ACS PUMS microdata via IPUMS USA API

Phase 2 – Data preparation
  SEHTestACS2a_dataprepACS.R    Clean and aggregate tract-level ACS data
                                → data/acs_top100.parquet
  SEHTestACS2b_dataprepPUMS.R   Clean PUMS; link PUMAs to CBSAs; derive
                                household-level variables
                                → data/pums_hh.parquet
  SEHTestACS2c_dataprepGEO.R    Attach tract geometries (optional, for
                                spatial analysis)
                                → data/acs_top100_geo.parquet

Phase 3 – City-level aggregation
  SEHTestACS3_citylevel.R       Compute CBSA × year segregation indices,
                                inequality measures, and controls; join to
                                PUMS
                                → data/cbsa_vars.parquet
                                → data/pums_analysis.parquet

Phase 4 – Analysis
  SEHTestACS4_analyses.Rmd      Individual- and city-level regression
                                analyses (fixest); rendered to HTML
                                → results/SEHTestACS4_analyses.html
```

## Data

Raw data are not included in this repository. They are obtained from two sources, both requiring a free [IPUMS](https://www.ipums.org) account and API key.

| Source | Script | What is downloaded |
|--------|--------|--------------------|
| IPUMS NHGIS | `SEHTestACS1a_downloadACS.R` | ACS 5-year tract-level tables (demographics, income brackets, tenure, rent brackets, home value brackets, vacancy, education) for 4 waves |
| IPUMS USA | `SEHTestACS1b_downloadPUMS.R` | ACS PUMS microdata (household heads in standard housing units), 4 waves |

MABLE/Geocorr crosswalk files (PUMA → County, three vintages) must be downloaded manually from the [Missouri Census Data Center](https://mcdc.missouri.edu/applications/geocorr.html) and placed in `data/PUMS/`.

### Intermediate data files

| File | Unit | Contents |
|------|------|----------|
| `data/acs_top100.parquet` | Tract × year | Tract-level ACS aggregates for top-100 CBSAs |
| `data/acs_top100_geo.parquet` | Tract × year | Same, with tract polygon geometries (GeoParquet) |
| `data/pums_hh.parquet` | Household × year | Cleaned PUMS microdata with derived variables |
| `data/cbsa_vars.parquet` | CBSA × year | Segregation indices, inequality measures, controls |
| `data/pums_analysis.parquet` | Household × year | PUMS joined with CBSA-level variables |

## Key methodological choices

**Sample.** Top 100 CBSAs by 2024 population; contiguous US only; 2020-vintage CBSA definitions throughout.

**Segregation indices.** Rank-order income segregation H^R (Reardon & Bischoff 2011) is the primary measure. It is computed from income bracket counts by fitting a 4th-degree polynomial to bracket-level Theil H values and integrating. This approach is robust to bracket boundary shifts across waves. Binary Theil H (Reardon & Firebaugh 2002) is used for two-category splits (owner/renter, NH-White/NH-Black, occupied/vacant).

**Income.** All monetary values deflated to 1999 USD using the wave-specific CPI99 multiplier provided by IPUMS. Household income is equivalised using the OECD square-root scale and log-transformed. Income is top-coded at the within-CBSA × year 99th percentile.

**Housing quality.** Gross monthly rent (renters) and self-reported home value (owners) are z-standardised within YEAR × CBSAFP × tenure. This removes between-metro and between-period price level differences and makes the FEs redundant in individual-level regressions. A robustness version (`quality_rc`) standardises renters using only recent movers (moved in within the past two years) to mitigate rent control distortions.

**Housing cost burden.** Three cost-to-income proxies: `rent_to_inc` = (monthly rent × 12) / annual income (renters); `val_to_inc` = home value / annual income (owners, stock/flow); `cost_to_inc` = home value × metro cap rate / annual income (owners, flow/flow, directly comparable to `rent_to_inc`). The metro cap rate is the ratio of median gross rent to median home value within each CBSA × year.

**Regression.** Fixed effects OLS via `fixest`. Standard errors are clustered by CBSA throughout; two-way clustering on year is not used because only four survey waves are available.

## Requirements

- R ≥ 4.4
- IPUMS API key stored in `.Renviron` as `IPUMS_API_KEY`
- Key packages: `ipumsr`, `tigris`, `nanoparquet`, `dplyr`, `tidyr`, `sf`, `sfarrow`, `fixest`, `modelsummary`, `ggplot2`, `latex2exp`
- 50 GB RAM for data preparation; ~2.5 GB disk for intermediate Parquet files

## References

Reardon, S. F., & Bischoff, K. (2011). Income inequality and income segregation. *American Journal of Sociology*, 116(4), 1092–1153.

Reardon, S. F., & Firebaugh, G. (2002). Measures of multigroup segregation. *Sociological Methodology*, 32(1), 33–67.
