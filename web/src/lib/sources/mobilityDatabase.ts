// TypeScript port of R/mobility_database.R -- resolves a picked date to
// UTA's historical GTFS snapshot via the Mobility Database API, called
// directly from the browser (no backend at all, per the "no Cloudflare"
// decision -- see the plan file). This only works because Mobility
// Database's API has wide-open CORS (confirmed live: `allow_origins:
// ["*"]`, reflected per-origin) and its zip download URLs (Google Cloud
// Storage) are CORS-open too -- the one thing it *can't* do statically is
// hold a secret, so the user brings their own free token instead of this
// app shipping a shared one (see ../storage/mobilityDatabaseToken.ts).
import { buildGtfsLayers, type GtfsLayers } from "../gtfs/build";
import { getMobilityDatabaseToken } from "../storage/mobilityDatabaseToken";

const MDB_BASE_URL = "https://api.mobilitydatabase.org/v1";

// UTA's feed id in the Mobility Database catalog (mobilitydatabase.org/feeds/gtfs/mdb-2349,
// "UTA GTFS Schedule Feed") -- hardcoded, same as R/mobility_database.R,
// since this app only ever compares against UTA.
const MDB_UTA_FEED_ID = "mdb-2349";

export interface MdbDataset {
  id: string;
  hosted_url: string;
  downloaded_at: string;
  service_date_range_start: string;
  service_date_range_end: string;
}

/**
 * Exchanges the user's own refresh token for a short-lived access token.
 * POST /v1/tokens, {"refresh_token": ...} -> {"access_token": ...} -- this
 * exact contract isn't in Mobility Database's published OpenAPI spec at
 * all (confirmed during planning research); it was cross-checked against
 * a real working third-party client's source, same as the R version.
 */
async function mdbAccessToken(refreshToken: string): Promise<string> {
  const res = await fetch(`${MDB_BASE_URL}/tokens`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!res.ok) {
    throw new Error(`Mobility Database token exchange failed (HTTP ${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  if (!data.access_token) {
    throw new Error("Mobility Database token response had no access_token field.");
  }
  return data.access_token;
}

/** GET /v1/gtfs_feeds/{feed_id}/datasets -- every historical snapshot, newest-first. */
async function mdbListDatasets(feedId: string, accessToken: string): Promise<MdbDataset[]> {
  const url = new URL(`${MDB_BASE_URL}/gtfs_feeds/${feedId}/datasets`);
  url.searchParams.set("limit", "500");
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res.ok) {
    throw new Error(`Mobility Database dataset list request failed (HTTP ${res.status}): ${await res.text()}`);
  }
  return res.json();
}

/**
 * Picks the dataset whose service_date_range brackets targetDate; falls
 * back to the newest dataset with downloaded_at <= targetDate, then the
 * single oldest dataset on record -- exact port of R's mdb_pick_dataset().
 * Exported for testability (see the fixture-based check used to verify
 * this port matches the R version's behavior exactly).
 */
export function mdbPickDataset(datasets: MdbDataset[], targetDate: Date): MdbDataset | null {
  if (datasets.length === 0) return null;

  const toDate = (s: string | undefined) => (s ? new Date(s.slice(0, 10)) : null);
  const target = targetDate.getTime();

  const bracketing = datasets.find((d) => {
    const start = toDate(d.service_date_range_start);
    const end = toDate(d.service_date_range_end);
    return start && end && start.getTime() <= target && target <= end.getTime();
  });
  if (bracketing) return bracketing;

  const before = datasets.find((d) => {
    const downloaded = toDate(d.downloaded_at);
    return downloaded && downloaded.getTime() <= target;
  });
  if (before) return before;

  return datasets[datasets.length - 1];
}

export interface ResolvedFeed {
  hostedUrl: string;
  datasetId: string;
  serviceDateRangeStart: Date | null;
  serviceDateRangeEnd: Date | null;
}

async function resolveMobilityDatabaseFeedUrl(targetDate: Date, refreshToken: string): Promise<ResolvedFeed> {
  const accessToken = await mdbAccessToken(refreshToken);
  const datasets = await mdbListDatasets(MDB_UTA_FEED_ID, accessToken);
  if (datasets.length === 0) {
    throw new Error(`Mobility Database has no recorded datasets for feed ${MDB_UTA_FEED_ID}.`);
  }
  const chosen = mdbPickDataset(datasets, targetDate);
  if (!chosen) throw new Error("No matching Mobility Database dataset found for that date.");
  return {
    hostedUrl: chosen.hosted_url,
    datasetId: chosen.id,
    serviceDateRangeStart: chosen.service_date_range_start ? new Date(chosen.service_date_range_start.slice(0, 10)) : null,
    serviceDateRangeEnd: chosen.service_date_range_end ? new Date(chosen.service_date_range_end.slice(0, 10)) : null,
  };
}

// In-memory-only cache (no IndexedDB/persistent storage yet -- this app has
// no cache anywhere else either, by the same "reprocess live" philosophy
// R/gtfs_pipeline.R documents; this just avoids re-downloading the same
// zip twice in one page session if a user picks the same date again).
const zipCache = new Map<string, ArrayBuffer>();

export async function loadGtfsFromDate(targetDate: Date): Promise<GtfsLayers> {
  const token = getMobilityDatabaseToken();
  if (!token) {
    throw new Error(
      "No Mobility Database token configured -- add your free refresh token in Settings (create one at mobilitydatabase.org).",
    );
  }
  const resolved = await resolveMobilityDatabaseFeedUrl(targetDate, token);

  let zipBuffer = zipCache.get(resolved.datasetId);
  if (!zipBuffer) {
    const res = await fetch(resolved.hostedUrl);
    if (!res.ok) throw new Error(`Failed to download the resolved GTFS feed (HTTP ${res.status}).`);
    zipBuffer = await res.arrayBuffer();
    zipCache.set(resolved.datasetId, zipBuffer);
  }

  return buildGtfsLayers(zipBuffer);
}
