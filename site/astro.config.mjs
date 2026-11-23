import { defineConfig } from 'astro/config';

// Published by GitHub Pages at the custom domain https://birdsongs.ai/
// (set in the repo's Settings → Pages; dopeytree.github.io/birdsongs.ai
// redirects there). For another address, set these when building, e.g.
//   SITE_URL=https://example.com SITE_BASE=/some-folder npm run build
// then upload the contents of dist/.
export default defineConfig({
  site: process.env.SITE_URL || 'https://birdsongs.ai',
  base: process.env.SITE_BASE || '/',
});
