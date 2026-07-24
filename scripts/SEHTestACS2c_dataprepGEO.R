################################################################################
### Testing the Housing Market Model using ACS and PUMS Data
### Data Preparation: Attach Tract Geometries to ACS Data
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Reads acs_top100.parquet (produced by SEHTestACS2a_dataprepACS.R) and merges
# tract geometries from the NHGIS shapefile extract.
#
# Boundary vintages:
#   2010-vintage (tl2010_us_tract): waves 2009, 2014, 2019
#   2020-vintage (tl2020_us_tract): wave 2024
#
# Output: acs_top100_geo.parquet (sfarrow / GeoParquet)


## ── SETUP ────────────────────────────────────────────────────────────────────

library(ipumsr)
library(nanoparquet)
library(dplyr)
library(sf)
library(sfarrow)

data_dir   <- "./data/ACS/"
output_dir <- "./data/"
shp_zip    <- list.files(data_dir, pattern = "nhgis.*shape.*\\.zip$", full.names = TRUE)


## ── 1. LOAD ACS DATA ─────────────────────────────────────────────────────────

acs <- read_parquet(file.path(output_dir, "acs_top100.parquet"))


## ── 2. ATTACH GEOMETRIES ─────────────────────────────────────────────────────

# 2010-vintage boundaries (waves 2009, 2014, 2019); 2020-vintage (wave 2024)
geom_2010 <- read_ipums_sf(shp_zip, file_select = contains("tl2010_us_tract")) |>
  select(fips11 = GEOID10) |>
  st_transform(4326)

geom_2020 <- read_ipums_sf(shp_zip, file_select = contains("tl2020_us_tract")) |>
  select(fips11 = GEOID) |>
  st_transform(4326)

# Plain 11-digit FIPS for joining (strip NHGIS prefix "14000US" / "1400000US")
acs_fips <- acs |> mutate(fips11 = sub("^.*US", "", GEOID))

acs_sf <- bind_rows(
  acs_fips |> filter(year != 2024) |> left_join(as_tibble(geom_2010), by = "fips11"),
  acs_fips |> filter(year == 2024) |> left_join(as_tibble(geom_2020), by = "fips11")
) |>
  select(-fips11) |>
  st_as_sf()

rm(geom_2010, geom_2020, acs_fips)


## ── 3. SAVE ──────────────────────────────────────────────────────────────────

st_write_parquet(acs_sf, file.path(output_dir, "acs_top100_geo.parquet"))
