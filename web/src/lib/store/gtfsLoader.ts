import { appState } from "./appState.svelte";
import { loadGtfsFromUpload } from "../sources/upload";
import { loadGtfsFromUrl } from "../sources/url";
import { loadGtfsFromDate } from "../sources/mobilityDatabase";
import type { GtfsLayers } from "../gtfs/build";

function applyResult(layers: GtfsLayers) {
  appState.gtfsRoutesData = layers.routesGeoJSON;
  appState.gtfsStopsData = layers.stopsGeoJSON;
  appState.gtfsValidityStart = layers.validity.start;
  appState.gtfsValidityEnd = layers.validity.end;
}

async function withLoadHandling(load: () => Promise<GtfsLayers>) {
  appState.gtfsLoading = true;
  appState.gtfsError = null;
  try {
    applyResult(await load());
  } catch (err) {
    appState.gtfsError = err instanceof Error ? err.message : String(err);
  } finally {
    appState.gtfsLoading = false;
  }
}

export function loadGtfsUpload(file: File) {
  return withLoadHandling(() => loadGtfsFromUpload(file));
}

export function loadGtfsUrl(url: string) {
  return withLoadHandling(() => loadGtfsFromUrl(url));
}

export function loadGtfsDate(date: Date) {
  return withLoadHandling(() => loadGtfsFromDate(date));
}
