import type { GtfsRow } from "./csv";

export interface ValidityRange {
  start: Date | null;
  end: Date | null;
}

/** GTFS dates are plain YYYYMMDD strings (no separators, no timezone). */
export function parseGtfsDate(yyyymmdd: string | undefined): Date | null {
  if (!yyyymmdd || !/^\d{8}$/.test(yyyymmdd)) return null;
  const year = Number(yyyymmdd.slice(0, 4));
  const month = Number(yyyymmdd.slice(4, 6)) - 1;
  const day = Number(yyyymmdd.slice(6, 8));
  const d = new Date(Date.UTC(year, month, day));
  return Number.isNaN(d.getTime()) ? null : d;
}

function minMaxDates(dates: (Date | null)[]): ValidityRange {
  const valid = dates.filter((d): d is Date => d !== null);
  if (valid.length === 0) return { start: null, end: null };
  const times = valid.map((d) => d.getTime());
  return { start: new Date(Math.min(...times)), end: new Date(Math.max(...times)) };
}

/**
 * Port of R/gtfs_pipeline.R's extract_gtfs_validity_range(): the feed's own
 * effective date *range*, independent of where it came from or what a
 * filename happens to say. feed_info.txt is optional in the GTFS spec (and
 * feed_end_date is only conditionally required even when feed_info.txt
 * exists), so this falls back to calendar.txt's min(start_date)/
 * max(end_date), then calendar_dates.txt's min/max(date), same fallback
 * chain and same reasoning as the R version.
 */
export function extractGtfsValidityRange(tables: Map<string, GtfsRow[]>): ValidityRange {
  const feedInfo = tables.get("feed_info");
  if (feedInfo && feedInfo.length > 0) {
    const start = parseGtfsDate(feedInfo[0].feed_start_date);
    const end = parseGtfsDate(feedInfo[0].feed_end_date);
    if (start && end) return { start, end };
  }

  const calendar = tables.get("calendar");
  if (calendar && calendar.length > 0) {
    const start = minMaxDates(calendar.map((r) => parseGtfsDate(r.start_date))).start;
    const end = minMaxDates(calendar.map((r) => parseGtfsDate(r.end_date))).end;
    if (start && end) return { start, end };
  }

  const calendarDates = tables.get("calendar_dates");
  if (calendarDates && calendarDates.length > 0) {
    const range = minMaxDates(calendarDates.map((r) => parseGtfsDate(r.date)));
    if (range.start && range.end) return range;
  }

  return { start: null, end: null };
}
