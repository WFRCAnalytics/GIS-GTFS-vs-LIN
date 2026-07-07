// Static GTFS snapshot picker -- the same curated dated zips app.R's own
// Snapshot source reads from _data/gtfs/ (see web/scripts/build-gtfs-snapshots.mjs,
// which copies them here and writes this manifest). Always works with zero
// setup: same-origin static files, no network/CORS/token concerns at all.
export interface GtfsSnapshotInfo {
  id: string;
  file: string;
  label: string;
}

let manifestCache: GtfsSnapshotInfo[] | null = null;

export async function listGtfsSnapshots(): Promise<GtfsSnapshotInfo[]> {
  if (manifestCache) return manifestCache;
  const res = await fetch(`${import.meta.env.BASE_URL}data/gtfs-snapshots/manifest.json`);
  if (!res.ok) throw new Error(`Failed to load the GTFS snapshot list (HTTP ${res.status}).`);
  manifestCache = await res.json();
  return manifestCache!;
}

export async function resolveGtfsZipFromSnapshot(id: string): Promise<ArrayBuffer> {
  const snapshots = await listGtfsSnapshots();
  const snapshot = snapshots.find((s) => s.id === id);
  if (!snapshot) throw new Error(`Unknown GTFS snapshot: ${id}`);
  const res = await fetch(`${import.meta.env.BASE_URL}data/gtfs-snapshots/${snapshot.file}`);
  if (!res.ok) throw new Error(`Failed to load snapshot ${snapshot.label} (HTTP ${res.status}).`);
  return res.arrayBuffer();
}
