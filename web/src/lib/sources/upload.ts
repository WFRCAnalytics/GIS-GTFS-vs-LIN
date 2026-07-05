import { buildGtfsLayers, type GtfsLayers } from "../gtfs/build";

/** Simplest GTFS source: a local file, no network/CORS/Worker involved at all. */
export async function loadGtfsFromUpload(file: File): Promise<GtfsLayers> {
  return buildGtfsLayers(file);
}
