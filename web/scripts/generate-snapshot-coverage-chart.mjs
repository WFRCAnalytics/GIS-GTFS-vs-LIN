#!/usr/bin/env node
// Renders web/public/data/mobility-database-cache/manifest.json as a timeline SVG --
// one row per cached GTFS snapshot, showing either its real service
// validity range (a bar) or, for the majority of entries where Mobility
// Database never recorded a service_date_range at all, a single tick at
// its downloadedAt date (a known-state marker, not a fabricated range).
// Pure string-templated SVG, zero dependencies -- GitHub renders SVG
// natively in Markdown, so there's no PNG rasterization step needed.
//
// Called automatically at the end of fetch-mobility-database-snapshots.mjs
// so the chart always reflects the current cache; run standalone with
// `node web/scripts/generate-snapshot-coverage-chart.mjs` to regenerate
// without re-fetching.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MANIFEST_PATH = join(import.meta.dirname, "..", "public", "data", "mobility-database-cache", "manifest.json");
const OUT_PATH = join(import.meta.dirname, "..", "..", "gtfs-snapshot-coverage.svg");

const MARGIN = { top: 50, right: 30, bottom: 40, left: 30 };
const ROW_HEIGHT = 6;
const CHART_WIDTH = 1200;
const RANGE_COLOR = "#023c5b"; // wfrc-blue
const MARKER_COLOR = "#94a2ae"; // neutral gray

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
}

function main() {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8"));

  // Chronological effective date per entry (real range start, else the only
  // date we have at all) -- rows are sorted oldest-to-newest, top-to-bottom.
  const rows = manifest
    .map((m) => ({
      ...m,
      effectiveDate: m.serviceDateRangeStart ?? m.downloadedAt,
    }))
    .filter((m) => m.effectiveDate)
    .sort((a, b) => a.effectiveDate.localeCompare(b.effectiveDate));

  const allDates = rows.flatMap((m) => [m.serviceDateRangeStart, m.serviceDateRangeEnd, m.downloadedAt].filter(Boolean));
  const minDate = allDates.reduce((a, b) => (a < b ? a : b));
  const maxDate = allDates.reduce((a, b) => (a > b ? a : b));
  const minTime = new Date(minDate).getTime();
  const maxTime = new Date(maxDate).getTime();

  const chartHeight = rows.length * ROW_HEIGHT;
  const width = MARGIN.left + CHART_WIDTH + MARGIN.right;
  const height = MARGIN.top + chartHeight + MARGIN.bottom;

  const xForDate = (dateStr) => {
    const t = new Date(dateStr).getTime();
    return MARGIN.left + ((t - minTime) / (maxTime - minTime)) * CHART_WIDTH;
  };

  const rangeCount = rows.filter((m) => m.serviceDateRangeStart && m.serviceDateRangeEnd).length;
  const markerCount = rows.length - rangeCount;

  const rowEls = rows
    .map((m, i) => {
      const y = MARGIN.top + i * ROW_HEIGHT + ROW_HEIGHT / 2;
      const title = m.mergedFrom
        ? `${m.datasetId} (+ ${m.mergedFrom.length - 1} identical capture(s))`
        : m.datasetId;
      if (m.serviceDateRangeStart && m.serviceDateRangeEnd) {
        const x1 = xForDate(m.serviceDateRangeStart);
        const x2 = xForDate(m.serviceDateRangeEnd);
        return `<rect x="${x1.toFixed(1)}" y="${(y - 2).toFixed(1)}" width="${Math.max(1, x2 - x1).toFixed(1)}" height="4" fill="${RANGE_COLOR}" rx="1"><title>${esc(title)}: ${m.serviceDateRangeStart} to ${m.serviceDateRangeEnd}</title></rect>`;
      }
      const x = xForDate(m.effectiveDate);
      return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="1.6" fill="${MARKER_COLOR}"><title>${esc(title)}: known as of ${m.effectiveDate} (no recorded service range)</title></circle>`;
    })
    .join("\n    ");

  // Year gridlines/labels across the full span.
  const startYear = new Date(minDate).getUTCFullYear();
  const endYear = new Date(maxDate).getUTCFullYear();
  const yearEls = [];
  for (let y = startYear; y <= endYear; y++) {
    const x = xForDate(`${y}-01-01`);
    if (x < MARGIN.left || x > MARGIN.left + CHART_WIDTH) continue;
    yearEls.push(
      `<line x1="${x.toFixed(1)}" y1="${MARGIN.top}" x2="${x.toFixed(1)}" y2="${MARGIN.top + chartHeight}" stroke="#e2e8ee" stroke-width="1"/>`,
      `<text x="${x.toFixed(1)}" y="${MARGIN.top - 10}" font-size="11" fill="#6a7682" text-anchor="middle" font-family="sans-serif">${y}</text>`,
    );
  }

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" font-family="sans-serif">
  <rect width="${width}" height="${height}" fill="#ffffff"/>
  <text x="${MARGIN.left}" y="20" font-size="14" font-weight="700" fill="#151515">GTFS snapshot cache coverage (${rows.length} unique captures, ${minDate} to ${maxDate})</text>
  <g>
    ${yearEls.join("\n    ")}
  </g>
  <g>
    ${rowEls}
  </g>
  <g transform="translate(${MARGIN.left}, ${MARGIN.top + chartHeight + 22})">
    <rect x="0" y="-8" width="14" height="4" fill="${RANGE_COLOR}" rx="1"/>
    <text x="20" y="-4" font-size="11" fill="#6a7682">Known service date range (${rangeCount})</text>
    <circle cx="230" cy="-6" r="1.6" fill="${MARKER_COLOR}"/>
    <text x="240" y="-4" font-size="11" fill="#6a7682">Downloaded-at only, exact range unknown (${markerCount})</text>
  </g>
</svg>
`;

  writeFileSync(OUT_PATH, svg);
  console.log(`Wrote ${OUT_PATH} (${rows.length} rows, ${rangeCount} ranged, ${markerCount} marker-only)`);
}

main();
