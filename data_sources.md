# Data Sources for Empirical Testing of Model Hypotheses

This document summarizes datasets suited to test the hypotheses derived from the
agent-based model (see `abm/b_hypotheses/`). The hypotheses operate at three levels:

- **City level**: cross-city variation in segregation and inequality (H1–H9)
- **Neighborhood level**: stability of neighborhood composition over time (H10)
- **Individual level**: residential mobility moderated by income and city-level segregation (H11–H15)

The reference dataset for city-level and individual-level hypotheses is the
**American Community Survey (ACS)**, already used in `empirics/dataprep_ACS.R`.

---

## Key data requirements by hypothesis group

| Group | Required variables |
|---|---|
| H1–H9 (city level) | Neighborhood-level income, status, rent, housing quality; multiple cities; segregation and inequality measures |
| H10 (NB stability) | Longitudinal neighborhood composition panel |
| H11–H15 (individual) | Residential moves (ideally voluntary vs. involuntary), household income, city-level segregation context |

---

## US Datasets

### 1. Longitudinal Tract Data Base (LTDB)

**What it is:** Harmonized tract-level dataset produced by Logan, Xu & Stults (2014,
*The Professional Geographer*, 66:412–420) at Brown University's Diversity and Disparities
project. Decennial census data for 1970, 1980, 1990, 2000, and 2010, plus ACS 5-year
estimates for 2008–2012 and 2013–2017, all normalized to **2010 tract boundaries** via
block-level areal interpolation.

**Variables:** Population, race/ethnicity, poverty rate, median household income, housing
tenure, housing value, vacancy rate. The variable set covers the major demographic and
socioeconomic indicators from each census and the two ACS supplements.

**Hypotheses:** Best suited for H10 (neighborhood stability): provides up to 50 years of
neighborhood composition change on a consistent geography. Useful background for H1–H9 as
a longer baseline for segregation trends.

**Caveats:**

- *Boundary coverage stops at 2020.* Data are normalized to 2010 tract boundaries.
  The 2015–2019 and 2020–2024 ACS waves (using 2010- and 2020-vintage tracts
  respectively) are not included. Extending the series to 2019 or 2024 requires applying
  NHGIS crosswalk files (2010→2020) independently.
- *No income bracket distributions.* LTDB provides median income and poverty rates, not
  the bracket-count tables (B19001 etc.) needed to compute H^R income segregation. The
  segregation indices in `SEHTestACS3_citylevel.R` cannot be replicated from LTDB alone;
  the NHGIS ACS extracts remain necessary for those.
- *Interpolation error.* Normalizing older tract data to 2010 boundaries uses
  block-level population weights, which introduces measurement error wherever tract
  boundaries changed substantially between vintages. Error is largest in fast-growing
  areas where many tracts were split.
- *Decennial gaps.* Between 1970 and 2010 the data are 10-year snapshots. The two ACS
  supplements (2008–2012, 2013–2017) densify the recent period but still leave the
  2017–present window uncovered.

**Relationship to current pipeline:** LTDB and the NHGIS ACS extracts are complements.
LTDB extends the time series backward for variables it covers; the NHGIS ACS extracts
provide the bracket-level data needed for the full set of segregation indices and extend
the series to 2024.

**Access:** Free, no application required.
- https://s4.ad.brown.edu/projects/diversity/Researcher/LTDB.htm

---

## European Datasets

### 1. Eurostat Census 2021 Population Grids

**What it is:** All 30 European countries published harmonized 1 km² grid data for the
2021 census round (Eurostat GISCO). A 2011 grid is available for comparison.

**Variables per grid cell:** Population, sex, age groups, household composition, country
of birth, educational attainment, employment status, number of dwellings.

**Key limitation:** No income or rent at grid level.

**Hypotheses:** Good for H1–H5 (segregation patterns across cities) if income is sourced
elsewhere. A 2024/25 study computed segregation indices for 717 Functional Urban Areas
across 30 countries using this data.

**Access:** Fully public, no application.
- Eurostat GISCO: https://ec.europa.eu/eurostat/web/gisco/geodata/population-distribution/population-grids

---

### 2. Eurostat Urban Audit

**What it is:** City-level statistics for 800+ European cities, updated every ~3 years.
Contains 100+ indicators on population, housing, income, employment, education.

**Key limitation:** No distributional measures (no Gini, no segregation indices). Sub-city
district data is sparse and inconsistent across countries.

**Hypotheses:** Useful as a control variable database for H6–H9. Not suited for
segregation or individual-level analyses.

**Access:** Fully public.
- https://ec.europa.eu/regional_policy/policy/themes/urban-development/audit_en

---

### 3. EU-SILC (European Union Statistics on Income and Living Conditions)

