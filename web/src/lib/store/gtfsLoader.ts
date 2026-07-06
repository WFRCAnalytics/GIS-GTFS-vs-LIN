import { appState } from "./appState.svelte";
import { resolveGtfsZipFromUpload } from "../sources/upload";
import { resolveGtfsZipFromUrl } from "../sources/url";
import { resolveGtfsZipFromDate } from "../sources/mobilityDatabase";
import { inspectGtfsZip } from "../gtfs/inspect";
import { parseGtfsInWorker } from "../gtfs/parseInWorker";
import type { GtfsLayers } from "../gtfs/build";

function applyResult(layers: GtfsLayers) {
  appState.gtfsRoutesData = layers.routesGeoJSON;
  appState.gtfsStopsData = layers.stopsGeoJSON;
  appState.gtfsValidityStart = layers.validity.start;
  appState.gtfsValidityEnd = layers.validity.end;
}

// Resolved by confirmLargeFeedLoad()/cancelLargeFeedLoad(), called from the
// inline warning in Sidebar.svelte's GTFS card (never a modal, per this
// project's established design rule) -- there's only ever one load pending
// gate at a time, so a single module-level slot is enough.
let pendingResolve: ((proceed: boolean) => void) | null = null;

/**
 * Pre-flight size check (see inspect.ts); if the feed is large, pauses and
 * waits for the user to confirm via the sidebar's Cancel/"Try anyway" gate
 * instead of charging straight into a parse that could hang the tab --
 * matches GTFSx's own soft-warning behavior exactly (not a hard reject).
 * If the inspection itself fails (e.g. a corrupt zip), fails *open* --
 * proceeds to the real parse, which will surface a real error on its own,
 * same as GTFSx's own `catch { /* proceed anyway *\/ }`.
 */
async function gateIfLarge(zipData: ArrayBuffer | Blob): Promise<boolean> {
  try {
    const info = await inspectGtfsZip(zipData);
    if (!info.isLarge) return true;
    appState.gtfsPendingLarge = info;
  } catch {
    return true;
  }
  return new Promise<boolean>((resolve) => {
    pendingResolve = resolve;
  });
}

export function confirmLargeFeedLoad() {
  appState.gtfsPendingLarge = null;
  pendingResolve?.(true);
  pendingResolve = null;
}

export function cancelLargeFeedLoad() {
  appState.gtfsPendingLarge = null;
  pendingResolve?.(false);
  pendingResolve = null;
}

async function withLoadHandling(resolveZip: () => Promise<ArrayBuffer | Blob | File>) {
  appState.gtfsLoading = true;
  appState.gtfsError = null;
  appState.gtfsProgress = null;
  try {
    const zipData = await resolveZip();
    const proceed = await gateIfLarge(zipData);
    if (!proceed) return; // user cancelled -- not an error, just no-op
    const layers = await parseGtfsInWorker(zipData, (phase, rows) => {
      appState.gtfsProgress = rows ? `${phase} ${rows.toLocaleString()} rows` : phase;
    });
    applyResult(layers);
  } catch (err) {
    appState.gtfsError = err instanceof Error ? err.message : String(err);
  } finally {
    appState.gtfsLoading = false;
    appState.gtfsProgress = null;
  }
}

export function loadGtfsUpload(file: File) {
  return withLoadHandling(() => resolveGtfsZipFromUpload(file));
}

export function loadGtfsUrl(url: string) {
  return withLoadHandling(() => resolveGtfsZipFromUrl(url));
}

export function loadGtfsDate(date: Date) {
  return withLoadHandling(() => resolveGtfsZipFromDate(date));
}
