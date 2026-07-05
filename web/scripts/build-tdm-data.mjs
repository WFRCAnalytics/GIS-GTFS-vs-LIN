#!/usr/bin/env node
// Converts the TDM zipped file geodatabase (_data/tdm/PS_RTP_Transit_Stops.zip)
// into two static GeoJSON files this app can load directly, with the same
// tdm_mode/tdm_color logic the R app computes at startup (app.R) baked in
// at build time instead -- this script is the one-time (per data update)
// replacement for what R's sf/GDAL + app.R's color-matching block do live.
//
// Requires `ogr2ogr`/`ogrinfo` on PATH (GDAL). On the GitHub Actions runner
// this comes from `apt-get install gdal-bin`; locally, anything that
// already has GDAL (e.g. the R app's own renv/sf setup, QGIS, a conda env)
// works the same way.
//
// Run: node web/scripts/build-tdm-data.mjs   (from the repo root or web/)

import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { unzip } from "unzipit";
import Papa from "papaparse";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../..");
const GDB_ZIP_PATH = resolve(REPO_ROOT, "_data/tdm/PS_RTP_Transit_Stops.zip");
const GDB_VSIZIP = `/vsizip/${GDB_ZIP_PATH.replace(/\\/g, "/")}/PS_RTP_Transit_Stops/WFv1000_MasterNet_20260430.gdb`;
const OUT_ROUTES = resolve(__dirname, "../public/data/tdm-routes.geojson");
const OUT_STOPS = resolve(__dirname, "../public/data/tdm-stops.geojson");

// Reference GTFS feed used only to compute tdm_color at build time (the
// crosswalk below matches TDM route names to this feed's real
// route_short_name/route_color) -- not shipped to the browser, not the
// "Snapshot" source the R app has (that's explicitly dropped here). Node's
// fetch() has no CORS restriction (CORS is a browser-only concept), so
// this works even though the same URL is unfetchable directly from a
// deployed static site (confirmed during planning research).
const REFERENCE_GTFS_URL = "https://gtfsfeed.rideuta.com/gtfs.zip";

function ogr2ogrGeoJSON(layer, extraArgs = []) {
  const args = [
    "-f", "GeoJSON", "/vsistdout/",
    GDB_VSIZIP, layer,
    "-t_srs", "EPSG:4326",
    ...extraArgs,
  ];
  const out = execFileSync("ogr2ogr", args, { maxBuffer: 1024 * 1024 * 256 });
  return JSON.parse(out.toString("utf-8"));
}

function listTransitGroups() {
  // ogrinfo's -json output only carries schema/summary info in this GDAL
  // version, not actual feature values -- ogr2ogr's GeoJSON output (the
  // same tool used for every other layer below) does carry real rows.
  const geojson = ogr2ogrGeoJSON("CITILABS_TRANSITGROUPS", ["-select", "TRANSITGROUP_NAME"]);
  return geojson.features.map((f) => f.properties.TRANSITGROUP_NAME);
}

// --- Port of app.R's parse_tdm_mode()/parse_tdm_year() (app.R:118-138) ---
// Matched on whole underscore-delimited tokens, not a bare substring, so a
// code can't accidentally match inside an unrelated token.
function parseTdmMode(group) {
  const token = (code) => new RegExp(`(^|_)${code}(_|$)`, "i");
  if (token("rail").test(group)) return "rail";
  if (token("brt").test(group)) return "brt";
  if (token("core").test(group)) return "core";
  if (token("exp").test(group)) return "express";
  if (token("lcl").test(group)) return "local";
  return "other";
}
function parseTdmYear(group) {
  const m = group.match(/[0-9]{4}(UF)?$/);
  return m ? m[0] : "unknown";
}

// --- Port of app.R's best_headway()/n_service_periods() (app.R:150-160) ---
const HEADWAY_FIELDS = ["HEADWAY_1", "HEADWAY_2", "HEADWAY_3", "HEADWAY_4", "HEADWAY_5"];
function bestHeadway(props) {
  const positive = HEADWAY_FIELDS.map((f) => props[f]).filter((v) => typeof v === "number" && v > 0);
  return positive.length === 0 ? null : Math.min(...positive);
}
function nServicePeriods(props) {
  return HEADWAY_FIELDS.map((f) => props[f]).filter((v) => typeof v === "number" && v > 0).length;
}

