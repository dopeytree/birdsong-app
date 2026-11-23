#!/bin/zsh -l
# Double-click in Finder. Shows the splash web page (site/) in your browser.
# Edits to site/ show at once. Close this window to stop it.
# Also reachable from an iPhone or iPad on the same Wi-Fi: the address is
# printed below as "Network".
cd "$(dirname "$0")/site"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[ -d node_modules ] || npm install --no-audit --no-fund
(sleep 3; open "http://localhost:4321/birdsongs.ai/") &
npx astro dev --port 4321 --host
