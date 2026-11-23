#!/bin/zsh -l
# Double-click in Finder. Shows the splash web page (site/) in your browser.
# Edits to site/ show at once. Close this window to stop it.
cd "$(dirname "$0")/site"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
[ -d node_modules ] || npm install --no-audit --no-fund
(sleep 3; open "http://localhost:4321/birdsong-app/") &
npx astro dev --port 4321
