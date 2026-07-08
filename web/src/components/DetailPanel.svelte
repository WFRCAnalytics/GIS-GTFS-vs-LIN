<script lang="ts">
  import { appState } from '../lib/store/appState.svelte'
  import { routeTypeLabel } from '../lib/gtfs/routeTypeLabels'
  import { tdmModeLabel } from '../lib/tdm/modeLabels'

  const HEADWAY_FIELDS = ['HEADWAY_1', 'HEADWAY_2', 'HEADWAY_3', 'HEADWAY_4', 'HEADWAY_5']

  let selected = $derived(appState.selectedFeature)

  // GTFS stop -> its serving routes' short_name/color, resolved from the
  // already-loaded GTFS routes (route_ids is a comma-joined string of ids,
  // see build.ts's buildStopRouteInfo() -- one lookup, no re-parsing).
  let gtfsServingRoutes = $derived.by(() => {
    if (selected?.kind !== 'gtfs-stop' || !appState.gtfsRoutesData) return []
    const ids = String(selected.properties.route_ids ?? '')
      .split(',')
      .filter(Boolean)
    const byId = new Map<string, { name: string; color: string }>()
    for (const f of appState.gtfsRoutesData.features) {
      const p = f.properties as Record<string, unknown>
      const id = String(p.route_id)
      if (ids.includes(id) && !byId.has(id)) {
        byId.set(id, { name: String(p.route_short_name ?? id), color: String(p.route_color ?? '#999') })
      }
    }
    return [...byId.values()]
  })

  // TDM stop -> the one TDM route it's on, resolved the same way
  // build-tdm-data.mjs itself joins stop_color (tdm_group + LINEID/line_id).
  let tdmServingRoute = $derived.by(() => {
    if (selected?.kind !== 'tdm-stop' || !appState.tdmRoutesData) return null
    const group = selected.properties.tdm_group
    const lineId = selected.properties.LINEID
    for (const f of appState.tdmRoutesData.features) {
      const p = f.properties as Record<string, unknown>
      if (p.tdm_group === group && p.line_id === lineId) return p
    }
    return null
  })

  // Headway-by-period bars for a TDM route: only populated periods, longer
  // bar = shorter (better) headway, scaled relative to the best one.
  let headwayBars = $derived.by(() => {
    if (selected?.kind !== 'tdm-route') return []
    const values = HEADWAY_FIELDS.map((f, i) => ({ period: i + 1, minutes: Number(selected.properties[f]) })).filter(
      (b) => b.minutes > 0,
    )
    const best = Math.min(...values.map((b) => b.minutes))
    return values.map((b) => ({ ...b, widthPct: (best / b.minutes) * 100 }))
  })

  function close() {
    appState.selectedFeature = null
  }
</script>

