import { unzip } from "unzipit";

// Combined uncompressed size of the heavy tables (stop_times + shapes) above
// which we refuse to parse outright (see assertGtfsZipNotTooLarge below).
// Mirrors GTFSx's own pre-flight check (github.com/markegge/gtfsx, studied
// for approach only -- AGPL-3.0, not copied -- see its
// src/services/gtfsParse.ts inspectGtfsZip()/LARGE_FEED_BYTES), but tuned
// against this app's actual reference feed rather than assumed: UTA's own
// real feed (_data/gtfs/GTFS20250227.zip) is 25.48 MB of stop_times+shapes
// alone (a 4 MB zip on disk -- stop_times.txt is highly repetitive CSV and
// commonly compresses 5-8x, so this is normal, not a sign of an oversized
// feed), which would trip GTFSx's own ~25 MB threshold with zero margin.
// GTFSx's own worked example of a feed that actually needs the guard is
// RTD Denver-class regional data (~35 MB stop_times + ~26 MB shapes =
// ~61 MB) -- 50 MB sits with real margin above UTA's size and well below
// that regional-feed scale.
export const LARGE_FEED_BYTES = 50 * 1024 * 1024;

export interface GtfsZipSize {
  stopTimesBytes: number;
  shapesBytes: number;
  totalHeavyBytes: number;
  isLarge: boolean;
}

/**
 * Cheap pre-flight: reads the *uncompressed* sizes of stop_times.txt and
 * shapes.txt straight from the ZIP's central directory (unzipit exposes
 * `size` on each entry without decompressing it) so a huge feed can be
 * rejected with a clear message before the expensive unzip+parse+join work
 * that would otherwise run first and fail (or hang the tab) anyway.
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
  return { stopTimesBytes, shapesBytes, totalHeavyBytes, isLarge: totalHeavyBytes > LARGE_FEED_BYTES };
}

function formatMB(bytes: number): string {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Throws a clear, specific error if the feed exceeds LARGE_FEED_BYTES. */
export async function assertGtfsZipNotTooLarge(zipData: ArrayBuffer | Blob): Promise<void> {
  const size = await inspectGtfsZip(zipData);
  if (size.isLarge) {
    throw new Error(
      `This feed's stop_times.txt + shapes.txt total ${formatMB(size.totalHeavyBytes)} uncompressed, ` +
        `over this app's ${formatMB(LARGE_FEED_BYTES)} limit -- too large to parse in the browser ` +
        `without risking a frozen or crashed tab. Try a smaller/single-agency feed.`,
    );
  }
}
