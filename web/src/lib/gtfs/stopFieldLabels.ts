// Straight from the GTFS spec (stops.txt):
// https://gtfs.org/documentation/schedule/reference/#stopstxt
const WHEELCHAIR_BOARDING_LABELS: Record<string, string> = {
  "0": "No accessibility information",
  "1": "Some accessible boarding",
  "2": "Not wheelchair accessible",
};

export function wheelchairBoardingLabel(value: unknown): string | null {
  const key = String(value ?? "");
  return WHEELCHAIR_BOARDING_LABELS[key] ?? null;
}

const LOCATION_TYPE_LABELS: Record<string, string> = {
  "0": "Stop or platform",
  "1": "Station",
  "2": "Entrance/exit",
  "3": "Generic node",
  "4": "Boarding area",
};

export function locationTypeLabel(value: unknown): string | null {
  // Missing/blank location_type defaults to 0 ("Stop or platform") per the
  // GTFS spec -- build.ts stores an absent field as "" (not undefined), so
  // the "0" fallback has to also catch the empty string, not just `??`'s
  // null/undefined.
  const key = value === undefined || value === null || value === "" ? "0" : String(value);
  return LOCATION_TYPE_LABELS[key] ?? null;
}