**What it is:** Eurostat's flagship comparative household survey covering all EU-27
countries plus Norway, Iceland, Switzerland. Annual cross-section and 4-year rotating
panel (~5,000–15,000 households per country per year).

**Variables:** Household disposable income, housing tenure, monthly rent, housing
deprivation indicators (overcrowding, leaking roof, damp, no bath/toilet), housing cost
overburden, education, occupation.

**Key limitation:** Geographic identifiers in the Scientific Use File go only to NUTS-1
(large macro-regions) or a 3-category urban/rural variable. No city or neighborhood
identifiers. Cross-city segregation analysis is not possible.

**Hypotheses:** Good for H6–H9 at the cross-country level (income inequality vs. housing
deprivation). Partial for H11–H15 (individual mobility can be tracked across 4 panel
waves but without city-level segregation context).

**Access:** Free for academic researchers via Eurostat microdata portal.
- https://ec.europa.eu/eurostat/web/microdata/european-union-statistics-on-income-and-living-conditions

---

### 4. Nordic Register Data (Sweden, Denmark, Finland, Norway)

**What it is:** Full-population administrative register systems linking individuals
across income tax, property, education, employment, and address registers. Annual panel
going back to the 1980s/90s. Fine neighborhood geography (e.g., Swedish DeSO ~700–2,700
residents; Danish small areas; Norwegian grunnkrets ~200 residents).

**Variables:** Individual disposable income (from tax registers), housing tenure, dwelling
characteristics, education, employment, address history (enabling annual moves). Denmark
also has a Rent Register (from 2013).

**Key limitation:** Move reasons (voluntary vs. involuntary) are not available in
administrative data. Access often requires national institutional affiliation.

**Hypotheses:** Excellent for all of H1–H10. Best European option for H10 (neighborhood
stability). For H11–H15: excellent for income and mobility, but cannot distinguish
voluntary from involuntary moves without survey linkage.

**Access:** Restricted; usually requires collaboration with a national institution.
- Sweden (SCB MONA): https://www.scb.se/en/services/ordering-data-and-statistics/microdata/
- Denmark (Statistics Denmark): https://www.dst.dk/en/TilSalg/data-til-forskning

---

### 5. Netherlands CBS Microdata

**What it is:** Full-population register data for the Netherlands. Individual address
histories from 1994, linked to building register (BAG: size, construction year), income
from tax records, neighborhood codes (buurt ~1,500 residents, wijk ~7,500 residents).

**Variables:** Individual income and wealth (tax registers), housing tenure, dwelling type
and size, annual residential moves, neighborhood identifiers.

**Key limitation:** Move reasons not available. Institutional access contract required.

**Hypotheses:** Excellent for H1–H10. For H11–H15: moves are observable annually but
voluntary/involuntary distinction requires survey linkage (e.g., LISS panel).

**Access:** Via CBS Microdata Services / ODISSEI.
- https://www.cbs.nl/en-gb/our-services/customised-services-microdata/microdata-conducting-your-own-research
- https://odissei-data.nl/facility/microdata-access/

---

### 6. German SOEP (Socio-Economic Panel Study)

**What it is:** Germany's major longitudinal household panel, ~20,000 households
annually since 1984, maintained by DIW Berlin.

**Variables:** Annual household income, monthly net rent, housing type and size, housing
tenure, residential mobility between waves, **reason for last move** (including
involuntary/forced relocation categories), education, occupational prestige (ISEI/SIOPS),
neighborhood satisfaction.

**Key limitation:** Geographic identifiers in the standard distribution are only at
Bundesland level. Finer regional data (Kreis level, geocoordinates) requires an
additional restricted-access contract and on-site use at DIW Berlin's RDC. Sample size
(~20,000 HH) is insufficient for computing neighborhood-level segregation estimates.

**Hypotheses:** SOEP's unique strength is H11–H15: it is the only major European dataset
that distinguishes voluntary from involuntary residential moves. With the geocoded
regional add-on, city-level segregation context can be linked to individuals. For H1–H10,
SOEP must be combined with external spatial data.

**Access:** Free for academic researchers; online application via DIW.
Additional regional data: separate data protection agreement required.
- https://www.diw.de/en/diw_01.c.683748.en/regional_data.html

---

### 7. UK Understanding Society (UKHLS)

**What it is:** UK's major household panel, ~40,000 households annually since 2009
(with predecessor BHPS from 1991). Maintained at University of Essex.

**Variables:** Housing tenure, monthly rent, housing type, number of rooms, overcrowding,
residential mobility between waves, reason for move (limited categories), household
income, education, occupation. With **Special Licence**, LSOA identifiers (~1,500
residents) enable linkage to the Index of Multiple Deprivation and local house price data.

