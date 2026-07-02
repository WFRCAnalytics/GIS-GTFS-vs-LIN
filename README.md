# GTFS vs TDM

Compares the base-year transit network in the Wasatch Front regional travel demand model (TDM) against published GTFS transit data, to check that the two are consistent with each other.

## Background

The regional travel demand model represents transit service (routes, stops, and line-haul network) for a defined base year. GTFS (General Transit Feed Specification) feeds published by the region's transit agency describe the same service as actually operated. This repo brings both datasets into a common GIS environment so differences in route alignment, stop locations, and service coverage can be identified and reconciled.

## Repository contents

- `gtfs-vs-tdm.qgz` — QGIS project used to visually and spatially compare the TDM network against GTFS layers.
- `_data/gtfs/` — GTFS snapshots used for comparison, one per feed publication date:
  - `_data/gtfs/raw/` — original, unmodified GTFS zip downloads.
  - `_data/gtfs/<YYYYMMDD>.zip` — corresponding processed/working copy of each feed.
  - `_data/gtfs/<YYYYMMDD>/` — GTFS routes and stops extracted to GeoJSON (`routes.geojson`, `stops.geojson`) for direct use in GIS.
- `_data/tdm/` — TDM base-year transit network data (populate with the model's transit line/stop layers for comparison).

Current GTFS snapshots: 2023-07-23, 2023-09-18, 2024-03-25, 2024-07-15, 2024-11-21, 2025-02-27.

## Workflow

1. Download/refresh a GTFS feed into `_data/gtfs/raw/` and extract `routes` and `stops` to GeoJSON under `_data/gtfs/<date>/`.
2. Export or link the TDM base-year transit network into `_data/tdm/`.
3. Open `gtfs-vs-tdm.qgz` in QGIS and load the GTFS and TDM layers to compare route alignments, stop placement, and service coverage.
4. Document and resolve discrepancies between the model network and the observed GTFS service.

## Requirements

- [QGIS](https://qgis.org/) to open `gtfs-vs-tdm.qgz` and perform spatial comparison.
