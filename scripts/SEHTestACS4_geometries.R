################################################################################
### Testing the Housing Market Model using ACS and PUMS Data
### Data Preparation: Attach Tract Geometries to ACS Data
### Author: Malte Grönemann
### R version 4.5.3 (2026-03-11) on Fedora Linux 43 (x86_64)
################################################################################


## ── DOCUMENTATION ────────────────────────────────────────────────────────────
#
# Reads acs_metro.parquet (produced by SEHTestACS2a_dataprepACS.R) and merges
# simplified tract geometries from the NHGIS shapefile extract.
#
# Boundary vintages (tract-level):
#   2010-vintage (tl2010_us_tract): waves 2009, 2014, 2019
#   2020-vintage (tl2020_us_tract): wave 2024
#
# Tract geometries are simplified with ms_simplify (keep = 5 % of vertices)
# before joining. The mapshaper algorithm preserves shared boundaries between
# adjacent tracts, preventing gaps; keep_shapes = TRUE prevents small tracts
# from collapsing to empty polygons.
#
# CBSA polygons are read from cbsa_2020.gpkg (downloaded in
# SEHTestACS1a_downloadACS.R) — pre-dissolved cartographic boundary files,
# already simplified, no internet access required at runtime.
#
# Outputs:
#   acs_metro_geo.parquet    tract-level ACS data with simplified tract geometries
#   metro_vars_geo.parquet   metro_vars with CBSA boundary polygon column


## ── SETUP ────────────────────────────────────────────────────────────────────

library(ipumsr)
library(arrow)
library(dplyr)
library(sf)
library(geoarrow)
library(rmapshaper)
library(parallel)

# File Paths
# TODO for replication: change paths
# local paths for development
#acs_dir  <- "~/Projects/SEHTestACS/data/ACS/"
#data_dir <- "~/Projects/SEHTestACS/data/"
# paths at HELIX HPC
acs_dir  <- "./data/ACS/"
data_dir <- "./data/"

shp_zip <- list.files(acs_dir, pattern = "nhgis.*shape.*\\.zip$", full.names = TRUE)


## ── 1. LOAD DATA ─────────────────────────────────────────────────────────────

acs        <- read_parquet(file.path(data_dir, "acs_metro.parquet"))
metro_vars <- read_parquet(file.path(data_dir, "metro_vars.parquet"))

# Plain 11-digit FIPS for joining (strip NHGIS prefix "14000US" / "1400000US")
acs_fips <- acs |> mutate(fips11 = sub("^.*US", "", GEOID))

fips_pre2024 <- acs_fips |> filter(year != 2024) |> pull(fips11) |> unique()
fips_2024    <- acs_fips |> filter(year == 2024)  |> pull(fips11) |> unique()


## ── 2. LOAD AND SIMPLIFY TRACT GEOMETRIES ────────────────────────────────────
# ms_simplify is the main bottleneck. Boundary continuity only matters within a
# CBSA for these visualisations, so I split by metro_area and simplify each
# CBSA's tracts independently in parallel.

# On SLURM, detectCores() reads the host's total CPUs, not the allocated ones.
# Read the allocation directly; fall back to detectCores()-1 for interactive use.
n_cores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK",
                                  unset = as.character(min(detectCores() - 1L, 16L))))

simplify_cbsa <- function(x) ms_simplify(x, keep = 0.05, keep_shapes = TRUE)

# fips11 → metro_area lookups (acs_fips retains all acs columns incl. metro_area)
metro_lookup_pre2024 <- acs_fips |> filter(year != 2024) |> distinct(fips11, metro_area)
metro_lookup_2024    <- acs_fips |> filter(year == 2024)  |> distinct(fips11, metro_area)

geom_2010 <- read_ipums_sf(shp_zip, file_select = contains("tl2010_us_tract")) |>
  select(fips11 = GEOID10) |>
  filter(fips11 %in% fips_pre2024) |>
  st_transform(4326) |>
  left_join(metro_lookup_pre2024, by = "fips11") |>
  group_split(metro_area) |>
  mclapply(simplify_cbsa, mc.cores = n_cores) |>
  bind_rows() |>
  select(fips11)

geom_2020 <- read_ipums_sf(shp_zip, file_select = contains("tl2020_us_tract")) |>
  select(fips11 = GEOID) |>
  filter(fips11 %in% fips_2024) |>
  st_transform(4326) |>
  left_join(metro_lookup_2024, by = "fips11") |>
  group_split(metro_area) |>
  mclapply(simplify_cbsa, mc.cores = n_cores) |>
  bind_rows() |>
  select(fips11)


## ── 3. JOIN GEOMETRIES TO ACS ─────────────────────────────────────────────────

acs_sf <- bind_rows(
  acs_fips |> filter(year != 2024) |> left_join(as_tibble(geom_2010), by = "fips11"),
  acs_fips |> filter(year == 2024) |> left_join(as_tibble(geom_2020), by = "fips11")
) |>
  select(-fips11) |>
  st_as_sf() |>
  st_make_valid() |>
  mutate(lon = st_coordinates(st_centroid(geometry))[, 1],
         lat = st_coordinates(st_centroid(geometry))[, 2])

rm(geom_2010, geom_2020, acs_fips)


## ── 4. CBSA POLYGONS → metro_vars_geo ────────────────────────────────────────
# Read pre-dissolved cartographic CBSA boundaries saved by the download script.
# Centroid lon/lat added for map label placement.

cbsa_geo <- read_sf(file.path(acs_dir, "cbsa_2020.gpkg")) |>
  select(metro_area = GEOID) |>
  filter(metro_area %in% metro_vars$metro_area)

cbsa_cent <- st_centroid(cbsa_geo)
metro_centroids <- cbsa_geo |>
  st_drop_geometry() |>
  mutate(lon = st_coordinates(cbsa_cent)[, 1],
         lat = st_coordinates(cbsa_cent)[, 2])

metro_vars_geo <- metro_vars |>
  left_join(as_tibble(cbsa_geo), by = "metro_area") |>
  left_join(metro_centroids, by = "metro_area") |>
  st_as_sf()


## ── 5. SAVE DATA ─────────────────────────────────────────────────────────────

as_arrow_table(acs_sf)         |> write_parquet(file.path(data_dir, "acs_metro_geo.parquet"))
as_arrow_table(metro_vars_geo) |> write_parquet(file.path(data_dir, "metro_vars_geo.parquet"))
