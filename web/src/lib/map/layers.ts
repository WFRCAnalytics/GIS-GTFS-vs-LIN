import type { Map as MapLibreMap } from "maplibre-gl";

// Ports of app.R's stop_radius_expr / stop_cluster_options() /
// apply_cluster_paint_workaround() (app.R:438-488) -- MapLibre GL JS's
// native `cluster: true` on a geojson source needs no extra library
// (Supercluster is built in), so this is a direct port, not a
// reimplementation with different tooling.
const STOP_RADIUS: maplibregl.ExpressionSpecification = [
  "interpolate", ["linear"], ["zoom"], 10, 3, 14, 6,
];
// GTFSx's actual clusterCircle radius step expression (re-verified against
// GTFSx's source, see app.R's comment) -- 4-tier scale at count breakpoints
// 50/200/1000, not a coarser 3-tier guess.
const CLUSTER_RADIUS: maplibregl.ExpressionSpecification = [
  "step", ["get", "point_count"], 14, 50, 18, 200, 24, 1000, 30,
];

export interface ClusterColors {
  clusterColor: string;
}

/**
 * Adds a clustered stop-point layer (matches add_circle_layer(cluster_options=...)
 * in app.R): unclustered points colored by their own `tdm_color`/`stop_color`
 * property, clusters in one flat color regardless of member color (mirrors
 * cluster_options(color_stops = rep(color, 4)) -- a cluster blends many
 * routes' stops together, so a single representative color is used rather
 * than an arbitrary member's color).
 */
export function addClusteredStopLayer(
  map: MapLibreMap,
  sourceId: string,
  data: GeoJSON.FeatureCollection,
  colorProperty: string,
  clusterColor: string,
  visible = true,
) {
  map.addSource(sourceId, {
    type: "geojson",
    data,
    cluster: true,
    clusterMaxZoom: 10,
    clusterRadius: 50,
  });

  const visibility = visible ? "visible" : "none";

  map.addLayer({
    id: `${sourceId}-clusters`,
    type: "circle",
    source: sourceId,
    filter: ["has", "point_count"],
    layout: { visibility },
    paint: {
      "circle-color": clusterColor,
      "circle-radius": CLUSTER_RADIUS,
      "circle-stroke-color": "#ffffff",
      "circle-stroke-width": 1.5,
      "circle-opacity": 0.85,
    },
  });

  map.addLayer({
    id: `${sourceId}-cluster-count`,
    type: "symbol",
    source: sourceId,
    filter: ["has", "point_count"],
    layout: {
      visibility,
      "text-field": ["get", "point_count_abbreviated"],
      "text-size": 12,
    },
    paint: { "text-color": "#ffffff" },
  });

  map.addLayer({
    id: sourceId,
    type: "circle",
    source: sourceId,
    filter: ["!", ["has", "point_count"]],
    layout: { visibility },
    paint: {
      "circle-color": ["get", colorProperty],
      "circle-radius": STOP_RADIUS,
      "circle-stroke-color": "#ffffff",
      "circle-stroke-width": 1,
    },
  });
}

/**
 * TDM route lines (matches add_tdm_layers() in app.R): dashed so they stay
 * visually distinguishable from GTFS's solid lines, colored per-feature via
 * tdm_color (see web/scripts/build-tdm-data.mjs for how that's computed).
 */
export function addTdmRouteLayer(map: MapLibreMap, data: GeoJSON.FeatureCollection, visible = true) {
  map.addSource("tdm_routes", { type: "geojson", data });
  map.addLayer({
    id: "tdm_routes",
    type: "line",
    source: "tdm_routes",
    layout: { visibility: visible ? "visible" : "none" },
    paint: {
      "line-color": ["get", "tdm_color"],
      "line-width": 3,
      "line-dasharray": [2, 1],
    },
  });
}

/**
 * GTFS route lines (matches add_gtfs_layers() in app.R): solid, colored by
 * the feed's own route_color -- no dasharray, so GTFS and TDM stay visually
 * distinguishable from each other even where their colors coincide.
 */
export function addGtfsRouteLayer(map: MapLibreMap, data: GeoJSON.FeatureCollection, visible = true) {
  map.addSource("gtfs_routes", { type: "geojson", data });
  map.addLayer({
    id: "gtfs_routes",
    type: "line",
    source: "gtfs_routes",
    layout: { visibility: visible ? "visible" : "none" },
    paint: {
      "line-color": ["get", "route_color"],
      "line-width": 3,
    },
  });
}

export function setLayerVisibility(map: MapLibreMap, layerId: string, visible: boolean) {
  if (!map.getLayer(layerId)) return;
  map.setLayoutProperty(layerId, "visibility", visible ? "visible" : "none");
}

/**
 * Filters TDM *routes* to a given year + set of line-type modes via
 * MapLibre's own layer `filter` (matches app.R's tdm_year/input$tdm_modes
 * filtering) -- fine for an unclustered line layer, since a layer filter
 * only affects which already-drawn features are visible, not any
 * aggregation. Stops need different handling -- see filterTdmStopsData().
 */
export function setTdmRouteFilter(map: MapLibreMap, year: string, modes: string[]) {
  if (!map.getLayer("tdm_routes")) return;
  map.setFilter("tdm_routes", [
    "all",
    ["==", ["get", "tdm_year"], year],
    ["in", ["get", "tdm_mode"], ["literal", modes]],
  ]);
}

/**
 * TDM stops are clustered (see addClusteredStopLayer) -- MapLibre's
 * built-in Supercluster runs over the *source's full data* before any
 * layer-level `filter` is applied, so a layer filter alone would leave
 * cluster counts wrong (still counting year/mode-filtered-out points).
 * The correct fix is what app.R's own `set_source()` observers do too:
 * filter the underlying data itself and re-set the source, so clustering
 * recomputes over only the features that should actually be shown.
 */
export function filterTdmStopsData(
  allStops: GeoJSON.FeatureCollection,
  year: string,
  modes: string[],
): GeoJSON.FeatureCollection {
  return {
    type: "FeatureCollection",
    features: allStops.features.filter(
      (f) => f.properties?.tdm_year === year && modes.includes(f.properties?.tdm_mode),
    ),
  };
}
