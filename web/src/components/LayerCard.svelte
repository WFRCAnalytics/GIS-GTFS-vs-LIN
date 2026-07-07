<script lang="ts">
  import type { Snippet } from 'svelte'
  let { accent, label, enabled = $bindable(), children }: {
    accent: string
    label: string
    enabled: boolean
    children: Snippet
  } = $props()
</script>

<div class="sb-card" style={`--accent: ${accent}`}>
  <div class="sb-card-head">
    <span class="sb-card-label">{label}</span>
    <label class="switch">
      <input type="checkbox" bind:checked={enabled} />
      <span class="slider"></span>
    </label>
  </div>
  {#if enabled}
    <div class="sb-card-body">
      {@render children()}
    </div>
  {/if}
</div>

<style>
  .sb-card {
    border: 1px solid var(--hair);
    border-left: 3px solid var(--accent);
    border-radius: 10px;
    background: color-mix(in srgb, var(--accent) 4%, var(--bg));
    box-shadow: var(--card-shadow);
    padding: 10px 12px 11px;
  }
  .sb-card-head {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 9px;
  }
  .sb-card-label {
    font-family: 'Inter', sans-serif;
    font-weight: 600;
    font-size: 0.74rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--section);
  }
  .sb-card-body {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .switch {
    margin-left: auto;
    position: relative;
    display: inline-block;
    width: 34px;
    height: 18px;
  }
  .switch input {
    opacity: 0;
    width: 0;
    height: 0;
  }
  .slider {
    position: absolute;
    inset: 0;
    background: var(--border);
    border-radius: 999px;
    cursor: pointer;
    transition: background-color 0.15s ease;
  }
  .slider::before {
    content: '';
    position: absolute;
    height: 14px;
    width: 14px;
    left: 2px;
    top: 2px;
    background: white;
    border-radius: 50%;
    transition: transform 0.15s ease;
  }
  input:checked + .slider {
    background: var(--wfrc-blue);
  }
  input:checked + .slider::before {
    transform: translateX(16px);
  }
</style>
