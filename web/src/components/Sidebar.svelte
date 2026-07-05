<script lang="ts">
  import { appState, type GtfsSource } from '../lib/store/appState.svelte'
  import { loadGtfsUpload, loadGtfsUrl, loadGtfsDate } from '../lib/store/gtfsLoader'
  import { getMobilityDatabaseToken, setMobilityDatabaseToken } from '../lib/storage/mobilityDatabaseToken'
  import SegmentedControl from './SegmentedControl.svelte'
  import ChipGroup from './ChipGroup.svelte'
  import LayerCard from './LayerCard.svelte'

  const showChoices = [
    { label: 'Lines', value: 'lines' as const },
    { label: 'Stops', value: 'stops' as const },
  ]
  const gtfsSourceChoices: { label: string; value: GtfsSource }[] = [
    { label: 'Upload', value: 'upload' },
    { label: 'URL', value: 'url' },
    { label: 'By date', value: 'date' },
  ]
  const allTdmModes = [
    { label: 'rail', value: 'rail' },
    { label: 'brt', value: 'brt' },
    { label: 'core', value: 'core' },
    { label: 'express', value: 'express' },
    { label: 'local', value: 'local' },
  ]

  let urlInput = $state('')
  let dateInput = $state('')
  let tokenInput = $state(getMobilityDatabaseToken() ?? '')
  let showSettings = $state(false)

  function onFileChange(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0]
    if (file) loadGtfsUpload(file)
  }
  function onUrlLoad() {
    if (urlInput) loadGtfsUrl(urlInput)
  }
  function onDateLoad() {
    if (dateInput) loadGtfsDate(new Date(dateInput))
  }
  function onSaveToken() {
    setMobilityDatabaseToken(tokenInput)
    showSettings = false
  }
</script>

<aside class="sidebar">
  <section class="sb-section">
    <span class="section-label">Comparison</span>
    <SegmentedControl
      choices={[
        { label: 'Overlay', value: 'overlay' as const },
        { label: 'Swipe', value: 'swipe' as const },
      ]}
      bind:value={appState.compareMode}
      accent="var(--wfrc-yellow)"
    />
    {#if !appState.bothEnabled}
      <p class="hint">Enable both GTFS and TDM to use Swipe.</p>
    {/if}
  </section>

  <LayerCard accent="var(--wfrc-secondary-blue)" label="GTFS" bind:enabled={appState.gtfsEnabled}>
    <div class="sb-field">
      <span class="field-label">Source</span>
      <SegmentedControl choices={gtfsSourceChoices} bind:value={appState.gtfsSource} />
    </div>

    {#if appState.gtfsSource === 'upload'}
      <div class="sb-field">
        <span class="field-label">GTFS zip file</span>
        <input type="file" accept=".zip" onchange={onFileChange} />
      </div>
    {:else if appState.gtfsSource === 'url'}
      <div class="sb-field">
        <span class="field-label">Feed URL</span>
        <div class="row">
          <input type="text" bind:value={urlInput} placeholder="https://.../gtfs.zip" />
          <button onclick={onUrlLoad}>Load feed</button>
        </div>
        <p class="hint">Works only if the feed's server allows cross-origin browser requests (CORS) -- many don't. Use Upload if this fails.</p>
      </div>
    {:else}
      <div class="sb-field">
        <span class="field-label">Date</span>
        <div class="row">
          <input type="date" bind:value={dateInput} />
          <button onclick={onDateLoad}>Find feed</button>
        </div>
        <button class="link-button" onclick={() => (showSettings = !showSettings)}>
          {getMobilityDatabaseToken() ? 'Change' : 'Set'} Mobility Database token
        </button>
        {#if showSettings}
          <div class="row">
            <input type="password" bind:value={tokenInput} placeholder="Your free refresh token" />
            <button onclick={onSaveToken}>Save</button>
          </div>
          <p class="hint">
            Your own free token from <a href="https://mobilitydatabase.org" target="_blank" rel="noreferrer">mobilitydatabase.org</a>,
            stored only in this browser.
          </p>
        {/if}
      </div>
    {/if}

    {#if appState.gtfsError}<p class="error">{appState.gtfsError}</p>{/if}

    <div class="sb-field">
      <span class="field-label">Show</span>
      <ChipGroup choices={showChoices} bind:selected={appState.gtfsDisplay} accent="var(--wfrc-secondary-blue)" />
    </div>
  </LayerCard>

  <LayerCard accent="var(--wc-light-rail)" label="TDM" bind:enabled={appState.tdmEnabled}>
    <div class="sb-field-row">
      <div class="sb-field">
        <span class="field-label">Year</span>
        <select bind:value={appState.tdmYear}>
          <option value="2023">2023</option>
          <option value="2055UF">2055UF</option>
        </select>
      </div>
      <div class="sb-field">
        <span class="field-label">Line types</span>
        <ChipGroup choices={allTdmModes} bind:selected={appState.tdmModes} accent="var(--wc-light-rail)" />
      </div>
    </div>
    <div class="sb-field">
      <span class="field-label">Show</span>
      <ChipGroup choices={showChoices} bind:selected={appState.tdmDisplay} accent="var(--wc-light-rail)" />
    </div>
  </LayerCard>
</aside>

<style>
  .sidebar {
    width: 340px;
    height: 100%;
    overflow-y: auto;
    padding: 12px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    background: var(--body-bg);
    border-right: 1px solid var(--hair);
    font-size: 13px;
  }
  .sb-section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .section-label {
    font-family: 'Inter', sans-serif;
    font-weight: 600;
    font-size: 0.74rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--section);
  }
  .sb-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .sb-field-row {
    display: flex;
    gap: 10px;
  }
  .sb-field-row > .sb-field:first-child {
    flex: 0 0 34%;
  }
  .sb-field-row > .sb-field:last-child {
    flex: 1 1 auto;
  }
  .field-label {
    font-family: 'Inter', sans-serif;
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--label);
  }
  .row {
    display: flex;
    gap: 6px;
  }
  input[type='text'],
  input[type='password'],
  input[type='date'],
  select {
    flex: 1;
    font-size: 13px;
    padding: 0.26rem 0.55rem;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: var(--bg);
    color: var(--text);
  }
  button {
    font-size: 12.5px;
    padding: 0.26rem 0.6rem;
    border-radius: 8px;
    border: 1px solid var(--wfrc-blue);
    background: var(--wfrc-blue);
    color: white;
    cursor: pointer;
  }
  .link-button {
    background: none;
    border: none;
    color: var(--wfrc-secondary-blue);
    padding: 0;
    text-align: left;
    font-size: 12px;
    text-decoration: underline;
  }
  .hint {
    font-size: 11.5px;
    color: var(--label);
    margin: 0;
  }
  .error {
    color: #be2036;
    font-size: 12px;
    margin: 0;
  }
</style>