**Key limitation:** Sample too small for direct neighborhood-level segregation estimates.
Move reasons are limited compared to SOEP.

**Hypotheses:** Good for H11–H15 in the UK context (30+ years of panel data with BHPS
extension). Moderate for H1–H9 with LSOA linkage to external area statistics.

**Access:** Standard (open) access free via UK Data Service; Special Licence (LSOA codes)
requires separate application.
- https://www.understandingsociety.ac.uk/documentation/linked-data/geographical-identifiers/

---

### 8. French INSEE RP + FIDELI

**What it is:** INSEE's rolling annual census (Recensement de la Population) provides
IRIS-level aggregates (~2,000 residents, ~50,000 IRIS units nationally). FIDELI is a
linked administrative dataset connecting all French individuals to dwellings and income
from tax records — covering the full French population.

**Variables (IRIS level, public):** Housing type, tenure, number of rooms, household
composition by income quartile. **FIDELI (restricted):** individual income, dwelling
characteristics, annual address history.

**Hypotheses:** Good for H1–H9 in France. FIDELI enables H10–H15 similarly to Nordic
registers. An under-utilized resource in comparative segregation research.

**Access:** IRIS aggregates free from INSEE. FIDELI via CASD (Centre d'Accès Sécurisé
aux Données).
- https://www.insee.fr/en/metadonnees/source/serie/s1172

---

### 9. BBSR Raumbeobachtung

**What it is:** The Federal Institute for Research on Building, Urban Affairs and Spatial
Development (BBSR) maintains a spatial monitoring system consisting of several products:

#### 9a. INKAR (Indikatoren und Karten zur Raum- und Stadtentwicklung)

~600 harmonized regional indicators from 1995 to present, covering the full hierarchy
from federal level to Gemeindeverbände (~4,500 units). Open data.

**Key variables:** Medianeinkommen (median income, primarily at Kreis level), Kaufkraft,
Angebotsmieten (offered rents at Kreis level, from ~2010, sourced from IDN ImmoDaten),
housing stock variables, SGB II recipient rates, unemployment, migration balance,
population structure.

**Key limitation:** Finest public spatial level is Gemeindeverbände/Kreise (~400 units).
No within-city neighborhood data. No Gini coefficients (must be computed externally).

**Hypotheses:** Moderate for H6–H9 (cross-city income vs. rent inequality in Germany).
Weak for H1–H5 (too coarse for within-city segregation). Not suited for H10–H15.

**R packages:** `inkr` (full DB into DuckDB), `inkaR` (CRAN), `bonn` (CRAN, API-based).

**Access:** Open data, no application required.
- https://www.inkar.de

#### 9b. Innerstädtische Raumbeobachtung (IRB)

**What it is:** Sub-municipal dataset for 55 large German cities, ~3,000 Stadtteile
(neighborhoods), annual from 2002.

**Variables:** 400+ characteristics including population by age/nationality/migration
background, **internal residential migrations (Binnenwanderungen)**, SGB II rates,
employment, housing inventory.

**Key limitation:** No income data at Stadtteil level. No individual-level data.
Restricted access.

**Hypotheses:** Good for H1–H5 (neighborhood-level social composition in 55 cities),
H6–H9 with income proxied by SGB II rates, H10 (neighborhood stability via annual
migration flows). Not suited for H11–H15.

**Access:** Email project description (~1 page) to stadtbeobachtung@bbr.bund.de.
Data provided as Excel files; no charge.

#### 9c. Laufende Bevölkerungsumfrage

Annual population survey since 1985 on housing, residential mobility, neighborhood
perceptions, and housing satisfaction. Individual-level. Cumulated dataset 2000–2010
available via GESIS (ZA5611).

---

### 10. RWI-GEO-RED (Real Estate Data for Germany)

**What it is:** Listing-level micro-data from ImmobilienScout24 (~50–60% market share),
prepared by FDZ Ruhr at RWI. Four sub-datasets: apartments/houses for rent/sale.
Coverage: June 2007 – December 2025.

**Variables per listing:** Net cold rent (`mietekalt`), warm rent, size (m²), number of
rooms, floor, construction year (`baujahr`), last renovation, property condition
(`objektzustand`, 11-category), equipment quality (`ausstattung`: simple/normal/
upscale/luxury), energy efficiency class and consumption value, heating type. Geographic
identifiers: 1 km² INSPIRE grid cell, postal code, municipality AGS, Kreis AGS. Exact
coordinates only on-site.

**Key limitation:** Supply-side only (new-letting market). Misses social housing,
cooperative housing, and cheap incumbent tenancies. No tenant/household data. Geocoding
incomplete before ~2015.

