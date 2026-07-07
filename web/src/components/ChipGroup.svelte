<script lang="ts" generics="T extends string">
  interface Choice {
    label: string
    value: T
  }
  let { choices, selected = $bindable(), accent = 'var(--wfrc-secondary-blue)' }: {
    choices: Choice[]
    selected: Set<T>
    accent?: string
  } = $props()

  function toggle(value: T) {
    const next = new Set(selected)
    if (next.has(value)) next.delete(value)
    else next.add(value)
    selected = next
  }
</script>

<div class="chip-group" role="group" style={`--accent: ${accent}`}>
  {#each choices as choice (choice.value)}
    <button
      type="button"
      role="checkbox"
      aria-checked={selected.has(choice.value)}
      class:is-active={selected.has(choice.value)}
      onclick={() => toggle(choice.value)}
    >
      {choice.label}
    </button>
  {/each}
</div>

<style>
  .chip-group {
    display: flex;
    gap: 7px;
    flex-wrap: wrap;
  }
  button {
    appearance: none;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: transparent;
    padding: 0.22rem 0.65rem;
    font: inherit;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--label);
    cursor: pointer;
    transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  }
  button:hover {
    border-color: var(--label);
  }
  button.is-active {
    background: color-mix(in srgb, var(--accent) 14%, transparent);
    border-color: var(--accent);
    color: var(--text);
  }
  button:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }
</style>
