<script lang="ts">
  // Matches app.R's navbar toggle (bslib's input_dark_mode()): an
  // icon-only circular button using the same sun-morphs-into-moon SVG
  // design (a well-known open dark-mode-toggle icon pattern, distinct
  // from WFRC's own branded assets) rather than a text-labeled button.
  let { checked = $bindable() }: { checked: boolean } = $props()
</script>

<button
  type="button"
  class="theme-toggle"
  title={checked ? 'Switch to light mode' : 'Switch to dark mode'}
  aria-label={checked ? 'Switch to light mode' : 'Switch to dark mode'}
  onclick={() => (checked = !checked)}
>
  <svg class="sun-and-moon" class:is-dark={checked} aria-hidden="true" viewBox="0 0 24 24">
    <mask class="moon" id="moon-mask">
      <rect x="0" y="0" width="100%" height="100%" fill="white" />
      <circle cx="25" cy="10" r="6" fill="black" />
    </mask>
    <circle class="sun" cx="12" cy="12" r="6" mask="url(#moon-mask)" fill="currentColor" />
    <g class="sun-beams" stroke="currentColor">
      <line x1="12" y1="1" x2="12" y2="3" />
      <line x1="12" y1="21" x2="12" y2="23" />
      <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
      <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
      <line x1="1" y1="12" x2="3" y2="12" />
      <line x1="21" y1="12" x2="23" y2="12" />
      <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
      <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
    </g>
  </svg>
</button>

<style>
  .theme-toggle {
    --size: 29px;
    width: var(--size);
    height: var(--size);
    padding: 4px;
    border: none;
    border-radius: 50%;
    background: transparent;
    color: white;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: 0 0 auto;
    transition: background-color 0.15s ease;
  }
  .theme-toggle:hover {
    background: rgba(255, 255, 255, 0.15);
  }
  .theme-toggle:focus-visible {
    outline: 2px solid white;
    outline-offset: 2px;
  }
  .sun-and-moon {
    width: 21px;
    height: 21px;
    stroke-linecap: round;
  }
  .sun-and-moon > .sun {
    transition: transform 0.4s ease;
    transform-origin: center;
  }
  .sun-and-moon > .sun-beams {
    stroke-width: 2px;
    transition: transform 0.4s ease, opacity 0.4s ease;
  }
  .sun-and-moon .moon circle {
    transition: transform 0.4s ease;
  }
  .sun-and-moon.is-dark > .sun {
    transform: scale(1.75);
  }
  .sun-and-moon.is-dark > .sun-beams {
    opacity: 0;
    transform: rotate(-25deg);
  }
  .sun-and-moon.is-dark .moon circle {
    transform: translateX(-7px);
  }
</style>
