// Display labels for TDM line-type modes -- matches app.R's tdm_mode_choices
// exactly (proper-cased for display; the underlying values stay lowercase
// since they're the actual tdm_mode property values baked into
// tdm-routes.geojson/tdm-stops.geojson by build-tdm-data.mjs).
export const TDM_MODE_LABELS: Record<string, string> = {
  rail: "Rail",
  brt: "BRT",
  core: "Core",
  express: "Express",
  local: "Local",
};

export function tdmModeLabel(mode: string): string {
  return TDM_MODE_LABELS[mode] ?? mode;
}
