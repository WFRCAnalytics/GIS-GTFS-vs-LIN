<script lang="ts">
  import { onDestroy, onMount } from 'svelte'
  import maplibregl from 'maplibre-gl'
  import 'maplibre-gl/dist/maplibre-gl.css'
  import { addClusteredStopLayer, addGtfsRouteLayer, addTdmRouteLayer } from './layers'
  import { loadGtfsFromUpload } from '../sources/upload'

  // Same Carto basemap the R app uses (free, no API key, light/dark pair) --
  // kept for visual continuity between the two apps.
  const CARTO_LIGHT = 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json'

  let container: HTMLDivElement
  let map: maplibregl.Map | undefined
  let mapLoaded = false
  let gtfsLoaded = false
  let gtfsError: string | null = null

  onMount(() => {
    map = new maplibregl.Map({
      container,
      style: CARTO_LIGHT,
      center: [-111.891, 40.7608], // Salt Lake City
      zoom: 9,
    })
    map.addControl(new maplibregl.NavigationControl(), 'top-right')
    map.addControl(new maplibregl.ScaleControl({ unit: 'imperial' }), 'bottom-left')

    map.on('load', async () => {
      mapLoaded = true
      const [routesRes, stopsRes] = await Promise.all([
        fetch(`${import.meta.env.BASE_URL}data/tdm-routes.geojson`),
        fetch(`${import.meta.env.BASE_URL}data/tdm-stops.geojson`),
      ])
      const routes = await routesRes.json()
      const stops = await stopsRes.json()
      addTdmRouteLayer(map!, routes)
      addClusteredStopLayer(map!, 'tdm_stops', stops, 'tdm_color', '#333333')
    })
  })

  onDestroy(() => {
    map?.remove()
  })

  async function onGtfsFileChange(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0]
    if (!file || !map) return
    gtfsError = null
    try {
      const layers = await loadGtfsFromUpload(file)
      if (!gtfsLoaded) {
        addGtfsRouteLayer(map, layers.routesGeoJSON)
        addClusteredStopLayer(map, 'gtfs_stops', layers.stopsGeoJSON, 'stop_color', '#3E7C8B')
        gtfsLoaded = true
      } else {
        ;(map.getSource('gtfs_routes') as maplibregl.GeoJSONSource).setData(layers.routesGeoJSON)
        ;(map.getSource('gtfs_stops') as maplibregl.GeoJSONSource).setData(layers.stopsGeoJSON)
      }
    } catch (err) {
      gtfsError = err instanceof Error ? err.message : String(err)
    }
  }
</script>

<div class="map-container" bind:this={container}></div>

<!-- Temporary GTFS Upload test control (Phase 3) -- real sidebar UI comes later. -->
<div class="gtfs-upload">
  <label>
    GTFS zip:
    <input type="file" accept=".zip" on:change={onGtfsFileChange} disabled={!mapLoaded} />
  </label>
  {#if gtfsError}<p class="error">{gtfsError}</p>{/if}
</div>

<style>
  .map-container {
    position: absolute;
    inset: 0;
  }
  .gtfs-upload {
    position: absolute;
    top: 10px;
    left: 10px;
    background: white;
    padding: 8px 12px;
    border-radius: 6px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
    font-size: 13px;
    z-index: 1;
  }
  .error {
    color: #be2036;
    margin: 4px 0 0;
  }
</style>
