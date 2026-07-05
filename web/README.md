# TDM vs GTFS -- static web app

A static (no server, no R/Shiny) sibling of this repo's R/Shiny app, built
with Vite + Svelte + TypeScript, hosted on GitHub Pages. Compares the same
GTFS and TDM transit networks on a MapLibre GL JS map (Overlay/Swipe), with
GTFS loadable via Upload / URL / a date picker backed by the Mobility
Database API -- there's no "Snapshot" source here (no bundled dated zip
picker), unlike the R app.

## Development

```
npm install
npm run dev
```

## TDM data

`public/data/tdm-routes.geojson` / `tdm-stops.geojson` are committed,
pre-converted static files -- not regenerated on every deploy. Regenerate
them with:

```
node scripts/build-tdm-data.mjs
```

This requires GDAL (`ogr2ogr`/`ogrinfo` on `PATH`) and reads
`../_data/tdm/PS_RTP_Transit_Stops.zip` directly (the same file the R app
uses) via GDAL's `/vsizip/` virtual filesystem -- the exact same mechanism
`R/tdm_pipeline.R` uses through `sf`, just invoked directly. It also fetches
UTA's live GTFS feed once, purely to compute each TDM route's color to match
the real network (see `R/gtfs_pipeline.R`'s and `app.R`'s color-matching
logic in the R app -- this script is a TypeScript port of that same logic).

Re-run this and commit the two updated `.geojson` files whenever
`_data/tdm/PS_RTP_Transit_Stops.zip` is updated.

## Deployment

`.github/workflows/deploy-web.yml` builds this app and deploys `dist/` to
GitHub Pages on every push to `main` that touches `web/`. GDAL is **not**
needed in that workflow, since the TDM GeoJSON is committed, not generated
at deploy time.
