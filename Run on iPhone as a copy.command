#!/bin/zsh -l
# Double-click in Finder: installs this build as a separate app beside the
# usual Birdsong, named "Birdsong HH:MM", with its own empty data, so older
# builds and their recordings stay as they are. Each copy is a new app ID:
# a free Apple account allows 3 apps from this Mac on the phone at once and
# 10 new IDs a week, so delete old copies from the phone when done.
cd "$(dirname "$0")"
export BIRDSONG_COPY=$(date +%m%d%H%M)
exec ./"Run on iPhone.command"
