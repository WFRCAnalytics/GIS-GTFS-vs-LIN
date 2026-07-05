import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// Served as a GitHub Pages *project* page (https://wfrcanalytics.github.io/GIS-GTFS-vs-LIN/),
// not a user/org root page or custom domain -- base must match the repo name.
// https://vite.dev/config/
export default defineConfig({
  base: '/GIS-GTFS-vs-LIN/',
  plugins: [svelte()],
})
