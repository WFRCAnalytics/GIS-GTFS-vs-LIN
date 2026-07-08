import type { Map as MapLibreMap } from "maplibre-gl";
import { appState, type SelectedFeature } from "../store/appState.svelte";

// Same idempotency concern as tooltip.ts's addHoverTooltip(): applyLayers.ts
// fully removes and re-adds gtfs_routes/gtfs_stops/tdm_routes/tdm_stops on
// every filter/theme change, and MapLibre's map.on(event, layerId, handler)
// filters by layer *id string* rather than a live Layer reference, so one
// attachment per (map, layerId) stays valid across those re-adds.
const attached = new WeakMap<MapLibreMap, Set<string>>();

export function addClickDetail(map: MapLibreMap, layerId: string, kind: SelectedFeature["kind"]) {
  const seen = attached.get(map) ?? new Set<string>();
  attached.set(map, seen);
  if (seen.has(layerId)) return;
  seen.add(layerId);

  map.on("click", layerId, (e) => {
    const feature = e.features?.[0];
    if (!feature?.properties) return;
    appState.selectedFeature = { kind, properties: feature.properties } as SelectedFeature;
  });
}
