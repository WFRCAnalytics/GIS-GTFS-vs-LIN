// Central reactive state for the sidebar, using Svelte 5 runes ($state) so
// every component reading/writing these fields stays in sync without prop
// drilling -- mirrors what the R app's `input$...` reactive values do,
// just as a plain class instead of Shiny's reactive graph.

import type { GtfsZipSize } from "../gtfs/inspect";

export type GtfsSource = "upload" | "url" | "date";
export type CompareMode = "overlay" | "swipe";
export type ShowLayer = "lines" | "stops";

class AppState {
  gtfsEnabled = $state(true);
  tdmEnabled = $state(true);
  // Defaults to URL (pre-filled with UTA's own feed in Sidebar.svelte) --
  // the common case is loading UTA's current feed, no file to pick.
  gtfsSource = $state<GtfsSource>("url");
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
}

export const appState = new AppState();
