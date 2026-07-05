import type { GtfsLayers } from "./build";
import type { GtfsParseRequest, GtfsParseResponse } from "./gtfsParse.worker";
import { assertGtfsZipNotTooLarge } from "./inspect";

/**
 * Pre-flight size check (see inspect.ts), then hands the actual parse off
 * to a Web Worker so the main thread -- and thus the UI -- doesn't freeze
 * while a feed is being unzipped/parsed/joined. Vite's `new Worker(new
 * URL(...), { type: 'module' })` form is what lets this bundle correctly
 * both in dev and in the production build (plain `new Worker('/path.js')`
 * wouldn't survive Vite's asset hashing).
 */
export async function parseGtfsInWorker(zipData: ArrayBuffer | Blob): Promise<GtfsLayers> {
  await assertGtfsZipNotTooLarge(zipData);

  const worker = new Worker(new URL("./gtfsParse.worker.ts", import.meta.url), { type: "module" });
  try {
    return await new Promise<GtfsLayers>((resolve, reject) => {
      worker.onmessage = (e: MessageEvent<GtfsParseResponse>) => {
        if (e.data.ok) resolve(e.data.layers);
        else reject(new Error(e.data.error));
      };
      worker.onerror = (e) => reject(new Error(e.message));
      const request: GtfsParseRequest = { zipData };
      // Blob/File clone efficiently by reference already -- only a raw
      // ArrayBuffer needs to be in the transfer list to avoid a full copy.
      worker.postMessage(request, zipData instanceof ArrayBuffer ? [zipData] : []);
    });
  } finally {
    worker.terminate();
  }
}
