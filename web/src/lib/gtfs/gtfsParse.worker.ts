// Runs the actual unzip+CSV-parse+join work off the main thread so a large
// feed doesn't freeze the tab's UI while it's being processed -- a plain
// browser Web Worker (built into every browser, nothing to deploy or host;
// unrelated to Cloudflare Workers despite the shared name). Same idea as
// GTFSx's own gtfsImport.worker.ts (studied for approach only, AGPL-3.0 --
// see inspect.ts's comment), just for our simpler single-feed-in,
// GeoJSON-out pipeline instead of their full editable-store import.
import { buildGtfsLayers } from "./build";

export interface GtfsParseRequest {
  zipData: ArrayBuffer | Blob;
}

export type GtfsParseResponse =
  | { ok: true; layers: Awaited<ReturnType<typeof buildGtfsLayers>> }
  | { ok: false; error: string };

self.onmessage = async (e: MessageEvent<GtfsParseRequest>) => {
  try {
    const layers = await buildGtfsLayers(e.data.zipData);
    const response: GtfsParseResponse = { ok: true, layers };
    self.postMessage(response);
  } catch (err) {
    const response: GtfsParseResponse = { ok: false, error: err instanceof Error ? err.message : String(err) };
    self.postMessage(response);
  }
};
