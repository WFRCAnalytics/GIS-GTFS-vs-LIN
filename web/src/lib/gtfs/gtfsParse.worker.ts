// Runs the actual unzip+CSV-parse+join work off the main thread so a large
// feed doesn't freeze the tab's UI while it's being processed -- a plain
// browser Web Worker (built into every browser, nothing to deploy or host;
// unrelated to Cloudflare Workers despite the shared name). Same idea as
// GTFSx's own gtfsImport.worker.ts (studied for approach only, AGPL-3.0 --
// see inspect.ts's comment), just for our simpler single-feed-in,
// GeoJSON-out pipeline instead of their full editable-store import. No
// size gating happens in here at all -- that's the caller's job (see
// gtfsLoader.ts), exactly like GTFSx's own parseGtfsInWorker() has zero
// awareness of inspectGtfsZip()/isLarge.
import { buildGtfsLayers, type GtfsLayers } from "./build";

export interface GtfsParseRequest {
  zipData: ArrayBuffer | Blob;
}

export type GtfsParseResponse =
  | { type: "progress"; phase: string; rows?: number }
  | { type: "result"; layers: GtfsLayers }
  | { type: "error"; message: string };

self.onmessage = async (e: MessageEvent<GtfsParseRequest>) => {
  const post = (msg: GtfsParseResponse) => self.postMessage(msg);
  try {
    const layers = await buildGtfsLayers(e.data.zipData, (phase, rows) => post({ type: "progress", phase, rows }));
    post({ type: "result", layers });
  } catch (err) {
    post({ type: "error", message: err instanceof Error ? err.message : String(err) });
  }
};