// --- Port of app.R's tdm_bus_color_tier() (app.R:183-209) ---
function tdmBusColorTier(mode, headway, nPeriods) {
  if (mode === "local" && headway != null && headway <= 15) return "core";
  if (mode === "local" && nPeriods === 1) return "express";
  return mode;
}

// Bus tiers matched to the real GTFS feed's own route_color (app.R:164-166).
const TDM_MODE_COLORS = {
  core: "#2eb566",
  express: "#be2036",
  brt: "#1191d0",
  local: "#004a97",
};
const DEFAULT_MODE_COLOR = "#808080";

// Rail per-line colors, matched by NAME to the real GTFS rail route_color
// (app.R:211-241). Orange/POM_Rail are 2055UF-only with no current
// real-world route -- best guess from WFRC's brand palette (same values
// used in app.R, copied here rather than parsed from brand.yml since this
// is a one-time build-time constant, not a live theme integration).
const TDM_RAIL_LINE_COLORS = {
  Blue: "#004a97",
  Red: "#be2036",
  Green: "#2eb566",
  Sline: "#77777a",
  RCRT_OGPN: "#c227b9",
  FRFBCEXT1: "#c227b9",
  Orange: "#ea7b00", // brand Core Palette "orange"
  POM_Rail: "#24316d", // brand "wc-commuter-rail"
};
function tdmRailFallbackColor(mode) {
  return mode === 7 ? "#3762ad" : "#24316d";
}

// Named-service dictionary override (app.R's MidValCon comment) -- the "X"
// naming convention (UVX/603X/830X/OGX) marks express/BRT-branded service
// across both TDM and GTFS naming; every other "X"-branded route already
// has tdm_mode "brt"/"express" from its tdm_group name, so this is the one
// documented exception needing a manual override.
const TDM_NAMED_OVERRIDES = { MidValCon: "brt" };

// --- Port of app.R's tdm_bus_crosswalk_key() (app.R:283-301) ---
function tdmBusCrosswalkKeys(name) {
  const isFlex = /^[SO]F/.test(name);
  let noPrefix = name.replace(/^(S|O|M)/, "");
  noPrefix = noPrefix.replace(/_.*$/, "");
  const digits = noPrefix.replace(/[^0-9]/g, "").replace(/^0+(?=[0-9])/, "");
  const lettersSuffix = noPrefix.replace(/[0-9]/g, "");
  return {
    primary: isFlex ? `F${digits}` : `${digits}${lettersSuffix}`,
    alt: isFlex ? `F${digits}` : digits,
  };
}

async function fetchReferenceGtfsColors() {
  console.log(`Fetching reference GTFS feed for the color crosswalk: ${REFERENCE_GTFS_URL}`);
  const res = await fetch(REFERENCE_GTFS_URL);
  if (!res.ok) throw new Error(`Failed to fetch reference GTFS feed: HTTP ${res.status}`);
  const buf = await res.arrayBuffer();
  const { entries } = await unzip(buf);
  // routes.txt may sit inside a subfolder, same quirk R/gtfs_pipeline.R's
  // flatten_gtfs_zip() works around -- find it wherever it is.
  const routesEntryName = Object.keys(entries).find((n) => /(^|\/)routes\.txt$/i.test(n));
  if (!routesEntryName) throw new Error("Reference GTFS feed has no routes.txt");
  const routesText = await entries[routesEntryName].text();
  const { data } = Papa.parse(routesText, { header: true, skipEmptyLines: true });

  const colorByShortName = {};
  for (const row of data) {
    if (row.route_type !== "3") continue; // bus only, matches app.R's crosswalk scope
    const shortName = (row.route_short_name ?? "").trim();
    const color = (row.route_color ?? "").trim();
    if (shortName && color) colorByShortName[shortName] = `#${color}`;
  }
  console.log(`Reference feed: ${data.length} routes, ${Object.keys(colorByShortName).length} bus route colors indexed.`);
  return colorByShortName;
}

