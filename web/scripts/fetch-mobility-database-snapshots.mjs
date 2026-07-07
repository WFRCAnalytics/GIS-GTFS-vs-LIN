#!/usr/bin/env node
// Fetches historical GTFS snapshots Mobility Database has recorded for
// UTA's feed and caches them locally in web/public/data/mobility-database-cache/, so
// the "By date" GTFS source can resolve a picked date entirely offline --
// no token, no live API call, needed in the deployed app at all. Run this
// manually whenever you want to refresh the cache (no CI/scheduled Action:
// the token must never be baked into the public static bundle, so it only
// ever needs to exist on a developer's own machine -- same as
// R/mobility_database.R's own local disk cache).
//
// Mobility Database records a new "dataset" entry essentially every time it
// re-scrapes the feed, even when the feed content hasn't actually changed --
// a live run found 187 recorded entries totaling 1.1+ GB. Since UTA can in
// principle update the live feed mid-service-period, de-duping by
// *declared date range* would be wrong -- two entries with the same
// nominal range could genuinely differ. So this de-dupes by content hash
// (SHA-256) instead: entries that are truly byte-identical collapse into
// one stored zip, with their date ranges merged (min start, max end) into
// a single manifest entry; entries that merely share a date range but
// differ in content are both kept.
//
// Incremental: a dataset's `id` never changes once Mobility Database
// creates it, so re-runs only download ids not already recorded in
// manifest.json (via each entry's datasetId + mergedFrom) -- a newly
// downloaded id can still turn out to be a content-duplicate of something
// already cached (checked against every existing entry's stored hash), in
// which case it just merges into that entry's date range with no new zip.
//
// Usage: MOBILITY_DATABASE_REFRESH_TOKEN=... node web/scripts/fetch-mobility-database-snapshots.mjs
// Add --dry-run to report what's new (with sizes) without downloading
// anything.

import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";

const MDB_BASE_URL = "https://api.mobilitydatabase.org/v1";
const MDB_UTA_FEED_ID = "mdb-2349";
const OUT_DIR = join(import.meta.dirname, "..", "public", "data", "mobility-database-cache");
const MANIFEST_PATH = join(OUT_DIR, "manifest.json");
const DRY_RUN = process.argv.includes("--dry-run");
const CONCURRENCY = 5;

async function mdbAccessToken(refreshToken) {
  const res = await fetch(`${MDB_BASE_URL}/tokens`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!res.ok) throw new Error(`Token exchange failed (HTTP ${res.status}): ${await res.text()}`);
  const data = await res.json();
  if (!data.access_token) throw new Error("Token response had no access_token field.");
  return data.access_token;
}

async function mdbListDatasets(accessToken) {
  const url = new URL(`${MDB_BASE_URL}/gtfs_feeds/${MDB_UTA_FEED_ID}/datasets`);
  url.searchParams.set("limit", "500");
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`Dataset list failed (HTTP ${res.status}): ${await res.text()}`);
  return res.json();
}

function formatMB(bytes) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Runs `fn` over `items` with at most `limit` in flight at once. */
async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function loadExistingManifest() {
  if (!existsSync(MANIFEST_PATH)) return [];
  return JSON.parse(readFileSync(MANIFEST_PATH, "utf-8"));
}

function backfillMissingHashes(manifest) {
  let changed = false;
  for (const entry of manifest) {
    if (entry.hash) continue;
    const zipPath = join(OUT_DIR, entry.file);
    if (!existsSync(zipPath)) continue; // stale manifest entry with no local file -- leave as-is
    entry.hash = createHash("sha256").update(readFileSync(zipPath)).digest("hex");
    changed = true;
  }
  if (changed) console.log("Backfilled hash field on existing manifest entries from local zips (no network needed).");
  return manifest;
}

