import type { Map as MapLibreMap } from "maplibre-gl";
import {
  addClusteredStopLayer,
  addGtfsRouteLayer,
  addTdmRouteLayer,
  filterTdmStopsData,
  setLayerVisibility,
  setTdmRouteFilter,
} from "./layers";
import { addHoverTooltip } from "./tooltip";
import { addClickDetail } from "./clickDetail";
import { appState } from "../store/appState.svelte";

export interface MapLayerData {
  tdmRoutes: GeoJSON.FeatureCollection | null;
  tdmStops: GeoJSON.FeatureCollection | null;
}

/**
 * Full teardown + rebuild of this map's TDM and/or GTFS layers from current
 * state -- simpler to reason about correctly than incrementally patching
 * sources/paint properties, and cheap enough at this app's data scale
 * (a few MB total). Needed both for ordinary data/filter changes and after
 * a dark-mode style swap, since MapLibre's setStyle() diffs away any
 * layer/source that isn't part of either style's own declared layers
 * (confirmed against MapLibre's style-diff behavior) -- our custom layers
 * don't survive that diff, so they need re-adding either way.
 */
export function applyLayers(map: MapLibreMap, which: "tdm" | "gtfs" | "both", data: MapLayerData) {
  if ((which === "tdm" || which === "both") && data.tdmRoutes && data.tdmStops) {
    for (const id of ["tdm_routes", "tdm_stops", "tdm_stops-clusters", "tdm_stops-cluster-count"]) {
      if (map.getLayer(id)) map.removeLayer(id);
    }
    for (const id of ["tdm_routes", "tdm_stops"]) {
      if (map.getSource(id)) map.removeSource(id);
    }
    const linesVisible = appState.tdmEnabled && appState.tdmDisplay.has("lines");
    const stopsVisible = appState.tdmEnabled && appState.tdmDisplay.has("stops");
    addTdmRouteLayer(map, data.tdmRoutes, linesVisible);
    const filteredStops = filterTdmStopsData(data.tdmStops, appState.tdmYear, [...appState.tdmModes]);
    addClusteredStopLayer(map, "tdm_stops", filteredStops, "tdm_color", "#333333", stopsVisible);
    setTdmRouteFilter(map, appState.tdmYear, [...appState.tdmModes]);
    addHoverTooltip(map, "tdm_routes", "NAME");
    addClickDetail(map, "tdm_routes", "tdm-route");
    addClickDetail(map, "tdm_stops", "tdm-stop");
  }

  if ((which === "gtfs" || which === "both") && appState.gtfsRoutesData && appState.gtfsStopsData) {
    for (const id of ["gtfs_routes", "gtfs_stops", "gtfs_stops-clusters", "gtfs_stops-cluster-count"]) {
      if (map.getLayer(id)) map.removeLayer(id);
    }
    for (const id of ["gtfs_routes", "gtfs_stops"]) {
      if (map.getSource(id)) map.removeSource(id);
    }
    const linesVisible = appState.gtfsEnabled && appState.gtfsDisplay.has("lines");
    const stopsVisible = appState.gtfsEnabled && appState.gtfsDisplay.has("stops");
    addGtfsRouteLayer(map, appState.gtfsRoutesData, linesVisible);
    addClusteredStopLayer(map, "gtfs_stops", appState.gtfsStopsData, "stop_color", "#3E7C8B", stopsVisible);
    addHoverTooltip(map, "gtfs_routes", "route_short_name");
    addClickDetail(map, "gtfs_routes", "gtfs-route");
    addClickDetail(map, "gtfs_stops", "gtfs-stop");
  }
}

/** Cheap path for enable/display toggles that don't need a full rebuild. */
export function applyVisibility(map: MapLibreMap) {
  setLayerVisibility(map, "tdm_routes", appState.tdmEnabled && appState.tdmDisplay.has("lines"));
  const tdmStopsVisible = appState.tdmEnabled && appState.tdmDisplay.has("stops");
  for (const id of ["tdm_stops", "tdm_stops-clusters", "tdm_stops-cluster-count"]) {
    setLayerVisibility(map, id, tdmStopsVisible);
  }
  setLayerVisibility(map, "gtfs_routes", appState.gtfsEnabled && appState.gtfsDisplay.has("lines"));
  const gtfsStopsVisible = appState.gtfsEnabled && appState.gtfsDisplay.has("stops");
  for (const id of ["gtfs_stops", "gtfs_stops-clusters", "gtfs_stops-cluster-count"]) {
    setLayerVisibility(map, id, gtfsStopsVisible);
  }
}
