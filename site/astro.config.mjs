import { defineConfig } from 'astro/config';

// Where the site lives. By default GitHub Pages: dopeytree.github.io/birdsongs.ai/
// For another host, set these when building, e.g. at the top of a domain:
//   SITE_URL=https://birdsongs.ai SITE_BASE=/ npm run build
// then upload the contents of dist/.
export default defineConfig({
  site: process.env.SITE_URL || 'https://dopeytree.github.io',
  base: process.env.SITE_BASE || '/birdsongs.ai',
});
