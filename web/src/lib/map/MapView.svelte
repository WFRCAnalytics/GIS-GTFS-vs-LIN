<script lang="ts">
  import { onDestroy, onMount } from 'svelte'
  import maplibregl from 'maplibre-gl'
  import 'maplibre-gl/dist/maplibre-gl.css'
  import { addClusteredStopLayer, addTdmRouteLayer } from './layers'

  // Same Carto basemap the R app uses (free, no API key, light/dark pair) --
  // kept for visual continuity between the two apps.
  const CARTO_LIGHT = 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json'

  let container: HTMLDivElement
  let map: maplibregl.Map | undefined

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
</script>

<div class="map-container" bind:this={container}></div>

<style>
  .map-container {
    position: absolute;
    inset: 0;
  }
</style>
