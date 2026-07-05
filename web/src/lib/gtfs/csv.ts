import { unzip } from "unzipit";
import Papa from "papaparse";

export type GtfsRow = Record<string, string>;

/**
 * Unzips a GTFS feed and parses every .txt file into raw string-keyed row
 * objects (no type coercion here -- GTFS IDs are spec'd as arbitrary
 * strings and must never be numerically coerced, e.g. stop_id "007"
 * becoming 7 and silently losing its leading zeros -- individual builder
 * functions below parse only the specific numeric fields they need).
 *
 * Unlike R/gtfs_pipeline.R's flatten_gtfs_zip() (which has to physically
 * re-zip files into a flat layout before handing off to a library that
 * demands one), this doesn't need a "flatten" step at all: each file is
 * located directly by matching its filename (allowing it to sit inside a
 * subfolder, the same real-world quirk flatten_gtfs_zip() works around),
 * since we're doing our own parsing rather than calling a library that
 * assumes a specific on-disk layout.
 */
export async function unzipGtfsTables(zipData: ArrayBuffer | Blob): Promise<Map<string, GtfsRow[]>> {
  const { entries } = await unzip(zipData);
  const tables = new Map<string, GtfsRow[]>();

  for (const [name, entry] of Object.entries(entries)) {
    const match = name.match(/(?:^|\/)([a-z_]+)\.txt$/i);
    if (!match) continue;
    const tableName = match[1].toLowerCase();
    const text = await entry.text();
    const { data } = Papa.parse<GtfsRow>(text, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h) => h.trim(),
      transform: (v) => v.trim(),
    });
    tables.set(tableName, data);
  }

  return tables;
}

export function requireTable(tables: Map<string, GtfsRow[]>, name: string): GtfsRow[] {
  const rows = tables.get(name);
  if (!rows) throw new Error(`GTFS feed is missing required file: ${name}.txt`);
  return rows;
}
