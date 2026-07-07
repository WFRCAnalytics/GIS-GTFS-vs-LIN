<script lang="ts">
  import MapView from './lib/map/MapView.svelte'
  import Sidebar from './components/Sidebar.svelte'
  import { appState } from './lib/store/appState.svelte'

  $effect(() => {
    document.body.dataset.theme = appState.darkMode ? 'dark' : 'light'
  })
</script>

<div class="app">
  <header>
    <span class="title">
      <img
        src="{import.meta.env.BASE_URL}brand/WFRC_logo_abbreviated_white_transparent.png"
        height="28"
        alt="WFRC logo"
      />
      TDM vs GTFS
    </span>
    <button class="theme-toggle" onclick={() => (appState.darkMode = !appState.darkMode)}>
      {appState.darkMode ? '☀️ Light' : '🌙 Dark'}
    </button>
  </header>
  <div class="body">
    <Sidebar />
    <MapView />
  </div>
</div>

<style>
  .app {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 16px;
    background: var(--wfrc-blue);
    color: white;
    flex: 0 0 auto;
  }
  .title {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 700;
    font-size: 1rem;
  }
  .theme-toggle {
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.4);
    color: white;
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 12px;
    cursor: pointer;
  }
  .body {
    flex: 1;
    display: flex;
    min-height: 0;
  }
</style>
