import { unzip } from "unzipit";

// Combined uncompressed size of the heavy tables (stop_times + shapes) above
// which the caller should gate behind a confirmation instead of charging
// straight into a parse that can hang or crash the tab. Matches GTFSx's own
// threshold exactly (github.com/markegge/gtfsx, studied for approach only
// -- AGPL-3.0, not copied -- see its src/services/gtfsParse.ts
// inspectGtfsZip()/LARGE_FEED_BYTES): this is a *warning* gate the user can
// override ("Try anyway", see gtfsLoader.ts), not a hard reject, which is
// exactly why 25 MB works even though UTA's own real feed
// (_data/gtfs/GTFS20250227.zip) needs 25.48 MB uncompressed -- it just
// shows the warning and still loads if you proceed.
export const LARGE_FEED_BYTES = 25 * 1024 * 1024;

export interface GtfsZipSize {
  stopTimesBytes: number;
  shapesBytes: number;
  totalHeavyBytes: number;
  estimatedRows: number;
  isLarge: boolean;
}

/**
 * Cheap pre-flight: reads the *uncompressed* sizes of stop_times.txt and
 * shapes.txt straight from the ZIP's central directory (unzipit exposes
 * `size` on each entry without decompressing it) so a huge feed's warning
 * can be shown before the expensive unzip+parse+join work.
 */
export async function inspectGtfsZip(zipData: ArrayBuffer | Blob): Promise<GtfsZipSize> {
  const { entries } = await unzip(zipData);
  const sizeOf = (fileName: string) => {
    for (const [name, entry] of Object.entries(entries)) {
      if (new RegExp(`(?:^|/)${fileName}$`, "i").test(name)) return entry.size;
    }
    return 0;
  };
  const stopTimesBytes = sizeOf("stop_times.txt");
  const shapesBytes = sizeOf("shapes.txt");
  const totalHeavyBytes = stopTimesBytes + shapesBytes;
  // GTFS stop_times rows average roughly 55 bytes uncompressed (GTFSx's own
  // estimate) -- good enough for an order-of-magnitude row count to show
  // the user, not meant to be exact.
  const estimatedRows = Math.round(stopTimesBytes / 55);
  return { stopTimesBytes, shapesBytes, totalHeavyBytes, estimatedRows, isLarge: totalHeavyBytes > LARGE_FEED_BYTES };
}
