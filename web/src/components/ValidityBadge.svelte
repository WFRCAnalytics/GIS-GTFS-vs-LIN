<script lang="ts">
  import { appState } from '../lib/store/appState.svelte'
  import { formatValidityRange } from '../lib/format/validityRange'

  let gtfsPart = $derived(
    !appState.gtfsEnabled
      ? 'Off'
      : appState.gtfsLoading
        ? 'Loading…'
        : formatValidityRange(appState.gtfsValidityStart, appState.gtfsValidityEnd) || 'No feed loaded',
  )
  let tdmPart = $derived(
    !appState.tdmEnabled ? 'Off' : `${appState.tdmYear} (${[...appState.tdmModes].join(', ')})`,
  )
</script>

<div class="map-badge">
  <span class="dot" class:off={!appState.gtfsEnabled} style="background: var(--wfrc-secondary-blue)"></span>
  <span class="dim">GTFS</span>
  <span class="seg">{gtfsPart}</span>
  <span class="sep">|</span>
  <span class="dot" class:off={!appState.tdmEnabled} style="background: var(--wc-light-rail)"></span>
  <span class="dim">TDM</span>
  <span class="seg">{tdmPart}</span>
</div>

<style>
  .map-badge {
    position: absolute;
    top: 10px;
    left: 10px;
    z-index: 1;
    background: color-mix(in srgb, var(--bg) 80%, transparent);
    backdrop-filter: blur(12px) saturate(1.3);
    border: 1px solid var(--hair);
    border-radius: 11px;
    box-shadow: 0 6px 20px rgba(2, 60, 91, 0.16), 0 1px 3px rgba(2, 60, 91, 0.1);
    padding: 8px 14px;
    font-size: 12.5px;
    white-space: nowrap;
  }
  .dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    margin-right: 4px;
  }
  .dot.off {
    opacity: 0.3;
  }
  .dim {
    color: var(--label);
    margin-right: 4px;
  }
  .seg {
    font-family: 'Fira Code', ui-monospace, monospace;
    font-weight: 500;
    letter-spacing: -0.02em;
  }
  .sep {
    color: var(--border);
    margin: 0 8px;
  }
</style>
