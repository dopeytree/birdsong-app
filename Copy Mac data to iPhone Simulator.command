#!/bin/zsh
# Copy the Mac app's walks, stations and settings into Birdsong on the
# iPhone Simulator (run "Run on iPhone Simulator.command" once first).
# The Mac's data is only read. The simulator's own data is moved aside
# into sim-before-<time>, not deleted. Writes copy-sim-log.txt.
cd "$(dirname "$0")"
LOG="copy-sim-log.txt"
{
  echo "=== $(date)"
  BUNDLE=uk.co.edstone.birdsongApp
  MAC="$HOME/Library/Containers/$BUNDLE/Data/Library/Application Support/$BUNDLE"
  UDIDS=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json,sys
for l in json.load(sys.stdin)['devices'].values():
  for d in l:
    if d['state']=='Booted': print(d['udid']+'|'+d['name'])")
  STAMP=$(date +%Y%m%d-%H%M%S)

  if [ ! -d "$MAC" ]; then
    echo "STATUS: no-mac-data  (run Build on Mac.command once first)"
  elif [ -z "$UDIDS" ]; then
    echo "STATUS: no-simulator-running  (run Run on iPhone Simulator.command first)"
  else
    echo "From: $MAC"
    # Every simulator that is running and has Birdsong installed.
    for S in ${(f)UDIDS}; do
      UDID=${S%%|*}
      SIMAPP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)
      if [ -z "$SIMAPP" ]; then
        echo "STATUS: not-installed on ${S#*|}  (run Run on iPhone Simulator.command first)"
        continue
      fi
      SIM="$SIMAPP/Library/Application Support"
      echo "To ${S#*|}: $SIM"
      xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
      sleep 1
      OLD="$SIM/sim-before-$STAMP"
      mkdir -p "$SIM" "$OLD"
      # Walks, detections, stations, settings and the map's tile cache.
      # The bird models are left out: the simulator app has its own.
      for item in sessions detections stations settings.json flutter_map_vector_tiles; do
        if [ -e "$MAC/$item" ]; then
          [ -e "$SIM/$item" ] && mv "$SIM/$item" "$OLD/"
          cp -R "$MAC/$item" "$SIM/$item" && echo "copied $item"
        fi
      done
      COUNT=$(find "$SIM/sessions" -name session.json 2>/dev/null | wc -l | tr -d ' ')
      echo "STATUS: copy-ok on ${S#*|} ($COUNT walks; its old data is in sim-before-$STAMP)"
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null && echo "STATUS: launched on ${S#*|}"
    done
  fi
  echo "=== done $(date)"
} 2>&1 | tee "$LOG"
echo
echo "Log saved to $(pwd)/$LOG. You can close this window."
