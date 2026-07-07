import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// Served as a GitHub Pages *project* page (https://wfrcanalytics.github.io/GIS-GTFS-vs-LIN/),
// not a user/org root page or custom domain -- base must match the repo name.
// https://vite.dev/config/
export default defineConfig({
  base: '/GIS-GTFS-vs-LIN/',
  plugins: [svelte()],
  resolve: {
    alias: {
      // @maplibre/maplibre-gl-compare uses Node's EventEmitter internally.
      // Vite externalizes bare Node built-ins for the browser by default,
      // which leaves `events` unresolved at runtime ("EventEmitter is not
      // a constructor", confirmed live) -- alias it to the userland
      // browser-compatible `events` package instead.
      events: 'events',
    },
  },
})
