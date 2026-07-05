import maplibregl, { type Map as MapLibreMap } from "maplibre-gl";

// Same Carto basemap pair the R app uses (free, no API key) -- light/dark
// follows the app's own theme toggle, matching app.R's carto_style().
export const CARTO_LIGHT = "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json";
export const CARTO_DARK = "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json";

export function cartoStyle(dark: boolean) {
  return dark ? CARTO_DARK : CARTO_LIGHT;
}

export function createMap(container: HTMLElement, dark: boolean): MapLibreMap {
  const map = new maplibregl.Map({
    container,
    style: cartoStyle(dark),
    center: [-111.891, 40.7608], // Salt Lake City
    zoom: 9,
  });
  map.addControl(new maplibregl.NavigationControl(), "top-right");
  map.addControl(new maplibregl.ScaleControl({ unit: "imperial" }), "bottom-left");
  return map;
}
