<script lang="ts">
  import { onDestroy, onMount } from 'svelte'
  import type { Map as MapLibreMap } from 'maplibre-gl'
  import Compare from '@maplibre/maplibre-gl-compare'
  import 'maplibre-gl/dist/maplibre-gl.css'
  import '@maplibre/maplibre-gl-compare/dist/maplibre-gl-compare.css'
  import { createMap, cartoStyle } from './setup'
  import { applyLayers, applyVisibility, type MapLayerData } from './applyLayers'
  import { appState } from '../store/appState.svelte'
  import ValidityBadge from '../../components/ValidityBadge.svelte'

  let overlayContainer: HTMLDivElement
  let gtfsContainer: HTMLDivElement
  let tdmContainer: HTMLDivElement
  let compareContainer: HTMLDivElement

  let overlayMap: MapLibreMap | undefined
  let gtfsMap: MapLibreMap | undefined
  let tdmMap: MapLibreMap | undefined
  let compareInstance: Compare | undefined

  let overlayReady = $state(false)
  let swipeReady = $state(false)

  let tdmData: MapLayerData = { tdmRoutes: null, tdmStops: null }

  onMount(() => {
    overlayMap = createMap(overlayContainer, appState.darkMode)
    overlayMap.on('load', async () => {
      overlayReady = true
      const [routesRes, stopsRes] = await Promise.all([
        fetch(`${import.meta.env.BASE_URL}data/tdm-routes.geojson`),
        fetch(`${import.meta.env.BASE_URL}data/tdm-stops.geojson`),
      ])
      tdmData = { tdmRoutes: await routesRes.json(), tdmStops: await stopsRes.json() }
      applyLayers(overlayMap!, 'both', tdmData)
    })
  })

  onDestroy(() => {
    compareInstance?.remove()
    overlayMap?.remove()
    gtfsMap?.remove()
    tdmMap?.remove()
  })

  function setupSwipeMaps() {
    if (swipeReady) return
    gtfsMap = createMap(gtfsContainer, appState.darkMode)
    tdmMap = createMap(tdmContainer, appState.darkMode)
    let loaded = 0
    const onBothLoaded = () => {
      loaded++
      if (loaded < 2) return
      swipeReady = true
      applyLayers(gtfsMap!, 'gtfs', tdmData)
      applyLayers(tdmMap!, 'tdm', tdmData)
      compareInstance = new Compare(gtfsMap!, tdmMap!, compareContainer, { orientation: 'vertical' })
    }
    gtfsMap.on('load', onBothLoaded)
    tdmMap.on('load', onBothLoaded)
  }

  // Compare mode: lazily bootstrap the two swipe maps the first time it's
  // selected, then just toggle container visibility afterward -- same
  // "session-long singleton, nothing to re-bootstrap" approach app.R uses.
  $effect(() => {
    if (appState.compareMode === 'swipe' && appState.bothEnabled) {
      setupSwipeMaps()
    }
  })

  // Full layer rebuild whenever the underlying data or the TDM year/mode
  // filter changes (filter changes need a source re-set for stops, see
  // filterTdmStopsData()'s comment, so a full rebuild is simplest here).
  $effect(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions -- establishes the reactive dependency
    ;[appState.gtfsRoutesData, appState.gtfsStopsData, appState.tdmYear, appState.tdmModes]
    if (overlayReady) applyLayers(overlayMap!, 'both', tdmData)
    if (swipeReady) {
      applyLayers(gtfsMap!, 'gtfs', tdmData)
      applyLayers(tdmMap!, 'tdm', tdmData)
    }
  })

  // Cheap visibility-only toggles (enable switches, Show chips).
  $effect(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    ;[appState.gtfsEnabled, appState.gtfsDisplay, appState.tdmEnabled, appState.tdmDisplay]
    if (overlayReady) applyVisibility(overlayMap!)
    if (swipeReady) {
      applyVisibility(gtfsMap!)
      applyVisibility(tdmMap!)
    }
  })

  // Dark mode: MapLibre's setStyle() diffs away any layer/source that isn't
  // part of either style's own declared layers, so our custom layers don't
  // survive a style swap -- re-apply everything once the new style loads.
  $effect(() => {
    const dark = appState.darkMode
    const style = cartoStyle(dark)
    if (overlayMap) {
      overlayMap.once('style.load', () => applyLayers(overlayMap!, 'both', tdmData))
      overlayMap.setStyle(style)
    }
    if (gtfsMap && tdmMap) {
      gtfsMap.once('style.load', () => applyLayers(gtfsMap!, 'gtfs', tdmData))
      tdmMap.once('style.load', () => applyLayers(tdmMap!, 'tdm', tdmData))
      gtfsMap.setStyle(style)
      tdmMap.setStyle(style)
    }
  })
</script>

<div class="map-view">
  <div class="pane" class:hidden={appState.compareMode !== 'overlay'} bind:this={overlayContainer}></div>
  <div class="pane" class:hidden={appState.compareMode !== 'swipe'} bind:this={compareContainer}>
    <div class="compare-half" bind:this={gtfsContainer}></div>
    <div class="compare-half" bind:this={tdmContainer}></div>
  </div>
  <ValidityBadge />
</div>

<style>
  .map-view {
    position: relative;
    flex: 1;
    height: 100%;
  }
  .pane {
    position: absolute;
    inset: 0;
  }
  .pane.hidden {
    visibility: hidden;
    pointer-events: none;
  }
  .compare-half {
    position: absolute;
    inset: 0;
  }
</style>
