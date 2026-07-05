<script lang="ts" generics="T extends string">
  interface Choice {
    label: string
    value: T
  }
  let { choices, value = $bindable(), accent = 'var(--wfrc-secondary-blue)' }: {
    choices: Choice[]
    value: T
    accent?: string
  } = $props()
</script>

<div class="segmented" role="radiogroup" style={`--accent: ${accent}`}>
  {#each choices as choice (choice.value)}
    <button
      type="button"
      role="radio"
      aria-checked={value === choice.value}
      class:is-active={value === choice.value}
      onclick={() => (value = choice.value)}
    >
      {choice.label}
    </button>
  {/each}
</div>

<style>
  .segmented {
    display: flex;
    width: 100%;
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    background: var(--bg);
  }
  button {
    flex: 1 1 0;
    min-width: 0;
    appearance: none;
    background: transparent;
    border: none;
    border-right: 1px solid var(--border);
    padding: 0.32rem 0.5rem;
    font: inherit;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--label);
    text-align: center;
    white-space: nowrap;
    cursor: pointer;
    transition: background-color 0.15s ease, color 0.15s ease;
  }
  button:last-child {
    border-right: none;
  }
  button:hover:not(.is-active) {
    color: var(--text);
  }
  button.is-active {
    background: var(--accent);
    color: #fff;
    font-weight: 600;
  }
  button:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }
</style>
