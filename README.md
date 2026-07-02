# GTFS vs TDM

Compares the base-year transit network in the Wasatch Front regional travel demand model (TDM) against published GTFS transit data, to check that the two are consistent with each other.

## Background

The regional travel demand model represents transit service (routes, stops, and line-haul network) for a defined base year. GTFS (General Transit Feed Specification) feeds published by the region's transit agency describe the same service as actually operated. This repo brings both datasets into an R + [mapgl](https://walker-data.com/mapgl/) (MapLibre GL JS) Shiny app so route alignment and coverage differences can be inspected visually.

Comparison here is **visual validation**, not automated route matching: the TDM geodatabase currently only has a placeholder subset of the network (rail + BRT), with local bus routes expected to be added later, so there's no attempt to programmatically match TDM lines to GTFS routes or compute coverage gaps in code.

## Repository contents

- `app.R` — Shiny app comparing GTFS and TDM transit layers on a Carto Positron/Dark Matter basemap, either **overlaid** on one map or **swiped** side by side (`mapgl::compare()`). All settings — including Overlay/Swipe comparison mode, and an enable/disable switch for each dataset — live in a configuration modal (gear icon, top-right) rather than a permanent sidebar: GTFS source (a saved snapshot, an uploaded GTFS zip, or a live feed URL), TDM year (base year 2023 vs. forecast scenarios) and line type (rail/BRT/core), and what each side shows (lines/stops/both). Swipe mode is only selectable once both datasets are enabled.
- `R/gtfs_pipeline.R` — the shared GTFS extraction pipeline (flatten zip layout → `tidytransit::read_gtfs()` → shape-level routes + stops with route-color-derived stop colors). `app.R` calls it live for every GTFS source — a saved snapshot read straight from `_data/gtfs/`, an uploaded zip, or a downloaded feed URL — there's no pre-baked/cached copy to keep in sync; a snapshot is processed fresh each time it's selected, the same as an upload would be.
- `R/prepare_tdm.R` — reads the TDM transit line/stop layers out of the zipped file geodatabase, discovering transit groups dynamically so it keeps working as more are added.
- `_data/gtfs/` — GTFS snapshots (original, unmodified zip downloads), one per feed publication date. This is the only GTFS data committed to the repo — no derived/processed copies.
- `_data/tdm/` — TDM transit network:
  - `WFv1000_MasterNet_20260430.gdb.zip` — the model's zipped file geodatabase (read via GDAL's `/vsizip/`), currently a **placeholder subset**: only `rail_2023` (5 lines) and `wfrc_brt_2023` (1 line) transit groups exist for the 2023 base year (local bus, expected: hundreds of routes, hasn't been added yet). The gdb also has 2055 forecast-scenario groups (`rail_2055UF`, `wfrc_brt_2055UF`, `wfrc_core_2055UF`); the app defaults to 2023 only since comparing a forecast scenario against present-day GTFS isn't meaningful, but the forecast groups stay selectable.
  - `tdm_routes.geojson`, `tdm_stops.geojson` — output of `R/prepare_tdm.R`.
- `gtfs-vs-tdm.qgz` — earlier QGIS project; superseded by the Shiny app above (kept for reference).

Current GTFS snapshots: 2023-07-23, 2023-09-18, 2024-03-25, 2024-07-15, 2024-11-21, 2025-02-27.

## Workflow

1. Download/refresh a GTFS feed into `_data/gtfs/` — no separate processing step needed, the app reads the zips directly and reprocesses on demand.
2. Update `_data/tdm/WFv1000_MasterNet_20260430.gdb.zip` with the latest model export, then run `Rscript R/prepare_tdm.R`.
3. Run the app (`shiny::runApp()`). On launch it opens a configuration modal (reopen anytime via the gear icon): pick a GTFS source (saved snapshot / upload / feed URL), TDM year and line type, what each side shows, and Overlay or Swipe comparison mode — then visually compare route alignment and stop coverage between the two datasets.

## Requirements

- R with [renv](https://rstudio.github.io/renv/) — run `renv::restore()` to install the pinned package versions from `renv.lock` (`sf`, `tidytransit`, `mapgl`, `shiny`, `dplyr`, `bslib`).
- [QGIS](https://qgis.org/) only if opening the legacy `gtfs-vs-tdm.qgz` project.
