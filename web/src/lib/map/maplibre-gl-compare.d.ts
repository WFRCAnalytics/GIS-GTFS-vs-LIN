// @maplibre/maplibre-gl-compare ships no TypeScript types of its own --
// this is a minimal ambient declaration covering the API this app actually
// uses (see its own API.md, ported to R's mapgl::compare() the same way).
declare module "@maplibre/maplibre-gl-compare" {
  import type { Map as MapLibreMap } from "maplibre-gl";

  export default class Compare {
    constructor(
      a: MapLibreMap,
      b: MapLibreMap,
      container: string | HTMLElement,
      options?: { orientation?: "vertical" | "horizontal"; mousemove?: boolean },
    );
    setSlider(x: number): void;
    on(type: "slideend", fn: (data: unknown) => void): this;
    off(type: "slideend", fn: (data: unknown) => void): this;
    remove(): void;
  }
}
