import maplibregl, { type Map as MapLibreMap } from "maplibre-gl";

// Port of app.R's tooltip = "route_short_name" / tooltip = "NAME" (mapgl's
// add_line_layer(tooltip = ..., tooltip_style = "light")) -- with no static
// legend for either network (8 individually-colored TDM rail lines plus 4
// bus tiers, GTFS routes colored by the feed's own route_color), hovering a
// line to identify it is how both apps substitute for one. Always "light"
// style (dark text on a light box) regardless of the app's own dark mode,
// matching app.R's own reasoning: MapLibre's default popup CSS is a
// hardcoded white background with no explicit text color, so it inherits
// whatever color the surrounding dark-mode page currently has and becomes
// unreadable unless forced light here too.
function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// applyLayers.ts fully removes and re-adds gtfs_routes/tdm_routes on every
// filter/theme change (see its own comment on why) -- MapLibre's
// map.on(event, layerId, handler) form filters by layer *id string*, not a
// live reference to the removed Layer object, so a listener attached once
// stays valid across those re-adds. This guard just stops repeated
// applyLayers() calls from stacking up duplicate listeners on the same
// (map, layerId) pair.
const attached = new WeakMap<MapLibreMap, Set<string>>();

export function addHoverTooltip(map: MapLibreMap, layerId: string, property: string) {
  const seen = attached.get(map) ?? new Set<string>();
  attached.set(map, seen);
  if (seen.has(layerId)) return;
  seen.add(layerId);

  const popup = new maplibregl.Popup({
    closeButton: false,
    closeOnClick: false,
    className: "hover-tooltip",
  });

  map.on("mousemove", layerId, (e) => {
    map.getCanvas().style.cursor = "pointer";
    const feature = e.features?.[0];
    const value = feature?.properties?.[property];
    if (!value) return;
    popup.setLngLat(e.lngLat).setHTML(escapeHtml(String(value))).addTo(map);
  });

  map.on("mouseleave", layerId, () => {
    map.getCanvas().style.cursor = "";
    popup.remove();
  });
}
