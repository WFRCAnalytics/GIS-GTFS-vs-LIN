// Central reactive state for the sidebar, using Svelte 5 runes ($state) so
// every component reading/writing these fields stays in sync without prop
// drilling -- mirrors what the R app's `input$...` reactive values do,
// just as a plain class instead of Shiny's reactive graph.

import type { GtfsZipSize } from "../gtfs/inspect";

export type GtfsSource = "snapshot" | "url" | "date" | "upload";
export type CompareMode = "overlay" | "swipe";
export type ShowLayer = "lines" | "stops";

class AppState {
  gtfsEnabled = $state(true);
  tdmEnabled = $state(true);
  // Defaults to Snapshot, matching app.R -- the only source that always
  // works with zero setup on a static site (same-origin static files, no
  // CORS/token concerns at all, unlike URL/By date).
  gtfsSource = $state<GtfsSource>("snapshot");
  gtfsDisplay = $state<Set<ShowLayer>>(new Set(["lines", "stops"]));
  tdmDisplay = $state<Set<ShowLayer>>(new Set(["lines", "stops"]));

  tdmYear = $state("2023");
  tdmModes = $state<Set<string>>(new Set(["rail", "brt", "core", "express", "local"]));

  compareMode = $state<CompareMode>("overlay");
  bothEnabled = $derived(this.gtfsEnabled && this.tdmEnabled);

  darkMode = $state(false);

  gtfsValidityStart = $state<Date | null>(null);
  gtfsValidityEnd = $state<Date | null>(null);
  gtfsLoading = $state(false);
  gtfsError = $state<string | null>(null);
  gtfsProgress = $state<string | null>(null);

  // Set by gtfsLoader.ts's pre-flight size check when a feed's stop_times +
  // shapes exceed inspect.ts's LARGE_FEED_BYTES -- non-null while the
  // "Cancel"/"Try anyway" gate is showing (see the GTFS card in
  // Sidebar.svelte), matching GTFSx's own soft-warning gate rather than a
  // hard reject.
  gtfsPendingLarge = $state<GtfsZipSize | null>(null);

  // Set by gtfsLoader.ts once a load finishes; MapView.svelte watches these
  // (via $effect) to push updated data into the map -- Sidebar triggers a
  // load, MapView owns the actual map instance, this store is what
  // decouples the two without prop drilling.
  gtfsRoutesData = $state<GeoJSON.FeatureCollection | null>(null);
  gtfsStopsData = $state<GeoJSON.FeatureCollection | null>(null);

  // Set once by MapView.svelte on mount (static data, loaded once) -- kept
  // here rather than as a local MapView variable so DetailPanel.svelte can
  // also resolve a clicked TDM stop's serving route without prop drilling.
  tdmRoutesData = $state<GeoJSON.FeatureCollection | null>(null);
  tdmStopsData = $state<GeoJSON.FeatureCollection | null>(null);

  // Set by clickDetail.ts when a route/stop feature is clicked on the map;
  // null when nothing is selected. DetailPanel.svelte renders based on
  // this -- see its own file for the per-type property shapes.
  selectedFeature = $state<SelectedFeature | null>(null);
}

export type SelectedFeature =
  | { kind: "gtfs-route"; properties: Record<string, unknown> }
  | { kind: "gtfs-stop"; properties: Record<string, unknown> }
  | { kind: "tdm-route"; properties: Record<string, unknown> }
  | { kind: "tdm-stop"; properties: Record<string, unknown> };

export const appState = new AppState();