**Hypotheses:** Good for H1 (compare within-cell variance of rent/quality to income
variance), H6–H9 (compute city-level rent Ginis and housing quality distributions,
correlate with income inequality). Partial for H10 (neighborhood rent trajectories).
Not suited for H11–H15.

**DOIs:** Apartments for rent: `10.7807/IMMO:RED:WM:SUF:V14`; for sale:
`10.7807/IMMO:RED:WK:SUF:V14`.
Campus file (15 cities): `10.7807/IMMO:RED:PANEL:V7`.
Public hedonic price indices (REDX): `10.7807/IMMO:REDX:PUF:V16`.

**Access:** Free SUF via FDZ Ruhr, ~10 working days. EU institutional affiliation required.
R cleaning scripts: https://github.com/eyayaw/cleaning-RWI-GEO-RED
- https://fdz.rwi-essen.de/en

---

### 11. RWI-GEO-GRID (Socio-Economic Data on Grid Level)

**What it is:** Annual 1 km² grid-level socioeconomic panel for all of Germany, produced
by FDZ Ruhr from commercial data by microm (fusing credit records, postal data, vehicle
registrations, official statistics). Uses the same INSPIRE grid as RWI-GEO-RED, enabling
direct merge by grid cell ID and year. Coverage: 2005, then 2009–2023 annually.

**Variables (modular packages):**
- **Kaufkraft** (purchasing power): estimated net household income in EUR (absolute,
  per capita, per household, index, classes) — best available annual income proxy at
  1 km² in Germany
- Unemployment rate
- Payment default / credit risk (9 classes)
- Household structure (singles/couples/families with children)
- Share of foreign-origin households (`Ausländeranteil`, name-based)
- `Ethno`: finer inferred national-origin breakdown (name-based)
- Age structure, sex, total population
- Building type (7 categories)

**Key limitations:** Variables are modeled estimates, not official registry data. Ethnicity
measure is name-based (does not capture second-generation migrants with German names,
naturalized citizens). No education or occupation variables. Cells with <10 households
are anonymized in the off-site SUF. Costs €200 + VAT.

**Hypotheses:** Good for H1 (Kaufkraft variance within cells over time), H6–H9 (annual
Kaufkraft Gini by city, combined with rent from RED), H10 (annual neighborhood
composition panel). Not suited for H11–H15.

**DOI (V15 off-site SUF):** `10.7807/MICROM:SUF:V15`

**Access:** Same FDZ Ruhr application as RWI-GEO-RED; costs €200 + VAT.
- https://fdz.rwi-essen.de/en

---

## Summary: Recommended Dataset Combinations

### For Germany (deepest coverage)

| Hypothesis group | Recommended data |
|---|---|
| H1–H9 (city level, inc.–housing ineq.) | RWI-GEO-RED + RWI-GEO-GRID (1 km² annual panel) + Zensus 2022 (housing stock, official demographics) |
| H1–H5 (segregation patterns, 55 cities) | BBSR IRB (Stadtteil level, annual from 2002) |
| H10 (neighborhood stability) | BBSR IRB or RWI-GEO-GRID (annual composition change) |
| H11–H15 (individual mobility, vol./invol.) | SOEP + regional geocoded add-on (only dataset distinguishing voluntary from involuntary moves) |

### For cross-European comparison

| Hypothesis group | Recommended data |
|---|---|
| H1–H9 (cross-country) | Eurostat Census 2021 Population Grids (segregation indices for 717 FUAs) + Urban Audit (controls) |
| H6–H9 (income–housing ineq.) | EU-SILC (cross-country income and housing deprivation, country level) |
| H10 (NB stability) | Nordic registers or Dutch CBS (full population, annual, fine geography) |
| H11–H15 (individual mobility) | Nordic/Dutch registers (moves, income) + note: vol./invol. distinction unavailable |

### Key trade-offs

- **Scale vs. depth**: ACS provides the best combination of sample size, geographic
  detail, and cross-city coverage. No single European dataset matches all three
  simultaneously.
- **Vol. vs. invol. moves**: Only SOEP (Germany) has explicit move-reason categories
  covering involuntary relocation. Nordic/Dutch registers record moves but not reasons.
- **Income at neighborhood level**: RWI-GEO-GRID (annual, modeled) or Nordic/Dutch
  registers (annual, official) are the best options. Zensus 2022 provides a single
  cross-section at 1 km².
- **Status vs. income**: The income–status segregation distinction (H2, H3) is the
  hardest to operationalize in Europe. Education at neighborhood level requires census
  data (Zensus 2022 at municipality level; Nordic registers at fine geography). Occupational
  prestige requires individual survey data (SOEP, UKHLS).