{#if selected}
  <aside class="detail-panel">
    <button class="close-btn" onclick={close} aria-label="Close">&times;</button>

    {#if selected.kind === 'gtfs-route'}
      <div class="swatch" style="background: {selected.properties.route_color}"></div>
      <h3>{selected.properties.route_short_name || selected.properties.route_id}</h3>
      {#if selected.properties.route_long_name}<p class="subtitle">{selected.properties.route_long_name}</p>{/if}
      <dl>
        <dt>Type</dt>
        <dd>{routeTypeLabel(selected.properties.route_type)}</dd>
      </dl>
    {:else if selected.kind === 'gtfs-stop'}
      <div class="swatch" style="background: {selected.properties.stop_color}"></div>
      <h3>{selected.properties.stop_name || selected.properties.stop_id}</h3>
      {#if gtfsServingRoutes.length > 0}
        <span class="field-label">Served by</span>
        <div class="chips">
          {#each gtfsServingRoutes as r (r.name)}
            <span class="chip" style="background: {r.color}">{r.name}</span>
          {/each}
        </div>
      {/if}
    {:else if selected.kind === 'tdm-route'}
      <div class="swatch" style="background: {selected.properties.tdm_color}"></div>
      <h3>{selected.properties.NAME}</h3>
      {#if selected.properties.LONGNAME}<p class="subtitle">{selected.properties.LONGNAME}</p>{/if}
      <dl>
        <dt>Mode</dt>
        <dd>{tdmModeLabel(String(selected.properties.tdm_mode))}</dd>
        <dt>Scenario</dt>
        <dd>{selected.properties.tdm_year}</dd>
      </dl>
      {#if headwayBars.length > 0}
        <span class="field-label">Headway by period</span>
        <p class="hint">
          The model's 5 headway slots aren't labeled with actual time-of-day periods in this data -- shown as
          Period 1-5, not "AM peak" etc.
        </p>
        <div class="headway-chart">
          {#each headwayBars as bar (bar.period)}
            <div class="headway-row">
              <span class="headway-label">Period {bar.period}</span>
              <div class="headway-track">
                <div class="headway-fill" style="width: {bar.widthPct}%"></div>
              </div>
              <span class="headway-value">{bar.minutes} min</span>
            </div>
          {/each}
        </div>
      {/if}
    {:else if selected.kind === 'tdm-stop'}
      <div class="swatch" style="background: {selected.properties.tdm_color}"></div>
      <h3>Stop #{selected.properties.SEQNO}</h3>
      {#if tdmServingRoute}
        <p class="subtitle">On {tdmServingRoute.NAME}{tdmServingRoute.LONGNAME ? ` (${tdmServingRoute.LONGNAME})` : ''}</p>
      {/if}
      <dl>
        <dt>Mode</dt>
        <dd>{tdmModeLabel(String(selected.properties.tdm_mode))}</dd>
        <dt>Scenario</dt>
        <dd>{selected.properties.tdm_year}</dd>
      </dl>
    {/if}
  </aside>
{/if}

<style>
  .detail-panel {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    width: 300px;
    background: var(--bg);
    border-left: 1px solid var(--hair);
    box-shadow: -4px 0 16px rgba(2, 60, 91, 0.12);
    padding: 16px;
    overflow-y: auto;
    z-index: 2;
  }
  .close-btn {
    position: absolute;
    top: 10px;
    right: 10px;
    width: 26px;
    height: 26px;
    border: none;
    background: transparent;
    color: var(--label);
    font-size: 20px;
    line-height: 1;
    cursor: pointer;
    border-radius: 50%;
  }
  .close-btn:hover {
    background: var(--hair);
  }
  .swatch {
    width: 40px;
    height: 8px;
    border-radius: 4px;
    margin-bottom: 10px;
  }
  h3 {
    margin: 0 0 4px;
    font-size: 1.05rem;
    color: var(--text);
    padding-right: 24px;
  }
  .subtitle {
    margin: 0 0 12px;
    font-size: 12.5px;
    color: var(--label);
  }
  dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 4px 10px;
    margin: 0 0 12px;
  }
  dt {
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--label);
  }
  dd {
    margin: 0;
    font-size: 13px;
    color: var(--text);
  }
  .field-label {
    display: block;
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--label);
    margin-bottom: 6px;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    padding: 3px 9px;
    border-radius: 999px;
    color: white;
    font-size: 12px;
    font-weight: 600;
  }
  .hint {
    font-size: 11px;
    color: var(--label);
    margin: 0 0 10px;
  }
  .headway-chart {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .headway-row {
    display: grid;
    grid-template-columns: 56px 1fr 48px;
    align-items: center;
    gap: 8px;
  }
  .headway-label {
    font-size: 11.5px;
    color: var(--label);
  }
  .headway-track {
    height: 8px;
    background: var(--hair);
    border-radius: 4px;
    overflow: hidden;
  }
  .headway-fill {
    height: 100%;
    background: var(--wc-light-rail);
    border-radius: 4px;
  }
  .headway-value {
    font-size: 11.5px;
    color: var(--text);
    text-align: right;
  }
</style>
