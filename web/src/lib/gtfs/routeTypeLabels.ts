// GTFS route_type is a numeric code (routes.txt, "Extended" values omitted
// since they're rarely used and UTA's feed doesn't need them) -- not
// something to guess at, straight from the spec:
// https://gtfs.org/documentation/schedule/reference/#routestxt
const ROUTE_TYPE_LABELS: Record<string, string> = {
  "0": "Tram, Streetcar, Light rail",
  "1": "Subway, Metro",
  "2": "Rail",
  "3": "Bus",
  "4": "Ferry",
  "5": "Cable tram",
  "6": "Aerial lift",
  "7": "Funicular",
  "11": "Trolleybus",
  "12": "Monorail",
};

export function routeTypeLabel(routeType: unknown): string {
  const key = String(routeType ?? "");
  return ROUTE_TYPE_LABELS[key] ?? `Route type ${key}`;
}
