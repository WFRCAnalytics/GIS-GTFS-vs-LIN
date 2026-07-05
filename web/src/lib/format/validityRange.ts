// Port of app.R's fmt_validity_range(): "Apr 16 - Aug 19, 2023" when both
// dates share a year, "Apr 16, 2023 - Aug 19, 2024" when they don't, or a
// single date if the feed is only valid for one day.
export function formatValidityRange(start: Date | null, end: Date | null): string {
  if (!start || !end) return "";
  // GTFS dates have no time-of-day/timezone at all (parseGtfsDate() stores
  // them as UTC midnight, arbitrarily) -- formatting must read them back in
  // UTC too, or a negative-UTC-offset local timezone (e.g. US Mountain
  // Time) shows the wrong calendar day entirely (confirmed: Dec 8 rendered
  // as Dec 7 without this).
  const fmt = (d: Date, withYear: boolean) =>
    d.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: withYear ? "numeric" : undefined,
      timeZone: "UTC",
    });
  if (start.getTime() === end.getTime()) return fmt(start, true);
  const sameYear = start.getUTCFullYear() === end.getUTCFullYear();
  return sameYear ? `${fmt(start, false)} - ${fmt(end, true)}` : `${fmt(start, true)} - ${fmt(end, true)}`;
}
