import type { GtfsLayers } from "../gtfs/build";
import { parseGtfsInWorker } from "../gtfs/parseInWorker";

/**
 * Fetches an arbitrary GTFS feed URL directly from the browser -- no proxy,
 * per the "no backend at all" decision (see the plan file). This is
 * best-effort: confirmed during planning research that UTA's own feed URL
 * sends zero CORS headers, and that's typical of plain static-file GTFS
 * hosting industry-wide, not a UTA-specific gap -- most pasted feed URLs
 * will fail here. A failed `fetch()` from a cross-origin CORS block and a
 * failed fetch from a genuinely broken/unreachable URL look identical to
 * JS (a generic "Failed to fetch" TypeError, no distinguishing detail),
 * so the error message below explains the *likely* cause rather than
 * claiming certainty -- it's a reasonable guess, not something this code
 * can actually detect.
 */
export async function loadGtfsFromUrl(url: string): Promise<GtfsLayers> {
  let res: Response;
  try {
    res = await fetch(url);
  } catch {
    throw new Error(
      "Could not fetch that URL. Most likely the feed's server doesn't allow cross-origin " +
        "browser requests (CORS) -- this is common for GTFS feeds hosted as plain static files, " +
        "and isn't something this app can work around without a server of its own. " +
        "Try downloading the feed and using Upload instead.",
    );
  }
  if (!res.ok) {
    throw new Error(`Feed URL returned HTTP ${res.status}.`);
  }
  const buffer = await res.arrayBuffer();
  return parseGtfsInWorker(buffer);
}