async function main() {
  const refreshToken = process.env.MOBILITY_DATABASE_REFRESH_TOKEN;
  if (!refreshToken) {
    throw new Error("Set MOBILITY_DATABASE_REFRESH_TOKEN in your environment before running this script.");
  }
  mkdirSync(OUT_DIR, { recursive: true });

  const manifest = backfillMissingHashes(loadExistingManifest());
  const seenIds = new Set(manifest.flatMap((m) => [m.datasetId, ...(m.mergedFrom ?? [])]));
  const hashToEntry = new Map(manifest.filter((m) => m.hash).map((m) => [m.hash, m]));

  console.log("Exchanging refresh token...");
  const accessToken = await mdbAccessToken(refreshToken);

  console.log(`Listing datasets for ${MDB_UTA_FEED_ID}...`);
  const allDatasets = await mdbListDatasets(accessToken);
  const newDatasets = allDatasets.filter((d) => !seenIds.has(d.id));
  console.log(`${allDatasets.length} total, ${manifest.length} already cached, ${newDatasets.length} new.`);

  if (newDatasets.length === 0) {
    console.log("Nothing new to fetch.");
  } else if (DRY_RUN) {
    let totalBytes = 0;
    for (const d of newDatasets) {
      const res = await fetch(d.hosted_url, { method: "HEAD" });
      const size = Number(res.headers.get("content-length") ?? 0);
      totalBytes += size;
      console.log(`  ${d.id}  ${d.service_date_range_start?.slice(0, 10)} - ${d.service_date_range_end?.slice(0, 10)}  ${formatMB(size)}`);
    }
    console.log(`\nTotal new: ${formatMB(totalBytes)} across ${newDatasets.length} snapshot(s). Re-run without --dry-run to download.`);
    return;
  } else {
    console.log(`Downloading ${newDatasets.length} new snapshot(s) (${CONCURRENCY} at a time)...`);
    let done = 0;
    const downloaded = await mapLimit(newDatasets, CONCURRENCY, async (d) => {
      const res = await fetch(d.hosted_url);
      done++;
      if (!res.ok) {
        console.warn(`  [${done}/${newDatasets.length}] Skipped ${d.id}: HTTP ${res.status}`);
        return null;
      }
      const buf = Buffer.from(await res.arrayBuffer());
      const hash = createHash("sha256").update(buf).digest("hex");
      console.log(`  [${done}/${newDatasets.length}] ${d.id} -> ${hash.slice(0, 12)}`);
      return { dataset: d, buf, hash };
    });

    for (const entry of downloaded) {
      if (!entry) continue;
      const { dataset: d, buf, hash } = entry;
      const start = d.service_date_range_start?.slice(0, 10) ?? null;
      const end = d.service_date_range_end?.slice(0, 10) ?? null;
      const downloadedAt = d.downloaded_at?.slice(0, 10) ?? null;

      const existing = hashToEntry.get(hash);
      if (existing) {
        // Byte-identical to something already cached -- merge date range,
        // no new zip written.
        existing.mergedFrom = [...(existing.mergedFrom ?? [existing.datasetId]), d.id];
        if (start && (!existing.serviceDateRangeStart || start < existing.serviceDateRangeStart)) existing.serviceDateRangeStart = start;
        if (end && (!existing.serviceDateRangeEnd || end > existing.serviceDateRangeEnd)) existing.serviceDateRangeEnd = end;
        if (downloadedAt && (!existing.downloadedAt || downloadedAt > existing.downloadedAt)) existing.downloadedAt = downloadedAt;
      } else {
        const newEntry = {
          datasetId: d.id,
          file: `${d.id}.zip`,
          serviceDateRangeStart: start,
          serviceDateRangeEnd: end,
          downloadedAt,
          hash,
        };
        writeFileSync(join(OUT_DIR, newEntry.file), buf);
        manifest.push(newEntry);
        hashToEntry.set(hash, newEntry);
      }
    }
  }

  manifest.sort((a, b) => (b.downloadedAt ?? "").localeCompare(a.downloadedAt ?? ""));
  writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
  console.log(`Wrote manifest with ${manifest.length} unique snapshot(s) to ${MANIFEST_PATH}`);

  console.log("Regenerating coverage chart...");
  execFileSync(process.execPath, [join(import.meta.dirname, "generate-snapshot-coverage-chart.mjs")], { stdio: "inherit" });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
