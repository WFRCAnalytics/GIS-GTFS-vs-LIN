#!/usr/bin/env node
// Copies the repo's hand-curated GTFS snapshot zips (_data/gtfs/, the same
// set app.R's own Snapshot source reads) into web/public/data/gtfs-snapshots/
// and writes a manifest.json describing them, so the static app's Snapshot
// source doesn't need to hardcode the list or duplicate app.R's
// extract_date()/fmt_snapshot() logic in two places. Re-run whenever
// _data/gtfs/ gets a new snapshot added.

import { readdirSync, copyFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const SRC_DIR = join(import.meta.dirname, "..", "..", "_data", "gtfs");
const OUT_DIR = join(import.meta.dirname, "..", "public", "data", "gtfs-snapshots");

// Matches R/gtfs_pipeline.R's extract_date(): first 8-digit run in the
// filename (handles both "20230723.zip" and "GTFS20250227.zip").
function extractDate(filename) {
  const m = filename.match(/\d{8}/);
  if (!m) throw new Error(`No 8-digit date found in filename: ${filename}`);
  return m[0];
}

// Matches R/app.R's fmt_snapshot(): "20250227" -> "Feb 27, 2025".
function formatLabel(id) {
  const date = new Date(`${id.slice(0, 4)}-${id.slice(4, 6)}-${id.slice(6, 8)}T00:00:00Z`);
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
}

function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const files = readdirSync(SRC_DIR).filter((f) => f.endsWith(".zip"));

  const manifest = files
    .map((file) => {
      const id = extractDate(file);
      copyFileSync(join(SRC_DIR, file), join(OUT_DIR, file));
      return { id, file, label: formatLabel(id) };
    })
    .sort((a, b) => b.id.localeCompare(a.id)); // newest first, matches app.R's available_dates

  writeFileSync(join(OUT_DIR, "manifest.json"), JSON.stringify(manifest, null, 2));
  console.log(`Copied ${manifest.length} snapshot(s) and wrote manifest.json to ${OUT_DIR}`);
}

main();
