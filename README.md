# GTFS vs TDM

Compares the base-year transit network in the Wasatch Front regional travel demand model (TDM) against published GTFS transit data, to check that the two are consistent with each other.

## Background

The regional travel demand model represents transit service (routes, stops, and line-haul network) for a defined base year. GTFS (General Transit Feed Specification) feeds published by the region's transit agency describe the same service as actually operated. This repo brings both datasets into an R + [mapgl](https://walker-data.com/mapgl/) (MapLibre GL JS) Shiny app so route alignment and coverage differences can be inspected visually.

Comparison here is **visual validation**, not automated route matching: the TDM geodatabase currently only has a placeholder subset of the network (rail + BRT), with local bus routes expected to be added later, so there's no attempt to programmatically match TDM lines to GTFS routes or compute coverage gaps in code.

## Repository contents

- `app.R` — Shiny app: overlays GTFS and TDM transit layers on a Carto Positron/Dark Matter basemap for visual comparison.
- `R/prepare_gtfs.R` — extracts routes (shape-level detail and route-level dissolved), colors, and stops directly from the raw GTFS zips using [tidytransit](https://r-transit.github.io/tidytransit/), into `_data/gtfs/<date>/`.
- `R/prepare_tdm.R` — reads the TDM transit line/stop layers out of the zipped file geodatabase, discovering transit groups dynamically so it keeps working as more are added.
- `_data/gtfs/` — GTFS snapshots used for comparison, one per feed publication date:
  - `_data/gtfs/raw/` — original, unmodified GTFS zip downloads.
  - `_data/gtfs/<YYYYMMDD>.zip` — corresponding processed/working copy of each feed.
  - `_data/gtfs/<YYYYMMDD>/` — output of `R/prepare_gtfs.R`: `routes_shapes.geojson` (one row per GTFS shape, full route attributes including `route_color`), `routes_dissolved.geojson` (one row per route), `stops.geojson`.
- `_data/tdm/` — TDM transit network:
  - `WFv1000_MasterNet_20260430.gdb.zip` — the model's zipped file geodatabase (read via GDAL's `/vsizip/`), currently a **placeholder subset**: only `rail_2023` (5 lines) and `wfrc_brt_2023` (1 line) transit groups exist; local bus routes (expected: hundreds) haven't been added yet.
  - `tdm_routes.geojson`, `tdm_stops.geojson` — output of `R/prepare_tdm.R`.
- `gtfs-vs-tdm.qgz` — earlier QGIS project; superseded by the Shiny app above (kept for reference).

Current GTFS snapshots: 2023-07-23, 2023-09-18, 2024-03-25, 2024-07-15, 2024-11-21, 2025-02-27.

## Workflow

1. Download/refresh a GTFS feed into `_data/gtfs/raw/`, then run `Rscript R/prepare_gtfs.R` to (re)generate GeoJSON for every snapshot in that folder.
2. Update `_data/tdm/WFv1000_MasterNet_20260430.gdb.zip` with the latest model export, then run `Rscript R/prepare_tdm.R`.
3. Run the app (`shiny::runApp()`) and visually compare route alignment and stop coverage between the two datasets, toggling GTFS snapshot date, TDM transit groups, route detail level, and basemap as needed.

## Requirements

- R with [renv](https://rstudio.github.io/renv/) — run `renv::restore()` to install the pinned package versions from `renv.lock` (`sf`, `tidytransit`, `mapgl`, `shiny`, `dplyr`, `bslib`).
- [QGIS](https://qgis.org/) only if opening the legacy `gtfs-vs-tdm.qgz` project.
