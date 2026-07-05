import type { GtfsLayers } from "../gtfs/build";
import { parseGtfsInWorker } from "../gtfs/parseInWorker";

/** Simplest GTFS source: a local file, no network/CORS involved at all. */
export async function loadGtfsFromUpload(file: File): Promise<GtfsLayers> {
  return parseGtfsInWorker(file);
}
