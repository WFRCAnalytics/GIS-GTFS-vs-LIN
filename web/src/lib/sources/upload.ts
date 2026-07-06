/** Simplest GTFS source: a local file, no network/CORS involved at all. */
export async function resolveGtfsZipFromUpload(file: File): Promise<File> {
  return file;
}
