#!/bin/zsh -l
# Double-click in Finder with the iPhone plugged in and unlocked. Copies the
# listening sessions recorded on the iPhone (detections, recordings, the GPS
# trail) into Birdsong on this Mac, for testing the plate and the map with
# real walks. Output is saved to copy-log.txt.
#
# The iPhone is only read, never changed. The Mac's own sessions are moved
# aside (sessions-mac-<date>, beside them), not mixed in: each device numbers
# its sessions and detections from 1, so mixing the two would give two birds
# the same number and the wrong recording on a card. To go back, quit
# Birdsong, delete "sessions" and rename the folder you want back to it.
cd "$(dirname "$0")"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  BUNDLE=uk.co.edstone.birdsongApp
  DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c "
import json,sys
ds=[d for d in json.load(sys.stdin) if d.get('targetPlatform','').startswith('ios') and not d.get('emulator')]
print(ds[0]['id'] if ds else '')")
  # Where the Mac app keeps its data: sandboxed, in its container.
  MAC=""
  for d in "$HOME/Library/Containers/$BUNDLE/Data/Library/Application Support/$BUNDLE" \
           "$HOME/Library/Application Support/$BUNDLE"; do
    if [ -d "$d" ]; then MAC="$d"; break; fi
  done
  if [ -z "$DEVICE" ]; then
    echo "STATUS: no-iphone  (plug it in, unlock it, trust this Mac, turn on Developer Mode)"
  elif [ -z "$MAC" ]; then
    echo "STATUS: no-mac-app  (run Build on Mac.command once first, so the Mac app has its folder)"
  else
    echo "Using device $DEVICE"
    echo "Mac data: $MAC"
    STAMP=$(date +%Y%m%d-%H%M%S)
    TMP=$(mktemp -d)
    if xcrun devicectl device copy from --device "$DEVICE" \
         --domain-type appDataContainer --domain-identifier "$BUNDLE" \
         --source "Library/Application Support/sessions" --destination "$TMP/sessions"; then
      COUNT=$(find "$TMP/sessions" -name session.json | wc -l | tr -d ' ')
      echo "Copied $COUNT sessions from the iPhone"
      if [ "$COUNT" = "0" ]; then
        echo "STATUS: copy-empty  (nothing came across; the iPhone's sessions are left as they are)"
      else
        # Birdsong writes to its sessions while it runs: close it first.
        osascript -e "tell application id \"$BUNDLE\" to quit" >/dev/null 2>&1
        sleep 2
        if [ -d "$MAC/sessions" ]; then
          mv "$MAC/sessions" "$MAC/sessions-mac-$STAMP" && echo "The Mac's own sessions are kept in sessions-mac-$STAMP"
        fi
        mv "$TMP/sessions" "$MAC/sessions" && echo "STATUS: copy-ok ($COUNT sessions from the iPhone)"
      fi
    else
      echo "STATUS: copy-failed  (devicectl could not read the app's data; in Xcode, Window > Devices and Simulators,"
      echo "        pick the iPhone, then Birdsong under Installed Apps, the ... menu, Download Container, and copy"
      echo "        AppData/Library/Application Support/sessions from it into: $MAC)"
    fi
    rm -rf "$TMP"
  fi
  echo "=== done $(date)"
} 2>&1 | tee copy-log.txt
echo
echo "Log saved to copy-log.txt. Open Birdsong on the Mac to see the iPhone's sessions. You can close this window."