async function main() {
  console.log("Enumerating TDM transit groups...");
  const groups = listTransitGroups();
  console.log(`Found ${groups.length} groups: ${groups.join(", ")}`);

  const allRouteFeatures = [];
  const allStopFeatures = [];

  for (const group of groups) {
    console.log(`Converting ${group}...`);
    const lineGeoJSON = ogr2ogrGeoJSON(`${group}_PTLine`, [
      "-select", "NAME,LONGNAME,MODE,HEADWAY_1,HEADWAY_2,HEADWAY_3,HEADWAY_4,HEADWAY_5",
    ]);
    lineGeoJSON.features.forEach((f, i) => {
      f.properties.tdm_group = group;
      f.properties.line_id = i + 1; // 1-based, matches _PTNode's LINEID (see R/tdm_pipeline.R's read_group() comment)
      allRouteFeatures.push(f);
    });

    const nodeGeoJSON = ogr2ogrGeoJSON(`${group}_PTNode`, [
      "-where", "STOPNODE=1",
      "-select", "LINEID,SEQNO,NODES",
    ]);
    nodeGeoJSON.features.forEach((f) => {
      f.properties.tdm_group = group;
      allStopFeatures.push(f);
    });
  }
  console.log(`Total: ${allRouteFeatures.length} route features, ${allStopFeatures.length} stop features.`);

  // Derived fields, mirroring app.R:140-160.
  for (const f of allRouteFeatures) {
    const p = f.properties;
    p.tdm_mode = parseTdmMode(p.tdm_group);
    p.tdm_year = parseTdmYear(p.tdm_group);
    p.best_headway = bestHeadway(p);
    p.n_service_periods = nServicePeriods(p);
  }

  const gtfsColorByShortName = await fetchReferenceGtfsColors();

  const unmatchedRailNames = new Set();
  for (const f of allRouteFeatures) {
    const p = f.properties;
    if (p.tdm_mode === "rail") {
      if (p.NAME in TDM_RAIL_LINE_COLORS) {
        p.tdm_color = TDM_RAIL_LINE_COLORS[p.NAME];
      } else {
        unmatchedRailNames.add(p.NAME);
        p.tdm_color = tdmRailFallbackColor(p.MODE);
      }
      continue;
    }

    // 2023-only crosswalk (see app.R's comment on why 2055UF is excluded --
    // forecast-only project codenames coincidentally matching a real
    // route number via the bare-digit fallback key produced false
    // positives when this was tried against all years).
    let crosswalkColor = null;
    if (p.tdm_year === "2023") {
      const keys = tdmBusCrosswalkKeys(p.NAME);
      crosswalkColor = gtfsColorByShortName[keys.primary] ?? gtfsColorByShortName[keys.alt] ?? null;
    }
    if (crosswalkColor) {
      p.tdm_color = crosswalkColor;
      continue;
    }

    if (p.NAME in TDM_NAMED_OVERRIDES) {
      p.tdm_color = TDM_MODE_COLORS[TDM_NAMED_OVERRIDES[p.NAME]];
      continue;
    }

    const tier = tdmBusColorTier(p.tdm_mode, p.best_headway, p.n_service_periods);
    p.tdm_color = TDM_MODE_COLORS[tier] ?? DEFAULT_MODE_COLOR;
  }
  if (unmatchedRailNames.size > 0) {
    console.warn(`WARNING: unrecognized rail NAME(s), used mode-aware fallback: ${[...unmatchedRailNames].join(", ")}`);
  }

  // Stops inherit their line's color via (tdm_group, LINEID <-> line_id) --
  // mirrors app.R's stop_line_colors join.
  const colorByGroupAndLineId = new Map();
  for (const f of allRouteFeatures) {
    colorByGroupAndLineId.set(`${f.properties.tdm_group}::${f.properties.line_id}`, f.properties.tdm_color);
  }
  let unmatchedStops = 0;
  for (const f of allStopFeatures) {
    const key = `${f.properties.tdm_group}::${f.properties.LINEID}`;
    const color = colorByGroupAndLineId.get(key);
    if (color == null) unmatchedStops++;
    f.properties.tdm_color = color ?? DEFAULT_MODE_COLOR;
    // Needed for the app's Year/Line-types filtering (filterTdmStopsData()
    // in web/src/lib/map/layers.ts) -- routes already get these above.
    f.properties.tdm_mode = parseTdmMode(f.properties.tdm_group);
    f.properties.tdm_year = parseTdmYear(f.properties.tdm_group);
  }
  if (unmatchedStops > 0) {
    console.warn(`WARNING: ${unmatchedStops} stop(s) had no matching route color, used default gray.`);
  }

  writeFileSync(OUT_ROUTES, JSON.stringify({ type: "FeatureCollection", features: allRouteFeatures }));
  writeFileSync(OUT_STOPS, JSON.stringify({ type: "FeatureCollection", features: allStopFeatures }));
  console.log(`Wrote ${OUT_ROUTES}`);
  console.log(`Wrote ${OUT_STOPS}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
